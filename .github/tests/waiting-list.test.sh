#!/bin/bash
# Does the daily list say what is waiting, once, and stay quiet otherwise (#265)?
#
# Usage: bash .github/tests/waiting-list.test.sh
#
# Stubbed `gh`, for `opencode-worker.test.sh`'s reason: the interesting parts are
# the ones a green run cannot show — that a held column is excluded, that two
# issues linked by a dependency appear as one entry rather than two, and that a
# day with nothing waiting produces a body saying so and no arrival.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/waiting-list.sh"
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  # **One fixture per label**, because the script asks once per label — two
  # `label:` qualifiers are an AND in GitHub's search syntax and would return
  # nothing. A single fixture here would hide exactly that.
  "search issues")
    if [ -s "$GH_FIXTURES/search_fails" ]; then
      echo "HTTP 503" >&2
      exit 1
    fi
    label=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --label) label=$2; shift 2 ;;
        *)       shift ;;
      esac
    done
    cat "$GH_FIXTURES/search_${label//:/_}" 2>/dev/null || echo '[]' ;;
  # **The board arrives as GraphQL now** (`#271`): `waiting-list.sh` asks
  # `opencode-worker.sh board-read` rather than `gh project item-list`, so this
  # is where a board fixture is served from.
  #
  # The fixtures stay in `item-list` shape. That is deliberate and it is the
  # same argument `board_read` itself makes: the shape is what every assertion
  # below was written against, and re-shaping thirty fixtures to prove a change
  # of transport would be re-testing `jq`. They are wrapped back into the
  # document `board_read` parses, here, once.
  "api graphql")
    if [ -s "$GH_FIXTURES/board_fails" ]; then
      echo "HTTP 502" >&2
      exit 1
    fi
    jq '{data:{organization:{projectV2:{items:{
          pageInfo:{hasNextPage:false,endCursor:null},
          nodes:[ .items[]
            | {id:.id,
               updatedAt:(.updatedAt // null),
               fieldValueByName:{name:.status},
               content:{number:.content.number,
                        title:(.content.title // "untitled"),
                        url:(.content.url // ""),
                        state:(.content.state // "OPEN"),
                        closedAt:(.content.closedAt // null),
                        repository:{nameWithOwner:.content.repository, url:""},
                        labels:{nodes:[ (.labels // [])[] | {name:.} ]}}} ]}}}}}' \
      "$GH_FIXTURES/board" 2>/dev/null ;;
  "api "*)
    case "$2" in
      */dependencies/blocked_by)
        key=${2#repos/}
        key=${key%/dependencies/blocked_by}
        fixture="$GH_FIXTURES/blocked_${key//\//_}"
        [ -f "$fixture" ] || exit 0
        expression=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --jq) expression=$2; shift 2 ;;
            *)    shift ;;
          esac
        done
        if [ -n "$expression" ]; then jq -r "$expression" "$fixture"; else cat "$fixture"; fi ;;
      *) ;;
    esac ;;
  *) ;;
esac
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

case_setup() {
  GH_FIXTURES="$WORK/fixtures"
  GH_LOG="$WORK/gh.log"
  export GH_FIXTURES GH_LOG
  rm -rf "$GH_FIXTURES"
  mkdir -p "$GH_FIXTURES"
  : > "$GH_LOG"
}

check() {
  local what=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then
    echo "  ok   $what"
  else
    echo "  FAIL $what"
    echo "         expected: $expected"
    echo "         actual:   $actual"
    FAILURES+=("$what")
  fi
}

contains() {
  local what=$1 needle=$2 haystack=$3
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  ok   $what"
  else
    echo "  FAIL $what"
    echo "         wanted to find: $needle"
    echo "         in:             $haystack"
    FAILURES+=("$what")
  fi
}

absent() {
  local what=$1 needle=$2 haystack=$3
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  ok   $what"
  else
    echo "  FAIL $what"
    echo "         did not want to find: $needle"
    FAILURES+=("$what")
  fi
}

# $1 is the label, the rest are `number|createdAt|labels(comma)|owner/repo|title`.
searched() {
  local label=$1; shift
  local rows=()
  for row in "$@"; do
    IFS='|' read -r number created labels repo title <<<"$row"
    local names=()
    IFS=',' read -ra parts <<<"$labels"
    for name in "${parts[@]}"; do names+=("{\"name\":\"$name\"}"); done
    local joinedLabels
    joinedLabels=$(IFS=,; echo "${names[*]}")
    rows+=("{\"number\":$number,\"title\":\"$title\",\"createdAt\":\"$created\",\"labels\":[$joinedLabels],\"repository\":{\"nameWithOwner\":\"$repo\"}}")
  done
  local joined
  joined=$(IFS=,; echo "${rows[*]}")
  echo "[$joined]" > "$GH_FIXTURES/search_${label//:/_}"
}

# $1.. are `number:Status:owner/repo`, each with three optional suffixes:
# `@hours` for how long ago the *card* last moved, and `+label,label` for the
# labels on the issue. Both are marked rather than positional, because a
# timestamp and a label list each contain colons of their own.
#
# `@0` is the default, so every row written before `#381` reads as a card that
# moved just now — which is what those cases meant when they said nothing.
boarded() {
  local items=()
  for row in "$@"; do
    local labels="" carded_hours=0 carded joinedLabels
    case "$row" in *+*) labels=${row#*+}; row=${row%%+*} ;; esac
    case "$row" in *@*) carded_hours=${row#*@}; row=${row%@*} ;; esac
    IFS=':' read -r number status repo <<<"$row"
    local names=()
    if [ -n "$labels" ]; then
      local parts; IFS=',' read -ra parts <<<"$labels"
      local name; for name in "${parts[@]}"; do names+=("\"$name\""); done
    fi
    joinedLabels=$(IFS=,; echo "${names[*]}")
    carded=$(date -u -d "$carded_hours hours ago" +%Y-%m-%dT%H:%M:%SZ)
    items+=("{\"id\":\"ITEM_${number}\",\"updatedAt\":\"$carded\",\"status\":\"${status}\",\"labels\":[$joinedLabels],\"content\":{\"number\":${number},\"repository\":\"$repo\"}}")
  done
  local joined
  joined=$(IFS=,; echo "${items[*]}")
  echo "{\"items\":[$joined]}" > "$GH_FIXTURES/board"
}

# $1 is `owner/repo|number`, the rest are `owner/repo|number|state`.
blocked_by() {
  local target=$1; shift
  IFS='|' read -r repo number <<<"$target"
  local rows=()
  for row in "$@"; do
    IFS='|' read -r brepo bnumber bstate <<<"$row"
    rows+=("{\"number\":$bnumber,\"state\":\"$bstate\",\"repository_url\":\"https://api.github.com/repos/$brepo\"}")
  done
  local joined
  joined=$(IFS=,; echo "${rows[*]}")
  echo "[$joined]" > "$GH_FIXTURES/blocked_${repo//\//_}_issues_$number"
}

echo "what is waiting"

case_setup
searched agent:claude "10|2026-08-01T00:00:00Z|agent:claude,p1|Kolonie-AI/kolonie-docs|A thing"
searched agent:human "11|2026-08-02T00:00:00Z|agent:human,p1,blocked:human|Kolonie-AI/kolonie-docs|A decision"
boarded "10:Ready:Kolonie-AI/kolonie-docs" "11:Blocked:Kolonie-AI/kolonie-docs"
entries=$(bash "$SCRIPT" entries 2>/dev/null)
contains "an issue routed to a Claude agent is on the list" "kolonie-docs	10	agent:claude" "$entries"
contains "and so is one routed to a person" "kolonie-docs	11	agent:human" "$entries"
check "and both of them, once each" "2" "$(wc -l <<<"$entries")"

# The point of asking per label: two `label:` qualifiers are an AND, so a single
# search would have returned nothing and the list would have been silently empty.
contains "the labels are searched one at a time" "--label agent:claude" "$(cat "$GH_LOG")"
contains "and the other one too" "--label agent:human" "$(cat "$GH_LOG")"

# A column that means somebody already has it is not waiting for anybody.
case_setup
searched agent:claude \
  "10|2026-08-01T00:00:00Z|agent:claude,p1|Kolonie-AI/kolonie-docs|Being worked" \
  "12|2026-08-01T00:00:00Z|agent:claude,p1|Kolonie-AI/kolonie-docs|Waiting"
boarded "10:In Progress:Kolonie-AI/kolonie-docs" "12:Ready:Kolonie-AI/kolonie-docs"
entries=$(bash "$SCRIPT" entries 2>/dev/null)
absent "an issue somebody is already working is not waiting" "	10	" "$entries"
contains "and the one nobody has is" "	12	" "$entries"

# `p1` before `p2`, then oldest — the same order the queue uses, because a list
# somebody reads top to bottom should agree with it.
case_setup
searched agent:claude \
  "10|2026-08-05T00:00:00Z|agent:claude,p2|Kolonie-AI/kolonie-docs|Later" \
  "12|2026-08-06T00:00:00Z|agent:claude,p1|Kolonie-AI/kolonie-docs|First"
boarded "10:Ready:Kolonie-AI/kolonie-docs" "12:Ready:Kolonie-AI/kolonie-docs"
check "p1 sorts above p2" "12" \
  "$(bash "$SCRIPT" entries 2>/dev/null | head -1 | cut -f2)"

# The reason it is not `agent:opencode`, in one clause, off the labels — which is
# all there is to read until triage records why it decided.
case_setup
searched agent:claude "10|2026-08-01T00:00:00Z|agent:claude,p1,opencode:forbidden|Kolonie-AI/kolonie-docs|Forbidden"
boarded "10:Ready:Kolonie-AI/kolonie-docs"
contains "an entry says why the worker cannot take it" "the worker may not write it" \
  "$(bash "$SCRIPT" entries 2>/dev/null)"

echo
echo "a package is one entry, not its parts"

# `#261` made a dependency a relation. A set of issues linked by one already is a
# package — this only has to notice, and the order it prints them in is the order
# they have to be worked in.
case_setup
searched agent:claude \
  "10|2026-08-01T00:00:00Z|agent:claude,p1|Kolonie-AI/kolonie-docs|The first half" \
  "12|2026-08-02T00:00:00Z|agent:claude,p1|Kolonie-AI/kolonie-docs|The second half" \
  "20|2026-08-03T00:00:00Z|agent:claude,p1|Kolonie-AI/kolonie-docs|Unrelated"
boarded "10:Ready:Kolonie-AI/kolonie-docs" "12:Ready:Kolonie-AI/kolonie-docs" \
        "20:Ready:Kolonie-AI/kolonie-docs"
blocked_by "Kolonie-AI/kolonie-docs|12" "Kolonie-AI/kolonie-docs|10|open"
bash "$SCRIPT" entries > "$WORK/entries" 2>/dev/null
body=$(bash "$SCRIPT" body "$WORK/entries")
contains "two linked issues are one entry" "A package of 2" "$body"
check "and there is exactly one package heading" "1" \
  "$(grep -c 'A package of' <<<"$body")"
contains "the blocker is named on the entry that waits" "waits for Kolonie-AI/kolonie-docs#10" "$body"
contains "and the unrelated issue keeps its own entry" "### Unrelated" "$body"

# A blocker nobody has routed to an agent is somebody else's work: it is named,
# and it does not drag that issue into this list's package.
case_setup
searched agent:claude "12|2026-08-02T00:00:00Z|agent:claude,p1|Kolonie-AI/kolonie-docs|Waits on the worker"
boarded "12:Ready:Kolonie-AI/kolonie-docs"
blocked_by "Kolonie-AI/kolonie-docs|12" "Kolonie-AI/kolonie-platform|700|open"
bash "$SCRIPT" entries > "$WORK/entries" 2>/dev/null
body=$(bash "$SCRIPT" body "$WORK/entries")
absent "a blocker outside the list is not a package" "A package of" "$body"
contains "but it is still named" "waits for Kolonie-AI/kolonie-platform#700" "$body"

echo
echo "a day with nothing waiting"

case_setup
boarded "10:Ready:Kolonie-AI/kolonie-docs"
: > "$WORK/entries"
body=$(bash "$SCRIPT" body "$WORK/entries")
contains "the body says so in as many words" "Nothing is waiting" "$body"
absent "and claims no count" "issue(s) are waiting" "$body"

case_setup
: > "$WORK/entries"
check "and nothing has arrived, so nothing is announced" "" \
  "$(bash "$SCRIPT" arrivals /dev/null "$WORK/entries" 2>/dev/null)"

echo
echo "only a change is announced"

case_setup
printf 'Kolonie-AI/kolonie-docs\t10\tagent:claude\t0\t2026-08-01T00:00:00Z\t\twhy\tA thing\n' > "$WORK/entries"
printf 'Kolonie-AI/kolonie-docs\t10\tagent:claude\t0\t2026-08-01T00:00:00Z\t\twhy\tA thing\nKolonie-AI/kolonie-docs\t12\tagent:claude\t0\t2026-08-02T00:00:00Z\t\twhy\tAnother\n' > "$WORK/entries.next"
bash "$SCRIPT" body "$WORK/entries" > "$WORK/body"
check "an unchanged list announces nothing" "" \
  "$(bash "$SCRIPT" arrivals "$WORK/body" "$WORK/entries" 2>/dev/null)"
check "and a new issue is the only thing announced" "Kolonie-AI/kolonie-docs#12" \
  "$(bash "$SCRIPT" arrivals "$WORK/body" "$WORK/entries.next" 2>/dev/null)"

# The first run has no previous body at all, and everything on the list is new.
case_setup
printf 'Kolonie-AI/kolonie-docs\t10\tagent:claude\t0\t2026-08-01T00:00:00Z\t\twhy\tA thing\n' > "$WORK/entries"
check "the first run announces the whole list" "Kolonie-AI/kolonie-docs#10" \
  "$(bash "$SCRIPT" arrivals "$WORK/nothing-here" "$WORK/entries" 2>/dev/null)"

echo
echo "a claim nobody is behind (#381)"

# The worker has been saying this on the issue every four hours to nobody. The
# list is the one page the person who can move the card actually reads.
case_setup
searched agent:claude "12|2026-08-01T00:00:00Z|agent:claude,p1|Kolonie-AI/kolonie-docs|Waiting"
boarded "12:Ready:Kolonie-AI/kolonie-docs" \
  "10:In Progress:Kolonie-AI/kolonie-docs@48" \
  "20:Ready:Kolonie-AI/kolonie-docs@1+agent:opencode"
entries=$(bash "$SCRIPT" entries 2>/dev/null)
contains "a card that has sat for two days is on the list" \
  "Kolonie-AI/kolonie-docs	10	stuck:in-progress" "$entries"
contains "and it says how long it has been there" "In Progress for 48 hours" "$entries"
contains "and what the claim is costing" "1 issue in that repository is queued behind it" "$entries"

# Two kinds of row in one file, and the headline counts one of them. Folding
# them together would make the single number on this list mean two things.
printf '%s\n' "$entries" > "$WORK/entries"
body=$(bash "$SCRIPT" body "$WORK/entries" 2>/dev/null)
contains "the headline counts only what is waiting to be started" "**1 issue(s) are waiting" "$body"
contains "and the stuck card gets a section of its own" "## 1 claim(s) nobody is behind" "$body"
contains "which names it" "[\`Kolonie-AI/kolonie-docs#10\`]" "$body"
contains "and says what moving it would start" "\`pick\` skips every other issue" "$body"

# A card that moved this morning is somebody working, not somebody forgetting.
case_setup
searched agent:claude "12|2026-08-01T00:00:00Z|agent:claude,p1|Kolonie-AI/kolonie-docs|Waiting"
boarded "12:Ready:Kolonie-AI/kolonie-docs" "10:In Progress:Kolonie-AI/kolonie-docs@2"
entries=$(bash "$SCRIPT" entries 2>/dev/null)
absent "a claim from two hours ago is not stuck" "stuck:in-progress" "$entries"

# **A day with nothing labelled still has to say this.** The stuck rows are
# found on the path where the search came back empty, or the one finding this
# workflow can make that nobody else makes would be reachable only by accident.
case_setup
boarded "10:In Progress:Kolonie-AI/kolonie-docs@30"
entries=$(bash "$SCRIPT" entries 2>/dev/null)
contains "a stuck card is found on a day with nothing labelled" \
  "Kolonie-AI/kolonie-docs	10	stuck:in-progress" "$entries"
absent "and no issue was read to find it, because this step holds a Projects-only token" \
  "api repos/" "$(cat "$GH_LOG")"

printf '%s\n' "$entries" > "$WORK/entries"
bash "$SCRIPT" body "$WORK/entries" > "$WORK/body" 2>/dev/null
body=$(cat "$WORK/body")
contains "the body still says nothing is waiting to be started" "Nothing is waiting" "$body"
contains "and still carries the stuck card" "## 1 claim(s) nobody is behind" "$body"

# It is announced once, on the day it becomes stuck, and then not again.
check "a newly stuck card is announced" "Kolonie-AI/kolonie-docs#10" \
  "$(bash "$SCRIPT" arrivals "$WORK/nothing-here" "$WORK/entries" 2>/dev/null)"
check "and not again the next day" "" \
  "$(bash "$SCRIPT" arrivals "$WORK/body" "$WORK/entries" 2>/dev/null)"

echo
echo "a read that fails is not an empty list"

# The failure this issue exists to prevent is a routed issue nobody hears about.
# A list that is empty because a query died looks exactly like a quiet day, so
# neither may exit 0 with nothing.
case_setup
echo yes > "$GH_FIXTURES/search_fails"
out=$(bash "$SCRIPT" entries 2>"$WORK/err"); rc=$?
check "a search that fails takes the list with it" "1" "$rc"
check "and prints nothing" "" "$out"
contains "and says the list would be wrong" "the list would be wrong" "$(cat "$WORK/err")"

case_setup
searched agent:claude "10|2026-08-01T00:00:00Z|agent:claude,p1|Kolonie-AI/kolonie-docs|A thing"
echo yes > "$GH_FIXTURES/board_fails"
out=$(bash "$SCRIPT" entries 2>"$WORK/err"); rc=$?
check "a board that cannot be read is not a list of everything" "1" "$rc"
contains "and says no column can be trusted" "no column can be trusted" "$(cat "$WORK/err")"

echo
if [ "${#FAILURES[@]}" -gt 0 ]; then
  echo "${#FAILURES[@]} failed:"
  for failure in "${FAILURES[@]}"; do echo "  - $failure"; done
  exit 1
fi
echo "all good"

#!/bin/bash
# Does the triage pass decide only what it is allowed to decide? (`#262`)
#
# Usage: bash .github/tests/board-triage.test.sh
#
# The model's judgement is not under test here and cannot be — what is under test
# is every place `board-triage.sh` overrules it. Each case hands `apply` a
# decisions file of the shape the model produces, including the shapes a wrong or
# malicious answer would have, and asserts what reached GitHub.
#
# **Stubbed `gh`, and the log is the assertion.** Every invocation is appended to
# `$GH_LOG`, so *no label was written* is checkable rather than inferred — an
# `issue edit --add-label` would appear there whatever path produced it.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/board-triage.sh"
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/bash
# The credential each call was made with, so that a step wired to the wrong token
# is a failing assertion rather than a 403 in production (`#270`).
#
# **Short values only.** The cases that care set `GH_TOKEN=issues` or `=board`;
# anything longer is whatever the machine running the tests happens to hold, and a
# real token belongs in no log — including a temporary one.
if [ "${#GH_TOKEN}" -le 12 ]; then as=${GH_TOKEN:-none}; else as=ambient; fi
echo "as=$as $*" >> "$GH_LOG"
case "$1 $2" in
  "search issues") cat "$GH_FIXTURES/issues" 2>/dev/null ;;
  # `#264` reads the failed issues' threads, lists the collecting issue rather than
  # searching for it, and opens it when there is none.
  # Both are read through `--jq`, and the filter is the behaviour: `proposal_issue`
  # picks the collecting issue out of the repository's issues by title, and
  # `proposed_keys` reads the comment bodies. A fixture of pre-filtered output would
  # assert nothing about either.
  "issue view"|"issue list")
    case "$1 $2" in
      "issue view") fixture="$GH_FIXTURES/comments" ;;
      *)            fixture="$GH_FIXTURES/issue_list" ;;
    esac
    [ -f "$fixture" ] || exit 0
    expression=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --jq) expression=$2; shift 2 ;;
        *)    shift ;;
      esac
    done
    if [ -n "$expression" ]; then jq -r "$expression" "$fixture"; else cat "$fixture"; fi ;;
  "issue create") cat "$GH_FIXTURES/created" 2>/dev/null ;;
  # The board, translated out of the `gh project item-list` shape the fixtures are
  # written in — the same translation `opencode-worker.test.sh` does, because
  # `board-triage.sh` reads the board through that script rather than with a
  # second copy of the query.
  "api graphql")
    query=""; owner=""; name=""; number=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -f|-F)
          case "$2" in
            query=*)  query=${2#query=} ;;
            owner=*)  owner=${2#owner=} ;;
            name=*)   name=${2#name=} ;;
            number=*) number=${2#number=} ;;
          esac
          shift 2 ;;
        *) shift ;;
      esac
    done
    [ -s "$GH_FIXTURES/board" ] || { echo "GraphQL: no board" >&2; exit 1; }
    case "$query" in
      *projectItems*)
        jq -c --arg repo "$owner/$name" --argjson n "${number:-0}" '
          { data: { repository: { issue: { projectItems: { nodes:
            [ .items[]
              | select(.content.repository == $repo and .content.number == $n)
              | { id: .id, isArchived: false,
                  project: { id: "PVT_kwDOEmwuYs4BebbB" },
                  fieldValueByName: { name: .status } } ] } } } } }
        ' "$GH_FIXTURES/board" ;;
      *)
        jq -c '
          { data: { organization: { projectV2: { items: {
            pageInfo: { hasNextPage: false, endCursor: null },
            nodes: [ .items[]
              | { id: .id,
                  fieldValueByName: { name: .status },
                  content: { number: .content.number,
                             title: .content.title,
                             url: ("https://github.com/\(.content.repository)/issues/\(.content.number)"),
                             repository: { nameWithOwner: .content.repository,
                                           url: ("https://github.com/\(.content.repository)") },
                             labels: { nodes: [ (.labels // [])[] | { name: . } ] } } } ] } } } } }
        ' "$GH_FIXTURES/board" ;;
    esac ;;
  "project item-edit")
    item=""; option=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --id) item=$2; shift 2 ;;
        --single-select-option-id) option=$2; shift 2 ;;
        *) shift ;;
      esac
    done
    case "$option" in
      ee5ea42c) status="Ready" ;;
      b14e3c08) status="Inbox" ;;
      *)        status="" ;;
    esac
    if [ -n "$item" ] && [ -n "$status" ]; then
      jq --arg id "$item" --arg s "$status" \
        '.items = [.items[] | if .id == $id then .status = $s else . end]' \
        "$GH_FIXTURES/board" > "$GH_FIXTURES/board.next" &&
        mv "$GH_FIXTURES/board.next" "$GH_FIXTURES/board"
    fi ;;
  # `gh api` is called two ways: `gh api <path>` and `gh api --method POST <path>`,
  # so `$2` is the path only half the time. The path and the method are extracted
  # before anything dispatches on them — a stub that read `$2` matched every POST
  # against its catch-all and answered success to writes it was meant to refuse.
  "api"*)
    path=""; method="GET"; expression=""; next=""
    shift   # the literal `api`
    for arg in "$@"; do
      case "$arg" in
        --method) next=method ;;
        --jq)     next=jq ;;
        -*)       next="" ;;
        *)
          case "$next" in
            method) method=$arg ;;
            jq)     expression=$arg ;;
            *)      [ -n "$path" ] || path=$arg ;;
          esac
          next="" ;;
      esac
    done
    case "$path" in
      # Membership: 204 for a member, 404 for anybody else. `--silent` is what
      # the script passes and the exit status is the whole answer.
      orgs/*/members/*)
        login=${path##*/}
        grep -qxF "$login" "$GH_FIXTURES/members" 2>/dev/null || { echo "HTTP 404" >&2; exit 1; } ;;
      */dependencies/blocked_by)
        key=${path#repos/}; key=${key%/dependencies/blocked_by}
        fixture="$GH_FIXTURES/blocked_${key//\//_}"
        if [ "$method" = "POST" ]; then
          # **422 is what GitHub answers for a relation that is already there**, and
          # for one that would close a cycle. `link_exists` is the case where this
          # dependency has been recorded on an earlier pass, which is the ordinary
          # state of a blocked issue and the one that must produce no comment.
          [ -s "$GH_FIXTURES/link_exists" ] && { echo "HTTP 422: already exists" >&2; exit 1; }
          [ -s "$GH_FIXTURES/link_fails" ] && { echo "HTTP 500" >&2; exit 1; }
          exit 0
        fi
        [ -f "$fixture" ] || exit 0
        if [ -n "$expression" ]; then jq -r "$expression" "$fixture"; else cat "$fixture"; fi ;;
      # One issue, read for its id and its state before a dependency is written.
      # `--jq` is applied here because the script's filter is what turns the
      # answer into the two words it uses.
      */issues/*)
        key=${path#repos/}
        fixture="$GH_FIXTURES/issue_${key//\//_}"
        [ -f "$fixture" ] || { echo "HTTP 404" >&2; exit 1; }
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
  printf '%s\n' "colleague" "runner" > "$GH_FIXTURES/members"
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

# One issue in the search answer. Labels and author are what the guards turn on.
issue() {
  local number=$1 title=$2 labels=$3 author=${4:-colleague} body=${5:-a body}
  jq -cn --argjson n "$number" --arg t "$title" --arg l "$labels" \
    --arg a "$author" --arg b "$body" '
    { repository: { nameWithOwner: "Kolonie-AI/kolonie-docs" },
      number: $n, title: $t, body: $b,
      labels: [ $l | split(" ") | .[] | select(length > 0) | { name: . } ],
      author: { login: $a, type: (if ($a | test("\\[bot\\]$")) then "Bot" else "User" end) },
      createdAt: "2026-08-10T09:00:00Z",
      url: "https://github.com/Kolonie-AI/kolonie-docs/issues/\($n)" }'
}

boarded() {
  local rows=""
  local row
  for row in "$@"; do
    IFS='|' read -r number status labels <<<"$row"
    rows+=$(jq -cn --argjson n "$number" --arg s "$status" --arg l "$labels" '
      { id: "PVTI_item\($n)", status: $s,
        labels: [ $l | split(" ") | .[] | select(length > 0) ],
        content: { number: $n, repository: "Kolonie-AI/kolonie-docs" } }')$'\n'
  done
  jq -s '{items: .}' <<<"$rows" > "$GH_FIXTURES/board"
}

searched() {
  jq -s '.' <<<"$(printf '%s\n' "$@")" > "$GH_FIXTURES/issues"
}

# A decisions file of the shape `board-triage-decide.py` writes.
decided() {
  local number=$1 route=$2 priority=$3 readiness=$4 depends=$5 ready=$6
  jq -cn --argjson n "$number" --arg r "$route" --arg p "$priority" \
    --arg d "$readiness" --arg dep "$depends" --argjson ready "$ready" '
    { decisions: [ { repo: "Kolonie-AI/kolonie-docs", number: $n, route: $r,
                     priority: $p, readiness: $d,
                     depends_on: ($dep | split(" ") | map(select(length > 0))),
                     ready: $ready, reason: "because the table says so" } ] }' \
    > "$WORK/decisions.json"
  echo "$WORK/decisions.json"
}

run_apply() {
  bash "$SCRIPT" candidates > "$WORK/candidates.json" 2>/dev/null
  bash "$SCRIPT" apply "$WORK/candidates.json" "$1" 2>"$WORK/stderr"
}

echo
echo "what a pass may look at"

case_setup
searched "$(issue 900 'in inbox' '')" \
  "$(issue 901 'in ready' 'agent:claude p1')" \
  "$(issue 902 'in progress' 'agent:claude')" \
  "$(issue 903 'not on the board' '')" \
  "$(issue 904 'What is waiting for an agent' '')" \
  "$(issue 905 'Proposed additions to the worker prohibitions' '')"
boarded "900|Inbox|" "901|Ready|agent:claude p1" "902|In Progress|agent:claude" "904|Inbox|" "905|Inbox|"
found=$(bash "$SCRIPT" candidates 2>/dev/null)

check "the issues in Inbox and Ready are the candidates" "900 901" \
  "$(jq -r '[.candidates[].number] | join(" ")' <<<"$found")"
check "and every open issue is in the index, so a dependency can be noticed" "6" \
  "$(jq '.index | length' <<<"$found")"
absent "an issue In Progress is not a candidate, whatever the model is asked" \
  '"number":902' "$(jq -c '.candidates' <<<"$found")"
absent "an issue that is not on the board is not a candidate either" \
  '"number":903' "$(jq -c '.candidates' <<<"$found")"
absent "and the generated waiting list is not work" \
  '"number":904' "$(jq -c '.candidates' <<<"$found")"
absent "nor is the pass's own collecting issue for proposed prohibitions" \
  '"number":905' "$(jq -c '.candidates' <<<"$found")"

echo
echo "the brief carries the rules rather than a copy of them"

case_setup
searched "$(issue 900 'in inbox' '')"
boarded "900|Inbox|"
bash "$SCRIPT" candidates > "$WORK/candidates.json" 2>/dev/null
brief=$(bash "$SCRIPT" brief "$WORK/candidates.json")
contains "the routing table is quoted from AGENTS.md" "agent:opencode" "$brief"
contains "and the prohibitions from the file that holds them" \
  "The paths no worker may write" "$brief"
contains "and the issue to decide about" "in inbox" "$brief"

echo
echo "an unsure route is agent:claude, and never the unattended worker (#262)"

case_setup
searched "$(issue 900 'something' '')"
boarded "900|Inbox|"
run_apply "$(decided 900 "agent:whatever" "" "" "" true)" >/dev/null
contains "a route that is not one of the three becomes agent:claude" \
  "--add-label agent:claude" "$(cat "$GH_LOG")"

case_setup
searched "$(issue 900 'a person must decide' 'blocked:human')"
boarded "900|Inbox|blocked:human"
run_apply "$(decided 900 "agent:opencode" "" "" "" true)" >/dev/null
log=$(cat "$GH_LOG")
contains "blocked:human is routed to a person however the model answered" \
  "--add-label agent:human" "$log"
absent "and never to the queue" "agent:opencode" "$log"
absent "and it is not moved to Ready" "single-select-option-id ee5ea42c" "$log"

case_setup
searched "$(issue 900 'refused structurally' 'opencode:forbidden agent:claude')"
boarded "900|Inbox|opencode:forbidden agent:claude"
run_apply "$(decided 900 "agent:opencode" "" "" "" true)" >/dev/null
absent "opencode:forbidden is never handed back to the worker" \
  "--add-label agent:opencode" "$(cat "$GH_LOG")"

case_setup
searched "$(issue 900 'already routed to a person' 'agent:human')"
boarded "900|Inbox|agent:human"
run_apply "$(decided 900 "agent:opencode" "" "" "" true)" >/dev/null
absent "a route is never widened by a later pass" \
  "--add-label agent:opencode" "$(cat "$GH_LOG")"

# The second live pass moved three issues from `agent:human` back to `agent:claude`.
# Two passes disagreeing about one issue would trade it back and forth with a
# comment every hour, so the route only ever tightens.
case_setup
searched "$(issue 900 'reserved for a person' 'agent:human')"
boarded "900|Ready|agent:human"
run_apply "$(decided 900 "agent:claude" "" "" "" true)" >/dev/null
log=$(cat "$GH_LOG")
absent "a route is not loosened either, so two passes cannot trade an issue" \
  "--add-label agent:claude" "$log"
absent "and nothing is removed" "--remove-label" "$log"

case_setup
searched "$(issue 900 'was in the queue' 'agent:opencode')"
boarded "900|Ready|agent:opencode"
run_apply "$(decided 900 "agent:human" "" "" "" true)" >/dev/null
contains "tightening is the direction that works" \
  "--add-label agent:human --remove-label agent:opencode" "$(cat "$GH_LOG")"

echo
echo "priority, and the one class it is not triage's to set"

case_setup
searched "$(issue 900 'ours' '')"
boarded "900|Inbox|"
run_apply "$(decided 900 "agent:claude" "p1" "" "" true)" >/dev/null
contains "an unprioritised issue of ours gets the priority" "--add-label p1" "$(cat "$GH_LOG")"

case_setup
searched "$(issue 900 'from a citizen' 'from:citizen')"
boarded "900|Inbox|from:citizen"
run_apply "$(decided 900 "agent:claude" "p1" "" "" true)" >/dev/null
log=$(cat "$GH_LOG")
absent "an issue that arrived from outside is not prioritised (AGENTS.md §5, class 6)" \
  "--add-label p1" "$log"
contains "and it is still routed" "--add-label agent:claude" "$log"

case_setup
searched "$(issue 900 'already decided' 'p2')"
boarded "900|Inbox|p2"
run_apply "$(decided 900 "agent:claude" "p1" "" "" true)" >/dev/null
absent "a priority somebody already set is not overruled" "--add-label p1" "$(cat "$GH_LOG")"

case_setup
searched "$(issue 900 'an outsider wrote this' '' "stranger")"
boarded "900|Inbox|"
run_apply "$(decided 900 "agent:claude" "p1" "" "" true)" >/dev/null
log=$(cat "$GH_LOG")
contains "from:external comes from organisation membership, not from the model" \
  "--add-label from:external" "$log"
absent "and an issue triage has just found to be external is not prioritised either" \
  "--add-label p1" "$log"

case_setup
searched "$(issue 900 'a colleague wrote this' '')"
boarded "900|Inbox|"
run_apply "$(decided 900 "agent:claude" "" "" "" true)" >/dev/null
absent "a member's issue is not labelled from:external" "from:external" "$(cat "$GH_LOG")"

# The expensive way to learn this: the first live pass labelled `kolonie-infra#119`
# — filed by one of the Colony's own watchers — `from:external`, because a bot is
# not a *member* of the organisation. That is the one direction this label must
# not be wrong in.
case_setup
searched "$(issue 900 'a watcher filed this' '' "github-actions[bot]")"
boarded "900|Inbox|"
run_apply "$(decided 900 "agent:claude" "" "" "" true)" >/dev/null
log=$(cat "$GH_LOG")
absent "a machine is never labelled from:external" "from:external" "$log"
absent "and its membership is not even asked about" "members/github-actions" "$log"
contains "and the run says whose job that provenance is" "kolonie-platform#686" "$(cat "$WORK/stderr")"

echo
echo "a dependency is recorded as the relation the queue reads (#261)"

case_setup
searched "$(issue 900 'waits for something' '')"
boarded "900|Inbox|"
cat > "$GH_FIXTURES/issue_Kolonie-AI_kolonie-docs_issues_800" <<'JSON'
{"id": 55500, "state": "open"}
JSON
# The blocker is reported by the second read, which is what `blockers` asks after
# the link has been written.
cat > "$GH_FIXTURES/blocked_Kolonie-AI_kolonie-docs_issues_900" <<'JSON'
[{"repository_url": "https://api.github.com/repos/Kolonie-AI/kolonie-docs", "number": 800, "state": "open"}]
JSON
run_apply "$(decided 900 "agent:opencode" "" "" "Kolonie-AI/kolonie-docs#800" true)" >/dev/null
log=$(cat "$GH_LOG")
contains "the blocker is linked" \
  "--method POST repos/Kolonie-AI/kolonie-docs/issues/900/dependencies/blocked_by" "$log"
absent "an issue with an open blocker is not moved to Ready" \
  "single-select-option-id ee5ea42c" "$log"
absent "and it does not reach the unattended queue" "--add-label agent:opencode" "$log"
contains "and the comment says what it waits for" "Left in Inbox" "$log"

case_setup
searched "$(issue 900 'waits for a closed one' '')"
boarded "900|Inbox|"
cat > "$GH_FIXTURES/issue_Kolonie-AI_kolonie-docs_issues_800" <<'JSON'
{"id": 55500, "state": "closed"}
JSON
run_apply "$(decided 900 "agent:claude" "" "" "Kolonie-AI/kolonie-docs#800" true)" >/dev/null
log=$(cat "$GH_LOG")
absent "a closed blocker is not recorded" "--method POST" "$log"
contains "and the issue is moved to Ready" "single-select-option-id ee5ea42c" "$log"

case_setup
searched "$(issue 900 'in the queue and blocked' 'agent:opencode p1')"
boarded "900|Ready|agent:opencode p1"
cat > "$GH_FIXTURES/issue_Kolonie-AI_kolonie-docs_issues_800" <<'JSON'
{"id": 55500, "state": "open"}
JSON
cat > "$GH_FIXTURES/blocked_Kolonie-AI_kolonie-docs_issues_900" <<'JSON'
[{"repository_url": "https://api.github.com/repos/Kolonie-AI/kolonie-docs", "number": 800, "state": "open"}]
JSON
run_apply "$(decided 900 "agent:opencode" "" "" "Kolonie-AI/kolonie-docs#800" true)" >/dev/null
log=$(cat "$GH_LOG")
contains "an issue already in Ready that turns out to be blocked leaves the queue" \
  "single-select-option-id b14e3c08" "$log"
contains "and the comment says it is out of it" "Out of the queue" "$log"

# Two passes judged `kolonie-platform#702` differently within an hour, so it went to
# Ready and then back to Inbox. A judgement keeps an issue out of the queue; only a
# fact takes it out.
case_setup
searched "$(issue 900 'in the queue, and one pass disagrees' 'agent:claude p1')"
boarded "900|Ready|agent:claude p1"
run_apply "$(decided 900 "agent:claude" "" "" "" false)" >/dev/null
log=$(cat "$GH_LOG")
absent "an opinion does not take a card out of Ready" "single-select-option-id b14e3c08" "$log"
absent "and says nothing, because nothing changed" "issue comment" "$log"

# Measured 2026-08-10: the pass linked three independent watcher findings — `api`,
# `postgres` and `traefik` each logging something unusual — into a chain, and took
# all three out of Ready. A watcher reports; it creates nothing another one needs.
case_setup
searched "$(issue 900 'api is logging errors' 'from:watcher agent:claude')" \
  "$(issue 800 'postgres is logging errors' 'from:watcher agent:claude')"
boarded "900|Ready|from:watcher agent:claude" "800|Ready|from:watcher agent:claude"
cat > "$GH_FIXTURES/issue_Kolonie-AI_kolonie-docs_issues_800" <<'JSON'
{"id": 55500, "state": "open"}
JSON
run_apply "$(decided 900 "agent:claude" "" "" "Kolonie-AI/kolonie-docs#800" true)" >/dev/null
log=$(cat "$GH_LOG")
absent "two watcher findings are not linked to each other" "--method POST" "$log"
contains "and the run says they are siblings" "siblings from one run" "$(cat "$WORK/stderr")"

echo
echo "what stays in Inbox"

case_setup
searched "$(issue 900 'too vague' '')"
boarded "900|Inbox|"
run_apply "$(decided 900 "agent:claude" "" "idea" "" false)" >/dev/null
log=$(cat "$GH_LOG")
contains "an issue that is not ready gets the readiness label" "--add-label idea" "$log"
absent "and is not moved" "single-select-option-id ee5ea42c" "$log"
contains "and the comment says why it stayed" "not specified well enough" "$log"

case_setup
searched "$(issue 900 'in progress really' 'agent:claude')"
boarded "900|In Progress|agent:claude"
run_apply "$(decided 900 "agent:opencode" "p1" "idea" "" true)" >/dev/null
log=$(cat "$GH_LOG")
absent "a decision about an issue in flight writes nothing at all" "issue edit" "$log"
absent "and comments nothing" "issue comment" "$log"
contains "and says it skipped it" "not one of this pass's candidates" "$(cat "$WORK/stderr")"

case_setup
searched "$(issue 900 'nothing to do here' 'agent:claude p1')"
boarded "900|Ready|agent:claude p1"
run_apply "$(decided 900 "agent:claude" "p1" "" "" true)" >/dev/null
log=$(cat "$GH_LOG")
absent "an issue already routed, prioritised and in Ready is left alone" "issue edit" "$log"
absent "and a triage that changed nothing says nothing (#262)" "issue comment" "$log"

# `#270`: the board is moved by an app that cannot label an issue, and the labels
# need a token that reaches five repositories. A pass wired the other way round
# fails with a 403 on whichever half is wrong, hours later.
case_setup
searched "$(issue 900 'two credentials' '')"
boarded "900|Inbox|"
GH_TOKEN=issues BOARD_TOKEN=board bash "$SCRIPT" candidates > "$WORK/candidates.json" 2>/dev/null
GH_TOKEN=issues BOARD_TOKEN=board bash "$SCRIPT" apply "$WORK/candidates.json" \
  "$(decided 900 "agent:claude" "" "" "" true)" >/dev/null 2>&1
log=$(cat "$GH_LOG")
contains "the card is moved as the board app" "as=board project item-edit" "$log"
contains "and the label is written as the repository token" "as=issues issue edit" "$log"

# Measured the expensive way: the first live pass put `agent:human` on nine issues
# that already carried `agent:claude` and left both on — so the pass enforcing
# *exactly one of the three* was the thing breaking it.
case_setup
searched "$(issue 900 'routed once already' 'agent:claude p2')"
boarded "900|Ready|agent:claude p2"
run_apply "$(decided 900 "agent:human" "" "" "" true)" >/dev/null
log=$(cat "$GH_LOG")
contains "a changed route removes the old one in the same call" \
  "--add-label agent:human --remove-label agent:claude" "$log"
contains "and the comment says what it replaced" "instead of" "$log"

# The other direction: a route that did not change removes nothing, because the
# only label this pass ever removes is a route it has just replaced.
case_setup
searched "$(issue 900 'unchanged' 'agent:claude')"
boarded "900|Inbox|agent:claude"
run_apply "$(decided 900 "agent:claude" "" "idea" "" false)" >/dev/null
log=$(cat "$GH_LOG")
contains "an unchanged route adds the readiness label" "--add-label idea" "$log"
absent "and removes nothing" "--remove-label" "$log"

case_setup
searched "$(issue 900 'would deadlock' '')"
boarded "900|Inbox|"
cat > "$GH_FIXTURES/issue_Kolonie-AI_kolonie-docs_issues_800" <<'JSON'
{"id": 55500, "state": "open"}
JSON
# 800 already waits for 900, so 900 waiting for 800 would leave both out of the
# queue for ever.
cat > "$GH_FIXTURES/blocked_Kolonie-AI_kolonie-docs_issues_800" <<'JSON'
[{"repository_url": "https://api.github.com/repos/Kolonie-AI/kolonie-docs", "number": 900, "state": "open"}]
JSON
run_apply "$(decided 900 "agent:claude" "" "" "Kolonie-AI/kolonie-docs#800" true)" >/dev/null
absent "a mutual dependency is refused rather than written" "--method POST" "$(cat "$GH_LOG")"
contains "and the run says it would deadlock both" "deadlock" "$(cat "$WORK/stderr")"

# The third live pass wrote eleven comments that said nothing but *left in Inbox, it
# waits for #693* — true, unchanged since the pass before, and on its way to being
# hourly. `#262`: silence otherwise, because a triage that comments on everything is
# a triage nobody reads.
case_setup
searched "$(issue 900 'blocked and already labelled' 'agent:claude p1 idea')"
boarded "900|Inbox|agent:claude p1 idea"
cat > "$GH_FIXTURES/issue_Kolonie-AI_kolonie-docs_issues_800" <<'JSON'
{"id": 55500, "state": "open"}
JSON
cat > "$GH_FIXTURES/blocked_Kolonie-AI_kolonie-docs_issues_900" <<'JSON'
[{"repository_url": "https://api.github.com/repos/Kolonie-AI/kolonie-docs", "number": 800, "state": "open"}]
JSON
: > "$GH_FIXTURES/link_exists"
printf 'x\n' > "$GH_FIXTURES/link_exists"
run_apply "$(decided 900 "agent:claude" "p1" "idea" "Kolonie-AI/kolonie-docs#800" false)" >/dev/null
log=$(cat "$GH_LOG")
absent "a reason for not moving something is not news twice" "issue comment" "$log"
absent "and nothing is written" "issue edit" "$log"

echo
echo "the answer the model did not give"

case_setup
searched "$(issue 900 'something' '')"
boarded "900|Inbox|"
printf '{"decisions": []}\n' > "$WORK/decisions.json"
out=$(run_apply "$WORK/decisions.json")
absent "an empty answer writes nothing" "issue edit" "$(cat "$GH_LOG")"
contains "and the run says the pass decided nothing" "decided nothing" "$(cat "$WORK/stderr")"

case_setup
searched "$(issue 900 'something' '')"
boarded "900|Inbox|"
printf '{"decisions": [{"repo": "Kolonie-AI/kolonie-docs", "number": 900}]}\n' > "$WORK/decisions.json"
run_apply "$WORK/decisions.json" >/dev/null
contains "a decision with no route at all still routes to agent:claude" \
  "--add-label agent:claude" "$(cat "$GH_LOG")"

echo
echo "a refusal that has appeared twice becomes a proposal, and nothing more (#264)"

# `propose` is handed what the model answered; the threshold, the deduplication and
# the refusal to edit the list are this script's, and they are what these cases are.
proposals() {
  printf '%s' "$1" > "$WORK/proposals.json"
  echo "$WORK/proposals.json"
}

collecting() {
  # The collecting issue exists, with the keys given here already proposed on it.
  printf '[{"number": 500, "title": "Proposed additions to the worker prohibitions"}]\n' \
    > "$GH_FIXTURES/issue_list"
  local body="" key
  for key in "$@"; do
    body+="{\"body\": \"already said <!-- prohibition-proposal: $key -->\"},"
  done
  printf '{"comments": [%s]}\n' "${body%,}" > "$GH_FIXTURES/comments"
}

case_setup
collecting
out=$(bash "$SCRIPT" propose "$(proposals '{"proposals":[{"key":"live-host-write","reason":"it writes to the live host","issues":["Kolonie-AI/kolonie-infra#103","Kolonie-AI/kolonie-infra#107"],"wording":"A write to the live host cannot be observed by a repository check."}]}')" 2>"$WORK/stderr")
log=$(cat "$GH_LOG")
contains "a reason on two issues is proposed" "issue comment 500" "$log"
contains "and the comment carries the key, so it is recognisable next time" \
  "prohibition-proposal: live-host-write" "$log"
contains "and the suggested wording" "cannot be observed by a repository check" "$log"
absent "and nothing edits the prohibitions file" "worker-prohibitions.md --" "$log"
check "and the run says what it published" "1 prohibition(s) proposed" "$(tail -1 <<<"$out")"

case_setup
collecting
bash "$SCRIPT" propose "$(proposals '{"proposals":[{"key":"one-off","reason":"a one-off","issues":["Kolonie-AI/kolonie-docs#900"],"wording":"Something."}]}')" >/dev/null 2>"$WORK/stderr"
absent "one refusal is not a rule: two, not three, and never one" "issue comment" "$(cat "$GH_LOG")"
contains "and it says why it said nothing" "threshold is 2" "$(cat "$WORK/stderr")"

case_setup
collecting "live-host-write"
bash "$SCRIPT" propose "$(proposals '{"proposals":[{"key":"live-host-write","reason":"again","issues":["Kolonie-AI/kolonie-infra#103","Kolonie-AI/kolonie-infra#107"],"wording":"Again."}]}')" >/dev/null 2>"$WORK/stderr"
absent "a proposal already waiting for a person is not made twice" "issue comment" "$(cat "$GH_LOG")"
contains "and it says it is waiting" "waiting for a person" "$(cat "$WORK/stderr")"

case_setup
# No collecting issue yet: it is opened on the first proposal and not before.
printf '[]\n' > "$GH_FIXTURES/issue_list"
printf '{"comments": []}\n' > "$GH_FIXTURES/comments"
printf 'https://github.com/Kolonie-AI/kolonie-docs/issues/501\n' > "$GH_FIXTURES/created"
bash "$SCRIPT" propose "$(proposals '{"proposals":[{"key":"a","reason":"r","issues":["x/y#1","x/y#2"],"wording":"W."},{"key":"b","reason":"r2","issues":["x/y#3","x/y#4"],"wording":"W2."}]}')" >/dev/null 2>&1
log=$(cat "$GH_LOG")
contains "the collecting issue is opened for a person, not for an agent" \
  "--label agent:human" "$log"
check "and it is opened once however many proposals a pass has" "1" \
  "$(grep -c "issue create" <<<"$log")"
check "the second proposal comments on the issue the first one opened" "2" \
  "$(grep -c "issue comment 501" <<<"$log")"

case_setup
printf '[]\n' > "$GH_FIXTURES/issue_list"
printf '{"comments": []}\n' > "$GH_FIXTURES/comments"
bash "$SCRIPT" propose "$(proposals '{"proposals":[]}')" >/dev/null 2>"$WORK/stderr"
absent "nothing proposed opens nothing" "issue create" "$(cat "$GH_LOG")"
contains "and says so" "no prohibition was proposed" "$(cat "$WORK/stderr")"

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "all good"
  exit 0
fi
echo "${#FAILURES[@]} failed:"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

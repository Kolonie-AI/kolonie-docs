#!/bin/bash
# Does the hourly worker pick the right issue, and keep its hands off the label?
#
# Usage: bash .github/tests/opencode-worker.test.sh
#
# `kolonie-docs#142` turns on properties that a green run cannot show: that the
# ordering is deterministic, that an issue in any column but Ready is not in the
# queue, that a board write which fails stops the run *before* work starts, and
# that nothing ever removes `agent:opencode`. Each is a branch that would look
# fine in review and be wrong in production.
#
# Stubbed `gh`, for `board-self-check.test.sh`'s reason: it is the only way to
# exercise a failing board write without breaking the board. The stub logs every
# invocation, so the label assertion is exhaustive rather than a reading of the
# script — any `issue edit --remove-label` would appear in the log whatever path
# produced it.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/opencode-worker.sh"
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export GITHUB_REPOSITORY="Kolonie-AI/kolonie-docs"
export RUN_URL="https://example.invalid/run/1"

mkdir -p "$WORK/bin"
# ## One stub, installed twice (`#266`)
#
# There were two copies of this and they had already drifted — the same cases in
# a different order, one of them missing a comment. A stub that two cases
# disagree about is a stub neither of them is really testing against, so it is
# written once here and `install_stub` puts it back where a case has replaced it.
cat > "$WORK/stub-gh" <<'STUB'
#!/bin/bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "search issues")     cat "$GH_FIXTURES/issues" 2>/dev/null ;;
  "issue list")        cat "$GH_FIXTURES/issues" 2>/dev/null ;;
  "run list")
    if [ -s "$GH_FIXTURES/run_list_fails" ]; then
      echo "HTTP 503: the API is having a moment" >&2
      exit 1
    fi
    cat "$GH_FIXTURES/runs" 2>/dev/null ;;
  # ## The board is read over GraphQL now (`#269`), and the fixture did not change
  #
  # `boarded` still writes what `gh project item-list --format json` returned,
  # because that is the shape the cases are written in and the shape
  # `board_read` still emits. This case translates it into the two API answers
  # the script now asks for, so the tests describe what the worker does with the
  # board rather than which call it made to get it.
  #
  # The board fixture is the whole board, so `hasNextPage` is false: pagination
  # is exercised against the live API in `#269`, not here, and a stub that
  # pretended to paginate would only be testing itself.
  "api graphql")
    query=""; owner=""; name=""; number=""; content=""; expression=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --jq) expression=$2; shift 2 ;;
        -f|-F)
          case "$2" in
            query=*)   query=${2#query=} ;;
            owner=*)   owner=${2#owner=} ;;
            name=*)    name=${2#name=} ;;
            number=*)  number=${2#number=} ;;
            content=*) content=${2#content=} ;;
          esac
          shift 2 ;;
        *) shift ;;
      esac
    done
    # `--jq` is `gh`'s own flag rather than a pipe the caller adds, so the stub
    # has to apply it: `board-add` reads both of its answers through one.
    emit() { if [ -n "$expression" ]; then jq -r "$expression"; else cat; fi; }

    # ## A call that fails writes to stdout (`#422`)
    #
    # This is the whole reproduction, and it has to be here rather than in the
    # script's own error path: `gh api graphql` prints its `errors` envelope on
    # **stdout** and exits non-zero. A stub that only exited non-zero would let a
    # guard reading emptiness pass, because there would be nothing to read — and
    # that guard passing on an error document is the bug `#422` is about.
    #
    # `--jq` is not applied, exactly as `gh` does not apply it to an error.
    if [ -s "$GH_FIXTURES/graphql_fails" ]; then
      jq -cn '{errors: [{message: "Something went wrong while executing your query."}]}'
      exit 1
    fi

    # The two calls `board-add` makes, answered before the board is read for
    # existence: the mutation is the write under test, and a case asserting about
    # it is not asserting anything about the board fixture.
    case "$query" in
      *addProjectV2ItemById*)
        jq -cn --arg id "PVTI_added_${content#I_}" \
          '{data: {addProjectV2ItemById: {item: {id: $id}}}}' | emit
        exit 0 ;;
      *"issue(number:\$number){id}"*)
        if grep -qxF -- "$name#$number" "$GH_FIXTURES/unreadable_issues" 2>/dev/null; then
          jq -cn '{data: {repository: {issue: null}}}' | emit
        else
          jq -cn --arg id "I_${name}${number}" '{data: {repository: {issue: {id: $id}}}}' | emit
        fi
        exit 0 ;;
    esac

    # **An empty fixture is an unreadable board, not an empty one** — an empty
    # board is `{"items":[]}` and the cases that mean that write it. `cat` of an
    # empty file used to produce this, caught downstream by `[ -s ]`; over
    # GraphQL the same thing is a call that fails, so it fails here. Answering
    # `[]` instead would erase the distinction `pick` exists to draw.
    if [ ! -s "$GH_FIXTURES/board" ]; then
      echo "GraphQL: API rate limit exceeded for user ID 1" >&2
      exit 1
    fi

    case "$query" in
      # One issue's card, asked from the issue's side. `isArchived` is false
      # because nothing in the fixture is archived; the live query filters on it
      # and the reason is in the script.
      *projectItems*)
        jq -c --arg repo "$owner/$name" --argjson n "${number:-0}" '
          { data: { repository: { issue: { projectItems: { nodes:
            [ .items[]
              | select(.content.repository == $repo and .content.number == $n)
              | { id: .id,
                  isArchived: false,
                  project: { id: "PVT_kwDOEmwuYs4BebbB" },
                  fieldValueByName: { name: .status } } ] } } } } }
        ' "$GH_FIXTURES/board"
        ;;
      *)
        jq -c '
          { data: { organization: { projectV2: { items: {
            pageInfo: { hasNextPage: false, endCursor: null },
            nodes: [ .items[]
              | { id: .id,
                  updatedAt: (.updatedAt // null),
                  fieldValueByName: { name: .status },
                  content: { number: .content.number,
                             title: .content.title,
                             state: (.content.state // "OPEN"),
                             closedAt: (.content.closedAt // null),
                             url: ("https://github.com/\(.content.repository)/issues/\(.content.number)"),
                             repository: { nameWithOwner: .content.repository,
                                           url: ("https://github.com/\(.content.repository)") },
                             labels: { nodes: [ (.labels // [])[] | { name: . } ] } } } ] } } } } }
        ' "$GH_FIXTURES/board"
        ;;
    esac
    ;;
  # **The board write moves the board** (`#266`). It used to do nothing at all,
  # which was enough while `claim` never read what it had written — and would
  # have made the read-back it now does either always pass or always fail,
  # depending on the fixture, rather than on the code. So the option id is
  # translated back into the column name and written into the board fixture,
  # and `edit_ignored` is the case where the API says yes and nothing moves.
  "project item-edit")
    if [ -s "$GH_FIXTURES/edit_fails" ]; then
      echo "HTTP 401: Bad credentials" >&2
      exit 1
    fi
    [ -s "$GH_FIXTURES/edit_ignored" ] && exit 0
    item="" option=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --id) item=$2; shift 2 ;;
        --single-select-option-id) option=$2; shift 2 ;;
        *) shift ;;
      esac
    done
    case "$option" in
      0ce10d81) status="Ready" ;;
      604be33b) status="In Progress" ;;
      bd543ca4) status="In Review" ;;
      9caff3d3) status="Blocked" ;;
      *)        status="" ;;
    esac
    if [ -n "$item" ] && [ -n "$status" ] && [ -s "$GH_FIXTURES/board" ]; then
      jq --arg id "$item" --arg status "$status" \
        '.items = [.items[] | if .id == $id then .status = $status else . end]' \
        "$GH_FIXTURES/board" > "$GH_FIXTURES/board.next" &&
        mv "$GH_FIXTURES/board.next" "$GH_FIXTURES/board"
    fi
    ;;
  # `#245` reads two things over REST: this run's steps, and the issue's own
  # comments. Both are `gh api`, so the stub dispatches on the path.
  "api "*)
    if [ -s "$GH_FIXTURES/api_fails" ]; then
      echo "HTTP 502" >&2
      exit 1
    fi
    # `#326` is the one caller that paginates, so its path is not in `$2`. Every
    # branch below dispatches on `$2`; dropping the flag here keeps that true
    # rather than teaching each branch about a flag only one of them uses.
    if [ "${2:-}" = "--paginate" ]; then
      set -- "$1" "${@:3}"
    fi
    case "$2" in
      */jobs)     cat "$GH_FIXTURES/jobs" 2>/dev/null ;;
      */comments) cat "$GH_FIXTURES/comments" 2>/dev/null ;;
      # `#261` asks what an issue waits for, once per candidate. Keyed by
      # `<repo>#<number>` because the point of the case is that one candidate is
      # blocked and the next one is not — one fixture could not say that. Before
      # `*/issues/*`, which this path would otherwise match.
      */dependencies/blocked_by)
        if [ -s "$GH_FIXTURES/dependencies_fail" ]; then
          echo "HTTP 502" >&2
          exit 1
        fi
        key=${2#repos/}
        key=${key%/dependencies/blocked_by}
        fixture="$GH_FIXTURES/blocked_${key//\//_}"
        # An absent fixture is *nothing blocks it*, not a failed read: a missing
        # file would make `cat` exit 1, and every case written before `#261`
        # would then die on an unreadable queue.
        [ -f "$fixture" ] || exit 0
        # **This one path runs the real `--jq`**, against a fixture that is real
        # API JSON. Everywhere else the fixture holds what `--jq` would have
        # printed, which is fine while the filter is a projection — here the
        # filter is the behaviour under test (`select(.state == "open")`), and a
        # fixture of pre-filtered lines would assert nothing about it.
        expression=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --jq) expression=$2; shift 2 ;;
            *)    shift ;;
          esac
        done
        if [ -n "$expression" ]; then jq -r "$expression" "$fixture"; else cat "$fixture"; fi ;;
      # `#256` sweeps the worker's own pull requests: one search for the set,
      # then one read per pull request. The per-pull-request fixture is keyed by
      # `<repo>#<number>` so one case can hold several and give each a different
      # `mergeable_state`, which is the whole thing the sweep decides on.
      search/issues)
        if [ -s "$GH_FIXTURES/search_fails" ]; then
          echo "HTTP 422: the search index said no" >&2
          exit 1
        fi
        cat "$GH_FIXTURES/prs" 2>/dev/null ;;
      */pulls/*)
        key=${2#repos/}
        fixture="$GH_FIXTURES/pull_${key//\//_}"
        [ -f "$fixture" ] || exit 0
        # **One line per read, and the last one repeats** (`#484`). The sweep now
        # asks a second time when the first answer is `dirty`, because a `dirty`
        # computed against a base that has since moved is a stale verdict and the
        # first read is what makes GitHub recompute it. A stub that answered the
        # same thing forever could not tell *it recomputed and it was stale* from
        # *it recomputed and the conflict is real*, which is the only distinction
        # the change makes. Repeating the last line keeps every case written
        # before this one saying exactly what it said.
        state=$(head -n 1 "$fixture")
        if [ "$(wc -l < "$fixture")" -gt 1 ]; then
          tail -n +2 "$fixture" > "$fixture.next" && mv "$fixture.next" "$fixture"
        fi
        # The sweep asks for the state and the age together — one request
        # answers both, which is why saying how long costs nothing. The stub
        # dispatches on the `--jq` it was given, as the dependencies path above
        # already does.
        expression=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --jq) expression=$2; shift 2 ;;
            *)    shift ;;
          esac
        done
        case "$expression" in
          *updated_at*)
            printf '%s\t%s\n' "$state" \
              "$(cat "$GH_FIXTURES/updated_${key//\//_}" 2>/dev/null)" ;;
          *) printf '%s\n' "$state" ;;
        esac ;;
      # `#275` sweeps every repository rather than one search result, so it asks
      # three more questions: which repositories exist, which pull requests are
      # open in each, and what `main` requires there.
      orgs/*/repos)
        if [ -s "$GH_FIXTURES/repos_fail" ]; then
          echo "HTTP 502: the organisation could not be listed" >&2
          exit 1
        fi
        cat "$GH_FIXTURES/repos" 2>/dev/null ;;
      */branches/*/protection)
        key=${2#repos/}
        branch=${key#*/branches/}
        branch=${branch%/protection}
        key=${key%/branches/*/protection}
        key="${key}_${branch}"
        # **An absent fixture is an unprotected branch**, which is the case the
        # sweep must refuse on, and a missing file makes `cat` exit 1 exactly as
        # the live API 404s on a branch with no protection.
        cat "$GH_FIXTURES/protection_${key//\//_}" 2>/dev/null ;;
      # The second path that runs the real `--jq`, for `*/dependencies/blocked_by`'s
      # reason: fork, draft and already-armed are what the filter *is*, so a
      # fixture of pre-filtered numbers would assert nothing about them. These
      # fixtures are API-shaped JSON and the script's own filter decides.
      */pulls)
        key=${2#repos/}
        key=${key%/pulls}
        fixture="$GH_FIXTURES/pulls_${key//\//_}"
        if [ -s "$GH_FIXTURES/pulls_fail_${key//\//_}" ]; then
          echo "HTTP 502: the pull requests could not be listed" >&2
          exit 1
        fi
        [ -f "$fixture" ] || exit 0
        expression=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --jq) expression=$2; shift 2 ;;
            *)    shift ;;
          esac
        done
        if [ -n "$expression" ]; then jq -r "$expression" "$fixture"; else cat "$fixture"; fi ;;
      # `#326` asks whether anybody disarmed auto-merge, once per candidate that
      # survived the list filters. Before `*/issues/*`, which this path would
      # otherwise match. **An absent fixture is a timeline with no such event**,
      # not a failed read — every case written before `#326` would otherwise die
      # here on a pull request nobody ever touched. The real `--jq` runs, because
      # picking `auto_merge_disabled` out of a mixed timeline is the behaviour
      # under test.
      */timeline)
        if [ -s "$GH_FIXTURES/timeline_fail" ]; then
          echo "HTTP 502: the timeline could not be read" >&2
          exit 1
        fi
        key=${2#repos/}
        key=${key%/timeline}
        fixture="$GH_FIXTURES/timeline_${key//\//_}"
        [ -f "$fixture" ] || exit 0
        expression=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --jq) expression=$2; shift 2 ;;
            *)    shift ;;
          esac
        done
        if [ -n "$expression" ]; then jq -r "$expression" "$fixture"; else cat "$fixture"; fi ;;
      # `#258` asks one more question per pull request: is the issue closed.
      # `*/comments` above already claimed the comments path, so this only ever
      # sees the issue itself.
      */issues/*)
        key=${2#repos/}
        cat "$GH_FIXTURES/issue_${key//\//_}" 2>/dev/null ;;
      *) ;;
    esac ;;
  *) ;;
esac
STUB

install_stub() {
  cp "$WORK/stub-gh" "$WORK/bin/gh"
  chmod +x "$WORK/bin/gh"
}
install_stub
export PATH="$WORK/bin:$PATH"

case_setup() {
  GH_FIXTURES="$WORK/fixtures"
  GH_LOG="$WORK/gh.log"
  export GH_FIXTURES GH_LOG
  rm -rf "$GH_FIXTURES"
  mkdir -p "$GH_FIXTURES"
  : > "$GH_LOG"
}

# `pick` prints "<owner/repo>\t<number>" since `#231` — a bare number identifies
# nothing across five repositories that each start at 1. The helper keeps the
# cases below readable rather than littering them with $'\t'.
q() {
  local number=$1 repo=${2:-Kolonie-AI/kolonie-docs}
  printf '%s\t%s' "$repo" "$number"
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

# ## Extracting one step out of the workflow, without a regex (2026-08-10)
#
# These assertions used `awk '/name: …/,/name: …/'` and CI disagreed with a
# local run about what that range contained — the two `set +e` checks passed
# here and failed on the runner against the identical commit. Rather than find
# out which awk was right, `index()` takes the markers as plain strings and
# there is nothing left to disagree about.
#
# **And an empty block is a failure, not a pass.** The version of these checks
# before this one asserted the *absence* of `set -euo`, which an empty block
# satisfies trivially — so an extraction that had silently stopped working
# reported ok. Every caller goes through here and here refuses to return
# nothing.
step_block() {
  local start=$1 stop=$2 file=${3:-$WORKFLOW} out
  out=$(awk -v s="$start" -v e="$stop" '
    !on && index($0, s) { on = 1; next }
    on && index($0, e)  { exit }
    on                  { print }
  ' "$file")
  if [ -z "$out" ]; then
    echo "  FAIL could not extract the block between '$start' and '$stop'" >&2
    FAILURES+=("step_block found nothing for '$start'")
  fi
  printf '%s\n' "$out"
}

boarded() {
  # $1.. are `number:Status[:owner/repo][@hours][+label,label][!CLOSED]` rows.
  #
  # The three optional suffixes are marked rather than positional because two of
  # the fields they carry contain colons themselves — a timestamp and a label
  # both do — so a fifth `:` field would have been unparseable.
  #
  # `@hours` is **how long ago the card last moved**, which is the clock `#381`
  # escalates on and the one a comment does not reset. It defaults to *now*, so
  # every case written before `#381` reads as a card that has just moved and
  # nothing about them changes.
  local items=()
  for row in "$@"; do
    local state=OPEN labels="" carded_hours=0
    case "$row" in *'!CLOSED') state=CLOSED; row=${row%'!CLOSED'} ;; esac
    case "$row" in *+*) labels=${row#*+}; row=${row%%+*} ;; esac
    case "$row" in *@*) carded_hours=${row#*@}; row=${row%@*} ;; esac

    IFS=':' read -r number status repo <<<"$row"
    repo=${repo:-Kolonie-AI/kolonie-docs}

    local labelJson=()
    if [ -n "$labels" ]; then
      local names name
      IFS=',' read -ra names <<<"$labels"
      for name in "${names[@]}"; do labelJson+=("\"$name\""); done
    fi
    local joinedLabels carded
    joinedLabels=$(IFS=,; echo "${labelJson[*]}")
    carded=$(date -u -d "$carded_hours hours ago" +%Y-%m-%dT%H:%M:%SZ)

    items+=("{\"id\":\"ITEM_${number}\",\"updatedAt\":\"$carded\",\"status\":\"${status}\",\"labels\":[$joinedLabels],\"content\":{\"number\":${number},\"repository\":\"$repo\",\"state\":\"$state\",\"title\":\"issue $number\"}}")
  done
  local joined
  joined=$(IFS=,; echo "${items[*]}")
  echo "{\"items\":[$joined]}" > "$GH_FIXTURES/board"
}

issued() {
  # $1.. are `number|createdAt|label,label[|owner/repo]` rows. The repository
  # defaults to `Kolonie-AI/kolonie-docs` so that the cases written before the
  # queue went organisation-wide (`#231`) still read as they did.
  local rows=()
  for row in "$@"; do
    IFS='|' read -r number created labels repo <<<"$row"
    repo=${repo:-Kolonie-AI/kolonie-docs}
    local labelJson=()
    if [ -n "$labels" ]; then
      IFS=',' read -ra names <<<"$labels"
      for name in "${names[@]}"; do labelJson+=("{\"name\":\"$name\"}"); done
    fi
    local joinedLabels
    joinedLabels=$(IFS=,; echo "${labelJson[*]}")
    rows+=("{\"number\":$number,\"createdAt\":\"$created\",\"labels\":[$joinedLabels],\"repository\":{\"name\":\"${repo#*/}\",\"nameWithOwner\":\"$repo\"}}")
  done
  local joined
  joined=$(IFS=,; echo "${rows[*]}")
  echo "[$joined]" > "$GH_FIXTURES/issues"
}

echo "the queue"

case_setup
issued
echo '{"items":[]}' > "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" pick 2>"$WORK/err"); rc=$?
check "an empty queue exits 0" "0" "$rc"
check "an empty queue picks nothing" "" "$out"
contains "an empty queue says so, rather than being silent" "nothing queued" "$(cat "$WORK/err")"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2" "11|2026-08-02T00:00:00Z|agent:opencode,p1"
boarded "10:Ready" "11:Ready"
check "p1 comes before an older p2" "$(q 11)" "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2" "11|2026-08-02T00:00:00Z|agent:opencode,p2"
boarded "10:Ready" "11:Ready"
check "at the same priority the oldest goes first" "$(q 10)" "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2" "11|2026-08-02T00:00:00Z|agent:opencode,p2"
boarded "10:In Progress" "11:Ready"
check "a repository with work in flight yields nothing, siblings included" "" "$(bash "$SCRIPT" pick 2>/dev/null)"

# The other half of the same rule, and the reason for it: a second repository is
# not blocked by the first. Two runs in one repository is what every conflict was
# made of; two runs in different ones share no history, no check and no merge.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2" \
       "11|2026-08-02T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-website"
boarded "10:In Progress" "11:Ready:Kolonie-AI/kolonie-website"
check "and another repository is still open for work" \
  "$(q 11 Kolonie-AI/kolonie-website)" "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2" "11|2026-08-02T00:00:00Z|agent:opencode,p2"
boarded "10:Done" "11:Ready"
check "a finished issue does not hold its repository" "$(q 11)" "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2"
boarded "10:Inbox"
check "only Ready is the queue — Inbox is not" "" "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p1,blocked:human" "11|2026-08-02T00:00:00Z|agent:opencode,p2"
boarded "10:Ready" "11:Ready"
check "blocked:human is out of the queue however it got the label" "$(q 11)" "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2"
boarded "10:Ready"
out=$(bash "$SCRIPT" pick 2>/dev/null)
check "exactly one issue is taken per run" "1" "$(grep -c . <<<"$out")"

# `#250`: the one mark a person putting `agent:opencode` back does not undo.
# `kolonie-infra#107` was taken three times in eighty minutes and refused in the
# same words each time, because nothing could say *this is not the worker's*.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p1,opencode:forbidden" \
       "11|2026-08-02T00:00:00Z|agent:opencode,p2"
boarded "10:Ready" "11:Ready"
check "an issue the worker may not implement is out of the queue" "$(q 11)" \
  "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p1,opencode:forbidden"
boarded "10:Ready"
check "even when it is the only thing queued and in Ready" "" \
  "$(bash "$SCRIPT" pick 2>/dev/null)"

# `opencode:failed` is the reversible one and must stay reversible: it says
# *tried and not finished*, and putting the queue label back is the whole design.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p1,opencode:failed"
boarded "10:Ready"
check "a merely failed issue is still takeable, which is the difference" "$(q 10)" \
  "$(bash "$SCRIPT" pick 2>/dev/null)"

echo
echo "claiming, and the token that stopped working"

case_setup
boarded "10:Ready"
bash "$SCRIPT" claim Kolonie-AI/kolonie-docs 10 >/dev/null 2>&1
rc=$?
check "a claim that works exits 0" "0" "$rc"
contains "a claim moves the issue to In Progress" "604be33b" "$(cat "$GH_LOG")"

case_setup
boarded "10:Ready"
echo yes > "$GH_FIXTURES/edit_fails"
err=$(bash "$SCRIPT" claim Kolonie-AI/kolonie-docs 10 2>&1 >/dev/null); rc=$?
check "a claim that cannot be written fails the run" "4" "$rc"
contains "and says the token may have expired" "may have expired" "$err"
contains "and says work has not started" "Not starting work" "$err"

case_setup
echo '{"items":[]}' > "$GH_FIXTURES/board"
err=$(bash "$SCRIPT" claim Kolonie-AI/kolonie-docs 10 2>&1 >/dev/null); rc=$?
check "an issue not on the board is refused rather than worked" "3" "$rc"

echo
echo "releasing a failed run"

case_setup
boarded "10:In Progress"
bash "$SCRIPT" release Kolonie-AI/kolonie-docs 10 >/dev/null 2>&1
contains "a release puts the issue back in Ready" "0ce10d81" "$(cat "$GH_LOG")"

case_setup
boarded "10:In Progress"
echo yes > "$GH_FIXTURES/edit_fails"
err=$(bash "$SCRIPT" release Kolonie-AI/kolonie-docs 10 2>&1 >/dev/null); rc=$?
check "a release that cannot be written fails loudly" "4" "$rc"
contains "and says the issue is stuck and needs a person" "needs a person" "$err"
contains "and names the run" "$RUN_URL" "$err"

echo
echo "a board that is large, or from another repository (#142, 2026-08-07)"

# The defect the first non-empty run found, and the reason it took three days to
# find: the board was passed to `jq` with `--argjson`, which puts the whole
# document on the command line. Linux caps a single argument at 128 KiB whatever
# `ARG_MAX` says, the real board was about 190 KB, and `jq` died with `Argument
# list too long` — after which `pick` printed nothing and the workflow reported
# an empty queue. Every run between 2026-08-04 and 2026-08-07 was green and
# quiet because the queue really was empty; the first hour it was not, the run
# was still green and still quiet.
#
# The board here is padded past the ceiling with items nothing else matches, so
# a `pick` that puts it on a command line cannot survive this case.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2"
{
  printf '{"items":['
  printf '{"id":"ITEM_10","status":"Ready","content":{"number":10,"repository":"Kolonie-AI/kolonie-docs"}}'
  for i in $(seq 1 1500); do
    printf ',{"id":"PAD_%s","status":"Done","content":{"number":%s,"repository":"Kolonie-AI/kolonie-platform","title":"padding so the document passes the per-argument ceiling"}}' "$i" "$((90000 + i))"
  done
  printf ']}'
} > "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" pick 2>"$WORK/err"); rc=$?
check "a board too large for a command line still picks" "$(q 10)" "$out"
check "and exits 0" "0" "$rc"
absent "nothing complains about the argument list" "Argument list too long" "$(cat "$WORK/err")"

# The second defect in the same query, latent rather than firing: it matched the
# board item by issue *number* only. The board spans five repositories and the
# numbers repeat across them, so another repository's item decided what this
# repository's status was. `board_item_for` always matched the repository too —
# the two disagreeing is how a worker takes an issue the board says is Blocked.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2"
cat > "$GH_FIXTURES/board" <<'BOARD'
{"items":[
  {"id":"ITEM_OTHER","status":"Ready","content":{"number":10,"repository":"Kolonie-AI/kolonie-platform"}},
  {"id":"ITEM_10","status":"Blocked","content":{"number":10,"repository":"Kolonie-AI/kolonie-docs"}}
]}
BOARD
check "another repository's item does not put an issue in the queue" "" "$(bash "$SCRIPT" pick 2>/dev/null)"

# And the same in the direction that matters for throughput: a Ready issue here
# is not hidden by a Blocked item of the same number elsewhere.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2"
cat > "$GH_FIXTURES/board" <<'BOARD'
{"items":[
  {"id":"ITEM_OTHER","status":"Blocked","content":{"number":10,"repository":"Kolonie-AI/kolonie-platform"}},
  {"id":"ITEM_10","status":"Ready","content":{"number":10,"repository":"Kolonie-AI/kolonie-docs"}}
]}
BOARD
check "nor does it hide one" "$(q 10)" "$(bash "$SCRIPT" pick 2>/dev/null)"

# A board that cannot be read is not an empty queue. The workflow reads `pick`'s
# exit code separately from its output for exactly this distinction, and it can
# only do that if the script draws it.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2"
: > "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" pick 2>"$WORK/err"); rc=$?
check "an unreadable board fails rather than reading as an empty queue" "1" "$rc"
check "and picks nothing" "" "$out"
contains "and says the queue is unknown" "unknown" "$(cat "$WORK/err")"

echo
echo "the queue is the organisation, not this repository (#231)"

# The defect `#231` names: the worker could only ever see the repository hosting
# it, and the queue there was empty while labelled work sat in the other four.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-platform"
boarded "10:Ready:Kolonie-AI/kolonie-platform"
check "an issue in another repository is in the queue" \
  "$(q 10 Kolonie-AI/kolonie-platform)" "$(bash "$SCRIPT" pick 2>/dev/null)"

# Oldest wins across repositories, not within one. Ordering that only held
# inside a repository would make the queue depend on which repository you asked
# from, which is the property `#231` removes.
case_setup
issued "10|2026-08-03T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-docs" \
       "20|2026-08-01T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-website" \
       "30|2026-08-02T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-platform"
boarded "10:Ready:Kolonie-AI/kolonie-docs" \
        "20:Ready:Kolonie-AI/kolonie-website" \
        "30:Ready:Kolonie-AI/kolonie-platform"
check "the oldest across the whole organisation goes first" \
  "$(q 20 Kolonie-AI/kolonie-website)" "$(bash "$SCRIPT" pick 2>/dev/null)"

# And priority still beats age across repositories, for `#234`'s reason: a p1
# labelled this morning must not wait behind a p2 from last week, wherever
# either of them lives.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-website" \
       "20|2026-08-05T00:00:00Z|agent:opencode,p1|Kolonie-AI/kolonie-platform"
boarded "10:Ready:Kolonie-AI/kolonie-website" "20:Ready:Kolonie-AI/kolonie-platform"
check "p1 beats an older p2 in a different repository" \
  "$(q 20 Kolonie-AI/kolonie-platform)" "$(bash "$SCRIPT" pick 2>/dev/null)"

# Two repositories, same issue number, only one of them Ready. This is the case
# that was latent while the search was single-repository and is live now.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-docs" \
       "10|2026-08-02T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-platform"
boarded "10:Blocked:Kolonie-AI/kolonie-docs" "10:Ready:Kolonie-AI/kolonie-platform"
check "the same number in two repositories resolves to the Ready one" \
  "$(q 10 Kolonie-AI/kolonie-platform)" "$(bash "$SCRIPT" pick 2>/dev/null)"

# `#234`: an issue with neither priority sorts last, and the log names it. It is
# taken rather than skipped — refusing it would leave it queued forever with
# nothing saying why.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode" \
       "11|2026-08-05T00:00:00Z|agent:opencode,p2"
boarded "10:Ready" "11:Ready"
out=$(bash "$SCRIPT" pick 2>"$WORK/err")
check "an unprioritised issue sorts behind a newer p2" "$(q 11)" "$out"
contains "and the log names it rather than dropping it silently" \
  "carries neither p1 nor p2" "$(cat "$WORK/err")"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode"
boarded "10:Ready"
check "an unprioritised issue is still taken when it is all there is" \
  "$(q 10)" "$(bash "$SCRIPT" pick 2>/dev/null)"

# `#234`'s definition of done: one queue holding one of every case at once, so
# that the three tiers are shown to order against each other rather than each
# being right on its own. Deliberately laid out worst-first — the newest p1 is
# last in the fixture and first out of the queue.
case_setup
issued "40|2026-08-01T00:00:00Z|agent:opencode" \
       "30|2026-08-02T00:00:00Z|agent:opencode,p2" \
       "20|2026-08-01T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-website" \
       "10|2026-08-06T00:00:00Z|agent:opencode,p1|Kolonie-AI/kolonie-platform"
boarded "40:Ready" "30:Ready" \
        "20:Ready:Kolonie-AI/kolonie-website" \
        "10:Ready:Kolonie-AI/kolonie-platform"
out=$(bash "$SCRIPT" pick 2>"$WORK/err")
check "one of each case: the newest p1 still goes first" \
  "$(q 10 Kolonie-AI/kolonie-platform)" "$out"
contains "and the unprioritised one is named, not silently last" \
  "#40 carries neither p1 nor p2" "$(cat "$WORK/err")"

# The same queue with the p1 gone, to show the second and third tiers order
# against each other and not merely against p1.
case_setup
issued "40|2026-08-01T00:00:00Z|agent:opencode" \
       "30|2026-08-02T00:00:00Z|agent:opencode,p2" \
       "20|2026-08-01T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-website"
boarded "40:Ready" "30:Ready" "20:Ready:Kolonie-AI/kolonie-website"
check "with no p1, the oldest p2 goes before a p2 and both before no priority" \
  "$(q 20 Kolonie-AI/kolonie-website)" "$(bash "$SCRIPT" pick 2>/dev/null)"

# A search that fails is not an empty queue, for the same reason an unreadable
# board is not: the workflow reads the exit code separately from the output and
# can only do that if this script draws the distinction.
case_setup
rm -f "$GH_FIXTURES/issues"
cat > "$WORK/bin/gh" <<'FAILING'
#!/bin/bash
echo "$*" >> "$GH_LOG"
if [ "$1 $2" = "search issues" ]; then
  echo "HTTP 503" >&2
  exit 1
fi
FAILING
chmod +x "$WORK/bin/gh"
out=$(bash "$SCRIPT" pick 2>"$WORK/err"); rc=$?
check "a search that fails is not an empty queue" "1" "$rc"
check "and picks nothing" "" "$out"
contains "and says the queue is unknown" "unknown" "$(cat "$WORK/err")"
# Put the ordinary stub back for everything after this.
install_stub

echo
echo "the check command, read from the target's AGENTS.md (#231)"

case_setup
cat > "$WORK/agents-ok.md" <<'DOC'
# AGENTS.md
## 3. Something else
```bash
not this one
```
## 11. The check command
```bash
npm run check
```
## 12. When something here is wrong
DOC
out=$(bash "$SCRIPT" check-command "$WORK/agents-ok.md" 2>/dev/null); rc=$?
check "the command is read out of the named section" "npm run check" "$out"
check "and reading it exits 0" "0" "$rc"

case_setup
cat > "$WORK/agents-none.md" <<'DOC'
# AGENTS.md
## 1. What you need
```bash
gh auth login
```
DOC
err=$(bash "$SCRIPT" check-command "$WORK/agents-none.md" 2>&1 >/dev/null); rc=$?
check "a repository naming no check command fails rather than guessing" "5" "$rc"
contains "and says what is missing" "names no check command" "$err"
absent "and does not invent npm" "npm run check" "$err"

case_setup
err=$(bash "$SCRIPT" check-command "$WORK/there-is-no-such-file.md" 2>&1 >/dev/null); rc=$?
check "a missing AGENTS.md fails the same way" "5" "$rc"
contains "and says so" "no AGENTS.md" "$err"

echo
echo "what the check needs in front of it (#247)"

# The defect: the worker re-ran `kolonie-platform`'s check in an environment
# without PostgreSQL, and that check refuses to run without one on purpose. The
# repository states its prerequisite beside the command it already states, and
# this is the reader for it — the same convention, so that the worker holds no
# per-repository knowledge (`#231`).
case_setup
cat > "$WORK/agents-prereq.md" <<'DOC'
# AGENTS.md
## 8. The check command
```bash
npm run check
```
## 8a. The check prerequisite
```bash
npm run test:db:up
```
## 9. When you are unsure
DOC
out=$(bash "$SCRIPT" check-prerequisite "$WORK/agents-prereq.md" 2>/dev/null); rc=$?
check "the prerequisite is read out of its own section" "npm run test:db:up" "$out"
check "and reading it exits 0" "0" "$rc"
check "the check command is unaffected by the sibling section" \
  "npm run check" "$(bash "$SCRIPT" check-command "$WORK/agents-prereq.md" 2>/dev/null)"

# Four of the five repositories need nothing before their check, so silence is
# the ordinary answer and must not read as a defect — unlike a missing check
# *command*, which stops the run.
case_setup
out=$(bash "$SCRIPT" check-prerequisite "$WORK/agents-ok.md" 2>/dev/null); rc=$?
check "a repository declaring no prerequisite prints nothing" "" "$out"
check "and that is not an error" "0" "$rc"

echo
echo "the environment a prerequisite hands back (#247)"

# `npm run test:db:up` finishes by printing `export DATABASE_URL=…` — the
# repository's existing interface to a person. Honouring it is the whole point:
# a prerequisite that starts a server the check cannot then find has done
# nothing.
case_setup
cat > "$WORK/prereq-out.txt" <<'OUT'
created container kolonie-pg
waiting for postgres.
export DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5433/kolonie_test
OUT
out=$(bash "$SCRIPT" exports "$WORK/prereq-out.txt" 2>/dev/null)
check "the value survives one round of eval" \
  "postgres://postgres:postgres@127.0.0.1:5433/kolonie_test" \
  "$(eval "$out"; printf '%s' "${DATABASE_URL:-}")"
absent "and the rest of the output does not" "waiting for postgres" "$out"
absent "nor does the line about the container" "created container" "$out"

# Sourcing the output wholesale would run whatever the command chose to print,
# in this shell, with this run's credentials. `printf %q` is what makes a value
# a value.
case_setup
printf 'export DATABASE_URL=x$(id);echo pwned\n' > "$WORK/prereq-evil.txt"
out=$(bash "$SCRIPT" exports "$WORK/prereq-evil.txt" 2>/dev/null)
check "a command substitution in a value stays data" \
  'x$(id);echo pwned' "$(eval "$out"; printf '%s' "${DATABASE_URL:-}")"

case_setup
printf 'export DATABASE_URL="postgres://quoted/db"\n' > "$WORK/prereq-quoted.txt"
out=$(bash "$SCRIPT" exports "$WORK/prereq-quoted.txt" 2>/dev/null)
check "one layer of the emitter's own quotes comes off" \
  "postgres://quoted/db" "$(eval "$out"; printf '%s' "${DATABASE_URL:-}")"

# "My check needs a database" is not "my check needs your token", and the
# refusal is by name rather than by hoping nobody writes it.
case_setup
printf 'export PATH=/evil\nexport GH_TOKEN=stolen\nexport DATABASE_URL=ok\n' \
  > "$WORK/prereq-greedy.txt"
out=$(bash "$SCRIPT" exports "$WORK/prereq-greedy.txt" 2>"$WORK/err")
absent "a prerequisite may not set PATH" "PATH" "$out"
absent "nor may it hand the step a token" "GH_TOKEN" "$out"
contains "and it says which name it refused" "refusing to let the check prerequisite set PATH" \
  "$(cat "$WORK/err")"
check "while what it may set still arrives" "ok" \
  "$(eval "$out"; printf '%s' "${DATABASE_URL:-}")"

echo
echo "a failure that says why (#245)"

# The excerpt is moving build output from a place GitHub masks secrets in — a
# log — to a place it does not: a public comment. So the bounding and the
# filtering are the two properties worth proving, and `#245`'s definition of
# done asks for both by name.
#
# The stub returns what `--jq` would already have reduced the response to,
# which is the convention the `run list` cases above set: the fixture is the
# answer, not the payload.

case_setup
{
  for i in $(seq 1 200); do echo "line $i of build output"; done
} > "$WORK/big.log"
out=$(bash "$SCRIPT" excerpt "$WORK/big.log" 2>/dev/null)
check "the excerpt is twenty lines and not two hundred" "20" "$(grep -c . <<<"$out")"
contains "and it is the last of them, which is where the reason is" "line 200" "$out"
absent "not the first" "line 1 of" "$out"

case_setup
{
  printf 'a very long line: '
  for i in $(seq 1 500); do printf 'xxxxxxxxxx'; done
  printf '\n'
} > "$WORK/long.log"
out=$(bash "$SCRIPT" excerpt "$WORK/long.log" 2>/dev/null)
if [ "${#out}" -le 400 ]; then
  echo "  ok   one enormous line is cut rather than posted whole"
else
  echo "  FAIL one enormous line is cut rather than posted whole"
  echo "         got ${#out} characters"
  FAILURES+=("the line bound")
fi
contains "and says it was cut" "line truncated" "$out"

case_setup
{ for i in $(seq 1 20); do printf 'line %s: ' "$i"; for j in $(seq 1 40); do printf 'yyyyyyyyyy'; done; printf '\n'; done; } > "$WORK/wide.log"
out=$(bash "$SCRIPT" excerpt "$WORK/wide.log" 2>/dev/null)
if [ "${#out}" -le 2200 ]; then
  echo "  ok   and twenty long lines are cut as a whole too"
else
  echo "  FAIL and twenty long lines are cut as a whole too"
  echo "         got ${#out} characters"
  FAILURES+=("the total bound")
fi
contains "and says so" "excerpt truncated" "$out"

# The filtering, with a fake secret in the fixture — `#245`'s definition of
# done. By value first: this is the case where the secret is one this run holds
# and could be any shape at all.
case_setup
cat > "$WORK/leaky.log" <<'LOG'
> npm run check
fetching from https://gateway.invalid.example/v1 with key sk-live-abcdefghijklmnop
GH_TOKEN=ghp_0123456789abcdefghijklmnopqrstuvwxyz
DATABASE_URL=postgres://admin:hunter2@db.internal:5432/kolonie
Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJlSGVyZQ
MY_SERVICE_TOKEN=totally-secret-value
LOG
out=$(LLM_GATEWAY_BASE_URL="https://gateway.invalid.example/v1" \
      LLM_GATEWAY_API_KEY_WORKER="sk-live-abcdefghijklmnop" \
      bash "$SCRIPT" excerpt "$WORK/leaky.log" 2>/dev/null)
absent "the gateway URL does not reach a comment" "gateway.invalid.example" "$out"
absent "nor does the gateway key" "sk-live-abcdefghijklmnop" "$out"
contains "and it says which variable it took out, which is enough to fix it" \
  "the value of LLM_GATEWAY_BASE_URL" "$out"

# By shape second, which is what value-matching cannot do: a credential this
# run never held, printed by somebody else's build.
absent "a GitHub token is redacted by shape, not only by value" \
  "ghp_0123456789abcdefghijklmnopqrstuvwxyz" "$out"
absent "so is a bearer token" "c2lnbmF0dXJlSGVyZQ" "$out"
absent "so is a password inside a URL" "hunter2" "$out"
absent "and an environment dump does not leak a value it never knew" \
  "totally-secret-value" "$out"
contains "while the line that says what actually failed survives" "npm run check" "$out"

# A short or unset value must not be searched for: it would match half the
# output and turn every excerpt into `[redacted]`.
case_setup
printf 'the build failed in packages/db\n' > "$WORK/short.log"
out=$(LLM_GATEWAY_API_KEY_WORKER="abc" bash "$SCRIPT" excerpt "$WORK/short.log" 2>/dev/null)
check "a value too short to search for is skipped, not matched" \
  "the build failed in packages/db" "$out"

# The excerpt goes into a fenced block in a comment, so three backticks in the
# output would end the fence and render the rest as prose.
case_setup
printf 'error in ```js\nconst x = 1\n```\n' > "$WORK/fenced.log"
out=$(bash "$SCRIPT" excerpt "$WORK/fenced.log" 2>/dev/null)
absent "a fence in the output cannot break out of the comment's fence" '```' "$out"

case_setup
out=$(bash "$SCRIPT" excerpt "$WORK/there-is-no-output-file" 2>/dev/null); rc=$?
check "no captured output is not an error" "0" "$rc"
check "and produces nothing to put in the comment" "" "$out"

echo
echo "what the model is given to read, and what it may print (#254)"

# The failing line is above the tail's cut, which is the whole reason a tail
# was not enough: `kolonie-platform#533`'s siblings read as "npm run check did
# not pass" followed by a hundred lines of vitest output.
case_setup
{
  echo "FAIL src/thing.test.ts > it keeps the header"
  echo "AssertionError: expected 'a' to be 'b'"
  for i in $(seq 1 100); do echo "some perfectly ordinary line $i"; done
} > "$WORK/deep.log"
out=$(bash "$SCRIPT" failure-digest "$WORK/deep.log" 2>/dev/null)
contains "the failing line survives even when it is a hundred lines above the tail" \
  "FAIL src/thing.test.ts" "$out"
contains "and so does what it expected against what it got" \
  "expected 'a' to be 'b'" "$out"
contains "the tail is still there, and is labelled as a tail" \
  "the last 20 lines" "$out"
contains "which the tail's last line proves" "ordinary line 100" "$out"

# The digest is read by a model that then writes into a public comment, so it
# goes through exactly the filter the excerpt does.
case_setup
printf 'Error: connecting with ghp_%s\n' "aaaaaaaaaaaaaaaaaaaa" > "$WORK/leaky-digest.log"
out=$(bash "$SCRIPT" failure-digest "$WORK/leaky-digest.log" 2>/dev/null)
absent "a token in the log never reaches the model" "ghp_aaaaaaaaaaaaaaaaaaaa" "$out"
contains "and is named rather than silently dropped" "redacted: a GitHub token" "$out"

case_setup
printf 'FAIL: %s\n' "$(head -c 9000 /dev/zero | tr '\0' 'x')" > "$WORK/huge.log"
out=$(bash "$SCRIPT" failure-digest "$WORK/huge.log" 2>/dev/null)
if [ "${#out}" -le 6200 ]; then
  echo "  ok   somebody else's build output cannot become an unbounded prompt"
else
  echo "  FAIL somebody else's build output cannot become an unbounded prompt"
  echo "         ${#out} characters"
  FAILURES+=("the digest is bounded")
fi

case_setup
out=$(bash "$SCRIPT" failure-digest "$WORK/there-is-no-such-log" 2>/dev/null); rc=$?
check "no log is not an error, it is a missing paragraph" "0" "$rc"
check "and there is nothing to ask about" "" "$out"

# The account is written by a process that holds the gateway key, so what it
# wrote is filtered before it is published — the same filter again.
case_setup
printf 'The check failed because GH_TOKEN=%s was wrong.\n' "ghp_bbbbbbbbbbbbbbbbbbbb" > "$WORK/account.raw"
out=$(bash "$SCRIPT" redact "$WORK/account.raw" 2>/dev/null)
absent "a secret the model wrote into its account does not reach the comment" \
  "ghp_bbbbbbbbbbbbbbbbbbbb" "$out"

case_setup
printf 'a %s b\n' "$(head -c 4000 /dev/zero | tr '\0' 'y')" > "$WORK/verbose.raw"
out=$(bash "$SCRIPT" redact "$WORK/verbose.raw" 2>/dev/null)
if [ "${#out}" -le 1600 ]; then
  echo "  ok   \"answer in three short paragraphs\" is an instruction, not a guarantee"
else
  echo "  FAIL \"answer in three short paragraphs\" is an instruction, not a guarantee"
  echo "         ${#out} characters"
  FAILURES+=("the account is bounded")
fi

case_setup
printf 'it broke in ```ts\nconst x = 1\n```\n' > "$WORK/fenced.raw"
out=$(bash "$SCRIPT" redact "$WORK/fenced.raw" 2>/dev/null)
absent "and a fence in the account cannot break the comment either" '```' "$out"

echo
echo "nothing leaves the runner carrying a secret (#246)"

# The boundary where a secret would actually escape: GitHub masks a value in a
# log and does not mask it in a pull request, and a public branch cannot be
# taken back. `#246`'s definition of done asks for a fixture with a fake secret,
# and this is it.
case_setup
cat > "$WORK/clean-diff" <<'DIFF'
--- a/AGENTS.md
+++ b/AGENTS.md
+The check prerequisite is npm run test:db:up.
DIFF
printf 'A repository states what its check needs\n' > "$WORK/clean-messages"
out=$(LLM_GATEWAY_API_KEY_WORKER="sk-live-abcdefghijklmnop" \
      LLM_GATEWAY_BASE_URL="https://gateway.invalid.example/v1" \
      bash "$SCRIPT" leak-check "$WORK/clean-diff" "$WORK/clean-messages" 2>&1); rc=$?
check "an ordinary change is not refused" "0" "$rc"
# The count of secrets is whatever this environment happens to hold — the run's
# in production, a developer's `GH_TOKEN` here — so the assertion is on what was
# read rather than on how many needles there were.
contains "and it says what it checked" "against 2 file(s)" "$out"

case_setup
cat > "$WORK/leaky-diff" <<'DIFF'
+// the gateway we talk to
+const BASE = "https://gateway.invalid.example/v1"
DIFF
err=$(LLM_GATEWAY_API_KEY_WORKER="sk-live-abcdefghijklmnop" \
      LLM_GATEWAY_BASE_URL="https://gateway.invalid.example/v1" \
      bash "$SCRIPT" leak-check "$WORK/leaky-diff" 2>&1 >/dev/null); rc=$?
check "a diff carrying the gateway URL is refused, not warned about" "1" "$rc"
contains "and it names the variable, which is enough to fix it" \
  "the value of LLM_GATEWAY_BASE_URL" "$err"
contains "and the file" "leaky-diff" "$err"
absent "and never the value — printing it here would be the leak itself" \
  "gateway.invalid.example" "$err"

# A commit message is published by the push exactly as the diff is.
case_setup
printf 'fix: talk to https://gateway.invalid.example/v1 directly\n' > "$WORK/leaky-messages"
rc=0
LLM_GATEWAY_BASE_URL="https://gateway.invalid.example/v1" \
  bash "$SCRIPT" leak-check "$WORK/clean-diff" "$WORK/leaky-messages" >/dev/null 2>&1 || rc=$?
check "a commit message is checked as well as the diff" "1" "$rc"

case_setup
printf 'Opened by the hourly opencode worker. Key: ghp_0123456789abcdefghijkl\n' > "$WORK/leaky-body"
rc=0
GH_TOKEN="ghp_0123456789abcdefghijkl" \
  bash "$SCRIPT" leak-check "$WORK/leaky-body" >/dev/null 2>&1 || rc=$?
check "so is the pull request body" "1" "$rc"

# The cost of a false positive here is a refused pull request and an hour of
# work back in the queue, so the test is by value and deliberately not by shape:
# a repository that documents what a token looks like is not leaking one.
case_setup
printf 'Set GH_TOKEN to a value like ghp_xxxxxxxxxxxxxxxxxxxx before running.\n' \
  > "$WORK/documentation.md"
rc=0
GH_TOKEN="ghp_0123456789abcdefghijkl" \
  bash "$SCRIPT" leak-check "$WORK/documentation.md" >/dev/null 2>&1 || rc=$?
check "documentation that looks like a token is not a leak" "0" "$rc"

case_setup
printf 'nothing to see\n' > "$WORK/plain"
out=$(GH_TOKEN="short" bash "$SCRIPT" leak-check "$WORK/plain" 2>&1); rc=$?
check "a value too short to search for cannot refuse everything" "0" "$rc"
contains "and it says it skipped it rather than passing quietly" "skip: GH_TOKEN" "$out"

echo
echo "which step failed, and how often this issue has (#245)"

case_setup
export GITHUB_RUN_ID=31302611039
printf 'Work it\n' > "$GH_FIXTURES/jobs"
check "the failed step is named" "Work it" "$(bash "$SCRIPT" failed-step 2>/dev/null)"

case_setup
export GITHUB_RUN_ID=31302611039
echo yes > "$GH_FIXTURES/api_fails"
out=$(bash "$SCRIPT" failed-step 2>/dev/null); rc=$?
check "an API that will not answer does not fail the reporting step" "0" "$rc"
check "it simply has no name to give" "" "$out"

case_setup
printf '2\n' > "$GH_FIXTURES/comments"
check "prior failures on the issue are counted off its own comments" \
  "2" "$(bash "$SCRIPT" previous-failures Kolonie-AI/kolonie-docs 10 2>/dev/null)"

# `--paginate` with `--jq` prints one number per page rather than one total.
case_setup
printf '100\n2\n' > "$GH_FIXTURES/comments"
check "and a paginated answer is added up rather than read as the first page" \
  "102" "$(bash "$SCRIPT" previous-failures Kolonie-AI/kolonie-docs 10 2>/dev/null)"

case_setup
echo yes > "$GH_FIXTURES/api_fails"
check "a count that cannot be read is zero, not a failure" \
  "0" "$(bash "$SCRIPT" previous-failures Kolonie-AI/kolonie-docs 10 2>/dev/null)"
unset GITHUB_RUN_ID

echo
echo "an issue that waits for another one (#261)"

# `kolonie-platform#660` reads a contract field `#659` creates. It was written in
# prose in both bodies, twice, and the worker took `#660` anyway on 2026-08-10
# because `pick` read labels and a column and neither of those can say *waits*.
blocked_by() {
  # $1 is `owner/repo|number`, the rest are `owner/repo|number|state` blockers.
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

case_setup
issued "660|2026-08-01T00:00:00Z|agent:opencode,p1|Kolonie-AI/kolonie-platform"
boarded "660:Ready:Kolonie-AI/kolonie-platform"
blocked_by "Kolonie-AI/kolonie-platform|660" "Kolonie-AI/kolonie-platform|659|open"
out=$(bash "$SCRIPT" pick 2>"$WORK/err")
check "an issue with an open blocker is not taken" "" "$out"
contains "and the log names what it waits for" "660 waits for Kolonie-AI/kolonie-platform#659" "$(cat "$WORK/err")"

# The case `#261` asks to get right. `#659`'s pull request was closed without
# merging and the issue went back to Ready; a closed blocker still unblocks,
# because the field is either on `main` or it is not and the check says which.
case_setup
issued "660|2026-08-01T00:00:00Z|agent:opencode,p1|Kolonie-AI/kolonie-platform"
boarded "660:Ready:Kolonie-AI/kolonie-platform"
blocked_by "Kolonie-AI/kolonie-platform|660" "Kolonie-AI/kolonie-platform|659|closed"
check "a closed blocker does not block" "$(q 660 Kolonie-AI/kolonie-platform)" \
  "$(bash "$SCRIPT" pick 2>/dev/null)"

# Blocked or not blocked. An issue waiting on one open and one closed blocker is
# waiting.
case_setup
issued "660|2026-08-01T00:00:00Z|agent:opencode,p1|Kolonie-AI/kolonie-platform"
boarded "660:Ready:Kolonie-AI/kolonie-platform"
blocked_by "Kolonie-AI/kolonie-platform|660" \
  "Kolonie-AI/kolonie-platform|659|closed" "Kolonie-AI/kolonie-docs|1|open"
check "one open blocker among closed ones is still a block" "" \
  "$(bash "$SCRIPT" pick 2>/dev/null)"

# The queue does not stop at the blocked issue: it goes on to the next one in the
# order it had already computed.
case_setup
issued "660|2026-08-01T00:00:00Z|agent:opencode,p1|Kolonie-AI/kolonie-platform" \
       "10|2026-08-02T00:00:00Z|agent:opencode,p1"
boarded "660:Ready:Kolonie-AI/kolonie-platform" "10:Ready"
blocked_by "Kolonie-AI/kolonie-platform|660" "Kolonie-AI/kolonie-platform|659|open"
check "the next candidate is taken instead" "$(q 10)" "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "660|2026-08-01T00:00:00Z|agent:opencode,p1|Kolonie-AI/kolonie-platform" \
       "10|2026-08-02T00:00:00Z|agent:opencode,p1"
boarded "660:Ready:Kolonie-AI/kolonie-platform" "10:Ready"
blocked_by "Kolonie-AI/kolonie-platform|660" "Kolonie-AI/kolonie-platform|659|open"
blocked_by "Kolonie-AI/kolonie-docs|10" "Kolonie-AI/kolonie-docs|9|open"
out=$(bash "$SCRIPT" pick 2>"$WORK/err")
check "a queue where everything waits takes nothing" "" "$out"
contains "and says that is what happened" "every queued issue is waiting" "$(cat "$WORK/err")"

# A dependency that cannot be read is not *no dependency*. The whole point is
# that the worker stops taking blocked work, and a queue it cannot read is
# unknown — which the workflow reports as an error rather than as a quiet hour.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p1"
boarded "10:Ready"
echo yes > "$GH_FIXTURES/dependencies_fail"
out=$(bash "$SCRIPT" pick 2>"$WORK/err"); rc=$?
check "a dependency read that fails does not become an empty answer" "" "$out"
check "and the queue is unknown rather than empty" "1" "$rc"
contains "and it says why it took nothing" "rather than taking blocked work" "$(cat "$WORK/err")"

# The same question, asked directly, because a person needs it too.
case_setup
blocked_by "Kolonie-AI/kolonie-platform|660" \
  "Kolonie-AI/kolonie-platform|659|open" "Kolonie-AI/kolonie-docs|1|closed"
check "blockers prints the open ones and only those" "Kolonie-AI/kolonie-platform#659" \
  "$(bash "$SCRIPT" blockers Kolonie-AI/kolonie-platform 660 2>/dev/null)"

echo
echo "two runs, one issue (#266)"

# `solo` used to answer this by refusing to let a second run start at all. It is
# gone, so what is tested here is the claim itself — the thing the file always
# said was the real lock and was not.

# A claim reads the column before it writes it. The stub now moves the board on a
# successful write, so this is the whole sequence: Ready, write, read back.
case_setup
boarded "10:Ready"
out=$(bash "$SCRIPT" claim Kolonie-AI/kolonie-docs 10 2>/dev/null); rc=$?
check "a claim on a Ready issue is held" "held" "$out"
check "and exits 0" "0" "$rc"

# The wide window, and the one that has actually happened: `pick` and `claim` are
# separate steps of the workflow, so another run can take the issue in between.
case_setup
boarded "10:In Progress"
out=$(bash "$SCRIPT" claim Kolonie-AI/kolonie-docs 10 2>"$WORK/err"); rc=$?
check "an issue already In Progress is not claimed" "lost" "$out"
check "and losing is not a failure" "0" "$rc"
absent "and the column is not overwritten" "604be33b" "$(cat "$GH_LOG")"
contains "and the log says who has it" "another run took it" "$(cat "$WORK/err")"

# A write that reports success and does not take is not a claim. Before `#266`
# nothing here was read, so this was indistinguishable from a claim that worked.
case_setup
boarded "10:Ready"
echo yes > "$GH_FIXTURES/edit_ignored"
out=$(bash "$SCRIPT" claim Kolonie-AI/kolonie-docs 10 2>"$WORK/err"); rc=$?
check "a write that did not move the column is not a claim" "lost" "$out"
check "and still exits 0" "0" "$rc"
contains "and says what it read back" "reads back as Ready" "$(cat "$WORK/err")"

echo
echo "the tie-break, for two runs that read Ready in the same instant (#266)"

# Both runs write a claim comment and comment ids are ordered, which the board is
# not. Each run reads the same list and reaches the same verdict, so exactly one
# of them holds the issue however the two orderings interleave.
claimed() {
  # $1.. are `id|minutes ago|run url` rows.
  : > "$GH_FIXTURES/comments"
  for row in "$@"; do
    IFS='|' read -r id ago url <<<"$row"
    printf '%s\t%s\t%s\n' "$id" \
      "$(date -u -d "$ago minutes ago" +%Y-%m-%dT%H:%M:%SZ)" \
      "Taken by the opencode worker (\`kolonie-docs#142\`), moved to **In Progress**: $url" \
      >> "$GH_FIXTURES/comments"
  done
}

MINE="https://github.com/Kolonie-AI/kolonie-docs/actions/runs/111"
THEIRS="https://github.com/Kolonie-AI/kolonie-docs/actions/runs/222"

case_setup
claimed "900|0|$MINE"
check "the only claim on the issue is this run's" "held" \
  "$(bash "$SCRIPT" verify-claim Kolonie-AI/kolonie-docs 10 "$MINE" 2>/dev/null)"

case_setup
claimed "900|0|$MINE" "901|0|$THEIRS"
check "the earlier comment wins, and it is this one" "held" \
  "$(bash "$SCRIPT" verify-claim Kolonie-AI/kolonie-docs 10 "$MINE" 2>/dev/null)"

case_setup
claimed "899|0|$THEIRS" "900|0|$MINE"
out=$(bash "$SCRIPT" verify-claim Kolonie-AI/kolonie-docs 10 "$MINE" 2>/dev/null)
check "and when it is the other one, this run has lost" "lost $THEIRS" "$out"

# The verdict cannot depend on which run asks: the loser must see itself lose and
# the winner must see itself win, from the identical list.
case_setup
claimed "899|0|$THEIRS" "900|0|$MINE"
check "the same list read by the winner says held" "held" \
  "$(bash "$SCRIPT" verify-claim Kolonie-AI/kolonie-docs 10 "$THEIRS" 2>/dev/null)"

# The window exists only to keep a previous attempt out of the comparison. An
# issue that failed and was queued again carries an old claim comment, and losing
# to it would park the issue for good.
case_setup
claimed "500|90|$THEIRS" "900|0|$MINE"
check "a claim from an earlier attempt does not win the race" "held" \
  "$(bash "$SCRIPT" verify-claim Kolonie-AI/kolonie-docs 10 "$MINE" 2>/dev/null)"

# The comment is best-effort in the workflow. If it never landed there is nothing
# to compare, and the answer has to be the safe one — the column was read back.
case_setup
: > "$GH_FIXTURES/comments"
out=$(bash "$SCRIPT" verify-claim Kolonie-AI/kolonie-docs 10 "$MINE" 2>"$WORK/err")
check "no claim comment at all is not a lost race" "held" "$out"
contains "and says why nothing contests it" "nothing contests" "$(cat "$WORK/err")"

case_setup
echo yes > "$GH_FIXTURES/api_fails"
out=$(bash "$SCRIPT" verify-claim Kolonie-AI/kolonie-docs 10 "$MINE" 2>"$WORK/err"); rc=$?
check "an API that cannot answer holds the claim" "held" "$out"
check "and exits 0" "0" "$rc"
contains "and says the column was read back" "read back and held" "$(cat "$WORK/err")"

echo
echo "an In Progress item with no run behind it (#266)"

# `pick` skips a repository that has anything In Progress, so a forgotten item
# holds its whole repository out of the queue. It is reported and never moved:
# an automatic release would eventually take an issue from somebody mid-thought.
aged() {
  # $1.. are `owner/repo|number|hours ago` rows.
  printf '%s\n' "$1" >/dev/null
  for row in "$@"; do
    IFS='|' read -r repo number ago <<<"$row"
    date -u -d "$ago hours ago" +%Y-%m-%dT%H:%M:%SZ \
      > "$GH_FIXTURES/issue_${repo//\//_}_issues_$number"
  done
}

case_setup
boarded "10:In Progress" "11:Ready"
aged "Kolonie-AI/kolonie-docs|10|9"
out=$(bash "$SCRIPT" forgotten-claims 2>/dev/null)
contains "an item untouched for hours is a finding" "Kolonie-AI/kolonie-docs	10	9" "$out"

case_setup
boarded "10:In Progress"
aged "Kolonie-AI/kolonie-docs|10|1"
check "an item somebody is working is not" "" "$(bash "$SCRIPT" forgotten-claims 2>/dev/null)"

case_setup
boarded "10:Ready" "11:Done"
check "and nothing outside In Progress is looked at" "" \
  "$(bash "$SCRIPT" forgotten-claims 2>/dev/null)"

# Reported, never released — the whole distinction `#266` draws.
case_setup
boarded "10:In Progress"
aged "Kolonie-AI/kolonie-docs|10|9"
bash "$SCRIPT" forgotten-claims >/dev/null 2>&1
absent "the finding moves nothing" "item-edit" "$(cat "$GH_LOG")"

case_setup
boarded "10:In Progress"
echo yes > "$GH_FIXTURES/api_fails"
out=$(bash "$SCRIPT" forgotten-claims 2>"$WORK/err"); rc=$?
check "an issue that cannot be read is not reported" "" "$out"
check "and the sweep still exits 0" "0" "$rc"
contains "and says it said nothing rather than guessing" "rather than guessing" "$(cat "$WORK/err")"

echo
echo "the clock that grows, and what the claim is costing (#381)"

# The sweep speaks on the *issue* clock, which its own comment resets — that is
# the de-duplication and it stays. What it *says* is the **card** clock, which a
# comment does not touch, so the number grows across reports and a threshold
# expressed in it can fire. Before this, an item forgotten for a month reported
# four hours, every time, forever.
case_setup
boarded "10:In Progress@30"
aged "Kolonie-AI/kolonie-docs|10|9"
out=$(bash "$SCRIPT" forgotten-claims 2>/dev/null)
contains "the issue clock decides whether to speak" "Kolonie-AI/kolonie-docs	10	9" "$out"
check "and the card clock is what is said" "30" "$(cut -f4 <<<"$out")"

# The two really are independent: an issue commented on a minute ago is still
# reported as a card that has not moved in two days, once the issue clock passes
# the threshold again.
case_setup
boarded "10:In Progress@48"
aged "Kolonie-AI/kolonie-docs|10|5"
check "a comment resets one and not the other" "48" \
  "$(bash "$SCRIPT" forgotten-claims 2>/dev/null | cut -f4)"

# A board that answered without an `updatedAt` reports `-1` rather than `0`.
# *Moved just now* is the opposite of the finding, and inventing it would make
# the escalation silently unreachable for that item.
case_setup
boarded "10:In Progress"
jq -c '.items[0].updatedAt = null' "$GH_FIXTURES/board" > "$WORK/no-card-clock.json"
aged "Kolonie-AI/kolonie-docs|10|9"
check "a card with no clock is not guessed at" "-1" \
  "$(BOARD_FILE="$WORK/no-card-clock.json" bash "$SCRIPT" forgotten-claims 2>/dev/null | cut -f4)"

# **What the claim is costing.** `pick` skips every issue in a repository that
# has anything In Progress, so the same forgotten claim is urgent in a repository
# with a queue and housekeeping in an empty one — and until `#381` the report
# could not tell them apart. The filters are `pick`'s.
case_setup
boarded "10:In Progress@30" \
  "11:Ready+agent:opencode" \
  "12:Ready+agent:opencode,blocked:human" \
  "13:Ready+agent:claude" \
  "14:Ready+agent:opencode,opencode:forbidden" \
  "15:Ready+agent:opencode!CLOSED" \
  "16:Ready+agent:opencode:Kolonie-AI/kolonie-platform" \
  "17:Inbox+agent:opencode"
aged "Kolonie-AI/kolonie-docs|10|9"
check "only what pick would actually take next is counted" "1" \
  "$(bash "$SCRIPT" forgotten-claims 2>/dev/null | cut -f5)"

case_setup
boarded "10:In Progress@30"
aged "Kolonie-AI/kolonie-docs|10|9"
check "and an empty repository says so rather than nothing" "0" \
  "$(bash "$SCRIPT" forgotten-claims 2>/dev/null | cut -f5)"

echo
echo "the escalated half, for a reader that is not the issue (#381)"

# The daily waiting list runs on its own schedule and under the board app, which
# cannot read an issue at all. So `--escalated` answers from the board alone: no
# issue clock, no `gh api repos/...`, and only cards past the threshold.
case_setup
boarded "10:In Progress@48" "11:In Progress@2" "12:Ready+agent:opencode"
out=$(bash "$SCRIPT" forgotten-claims --escalated 2>/dev/null)
contains "a card past a day is escalated" "Kolonie-AI/kolonie-docs	10	48	1" "$out"
absent "and a fresh one is not" "	11	" "$out"
absent "no issue is read for it" "api repos/" "$(cat "$GH_LOG")"

case_setup
boarded "10:In Progress@48"
check "the threshold is where the constant says" "" \
  "$(FORGOTTEN_CLAIM_ESCALATE_HOURS=72 bash "$SCRIPT" forgotten-claims --escalated 2>/dev/null)"

echo
echo "asking the board where an issue is (#381)"

# `release` and `move` both write a column and neither read one back, which is
# how a failure comment came to say *put back in Ready* about a card that had not
# moved. One point, one word.
case_setup
boarded "10:In Progress"
check "the column is reported in a word" "In Progress" "$(bash "$SCRIPT" column Kolonie-AI/kolonie-docs 10)"

case_setup
boarded "10:In Progress"
out=$(bash "$SCRIPT" column Kolonie-AI/kolonie-docs 99 2>/dev/null); rc=$?
check "an issue that is not on the board is not a column" "" "$out"
check "and it exits 3" "3" "$rc"

# An item on the board and in no column is a real state — what an arrival that
# was never sorted looks like — and it is reported in words, so that a caller
# putting this into a sentence need not know a blank means anything.
case_setup
boarded "10:"
check "no column is said rather than left blank" "no column" \
  "$(bash "$SCRIPT" column Kolonie-AI/kolonie-docs 10)"

# The release path reads its own write back, as `claim` has since `#266`. A
# mutation that reports success and does not take is what `#381` is about.
case_setup
boarded "10:In Progress"
echo yes > "$GH_FIXTURES/edit_ignored"
out=$(bash "$SCRIPT" release Kolonie-AI/kolonie-docs 10 2>&1); rc=$?
check "a release that did not take fails" "4" "$rc"
contains "and says where the card actually is" "reads back In Progress" "$out"

echo
echo "a board read by somebody else (BOARD_FILE)"

# The sweep needs the board *and* permission to comment in another repository,
# and one step holds one `GH_TOKEN`. `WORKER_REPO_TOKEN` lost `read:project`
# between 14:31 and 15:01 UTC on 2026-08-12 and every run since said *the
# forgotten-claim sweep could not read the board*, under a green tick. So the
# workflow reads the board in its own step, under the board app, and hands the
# file over.
case_setup
boarded "10:In Progress"
bash "$SCRIPT" board-read > "$WORK/handed-over.json" 2>/dev/null

# A fresh case: no board fixture at all, so anything that queries for itself sees
# nothing. Only the handed-over file can produce a finding here.
case_setup
aged "Kolonie-AI/kolonie-docs|10|9"
out=$(BOARD_FILE="$WORK/handed-over.json" bash "$SCRIPT" forgotten-claims 2>/dev/null)
contains "a handed-over board is what the sweep reads" "Kolonie-AI/kolonie-docs	10	9" "$out"
absent "and the board is not asked for again" "projectV2" "$(cat "$GH_LOG")"

# The issue itself is still read with the step's own credential — that is the
# half the board app cannot do, and the reason this is a file and not a token.
contains "and the issue is still read for itself" "api repos/Kolonie-AI/kolonie-docs/issues/10" \
  "$(cat "$GH_LOG")"

# *Nobody could look* must not arrive as *nobody is In Progress*: an empty file
# falls through to the query rather than answering with an empty board.
case_setup
boarded "10:In Progress"
aged "Kolonie-AI/kolonie-docs|10|9"
: > "$WORK/empty.json"
out=$(BOARD_FILE="$WORK/empty.json" bash "$SCRIPT" forgotten-claims 2>/dev/null)
contains "an empty hand-over falls through to the query" "Kolonie-AI/kolonie-docs	10	9" "$out"

case_setup
boarded "10:In Progress"
aged "Kolonie-AI/kolonie-docs|10|9"
out=$(BOARD_FILE="$WORK/there-is-no-such-file.json" bash "$SCRIPT" forgotten-claims 2>/dev/null)
contains "and so does a file that is not there" "Kolonie-AI/kolonie-docs	10	9" "$out"

# Every other caller reads the board itself, which is why the workflow sets the
# variable on one step rather than on the job.
case_setup
boarded "10:In Progress"
issued "10|2026-08-01T00:00:00Z|agent:opencode"
check "an unset BOARD_FILE changes nothing about the queue" "" \
  "$(BOARD_FILE= bash "$SCRIPT" pick 2>/dev/null)"

echo
echo "a refusal that names a rule rather than the issue (#250)"

case_setup
cat > "$WORK/refusal-rule.txt" <<'DOC'
Issue #107 cannot be implemented as specified under this run's binding rule that
.github/workflows/ must not be edited.
DOC
check "a refusal naming the workflow path is recognised" ".github/workflows/" \
  "$(bash "$SCRIPT" worker-rule-refusal "$WORK/refusal-rule.txt" 2>/dev/null)"

case_setup
printf 'This needs a change to opencode.json, which I may not edit.\n' > "$WORK/refusal-config.txt"
check "and so is the other one" "opencode.json" \
  "$(bash "$SCRIPT" worker-rule-refusal "$WORK/refusal-config.txt" 2>/dev/null)"

# The distinction this whole issue turns on: a refusal about the *issue* may
# not recur, and must keep the ordinary "put the label back" ending.
case_setup
cat > "$WORK/refusal-issue.txt" <<'DOC'
The issue asks for a decision I cannot take: it does not say which of the two
schemas the migration should target, and both are defensible.
DOC
check "a refusal about the issue is not a worker-rule refusal" "" \
  "$(bash "$SCRIPT" worker-rule-refusal "$WORK/refusal-issue.txt" 2>/dev/null)"

case_setup
out=$(bash "$SCRIPT" worker-rule-refusal "$WORK/there-is-no-refusal" 2>/dev/null); rc=$?
check "no refusal file is not an error" "0" "$rc"
check "and names nothing" "" "$out"

echo
echo "the board write triage is allowed to make (#262)"

# `move` exists so that the triage pass does not carry a second copy of the
# mutation. What makes it safe is that it writes three columns and refuses the
# rest: In Progress and In Review belong to whoever holds them, and a triage pass
# that could write them could take work off an agent that has it.
case_setup
boarded "77:Inbox"
check "an issue in Inbox can be moved to Ready" "moved Kolonie-AI/kolonie-docs#77 to Ready" \
  "$(bash "$SCRIPT" move Kolonie-AI/kolonie-docs 77 Ready 2>/dev/null)"
check "and the board says so" "Ready" \
  "$(jq -r '.items[0].status' "$GH_FIXTURES/board")"

# `#412`: the third writable column. It is on the same side of the line as the
# other two because nobody *holds* a card in Blocked — moving one takes no work
# off anybody, which is the property that decides what triage may write.
case_setup
boarded "77:Ready"
check "and an issue in Ready can be moved to Blocked" "moved Kolonie-AI/kolonie-docs#77 to Blocked" \
  "$(bash "$SCRIPT" move Kolonie-AI/kolonie-docs 77 Blocked 2>/dev/null)"
check "and the board says so" "Blocked" \
  "$(jq -r '.items[0].status' "$GH_FIXTURES/board")"

case_setup
boarded "77:Ready"
out=$(bash "$SCRIPT" move Kolonie-AI/kolonie-docs 77 "In Progress" 2>&1); rc=$?
check "In Progress is not a column triage may write" "1" "$rc"
contains "and it says which columns belong to somebody" "belong to whoever holds them" "$out"
absent "and nothing was written" "item-edit" "$(cat "$GH_LOG")"

case_setup
boarded "77:Ready"
out=$(bash "$SCRIPT" move Kolonie-AI/kolonie-docs 77 Done 2>&1); rc=$?
check "nor Done" "1" "$rc"

echo
echo "the prohibitions live in one file and everything else reads it (#260)"

# The rule used to live in three places — the model's prompt, this script and
# `AGENTS.md` §5 — and two of them had already drifted: the prompt forbade
# `.github/scripts/opencode-worker.sh` from 2026-08-10 and the script's own
# comparison did not, so a refusal naming the queue script was read as a refusal
# about the issue and invited a retry that could not work. These cases assert the
# direction of the fix rather than the contents of the list: a fifth path added to
# the document must reach the prompt and the comparison without a second edit.

case_setup
mkdir -p "$WORK/prohibitions"
cat > "$WORK/prohibitions/one.md" <<'DOC'
# What no worker can do

## The paths no worker may write

```
.github/workflows/
somewhere/else.sh
```

## Conditions no repository check can satisfy

Not paths, and this heading must not be read as though it were.

```
not/a/path
```
DOC

check "every line of the fenced block is a path, not only the first" \
  ".github/workflows/
somewhere/else.sh" \
  "$(bash "$SCRIPT" prohibited-paths "$WORK/prohibitions/one.md")"

# The heading's own block and nothing after it: `first_fenced_block_under` stops
# at the next heading for the two check headings, and this has to as well or the
# conditions table becomes a list of paths.
absent "and nothing from the next section" "not/a/path" \
  "$(bash "$SCRIPT" prohibited-paths "$WORK/prohibitions/one.md")"

case_setup
printf 'This wants a change under somewhere/else.sh, which I may not write.\n' \
  > "$WORK/refusal-from-file.txt"
check "a refusal is matched against the file's list, not a constant in the script" \
  "somewhere/else.sh" \
  "$(PROHIBITIONS_FILE="$WORK/prohibitions/one.md" bash "$SCRIPT" worker-rule-refusal "$WORK/refusal-from-file.txt" 2>/dev/null)"

case_setup
out=$(PROHIBITIONS_FILE="$WORK/prohibitions/absent.md" bash "$SCRIPT" prohibited-paths 2>&1); rc=$?
check "a list that cannot be read stops the run rather than running with none" "5" "$rc"
contains "and says which file it wanted" "absent.md" "$out"

case_setup
cat > "$WORK/prohibitions/empty.md" <<'DOC'
# What no worker can do

## The paths no worker may write

Prose where the block should be.
DOC
out=$(PROHIBITIONS_FILE="$WORK/prohibitions/empty.md" bash "$SCRIPT" prohibited-paths 2>&1); rc=$?
check "a heading with no fenced block is the same failure" "5" "$rc"
contains "and names the heading it needs" "The paths no worker may write" "$out"

# Now the live document, which is the one the worker will actually read. The
# assertion is that the historical two are still in it — the pair `#250` was
# written for — and that the two readers derive from it rather than repeating it.
case_setup
live=$(bash "$SCRIPT" prohibited-paths)
contains "the live list still names the workflows directory" ".github/workflows/" "$live"
contains "and the runtime configuration" "opencode.json" "$live"
contains "and the queue script, which the prompt forbade before the script did" \
  ".github/scripts/opencode-worker.sh" "$live"

workflow_text=$(cat "$ROOT/.github/workflows/opencode-worker.yml")
contains "the workflow reads the list rather than carrying a copy" \
  "opencode-worker.sh prohibited-paths" "$workflow_text"
contains "and the prompt the model is given is built from what it read" \
  'Do not edit ${prohibited_list}' "$workflow_text"
for path in ".github/workflows/" "opencode.json" ".github/scripts/opencode-worker.sh"; do
  absent "the prompt does not name $path itself" \
    "Do not edit $path" "$workflow_text"
done

# §5 is `agents/routes.md` since `#363` split `AGENTS.md` into routed modules.
# The assertion is the same one — the labeller is sent to the document rather
# than given a copy of it — read from the file that now carries that section.
contains "§5, wherever it lives, sends the labeller to the document" \
  "operations/worker-prohibitions.md" \
  "$(cat "$ROOT/agents/routes.md")"

echo
echo "the pull requests that cannot merge (#256)"

# The fixtures are the *output* of the `--jq` the stub ignores, as everywhere
# else in this file: one `<repo>\t<number>` line per pull request the search
# found, and one `<state>\t<branch>` line per pull request read.
searched() {
  : > "$GH_FIXTURES/prs"
  for row in "$@"; do
    IFS='|' read -r repo number state ref <<<"$row"
    printf '%s\t%s\n' "$repo" "$number" >> "$GH_FIXTURES/prs"
    printf '%s\t%s\n' "$state" "$ref" > "$GH_FIXTURES/pull_${repo//\//_}_pulls_$number"
  done
}

case_setup
searched "Kolonie-AI/kolonie-platform|668|dirty|opencode/issue-659"
out=$(bash "$SCRIPT" stale-pull-requests 2>/dev/null)
check "a conflicting pull request is reported with its issue" \
  "$(printf 'Kolonie-AI/kolonie-platform\t668\t659')" "$out"

case_setup
searched "Kolonie-AI/kolonie-platform|668|clean|opencode/issue-659"
check "one that merges cleanly is left alone" "" "$(bash "$SCRIPT" stale-pull-requests 2>/dev/null)"

# The three states that are not this issue, and each would take a healthy pull
# request out of In Review if it were read as a conflict.
case_setup
searched "Kolonie-AI/kolonie-platform|668|blocked|opencode/issue-659"
check "a required check that has not reported is not a conflict" "" \
  "$(bash "$SCRIPT" stale-pull-requests 2>/dev/null)"

case_setup
searched "Kolonie-AI/kolonie-platform|668|behind|opencode/issue-659"
check "a branch that is merely out of date is not a conflict" "" \
  "$(bash "$SCRIPT" stale-pull-requests 2>/dev/null)"

case_setup
searched "Kolonie-AI/kolonie-platform|668|unstable|opencode/issue-659"
check "a failing non-required check is not a conflict" "" \
  "$(bash "$SCRIPT" stale-pull-requests 2>/dev/null)"

# GitHub computes mergeability lazily, so the first read after `main` moves is
# `unknown`. Reading that either way round is wrong, and it must say so.
case_setup
searched "Kolonie-AI/kolonie-platform|668|unknown|opencode/issue-659"
out=$(bash "$SCRIPT" stale-pull-requests 2>"$WORK/err")
check "an uncomputed mergeability is not an answer" "" "$out"
contains "and the run says it is waiting rather than deciding" \
  "has not computed mergeability yet" "$(cat "$WORK/err")"

case_setup
searched "Kolonie-AI/kolonie-platform|668|dirty|feature/somebody-elses-branch"
out=$(bash "$SCRIPT" stale-pull-requests 2>"$WORK/err")
check "a branch that names no issue is left for a person" "" "$out"
contains "and says why it was left" "names no issue" "$(cat "$WORK/err")"

case_setup
searched "Kolonie-AI/kolonie-platform|668|dirty|opencode/issue-659" \
         "Kolonie-AI/kolonie-docs|215|clean|opencode/issue-212" \
         "Kolonie-AI/kolonie-infra|116|dirty|opencode/issue-99"
out=$(bash "$SCRIPT" stale-pull-requests 2>/dev/null)
check "the sweep is organisation-wide and reports every conflicting one" "2" "$(grep -c . <<<"$out")"
contains "including the one in another repository" "kolonie-infra	116	99" "$out"

case_setup
echo yes > "$GH_FIXTURES/search_fails"
out=$(bash "$SCRIPT" stale-pull-requests 2>/dev/null); rc=$?
check "a search that fails reports nothing rather than guessing" "" "$out"
check "and does not fail the run that has queue work to do" "0" "$rc"

case_setup
searched "Kolonie-AI/kolonie-platform|668|dirty|opencode/issue-659"
bash "$SCRIPT" stale-pull-requests >/dev/null 2>&1
log=$(cat "$GH_LOG")
contains "the sweep identifies its pull requests by the body sentence" \
  "opencode worker for" "$log"
absent "and not by whoever the token authenticates as" "author:" "$log"
absent "the sweep itself never closes anything — that is the workflow's, on the repo token" \
  "pr close" "$log"
absent "and never moves a card" "item-edit" "$log"

echo
echo "the completions nobody was told about (#258)"

# `<repo>|<pr>|<issue named in the body>|<issue state>|<completion comments>`.
# The body is what the search returns, so it carries the sentence the sweep
# matches on and the issue number it reads out of it.
merged() {
  : > "$GH_FIXTURES/prs"
  for row in "$@"; do
    IFS='|' read -r repo pr issue state reported <<<"$row"
    printf '%s\t%s\tOpened by the opencode worker for #%s, unattended. Closes #%s\n' \
      "$repo" "$pr" "$issue" "$issue" >> "$GH_FIXTURES/prs"
    printf '%s\n' "$state" > "$GH_FIXTURES/issue_${repo//\//_}_issues_$issue"
    printf '%s\n' "$reported" > "$GH_FIXTURES/comments"
  done
}

case_setup
merged "Kolonie-AI/kolonie-platform|667|658|closed|0"
check "a merged pull request whose issue says nothing is reported" \
  "$(printf 'Kolonie-AI/kolonie-platform\t667\t658')" \
  "$(bash "$SCRIPT" unreported-completions 2>/dev/null)"

case_setup
merged "Kolonie-AI/kolonie-platform|667|658|closed|1"
check "one that has already been reported is not reported twice" "" \
  "$(bash "$SCRIPT" unreported-completions 2>/dev/null)"

# Opening a pull request is not completion, and neither is merging one whose
# issue somebody reopened because the work was not enough.
case_setup
merged "Kolonie-AI/kolonie-platform|667|658|open|0"
check "an issue that is still open gets no success summary" "" \
  "$(bash "$SCRIPT" unreported-completions 2>/dev/null)"

case_setup
: > "$GH_FIXTURES/prs"
printf 'Kolonie-AI/kolonie-platform\t667\tSomebody else opened this one by hand\n' > "$GH_FIXTURES/prs"
out=$(bash "$SCRIPT" unreported-completions 2>"$WORK/err")
check "a body that names no issue is reported on nothing" "" "$out"
contains "and says so rather than passing silently" "names no issue" "$(cat "$WORK/err")"

case_setup
echo yes > "$GH_FIXTURES/search_fails"
out=$(bash "$SCRIPT" unreported-completions 2>/dev/null); rc=$?
check "a search that fails reports no completions" "" "$out"
check "and does not fail the run" "0" "$rc"

case_setup
merged "Kolonie-AI/kolonie-platform|667|658|closed|0"
bash "$SCRIPT" unreported-completions >/dev/null 2>&1
log=$(cat "$GH_LOG")
contains "the sweep bounds itself by when the pull request merged" "merged:>=" "$log"
contains "and reads the issue's own comments for the marker" \
  "issues/658/comments" "$log"
absent "the sweep itself never comments — that is the workflow's job" "issue comment" "$log"

echo
echo "the pull requests nobody armed (#275)"

# One organisation, written from `<repo>|<protection>` rows. An empty protection
# is a `main` that requires nothing, which is a 404 from the live API and a
# missing fixture here.
org() {
  : > "$GH_FIXTURES/repos"
  for row in "$@"; do
    # A third field names the default branch, because `#331` reads it per
    # repository. `main` where a case does not care, which is nearly all of them.
    IFS='|' read -r repo required default_branch <<<"$row"
    printf '%s\t%s\n' "$repo" "${default_branch:-main}" >> "$GH_FIXTURES/repos"
    [ -n "${required:-}" ] &&
      printf '%s\n' "$required" > "$GH_FIXTURES/protection_${repo//\//_}_${default_branch:-main}"
  done
}

# The open pull requests of one repository, as the API returns them, because the
# filter is what is under test.
# `<number>|<draft>|<head repo>|<auto_merge>[|<label>,<label>]`. The labels are
# optional and default to none, so every case written before `#326` reads the
# same as it did.
opened() {
  local repo=$1; shift
  local rows=()
  for row in "$@"; do
    # A sixth field is the base ref, for `#331`. Absent means the default branch,
    # which is what every case written before it meant.
    IFS='|' read -r number draft head auto labels base <<<"$row"
    local labelled="[]"
    if [ -n "${labels:-}" ]; then
      labelled=$(printf '%s' "$labels" | jq -R 'split(",") | map({name: .})' -c)
    fi
    rows+=("{\"number\":${number},\"draft\":${draft},\"auto_merge\":${auto},\"labels\":${labelled},\"head\":{\"repo\":${head}},\"base\":{\"ref\":\"${base:-main}\",\"repo\":{\"full_name\":\"${repo}\"}}}")
  done
  local joined
  joined=$(IFS=,; echo "${rows[*]}")
  printf '[%s]\n' "$joined" > "$GH_FIXTURES/pulls_${repo//\//_}"
}

# `mergeable_state` per pull request, one fixture each, as the sweep reads it.
# Several states may be given: the sweep reads once, and on `dirty` reads again,
# so a case can say *it said dirty and then said clean* — which is what a stale
# verdict actually looks like from outside (`#484`). One state given is that
# state for every read, so every case written before `#484` is unchanged.
mergeability() {
  local repo=$1 number=$2; shift 2
  printf '%s\n' "$@" > "$GH_FIXTURES/pull_${repo//\//_}_pulls_$number"
}

# How long a pull request has been carrying the verdict it has (`#484`). The
# sweep reads it from the same call that answers mergeability — one request
# answers both, so saying how long costs nothing. Given as an ISO timestamp,
# which is what `updated_at` is; absent means the sweep could not read one.
pull_updated() {
  local repo=$1 number=$2 when=$3
  printf '%s\n' "$when" > "$GH_FIXTURES/updated_${repo//\//_}_pulls_$number"
}

# A pull request's timeline, as `#326` reads it: the event names in order. Given
# a mixed timeline on purpose, because the filter has to find one event among
# several rather than read a flag somebody set for it.
timeline() {
  local repo=$1 number=$2; shift 2
  printf '%s\n' "$*" | tr ' ' '\n' | jq -R '{event: .}' | jq -s -c '.' \
    > "$GH_FIXTURES/timeline_${repo//\//_}_issues_$number"
}

mine='{"full_name":"Kolonie-AI/kolonie-docs"}'
theirs='{"full_name":"somebody/kolonie-docs"}'

case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 clean
check "a green pull request nobody armed is reported with the check it waits on" \
  "$(printf 'Kolonie-AI/kolonie-docs\t274\tcheck')" \
  "$(bash "$SCRIPT" unarmed-pull-requests 2>/dev/null)"

# The rule the whole thing hangs on. The repositories are public and anybody may
# open a pull request; a sweep that armed those would be a supply chain with a
# schedule.
case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$theirs|null"
check "a fork's pull request is never armed" "" \
  "$(bash "$SCRIPT" unarmed-pull-requests 2>/dev/null)"

case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|null|null"
check "and neither is one whose fork has been deleted" "" \
  "$(bash "$SCRIPT" unarmed-pull-requests 2>/dev/null)"

case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|true|$mine|null"
check "a draft is how an author says not yet, and it still is" "" \
  "$(bash "$SCRIPT" unarmed-pull-requests 2>/dev/null)"

case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" '274|false|'"$mine"'|{"enabled_by":{"login":"colette"}}'
check "one the worker already armed costs the sweep nothing" "" \
  "$(bash "$SCRIPT" unarmed-pull-requests 2>/dev/null)"

# `#326`. The two ways to say *this one waits for me* on a pull request that is
# already open, already green and no longer a draft.
case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null|blocked:human"
mergeability "Kolonie-AI/kolonie-docs" 274 clean
check "blocked:human takes a pull request out of the sweep" "" \
  "$(bash "$SCRIPT" unarmed-pull-requests 2>/dev/null)"

case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null|bug,area:infra"
mergeability "Kolonie-AI/kolonie-docs" 274 clean
contains "and any other label leaves it exactly as it was" \
  "274" "$(bash "$SCRIPT" unarmed-pull-requests 2>/dev/null)"

# The one that cost a production deploy: disarmed at 06:33, armed again at 06:41.
case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 clean
timeline "Kolonie-AI/kolonie-docs" 274 labeled auto_merge_enabled auto_merge_disabled commented
out=$(bash "$SCRIPT" unarmed-pull-requests 2>"$WORK/err")
check "a disarm sticks, and the sweep never arms it again" "" "$out"
contains "and it says a person did that on purpose" "somebody disarmed" "$(cat "$WORK/err")"

case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 clean
timeline "Kolonie-AI/kolonie-docs" 274 labeled commented reviewed
contains "an ordinary timeline is not a disarm" \
  "274" "$(bash "$SCRIPT" unarmed-pull-requests 2>/dev/null)"

# `#480`. **Closing a pull request disables auto-merge, and reopening does not
# put it back** — so the timeline of a close-and-reopen carries an
# `auto_merge_disabled` nobody decided. `#326` then concluded *a person wants
# this to wait* for ever, and the pull request stayed green, open and nobody's.
# `kolonie-platform#1534`, 2026-08-21: closed at 17:49:14, disarmed at 17:49:15,
# reopened at 17:49:20.
case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 clean
timeline "Kolonie-AI/kolonie-docs" 274 auto_merge_enabled closed auto_merge_disabled reopened commented
out=$(bash "$SCRIPT" unarmed-pull-requests 2>"$WORK/err")
contains "a disarm a reopen came after is stale, and the sweep arms it again" \
  "274" "$out"
absent "and it does not claim a person decided anything" \
  "somebody disarmed" "$(cat "$WORK/err")"

# The other order, which is what keeps `#326` intact: a person who disarms a
# pull request that was reopened earlier has decided something about the pull
# request as it stands now.
case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 clean
timeline "Kolonie-AI/kolonie-docs" 274 closed reopened auto_merge_enabled auto_merge_disabled commented
out=$(bash "$SCRIPT" unarmed-pull-requests 2>"$WORK/err")
check "a disarm after the last reopen still sticks" "" "$out"
contains "and still says a person did that on purpose" \
  "somebody disarmed" "$(cat "$WORK/err")"

# Twice round, because the rule is *the last of the two events wins* and a rule
# that only looked at the first pair would read this one backwards.
case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 clean
timeline "Kolonie-AI/kolonie-docs" 274 auto_merge_disabled reopened auto_merge_disabled commented
out=$(bash "$SCRIPT" unarmed-pull-requests 2>"$WORK/err")
check "and the last of several decides it" "" "$out"

# On a green pull request arming is merging, so not knowing is a reason to stop.
case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 clean
echo "the timeline read fails this case" > "$GH_FIXTURES/timeline_fail"
out=$(bash "$SCRIPT" unarmed-pull-requests 2>"$WORK/err")
check "a timeline that cannot be read fails closed" "" "$out"
contains "and says the disarm is what it could not establish" \
  "whether anybody disarmed it is unknown" "$(cat "$WORK/err")"

# `#331`. Branch protection binds the branch it is configured on, so filter 4's
# answer says nothing about a pull request into a feature branch — arming one
# merges it in the same second, unbuilt. `kolonie-platform#847`, 2026-08-13.
case_setup
# The required context is named distinctively here, because the assertion below
# is that this exact string does *not* reach the log: the sentence the sweep used
# to print named the check it was waiting for, on a pull request where that check
# was never going to run at all.
org "Kolonie-AI/kolonie-docs|format, lint, build, typecheck, test"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null||feat/stacked-on-273"
mergeability "Kolonie-AI/kolonie-docs" 274 clean
out=$(bash "$SCRIPT" unarmed-pull-requests 2>"$WORK/err")
check "a pull request into a feature branch is never armed" "" "$out"
contains "and the reason is the branch it targets" \
  "targets feat/stacked-on-273 rather than main" "$(cat "$WORK/err")"
absent "and no check name is named, because none can report" \
  "format, lint, build, typecheck, test" "$(cat "$WORK/err")"

case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null||main"
mergeability "Kolonie-AI/kolonie-docs" 274 clean
contains "one into the default branch is armed exactly as before" \
  "274" "$(bash "$SCRIPT" unarmed-pull-requests 2>/dev/null)"

# The default branch is read per repository rather than assumed, so a repository
# that calls it something else is swept rather than skipped.
case_setup
org "Kolonie-AI/kolonie-skill-hermes|check|trunk"
opened "Kolonie-AI/kolonie-skill-hermes" "9|false|{\"full_name\":\"Kolonie-AI/kolonie-skill-hermes\"}|null||trunk"
mergeability "Kolonie-AI/kolonie-skill-hermes" 9 clean
contains "the default branch is whatever the repository says it is" \
  "9" "$(bash "$SCRIPT" unarmed-pull-requests 2>/dev/null)"

case_setup
org "Kolonie-AI/kolonie-skill-hermes|check|trunk"
opened "Kolonie-AI/kolonie-skill-hermes" "9|false|{\"full_name\":\"Kolonie-AI/kolonie-skill-hermes\"}|null||main"
mergeability "Kolonie-AI/kolonie-skill-hermes" 9 clean
out=$(bash "$SCRIPT" unarmed-pull-requests 2>"$WORK/err")
check "and there main is the feature branch" "" "$out"
contains "which the refusal says in those words" \
  "targets main rather than trunk" "$(cat "$WORK/err")"

# The refusal `#232` already makes where the worker opens its own pull requests.
# Arming here would land the branch the instant it was enabled.
case_setup
org "Kolonie-AI/kolonie-email|"
opened "Kolonie-AI/kolonie-email" "5|false|{\"full_name\":\"Kolonie-AI/kolonie-email\"}|null"
mergeability "Kolonie-AI/kolonie-email" 5 clean
out=$(bash "$SCRIPT" unarmed-pull-requests 2>"$WORK/err")
check "a repository whose main requires nothing arms nothing" "" "$out"
contains "and says why it was left alone" "no required status check" "$(cat "$WORK/err")"

# `blocked` is a required check that has not reported, which is precisely what
# auto-merge is for. Skipping it would make the sweep arm only what needs it
# least.
case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 blocked
contains "a check that has not reported yet is exactly the case for arming" \
  "274" "$(bash "$SCRIPT" unarmed-pull-requests 2>/dev/null)"

case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 dirty dirty
out=$(bash "$SCRIPT" unarmed-pull-requests 2>"$WORK/err")
check "GitHub refuses to arm a conflicting one, so the sweep does not ask" "" "$out"
contains "and says that is what it is" "conflicts with main" "$(cat "$WORK/err")"

# ## A `dirty` that is no longer true (`#484`)
#
# Measured 2026-08-22: `kolonie-platform#1604` read `DIRTY` from 12:29 to about
# 14:00 while three other pull requests merged beneath it, and `git merge-tree`
# against the `main` of that moment produced a tree with no conflict at 13:39. It
# merged clean and GitHub reported a conflict for another twenty minutes.
#
# `mergeable_state` is computed at a moment and is correct for that moment. What
# was wrong is reading it as current ninety minutes later — and the sweep runs
# hourly and re-read the same field, so a verdict stale for ninety minutes was
# skipped on every pass.
#
# **The first read is what makes GitHub recompute.** Asking again is the whole
# fix: a stale verdict answers differently the second time, and a real conflict
# answers `dirty` again and costs one request.

case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 dirty clean
out=$(bash "$SCRIPT" unarmed-pull-requests 2>"$WORK/err")
contains "a dirty that recomputes to clean is armed rather than skipped" "274" "$out"
contains "and the sweep says it did not trust the cached verdict" \
  "recomputed" "$(cat "$WORK/err")"

case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 dirty blocked
out=$(bash "$SCRIPT" unarmed-pull-requests 2>"$WORK/err")
contains "and one that recomputes to blocked is armed too — a check pending is the case for arming" \
  "274" "$out"

# The cost of the recompute, stated so nobody removes it as a spare request: it
# is one extra read per `dirty` pull request per pass, and `dirty` is rare.
case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 clean
bash "$SCRIPT" unarmed-pull-requests >/dev/null 2>&1
check "a clean pull request is read exactly once, so the recompute costs nothing on a quiet day" \
  "1" "$(grep -c 'repos/Kolonie-AI/kolonie-docs/pulls/274 ' "$GH_LOG")"

# And the other half of that number: a dirty one costs exactly one extra read,
# not a poll. A loop here would be an hourly sweep waiting on GitHub's scheduler.
case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 dirty dirty
bash "$SCRIPT" unarmed-pull-requests >/dev/null 2>&1
check "a dirty one is read twice and never more" \
  "2" "$(grep -c 'repos/Kolonie-AI/kolonie-docs/pulls/274 ' "$GH_LOG")"

# ## Say how long (`#484`)
#
# Ninety minutes passed with nothing anywhere saying so, and it was found by
# hand. A pull request that has read `dirty` for more than an hour is worth one
# line beside the count `#480` added — whatever the verdict turns out to be,
# because the point is that nobody should have to go looking.

case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 dirty dirty
pull_updated "Kolonie-AI/kolonie-docs" 274 "2020-01-01T00:00:00Z"
out=$(bash "$SCRIPT" unarmed-pull-requests 2>"$WORK/err")
contains "one that has been dirty for over an hour is visible without anybody looking" \
  "has read dirty for" "$(cat "$WORK/err")"
contains "and the line names the pull request" "274" "$(cat "$WORK/err")"

case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 dirty dirty
pull_updated "Kolonie-AI/kolonie-docs" 274 "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"
out=$(bash "$SCRIPT" unarmed-pull-requests 2>"$WORK/err")
absent "one that has just gone dirty is not, because a fresh conflict is ordinary" \
  "has read dirty for" "$(cat "$WORK/err")"
contains "and it is still reported as conflicting" "conflicts with main" "$(cat "$WORK/err")"

case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 dirty dirty
out=$(bash "$SCRIPT" unarmed-pull-requests 2>"$WORK/err")
check "an unreadable age does not stop the sweep" "" "$out"
contains "and the pull request is still reported" "conflicts with main" "$(cat "$WORK/err")"

case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 unknown
out=$(bash "$SCRIPT" unarmed-pull-requests 2>"$WORK/err")
check "an uncomputed mergeability is not an answer here either" "" "$out"
contains "and the run waits rather than deciding" \
  "has not computed mergeability yet" "$(cat "$WORK/err")"

# Not the worker's own pull requests: every open one in the organisation that
# survives the four filters, in every repository.
case_setup
org "Kolonie-AI/kolonie-docs|check" "Kolonie-AI/kolonie-platform|build, test"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
opened "Kolonie-AI/kolonie-platform" \
  '700|false|{"full_name":"Kolonie-AI/kolonie-platform"}|null' \
  '701|true|{"full_name":"Kolonie-AI/kolonie-platform"}|null'
mergeability "Kolonie-AI/kolonie-docs" 274 clean
mergeability "Kolonie-AI/kolonie-platform" 700 blocked
out=$(bash "$SCRIPT" unarmed-pull-requests 2>/dev/null)
check "the sweep is organisation-wide" "2" "$(grep -c . <<<"$out")"
contains "and carries each repository's own required contexts" \
  "kolonie-platform	700	build, test" "$out"

case_setup
echo yes > "$GH_FIXTURES/repos_fail"
out=$(bash "$SCRIPT" unarmed-pull-requests 2>/dev/null); rc=$?
check "an organisation that cannot be listed arms nothing" "" "$out"
check "and the caller is told, so the run can carry on" "1" "$rc"

case_setup
org "Kolonie-AI/kolonie-docs|check" "Kolonie-AI/kolonie-platform|check"
opened "Kolonie-AI/kolonie-platform" '700|false|{"full_name":"Kolonie-AI/kolonie-platform"}|null'
mergeability "Kolonie-AI/kolonie-platform" 700 clean
echo yes > "$GH_FIXTURES/pulls_fail_Kolonie-AI_kolonie-docs"
out=$(bash "$SCRIPT" unarmed-pull-requests 2>"$WORK/err")
contains "one unreadable repository does not stop the others" "700" "$out"
contains "and it says which one it could not read" "kolonie-docs" "$(cat "$WORK/err")"

case_setup
org "Kolonie-AI/kolonie-docs|check"
opened "Kolonie-AI/kolonie-docs" "274|false|$mine|null"
mergeability "Kolonie-AI/kolonie-docs" 274 clean
bash "$SCRIPT" unarmed-pull-requests >/dev/null 2>&1
log=$(cat "$GH_LOG")
contains "the sweep asks what main requires before it reports anything" \
  "branches/main/protection" "$log"
absent "the script never arms anything itself — that is the workflow's, on the repo token" \
  "pr merge" "$log"
absent "and it never merges past the check with --admin" "--admin" "$log"

echo
echo "what it never does"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2"
boarded "10:Ready"
bash "$SCRIPT" pick >/dev/null 2>&1
bash "$SCRIPT" claim Kolonie-AI/kolonie-docs 10 >/dev/null 2>&1
bash "$SCRIPT" review Kolonie-AI/kolonie-docs 10 >/dev/null 2>&1
bash "$SCRIPT" release Kolonie-AI/kolonie-docs 10 >/dev/null 2>&1
log=$(cat "$GH_LOG")
absent "never removes the queue label" "remove-label" "$log"
absent "never edits a label at all" "issue edit" "$log"
absent "never comments — that is GITHUB_TOKEN's job in the workflow" "issue comment" "$log"
# The *script* never merges and never pushes. Since `#232` the **workflow** does
# enable auto-merge, deliberately — but the queue logic must stay incapable of
# it, because this is the file that runs with the board credential.
absent "the queue logic never merges — auto-merge is the workflow's, on GITHUB_TOKEN" "pr merge" "$log"
absent "never pushes" "push" "$log"

echo
echo "the workflow cannot merge past a failing check (#232)"

WORKFLOW="$ROOT/.github/workflows/opencode-worker.yml"

wf=$(cat "$WORKFLOW")
# Comments stripped before the forbidden-flag assertions, because the workflow
# *explains* why it does not use `--admin` and an assertion that cannot tell the
# explanation from the flag would forbid writing the reasoning down. That trade
# goes the other way: the reasoning is the part that stops somebody adding the
# flag back next year.
wf_commands=$(grep -v '^[[:space:]]*#' "$WORKFLOW")
absent "no --admin on any command in the workflow" "--admin" "$wf_commands"
absent "no force push" "push --force" "$wf_commands"
absent "and no force-with-lease either" "force-with-lease" "$wf_commands"
contains "auto-merge is queued, never waited on" "--auto --squash" "$wf"
contains "and it is gated on the target having a required check" \
  "branches/main/protection" "$wf"

# `#276` withdrew `#263`: there is no class of change the worker opens that waits
# for a person, and the assertion is that no path list grows back into one. It is
# on the commands rather than the file so the reasoning above may still be
# written down — which is where `#263` is recorded, and where anybody proposing
# it again should start.
absent "no diff is held back from auto-merge" "merge-gate" "$wf_commands"
absent "and nothing branches on a gated path" 'if [ -n "$gated" ]' "$wf_commands"

# `#275`: the arming the workflow does for pull requests it did not open. The
# sweep itself is tested against the stub above; what only the file can carry is
# that the workflow runs it, and on which credential.
contains "the workflow sweeps the pull requests it did not open" \
  "opencode-worker.sh unarmed-pull-requests" "$wf_commands"
contains "and arms them on the token that reaches another repository" \
  "gh pr merge \"\$pr\" --repo \"\$repo\" --auto --squash" "$wf_commands"

# `#245`: the two places a failure is announced both have to carry the reason.
# Neither can be executed by a test, so both are asserted on the file.
contains "a failed run writes a job summary" "GITHUB_STEP_SUMMARY" "$wf"
contains "and the comment carries the excerpt, not only a link" \
  "steps.why.outputs.excerpt" "$wf"
contains "and names the step that failed" "steps.why.outputs.step" "$wf"
# The sentence `previous-failures` counts. Changing it here without changing it
# in the script makes every failure before that day invisible to the count —
# which is exactly what `50ae76a` did by dropping the word *hourly* from the
# comment and not from the marker. The needle is now the part of the sentence
# that survives a cadence change, and this asserts both halves still carry it.
contains "the failure comment still opens with the sentence the count matches" \
  "opencode worker failed on this issue" "$wf"
contains "and it is the same sentence the script looks for" \
  "opencode worker failed on this issue" "$(cat "$SCRIPT")"

# `#246`: three properties of the workflow that only the file can carry.
contains "the model runs without the repository token in its environment" \
  "env -u GH_TOKEN opencode run" "$wf_commands"
contains "the worker's files live in the scratch directory, not the checkout" \
  "SCRATCH=/tmp/opencode" "$wf_commands"
absent "and #244's exclude workaround is gone with them" \
  ".git/info/exclude" "$wf_commands"
contains "and nothing is published before the leak check has passed" \
  "leak-check" "$wf_commands"
leak_line=$(grep -n 'opencode-worker.sh leak-check' "$WORKFLOW" | head -1 | cut -d: -f1)
push_line=$(grep -n 'git push --set-upstream' "$WORKFLOW" | head -1 | cut -d: -f1)
if [ -n "$leak_line" ] && [ -n "$push_line" ] && [ "$leak_line" -lt "$push_line" ]; then
  echo "  ok   the leak check runs before the push, not merely before the pull request"
else
  echo "  FAIL the leak check runs before the push, not merely before the pull request"
  echo "         leak check at line ${leak_line:-none}, push at line ${push_line:-none}"
  FAILURES+=("the leak check runs before the push")
fi

# The named-directory grant, and it is a grant rather than an opening: `/tmp`
# itself stays denied. The 2026-08-07 refusal asked for `/tmp/*`, which is
# *everything a runner keeps in `/tmp`*.
config=$(cat "$ROOT/opencode.json")
contains "the scratch directory is granted by name" '"/tmp/opencode/*": "allow"' "$config"
contains "and everything else outside the checkout is denied, not asked" \
  '"external_directory"' "$config"
if jq -e '.permission.external_directory["*"] == "deny"' "$ROOT/opencode.json" >/dev/null; then
  echo "  ok   the wider grant is refused explicitly rather than left to a default"
else
  echo "  FAIL the wider grant is refused explicitly rather than left to a default"
  FAILURES+=("external_directory defaults to deny")
fi
if jq -e '.permission.external_directory | has("/tmp/*") or has("/tmp") | not' "$ROOT/opencode.json" >/dev/null; then
  echo "  ok   and /tmp itself is not granted"
else
  echo "  FAIL and /tmp itself is not granted"
  FAILURES+=("/tmp is not granted")
fi

# `#247`: the prerequisite is worthless if it runs after the check. A `run:`
# block cannot be executed by a test, so the ordering is asserted on the file.
contains "the workflow reads the target's check prerequisite" "check-prerequisite" "$wf"
prereq_line=$(grep -n 'CHECK_PREREQUISITE:-' "$WORKFLOW" | head -1 | cut -d: -f1)
check_line=$(grep -n 'eval "\$CHECK_COMMAND"' "$WORKFLOW" | head -1 | cut -d: -f1)
if [ -n "$prereq_line" ] && [ -n "$check_line" ] && [ "$prereq_line" -lt "$check_line" ]; then
  echo "  ok   and runs it before the check, not after"
else
  echo "  FAIL and runs it before the check, not after"
  echo "         prerequisite at line ${prereq_line:-none}, check at line ${check_line:-none}"
  FAILURES+=("the prerequisite runs before the check")
fi

# `#251`: a failing issue leaves the queue rather than being retried forever.
contains "a failed run takes the label off the issue it took" \
  "--remove-label agent:opencode" "$wf"
contains "and says so in the comment, as something a person reverses" \
  "back once the reason above is dealt with" "$wf"
contains "a removal that failed is reported rather than swallowed" \
  "could not be removed" "$wf"
contains "and the counter now finds a second failure worth naming" \
  '"$failures" -ge 2' "$wf"

# `#253`: four failure endings, four sentences. Three of these shared one verdict
# and it was true of exactly one of them.
contains "a refusal is announced as a refusal" \
  "The model declined this issue and committed nothing" "$wf"
contains "and says explicitly that nothing failed a check" \
  "nothing was built, so nothing failed a check" "$wf"
contains "an empty run is its own case" \
  "The model committed nothing and did not say why" "$wf"
contains "a red check keeps the sentence that was always true of it" \
  "The change did not pass" "$wf"
contains "the model's refusal is recorded under its own kind" \
  "fail refused" "$wf"
contains "and a commitless run under its own" \
  "fail empty" "$wf"

# `#255`: a failure leaves a mark the board can be filtered on.
contains "a failed run sets the mark as it takes the queue label off" \
  "--remove-label agent:opencode --add-label opencode:failed" "$wf"
contains "and both edits are one call, so no window shows neither" \
  "Both edits in one call" "$wf"
contains "taking an issue clears the mark" \
  "--remove-label opencode:failed" "$wf"
contains "and clearing it cannot cost the claim" \
  ">/dev/null 2>&1 || true" "$wf"
# The literal in the workflow carries backslash-escaped backticks, so this
# matches the part of the sentence that has none.
contains "the comment says what the board now shows" \
  "goes back to **Ready**, loses" "$wf"

# `#257`: the branch is rebased onto the `main` that exists, and a conflict ends
# the run rather than opening a pull request that cannot merge.
contains "the run fetches main again before it publishes anything" \
  "+refs/heads/main:refs/remotes/origin/main" "$wf_commands"
contains "and rebases onto it" "git rebase origin/main" "$wf_commands"
contains "a conflict aborts" "git rebase --abort" "$wf_commands"
contains "and is reported as work rather than as a worker fault" \
  "the change no longer applies to" "$wf"
contains "naming the paths that conflicted" \
  "--diff-filter=U" "$wf_commands"
absent "no run resolves a conflict" "rebase --continue" "$wf_commands"
absent "and none takes theirs or ours to get past one" "-X ours" "$wf_commands"
rebase_line=$(grep -n 'git rebase origin/main' "$WORKFLOW" | head -1 | cut -d: -f1)
if [ -n "$rebase_line" ] && [ -n "$push_line" ] && [ "$rebase_line" -lt "$push_line" ]; then
  echo "  ok   the rebase happens before the push, so the pull request opens against current main"
else
  echo "  FAIL the rebase happens before the push, so the pull request opens against current main"
  echo "         rebase at line ${rebase_line:-none}, push at line ${push_line:-none}"
  FAILURES+=("the rebase runs before the push")
fi
if [ -n "$rebase_line" ] && [ -n "$check_line" ] && [ "$check_line" -lt "$rebase_line" ]; then
  echo "  ok   and after the target's check, which is the window it exists to close"
else
  echo "  FAIL and after the target's check, which is the window it exists to close"
  echo "         check at line ${check_line:-none}, rebase at line ${rebase_line:-none}"
  FAILURES+=("the rebase runs after the check")
fi

# `#232` closed on the measurement that auto-merge runs unattended, and the
# comment the worker writes on every issue it takes said the opposite until
# then. A sentence a citizen reads on fifteen issues a day is worth an assertion.
absent "the claim comment no longer promises a review that does not happen" \
  "a person reviews and merges" "$wf"

# `#256`: the sweep runs before the queue is read, on the two credentials, and
# nothing about it may cost this run its issue.
contains "the workflow sweeps its own stuck pull requests" "stale-pull-requests" "$wf_commands"
contains "and gives the issue back to Ready with the failure mark" \
  "--remove-label agent:opencode --add-label opencode:failed" "$wf_commands"
contains "the branch answer is one and it is stated" "--delete-branch" "$wf_commands"
contains "a sweep that cannot reach the API warns rather than failing" \
  "the stale-pull-request sweep could not read the API" "$wf"
sweep_line=$(grep -n 'opencode-worker.sh stale-pull-requests' "$WORKFLOW" | head -1 | cut -d: -f1)
pick_line=$(grep -n 'opencode-worker.sh pick' "$WORKFLOW" | head -1 | cut -d: -f1)
if [ -n "$sweep_line" ] && [ -n "$pick_line" ] && [ "$sweep_line" -lt "$pick_line" ]; then
  echo "  ok   the sweep runs before the queue is read, so a stuck issue can be picked again"
else
  echo "  FAIL the sweep runs before the queue is read, so a stuck issue can be picked again"
  echo "         sweep at line ${sweep_line:-none}, pick at line ${pick_line:-none}"
  FAILURES+=("the sweep runs before pick")
fi
# `set -e` in the sweep step would make a single unreachable pull request cost
# this run the issue it was going to work, which is the trade `#256` refuses.
# **`set +e`, asserted positively.** This used to assert the *absence* of
# `set -euo`, which was necessary and not sufficient: GitHub invokes a `run:`
# block with `bash -e {0}`, so a step that merely declines to set `-e` still has
# it. Run `31377996406` reported five completions and then died at `exit 141`
# from a `gh … | head` closing its own pipe, taking the queue work with it.
if grep -q 'set +e' <<<"$(step_block 'name: Is a pull request of mine stuck' 'name: Put the stuck')"; then
  echo "  ok   the sweep step turns off the -e the runner's own shell brings"
else
  echo "  FAIL the sweep step turns off the -e the runner's own shell brings"
  FAILURES+=("the sweep step does not set +e")
fi

# `#258`: a merged pull request tells its issue so, exactly once, and only after
# the merge.
contains "the workflow reports what landed" "unreported-completions" "$wf_commands"
contains "and the comment opens with the marker that makes it idempotent" \
  "Completed by the opencode worker in" "$wf"
contains "it says which pull request delivered it" "pull/" "$wf"
contains "and how the result was verified" "passed on the branch before the pull request was opened" "$wf"
contains "and distinguishes landed from merely started" \
  "landed" "$wf"
contains "the branch and the body are cross-checked before anything is written" \
  "branch says" "$wf_commands"
contains "a comment that could not be written does not misrepresent the merge" \
  "the merge stands and the next run will try again" "$wf"
landed_line=$(grep -n 'opencode-worker.sh unreported-completions' "$WORKFLOW" | head -1 | cut -d: -f1)
if [ -n "$landed_line" ] && [ -n "$pick_line" ] && [ "$landed_line" -lt "$pick_line" ]; then
  echo "  ok   the completion sweep runs before the queue, on previous runs' work"
else
  echo "  FAIL the completion sweep runs before the queue, on previous runs' work"
  FAILURES+=("the completion sweep runs before pick")
fi
if grep -q 'set +e' <<<"$(step_block 'name: Say what landed' 'name: Is there anything to do')"; then
  echo "  ok   reporting a completion cannot cost this run its issue"
else
  echo "  FAIL reporting a completion cannot cost this run its issue"
  FAILURES+=("the completion step does not set +e")
fi
# The `exit 141` in run `31377996406` came from a paginated read whose reader
# closed the pipe. Asking the API for the number of rows wanted has no pipe to
# close, and the bound stays where it was.
absent "and nothing in either sweep closes a pipe on a paginated read" \
  "--paginate --jq '.[].filename'" "$wf_commands"
# The whole design refuses to paraphrase the change, so no model may be reached
# from the reporting path — the summary is derived or it is not written.
absent "no model is asked to summarise the work it produced" "opencode run" \
  "$(step_block 'name: Say what landed' 'name: Is there anything to do')"

# `#254`: a red check gets an account of what broke, on that ending only, and
# nothing about producing one may cost the comment that has to be written.
why_step=$(step_block 'name: What failed, and why' 'name: Say why on the issue')
contains "a red check is read by the model that caused it" "failure-digest" "$why_step"
contains "and only that ending" '"$kind" = work' "$why_step"
contains "the call is bounded in time" "timeout 120 opencode run" "$why_step"
contains "the model runs with bash denied, so it cannot print its own environment" \
  '.permission.bash = {"*": "deny"}' "$why_step"
contains "and with no instructions file to pull in a repository's context" \
  "del(.instructions)" "$why_step"
contains "what it wrote is filtered before it is published" \
  "opencode-worker.sh redact" "$why_step"
contains "a call that fails leaves a missing paragraph and says so" \
  "the comment goes without one" "$why_step"
contains "the account is attributed, not presented as a finding" \
  "The model's account of why the check failed" "$wf"
contains "and the attribution says it did not read the diff" \
  "it did not review the diff" "$wf"
# The refusal is the artefact and a paraphrase of it is a loss, so the account
# must not be produced on that ending. `kind` is the only thing separating them.
# `#250`: the backstop, and the one ending that does not invite another attempt.
contains "a refusal is checked against the worker's own rules" \
  "worker-rule-refusal" "$why_step"
contains "and only a refusal is" '"$kind" = refused' "$why_step"
contains "a worker-rule refusal marks the issue" "--add-label opencode:forbidden" "$wf_commands"
contains "and the comment says a fourth attempt would produce the same words" \
  "would produce the same words" "$wf"
contains "and says what actually unblocks it" \
  "out of the queue until a person changes something" "$wf"
# The exclusion is in `pick`'s own filter rather than in the search query, so a
# label somebody re-applies cannot put the issue back in the queue. The
# behavioural cases above prove the effect; this proves it is where it has to be.
contains "the exclusion is in the queue filter, not in the search term" \
  'index($forbidden) | not' "$(cat "$SCRIPT")"
# It is set and never cleared by the worker: every other mark here has a run
# that clears it, and this one is a person's to remove.
absent "the worker never clears it for you" "--remove-label opencode:forbidden" "$wf_commands"

refusal_guarded=$(grep -c 'kind" = work' <<<"$why_step")
if [ "$refusal_guarded" -ge 1 ]; then
  echo "  ok   a refusal keeps its own words, unsummarised"
else
  echo "  FAIL a refusal keeps its own words, unsummarised"
  FAILURES+=("the account is guarded on kind=work")
fi
contains "and says what actually happens to the pull request" \
  "merges itself when the target's required check goes green" "$wf"

# The prohibition named the workflow and not the script that holds `pick`,
# `claim` and `release` — the selection and the lock.
contains "the worker may not rewrite its own queue script" \
  ".github/scripts/opencode-worker.sh" "$wf_commands"

# The per-repository courtesy: a repository with something In Progress is one no
# second run may take work from. Every conflict this worker has had was two runs
# in one repository; two runs in different ones share no history.
contains "pick reads which repositories are already in flight" \
  'select(.status == "In Progress")' "$(cat "$SCRIPT")"
contains "and skips candidates from them" \
  'select(.repo as $r | $busy | index($r) | not)' "$(cat "$SCRIPT")"

# `#259`: a failure must never leave an issue with no `agent:` label at all.
contains "a failed run routes the issue onward rather than orphaning it" \
  "--add-label opencode:failed --add-label agent:claude" "$wf"
contains "and the conflict sweep does the same" \
  "--add-label opencode:failed --add-label agent:claude \\" "$wf"

echo
echo "board-add tells a failed call apart from an honest empty answer (#422)"

# ## Why these cases are worth the stub
#
# Every assertion below is about a path where GitHub answered and the answer was
# not a value. `gh api graphql` writes its `errors` document to **stdout** and
# exits non-zero, so `out=$(gh ... --jq '... // empty' 2>/dev/null)` followed by
# `[ -n "$out" ]` reads the error blob as a value and carries on with it. That
# shape is invisible in review — it looks like a guard — and it is green in every
# run where the API behaves. The stub is the only way to make the API misbehave.
#
# The exit codes are asserted rather than only the messages, because `board-add`
# is called from workflows that branch on them: *did not run* and *does not
# exist* want different responses from whoever is reading.

case_setup
printf '%s\n' yes > "$GH_FIXTURES/graphql_fails"
out=$(bash "$SCRIPT" board-add kolonie-hermes 12 2>&1); rc=$?
check "a query that did not run exits 2" "2" "$rc"
contains "and says so, rather than saying the issue does not exist" \
  "did not run" "$out"
absent "and nothing is added on the strength of an error document" \
  "addProjectV2ItemById" "$(cat "$GH_LOG")"

case_setup
printf '%s\n' "kolonie-hermes#12" > "$GH_FIXTURES/unreadable_issues"
out=$(bash "$SCRIPT" board-add kolonie-hermes 12 2>&1); rc=$?
check "an issue that really is not there exits 3, which is a different answer" "3" "$rc"
contains "and names what is missing" "does not exist" "$out"
absent "and adds nothing, because there is nothing to add" \
  "addProjectV2ItemById" "$(cat "$GH_LOG")"

# The repository argument, in both shapes. `board-item-id.sh` in the same
# directory takes a bare name and this took a qualified one, so a reader had to
# remember which script wanted which. Both now work and both mean the same board.
case_setup
jq -cn '{items: []}' > "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" board-add kolonie-hermes 12 2>&1); rc=$?
check "a bare repository name is accepted" "0" "$rc"
contains "and is asked about under the organisation" \
  "-f owner=Kolonie-AI -f name=kolonie-hermes" "$(cat "$GH_LOG")"
contains "and the issue lands in Inbox rather than in no column" \
  "in Inbox" "$out"

case_setup
jq -cn '{items: []}' > "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" board-add Kolonie-AI/kolonie-hermes 12 2>&1); rc=$?
check "the qualified shape still works and means the same thing" "0" "$rc"
contains "the same issue, the same owner" \
  "-f owner=Kolonie-AI -f name=kolonie-hermes" "$(cat "$GH_LOG")"

# The rejection case: an argument that is neither shape is refused by name at the
# first line, rather than queried for and reported as a missing issue.
case_setup
out=$(bash "$SCRIPT" board-add Kolonie-AI/kolonie-docs/agents 12 2>&1); rc=$?
check "an argument that is no repository is refused" "1" "$rc"
contains "and the refusal shows both shapes it would have taken" \
  "is not a repository" "$out"
absent "and nothing is asked of GitHub about it" "api graphql" "$(cat "$GH_LOG")"

# ## The column that could not be set, and what may be said about it
#
# `#422` again, on the other side of the same argument as `release` (`#381`): the
# message used to assert *on the board and in no column* on a run where the add
# had not happened, and sent a reader looking for a card that was not there. The
# board is read back before anything is claimed about it — and the read-back can
# itself fail, which is a third answer and not the second one.
case_setup
printf '%s\n' yes > "$GH_FIXTURES/edit_fails"
jq -cn '{items: [ {id: "PVTI_added_kolonie-hermes12", status: "Ready", labels: [],
  content: {number: 12, repository: "Kolonie-AI/kolonie-hermes"}} ]}' > "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" board-add kolonie-hermes 12 2>&1); rc=$?
check "a column that could not be set exits 5" "5" "$rc"
contains "and names the column the board actually shows" "it is in Ready" "$out"

case_setup
printf '%s\n' yes > "$GH_FIXTURES/edit_fails"
jq -cn '{items: []}' > "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" board-add kolonie-hermes 12 2>&1); rc=$?
contains "an issue the board does not show is not claimed to be on it" \
  "does not show it at all" "$out"
absent "and the old wording, which asserted the opposite, is gone" \
  "is on the board and its column could not be set" "$out"

# No board fixture at all is a failed read in this stub, which is the third
# answer: the write failed and the board could not be asked about it either.
case_setup
printf '%s\n' yes > "$GH_FIXTURES/edit_fails"
out=$(bash "$SCRIPT" board-add kolonie-hermes 12 2>&1); rc=$?
contains "a read-back that fails says the board could not be asked" \
  "could not be asked where it ended up" "$out"
absent "and does not report a column it never read" "it is in " "$out"

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "all good"
  exit 0
fi
echo "${#FAILURES[@]} failed:"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

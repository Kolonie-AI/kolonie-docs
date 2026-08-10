#!/bin/bash
# Does a red worker pull request give its issue back, and only ever its own?
#
# Usage: bash .github/tests/opencode-red.test.sh
#
# `#240` turns on four properties that a green run cannot show: that an
# inconclusive check moves nothing, that a pull request on any other branch is
# left alone, that a second report does not comment twice, and that
# `agent:opencode` is never touched. Each is a branch that would look fine in
# review and be wrong in production — the last one silently, for a week.
#
# Stubbed `gh`, for `opencode-worker.test.sh`'s reason: it is the only way to
# exercise a board write that fails without breaking the board, and the stub logs
# every invocation so the label assertion is exhaustive rather than a reading of
# the script.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/opencode-red.sh"
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export GITHUB_REPOSITORY="Kolonie-AI/kolonie-docs"
export RUN_URL="https://example.invalid/run/1"
# The board's own project id. `opencode-red.sh` and the `board-item-id.sh` it
# calls after `#271` both default to this one; exporting it is what stops the
# stub and the lookup under test disagreeing about which project a card is on,
# which would pass as *not on the board* in every case below.
export PROJECT_ID="PVT_kwDOEmwuYs4BebbB"

mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "pr view")
    if [ -s "$GH_FIXTURES/view_fails" ]; then
      echo "HTTP 404: no such pull request" >&2
      exit 1
    fi
    cat "$GH_FIXTURES/pr" 2>/dev/null ;;
  "pr close")
    if [ -s "$GH_FIXTURES/close_fails" ]; then
      echo "HTTP 403: cannot close" >&2
      exit 1
    fi
    ;;
  # **One item, by repository and number** (`#271`). This script used to read
  # the whole board to find one card; it now asks the issue what it is on,
  # through `board-item-id.sh`, and that is a GraphQL call.
  #
  # The fixture stays in `item-list` shape, so `boarded` below and every
  # assertion are unchanged. The row matching the number the query asked for is
  # reshaped into what that query returns — and `isArchived: false` with the
  # board's own project id, because the lookup filters on both and a fixture
  # that omitted them would answer *not on the board* for every case here.
  "api graphql")
    n=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -F) case "$2" in n=*) n=${2#n=} ;; esac; shift 2 ;;
        *)  shift ;;
      esac
    done
    jq --argjson n "${n:-0}" --arg project "$PROJECT_ID" '
      {data:{repository:{issue:{
        state:"OPEN",
        projectItems:{nodes:[ .items[]
          | select(.content.number == $n)
          | {id:.id, isArchived:false, project:{id:$project},
             fieldValueByName:{name:.status}} ]}}}}}' \
      "$GH_FIXTURES/board" 2>/dev/null ;;
  "project item-edit")
    if [ -s "$GH_FIXTURES/edit_fails" ]; then
      echo "HTTP 401: Bad credentials" >&2
      exit 1
    fi
    ;;
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

# The pull request the event is about.
a_pull_request() {
  local branch=$1 state=${2:-OPEN}
  cat > "$GH_FIXTURES/pr" <<JSON
{"headRefName":"$branch","state":"$state","author":{"login":"github-actions"},
 "url":"https://github.com/Kolonie-AI/kolonie-docs/pull/9"}
JSON
}

# `number:Status` rows on the board, in this repository.
boarded() {
  local items=()
  for row in "$@"; do
    local number=${row%%:*} status=${row#*:}
    items+=("{\"id\":\"PVTI_$number\",\"status\":\"$status\",\"content\":{\"number\":$number,\"repository\":\"$GITHUB_REPOSITORY\"}}")
  done
  local joined
  joined=$(IFS=,; echo "${items[*]}")
  printf '{"items":[%s]}\n' "$joined" > "$GH_FIXTURES/board"
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

echo "a red pull request the worker opened"
case_setup
a_pull_request "opencode/issue-42"
boarded "42:In Review"
bash "$SCRIPT" handle "$GITHUB_REPOSITORY" 9 failure >/dev/null 2>&1
log=$(cat "$GH_LOG")
contains "closes the pull request" "pr close 9" "$log"
contains "moves the item back to Ready" "single-select-option-id ee5ea42c" "$log"
contains "moves the item it looked up, not another" "--id PVTI_42" "$log"
contains "says why, on the issue" "issue comment 42" "$log"

echo
echo "and the order is the one that cannot leave a bad state"
# Ready with an open pull request is what breaks the next run: the branch exists
# and its push fails. So the close has to come first, and a close that fails must
# stop the move.
case_setup
a_pull_request "opencode/issue-42"
boarded "42:In Review"
: > "$GH_FIXTURES/close_fails"
echo x > "$GH_FIXTURES/close_fails"
bash "$SCRIPT" handle "$GITHUB_REPOSITORY" 9 failure >/dev/null 2>&1
status=$?
log=$(cat "$GH_LOG")
check "a close that fails stops the run" 4 "$status"
absent "and the issue is not moved" "item-edit" "$log"

echo
echo "an inconclusive check moves nothing"
for conclusion in success cancelled skipped neutral ""; do
  case_setup
  a_pull_request "opencode/issue-42"
  boarded "42:In Review"
  bash "$SCRIPT" handle "$GITHUB_REPOSITORY" 9 "$conclusion" >/dev/null 2>&1
  log=$(cat "$GH_LOG")
  absent "'${conclusion:-empty}' closes nothing" "pr close" "$log"
  absent "'${conclusion:-empty}' moves nothing" "item-edit" "$log"
done

echo
echo "a timeout is a red"
case_setup
a_pull_request "opencode/issue-42"
boarded "42:In Review"
bash "$SCRIPT" handle "$GITHUB_REPOSITORY" 9 timed_out >/dev/null 2>&1
contains "timed_out is acted on" "pr close 9" "$(cat "$GH_LOG")"

echo
echo "a pull request that is not the worker's is left alone"
for branch in "main" "fix/something" "opencode/issue-abc" "renovate/opencode/issue-42"; do
  case_setup
  a_pull_request "$branch"
  boarded "42:In Review"
  bash "$SCRIPT" handle "$GITHUB_REPOSITORY" 9 failure >/dev/null 2>&1
  log=$(cat "$GH_LOG")
  absent "'$branch' is not closed" "pr close" "$log"
  absent "'$branch' moves no card" "item-edit" "$log"
done

echo
echo "a pull request that is already closed is left alone"
case_setup
a_pull_request "opencode/issue-42" "CLOSED"
boarded "42:In Review"
bash "$SCRIPT" handle "$GITHUB_REPOSITORY" 9 failure >/dev/null 2>&1
log=$(cat "$GH_LOG")
absent "nothing is closed twice" "pr close" "$log"
absent "and nothing is moved" "item-edit" "$log"

echo
echo "reporting twice does not comment twice"
# Checks report more than once and a workflow can be re-run. An issue already
# back in Ready has been handled.
case_setup
a_pull_request "opencode/issue-42"
boarded "42:Ready"
bash "$SCRIPT" handle "$GITHUB_REPOSITORY" 9 failure >/dev/null 2>&1
log=$(cat "$GH_LOG")
absent "an issue already in Ready is not moved again" "item-edit" "$log"
absent "and is not commented on again" "issue comment" "$log"

echo
echo "an issue that is not on the board stops the run"
case_setup
a_pull_request "opencode/issue-42"
boarded "7:Ready"
out=$(bash "$SCRIPT" handle "$GITHUB_REPOSITORY" 9 failure 2>&1)
status=$?
check "it refuses rather than guessing" 3 "$status"
contains "and says which issue" "#42 is not on the board" "$out"

echo
echo "a board write that fails is loud"
case_setup
a_pull_request "opencode/issue-42"
boarded "42:In Review"
echo x > "$GH_FIXTURES/edit_fails"
out=$(bash "$SCRIPT" handle "$GITHUB_REPOSITORY" 9 failure 2>&1)
status=$?
check "it exits 4" 4 "$status"
contains "and names the stuck issue" "COULD NOT RETURN" "$out"
contains "and points at the run" "$RUN_URL" "$out"

echo
echo "the label is never touched, on any path"
for conclusion in failure success cancelled; do
  for branch in "opencode/issue-42" "main"; do
    case_setup
    a_pull_request "$branch"
    boarded "42:In Review"
    bash "$SCRIPT" handle "$GITHUB_REPOSITORY" 9 "$conclusion" >/dev/null 2>&1
    log=$(cat "$GH_LOG")
    absent "$conclusion on $branch removes no label" "remove-label" "$log"
    absent "$conclusion on $branch adds no label" "add-label" "$log"
  done
done

echo
echo "the branch is never deleted"
case_setup
a_pull_request "opencode/issue-42"
boarded "42:In Review"
bash "$SCRIPT" handle "$GITHUB_REPOSITORY" 9 failure >/dev/null 2>&1
log=$(cat "$GH_LOG")
absent "no branch deletion" "--delete-branch" "$log"
absent "no git ref is removed" "api -X DELETE" "$log"

echo
if [ ${#FAILURES[@]} -gt 0 ]; then
  echo "FAILED: ${#FAILURES[@]}"
  printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
echo "all good"

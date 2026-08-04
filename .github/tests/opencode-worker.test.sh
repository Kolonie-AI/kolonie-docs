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
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "issue list")        cat "$GH_FIXTURES/issues" 2>/dev/null ;;
  "project item-list") cat "$GH_FIXTURES/board" 2>/dev/null ;;
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

boarded() {
  # $1.. are `number:Status` pairs.
  local items=()
  for pair in "$@"; do
    items+=("{\"id\":\"ITEM_${pair%%:*}\",\"status\":\"${pair#*:}\",\"content\":{\"number\":${pair%%:*},\"repository\":\"Kolonie-AI/kolonie-docs\"}}")
  done
  local joined
  joined=$(IFS=,; echo "${items[*]}")
  echo "{\"items\":[$joined]}" > "$GH_FIXTURES/board"
}

issued() {
  # $1.. are `number|createdAt|label,label` triples.
  local rows=()
  for row in "$@"; do
    IFS='|' read -r number created labels <<<"$row"
    local labelJson=()
    if [ -n "$labels" ]; then
      IFS=',' read -ra names <<<"$labels"
      for name in "${names[@]}"; do labelJson+=("{\"name\":\"$name\"}"); done
    fi
    local joinedLabels
    joinedLabels=$(IFS=,; echo "${labelJson[*]}")
    rows+=("{\"number\":$number,\"createdAt\":\"$created\",\"labels\":[$joinedLabels]}")
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
check "p1 comes before an older p2" "11" "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2" "11|2026-08-02T00:00:00Z|agent:opencode,p2"
boarded "10:Ready" "11:Ready"
check "at the same priority the oldest goes first" "10" "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2" "11|2026-08-02T00:00:00Z|agent:opencode,p2"
boarded "10:In Progress" "11:Ready"
check "an issue already claimed is not in the queue" "11" "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2"
boarded "10:Backlog"
check "only Ready is the queue — Backlog is not" "" "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p1,blocked:human" "11|2026-08-02T00:00:00Z|agent:opencode,p2"
boarded "10:Ready" "11:Ready"
check "blocked:human is out of the queue however it got the label" "11" "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2"
boarded "10:Ready"
out=$(bash "$SCRIPT" pick 2>/dev/null)
check "exactly one issue is taken per run" "1" "$(wc -w <<<"$out")"

echo
echo "claiming, and the token that stopped working"

case_setup
boarded "10:Ready"
bash "$SCRIPT" claim 10 >/dev/null 2>&1
rc=$?
check "a claim that works exits 0" "0" "$rc"
contains "a claim moves the issue to In Progress" "39185de7" "$(cat "$GH_LOG")"

case_setup
boarded "10:Ready"
echo yes > "$GH_FIXTURES/edit_fails"
err=$(bash "$SCRIPT" claim 10 2>&1 >/dev/null); rc=$?
check "a claim that cannot be written fails the run" "4" "$rc"
contains "and says the token may have expired" "may have expired" "$err"
contains "and says work has not started" "Not starting work" "$err"

case_setup
echo '{"items":[]}' > "$GH_FIXTURES/board"
err=$(bash "$SCRIPT" claim 10 2>&1 >/dev/null); rc=$?
check "an issue not on the board is refused rather than worked" "3" "$rc"

echo
echo "releasing a failed run"

case_setup
boarded "10:In Progress"
bash "$SCRIPT" release 10 >/dev/null 2>&1
contains "a release puts the issue back in Ready" "ee5ea42c" "$(cat "$GH_LOG")"

case_setup
boarded "10:In Progress"
echo yes > "$GH_FIXTURES/edit_fails"
err=$(bash "$SCRIPT" release 10 2>&1 >/dev/null); rc=$?
check "a release that cannot be written fails loudly" "4" "$rc"
contains "and says the issue is stuck and needs a person" "needs a person" "$err"
contains "and names the run" "$RUN_URL" "$err"

echo
echo "what it never does"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2"
boarded "10:Ready"
bash "$SCRIPT" pick >/dev/null 2>&1
bash "$SCRIPT" claim 10 >/dev/null 2>&1
bash "$SCRIPT" review 10 >/dev/null 2>&1
bash "$SCRIPT" release 10 >/dev/null 2>&1
log=$(cat "$GH_LOG")
absent "never removes the queue label" "remove-label" "$log"
absent "never edits a label at all" "issue edit" "$log"
absent "never comments — that is GITHUB_TOKEN's job in the workflow" "issue comment" "$log"
absent "never merges" "pr merge" "$log"
absent "never pushes" "push" "$log"

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "all good"
  exit 0
fi
echo "${#FAILURES[@]} failed:"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

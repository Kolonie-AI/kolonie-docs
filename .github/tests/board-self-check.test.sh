#!/bin/bash
# Does the board self-check report correctly, and does it keep its hands off the board?
#
# Usage: bash .github/tests/board-self-check.test.sh
#
# `kolonie-docs#132` asks for two properties to be proved rather than asserted:
# that a second issue is not opened while the first is open — *"a test or a
# documented guard, not a hope"* — and that nothing here ever writes to the
# board. Both are checked here against a **stubbed `gh`**, which is the only way
# to exercise the branch where an issue already exists without filing one.
#
# The stub records every `gh` invocation to a log and answers from files the
# case sets up. That makes the board-touching assertion exhaustive rather than a
# reading of the script: any `item-add`, `item-edit` or `archive` would appear in
# the log, whatever code path produced it.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/board-self-check.sh"
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export GITHUB_REPOSITORY="Kolonie-AI/kolonie-docs"
export RUN_URL="https://example.invalid/run/1"

# The stub. Every case writes the answers it wants into $WORK before running.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "api graphql")
    if [[ "$*" == *"projectV2(number:1){ id }"* ]]; then cat "$GH_FIXTURES/readable" 2>/dev/null
    else cat "$GH_FIXTURES/pruning" 2>/dev/null; fi ;;
  "project item-list") cat "$GH_FIXTURES/board" 2>/dev/null ;;
  "repo list")        cat "$GH_FIXTURES/repos" 2>/dev/null ;;
  "issue list")
    if [[ "$*" == *"in:title"* ]]; then cat "$GH_FIXTURES/existing" 2>/dev/null
    else cat "$GH_FIXTURES/issues" 2>/dev/null; fi ;;
  *) : ;;
esac
exit 0
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

expect() {
  local name=$1 ok=$2 detail=${3:-}
  if [ "$ok" = yes ]; then printf '  ok   %s\n' "$name"
  else printf '  FAIL %s%s\n' "$name" "${detail:+: $detail}"; FAILURES+=("$name"); fi
}

setup() {
  export GH_FIXTURES="$WORK/fixtures" GH_LOG="$WORK/log"
  rm -rf "$GH_FIXTURES"; mkdir -p "$GH_FIXTURES"; : > "$GH_LOG"
  # A healthy board by default: archiving on, 25 items, every open issue on it.
  echo "PVT_kwDOEmwuYs4BebbB" > "$GH_FIXTURES/readable"
  echo "true" > "$GH_FIXTURES/pruning"
  for i in $(seq 1 25); do echo "Kolonie-AI/kolonie-docs#$i"; done > "$GH_FIXTURES/board"
  echo "kolonie-docs" > "$GH_FIXTURES/repos"
  for i in $(seq 1 25); do echo "Kolonie-AI/kolonie-docs#$i"; done > "$GH_FIXTURES/issues"
  : > "$GH_FIXTURES/existing"
}

logged() { grep -q -- "$1" "$GH_LOG"; }

echo "a healthy board is silent"

setup
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "exit 0 when both answers are right" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc"
expect "says so in one line" "$([[ "$out" == *"pruning itself"* ]] && echo yes || echo no)" "$out"
expect "the report file is empty" "$([ ! -s "$WORK/report" ] && echo yes || echo no)" "$(cat "$WORK/report")"

echo
echo "5a — the pruning"

setup; echo "false" > "$GH_FIXTURES/pruning"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "auto-archive off fails" "$([ $rc -eq 1 ] && echo yes || echo no)" "rc=$rc"
expect "and says which setting" "$([[ "$out" == *"Auto-archive is switched off"* ]] && echo yes || echo no)" "$out"

setup; : > "$GH_FIXTURES/pruning"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "no answer at all fails, rather than reading as true" "$([ $rc -eq 1 ] && echo yes || echo no)" "rc=$rc"
expect "and says it is unverified" "$([[ "$out" == *"could not be read at all"* ]] && echo yes || echo no)" "$out"

echo
echo "5b — the arriving"

setup; echo "Kolonie-AI/kolonie-docs#99" >> "$GH_FIXTURES/issues"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "an issue not on the board fails" "$([ $rc -eq 1 ] && echo yes || echo no)" "rc=$rc"
expect "and names it" "$([[ "$out" == *"kolonie-docs#99"* ]] && echo yes || echo no)" "$out"

# The failure that would file a hundred false lines. A board listing that comes
# back short is a spent budget or a lost scope, never an empty board.
setup; echo "Kolonie-AI/kolonie-docs#1" > "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a short board listing fails without accusing every issue" \
  "$([ $rc -eq 1 ] && [[ "$out" != *"#20"* ]] && echo yes || echo no)" "$out"
expect "and says why it did not run the comparison" \
  "$([[ "$out" == *"was not run"* ]] && echo yes || echo no)" "$out"

echo
echo "a token that cannot see the board says so, and files nothing"

setup; : > "$GH_FIXTURES/readable"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "exit 2, distinct from both answers" "$([ $rc -eq 2 ] && echo yes || echo no)" "rc=$rc"
expect "names it a configuration gap" \
  "$([[ "$out" == *"configuration gap"* ]] && echo yes || echo no)" "$out"
expect "does not report the board as broken" \
  "$([[ "$out" != *"Auto-archive is switched off"* && "$out" != *"not on the board"* ]] && echo yes || echo no)" "$out"
expect "asks neither question" \
  "$(grep -q 'project item-list' "$GH_LOG" && echo no || echo yes)" "$(cat "$GH_LOG")"

echo
echo "reporting — the guard #132 asked to be proved"

setup; : > "$GH_FIXTURES/existing"
printf '5a — something is wrong\n' > "$WORK/report"
bash "$SCRIPT" report "$WORK/report" >/dev/null
expect "with no open issue, one is created" "$(logged 'issue create' && echo yes || echo no)"
expect "and it is labelled area:docs" "$(logged 'area:docs' && echo yes || echo no)"

setup; echo '77' > "$GH_FIXTURES/existing"
printf '5a — something is wrong\n' > "$WORK/report"
bash "$SCRIPT" report "$WORK/report" >/dev/null
expect "with one already open, no second issue is created" \
  "$(logged 'issue create' && echo no || echo yes)" "$(grep -c . "$GH_LOG") gh calls"
expect "it comments on the open one instead" "$(logged 'issue comment 77' && echo yes || echo no)"

setup; echo '77' > "$GH_FIXTURES/existing"
bash "$SCRIPT" resolve >/dev/null
expect "when both answers are right again, the issue is closed" \
  "$(logged 'issue close 77' && echo yes || echo no)"

setup; : > "$GH_FIXTURES/existing"
bash "$SCRIPT" resolve >/dev/null
expect "and closing nothing is not an error" "$(logged 'issue close' && echo no || echo yes)"

echo
echo "it never writes to the board"

# Every command, over every fixture, into one log. Anything that mutates the
# board would have to appear here.
: > "$WORK/all"
for fixture in healthy off missing; do
  setup
  case $fixture in
    off)     echo "false" > "$GH_FIXTURES/pruning" ;;
    missing) echo "Kolonie-AI/kolonie-docs#99" >> "$GH_FIXTURES/issues" ;;
  esac
  bash "$SCRIPT" check "$WORK/report" >/dev/null
  printf '5a — x\n' > "$WORK/report"
  bash "$SCRIPT" report "$WORK/report" >/dev/null
  bash "$SCRIPT" resolve >/dev/null
  cat "$GH_LOG" >> "$WORK/all"
done
for forbidden in "item-add" "item-edit" "archiveProjectV2Item" "unarchive" "item-delete"; do
  expect "no $forbidden in any code path" \
    "$(grep -q -- "$forbidden" "$WORK/all" && echo no || echo yes)" \
    "$(grep -- "$forbidden" "$WORK/all" | head -1)"
done

echo
if [ ${#FAILURES[@]} -gt 0 ]; then
  printf '%d failed: %s\n' "${#FAILURES[@]}" "$(IFS=,; echo "${FAILURES[*]}")"
  exit 1
fi
echo "all cases pass"

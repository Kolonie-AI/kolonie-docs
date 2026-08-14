#!/bin/bash
# Does the cap fail an over-cap file, and can the ratchet be left slack?
# (`kolonie-docs#365`)
#
# Usage: bash .github/tests/check-caps.test.sh
#
# **The rejection cases are the test.** A cap that passes on a repository already
# under it proves nothing — and this one has a second failure mode nobody would
# notice: a `max-lines:` declaration left far above the file it caps, which reads
# as enforced and enforces nothing. Both are here, plus the case that a file
# without front matter is not a module and is not capped at all.
#
#   over the default cap              fails, naming where content should go
#   over its own declared cap         fails
#   under its declared cap by > 50    fails, asking for the cap to be lowered
#   the core, over 200 but under 400  fails — `always` is capped tighter
#   not a module                      is not capped
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/check-caps.py"
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILURES+=("$1"); }

REPO=$WORK/repo
mkdir -p "$REPO/.github/scripts" "$REPO/agents"
cp "$SCRIPT" "$REPO/.github/scripts/"
CHECK="$REPO/.github/scripts/check-caps.py"
cd "$REPO" && git init -q .

# `module <path> <lines> [front-matter-extra...]`
module() {
  local path=$1 lines=$2; shift 2
  {
    echo "---"
    echo "module: $(basename "$path" .md)"
    echo "summary: A fixture."
    for extra in "$@"; do echo "$extra"; done
    echo "applies-to:"
    echo "  roles: [orchestrator]"
    echo "---"
  } > "$REPO/$path"
  local body=$(( lines - 7 ))
  for _ in $(seq 1 "$body"); do echo "a line" >> "$REPO/$path"; done
  git -C "$REPO" add -A >/dev/null
}

core() {
  local lines=$1
  {
    echo "---"
    echo "module: agents"
    echo "summary: The binding contract."
    echo "applies-to:"
    echo "  always: true"
    echo "---"
  } > "$REPO/AGENTS.md"
  for _ in $(seq 1 $(( lines - 6 ))); do echo "a line" >> "$REPO/AGENTS.md"; done
  git -C "$REPO" add -A >/dev/null
}

reset() { rm -f "$REPO"/AGENTS.md "$REPO"/agents/*.md; git -C "$REPO" add -A >/dev/null; }

echo
echo "the default caps"

reset; core 150; module agents/small.md 100
out=$(python3 "$CHECK" 2>&1); rc=$?
[ $rc -eq 0 ] && pass "a core and a module under their caps pass" || fail "under-cap failed: $out"

reset; core 250
out=$(python3 "$CHECK" 2>&1); rc=$?
[ $rc -ne 0 ] && pass "a 250-line core fails, though a module of that size would not" \
  || fail "the core was capped at the module number"
grep -q "the cap is 200" <<<"$out" && pass "and the number is named" || fail "the cap was not named"
grep -q "Do not delete a rule to fit" <<<"$out" && pass "and so is the alternative" \
  || fail "the message did not name where content should go"
grep -q "agents/history/" <<<"$out" && pass "including where the reasoning goes" \
  || fail "the message did not mention agents/history/"

reset; core 100; module agents/big.md 450
out=$(python3 "$CHECK" 2>&1); rc=$?
[ $rc -ne 0 ] && pass "a 450-line module fails" || fail "an over-cap module passed"
grep -q "declare .max-lines:" <<<"$out" && pass "and the ratchet is offered" \
  || fail "max-lines: was not offered"

echo
echo "the ratchet"

reset; core 100; module agents/big.md 450 "max-lines: 460"
out=$(python3 "$CHECK" 2>&1); rc=$?
[ $rc -eq 0 ] && pass "a declared cap above the file passes" || fail "a declared cap failed: $out"
grep -q "may only ever be lowered" <<<"$out" && pass "and every declaration is printed" \
  || fail "the declaration was not printed"

reset; core 100; module agents/big.md 450 "max-lines: 900"
out=$(python3 "$CHECK" 2>&1); rc=$?
[ $rc -ne 0 ] && pass "a declared cap with 450 lines of slack fails" \
  || fail "a cap nobody has to meet passed"
grep -q "lower it to about" <<<"$out" && pass "and it says what to lower it to" \
  || fail "no target was suggested"

reset; core 100; module agents/big.md 500 "max-lines: 460"
out=$(python3 "$CHECK" 2>&1); rc=$?
[ $rc -ne 0 ] && pass "a file over its own declared cap still fails" \
  || fail "a declared cap did not bind its own file"

echo
echo "what is not a module is not capped"

reset; core 100
for _ in $(seq 1 900); do echo "a line" >> "$REPO/not-a-module.md"; done
git -C "$REPO" add -A >/dev/null
out=$(python3 "$CHECK" 2>&1); rc=$?
[ $rc -eq 0 ] && pass "a 900-line file with no front matter is not capped" \
  || fail "a non-module was capped: $out"

echo
echo "against this repository"

cd "$ROOT"
out=$(python3 "$SCRIPT" 2>&1); rc=$?
[ $rc -eq 0 ] && pass "every module here is within its cap" || fail "caps are red here: $out"

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "check-caps.py: all cases pass"
  exit 0
fi
echo "check-caps.py: ${#FAILURES[@]} case(s) failed"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

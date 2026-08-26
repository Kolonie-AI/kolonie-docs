#!/bin/bash
# Does the coverage check notice a line that fell out of a split? (`kolonie-docs#363`)
#
# Usage: bash .github/tests/check-brief-coverage.test.sh
#
# **The rejection case is the whole test.** A coverage check that passes on a
# complete split proves nothing — so does one whose parser finds no lines at
# all, which is the failure `ci.yml`'s own comment warns about for the link
# checker. Every case here is either *it caught something* or *it could not have
# been made to pass by being broken*:
#
#   a complete split                     passes
#   a paragraph deleted from a module    fails, and the line is named
#   a line reworded rather than moved    fails
#   a line moved to agents/history/      passes — that is where narrative goes
#   a link retargeted by the split       passes; the target is not content
#   a line listed as retired             passes, and the count is printed
#   a retired line that is present       fails as a stale entry
#   a deleted Markdown heading           fails until it is retired, and passes
#                                        once the escaped form is written (#507)
#   a SHA that is not in the repository  fails rather than skipping
#
# It runs against a fixture repository, because the source has to be pinned by a
# commit that this test made — the real one names `AGENTS.md` at a SHA, and a
# test that edited it would be editing history.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/check-brief-coverage.py"
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILURES+=("$1"); }

REPO=$WORK/repo
mkdir -p "$REPO/.github/scripts" "$REPO/agents/history"
cp "$SCRIPT" "$REPO/.github/scripts/"
CHECK="$REPO/.github/scripts/check-brief-coverage.py"

cat > "$REPO/BIG.md" <<'MD'
# The one file

A rule that everybody needs, in every session.

A rule about the board, which most work never touches.

The reason that rule exists, which is a story about 2026-08-12.

#### `agent:human` and `blocked:human` are not the same label twice

See [the board](#the-board) for the rest of it.
MD

cd "$REPO"
git init -q .
git add -A
git -c user.email=t@t.invalid -c user.name=t commit -qm before
SHA=$(git rev-parse HEAD)

split() { # write the modules, in whatever state the case wants
  cat > "$REPO/BIG.md" <<'MD'
# The one file

A rule that everybody needs, in every session.
MD
  cat > "$REPO/agents/board.md" <<'MD'
# The board

A rule about the board, which most work never touches.

#### `agent:human` and `blocked:human` are not the same label twice

See [the board](board.md#the-board) for the rest of it.
MD
  cat > "$REPO/agents/history/2026-08-12.md" <<'MD'
# What happened

The reason that rule exists, which is a story about 2026-08-12.
MD
  printf 'BIG.md %s BIG.md agents/*.md agents/history/*.md\n' "$SHA" > "$REPO/.github/coverage-splits.txt"
  rm -f "$REPO/.github/coverage-retired.txt"
  git add -A >/dev/null
}

run() { python3 "$CHECK" "$REPO/.github/coverage-splits.txt" 2>&1; }

echo
echo "a complete split"

split
out=$(run); rc=$?
[ $rc -eq 0 ] && pass "passes" || { fail "a complete split failed: $out"; }
grep -q "all present" <<<"$out" && pass "and says so with a count" || fail "no count printed"
grep -q "story about 2026-08-12" <<<"$out" && fail "narrative in agents/history counted as missing" || pass "a line in agents/history/ counts as kept"
grep -q "See \[the board\]" <<<"$out" && fail "a retargeted link counted as missing" || pass "a link whose target moved is not a lost line"

echo
echo "a paragraph that fell out at the seam"

split
sed -i '/most work never touches/d' "$REPO/agents/board.md"
git add -A >/dev/null
out=$(run); rc=$?
[ $rc -ne 0 ] && pass "fails" || fail "a deleted paragraph passed"
grep -q "most work never touches" <<<"$out" && pass "and the line is named" || fail "the missing line was not named"

echo
echo "a line reworded rather than moved"

split
sed -i 's/most work never touches/hardly any work touches/' "$REPO/agents/board.md"
git add -A >/dev/null
out=$(run)
[ $? -ne 0 ] && pass "fails, because a rewrite is not a move" || fail "a reworded line passed"

echo
echo "retirement, and its own failure mode"

split
sed -i '/most work never touches/d' "$REPO/agents/board.md"
printf '# because the board went away\nA rule about the board, which most work never touches.\n' \
  > "$REPO/.github/coverage-retired.txt"
git add -A >/dev/null
out=$(run); rc=$?
[ $rc -eq 0 ] && pass "a retired line is excused" || fail "a retired line was not excused: $out"
grep -q "1 line(s) are deliberately retired" <<<"$out" && pass "and the count is printed" || fail "the retired count was not printed"

split
printf '# stale\nA rule about the board, which most work never touches.\n' \
  > "$REPO/.github/coverage-retired.txt"
git add -A >/dev/null
out=$(run); rc=$?
[ $rc -ne 0 ] && pass "a stale retirement fails" || fail "a retirement of a line that is present passed"
grep -q "present after all" <<<"$out" && pass "and says which" || fail "the stale entry was not named"

echo
echo "a retired Markdown heading (#507)"

split
sed -i '/are not the same label twice/d' "$REPO/agents/board.md"
git add -A >/dev/null
out=$(run); rc=$?
[ $rc -ne 0 ] && pass "a deleted heading fails before it is retired" \
  || fail "a deleted Markdown heading passed unretired"
grep -q "not the same label twice" <<<"$out" && pass "and the heading is named" \
  || fail "the missing heading was not named"

printf '# it was renamed\n\\#### `agent:human` and `blocked:human` are not the same label twice\n' \
  > "$REPO/.github/coverage-retired.txt"
git add -A >/dev/null
out=$(run); rc=$?
[ $rc -eq 0 ] && pass "the escaped heading retires it" \
  || fail "an escaped retired heading was not excused: $out"
grep -q "1 line(s) are deliberately retired" <<<"$out" && pass "and it is counted" \
  || fail "the escaped entry was not counted"

echo
echo "it cannot pass by being broken"

split
printf 'BIG.md 0000000000000000000000000000000000000000 agents/*.md\n' > "$REPO/.github/coverage-splits.txt"
out=$(run); rc=$?
[ $rc -ne 0 ] && pass "an unreachable SHA fails rather than skipping" || fail "an unreachable SHA passed"

split
printf 'BIG.md %s agents/nothing-matches-this/*.md\n' "$SHA" > "$REPO/.github/coverage-splits.txt"
out=$(run); rc=$?
[ $rc -ne 0 ] && pass "a glob that matches no file fails" || fail "an empty destination set passed"

echo
echo "against this repository"

cd "$ROOT"
out=$(python3 "$SCRIPT" 2>&1); rc=$?
[ $rc -eq 0 ] && pass "every split this repository has made is still covered" \
  || fail "coverage is red here: $out"

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "check-brief-coverage.py: all cases pass"
  exit 0
fi
echo "check-brief-coverage.py: ${#FAILURES[@]} case(s) failed"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

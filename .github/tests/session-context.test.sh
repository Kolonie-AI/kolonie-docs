#!/bin/bash
# Does the SessionStart producer survive everything, and say so? (`kolonie-docs#362`)
#
# Usage: bash .github/tests/session-context.test.sh
#
# One property matters more than the content: **it never fails the session.** A
# hook that exits non-zero tells the agent nothing about what went wrong, and an
# agent that starts with no context does not know that it started with none. So
# every case here asserts the exit status *and* that the reason reached the text.
#
# The clone it reads is a fixture with no remote, which is also the case that
# exercises the freshness warning: `git pull` fails, and the warning has to be
# inside the context rather than on a stderr nobody reads.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/session-context.sh"
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILURES+=("$1"); }
contains() { if grep -qF -- "$2" <<<"$3"; then pass "$1"; else fail "$1 (expected: $2)"; fi }

REPO=$WORK/repo
mkdir -p "$REPO/.github/scripts" "$REPO/governance"
cp "$ROOT/.github/scripts/brief.sh" "$REPO/.github/scripts/"
cp "$ROOT/.github/scripts/session-context.sh" "$REPO/.github/scripts/"
printf '# Red Lines\n## Forbidden\n- Credential exfiltration\n' > "$REPO/governance/red-lines.md"
cat > "$REPO/AGENTS.md" <<'MD'
---
module: agents
summary: The binding contract.
applies-to:
  always: true
---
UNIQUE-AGENTS-STRING
MD
(cd "$REPO" && git init -q . && git add -A && git -c user.email=t@t.invalid -c user.name=t commit -qm fixture)

echo
echo "a clone that is there"

out=$(KOLONIE_DOCS=$REPO bash "$REPO/.github/scripts/session-context.sh" 2>/dev/null)
status=$?
[ $status -eq 0 ] && pass "exits 0" || fail "exited $status"
if jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' <<<"$out" >/dev/null 2>&1; then
  pass "emits SessionStart JSON"
else
  fail "did not emit SessionStart JSON: $out"
fi
text=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" 2>/dev/null)
contains "the red lines are in it" "Credential exfiltration" "$text"
contains "the modules are named" "agents" "$text"
contains "no module content is in it" "a directory, not documents" "$text"
if grep -qF "UNIQUE-AGENTS-STRING" <<<"$text"; then
  fail "a module's content was loaded eagerly, which is the whole defect"
else
  pass "a module's content was not loaded eagerly"
fi
contains "a pull with no remote is reported rather than swallowed" "WARNING" "$text"

echo
echo "a worktree is a clone — .git is a file there, not a directory"

WT=$WORK/worktree
(cd "$REPO" && git worktree add -q -b fixture-branch "$WT" 2>/dev/null)
if [ -f "$WT/.git" ]; then
  out=$(KOLONIE_DOCS=$WT bash "$WT/.github/scripts/session-context.sh" 2>/dev/null)
  text=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" 2>/dev/null)
  contains "a worktree is briefed like any other checkout" "Credential exfiltration" "$text"
else
  fail "the fixture worktree was not created, so this case proved nothing"
fi

echo
echo "a clone that is not there"

out=$(KOLONIE_DOCS=$WORK/nowhere bash "$SCRIPT" 2>/dev/null)
status=$?
[ $status -eq 0 ] && pass "still exits 0" || fail "exited $status with no clone"
contains "and says where it looked" "$WORK/nowhere" "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"

echo
echo "--text is the same context without the envelope"

out=$(KOLONIE_DOCS=$REPO bash "$REPO/.github/scripts/session-context.sh" --text 2>/dev/null)
contains "plain text" "Credential exfiltration" "$out"
if jq -e . <<<"$out" >/dev/null 2>&1; then fail "--text emitted JSON"; else pass "and no JSON envelope"; fi

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "session-context.sh: all cases pass"
  exit 0
fi
echo "session-context.sh: ${#FAILURES[@]} case(s) failed"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

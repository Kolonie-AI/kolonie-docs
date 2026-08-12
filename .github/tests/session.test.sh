#!/bin/bash
# Does the session guard refuse the four ways the three facts can disagree, and
# allow the one way they agree? `kolonie-docs#318`.
#
# Usage: bash .github/tests/session.test.sh
#
# The rejection cases are the point. `#318` is an incident in which **every green
# thing stayed green** — push, CI, and the repository's own check command all
# passed on the wrong branch — so a test that only proves the happy path proves
# the property that was never in doubt.
#
# Five cases, one per refusal the script can issue, plus the pass:
#
#   unclaimed             nobody took the checkout
#   anonymous             KOLONIE_AGENT unset — the case that catches #318 itself
#   another session       KOLONIE_AGENT disagrees with the claim
#   wandered off          HEAD moved to a branch the session did not take
#   expired               the claim is older than its ttl
#   agreed                all three agree, and a commit goes through
#
# Every case runs against a **real, disposable git repository** rather than a
# stub. The hooks are the deliverable here — a test that called `session.sh check`
# directly and never let `git commit` invoke it would pass with the hooks
# uninstalled, which is the one failure that matters.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/session.sh"
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A repository that looks like this one from the script's point of view: the
# script resolves itself to the repository root, so it has to *be* there.
REPO="$WORK/repo"
mkdir -p "$REPO/.github/scripts"
cp "$SCRIPT" "$REPO/.github/scripts/session.sh"
GUARD="$REPO/.github/scripts/session.sh"

cd "$REPO"
git init -q -b main .
echo one > file.txt
git add -A
# Seeded through the environment rather than `git config`, so the checkout starts
# with **no local identity**. That is the state a fresh clone is in, and it is the
# one the two identity cases below are about.
GIT_AUTHOR_NAME=seed GIT_AUTHOR_EMAIL=seed@example.invalid \
GIT_COMMITTER_NAME=seed GIT_COMMITTER_EMAIL=seed@example.invalid \
  git commit -qm "seed"
git branch fix/somebody-elses-branch

# `default_branch()` asks origin/HEAD first and falls back to main. There is no
# origin here, so the fallback is what these cases exercise — which is also the
# arrangement a fresh clone has before anybody sets it.

say() { printf '\n── %s\n' "$1"; }

fail() {
  echo "   FAILED: $1"
  FAILURES+=("$1")
}

pass() { echo "   ok"; }

# Asserts on both the exit status and the text, because the text is half the
# deliverable: `#318`'s complaint is that the failure was silent, and a refusal
# that does not say which of the three facts disagreed sends the reader to the
# wrong fix.
refuses_with() {
  local what=$1 expect=$2 out status
  shift 2
  out=$("$@" 2>&1)
  status=$?
  if [ $status -eq 0 ]; then
    fail "$what — expected a refusal, got exit 0"
    return
  fi
  if ! grep -qF "$expect" <<<"$out"; then
    fail "$what — refused, but never said '$expect'"
    printf '%s\n' "$out" | sed 's/^/      | /'
    return
  fi
  pass
}

allows() {
  local what=$1 out status
  shift
  out=$("$@" 2>&1)
  status=$?
  if [ $status -ne 0 ]; then
    fail "$what — expected to be allowed, exit $status"
    printf '%s\n' "$out" | sed 's/^/      | /'
    return
  fi
  pass
}

say "an unclaimed checkout refuses a commit"
bash "$GUARD" install-hooks >/dev/null
echo two > file.txt
git add -A
# The identity comes from the environment here so that *the hook* is what
# refuses. Without it git fails first, on having no committer, and the case would
# pass on an error that has nothing to do with the guard.
refuses_with "unclaimed" "not claimed by any session" \
  env -u KOLONIE_AGENT \
    GIT_AUTHOR_NAME=seed GIT_AUTHOR_EMAIL=seed@example.invalid \
    GIT_COMMITTER_NAME=seed GIT_COMMITTER_EMAIL=seed@example.invalid \
    git commit -qm "should not land"

say "taking it on main is allowed, and gives an unconfigured checkout an identity"
out=$(KOLONIE_AGENT=alice bash "$GUARD" take 2>&1) || fail "take on main refused: $out"
if [ "$(git config --local --get user.email)" = "alice@noreply.kolonie.ai" ]; then pass; else
  fail "identity not set — user.email is '$(git config --local --get user.email)'"
fi
# `#230`: a generated address is a last resort and has to say so, or the agent
# never learns that its commits are not linked to its GitHub account.
if grep -q "kolonie-docs#230" <<<"$out"; then pass; else
  fail "generated an address without pointing at #230"
fi

say "a commit refuses when KOLONIE_AGENT is unset"
refuses_with "anonymous" "KOLONIE_AGENT is not set" \
  env -u KOLONIE_AGENT git commit -qm "should not land"

say "a commit refuses when another agent is at the keyboard"
refuses_with "another session" "held by another session" \
  env KOLONIE_AGENT=bob git commit -qm "should not land"

say "the agreed case commits"
allows "agreed" env KOLONIE_AGENT=alice git commit -qm "lands"
if git log -1 --format='%an <%ae>' | grep -q "alice <alice@noreply.kolonie.ai>"; then pass; else
  fail "the commit does not carry the session identity: $(git log -1 --format='%an <%ae>')"
fi

say "a commit refuses after HEAD wandered onto another branch"
# This is #318 in one line: the claim is real, the agent is right, and the branch
# is somebody else's.
git switch -q fix/somebody-elses-branch
echo three > file.txt
git add -A
refuses_with "wandered off" "not on the branch this session took" \
  env KOLONIE_AGENT=alice git commit -qm "should not land"

say "taking a non-default branch refuses until it is named"
refuses_with "unnamed branch" "which is not 'main'" \
  env KOLONIE_AGENT=alice bash "$GUARD" take
allows "named branch" env KOLONIE_AGENT=alice bash "$GUARD" take --branch fix/somebody-elses-branch
allows "commit on a branch taken deliberately" env KOLONIE_AGENT=alice git commit -qm "lands on the branch"

say "an expired claim refuses, and does not block a fresh take"
git switch -q main
KOLONIE_AGENT=alice bash "$GUARD" take >/dev/null
CLAIMFILE=$(git rev-parse --git-path kolonie-session)
sed -i "s/^taken=.*/taken=1/" "$CLAIMFILE"
echo four > file.txt
git add -A
refuses_with "expired" "expired" \
  env KOLONIE_AGENT=alice git commit -qm "should not land"
allows "a stale claim is walked over without --force" env KOLONIE_AGENT=bob bash "$GUARD" take

say "a live claim is refused without --force, and displaced with it"
refuses_with "live claim" "already held by 'bob'" \
  env KOLONIE_AGENT=carol bash "$GUARD" take
allows "forced" env KOLONIE_AGENT=carol bash "$GUARD" take --force

say "an identity already configured here is left alone"
# The case kolonie-docs#230 is about: the agent's real address links its commits
# to its GitHub account, and #318's want — *distinct* — is already satisfied by
# it. A guard that overwrote this would be trading attribution for nothing.
git config user.email "314729329+someone@users.noreply.github.com"
git config user.name "someone"
out=$(KOLONIE_AGENT=dave bash "$GUARD" take --force 2>&1)
if [ "$(git config --local --get user.email)" = "314729329+someone@users.noreply.github.com" ]; then pass; else
  fail "overwrote a configured identity — now '$(git config --local --get user.email)'"
fi
if grep -q "kolonie-docs#230" <<<"$out"; then
  fail "warned about a generated address when nothing was generated"
else pass; fi

say "KOLONIE_AGENT_EMAIL is used when the checkout has none"
git config --unset user.email
git config --unset user.name
out=$(KOLONIE_AGENT=erin KOLONIE_AGENT_EMAIL=erin@example.invalid bash "$GUARD" take --force 2>&1)
if [ "$(git config --local --get user.email)" = "erin@example.invalid" ]; then pass; else
  fail "KOLONIE_AGENT_EMAIL ignored — user.email is '$(git config --local --get user.email)'"
fi

say "a foreign hook is not overwritten"
HOOKS=$(git rev-parse --git-path hooks)
printf '#!/bin/bash\nexit 0\n' > "$HOOKS/pre-commit"
chmod +x "$HOOKS/pre-commit"
out=$(bash "$GUARD" install-hooks 2>&1)
if grep -q "leaving it alone" <<<"$out" && ! grep -q "session.sh" "$HOOKS/pre-commit"; then pass; else
  fail "a hook that was not ours was overwritten or not reported"
fi

say "release lets the next session start clean"
allows "release" bash "$GUARD" release
refuses_with "released" "not claimed by any session" env KOLONIE_AGENT=carol bash "$GUARD" check

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "session.sh: all cases pass"
  exit 0
fi
echo "session.sh: ${#FAILURES[@]} case(s) failed"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

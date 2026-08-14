#!/bin/bash
# This repository's own check command. `AGENTS.md` → *The check command*.
#
# Usage: bash .github/scripts/check.sh
#
# ## Why this exists, when `ci.yml` already ran all of it
#
# `AGENTS.md` §7 has required a *"repository's own check command"* in every
# issue's definition of done since long before there was one here to name. Four
# of the five repositories in the organisation answer that with `npm run check`;
# this one answered it with *read `ci.yml` and run the steps by hand*, which is a
# procedure rather than a command and which nobody did.
#
# `kolonie-docs#231` is what forced it: the hourly worker now runs **the target
# repository's** check before opening a pull request, and reads which one out of
# that repository's `AGENTS.md`. A repository that names none stops the run. This
# repository holds the worker and would have been the first to stop it.
#
# ## What it is not
#
# **Not a second definition of CI.** `ci.yml` stays the authority on what runs on
# a pull request, and this file deliberately runs the same things in the same
# order rather than a curated subset — a check command that is a *shorter* CI
# teaches you that green means nothing.
#
# Two steps behave differently outside Actions and both say so when they do:
# `no-gateway-leak.sh` skips when the secrets it greps for are not in the
# environment (its own rule, so a fork is not blocked by a check nobody outside
# can act on), and `check-brand-surfaces.py` needs a token to reach GraphQL.
# Neither is silently dropped: each prints why it was skipped, because a check
# that quietly does not run is the failure `ci.yml`'s own header is about.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

FAILED=()
SKIPPED=()

step() {
  local what=$1
  shift
  echo
  echo "── $what"
  if "$@"; then
    echo "   ok"
  else
    echo "   FAILED"
    FAILED+=("$what")
  fi
}

# First, and it is `ci.yml`'s rule as well as `check-red-lines.yml`'s before it:
# a check nobody has verified is a suite nobody runs with a shorter fuse. The
# link check needs it most — a parser bug there does not turn it red, it makes it
# find nothing and pass.
step "the checks are tested before they are trusted" bash -c '
  set -e
  python3 .github/tests/check-links.test.py
  python3 .github/tests/red-lines.test.py
  bash .github/tests/find-red-line-copies.test.sh
  python3 .github/tests/build-skill.test.py
  python3 .github/tests/build-readme.test.py
  python3 .github/tests/check-incident-order.test.py
  python3 .github/tests/check-brand-surfaces.test.py
  python3 .github/tests/check-skill-target.test.py
  bash .github/tests/no-gateway-leak.test.sh
  bash .github/tests/opencode-worker.test.sh
  bash .github/tests/board-triage.test.sh
  bash .github/tests/board-self-check.test.sh
  bash .github/tests/opencode-context.test.sh
  bash .github/tests/waiting-list.test.sh
  bash .github/tests/watch-finding.test.sh
  bash .github/tests/session.test.sh
'

step "every internal Markdown link resolves" \
  python3 .github/scripts/check-links.py .

step "the incidents are still newest first" \
  python3 .github/scripts/check-incident-order.py operations/incidents.md

step "README.md carries the current Colony header" \
  python3 .github/scripts/build-readme.py \
    onboarding/readme/header.md README.md --first --check

# `#252`. Runs in both states: while publication is blocked it asserts the record
# is intact and the blocker is real, and it needs neither a token nor the sibling
# repositories to do that. Now that the flag is flipped it asserts all seven
# carry the sentence — reading each from disk when the sibling is beside this
# repository and from GitHub when it is not, so the answer is the same here and
# in CI. It used to skip what was not checked out, which made CI green over
# seven files it had never read.
step "the marketplace description has one copy" \
  python3 .github/scripts/check-skill-description.py

# `#343`. The order in which an arriving agent handles its key lives once, in the
# shared body; **where the key goes** cannot, because it is a different place on
# every runtime. So the target lives in seven `skill.runtime.md` files, which is
# the arrangement that goes stale silently — an eighth runtime inherits the order
# for free and inherits nothing about the target. Same projection shape as the
# red-line copies, and the same reason.
step "every generated SKILL.md names one concrete place for the key" \
  python3 .github/scripts/check-skill-target.py

# Named rather than dropped. `no-gateway-leak.sh` decides for itself whether it
# can run — it greps for the *values* of two secrets and skips when they are
# absent, which is deliberate and is its own comment's reasoning — so it is
# always called and reports its own skip.
step "nothing about the private gateway is committed" \
  bash .github/scripts/no-gateway-leak.sh .

if [ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]; then
  step "brand/README.md §3 still describes the surfaces GitHub is serving" \
    python3 .github/scripts/check-brand-surfaces.py brand/README.md
  step "the copies of the red lines still agree" bash -c '
    set -o pipefail
    tmp=$(mktemp -d)
    bash .github/scripts/find-red-line-copies.sh "$tmp"
    python3 .github/scripts/red-lines.py "$tmp"
  '
else
  SKIPPED+=("brand surfaces and the red-line copies — both read GitHub, and no GH_TOKEN is set")
fi

echo
for skip in ${SKIPPED+"${SKIPPED[@]}"}; do
  echo "skipped: $skip"
done

if [ ${#FAILED[@]} -eq 0 ]; then
  echo "all good"
  exit 0
fi

echo "${#FAILED[@]} failed:"
printf '  - %s\n' "${FAILED[@]}"
exit 1

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
# Discovered rather than listed. This step and the one in `ci.yml` were two
# hand-written lists of the same set; they drifted, and three committed test
# files ended up in neither and ran nowhere — `kolonie-docs#378`. One record, or
# none. A test not meant to run says so in its own file; `run-tests.sh` explains
# how and refuses to pass silently over anything it cannot run.
step "the checks are tested before they are trusted" \
  bash .github/scripts/run-tests.sh

# `#443`. Named rather than discovered, and it is the one exception to the rule
# directly above. `run-tests.sh` discovers `.github/tests/*.test.*`;
# `rehearse-triage.sh` is deliberately outside that pattern — its own header and
# `run-tests.sh`'s both say why: it is a harness that reads
# `inbound-triage.yml` and rehearses it, not a test of one of the checks. So it
# ran in `rehearse.yml` and nowhere else, and `rehearse.yml` is not a required
# context on `main` — a red rehearsal stopped nothing and no local command ever
# asked it. That is two holes, and this closes the half that is in this
# repository: a push now has to get past it.
#
# It needs `pyyaml`, which `rehearse.yml` installs and a fresh checkout may not
# have. It says so itself and fails rather than skipping — the module is one
# `pip install` away, which is not the position `no-gateway-leak.sh` is in.
step "the inbound-triage rehearsal still passes" \
  bash .github/tests/rehearse-triage.sh

# `#365`. 216 lines on 2026-07-27, 2.021 on 2026-08-14 — every one of them a
# good-faith improvement, which is why a habit was never going to hold this. The
# `max-lines:` declarations are a ratchet and the check prints them on every run.
step "the core and every module are within their caps" \
  python3 .github/scripts/check-caps.py

# `#363`. A prose file split by hand loses paragraphs at the seams and nobody
# notices for weeks, so the promise that nothing was lost is a build failure
# rather than a sentence in a pull request. The rows are meant to age out.
step "nothing was lost when a document was split" \
  python3 .github/scripts/check-brief-coverage.py

step "every internal Markdown link resolves" \
  python3 .github/scripts/check-links.py .

step "Actions LLM callers use the reviewed gateway and tier contract" \
  python3 .github/scripts/check-llm-callers.py

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

# `#498`. The shared body is the one Colony-facing source; a sentence that still
# says rotation has no confirmation step reaches all seven generated skills.
step "the shared skill documents the two-call credential rotation" \
  python3 .github/scripts/check-skill-rotation.py

# `#458` adds `check-skill-spec.py`, and it is deliberately not a step here: this
# repository has no `SKILL.md` of its own to point it at, and the seven validate
# themselves in their own `skill.yml`. Its own test is discovered by
# `run-tests.sh` above, which is the half that matters here — the wrapper
# tolerates three named divergences and must fail on everything else, and a
# tolerance one character too wide would accept the next one silently.

# Named rather than dropped. `no-gateway-leak.sh` decides for itself whether it
# can run — it greps for the *values* of two secrets and skips when they are
# absent, which is deliberate and is its own comment's reasoning — so it is
# always called and reports its own skip.
step "nothing about the private gateway is committed" \
  bash .github/scripts/no-gateway-leak.sh .

if [ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]; then
  step "brand/README.md §3 still describes the surfaces GitHub is serving" \
    python3 .github/scripts/check-brand-surfaces.py brand/README.md
  # One discovery run, two comparisons over it (`#399`). The red lines and the
  # Atlas invitation live in the same documents, so fetching twice would pay the
  # whole sweep again for the same bytes — and reporting them as one step would
  # make a green line mean *one of the two things you cannot tell apart*.
  #
  # They are separate steps rather than a single `||` chain for that reason: a
  # chain returns one status, and `step` would name the wrong subject half the
  # time.
  COPIES=$(mktemp -d)
  step "every copy of the red lines and the invitation could be fetched" \
    bash .github/scripts/find-red-line-copies.sh "$COPIES"

  if [ -f "$COPIES/manifest.json" ]; then
    step "the copies of the red lines still agree" \
      python3 .github/scripts/red-lines.py "$COPIES"
    step "the copies of the Atlas invitation still agree" \
      python3 .github/scripts/red-lines.py "$COPIES" manifest-invitation.json
  else
    # The fetch above already failed and said why. Running the comparisons
    # against an empty directory would answer it with a traceback and bury the
    # sentence that actually names the problem.
    SKIPPED+=("both comparisons — nothing was fetched to compare")
  fi
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

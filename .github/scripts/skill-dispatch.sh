#!/bin/bash
# Ask the seven runtime repositories to regenerate their `SKILL.md` now.
#
# Usage: SKILL_SYNC_TOKEN=… bash .github/scripts/skill-dispatch.sh
#
# The Colony-facing half of every `SKILL.md` lives once, in `onboarding/skill/`.
# The seven regenerate against it on a cron at `17 6 * * *`; this asks them to do
# it now instead of tomorrow morning. `#359` is why the fast path exists: a tool
# withdrawn at 15:26 left six of the seven documenting a tool that answered
# `-32602 Tool not found` until the next morning.
#
# ## Why this is a script and not the workflow's own `run:` block
#
# `#500`. On 2026-08-25 a push of the shared body dispatched **none** of the
# seven and the run was green — run 32908682526, conclusion success, 7s. The
# defect is not that the dispatch failed; it is that nothing could tell the
# difference between *the fast path worked* and *the fast path did nothing*, and
# a workflow that is only prose in a `run:` block cannot be asserted against.
# `.github/tests/skill-dispatch.test.sh` exercises every ending below against a
# stubbed `gh`, which is what makes the rejection case a test rather than a
# sentence.
#
# ## The three endings, and why only one of them is green
#
#   - **No token.** Nothing can be dispatched. A `::error::`, a summary naming
#     the setting that closes it, and **exit 1**. This used to be deliberately
#     green while the fast path was unfinished; `#359` is closed now, so an
#     unreadable credential is a broken fast path rather than an unfinished one.
#   - **A token, and every runtime asked.** Exit 0. Each of the seven decides for
#     itself whether the body moved and opens a pull request a person reads.
#   - **A token, and any runtime not asked.** Exit 1. This is wired up and
#     broken, which is precisely the silent failure `#359` is about one level up.
#     Six of seven is the case that reads as success from a distance and is not
#     one: the seventh keeps serving a withdrawn tool for up to a day.
#
# ## What it may never do
#
# **It merges nothing, in any repository.** It asks seven workflows to run, and
# the human gate on a change reaching seven repositories is unchanged (`#359`).
set -uo pipefail

# Written out rather than derived. There is no API that answers *which
# repositories carry a generated SKILL.md*, and a wrong answer here is a
# repository that silently keeps a withdrawn tool — the exact failure this
# exists to prevent. `check-skill-target.py` and `check-skill-description.py`
# carry the same seven for the same reason.
REPOS=(
  kolonie-skill
  kolonie-claude
  kolonie-codex
  kolonie-hermes
  kolonie-kilo
  kolonie-openclaw
  kolonie-antigravity
)

RUN_URL=${RUN_URL:-}

summary() {
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] || return 0
  cat >> "$GITHUB_STEP_SUMMARY"
}

# `GITHUB_TOKEN` reaches this repository and no other, so dispatching a workflow
# in `kolonie-claude` needs a credential that spans them. Scoping that secret is
# a credential decision and belongs to a maintainer (`agents/routes.md`); this
# script never asks for a token value and never prints one.
if [ -z "${SKILL_SYNC_TOKEN:-}" ]; then
  echo "::error::the shared skill body moved and the seven were not told; SKILL_SYNC_TOKEN is not readable from this repository."
  summary <<'MD'
### The seven were not told

The shared skill body moved and this workflow could not dispatch `skill.yml`
anywhere, because `SKILL_SYNC_TOKEN` is not readable here.

**They are on their cron.** Each of the seven regenerates at `17 6 * * *` and
opens a pull request if the body has moved, so nothing is lost — only delayed,
by up to a day. That is the state `#359` measured.

**One setting closes it.** `SKILL_SYNC_TOKEN` is an organisation secret; adding
`kolonie-docs` to its selected-repositories list is the whole change. The token
also needs `actions: write` on the seven — `workflow_dispatch` is a different
permission from the `contents` and `pull-requests` writes it already uses.

`#359` is closed on the promise that this fast path works. No readable token
means **0 of 7** were dispatched, so this run is red rather than reporting that
promise green.
MD
  exit 1
fi

asked=0
for repo in "${REPOS[@]}"; do
  if GH_TOKEN="$SKILL_SYNC_TOKEN" gh workflow run skill.yml \
       --repo "Kolonie-AI/$repo" --ref main; then
    echo "::notice::$repo was asked to regenerate"
    asked=$((asked + 1))
  else
    # Named one at a time rather than counted, so whoever reads this knows
    # which repository keeps a stale shared body until its own 06:17 cron.
    echo "::error::Kolonie-AI/$repo could not be asked to regenerate, so it stays on its 06:17 cron with a stale shared body. Dispatch skill.yml there by hand: $RUN_URL"
  fi
done

total=${#REPOS[@]}

{
  echo "### Asked the seven to regenerate"
  echo
  echo "**$asked of $total** dispatched \`skill.yml\`."
  echo
  if [ "$asked" -eq 0 ]; then
    echo "**None of them was reached.** The fast path is wired up and did not work; the annotations above name what each attempt returned. Every runtime keeps a stale shared body until its own cron at 06:17, which is the delay \`#359\` exists to remove."
  elif [ "$asked" -ne "$total" ]; then
    echo "The rest are named in the annotations above. Each one keeps a stale shared body until its own cron at 06:17, which is the delay \`#359\` is about."
  else
    echo "Each opens a pull request if the body has moved, and **merges nothing** — the human gate on a change reaching seven repositories is unchanged (\`#359\`)."
  fi
} | summary

# `#500`: the no-token ending is 0 of 7, and a configured run can reach the
# same count through seven failed attempts. Any shortfall is red; zero says so
# twice.
if [ "$asked" -ne "$total" ]; then
  echo "::error::$asked of $total runtimes were asked to regenerate; the fast path did not reach them all."
  exit 1
fi
exit 0

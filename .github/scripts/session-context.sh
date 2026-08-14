#!/bin/bash
# What a session is given at SessionStart, and the freshness of the clone it was
# read from (`kolonie-docs#362`).
#
# Usage:
#   session-context.sh          # SessionStart JSON on stdout
#   session-context.sh --text   # the same context as plain text
#
# ## Why this is in the repository and not in the hook
#
# It used to be `~/.claude/hooks/kolonie-docs-context.sh`: 83 lines, on one
# machine, outside every repository, naming six files it loaded in full. Three
# consequences, and the third is the expensive one:
#
# - the repository could not change its own document structure without an edit
#   to an unversioned file nobody reviews;
# - nobody could review the loading policy, because it was not in a repository;
# - **a second machine ran a different policy and nothing said so.**
#
# The hook is now a shim that calls this file. What it kept is the one thing
# that belongs to the machine rather than to the project: where the clone is.
#
# ## The freshness warning is the half that must not be lost
#
# A `git pull` that fails quietly is worse than one that fails loudly: the
# documents would look current and be stale, and a stale rule is obeyed exactly
# as confidently as a current one. So the pull's outcome is *inside the context*
# rather than on stderr, where nothing would read it.
#
# ## Never fails the session
#
# Every path exits 0 and says what went wrong in the context text. A hook that
# exits non-zero tells the agent nothing about what happened, and an agent that
# starts with no context does not know that it did.
set -uo pipefail

REPO="${KOLONIE_DOCS:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
MODE=${1:---json}

emit() {
  if [ "$MODE" = --text ]; then
    cat
  else
    jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}'
  fi
}

# `git rev-parse` and not `[ -d "$REPO/.git" ]`: in a **worktree** `.git` is a
# file naming the real git directory, so the directory test answers *not a
# clone* for exactly the arrangement `AGENTS.md` §1 tells every session to work
# in. The hook then said no context was loaded and was believed.
if ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  printf '%s\n' "kolonie-docs is not a git checkout at $REPO — no project context was loaded." | emit
  exit 0
fi

{
  # --- freshness -----------------------------------------------------------
  pull_err=$(git -C "$REPO" pull --ff-only --quiet 2>&1)
  pull_rc=$?

  local_head=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null)
  upstream=$(git -C "$REPO" rev-parse --short '@{u}' 2>/dev/null)

  if (( pull_rc != 0 )); then
    echo "=== WARNING: kolonie-docs could not be updated ==="
    echo "git pull --ff-only exited $pull_rc: ${pull_err:-(no output)}"
    echo "What follows is the local clone at $local_head and may be stale."
    echo "Check before quoting it: git -C $REPO status"
    echo
  elif [[ -n "$upstream" && "$local_head" != "$upstream" ]]; then
    echo "=== WARNING: kolonie-docs differs from its upstream ==="
    echo "HEAD is $local_head, origin is $upstream. The pull reported success."
    echo
  fi

  # --- the directory, and nothing else -------------------------------------
  bash "$REPO/.github/scripts/brief.sh" --manifest 2>&1 ||
    echo "brief.sh could not assemble the start manifest. Read $REPO/AGENTS.md by hand and open an issue for this."
} | emit

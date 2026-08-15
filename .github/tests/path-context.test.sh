#!/usr/bin/env bash
#
# path-context.sh: the third loading trigger.
#
# What is asserted here is the contract the hook makes with a session — once per
# area, nothing for an area no module claims, and silence rather than an error
# wherever it cannot answer. The events are real `PreToolUse` JSON so the parser
# under test is the one that runs.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/path-context.sh"

FAILURES=()
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# State goes in the sandbox: a test that wrote to the real state directory would
# pass once and then silently assert nothing.
export KOLONIE_PATH_CONTEXT_STATE="$WORK/state"

pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILURES+=("$1"); }

contains() { # <case> <needle> <haystack>
  case $3 in *"$2"*) pass "$1" ;; *) fail "$1 — expected to contain: $2" ;; esac
}
absent() { # <case> <needle> <haystack>
  case $3 in *"$2"*) fail "$1 — expected NOT to contain: $2" ;; *) pass "$1" ;; esac
}
empty() { # <case> <output>
  if [ -z "$2" ]; then pass "$1"; else fail "$1 — expected no output, got: $2"; fi
}

# One PreToolUse event, as Claude Code sends it.
event() { # <session-id> <absolute-file-path>
  jq -nc --arg s "$1" --arg f "$2" \
    '{session_id:$s, hook_event_name:"PreToolUse", tool_name:"Write", tool_input:{file_path:$f}}'
}

# `run` is used inside a command substitution, so its exit status cannot come
# back in a variable — the assignment would happen in the subshell. It goes
# through a file, and `status_was` reads it afterwards.
run() { # <mode> <session-id> <path>  -> stdout, status in $WORK/status
  local mode=$1
  event "$2" "$3" | bash "$SCRIPT" $mode
  echo $? > "$WORK/status"
}

status_was() { # <case> <expected>
  local got; got=$(cat "$WORK/status" 2>/dev/null)
  [ "$got" = "$2" ] && pass "$1" || fail "$1 — expected exit $2, got ${got:-none}"
}

# A repository that is not this one, because the whole point of the trigger is
# that it fires wherever an agent works. With no `origin` given it has none, so
# these also cover the fallback for a checkout that was never cloned.
mkfixture() { # <directory-name> [origin-url]
  local repo="$WORK/$1"
  mkdir -p "$repo/packages/db/src" "$repo/.github/workflows"
  : > "$repo/README.md"
  : > "$repo/packages/db/src/thing.ts"
  : > "$repo/.github/workflows/ci.yml"
  git -C "$repo" init -q
  [ -n "${2:-}" ] && git -C "$repo" remote add origin "$2"
  git -C "$repo" add -A
  git -C "$repo" -c user.email=t@t.invalid -c user.name=t commit -qm fixture
  echo "$repo"
}

PLATFORM=$(mkfixture kolonie-platform)

# --- a claimed path arrives, once ------------------------------------------

out=$(run '' session-a "$PLATFORM/packages/db/src/thing.ts")
contains "a claimed path emits the PreToolUse envelope" '"hookEventName": "PreToolUse"' "$out"
contains "a claimed path emits additionalContext"       '"additionalContext"'           "$out"
contains "the module that claims it is the one loaded"  'platform'                      "$out"
status_was "exit 0 when it has something to say" 0

out=$(run '' session-a "$PLATFORM/packages/db/src/other.ts")
empty "a second write to the same area emits nothing" "$out"

out=$(run '' session-b "$PLATFORM/packages/db/src/thing.ts")
contains "a different session is told again" '"additionalContext"' "$out"

# --- the rejection case the definition of done asks for ---------------------

out=$(run '' session-c "$PLATFORM/nothing/claims/this.rs")
empty "a path no module claims emits nothing at all" "$out"
status_was "exit 0 with nothing to say" 0

# --- what it cannot answer, it declines quietly -----------------------------

out=$(run '' session-d "$WORK/loose/file.md")
empty "a path outside any worktree emits nothing" "$out"

out=$(echo '{"session_id":"session-e","tool_input":{}}' | bash "$SCRIPT")
empty "an event carrying no file path emits nothing" "$out"

out=$(echo 'not json at all' | bash "$SCRIPT"; echo "status=$?")
contains "a malformed event is not an error" 'status=0' "$out"

out=$(run '' session-f "packages/db/src/thing.ts")
empty "a relative path is declined rather than guessed at" "$out"

# --- repos: narrows what a path claims --------------------------------------
#
# `docs-repo` and `session` claim `**/*.md` *in kolonie-docs*. The same file in
# another repository is not theirs, which is the difference between this query
# and the one `--issue` asks.

out=$(run '' session-g "$PLATFORM/README.md")
empty "a module scoped to one repository does not claim the path in another" "$out"

DOCS_FIXTURE=$(mkfixture kolonie-docs)
out=$(run '' session-h "$DOCS_FIXTURE/README.md")
contains "the same path in the repository the module names is claimed" '"additionalContext"' "$out"

# --- the repository is `origin`, not the directory name ---------------------
#
# `agents/session.md` tells an agent to take a worktree per session, so the real
# checkouts on this board are `kolonie-platform-colette` and the like. Reading
# the repository off the directory made `repos:` narrowing reject every one of
# them, and the trigger was silent in exactly the checkouts it was written for.

SUFFIXED=$(mkfixture kolonie-platform-colette git@github.com:Kolonie-AI/kolonie-platform.git)
out=$(run '' session-k "$SUFFIXED/packages/db/src/thing.ts")
contains "a suffixed worktree is the repository its origin names" 'platform' "$out"

NOREMOTE=$(mkfixture kolonie-platform-noremote)
out=$(run '' session-l "$NOREMOTE/packages/db/src/thing.ts")
empty "a checkout with no origin falls back to its directory name" "$out"

# --- `**/*.md` reaches the root ---------------------------------------------
#
# `**/` matches no directory as well as several, so a pattern claiming every
# Markdown file claims the ones at the root too. It did not, once, and a module
# about a repository of Markdown files was silent about its own AGENTS.md.

out=$(bash "$ROOT/.github/scripts/brief.sh" --for-path AGENTS.md --repo kolonie-docs)
contains "**/*.md claims a file at the repository root" 'docs-repo' "$out"

# --- --text drops the envelope ----------------------------------------------

out=$(run --text session-i "$PLATFORM/packages/db/src/thing.ts")
absent   "--text carries no envelope" 'hookSpecificOutput' "$out"
contains "--text carries the content" 'platform'           "$out"

# --- the context describes and does not instruct ----------------------------
#
# It arrives from a tool event rather than from the person the agent works for,
# and the line that keeps that safe is that it states facts.

out=$(run --text session-j "$PLATFORM/packages/db/src/thing.ts")
contains "it says what is happening" 'is being written'  "$out"
contains "it disclaims instruction"  'instructs nothing' "$out"

if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "path-context.sh: all cases pass"
  exit 0
fi
echo "path-context.sh: ${#FAILURES[@]} case(s) failed"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

#!/usr/bin/env bash
#
# The third loading trigger (`#371`): the first time a session writes a path some
# module claims, that module arrives — once, before the write lands.
#
# The other two triggers are *a session started* and *an agent took an issue*.
# Both fire when the work is still a plan. This one fires on the first evidence
# of what the work actually is, which is the moment a module about that area
# stops being a guess.
#
# **The policy is here and the machine-local hook is a shim**, for the same
# reason `session-context.sh` is: what belongs to the machine is where the clone
# is, and everything else is the project's and is reviewed and tested with it.
#
# **It has to fire in every repository an agent works in**, not only in this one,
# which is the difference from `session-context.sh`. So nothing here assumes the
# write is inside this clone: the path is resolved against *its own* worktree,
# the repository is that worktree's name, and this clone is only where the
# assembler and the modules are read from.
#
# Reads a `PreToolUse` event on stdin. Writes a `hookSpecificOutput` envelope,
# or nothing at all.
#
#   path-context.sh            # JSON, for the hook
#   path-context.sh --text     # the same content without the envelope
#
# **Every path exits 0 and says nothing when it has nothing to say.** A context
# loader is not a gate: it must never be the reason a write was refused, and a
# repository it cannot make sense of is an ordinary case rather than an error.
set -uo pipefail

# Where this repository is. The one thing that belongs to the machine.
DOCS="${KOLONIE_DOCS:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
MODE=${1:---json}

# What this session has already been given. Once per session per module is the
# whole point — an agent writing forty files in one area must be told once.
STATE_DIR="${KOLONIE_PATH_CONTEXT_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/kolonie/path-context}"

say_nothing() { exit 0; }

emit() {
  if [ "$MODE" = --text ]; then
    cat
  else
    jq -Rs '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:.}}'
  fi
}

command -v jq >/dev/null 2>&1 || say_nothing

event=$(cat)

# `tool_input.file_path` is absolute for `Write`, `Edit` and `NotebookEdit`. A
# relative one would have to be resolved against a working directory this script
# has no reliable claim to, so it is declined rather than guessed at.
file=$(jq -r '.tool_input.file_path // empty' <<<"$event" 2>/dev/null) || say_nothing
[ -n "$file" ] || say_nothing
case $file in /*) ;; *) say_nothing ;; esac

session=$(jq -r '.session_id // empty' <<<"$event" 2>/dev/null)
# It becomes a file name, so it is reduced to what a file name may hold rather
# than trusted. A session that arrives without an id shares one bucket, which
# costs a repeat that a wrong file name would cost silence.
session=${session//[^A-Za-z0-9._-]/}
[ -n "$session" ] || session=unknown-session

# The file being written need not exist yet, and neither need its directory —
# `Write` creates both. Walk up to something that does.
dir=$(dirname "$file")
while [ ! -d "$dir" ] && [ "$dir" != / ]; do dir=$(dirname "$dir"); done

root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || say_nothing
[ -n "$root" ] || say_nothing
case $file in "$root"/*) rel=${file#"$root"/} ;; *) say_nothing ;; esac

# Which repository this is, from `origin` rather than from the directory name.
# The directory is the wrong answer for the arrangement this project actually
# recommends: `agents/session.md` tells agents to take a worktree per session,
# so the real checkouts are `kolonie-platform-colette` and the like, and a
# module scoped to `kolonie-platform` would have claimed nothing in any of them.
# A checkout with no remote falls back to the directory, which is the best a
# fresh `git init` can offer.
origin=$(git -C "$root" remote get-url origin 2>/dev/null)
repo=${origin%.git}
repo=${repo##*/}
[ -n "$repo" ] || repo=$(basename "$root")

claimed=$(bash "$DOCS/.github/scripts/brief.sh" \
  --for-path "$rel" --repo "$repo" 2>/dev/null) || say_nothing
[ -n "$claimed" ] || say_nothing

mkdir -p "$STATE_DIR" 2>/dev/null || say_nothing
state=$STATE_DIR/$session

fresh=()
while IFS=$'\t' read -r name path summary; do
  [ -n "$name" ] || continue
  grep -qxF "$name" "$state" 2>/dev/null && continue
  fresh+=("$name")
done <<<"$claimed"
[ ${#fresh[@]} -gt 0 ] || say_nothing

# Recorded *before* it is emitted, deliberately. If this run dies between the
# two, the session loses one module it could have had; recording afterwards
# would repeat a module on every write instead, and of the two failures the
# noisy one is worse.
printf '%s\n' "${fresh[@]}" >> "$state"

{
  # Stated as facts and never as an instruction. This text arrives in a model's
  # context from a tool event rather than from the person it works for, and the
  # rule that keeps that safe is that it describes and never directs.
  printf 'A file matching %s is being written. What this repository records about that area follows.\n' "$rel"
  printf 'It explains and instructs nothing, and it arrives once per session per area.\n\n'
  bash "$DOCS/.github/scripts/brief.sh" --module "$(IFS=,; echo "${fresh[*]}")" 2>&1
} | emit

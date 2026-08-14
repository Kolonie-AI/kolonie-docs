#!/bin/bash
# The one assembler. What a session, a worker or an orchestrator is given to
# read, and nothing else (`kolonie-docs#362`).
#
# Usage:
#   brief.sh --manifest                     # what a session starts with: red lines, the loop, a directory
#   brief.sh --module <name>[,<name>...]    # one named module, or several, in full
#   brief.sh --issue <owner/repo> <number>  # the modules that issue's labels and repository ask for
#   brief.sh --modules                      # the module table, one row per module, for a script
#   brief.sh --index                        # every Markdown file in the repository, by name
#
# Options: --role <role> (default `worker`), --path <path> (repeatable),
#          --max-tokens <n>, --no-content (name what would be loaded, load nothing).
#
# ## Why this exists
#
# The policy that decided what a session loaded used to live in
# `~/.claude/hooks/kolonie-docs-context.sh` — 83 lines, on one machine, outside
# every repository, hard-coding six filenames. So this repository could not
# change its own document structure without an edit to an unversioned file
# nobody reviews, and any split of those six documents either did nothing or
# silently dropped content.
#
# The measurement that forced it: the SessionStart context was **~72.000 tokens**
# before an agent read a single file, and a worker on an ordinary code issue
# needs about 250 of `AGENTS.md`'s 2.021 lines.
#
# ## The rule the whole file is built on
#
#   **Nothing is in context because it might be relevant.**
#
# A session starts with a **directory**, not with documents. Everything else
# arrives because something asked for it: the issue that was taken, the path
# being written, or a name the agent read in the directory and asked for.
#
# ## Routing is derived, never maintained
#
# A module is any Markdown file in the repository whose front matter names it.
# There is no list of modules anywhere — not here, not in the hook, not in a
# workflow. Adding one is adding a file; retiring one is deleting a file.
#
#   ---
#   module: board
#   summary: Getting <item-id> right; which repositories the automation covers.
#   applies-to:
#     roles: [orchestrator]
#     labels: [area:infra]
#     paths: [".github/workflows/**"]
#   ---
#
# `applies-to:` keys, all optional, any one of them matching is a match:
#
#   always: true        every brief, always. The binding contract, and nothing else
#   roles: [...]        matches --role
#   labels: [...]       matches a label on the issue
#   repos: [...]        matches the repository the issue is in
#   paths: [...]        matches --path, glob, `**` crosses directories
#
# `applies-to:` present and empty matches **nothing**, and that is a real
# setting rather than a mistake: `agents/history/` is written to be reachable
# and never briefed.
#
# ## The front matter this parses, and what it does with the rest
#
# A deliberate subset of YAML: `key: value` at the left margin, `key: [a, b]`
# or `key: true` nested one level under `applies-to:`. **A shape it does not
# understand is a hard error naming the file and the line** — never a shrug. A
# routing rule that is silently not applied is a document that is silently not
# loaded, which is the whole failure this file exists against.
#
# ## Nothing may be lost — three guarantees, in this order
#
# 1. **A brief always names what it left out**, one line per unloaded module,
#    from its own `summary:`. The hook this replaces already stated the rule:
#    *a file that is not loaded but not mentioned is a file nobody knows to
#    look for.*
# 2. **Over budget, the brief says what it dropped** — `opencode-context.sh`'s
#    rule, and this is the second implementation of it rather than a second
#    policy. Silent truncation reads as *there was nothing more*.
# 3. **Coverage is mechanical**: `check-brief-coverage.py` fails the build if a
#    line of a split document is in no module (`#363`).
#
# ## What it must not become
#
# **Not a second STATUS.md.** It reads front matter and prints files. It knows
# nothing about what the Colony is doing, holds no state, and caches nothing.
#
# **Not a gate.** Every module is loadable by name at any time. Routing decides
# what arrives *unasked*; it never decides what an agent may read.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ORG=${ORG:-Kolonie-AI}

# Bytes per token, for the estimate this file prints. Rough on purpose: the
# number is here to make a budget visible, not to be exact, and every place it
# is printed says `~`.
BYTES_PER_TOKEN=4

# What a brief may carry before it starts dropping. An issue brief that reaches
# this has stopped being a brief.
MAX_TOKENS=${BRIEF_MAX_TOKENS:-6000}

ROLE=worker
PATHS=()
WITH_CONTENT=yes

die() { echo "brief.sh: $1" >&2; exit "${2:-1}"; }

tokens_of() { # <bytes>
  echo $(( $1 / BYTES_PER_TOKEN ))
}

# ---------------------------------------------------------------------------
# Front matter
# ---------------------------------------------------------------------------

# The front matter block of a file, without its fences. Empty when the file does
# not open with one, which is how a document says *I am not a module*.
front_matter_of() { # <file>
  local file=$1
  [ -r "$file" ] || return 0
  # `head -1` and not `head -c 4`: command substitution strips the trailing
  # newline, so the four-character compare could never match and every file
  # answered *not a module* — silently, which is the shape of failure this
  # script is otherwise built against.
  [ "$(head -1 "$file")" = "---" ] || return 0
  awk 'NR==1 && $0=="---" {inside=1; next} inside && $0=="---" {exit} inside {print}' "$file"
}

# One top-level scalar out of a front matter block.
fm_scalar() { # <front-matter> <key>
  awk -v key="$2" '
    $0 ~ "^" key ":" { sub("^" key ":[[:space:]]*", ""); print; exit }
  ' <<<"$1"
}

# The items of an inline list nested one level under `applies-to:`, one per line.
# `roles: [orchestrator, worker]` → two lines. `always: true` → the word `true`.
fm_applies() { # <front-matter> <key>
  awk -v key="$2" '
    /^applies-to:[[:space:]]*$/ { inside=1; next }
    /^[^[:space:]]/ { inside=0 }
    inside && $0 ~ "^[[:space:]]+" key ":" {
      sub("^[[:space:]]+" key ":[[:space:]]*", "")
      gsub(/^\[|\]$/, "")
      n = split($0, parts, /,[[:space:]]*/)
      for (i = 1; i <= n; i++) {
        gsub(/^[[:space:]]*"?|"?[[:space:]]*$/, "", parts[i])
        if (parts[i] != "") print parts[i]
      }
    }
  ' <<<"$1"
}

# A module's front matter must parse as one of the shapes above. Anything else
# stops the run naming the file: a rule nobody applied is worse than no rule.
validate_front_matter() { # <file> <front-matter>
  local file=$1 fm=$2 bad
  bad=$(awk '
    /^[a-zA-Z][a-zA-Z-]*:/ { top=$0; next }
    /^applies-to:[[:space:]]*$/ { next }
    /^[[:space:]]+[a-zA-Z][a-zA-Z-]*:/ { next }
    /^[[:space:]]*$/ { next }
    { print NR ": " $0 }
  ' <<<"$fm")
  [ -z "$bad" ] || die "$file has front matter this parser does not understand:
$bad
Supported: 'key: value' at the margin, and 'key: [a, b]' or 'key: true' indented
under 'applies-to:'. Fix the file rather than the parser, or widen the parser
here and add a case to .github/tests/brief.test.sh."
}

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

# Every module in the repository: `<name>\t<path>\t<summary>`, sorted by path so
# the order a brief arrives in is stable and reviewable.
#
# `git ls-files` rather than `find`, so an untracked scratch file in the working
# copy can never become a module in somebody's brief.
modules() {
  local file fm name summary
  while IFS= read -r file; do
    fm=$(front_matter_of "$ROOT/$file")
    [ -n "$fm" ] || continue
    name=$(fm_scalar "$fm" module)
    [ -n "$name" ] || continue
    validate_front_matter "$file" "$fm"
    summary=$(fm_scalar "$fm" summary)
    printf '%s\t%s\t%s\n' "$name" "$file" "${summary:-no summary}"
  done < <(cd "$ROOT" && git ls-files '*.md' | sort)
}

# The same rows in reading order: the binding core, then what it routes to, then
# the documents. `modules` stays sorted by path because a script wants a stable
# order; a person wants the contract first.
modules_for_reading() {
  modules | awk -F'\t' '
    $2 == "AGENTS.md"        { core = $0; next }
    $2 ~ /^agents\//         { routed[++r] = $0; next }
                             { rest[++t] = $0 }
    END {
      if (core) print core
      for (i = 1; i <= r; i++) print routed[i]
      for (i = 1; i <= t; i++) print rest[i]
    }'
}

path_of_module() { # <name>
  modules | awk -F'\t' -v n="$1" '$1==n {print $2; exit}'
}

# Does this module apply, given a role, a set of labels, a repository and the
# paths being touched? Prints the reason it matched, or nothing.
module_matches() { # <path> <labels-csv> <repo>
  local file=$1 labels=$2 repo=$3 fm
  fm=$(front_matter_of "$ROOT/$file")

  [ "$(fm_applies "$fm" always)" = true ] && { echo "always"; return 0; }

  local want
  while IFS= read -r want; do
    [ -n "$want" ] || continue
    [ "$want" = "$ROLE" ] && { echo "role $ROLE"; return 0; }
  done < <(fm_applies "$fm" roles)

  while IFS= read -r want; do
    [ -n "$want" ] || continue
    case ",$labels," in *",$want,"*) echo "label $want"; return 0 ;; esac
  done < <(fm_applies "$fm" labels)

  while IFS= read -r want; do
    [ -n "$want" ] || continue
    [ "$want" = "$repo" ] || [ "$want" = "${repo#*/}" ] && { echo "repository $want"; return 0; }
  done < <(fm_applies "$fm" repos)

  local pattern p
  while IFS= read -r pattern; do
    [ -n "$pattern" ] || continue
    for p in ${PATHS+"${PATHS[@]}"}; do
      # `**` crosses directories and `*` does not, which is what the patterns in
      # the front matter mean by them. `extglob` off, so this is done by hand.
      local regex=${pattern//\*\*/$'\x01'}
      regex=${regex//\*/[^\/]*}
      regex=${regex//$'\x01'/.*}
      [[ "$p" =~ ^${regex}$ ]] && { echo "path $pattern"; return 0; }
    done
  done < <(fm_applies "$fm" paths)

  return 1
}

# ---------------------------------------------------------------------------
# Emitting
# ---------------------------------------------------------------------------

emit_module() { # <name> <path> <why>
  printf '\n=== MODULE %s — %s (%s) ===\n\n' "$1" "$2" "$3"
  cat "$ROOT/$2"
  printf '\n'
}

# The one thing every brief ends with: what it did not load, by name and
# summary, so that nothing is invisible merely because it was not relevant.
emit_not_loaded() { # <loaded-names-csv>
  local loaded=$1 name path summary any=no
  while IFS=$'\t' read -r name path summary; do
    case ",$loaded," in *",$name,"*) continue ;; esac
    [ "$any" = yes ] || {
      printf '\n--- Not loaded, and each is one command away ---\n\n'
      any=yes
    }
    printf -- '- %-22s %s\n' "$name" "$summary"
  done < <(modules)
  [ "$any" = no ] || printf '\n  bash %s/.github/scripts/brief.sh --module <name>\n' "$ROOT"
}

# ---------------------------------------------------------------------------
# --manifest — what a session starts with
# ---------------------------------------------------------------------------
#
# Three things and no document. The red lines are the exception that proves the
# rule: they are the one text that is never routed, never summarised and never
# left to a trigger, because a rule that arrives after the act it forbids has
# not been loaded at all.
cmd_manifest() {
  cat <<HEADER
=== Kolonie AI — a directory, not documents ===

Complete here: the red lines. Everything else is named below and one command
away, from $ROOT. Nothing is in context because it might be relevant.

HEADER

  printf -- '--- The red lines — binding, complete, never routed ---\n\n'
  if [ -r "$ROOT/governance/red-lines.md" ]; then
    cat "$ROOT/governance/red-lines.md"
  else
    printf 'governance/red-lines.md is MISSING from %s.\n' "$ROOT"
    printf 'Stop and fix that before doing anything else: the binding rules of this\n'
    printf 'project could not be loaded, and no other part of this brief is worth acting on.\n'
  fi

  cat <<LOOP

--- The loop, as commands ---

  export KOLONIE_AGENT=<your-session-name>
  bash .github/scripts/session.sh take <issue>   # claims the checkout, prints its brief
  gh api -X POST repos/$ORG/<repo>/issues/<n>/comments -f body='...'   # say you took it
  bash .github/scripts/check.sh                  # the verdict is in the log, not the exit code
  gh pr create --fill                            # finish the branch first; it merges on green

  The board query that says what can be started, and the order to decide in:
  bash .github/scripts/brief.sh --module orchestration

LOOP

  printf -- '--- The modules ---\n\n'
  local name path summary
  while IFS=$'\t' read -r name path summary; do
    printf -- '- %-13s %s\n' "$name" "$summary"
  done < <(modules_for_reading)
  printf '\n  bash .github/scripts/brief.sh --module <name>   any of them, in full\n\n' 

  # One line, counts only. Eight directory names with an example file each cost
  # more of this budget than they answer, and `--index` names every file for
  # anybody who wants them — which is the rule this whole manifest turns on.
  printf -- '--- Everything else: '
  (cd "$ROOT" && git ls-files '*/*.md' | cut -d/ -f1 | sort | uniq -c |
     awk '{printf "%s/%s ", $2, $1}')
  printf -- '---\n\n  bash .github/scripts/brief.sh --index   names every one of them\n'

  cat <<'FOOT'

--- If this did not answer your question ---

That is a defect in the briefing. The issue you open says which of three: this
manifest, a module, or the routing that gave you the wrong one.
FOOT
}

# ---------------------------------------------------------------------------
# --index — every Markdown file, by name
# ---------------------------------------------------------------------------
cmd_index() {
  printf '=== Every Markdown file in %s ===\n\n' "$ROOT"
  local file hint
  while IFS= read -r file; do
    hint=$(grep -m1 -E '^#{1,2} ' "$ROOT/$file" 2>/dev/null | sed 's/^#\{1,2\} //')
    printf -- '- %s — %s\n' "$file" "${hint:-no heading}"
  done < <(cd "$ROOT" && git ls-files '*.md' | sort)
}

# The same rows in reading order: the binding core, then what it routes to, then
# the documents. `modules` stays sorted by path because a script wants a stable
# order; a person wants the contract first.
modules_for_reading() {
  modules | awk -F'\t' '
    $2 == "AGENTS.md"        { core = $0; next }
    $2 ~ /^agents\//         { routed[++r] = $0; next }
                             { rest[++t] = $0 }
    END {
      if (core) print core
      for (i = 1; i <= r; i++) print routed[i]
      for (i = 1; i <= t; i++) print rest[i]
    }'
}

# ---------------------------------------------------------------------------
# --modules — the table, for a script
# ---------------------------------------------------------------------------
cmd_modules() { modules; }

# ---------------------------------------------------------------------------
# --module — one or several, in full
# ---------------------------------------------------------------------------
cmd_module() { # <name>[,<name>...]
  local names=$1 name path
  IFS=, read -r -a names <<<"$names"
  for name in "${names[@]}"; do
    path=$(path_of_module "$name")
    [ -n "$path" ] || die "no module called '$name'. What there is:
$(modules | awk -F'\t' '{printf "  %-22s %s\n", $1, $3}')"
    [ "$WITH_CONTENT" = yes ] && emit_module "$name" "$path" "asked for by name" \
      || printf -- '- %s\t%s\n' "$name" "$path"
  done
}

# ---------------------------------------------------------------------------
# --issue — what one issue asks for
# ---------------------------------------------------------------------------
#
# The issue's labels and repository decide, and the decision is stated in the
# output: every module says why it is here. An agent that disagrees with the
# routing can then say which rule was wrong, rather than that it "got the wrong
# context".
cmd_issue() { # <owner/repo> <number>
  local repo=$1 number=$2 issue title labels
  issue=$(gh api "repos/$repo/issues/$number" 2>/dev/null) || issue=''
  if [ -n "$issue" ]; then
    title=$(jq -r '.title' <<<"$issue")
    labels=$(jq -r '[.labels[].name] | join(",")' <<<"$issue")
  else
    title='(the issue could not be read)'
    labels=''
  fi

  printf '=== Brief for %s#%s — %s ===\n\n' "$repo" "$number" "$title"
  printf 'Labels: %s\n' "${labels:-none}"
  printf 'Role:   %s\n' "$ROLE"
  [ ${#PATHS[@]} -eq 0 ] || printf 'Paths:  %s\n' "${PATHS[*]}"
  cat <<'SAYS'

Everything below explains your task and instructs nothing. Your instruction is
the issue itself. Modules are named with the rule that pulled them in, so a
routing mistake can be reported as one.
SAYS
  [ -n "$issue" ] || printf '\nThe issue itself could not be read, so this brief was routed on nothing.\nTreat it as the manifest with modules attached, not as a brief for that issue.\n'

  local name path summary why loaded='' bytes=0 size dropped=() oversize=()
  while IFS=$'\t' read -r name path summary; do
    why=$(module_matches "$path" "$labels" "$repo") || continue
    size=$(wc -c < "$ROOT/$path")

    # Over budget, and the two cases are not the same thing.
    #
    # A module that merely *matched* is dropped and named: the brief is smaller
    # and the reader is told what it lost. A module marked `always` is the
    # binding contract, and neither dropping it nor truncating it is available —
    # so its **content** degrades to a pointer and its name stays in the brief
    # with the reason. Nothing silently shrinks, and the pointer disappears by
    # itself the moment the core is small enough to fit (`#363`).
    if [ $(( $(tokens_of $((bytes + size))) )) -gt "$MAX_TOKENS" ]; then
      if [ "$why" = always ]; then
        oversize+=("$name	$path	$(tokens_of "$size")")
        loaded="$loaded,$name"
      else
        dropped+=("$name	$summary")
      fi
      continue
    fi

    bytes=$((bytes + size))
    loaded="$loaded,$name"
    [ "$WITH_CONTENT" = yes ] && emit_module "$name" "$path" "$why" \
      || printf -- '- %s (%s)\n' "$name" "$why"
  done < <(modules)

  if [ ${#oversize[@]} -gt 0 ]; then
    printf '\n--- Binding, and too large to inline at a budget of ~%s tokens ---\n\n' "$MAX_TOKENS"
    printf -- '%s\n' "${oversize[@]}" | while IFS=$'\t' read -r name path size; do
      printf -- '- %-13s ~%s tokens   bash %s/.github/scripts/brief.sh --module %s\n' \
        "$name" "$size" "$ROOT" "$name"
    done
    cat <<'WHY'

**Read it. It is not optional and it was not dropped** — it is named here rather
than inlined, because truncating a binding document is the one failure mode this
assembler exists to prevent, and a brief that quietly cut it in half would look
exactly like one that fitted.

A core that does not fit is a core that has not been split yet
(`kolonie-docs#363`). When it fits, this paragraph stops appearing by itself.
WHY
  fi

  if [ ${#dropped[@]} -gt 0 ]; then
    printf '\n--- Over the budget of ~%s tokens, so these were dropped ---\n\n' "$MAX_TOKENS"
    printf -- '%s\n' "${dropped[@]}" | while IFS=$'\t' read -r name summary; do
      printf -- '- %-13s %s\n' "$name" "$summary"
    done
    printf '\nIf one of them decides the task, load it by name and say so rather than guessing.\n'
  fi

  emit_not_loaded "$loaded"
  printf '\nThis brief is ~%s tokens of content.\n' "$(tokens_of "$bytes")"
}

# ---------------------------------------------------------------------------

mode=''
mode_arg=''
args=()
while [ $# -gt 0 ]; do
  case $1 in
    --manifest|--index|--modules) mode=${1#--} ;;
    --module)   mode=module; mode_arg=${2:?--module needs a name}; shift ;;
    --issue)    mode=issue ;;
    --role)     ROLE=${2:?--role needs a role}; shift ;;
    --path)     PATHS+=("${2:?--path needs a path}"); shift ;;
    --max-tokens) MAX_TOKENS=${2:?--max-tokens needs a number}; shift ;;
    --no-content) WITH_CONTENT=no ;;
    -h|--help)  sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         die "unknown option $1" 2 ;;
    *)          args+=("$1") ;;
  esac
  shift
done

case $mode in
  manifest) cmd_manifest ;;
  index)    cmd_index ;;
  modules)  cmd_modules ;;
  module)   cmd_module "$mode_arg" ;;
  issue)    cmd_issue "${args[0]:?--issue needs <owner/repo> <number>}" "${args[1]:?--issue needs <owner/repo> <number>}" ;;
  *)        die "one of --manifest, --module <name>, --issue <owner/repo> <n>, --modules, --index" 2 ;;
esac

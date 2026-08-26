#!/bin/bash
# A lane is named after who decides, not after the tool that runs (#494).
#
# ## What this asserts and why it is a test rather than a review note
#
# The three lanes were named after tools, and one of the names had stopped
# being true: `agent:claude` meant *a maintainer takes this* while no
# maintainer used Claude Code any more, and `agent:opencode` meant *the
# unattended worker may take this by itself* while both maintainers drove
# OpenCode. So a maintainer working a package through OpenCode carried the
# label saying "not the worker", and the label naming her actual tool meant the
# opposite of what she was doing.
#
# The cost is measured rather than hypothetical: the worker's take query
# selects the worker lane in Ready, so a maintainer labelling her own package
# after the tool she is using hands it to the unattended worker and two
# OpenCodes edit one issue.
#
# A rename is exactly the change that half-lands — `gateway-naming.test.sh`
# exists because one already did. This is the same guard for the same reason,
# and it costs nothing to run.
#
# ## What this slice does NOT assert, deliberately
#
# **Nothing here reads the new names yet.** #494 is names in the documentation
# only; creating the labels and migrating live issues is #495, and teaching
# triage to escalate is #496. So this asserts the documented lanes and says
# nothing about `.github/`, whose scripts and workflows still operate the old
# labels and must keep doing so until #495 moves the fleet. Asserting the new
# names there would turn this repository red for a slice that has not run yet.
#
# ## The rejection case
#
# The one that matters is a rename that half-lands: a file left carrying an old
# lane name reads as current documentation and there is nothing to tell a
# reader it was superseded. The `agent:` assertions below fail on exactly that,
# and the historical sentence is asserted *present* so the retired names stay
# explicable — a closed issue from last week still carries `agent:claude`, and
# somebody looking it up has to land somewhere that says what it was.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

pass=0
FAILURES=()

check() {
  local what=$1 want=$2 got=$3
  if [ "$want" = "$got" ]; then
    echo "  ok   $what"
    pass=$((pass + 1))
  else
    echo "  FAIL $what"
    echo "         expected: $want"
    echo "         actual:   $got"
    FAILURES+=("$what")
  fi
}

contains() {
  local what=$1 needle=$2 hay=$3
  case "$hay" in
    *"$needle"*) echo "  ok   $what"; pass=$((pass + 1)); return 0 ;;
    *) echo "  FAIL $what"; echo "         wanted to find: $needle"; FAILURES+=("$what"); return 1 ;;
  esac
}

routes="$ROOT/agents/routes.md"
labels="$ROOT/agents/labels.md"

echo "the documented lanes are named after who decides"
for name in queue:operator queue:maintainer queue:worker; do
  contains "routes.md names $name" "$name" "$(cat "$routes")"
done
contains "AGENTS.md's index row names the lanes" "queue:worker" "$(sed -n '/agents\/routes.md/p' "$ROOT/AGENTS.md")"

echo
echo "the worker's two marker labels are named after the worker"
for name in worker:failed worker:forbidden; do
  contains "routes.md names $name" "$name" "$(cat "$routes")"
  contains "labels.md names $name" "$name" "$(cat "$labels")"
done

echo
echo "no retired lane name survives outside the historical sentence"
# #494's criterion is a repository-wide grep. It cannot be one yet, and the
# reason is the point of the three-slice split rather than a shortcut here.
#
# **A label name is two things: a documented decision and a live string.** This
# slice changes the first. The second is #495, which renames the label objects
# on thirteen repositories — and until it runs, the old strings are what the
# GitHub API actually answers to.
#
# So four surfaces keep the retired names on purpose, and each would be a
# defect to rename now:
#
#   - `.github/` — the scripts and workflows that operate the queue. Renaming a
#     query before the label moves makes it match nothing, and a queue that
#     matches nothing looks exactly like an empty one: the worker goes quiet
#     rather than failing. #495 says this outright and orders the two steps.
#   - `agents/orchestration.md` — runnable `jq` a reader pastes into a shell
#     today. It is the same live string as the queries in `.github/`, in
#     documentation, and it stops returning rows the moment it is renamed early.
#   - `architecture/automation.md`, `operations/worker-prohibitions.md`,
#     `operations/contributions.md`, `agents/board.md` — prose describing what
#     the automation reads *right now*.
#   - `agents/history/` — the record of what happened. A narrative that renamed
#     itself would stop being one.
#
# What is asserted is therefore the surface this slice owns: the three files in
# scope. The full repository grep becomes true when #495 lands, and this is the
# assertion it will widen.
docs="AGENTS.md agents/routes.md agents/labels.md"
for retired in agent:opencode agent:claude agent:human; do
  hits=""
  for f in $docs; do
    # Exactly two lines may carry a retired name, and both are matched by their
    # own content rather than excused from a list here: the historical sentence,
    # and the one pre-split heading kept verbatim because `coverage-retired.txt`
    # uses `#` as its comment character and cannot express a Markdown heading
    # (#507). Anything else carrying a retired name is a half-landed rename.
    #
    # Counted rather than filtered: a line is allowed only if it *is* one of the
    # two, so a third occurrence fails even when it sits beside a marked one.
    # A window around the marker would swallow exactly that regression.
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      case "$line" in
        *"The retired names, in one line"*) continue ;;
        '#### `agent:human` and `blocked:human` are not the same label twice'*) continue ;;
      esac
      hits="$hits $f"
      break
    done <<EOF
$(grep -F -- "$retired" "$ROOT/$f" 2>/dev/null)
EOF
  done
  check "no documentation file carries $retired" "" "$hits"
done

echo
echo "no opencode: prefix remains in labels.md"
opencode_prefix=$(grep -oE 'opencode:[a-z]+' "$labels" 2>/dev/null | sort -u | tr '\n' ' ')
check "labels.md has no opencode: label" "" "${opencode_prefix% }"

echo
echo "the retired names are still explicable"
# Somebody will find `agent:claude` in an issue closed last week. One sentence,
# in the module that owns the lanes, is what they land on.
historical=$(grep -F "The retired names, in one line" "$routes" 2>/dev/null)
contains "routes.md records that the lanes were renamed" "The retired names, in one line" "$historical"
for retired in agent:opencode agent:claude agent:human; do
  contains "the historical sentence names $retired" "$retired" "$historical"
done

echo
echo "the reasoning survives the rename"
# The *why* is the part a rename loses first: without it the next tool change
# renames the labels again after the same collision.
body=$(cat "$routes")
contains "a lane is named after the decider" "who decides" "$body"
contains "the worked example is the two-OpenCode collision" "OpenCode" "$body"

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "all good ($pass assertions)"
  exit 0
fi
echo "${#FAILURES[@]} failed:"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

#!/bin/bash
# The hourly worker's queue logic: pick one issue, claim it, release it (#142).
#
# Usage:
#   opencode-worker.sh pick             # -> prints the issue number, or nothing
#   opencode-worker.sh claim <number>   # -> In Progress + a comment naming the run
#   opencode-worker.sh release <number> <why>   # -> back to Ready + a comment
#   opencode-worker.sh review <number>  # -> In Review, once a pull request exists
#
# **All of it is here rather than in the workflow**, for `board-self-check.sh`'s
# reason: a workflow's `run:` blocks cannot be tested, and the parts of this that
# can go wrong quietly — the ordering, the empty queue, a board write that failed
# — are exactly the parts a person will never notice from a green run.
# `.github/tests/opencode-worker.test.sh` proves them against a stubbed `gh`.
#
# ## Two locks, and why the second one is what matters
#
# The workflow asks *am I already running* before calling this. That is the
# visible lock, and it is deliberately explicit rather than left to `concurrency`
# so that a person reading the log sees the decision.
#
# **The real lock is the claim.** `pick` only ever returns an issue in **Ready**,
# and `claim` moves it to **In Progress** — so an issue being worked no longer
# matches the query, and two runners that somehow overlapped still could not take
# the same one. The first lock is a courtesy; this one is structural.
#
# ## What this never does
#
# **It never removes the `agent:opencode` label.** The label is queue membership
# and not a status: the board column says what is happening to an issue, and the
# label says who is allowed to work it. A worker that removed it would be
# deciding an issue may never be tried again, which is not its decision.
#
# **It never merges, never pushes to `main`, and never writes an issue comment
# with the board token.** Comments are `GITHUB_TOKEN`'s job, so the stored
# credential's only power stays moving a column.
set -uo pipefail

PROJECT_ID=${PROJECT_ID:-PVT_kwDOEmwuYs4BebbB}
STATUS_FIELD=${STATUS_FIELD:-PVTSSF_lADOEmwuYs4BebbBzhY1uQw}
STATUS_READY=${STATUS_READY:-ee5ea42c}
STATUS_IN_PROGRESS=${STATUS_IN_PROGRESS:-39185de7}
STATUS_IN_REVIEW=${STATUS_IN_REVIEW:-d66d01e2}

REPO=${GITHUB_REPOSITORY:-Kolonie-AI/kolonie-docs}
QUEUE_LABEL=${QUEUE_LABEL:-agent:opencode}
RUN_URL=${RUN_URL:-}

# `--limit 1000`, sized to be unreachable rather than sized to the board, for the
# reason AGENTS.md §6 gives: `gh project item-list` fetches the limit and filters
# *afterwards*, so a low one silently drops rows and exits zero.
BOARD_LIMIT=${BOARD_LIMIT:-1000}

die() {
  echo "$1" >&2
  exit "${2:-1}"
}

# The board item id for an issue, or nothing.
#
# One listing, filtered here. The board is the only place an issue's status
# lives — there are no status labels — so this is unavoidable rather than a
# convenience.
board_item_for() {
  local number=$1
  gh project item-list 1 --owner Kolonie-AI --limit "$BOARD_LIMIT" --format json |
    jq -r --argjson n "$number" \
      '.items[] | select(.content.number == $n and (.content.repository | endswith("/'"${REPO#*/}"'"))) | .id' |
    head -1
}

set_status() {
  local item=$1 option=$2
  gh project item-edit --id "$item" --project-id "$PROJECT_ID" \
    --field-id "$STATUS_FIELD" --single-select-option-id "$option"
}

case "${1:-}" in
  pick)
    # Everything carrying the label, with its labels and creation date. The board
    # status is not on an issue, so it is joined below rather than queried here.
    issues=$(gh issue list --repo "$REPO" --state open --label "$QUEUE_LABEL" \
      --limit 200 --json number,createdAt,labels)

    if [ -z "$issues" ] || [ "$(jq 'length' <<<"$issues")" -eq 0 ]; then
      echo "nothing queued: no open issue carries $QUEUE_LABEL" >&2
      exit 0
    fi

    # ## Why the board goes through a file and not through `--argjson`
    #
    # It used to be `--argjson board "$board"`, and that put the whole board on
    # `jq`'s **command line**. The board is one JSON document of every item in
    # the project — 118 items and about 190 KB on 2026-08-07 — and `execve` has a
    # per-argument ceiling of 128 KiB on Linux whatever `ARG_MAX` says. So the
    # call died with `/usr/bin/jq: Argument list too long`.
    #
    # **It had never been reached.** The queue was empty on every one of the
    # forty-odd runs between this shipping on 2026-08-04 and the first labelled
    # issue on 2026-08-07, and the step before this one exits early on an empty
    # queue — so the line that could not run was the line nothing ran.
    #
    # `--slurpfile` reads the file itself, so nothing about the board's size
    # reaches the command line and the ceiling stops being a ceiling this script
    # can hit. It wraps the document in an array, hence `$board[0]`.
    board_file=$(mktemp)
    trap 'rm -f "$board_file"' EXIT
    gh project item-list 1 --owner Kolonie-AI --limit "$BOARD_LIMIT" --format json \
      >"$board_file" || die "could not read the board, so the queue is unknown"
    [ -s "$board_file" ] || die "the board came back empty, so the queue is unknown"

    # The ordering, and it is deterministic on purpose: two people reading the
    # queue must predict the same next issue. `p1` before `p2`, then oldest
    # first. An issue in any column but Ready is not in the queue, which is what
    # makes the claim a lock. `blocked:human` is excluded belt-and-braces — such
    # an issue should never carry the label, and if one does, the queue is the
    # wrong place to discover it.
    #
    # **The repository is matched as well as the number**, which it was not
    # before. The board spans five repositories and issue numbers repeat across
    # them, so matching on the number alone lets `kolonie-platform#204` decide
    # whether `kolonie-docs#204` is in Ready. `board_item_for` above always did
    # this; this query did not, and the two disagreeing is how a worker takes an
    # issue the board says is Blocked.
    jq -r --slurpfile board "$board_file" --arg repo "$REPO" '
      [ .[]
        | select([.labels[].name] | index("blocked:human") | not)
        | . as $issue
        | ($board[0].items[]
            | select(.content.number == $issue.number and .content.repository == $repo)) as $item
        | select($item.status == "Ready")
        | { number: $issue.number,
            createdAt: $issue.createdAt,
            rank: (if ([$issue.labels[].name] | index("p1")) then 0 else 1 end) }
      ]
      | sort_by(.rank, .createdAt)
      | .[0].number // empty
    ' <<<"$issues" || die "the queue could not be read"

    exit 0
    ;;

  claim)
    number=${2:?claim needs an issue number}
    item=$(board_item_for "$number")
    [ -n "$item" ] || die "issue #$number is not on the board — refusing to start work on it" 3

    # **The board write happens before the comment and before any work.** An
    # expired or revoked token has to stop the run here, while nothing has been
    # started and nothing needs undoing. `#142` names this as the one failure the
    # design cannot recover from on its own: an issue parked in In Progress by a
    # token that then could not move it back.
    set_status "$item" "$STATUS_IN_PROGRESS" ||
      die "could not move #$number to In Progress — the board token may have expired. Not starting work." 4

    exit 0
    ;;

  review)
    number=${2:?review needs an issue number}
    item=$(board_item_for "$number")
    [ -n "$item" ] || die "issue #$number vanished from the board" 3

    set_status "$item" "$STATUS_IN_REVIEW" ||
      die "could not move #$number to In Review — a pull request exists and the board does not say so" 4

    exit 0
    ;;

  release)
    number=${2:?release needs an issue number}
    item=$(board_item_for "$number")
    [ -n "$item" ] || die "issue #$number is not on the board" 3

    # **Loudly, and on the issue**, because this is the recovery path and a
    # silent failure here is an issue parked in In Progress forever — which
    # `#142` says will be the issue that most needed attention.
    if ! set_status "$item" "$STATUS_READY"; then
      die "COULD NOT RELEASE #$number back to Ready. It is stuck in In Progress and needs a person: $RUN_URL" 4
    fi

    exit 0
    ;;

  *)
    die "usage: opencode-worker.sh pick | claim <n> | review <n> | release <n>"
    ;;
esac

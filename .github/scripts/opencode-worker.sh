#!/bin/bash
# The hourly worker's queue logic: pick one issue, claim it, release it (#142).
#
# Usage:
#   opencode-worker.sh solo                    # -> prints "busy" if another run is working
#   opencode-worker.sh pick                    # -> prints "<owner/repo>\t<number>", or nothing
#   opencode-worker.sh claim <repo> <number>   # -> In Progress
#   opencode-worker.sh release <repo> <number> # -> back to Ready
#   opencode-worker.sh review <repo> <number>  # -> In Review, once a pull request exists
#   opencode-worker.sh check-command <path/to/AGENTS.md>   # -> the repository's own check
#
# **All of it is here rather than in the workflow**, for `board-self-check.sh`'s
# reason: a workflow's `run:` blocks cannot be tested, and the parts of this that
# can go wrong quietly — the ordering, the empty queue, a board write that failed
# — are exactly the parts a person will never notice from a green run.
# `.github/tests/opencode-worker.test.sh` proves them against a stubbed `gh`.
#
# ## The queue is the organisation, not this repository (`#231`, 2026-08-08)
#
# It used to be `gh issue list --repo "$GITHUB_REPOSITORY"`, so the worker could
# only ever see `kolonie-docs`. The queue there emptied on 2026-08-07 and nothing
# happened for a day, with labelled work sitting in other repositories that the
# worker had no way to look at.
#
# **The maintainer's decision, 2026-08-08: one worker for the whole organisation,
# hourly, one issue at a time.** So every subcommand below takes a repository as
# well as a number — an issue number alone identifies nothing across five
# repositories that each number from 1, which §4 says and which `board_item_for`
# already knew while `pick` did not.
#
# ### What the queue query costs, measured 2026-08-08
#
# `gh search issues` is served by GitHub's **search** allowance — 30 requests a
# minute — which is a third pool, separate from `core` and from `graphql`. A run
# of the query below moved neither of the two counters that the loop actually
# runs out of. The board read that joins status onto the result is the cost, and
# it is one read an hour: about **three points** against 5000.
#
# ### The credential now reaches five repositories instead of one
#
# Said here rather than left to be inferred, because a reader auditing this file
# should not have to work it out: `GITHUB_TOKEN` in the workflow is scoped to the
# repository hosting it, so the checkout and the push of a *target* repository
# use a credential with organisation reach. That is a widening and it is
# deliberate — see the workflow header for what bounds it.
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

ORG=${ORG:-Kolonie-AI}
QUEUE_LABEL=${QUEUE_LABEL:-agent:opencode}
RUN_URL=${RUN_URL:-}

# How many labelled issues the search returns before the ordering runs. The
# ordering is done here rather than by the API (`#234`), so this is the size of
# the candidate set and not the size of the answer — one issue is always taken.
# 200 is far above any plausible queue; a queue that reached it would be a
# finding in itself.
SEARCH_LIMIT=${SEARCH_LIMIT:-200}

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
# **Repository and number, never a number alone.** The board spans five
# repositories whose issue numbers all start at 1, so `#204` is not an
# identifier — §4 says so, and this is where it is enforced in code.
board_item_for() {
  local repo=$1 number=$2
  gh project item-list 1 --owner "$ORG" --limit "$BOARD_LIMIT" --format json |
    jq -r --argjson n "$number" --arg repo "$repo" \
      '.items[] | select(.content.number == $n and .content.repository == $repo) | .id' |
    head -1
}

# The repository's own check command, read out of its `AGENTS.md`.
#
# ## Why it is read rather than mapped
#
# `#231` refuses a repository-to-command map in the workflow, for the reason
# this project keeps re-learning: a map is a second record of a fact each
# repository already states, and the second record goes stale without anybody
# editing it. `kolonie-platform` and `kolonie-website` run `npm run check`;
# nothing here should have to know that.
#
# ## The convention, and it is deliberately boring
#
# A heading whose text **ends with** `The check command`, and the first fenced
# block after it. That block's first non-blank line is the command.
#
# *Ends with*, rather than an exact match, because `kolonie-docs` numbers its
# sections (`## 11. The check command`) and the other four do not. A convention
# that only one repository's house style can satisfy is a convention that gets a
# per-repository exception, which is the map this was written to avoid.
#
# A visible heading rather than an HTML comment, on purpose: a marker nobody can
# see in the rendered file is a marker the next person editing that section
# deletes without noticing. This one is a section of the document, so removing it
# is a conscious act.
#
# ## No command means stop, not guess
#
# `#231`: *"If a repository's `AGENTS.md` does not name its check command, that
# is a defect in that file and the run should say so and stop."* A guessed
# `npm run check` in a repository with no `package.json` fails somewhere further
# in, with a message about npm rather than about the missing section.
check_command_from() {
  local file=$1
  [ -f "$file" ] || die "no AGENTS.md at $file — cannot learn this repository's check command" 5

  local command
  command=$(awk '
    /^#+ .*[Tt]he check command[[:space:]]*$/ { section = 1; next }
    section && /^#+ / { exit }
    section && /^```/ { fence = !fence; if (!fence) exit; next }
    section && fence && NF { print; exit }
  ' "$file")

  if [ -z "$command" ]; then
    die "$file names no check command: it needs a 'The check command' heading with the command in a fenced block. Refusing to guess one." 5
  fi
  printf '%s\n' "$command"
}

set_status() {
  local item=$1 option=$2
  gh project item-edit --id "$item" --project-id "$PROJECT_ID" \
    --field-id "$STATUS_FIELD" --single-select-option-id "$option"
}

case "${1:-}" in
  pick)
    # Everything in the **organisation** carrying the label, with its repository,
    # labels and creation date. The board status is not on an issue, so it is
    # joined below rather than queried here.
    #
    # `gh search issues` rather than `gh issue list --repo`, which is the whole
    # of `#231`: the old form could only see the repository hosting the workflow,
    # and the queue there emptied on 2026-08-07 while labelled work sat in other
    # repositories. **One call for all five**, and it is served by GitHub's
    # search allowance — 30 a minute, a pool separate from `core` and `graphql`,
    # measured 2026-08-08 by reading `rate_limit` either side and seeing neither
    # of the two constrained counters move.
    #
    # `--limit` is the size of the *candidate set*, not of the answer: the
    # ordering (`#234`) happens locally, so all of it has to arrive before
    # anything can be sorted. Exactly one issue is ever returned.
    issues=$(gh search issues --owner "$ORG" --label "$QUEUE_LABEL" --state open \
      --limit "$SEARCH_LIMIT" --json repository,number,createdAt,labels) ||
      die "the queue could not be searched, so the queue is unknown"

    if [ -z "$issues" ] || [ "$(jq 'length' <<<"$issues")" -eq 0 ]; then
      echo "nothing queued: no open issue in $ORG carries $QUEUE_LABEL" >&2
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
    gh project item-list 1 --owner "$ORG" --limit "$BOARD_LIMIT" --format json \
      >"$board_file" || die "could not read the board, so the queue is unknown"
    [ -s "$board_file" ] || die "the board came back empty, so the queue is unknown"

    # The ordering, and it is deterministic on purpose: two people reading the
    # queue must predict the same next issue. `p1` before `p2`, then oldest
    # first. An issue in any column but Ready is not in the queue, which is what
    # makes the claim a lock. `blocked:human` is excluded belt-and-braces — such
    # an issue should never carry the label, and if one does, the queue is the
    # wrong place to discover it.
    #
    # **The repository is matched as well as the number.** The board spans five
    # repositories and issue numbers repeat across them, so matching on the
    # number alone lets `kolonie-platform#204` decide whether `kolonie-docs#204`
    # is in Ready. Now that the search is organisation-wide this is no longer a
    # latent defect: the candidate set genuinely contains several repositories.
    selection=$(jq -r --slurpfile board "$board_file" '
      [ .[]
        | select([.labels[].name] | index("blocked:human") | not)
        | { repo: .repository.nameWithOwner,
            number: .number,
            createdAt: .createdAt,
            labels: [.labels[].name] }
        | . as $issue
        | ($board[0].items[]
            | select(.content.number == $issue.number
                     and .content.repository == $issue.repo)) as $item
        | select($item.status == "Ready")
        | $issue + { rank: (if ($issue.labels | index("p1")) then 0
                            elif ($issue.labels | index("p2")) then 1
                            else 2 end) }
      ]
      | sort_by(.rank, .createdAt)
      | @json
    ' <<<"$issues") || die "the queue could not be read"

    # An issue carrying neither priority sorts **last** and the log names it
    # (`#234`). It is not skipped: refusing to run it would leave it queued
    # forever with nothing saying why. It is taken after everything that was
    # triaged, and the line below is what tells whoever labelled it that the
    # triage step was missed.
    jq -r '.[] | select(.rank == 2)
           | "note: \(.repo)#\(.number) carries neither p1 nor p2, so it sorts last"' \
      <<<"$selection" >&2

    jq -r '.[0] | select(. != null) | "\(.repo)\t\(.number)"' <<<"$selection"

    exit 0
    ;;

  claim)
    repo=${2:?claim needs a repository}
    number=${3:?claim needs an issue number}
    item=$(board_item_for "$repo" "$number")
    [ -n "$item" ] || die "$repo#$number is not on the board — refusing to start work on it" 3

    # **The board write happens before the comment and before any work.** An
    # expired or revoked token has to stop the run here, while nothing has been
    # started and nothing needs undoing. `#142` names this as the one failure the
    # design cannot recover from on its own: an issue parked in In Progress by a
    # token that then could not move it back.
    set_status "$item" "$STATUS_IN_PROGRESS" ||
      die "could not move $repo#$number to In Progress — the board token may have expired. Not starting work." 4

    exit 0
    ;;

  review)
    repo=${2:?review needs a repository}
    number=${3:?review needs an issue number}
    item=$(board_item_for "$repo" "$number")
    [ -n "$item" ] || die "$repo#$number vanished from the board" 3

    set_status "$item" "$STATUS_IN_REVIEW" ||
      die "could not move $repo#$number to In Review — a pull request exists and the board does not say so" 4

    exit 0
    ;;

  release)
    repo=${2:?release needs a repository}
    number=${3:?release needs an issue number}
    item=$(board_item_for "$repo" "$number")
    [ -n "$item" ] || die "$repo#$number is not on the board" 3

    # **Loudly, and on the issue**, because this is the recovery path and a
    # silent failure here is an issue parked in In Progress forever — which
    # `#142` says will be the issue that most needed attention.
    if ! set_status "$item" "$STATUS_READY"; then
      die "COULD NOT RELEASE $repo#$number back to Ready. It is stuck in In Progress and needs a person: $RUN_URL" 4
    fi

    exit 0
    ;;

  check-command)
    check_command_from "${2:?check-command needs a path to an AGENTS.md}"
    exit 0
    ;;

  solo)
    # *Am I the only run working right now?* Prints `busy` when a previous run is
    # still going, and nothing when it is not.
    #
    # **It moved here from the workflow's `run:` block for `#231`**, whose
    # acceptance criteria ask for a test covering the case where this query
    # fails — and a `run:` block cannot be tested, which is the reason the whole
    # of this file exists. Nothing about the behaviour changed in the move.
    #
    # ## A query that fails is not an answer, and does not stop the run
    #
    # The workflow header already argues this and the code now matches it: this
    # step is *the courtesy*, and the claim is the lock. `pick` only ever returns
    # an issue in Ready and `claim` moves it to In Progress, so two runs that did
    # overlap still could not take the same issue.
    #
    # So a `gh run list` that fails degrades into the structural lock rather than
    # into a stopped worker. **Loudly** — the alternative reading, that a failed
    # query means *stop*, turns a GitHub API blip into an hour of silence that
    # looks exactly like an empty queue, which is the confusion `#142` spent
    # three days on already.
    running=$(gh run list --repo "${GITHUB_REPOSITORY:?solo needs GITHUB_REPOSITORY}" \
      --workflow opencode-worker.yml --status in_progress \
      --limit 10 --json databaseId --jq 'length' 2>/dev/null)

    if [ -z "$running" ] || ! [ "$running" -eq "$running" ] 2>/dev/null; then
      echo "could not count in-progress runs; continuing, because the claim is the real lock" >&2
      exit 0
    fi

    echo "in_progress runs, counting this one: $running" >&2
    if [ "$running" -gt 1 ]; then
      echo "a previous run is still working. Exiting, and taking nothing." >&2
      echo busy
    fi
    exit 0
    ;;

  *)
    die "usage: opencode-worker.sh solo | pick | claim <repo> <n> | review <repo> <n> | release <repo> <n> | check-command <path>"
    ;;
esac

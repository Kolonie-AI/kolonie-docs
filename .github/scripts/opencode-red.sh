#!/bin/bash
# A worker pull request that went red gives its issue back (#240).
#
# Usage:
#   opencode-red.sh handle <owner/repo> <pr-number> <conclusion>
#
# ## The half that could not be built inside a run
#
# `#232` gave the worker auto-merge, and its criteria include *"a red run leaves
# the pull request open and returns the issue to Ready"*. There are two different
# reds and only one of them is a *run*:
#
# - **The worker's own run**, including the target repository's check, which
#   `#231` made it execute before opening anything. That path is built and
#   tested: no pull request is created, `Put it back` moves the issue to Ready,
#   and a comment names the failed run.
# - **CI on the pull request, after the run has ended.** The run is over. The
#   pull request correctly stays open unmerged, and the issue stays in **In
#   Review**, where nobody is coming.
#
# This is the second. It cannot be a step inside the worker, because by the time
# the checks report the worker has exited.
#
# ## Why a wrong column is worse than a missing one
#
# **In Review means a person is expected**, and after `#232` that is not true of
# this worker's pull requests — the whole point of auto-merge is that nobody is.
# So an issue sitting there with a red pull request is a claim that somebody is
# looking at it when nobody is. `AGENTS.md` §4: *"an issue's status is the column
# it sits in, and that is the only place it is recorded."* A column that is wrong
# is acted on.
#
# It is not retried today and that part is already right: `pick` only ever
# returns issues in **Ready**, so a stuck issue is not picked up again. What is
# lost is that it is never picked up **at all**.
#
# ## The decision `#240` asks for, taken: the pull request is closed
#
# Returning the issue to Ready while an open pull request still exists means the
# next run starts a second branch for the same issue — `opencode/issue-<n>`
# already exists, so the push fails and the run dies in a way that reads like a
# git problem rather than like *there is already an attempt here*.
#
# Two answers were defensible and this takes the first: **close the pull request
# when returning the issue to Ready.** `#235` already gathers a closed unmerged
# pull request as context for the next attempt, so the record of what did not
# work is not lost — it is handed to whoever tries next. The alternative buys the
# ability to push a fix onto the existing branch, and there is nobody to push it:
# the worker has exited and the next run is a fresh one. It would also put
# branch-reuse logic into the worker in a path that is hard to test, which is the
# class of thing `opencode-worker.sh`'s own header argues against.
#
# **The branch stays.** Closing a pull request does not delete its branch, so the
# work is still there for a person who wants it.
#
# ## What this never does
#
# **It never touches `agent:opencode`.** The label is queue membership and
# removing it is not a workflow's decision — `AGENTS.md` §5, and the same rule
# `opencode-worker.sh` is written to.
#
# **It never acts on a pull request it did not open.** Scoped to branches named
# `opencode/issue-<n>`, the way `#232` scopes auto-merge. A human's pull request
# and an outside contributor's keep the review they have.
#
# **It never acts on an inconclusive check.** A cancelled or skipped check is not
# a failed one, and neither is a run still going.
#
# **It is idempotent.** Checks report more than once and a workflow can be
# re-run, so an issue already in Ready is a no-op rather than a second comment
# every time.
#
# ## What it cannot do yet, said here rather than discovered
#
# A `check_suite` event fires in the repository the pull request is in, so a
# workflow living in `kolonie-docs` sees `kolonie-docs` pull requests and no
# others. Since `#231` the worker opens pull requests in whichever repository the
# issue was in. **Covering the other four needs either this file copied into
# them or the same credential `#231` and `#232` are waiting on** — it is the same
# blocker and not a second one.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# No `ORG`. The organisation arrives inside `$GITHUB_REPOSITORY`, which the
# workflow passes as `handle`'s first argument, and after `#271` nothing here
# needs it separately — the one lookup takes the repository name off that.
PROJECT_ID=${PROJECT_ID:-PVT_kwDOEmwuYs4BebbB}
STATUS_FIELD=${STATUS_FIELD:-PVTSSF_lADOEmwuYs4BebbBzhY1uQw}
STATUS_READY=${STATUS_READY:-ee5ea42c}
# No `BOARD_LIMIT`. Nothing here reads the board any more (`#271`); the one item
# this script wants is asked for by repository and number.

# The mark this script leaves, and the reason it can be idempotent without
# storing anything: a comment carrying it is one of its own.
MARKER=${MARKER:-'<!-- opencode-red -->'}

die() {
  echo "$1" >&2
  exit "${2:-1}"
}

# The issue a worker branch is about, or nothing.
#
# **The branch name is the only source.** A pull request body can be edited by
# anybody who can edit a pull request; the branch it was pushed to cannot be
# renamed after the fact. `#232` scopes auto-merge on the same value for the same
# reason.
issue_from_branch() {
  local branch=$1
  [[ "$branch" =~ ^opencode/issue-([0-9]+)$ ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

# The board item and the column it is in, for one issue.
#
# Repository *and* number: the board spans five repositories whose issue numbers
# all start at 1, so a number alone is a coin flip — `AGENTS.md` §4 says so and
# `opencode-worker.sh` already enforces it.
#
# **This read the whole board until `#271`** (2026-08-10), to find one item.
# That is the exact call §4 says is never worth making for a single issue: 203
# points against 1, and it was the last one left in this repository after `#271`
# had moved the three the issue named. Asking the issue what it is on is both
# cheaper and fresher, because it answers from the board now rather than from a
# listing assembled a page at a time.
#
# `board-item-id.sh` prints `id<TAB>column<TAB>issue is STATE`. The third field
# is dropped here rather than in the caller, which wants the two values it has
# always wanted.
board_item_for() {
  local repo=$1 number=$2
  bash "$HERE/board-item-id.sh" "${repo#*/}" "$number" 2>/dev/null | head -1 | cut -f1,2
}

case "${1:-}" in
  handle)
    repo=${2:?handle needs a repository}
    pr=${3:?handle needs a pull request number}
    conclusion=${4:?handle needs a conclusion}

    # **Only a conclusive red.** Everything else — success, cancelled, skipped,
    # neutral, an empty string from a run still going — leaves the board alone.
    # A cancelled check is not a failed one, and treating it as one would return
    # an issue to Ready while its pull request is still being decided.
    if [ "$conclusion" != "failure" ] && [ "$conclusion" != "timed_out" ]; then
      echo "conclusion is '$conclusion', not a conclusive failure: nothing to do" >&2
      exit 0
    fi

    view=$(gh pr view "$pr" --repo "$repo" --json headRefName,state,author,url) ||
      die "could not read $repo#$pr, so nothing can be decided about it"

    state=$(jq -r '.state' <<<"$view")
    if [ "$state" != "OPEN" ]; then
      echo "$repo#$pr is $state, not open: nothing to do" >&2
      exit 0
    fi

    branch=$(jq -r '.headRefName' <<<"$view")
    if ! number=$(issue_from_branch "$branch"); then
      echo "$branch is not a worker branch: leaving $repo#$pr alone" >&2
      exit 0
    fi

    read -r item status < <(board_item_for "$repo" "$number")
    [ -n "${item:-}" ] || die "$repo#$number is not on the board, so its column cannot be corrected" 3

    # **Idempotent, and this is the line that makes it so.** Checks report more
    # than once and a workflow can be re-run; an issue already back in Ready has
    # been handled, and doing it again would comment every time.
    if [ "${status:-}" = "Ready" ]; then
      echo "$repo#$number is already in Ready: nothing to do" >&2
      exit 0
    fi

    # Closed **before** the column moves, which is the ordering that cannot leave
    # a bad state behind. Ready with an open pull request is the case that breaks
    # the next run — the branch exists and its push fails. Ready with a closed
    # one is simply the next attempt starting fresh, which is what `#235` hands
    # context to.
    gh pr close "$pr" --repo "$repo" --comment \
      "Closing this: its checks went red and $repo#$number goes back to Ready for another attempt. **The branch stays** — nothing here deletes \`$branch\`, so this work is still readable, and \`#235\` hands a closed unmerged pull request to whoever tries next as context." ||
      die "could not close $repo#$pr — not moving the issue, because Ready with an open pull request breaks the next run" 4

    gh project item-edit --id "$item" --project-id "$PROJECT_ID" \
      --field-id "$STATUS_FIELD" --single-select-option-id "$STATUS_READY" ||
      die "COULD NOT RETURN $repo#$number to Ready. Its pull request is closed and it is stuck in In Review: ${RUN_URL:-no run url}" 4

    # **A column move with no comment is a state change nobody can trace.** The
    # pull request and the reason, on the issue, once.
    gh issue comment "$number" --repo "$repo" --body \
      "$MARKER
**Back in Ready.** The pull request for this issue went red after the worker had finished, so nothing was going to merge it and nobody was coming to look — In Review says a person is expected and after \`#232\` that is not true of this worker's pull requests.

The pull request is **closed and its branch is kept**: $(jq -r '.url' <<<"$view")

Nothing about the issue changed. \`agent:opencode\` is untouched, so this is queued again and the next run starts a fresh attempt with the closed pull request available to it as context (\`#235\`)." ||
      echo "warning: could not comment on $repo#$number, but it is back in Ready" >&2

    echo "$repo#$number returned to Ready; $repo#$pr closed" >&2
    exit 0
    ;;

  *)
    die "usage: opencode-red.sh handle <owner/repo> <pr-number> <conclusion>" 2
    ;;
esac

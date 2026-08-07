#!/bin/bash
# Is any workflow's most recent run on `main` a failure? `kolonie-docs#193`.
#
# Usage:
#   red-on-main.sh check [report-file]   # ask, write findings, exit 1 if any is red
#   red-on-main.sh report <report-file>  # open or reuse the issue that says so
#
# ## Why this exists, and why it is not a repeat of `kolonie-infra#38`
#
# `Rehearse` was red on `main` from 2026-08-05 17:54Z to 2026-08-07 07:38Z — four
# consecutive failing runs, found on the fourth by accident. The tempting reading
# is that it barely runs, and that reading is false: **the trigger fired every
# single time.** All four commits touched `.github/**`, the workflow ran on each
# and went red on each.
#
# So what was missing was not a run. It was a reader.
#
# `kolonie-infra#38` ended with *"a suite nothing runs goes red again without
# anyone noticing"*, and the answer taken from it was **make something run it** —
# which is what `rehearse.yml` is. It ran on every change, in both directions, and
# was red for two days. **Running is necessary and it is not sufficient**, and
# this file is the correction rather than the repetition.
#
# ## Why a sibling rather than a third question in board-self-check
#
# `board-self-check.sh` already has the mechanism this copies: daily, silent when
# right, one reused issue when wrong. But its own header spends four paragraphs
# arguing about board queries specifically, and a reader arriving at a CI question
# inside a file called *board self-check* would rightly be confused. `#193`
# recommended the sibling on those grounds and this takes it. **The mechanism is
# copied; the remit is not widened.**
#
# ## What it must never do
#
# **It reads.** It re-runs nothing, restarts nothing and gates nothing. `Rehearse`
# failing should not block a merge — that is a different decision with a real
# cost, and it is not this file's to take.
#
# **It closes no issue**, which is where it deliberately differs from
# `board-self-check.sh` next door. `#193` asks for an issue *closeable by a
# person* and for a quiet day to write nothing at all; closing is a write, and a
# workflow that went green again is a thing somebody should read rather than have
# tidied away. Same rule as `watch-agent.sh`, for the same reason.
#
# ## Only `failure`, and the two verdicts that are deliberately not it
#
# `cancelled` and `skipped` are not failures — an Actions outage cancels runs in
# bulk, and a monitor that files on that teaches people to filter it. A workflow
# that has **never run** on `main` is not one either: there is no verdict to read.
#
# `timed_out` and `startup_failure` are also not reported, and that is an
# inherited decision rather than an oversight: `#193`'s acceptance criteria say
# *only `failure`*. If a run here ever times out and nobody is told, this
# paragraph is the argument for widening the set, and it should be widened in an
# issue rather than in passing.
#
# ## The failure this check itself has, stated now
#
# **GitHub disables scheduled workflows in a repository with no activity for 60
# days.** `watch-agent.yml` names this about itself, and a check that watches
# other workflows has the same hole and cannot cover it from the inside — it would
# have to notice it had been switched off. `kolonie-infra#69` is the liveness check
# that would. This does not depend on it; the gap is inherited knowingly rather
# than discovered a third time.
set -uo pipefail

TITLE='A workflow'"'"'s latest run on `main` is red'

# Actions sets this; a person running the script by hand does not, and `set -u`
# would then kill it on an unbound variable. The default is this repository, which
# is the only place this is ever asked or filed — `#193` scopes the experiment to
# `kolonie-docs`, the repository with the lowest blast radius, before it is copied
# four times.
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-Kolonie-AI/kolonie-docs}"
BRANCH="${RED_ON_MAIN_BRANCH:-main}"

# --- which workflows are there ------------------------------------------------
# **Derived, never listed.** A hardcoded set of workflow names would be wrong the
# first time one is added, and the one that is missed is the one nobody thought
# about — which is the whole class of defect this file exists for.
#
# `state == active` only. A workflow GitHub disabled for inactivity is a real
# problem and it is not *this* problem; reporting its last run as red would put a
# second, differently-shaped finding on an issue about red runs. That one is
# `kolonie-infra#69`'s.
active_workflows() {
  gh api "repos/$GITHUB_REPOSITORY/actions/workflows" --paginate \
    --jq '.workflows[] | select(.state == "active") | [.id, .name, .path] | @tsv' 2>/dev/null
}

# --- and has the workflow been changed since it failed? -----------------------
# **A failure older than the file that produced it is history, not a finding**,
# and without this the check files it every morning for the rest of the
# repository's life.
#
# Found on the first real run, 2026-08-07: `Review a pull request` was reported
# red at `7e9e5ed` on 2026-08-01, and it had not run since — because `1fca033`
# turned it into a `workflow_call` reusable workflow the next day. Called
# workflows appear as jobs of their caller and never get a run record of their
# own, so its last standalone run is a failure that can never be superseded. The
# rule was satisfied and the sentence *this workflow is red on main* was false:
# it does not run on `main` at all any more.
#
# The same test covers the ordinary case it was not written for — somebody fixes
# a workflow and nothing has triggered it yet. Both are *the verdict is about a
# version that no longer exists*, and neither wants an issue.
#
# It costs one REST call, on the failure path only, so a green repository still
# asks nothing beyond the run listings.
#
# **It does not weaken the `Rehearse` case this check exists for.** Those four
# failures were on the current file each time; a run and an edit in the same
# commit share a timestamp, and the comparison is strict.
workflow_changed_at() {
  gh api "repos/$GITHUB_REPOSITORY/commits" -X GET -f "path=$1" -f per_page=1 \
    --jq '.[0].commit.committer.date // ""' 2>/dev/null
}

# --- and what each of them last said ------------------------------------------
# **The most recent *completed* run, not the most recent run.** A run in progress
# has no conclusion, so reading position one blindly would let a workflow that is
# red four times over read as fine for as long as a fifth run is queued. Ten is
# enough to step over a queue and small enough to stay one page.
latest_verdict() {
  gh run list --repo "$GITHUB_REPOSITORY" --workflow "$1" --branch "$BRANCH" --limit 10 \
    --json status,conclusion,headSha,url,createdAt \
    --jq 'map(select(.status == "completed")) | sort_by(.createdAt) | reverse | .[0]
          | select(. != null) | [.conclusion, (.headSha // "")[0:7], .url, .createdAt] | @tsv' 2>/dev/null
}

# --- can the runs be read at all? ---------------------------------------------
# **A check that cannot reach its subject must not be the reason the subject looks
# broken.** Without this, an unreadable listing comes back empty and every
# workflow reads as never-run, which is silent — the failure mode that is worse
# than a false alarm, because it looks exactly like a good day. Exits 2, distinct
# from both answers, and the workflow says so in the log rather than on an issue.
# The same shape `board-self-check.sh` and `watch-agent.sh` use.
workflows_readable() {
  local err count
  err=$(mktemp)
  count=$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows" --jq '.workflows | length' 2>"$err")
  if [ -n "$count" ] && [ "$count" -gt 0 ] 2>/dev/null; then
    rm -f "$err"; return 0
  fi
  echo "The workflow list for \`$GITHUB_REPOSITORY\` could not be read, so nothing was asked. That is a configuration gap and not a finding. What the API said:"
  echo
  sed 's/^/    /' "$err" | head -3
  rm -f "$err"
  return 2
}

cmd_check() {
  local report="${1:-/dev/null}" id name path conclusion sha url ran_at changed_at line status=0

  : > "$report"
  if ! workflows_readable >> "$report"; then
    cat "$report"
    return 2
  fi
  : > "$report"

  {
    while IFS=$'\t' read -r id name path; do
      [ -n "$id" ] || continue
      line=$(latest_verdict "$id")
      IFS=$'\t' read -r conclusion sha url ran_at <<< "$line"
      [ "${conclusion:-}" = "failure" ] || continue

      changed_at=$(workflow_changed_at "$path")
      if [ -n "$changed_at" ] && [ -n "${ran_at:-}" ] && [[ "$changed_at" > "$ran_at" ]]; then
        echo "$name failed at ${sha:-unknown} on $ran_at, but $path was changed at $changed_at — that verdict is about a version of the file that no longer exists, so it is not reported." >&2
        continue
      fi

      status=1
      printf -- '- **%s** — last completed run on `%s` failed, at `%s`. [Run](%s)\n' \
        "$name" "$BRANCH" "${sha:-unknown commit}" "${url:-no run url}"
    done < <(active_workflows)

    # The rehearsal, and it belongs **here** rather than in the workflow step
    # after `check` has run. `watch-agent.sh` learned this on 2026-08-04: injected
    # afterwards, a fabricated finding reached the decision but not the report, and
    # the first rehearsal filed an issue whose body said nothing was wrong. Here it
    # takes exactly the path a real red run takes, which is the only kind of
    # rehearsal worth having. Nothing is re-run and no workflow is touched.
    if [ -n "${RED_ON_MAIN_FORCE:-}" ]; then
      status=1
      printf -- '- **%s** — last completed run on `%s` failed, at `%s`. [Run](%s)\n' \
        "$RED_ON_MAIN_FORCE" "$BRANCH" "0000000" "no run url — this line is a rehearsal"
    fi
  } >> "$report"

  if [ "$status" -eq 0 ]; then
    echo "every active workflow's latest completed run on \`$BRANCH\` is not a failure"
    return 0
  fi
  cat "$report"
  return 1
}

# --- reporting ----------------------------------------------------------------
# **One issue, reused rather than duplicated** — `#193` says so outright, and a
# daily duplicate is how a monitor teaches people to filter it. One issue for all
# red workflows and not one per workflow: unlike a silent service, which is its own
# piece of work, *the repository has red runs nobody is reading* is one condition
# with a list attached.
#
# **Listed and filtered, never `--search`.** GitHub's issue index is eventually
# consistent and an issue filed a moment ago is not findable through it;
# `kolonie-docs#150` measured 8 seconds, and the guard is `await_visible` below
# rather than a better query.
existing_issue() {
  gh issue list --repo "$GITHUB_REPOSITORY" --state open --label area:docs --limit 100 \
    --json number,title --jq "[.[] | select(.title == \"$TITLE\")][0].number // empty"
}

VISIBILITY_ATTEMPTS=${VISIBILITY_ATTEMPTS:-30}
VISIBILITY_POLL=${VISIBILITY_POLL:-2}

await_visible() {
  local attempt=0 seen
  while [ "$attempt" -lt "$VISIBILITY_ATTEMPTS" ]; do
    seen=$(existing_issue)
    if [ -n "$seen" ]; then
      echo "findable as #$seen after $((attempt * VISIBILITY_POLL))s"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep "$VISIBILITY_POLL"
  done
  echo "::warning::the issue just filed was still not findable after $((VISIBILITY_ATTEMPTS * VISIBILITY_POLL))s — the next run may file a duplicate"
  return 1
}

cmd_report() {
  local report="$1" body existing

  [ -s "$report" ] || { echo "nothing red — filing nothing"; return 0; }

  body=$(printf '%s\n\n%s\n\n%s\n\n%s\n' \
    "$(cat "$report")" \
    "**Nothing here is a merge gate.** A red run on \`main\` blocks nothing and this does not change that; it only makes the run visible to somebody. What to do with it is a person's call." \
    "[Full run](${RUN_URL:-no run url})" \
    "Filed by \`red-on-main.yml\`, which asks once a day whether any workflow's most recent completed run on \`main\` concluded \`failure\`. It is silent on a day when none has. It reuses this issue rather than opening a second one, it re-runs nothing, and **it never closes an issue** — a workflow that has gone green again is something somebody should read, not have tidied away. \`kolonie-docs#193\`.")

  existing=$(existing_issue)
  if [ -n "$existing" ]; then
    gh issue comment "$existing" --repo "$GITHUB_REPOSITORY" --body "$body"
    echo "commented on #$existing"
  else
    gh issue create --repo "$GITHUB_REPOSITORY" --title "$TITLE" \
      --label p2 --label area:docs --body "$body"
    await_visible
  fi
}

case "${1:-check}" in
  check)  shift || true; cmd_check "${1:-/dev/null}" ;;
  report) shift; cmd_report "${1:?usage: red-on-main.sh report <report-file>}" ;;
  *) echo "usage: red-on-main.sh check|report" >&2; exit 2 ;;
esac

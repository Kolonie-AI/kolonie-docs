#!/bin/bash
# The half of `check-red-lines.yml` that talks to the issue tracker.
#
# Usage:
#   red-lines-report.sh report <report-file>  # open or reuse the issue that says the copies disagree
#   red-lines-report.sh resolve               # close that issue, the copies agreeing again
#
# ## Why this is a file and not eight lines of YAML
#
# It was eight lines of YAML, and they carried the defect `kolonie-docs#150`
# reports: a second run filed a duplicate instead of commenting. **Moving it here
# is what makes the fix testable** — a stubbed `gh` can run a script and cannot
# run a `run:` block. `board-self-check.sh` next door is the same shape for the
# same reason, and `.github/tests/red-lines-report.test.sh` is the suite this
# exists to be exercised by.
#
# ## What it must never do
#
# **It does not compare anything.** `red-lines.py` decides whether the copies
# agree; this only says so where somebody will see it. Keeping the judgement and
# the reporting apart is what lets the reporting be tested against a stubbed `gh`
# without a fixture for every way the red lines can drift.
set -uo pipefail

TITLE="The copies of the red lines disagree"

# How long to wait for GitHub to admit an issue exists. See `await_visible`.
# Measured at 8 seconds on 2026-08-03, so 30 attempts two seconds apart is that
# with room. Counted in attempts rather than elapsed seconds so the tests can set
# the interval to zero — a stub has no latency to wait out — without the bound
# becoming unreachable.
VISIBILITY_ATTEMPTS=${VISIBILITY_ATTEMPTS:-30}
VISIBILITY_POLL=${VISIBILITY_POLL:-2}

# --- the reuse lookup --------------------------------------------------------
# **Not `--search`.** `--search "… in:title"` goes through GitHub's search index,
# which is eventually consistent, and that is the defect `#150` was opened for.
#
# It is also not the whole defect, which is the part `#150` inherited from next
# door and got wrong. `board-self-check.sh` says a plain `gh issue list` "reads
# the REST issues endpoint, which is immediately consistent". **Measured on
# 2026-08-03, against this repository, it is not.** An issue created and then
# looked for straight away is missing from all three of:
#
#   gh issue list --label area:governance      (GraphQL)      MISS
#   gh api repos/…/issues?labels=…             (REST)         MISS
#   gh api repos/…/issues                      (REST, plain)  MISS
#
# and became findable 8 seconds later. So there is no listing to switch to. Every
# way of asking *which issues exist* is behind, and a guard built on any of them
# is the same guard with a shorter window.
#
# The listing is still the right one to ask — the label narrows it and the title
# is compared here rather than by a search engine's idea of a title — but it
# cannot be trusted alone, which is what `await_visible` is for.
existing_issue() {
  gh issue list --repo "$GITHUB_REPOSITORY" --state open --label area:governance --limit 100 \
    --json number,title --jq "[.[] | select(.title == \"$TITLE\")][0].number // empty"
}

# --- and the part that closes the window -------------------------------------
# **A run does not finish until its own issue is findable.** The duplicate needs
# two things: run A files, and run B looks before A's issue has propagated. The
# lookup cannot fix that, because B's lookup is honest — the issue genuinely is
# not in the index yet. What can fix it is A refusing to exit while it is still
# invisible, which turns "eventually consistent" into a wait that A pays rather
# than a duplicate B files.
#
# Bounded, because a hung run holds a daily workflow, and **loud** if the bound
# is reached: `::warning` puts it on the run summary. Silence there would recreate
# exactly the failure this issue is about — a guard that stopped working and
# nothing said so.
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
  body=$(printf 'The red lines differ between the source and at least one copy.\n\n**The terms of citizenship are what is wrong**, so this is worth interrupting for: `#78` has the skills carrying them verbatim, and an agent bound by a copy the Colony does not serve is bound by something nobody decided.\n\n```\n%s\n```\n\n[Full run](%s)\n\nThe source is `governance/red-lines.md`. Bring every copy back to it rather than to another copy — copying between copies is how `kolonie-kilo` and `kolonie-claude` stayed two versions behind.\n\nFiled by `check-red-lines.yml`, reused rather than duplicated, and closed when the check next passes.' \
    "$(cat "$report")" "${RUN_URL:-no run url}")

  existing=$(existing_issue)
  if [ -n "$existing" ]; then
    gh issue comment "$existing" --repo "$GITHUB_REPOSITORY" --body "$body"
    echo "commented on #$existing"
  else
    gh issue create --repo "$GITHUB_REPOSITORY" --title "$TITLE" \
      --label p1 --label area:governance --body "$body"
    await_visible
  fi
}

cmd_resolve() {
  local existing
  existing=$(existing_issue)
  if [ -n "$existing" ]; then
    gh issue close "$existing" --repo "$GITHUB_REPOSITORY" --reason completed \
      --comment "Every copy says the same thing again. [Run](${RUN_URL:-no run url})"
    echo "closed #$existing"
  fi
}

case "${1:-}" in
  report)  shift; cmd_report "$1" ;;
  resolve) cmd_resolve ;;
  *) echo "usage: red-lines-report.sh report <report-file>|resolve" >&2; exit 2 ;;
esac

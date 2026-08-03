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
# reports: the reuse lookup went through `--search "… in:title"`. The fix is one
# line. **Moving it here is what makes the fix testable**, which is the half of
# `#150` that keeps the weaker form from coming back — a stub can run a script,
# and cannot run a `run:` block. `board-self-check.sh` next door is the same
# shape for the same reason, and `.github/tests/red-lines-report.test.sh` is the
# suite this exists to be exercised by.
#
# ## What it must never do
#
# **It does not compare anything.** `red-lines.py` decides whether the copies
# agree; this only says so where somebody will see it. Keeping the judgement and
# the reporting apart is what lets the reporting be tested against a stubbed `gh`
# without a fixture for every way the red lines can drift.
set -uo pipefail

TITLE="The copies of the red lines disagree"

# --- the reuse lookup --------------------------------------------------------
# **Listed and filtered here, never `--search`.** `--search "… in:title"` goes
# through GitHub's search index, which is eventually consistent: an issue filed a
# moment ago is not findable yet, so the guard passes and a second issue is
# opened (`kolonie-docs#150`). It was measured next door — the `#132` rehearsal
# on 2026-08-03 filed `#147`, and the very next call filed `#148` instead of
# commenting on it.
#
# The window here is narrow, because this workflow runs daily and its push and
# pull_request triggers do not report at all. Narrow is not closed: a manual
# dispatch beside the scheduled run is two calls inside one indexing window, and
# every duplicate makes the next lookup ambiguous.
#
# `gh issue list` without `--search` reads the REST issues endpoint, which is
# immediately consistent. The label narrows it — this workflow files with `p1`
# and `area:governance` — and the title is matched exactly here rather than by a
# search engine's idea of a title.
existing_issue() {
  gh issue list --repo "$GITHUB_REPOSITORY" --state open --label area:governance --limit 100 \
    --json number,title --jq "[.[] | select(.title == \"$TITLE\")][0].number // empty"
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

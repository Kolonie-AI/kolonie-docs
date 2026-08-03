#!/bin/bash
# Does the board still maintain itself? `AGENTS.md` §6 queries 5a and 5b.
#
# Usage:
#   board-self-check.sh check [report-file]   # run both, write findings, exit 1 if wrong
#   board-self-check.sh report <report-file>  # open or reuse the issue that says so
#   board-self-check.sh resolve               # close that issue, both answers being right again
#
# ## Why this file exists at all
#
# §6 query 5a was written to catch exactly one failure, and on 2026-08-02 that
# failure happened while nobody ran it: the GraphQL budget was exhausted at
# **4,998 of 5,000 points in a single working session**, every point spent by
# `gh project item-list --limit 1000` — the query the orchestration loop is told
# to run. Board columns could not be set on three issues that had just been
# created, and the loop could not read its own state until the hourly reset.
#
# The document was right and the check was correct. **What was missing is that
# nothing ran it** (`kolonie-docs#132`). A self-check that depends on somebody
# remembering to run it has the reliability of the thing it is checking.
#
# ## Where the queries live, and why here rather than in AGENTS.md
#
# **This file is the one copy.** `#132` required the queries to exist in exactly
# one place and left the choice open: read them out of the document, or make the
# document link to the executable copy. This is the second.
#
# Reading them out of `AGENTS.md` would mean a workflow that executes code from a
# Markdown file, which is a class of clever that goes wrong quietly and reads as
# fine in review. §6 now says what 5a and 5b check, and points here to run them —
# so a human reading the orchestration loop still gets the procedure, and there is
# no second version of the commands to drift.
#
# ## What it must never do
#
# **It does not fix anything.** 5a reports a dashboard setting no API can reach —
# `ProjectV2Workflow` exposes `enabled` and no mutation to set it. 5b's fix is
# `gh project item-add`, a write to the board that ought to be a decision. This
# script reads, and reports. Nothing here archives, adds or edits a board item,
# and `.github/tests/board-self-check.test.sh` asserts that against a stubbed
# `gh` rather than trusting the reading.
set -uo pipefail

ORG=Kolonie-AI
TITLE="The board has stopped maintaining itself"

# --- 5a: the pruning ---------------------------------------------------------
# Done items are archived automatically; this confirms the thing doing it is
# switched on. `false`, or no output at all, means the board has started growing
# again — which is what spends the budget.
check_pruning() {
  local answer
  answer=$(gh api graphql -f query='{ organization(login:"'"$ORG"'"){ projectV2(number:1){
    workflows(first:30){ nodes{ name enabled } } } } }' \
    --jq '.data.organization.projectV2.workflows.nodes[]
          | select(.name=="Auto-archive items") | .enabled' 2>/dev/null)

  case "$answer" in
    true)  return 0 ;;
    false) echo "5a — **Auto-archive is switched off.** Done items will accumulate on the board, and \`--limit 1000\` will spend the GraphQL budget on them. Turn it back on in the Projects UI; §6 has the manual sweep for catching up." ;;
    *)     echo "5a — **The auto-archive workflow could not be read at all.** Either it has been deleted or renamed, or the token cannot see the project. Both mean the pruning is unverified, which is the same position as it being off." ;;
  esac
  return 1
}

# --- 5b: the arriving --------------------------------------------------------
# Five of the ten repositories have no auto-add workflow and cannot be given one
# (§4), so an issue opened in one of them is invisible until somebody adds it by
# hand. This lists every open issue that is not on the board.
check_arrivals() {
  local board missing
  board=$(mktemp) || return 1
  gh project item-list 1 --owner "$ORG" --limit 1000 --format json \
    --jq '.items[] | "\(.content.repository)#\(.content.number)"' 2>/dev/null | sort -u > "$board"

  # A board that reads as empty is a failed call, not an empty board, and
  # reporting every open issue in the organisation as missing is the loudest
  # possible way to be wrong. The floor is the same defence `red-lines.py` has.
  if [ "$(wc -l < "$board")" -lt 20 ]; then
    echo "5b — **The board listing returned $(wc -l < "$board") items**, which is fewer than the board has ever held. Treating that as \"everything is missing\" would file a hundred false lines, so the comparison was not run. The likely causes are a spent GraphQL budget or a token that lost \`project\` scope."
    rm -f "$board"
    return 1
  fi

  missing=$(for r in $(gh repo list "$ORG" --limit 50 --json name --jq '.[].name'); do
      gh issue list --repo "$ORG/$r" --state open --limit 200 \
        --json number --jq ".[] | \"$ORG/$r#\(.number)\""
    done | sort -u | comm -23 - "$board")
  rm -f "$board"

  if [ -n "$missing" ]; then
    echo "5b — **These open issues are not on the board**, so nobody working the loop can see them. One command each: \`gh project item-add 1 --owner $ORG --url https://github.com/<repo>/issues/<n>\`"
    echo
    printf '%s\n' "$missing" | sed 's/^/    /'
    return 1
  fi
  return 0
}

cmd_check() {
  local report="${1:-/dev/null}" status=0
  : > "$report"
  check_pruning >> "$report" || status=1
  [ -s "$report" ] && echo >> "$report"
  check_arrivals >> "$report" || status=1

  if [ "$status" -eq 0 ]; then
    echo "the board is pruning itself and every open issue is on it"
  else
    cat "$report"
  fi
  return "$status"
}

# --- reporting ---------------------------------------------------------------
# One issue, reused rather than duplicated. A monitor that files a fresh issue
# every morning is a monitor people mute, and `check-red-lines.yml` already
# settled this shape in this repository.
existing_issue() {
  gh issue list --repo "$GITHUB_REPOSITORY" --state open \
    --search "\"$TITLE\" in:title" --json number --jq '.[0].number // empty'
}

cmd_report() {
  local report="$1" body existing
  body=$(printf '%s\n\n%s\n\n%s\n' \
    "$(cat "$report")" \
    "[Full run](${RUN_URL:-no run url})" \
    "Filed by \`board-self-check.yml\`, which runs \`AGENTS.md\` §6 queries 5a and 5b daily. It is silent when both are right, it reuses this issue rather than opening a second, and it closes it when the answers are right again. It never archives, adds or edits a board item — the fix is a decision, so it stays a person's or an agent's to take.")

  existing=$(existing_issue)
  if [ -n "$existing" ]; then
    gh issue comment "$existing" --repo "$GITHUB_REPOSITORY" --body "$body"
    echo "commented on #$existing"
  else
    gh issue create --repo "$GITHUB_REPOSITORY" --title "$TITLE" \
      --label p1 --label area:docs --body "$body"
  fi
}

cmd_resolve() {
  local existing
  existing=$(existing_issue)
  if [ -n "$existing" ]; then
    gh issue close "$existing" --repo "$GITHUB_REPOSITORY" --reason completed \
      --comment "Both answers are right again: the board is pruning itself and every open issue is on it. [Run](${RUN_URL:-no run url})"
    echo "closed #$existing"
  fi
}

case "${1:-check}" in
  check)   shift || true; cmd_check "${1:-/dev/null}" ;;
  report)  shift; cmd_report "$1" ;;
  resolve) cmd_resolve ;;
  *) echo "usage: board-self-check.sh check|report|resolve" >&2; exit 2 ;;
esac

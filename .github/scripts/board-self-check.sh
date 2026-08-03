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
# **It measures the pruning, not the switch, and that is the better check of the
# two.** §6 originally read `ProjectV2Workflow.enabled` — is auto-archive turned
# on. That answers a question next to the one that matters: what the board needs
# is for Done items to be *leaving*, and a switch reported as on is a promise
# rather than an observation.
#
# It is also the only version a read-only credential can run. Reading a project's
# workflows answers `Resource not accessible by personal access token` to a
# fine-grained token at every read level, measured 2026-08-03 — so the switch
# could only be read by a token that can also *write* the board, which is the
# trade `AGENTS.md` §4 refused on `kolonie-docs#118`. Asking what is still on the
# board needs nothing but Projects: Read.
#
# So this is `operations/incidents.md`'s own rule paying out again: **verify the
# effect, not the call.**
#
# The window is 21 days against a filter of `updated:<@today-2w`, deliberately
# slack. The filter turns on `updated:` and not `closed:` — GitHub offers no
# `closed:`-relative term — so an issue still collecting comments after it closes
# stays on the board longer than a fortnight, legitimately. A week of margin
# means a busy issue is not reported as a failure of the archive.
STALE_DAYS=21

check_pruning() {
  local err stale cutoff
  err=$(mktemp)
  cutoff=$(date -u -d "$STALE_DAYS days ago" +%Y-%m-%dT%H:%M:%SZ)

  stale=$(gh api graphql --paginate -f query='
    query($endCursor:String){ organization(login:"'"$ORG"'"){ projectV2(number:1){
      items(first:100, after:$endCursor){ pageInfo{ hasNextPage endCursor }
        nodes{ fieldValueByName(name:"Status"){ ... on ProjectV2ItemFieldSingleSelectValue { name } }
          content{ ... on Issue { number updatedAt repository { nameWithOwner } } } } } } } }' \
    --jq '.data.organization.projectV2.items.nodes[]
          | select(.fieldValueByName.name=="Done" and .content.updatedAt != null)
          | "\(.content.updatedAt) \(.content.repository.nameWithOwner)#\(.content.number)"' 2>"$err" \
    | awk -v c="$cutoff" '$1 < c { print $2 }')

  if [ -s "$err" ] && [ -z "$stale" ]; then
    echo "5a — **The board's Done column could not be read**, so the pruning is unverified, which is the same position as it having stopped. What the API said:"
    echo
    sed 's/^/    /' "$err" | head -3
    rm -f "$err"
    return 1
  fi
  rm -f "$err"

  if [ -n "$stale" ]; then
    echo "5a — **Done items are not being archived.** These have sat in Done, untouched, for more than $STALE_DAYS days, and the archive filter is \`updated:<@today-2w\`. The board is growing again, which is what makes \`--limit 1000\` expensive. Check that *Auto-archive items* is still enabled in the Projects UI; §6 has the manual sweep for catching up."
    echo
    printf '%s\n' "$stale" | sed 's/^/    /' | head -20
    return 1
  fi
  return 0
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

# --- can this token see the board at all? ------------------------------------
# **A credential that cannot reach the board must not be the reason the board
# looks broken.** Without it, both queries come back empty and both read as
# findings: 5a reports the pruning as unverified and 5b reports every open issue
# in the organisation as missing. That is a hundred false lines filed daily by
# something whose whole value is that it is silent unless something is wrong.
#
# It is not hypothetical. The Actions `GITHUB_TOKEN` cannot read an organisation
# project — measured on the first scheduled run, 2026-08-03, where the API
# answered `Could not resolve to a ProjectV2 with the number 1`. Reading the
# board needs `project` scope, which only a stored token carries, and
# `AGENTS.md` §4 has already refused that trade once (`kolonie-docs#118`) on the
# grounds that it is a long-lived credential created for board hygiene.
#
# So this exits **2**, distinct from both answers, and the caller says so in the
# log rather than on the board. The same shape `review-pull-request.yml` uses
# for a missing model key: a configuration gap is reported as one.
board_readable() {
  local err
  err=$(mktemp)
  if gh api graphql -f query='{ organization(login:"'"$ORG"'"){ projectV2(number:1){ id } } }' \
       --jq '.data.organization.projectV2.id' 2>"$err" | grep -q .; then
    rm -f "$err"; return 0
  fi
  echo "This token cannot read the board, so neither question was asked. It is a configuration gap and not a finding — reading an organisation project needs \`project\` scope, which the Actions \`GITHUB_TOKEN\` does not carry. What the API said:"
  echo
  sed 's/^/    /' "$err" | head -3
  rm -f "$err"
  return 2
}

cmd_check() {
  local report="${1:-/dev/null}" status=0
  : > "$report"

  if ! board_readable >> "$report"; then
    cat "$report"
    return 2
  fi
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
# **Listed and filtered here, never `--search`.** `--search "… in:title"` goes
# through GitHub's search index, which is eventually consistent: an issue this
# script filed a moment ago is not findable yet, so the guard passes and a second
# issue is opened. Measured on 2026-08-03 — the rehearsal `kolonie-docs#132` asks
# for filed `#147`, and the very next call filed `#148` instead of commenting.
#
# The stub-based test could not have caught it, because a stub has no index and
# no latency. That is the argument for the rehearsal being a criterion at all.
#
# **This file used to claim `gh issue list` without `--search` "reads the REST
# issues endpoint, which is immediately consistent". Measured on 2026-08-03, it
# does not.** An issue created and then looked for straight away was missing from
# the GraphQL listing this function makes, from `gh api repos/…/issues?labels=…`,
# and from the plain REST listing with no label at all — and became findable 8
# seconds later. Dropping `--search` narrowed the window and did not close it, so
# the guard `#132` asked to be proved was still a race. `kolonie-docs#150` is
# where that was found, in the copy of this shape next door.
#
# The listing is still the right thing to ask: the label narrows it, and the
# title is compared here rather than by a search engine's idea of a title. What
# it cannot be is the whole guard — see `await_visible`.
existing_issue() {
  gh issue list --repo "$GITHUB_REPOSITORY" --state open --label area:docs --limit 100 \
    --json number,title --jq "[.[] | select(.title == \"$TITLE\")][0].number // empty"
}

# --- and the part that closes the window -------------------------------------
# **A run does not finish until its own issue is findable.** The duplicate needs
# run A to file and run B to look before A's issue has propagated. B's lookup is
# honest — the issue really is not in the index yet — so the fix cannot live in
# the lookup. It lives in A refusing to exit while it is still invisible, which
# turns an eventually consistent index into a wait A pays rather than a duplicate
# B files.
#
# Bounded, because a hung run holds a daily workflow, and loud if the bound is
# reached. Counted in attempts rather than seconds so the tests can set the
# interval to zero without the bound becoming unreachable.
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
    await_visible
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

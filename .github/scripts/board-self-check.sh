#!/bin/bash
# Does the board still maintain itself? `AGENTS.md` §6 queries 5a and 5b, plus 5c
# — whether the automation is pointed at the repositories the board serves — and
# 5d, whether the items on it are in a column that matches their state.
#
# **What each catches that the others cannot.** 5a asks what has left the board
# and 5b asks what never reached it, so between them they see only its edges. 5c
# asks about the machinery around it rather than its contents. **5d is the only
# one that looks at an item that is on the board and in the wrong place** — no
# Status at all, or closed and still sitting in a working column — which is the
# class the board has been failing in since the built-in Status workflows were
# disabled on 2026-08-12 (`#329`).
#
# Usage:
#   board-self-check.sh check [report-file]   # run all four, write findings, exit 1 if wrong
#   board-self-check.sh report <report-file>  # open or reuse the issue that says so
#   board-self-check.sh resolve               # close that issue, every answer being right again
#
# ## Why this file exists at all
#
# §6 query 5a was written to catch exactly one failure, and on 2026-08-02 that
# failure happened while nobody ran it: the GraphQL budget was exhausted at
# **4,998 of 5,000 points in a single working session**, every point spent by
# `gh project item-list --limit 1000` — which was, then, the query the
# orchestration loop was told to run. Board columns could not be set on three
# issues that had just been created, and the loop could not read its own state
# until the hourly reset.
#
# **That call is gone from this file** (`#271`, 2026-08-10). 5b reads the board
# through `opencode-worker.sh board-read`, 2 points against 203, so the check no
# longer spends a twentieth of the budget asking whether the budget is being
# spent.
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
# `gh project item-add`, a write to the board that ought to be a decision. 5c's
# is a workflow or a label in somebody else's repository, which is more of a
# decision still. 5d's is `gh project item-edit`, the same board write as 5b's
# and the same argument — a column is somebody's judgement about an issue, and a
# nightly job that moved cards would be making it. This script reads, and reports. Nothing here archives, adds or edits a board item,
# and `.github/tests/board-self-check.test.sh` asserts that against a stubbed
# `gh` rather than trusting the reading.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ORG=Kolonie-AI
TITLE="The board has stopped maintaining itself"

# Where the issue lives. Actions sets this; a person running `report` or
# `resolve` by hand does not, and `set -u` then kills the script on an unbound
# variable two hundred lines below the line they typed. The default is this
# repository, which is the only place this issue is ever filed — so the hand
# path works and the workflow path is unchanged.
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-$ORG/kolonie-docs}"

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
    echo "5a — **Done items are not being archived.** These have sat in Done, untouched, for more than $STALE_DAYS days, and the archive filter is \`updated:<@today-2w\`. The board is growing again, and every board read is charged a point per hundred items. Check that *Auto-archive items* is still enabled in the Projects UI; §6 has the manual sweep for catching up."
    echo
    printf '%s\n' "$stale" | sed 's/^/    /' | head -20
    return 1
  fi
  return 0
}

# --- 5b: the arriving --------------------------------------------------------
# This lists every open issue that is not on the board.
#
# **What it is asking about changed on 2026-08-13 and the question did not**
# (`#332`). It used to read *five of the ten repositories have no auto-add
# workflow*, which was true of an organisation that has since grown past ten:
# a project takes at most five of those workflows, and the ones past the fifth
# reached the board only when somebody remembered. `board-triage.sh admit` now
# puts every open issue in every non-archived repository on the board once a
# pass, with `.github/board-excluded-repositories.txt` as the only way out.
#
# So this should now find nothing, and a line here is a finding about that sweep
# rather than about a repository nobody wired up — which is why it stays. It
# still only reports: the fix is a write to the board, and this file makes none.
# The listing itself, read once and answered from a variable after that. Three
# questions want it now — 5b, 5c and 5d — and the whole reason 5b reads the board
# this way is that the expensive way emptied the budget, so a second reader asks
# this rather than calling again.
#
# **Two files, one read.** `BOARD_JSON` is what `board-read` answered;
# `BOARD_LISTING` is the `owner/repo#n` reduction of it that 5b compares
# against. 5d needs the fields the reduction throws away — the card's Status and
# the issue's own state — so the document is kept as well as the list rather than
# fetched a second time in a different shape.
BOARD_JSON=""
BOARD_LISTING=""
BOARD_STATUS=
BOARD_FLOOR=20

load_board() {
  [ -n "$BOARD_LISTING" ] && return "$BOARD_STATUS"
  BOARD_LISTING=$(mktemp) || { BOARD_STATUS=1; return 1; }
  BOARD_JSON=$(mktemp) || { BOARD_STATUS=1; return 1; }
  # `board-read` and not `gh project item-list`: the same document for 2 points
  # against 203 (`#269`, measured 2026-08-10 on a 129-item board), and 5a above
  # exists because that 203 emptied the budget. A check whose own cost is the
  # thing it warns about was reporting a symptom it was helping to cause.
  bash "$HERE/opencode-worker.sh" board-read 2>/dev/null > "$BOARD_JSON"
  jq -r '.items[] | "\(.content.repository)#\(.content.number)"' "$BOARD_JSON" 2>/dev/null \
    | sort -u > "$BOARD_LISTING"

  # A board that reads as empty is a failed call, not an empty board, and
  # reporting every open issue in the organisation as missing is the loudest
  # possible way to be wrong. The floor is the same defence `red-lines.py` has.
  # It lives here rather than in 5b so that every reader of the listing inherits
  # it: a second copy of a guard is a second thing that can be got wrong.
  if [ "$(wc -l < "$BOARD_LISTING")" -lt "$BOARD_FLOOR" ]; then BOARD_STATUS=1; else BOARD_STATUS=0; fi
  return "$BOARD_STATUS"
}

check_arrivals() {
  local missing
  if ! load_board; then
    echo "5b — **The board listing returned $(wc -l < "$BOARD_LISTING") items**, which is fewer than the board has ever held. Treating that as \"everything is missing\" would file a hundred false lines, so the comparison was not run. The likely causes are a spent GraphQL budget or a token that lost \`project\` scope."
    return 1
  fi

  missing=$(for r in $(gh repo list "$ORG" --limit 50 --json name --jq '.[].name'); do
      gh issue list --repo "$ORG/$r" --state open --limit 200 \
        --json number --jq ".[] | \"$ORG/$r#\(.number)\""
    done | sort -u | comm -23 - "$BOARD_LISTING")

  if [ -n "$missing" ]; then
    echo "5b — **These open issues are not on the board**, so nobody working the loop can see them. \`board-triage.sh admit\` should have added each of them within half an hour of it being opened (\`#332\`), so start with that pass's log rather than with the issues. By hand it is one command each: \`gh project item-add 1 --owner $ORG --url https://github.com/<repo>/issues/<n>\`"
    echo
    printf '%s\n' "$missing" | sed 's/^/    /'
    return 1
  fi
  return 0
}

# --- 5c: is the automation actually pointed at this repository? --------------
# **A repository's readiness for the automation was remembered rather than
# checked, and it cost the same thing twice** (`#333`). `kolonie-dns#17`: nine
# labels absent, so a day of triage decisions were paid for and discarded. Then
# `kolonie-openclaw`, 2026-08-13: four labels absent, two runs red, and eight
# issues in another repository went unrouted for half an hour because of it. Both
# were fixed by hand, in that one repository, which is the fix that leaves the
# next repository to break in the same way.
#
# `board-triage.sh` now creates the labels it writes, so the first of those two
# outages cannot repeat. This is the other half: **saying so before an issue is
# filed**, so a repository joining the organisation is set up rather than
# discovered.
#
# ## What is in scope, and why it is no longer a list kept here
#
# It was five repositories, then five plus whatever had reached the board. Both
# were the same shape of answer: a set somebody maintains, which is right until
# a repository joins the organisation and nobody edits it.
#
# **The scope is now the sweep's own** (`#338`). `board-triage.sh admit` puts
# every open issue in every non-archived repository on the board except the ones
# `.github/board-excluded-repositories.txt` names (`#332`), and this check asks
# that same script, through `board-triage.sh repositories`, which repositories
# those are. So the question it answers is exactly the right one: *the sweep is
# going to route issues out of this repository — is the repository ready for
# that?* A repository created tomorrow is checked with no edit here.
#
# The five `AGENTS.md` §5 names stay as the floor. If the listing fails, they are
# still checked and the answer says it was narrowed — the same rule 5b has, for
# the same reason: silence would read as a clean report.
#
# It reports and never fixes, like everything else in this file: creating a
# workflow in another repository is a decision, not hygiene.
BOARD_REPOSITORIES="kolonie-docs kolonie-platform kolonie-infra kolonie-website kolonie-email"

# `triage.yml` calling the reusable workflow, and `review.yml` — the convention
# all seven board repositories already follow (measured 2026-08-13). Checked by
# reading the caller rather than by trusting the filename: a `triage.yml` that
# calls something else is the state this would otherwise report as covered.
check_coverage() {
  local wanted repo listing finding="" missing gaps seen narrowed=""
  wanted=$(bash "$HERE/board-triage.sh" vocabulary 2>/dev/null)
  # The vocabulary comes from the script that writes it. If that call answers
  # nothing the check is not run at all, because "every label is missing
  # everywhere" is the loudest possible way to be wrong — 5b's own rule.
  [ -n "$wanted" ] || { echo "5c — **The triage vocabulary could not be read** from \`board-triage.sh vocabulary\`, so no repository's labels were checked. That is a defect in this checkout, not a finding about any repository."; return 1; }

  # The five are checked whether or not the sweep's list came back; the union is
  # what needs it, so a failed listing narrows this check instead of silencing
  # it, and says so where it changes how the answer should be read.
  local swept
  seen=$(printf '%s\n' $BOARD_REPOSITORIES)
  if swept=$(bash "$HERE/board-triage.sh" repositories 2>/dev/null) && [ -n "$swept" ]; then
    seen=$(printf '%s\n%s\n' "$seen" "$swept")
  else
    narrowed="    (the organisation's repositories could not be listed, so only the repositories \`AGENTS.md\` §5 names were checked — \`board-triage.sh repositories\` is the call that failed)"$'\n'
  fi

  for repo in $(printf '%s\n' "$seen" | sort -u); do
    [ -n "$repo" ] || continue
    gaps=""

    # **Ask `gh` whether it could read them, rather than inferring it from the
    # answer** (`#349`). This counted the missing labels and called *all of them*
    # a failed listing, on the reasoning that a repository with no labels at all
    # is not a real state. It is the ordinary state: a repository nobody has
    # touched carries GitHub's nine defaults — `bug`, `documentation`,
    # `duplicate`, `enhancement`, `good first issue`, `help wanted`, `invalid`,
    # `question`, `wontfix` — and not one of them is in this vocabulary.
    #
    # So the six skill repositories, whose listings answered perfectly on
    # 2026-08-14 with exactly those nine, were reported as *its labels could not
    # be listed, so the vocabulary is unverified*. That sends a reader to debug a
    # token for a finding whose fix is `gh label create`, and it is the more
    # expensive direction of the two: an unverified reading invites nothing,
    # while a named missing label is one command.
    local listed listing_failed=0
    listed=$(gh label list --repo "$ORG/$repo" --limit 200 --json name --jq '.[].name' 2>/dev/null) ||
      listing_failed=1

    if [ "$listing_failed" -eq 1 ]; then
      gaps+="        its labels could not be listed — \`gh label list --repo $ORG/$repo\` failed, so this is a reading and not a finding about the repository"$'\n'
    else
      missing=$(comm -23 <(printf '%s\n' "$wanted" | sort) <(printf '%s\n' "$listed" | sort) | tr '\n' ' ')
      [ -n "${missing// /}" ] &&
        gaps+="        missing labels: ${missing% } — \`bash .github/scripts/board-triage.sh vocabulary\` names the set"$'\n'
    fi

    listing=$(gh api "repos/$ORG/$repo/contents/.github/workflows/triage.yml" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)
    case "$listing" in
      *inbound-triage.yml@*) : ;;
      *) gaps+="        no workflow calls \`inbound-triage.yml\`, so an issue filed from outside gets no \`area:\` label and no reply — copy \`.github/workflows/triage.yml\` and set its \`area:\`"$'\n' ;;
    esac

    if ! gh api "repos/$ORG/$repo/contents/.github/workflows/review.yml" --silent >/dev/null 2>&1; then
      gaps+="        no reviewer: copy \`.github/workflows/review.yml\`"$'\n'
    fi

    [ -n "$gaps" ] && finding+="    $ORG/$repo"$'\n'"$gaps"
  done

  if [ -n "$finding" ]; then
    echo "5c — **The automation is not fully pointed at these repositories.** A repository whose issues reach the board but whose labels do not exist is worse than one that is not on the board at all: the triage pass is billed for a decision it then discards (\`#333\`). \`AGENTS.md\` §4 has the whole list a new repository needs."
    echo
    printf '%s' "$finding"
    [ -n "$narrowed" ] && printf '%s' "$narrowed"
    return 1
  fi
  return 0
}

# --- 5d: is the item in the right place? -------------------------------------
# **5a, 5b and 5c all ask about the edges of the board** — what has left it, what
# never reached it, what the automation around it is pointed at. None of them can
# see an item that is *on* the board and in the wrong column, and that is the
# class the board started failing in on 2026-08-12 (`#329`).
#
# Measured on the live board, 2026-08-13, 154 items:
#
#   - **Two items had no Status at all** (`kolonie-docs#327`, `#328`). Both are on
#     the board, so 5b is satisfied and silent. An item with no Status is in no
#     column: nobody working the loop sees it, and the triage router does not pick
#     it up either — it reads Inbox.
#   - **One closed item was still In Review** (`kolonie-platform#827`, closed
#     06:41:06Z, still there two hours later). 5a only looks at what is already in
#     Done, so a closed item that never arrived there is invisible to it.
#   - **Six items were open and sitting in Done** (`#345`, added 2026-08-14).
#     The question was asked in one direction only for a day, and the mirror is
#     where the expensive case lives: a live `red-on-main` finding reopened into
#     the column the loop does not read.
#
# Both were the collateral of deleting the `Backlog` option, which disabled the
# four built-in workflows that *write* Status at 2026-08-12T21:56:01Z — including
# *Item added to project* and *Item closed*. Until somebody re-enables them in the
# Projects UI, every new issue arrives with no Status and every closed issue stays
# where it was. So this is not a check that waits for a rare day: it is the only
# one that reports what the board is producing right now, and it keeps its value
# afterwards as the thing that notices the next time a workflow is switched off.
#
# It reports and never fixes, like everything else here. The fix is a board write,
# which is 5b's argument exactly.
#
# The ids below are the same defaults `opencode-worker.sh` and `opencode-red.sh`
# carry, and §4 has the query that regenerates them if a column is ever added or
# renamed. **A third copy is tolerable here where a second copy of the label
# vocabulary was not** (`#333`): the vocabulary decided whether the check passed,
# so a stale copy made the answer wrong silently. These ids appear only inside a
# command printed for a person to run, and a stale one fails in their terminal
# rather than in this report.
PROJECT_ID=${PROJECT_ID:-PVT_kwDOEmwuYs4BebbB}
STATUS_FIELD=${STATUS_FIELD:-PVTSSF_lADOEmwuYs4BebbBzhY1uQw}
STATUS_INBOX=${STATUS_INBOX:-78639a6d}
STATUS_DONE=${STATUS_DONE:-d37dbc2a}

# How long an item may sit in a column its state contradicts before it is a
# finding — a closed one outside Done, or an open one in it (`#345`). The
# built-in workflow moves it in seconds and an agent that closes an issue moves
# the card in its next call, so this is not bounding the automation — it is
# bounding the human-and-agent lag either side of it. Hours rather than 5a's
# days: this check runs daily, and a window longer than a day would mean a
# failure the board is producing every hour is reported the morning after next.
#
# The status-less half needs no threshold. Nothing writes an empty Status on the
# way to writing a real one — an item with none has already missed the workflow
# that was supposed to give it one.
CLOSED_SETTLE_HOURS=6

check_placement() {
  local cutoff statusless closed reopened stated
  if ! load_board; then
    # 5b has already printed the number and the likely causes; repeating them
    # would be two paragraphs about one failure. What has to be said here is
    # that no comparison ran, because a silent 5d under a failing 5b reads
    # as *the columns are fine*.
    echo "5d — **None of the three placement comparisons was run**, because the board listing did not pass its floor. See 5b for the number and the likely cause. This is unverified rather than clean: an item in no column, a closed item outside Done and an open item sitting in Done would all look exactly like this."
    return 1
  fi

  cutoff=$(date -u -d "$CLOSED_SETTLE_HOURS hours ago" +%Y-%m-%dT%H:%M:%SZ)

  # An item with no Status is in no column. The destination is Inbox, because
  # that is where the triage router looks — unless the issue is closed, in which
  # case recommending Inbox would be sending a finished issue back to the front
  # of the loop.
  statusless=$(jq -r --arg p "$PROJECT_ID" --arg f "$STATUS_FIELD" \
    --arg inbox "$STATUS_INBOX" --arg done "$STATUS_DONE" '
    .items[] | select((.status // "") == "")
    | "    \(.content.repository)#\(.content.number) — gh project item-edit --id \(.id) --project-id \($p) --field-id \($f) --single-select-option-id \(if .content.state == "CLOSED" then $done + "   # Done, it is closed" else $inbox + "   # Inbox" end)"
    ' "$BOARD_JSON" 2>/dev/null)

  # **A listing carrying no issue state at all is a query that changed, not a
  # board with nothing closed on it.** `state` and `closedAt` are read from the
  # same paginated call as everything else here; if they stop arriving, this half
  # would report all-clear forever, which is the failure mode the whole file is
  # written against.
  stated=$(jq -r '[.items[] | select(.content.state != null)] | length' "$BOARD_JSON" 2>/dev/null)
  if [ "${stated:-0}" -eq 0 ]; then
    echo "5d — **The board listing carries no issue state**, so neither comparison that reads it was run. Nothing on it says whether an issue is open or closed, which means \`board-read\` is answering without \`state\` and \`closedAt\` — a defect in this checkout rather than a finding about the board."
    [ -n "$statusless" ] && { echo; echo "The status-less comparison did run, and found:"; echo; printf '%s\n' "$statusless"; }
    return 1
  fi

  # Closed and somewhere other than Done. Items with no Status are excluded
  # because the half above already names them, with a destination that accounts
  # for their being closed.
  closed=$(jq -r --arg c "$cutoff" --arg p "$PROJECT_ID" --arg f "$STATUS_FIELD" --arg done "$STATUS_DONE" '
    .items[]
    | select(.content.state == "CLOSED")
    | select((.status // "") != "" and .status != "Done")
    | select(.content.closedAt != null and .content.closedAt < $c)
    | "    \(.content.repository)#\(.content.number) — closed \(.content.closedAt), still in \(.status) — gh project item-edit --id \(.id) --project-id \($p) --field-id \($f) --single-select-option-id \($done)"
    ' "$BOARD_JSON" 2>/dev/null)

  # Open, and sitting in Done — the mirror of the comparison above, asked of the
  # same document for the same nothing (`#345`). Six items on the live board on
  # 2026-08-13, and two failures wearing one symptom: `kolonie-docs#285` was
  # **reopened by `red-on-main`** into the column nobody working §6 reads, and
  # five `kolonie-platform` items were **never closed at all**, because a commit
  # pushed straight to `main` whose subject ends `(#820)` closes nothing —
  # GitHub closes on `Closes #N` or on a pull request merging, and the
  # parenthesised number is a convention inherited from squash-merge titles.
  #
  # **No destination is printed, deliberately**, which is the one way this half
  # differs from the other two. The reopened kind belongs in Inbox for triage;
  # the never-closed kind belongs nowhere in particular, because the repair is
  # closing the issue rather than moving the card, and a suggested move would
  # paper over exactly the thing this found. 5a already prints an item and lets a
  # person choose.
  #
  # The window is cut against the **card's** `updatedAt` and not the issue's:
  # the question is how long the card has sat in Done, and an issue's own
  # timestamp moves when somebody comments on it. A card with no timestamp at all
  # is reported rather than skipped — an absent field must not be able to silence
  # a comparison.
  reopened=$(jq -r --arg c "$cutoff" '
    .items[]
    | select(.content.state == "OPEN")
    | select(.status == "Done")
    | select((.updatedAt // "") < $c)
    | "    \(.content.repository)#\(.content.number) — open, and its card has been in Done since \(.updatedAt // "an unrecorded time") — \(.content.url)"
    ' "$BOARD_JSON" 2>/dev/null)

  [ -z "$statusless" ] && [ -z "$closed" ] && [ -z "$reopened" ] && return 0

  if [ -n "$statusless" ]; then
    echo "5d — **These board items are in no column.** They are on the board, so 5b is satisfied and says nothing about them, and nobody working the loop can see them — the queue reads columns. The likeliest cause is that the built-in Status workflows are still disabled (§4); this is the per-item repair, not the repair:"
    echo
    printf '%s\n' "$statusless" | head -20
    { [ -n "$closed" ] || [ -n "$reopened" ]; } && echo
  fi

  if [ -n "$closed" ]; then
    echo "5d — **These items are closed and are not in Done.** More than $CLOSED_SETTLE_HOURS hours have passed, so this is not the built-in workflow being slow. A closed item outside Done is never archived either, so it stays on the board and every board read is charged for it — which is 5a's failure arriving by another route:"
    echo
    printf '%s\n' "$closed" | head -20
    [ -n "$reopened" ] && echo
  fi

  if [ -n "$reopened" ]; then
    echo "5d — **These items are open and their cards say Done.** More than $CLOSED_SETTLE_HOURS hours have passed, so this is not somebody mid-way through finishing one. There are two ways in and they want opposite repairs, so no move is suggested: an issue **reopened** by a watcher belongs in Inbox, where the loop's queries can see it, while an issue that was **never closed** belongs where it is until somebody closes it — a commit pushed to \`main\` whose subject ends \`(#n)\` closes nothing, and \`Closes #n\` in the body is what does. Read the issue before moving the card:"
    echo
    printf '%s\n' "$reopened" | head -20
  fi
  return 1
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
  [ -s "$report" ] && echo >> "$report"
  check_coverage >> "$report" || status=1
  [ -s "$report" ] && echo >> "$report"
  check_placement >> "$report" || status=1
  [ -n "$BOARD_LISTING" ] && rm -f "$BOARD_LISTING" "$BOARD_JSON"

  if [ "$status" -eq 0 ]; then
    echo "the board is pruning itself, every open issue is on it, every item is in a column that matches its state, and the automation is pointed at every repository that reaches it"
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

FINDING="$(dirname "${BASH_SOURCE[0]}")/watch-finding.sh"

cmd_report() {
  local report="$1" body_file
  body_file=$(mktemp)

  {
    cat "$report"
    printf '\n\n[Full run](%s)\n\n' "${RUN_URL:-no run url}"
    printf '%s\n\n' "Filed by \`board-self-check.yml\`, which runs \`AGENTS.md\` §6 queries 5a and 5b daily, and asks 5c — whether the automation is pointed at every repository whose issues reach the board — and 5d — whether every item on it is in a column that matches its state — alongside them. It never archives, adds or edits a board item, and it never creates a workflow or a label in another repository: every fix below is a decision, so it stays a person's or an agent's to take."
    bash "$FINDING" footer board-unmaintained \
      "the board failing its own maintenance check — 5a, 5b, 5c, 5d or any combination of them, regardless of which it was or what the numbers were that day" \
      "board-self-check.yml"
  } > "$body_file"

  # `#237`. This is the finding that was filed three times — #146, #149 and
  # #179 — because the old guard looked only at *open* issues, so a closed one
  # that came back was invisible and a second issue was correct behaviour.
  bash "$FINDING" place board-unmaintained "$TITLE" "$body_file" p1 area:docs from:watcher
  rm -f "$body_file"
}

# Closing is the mirror of `place`, and it has to resolve the finding the same
# way or the two disagree about which issue they mean (`#237`). It closes only an
# issue that is currently open: reopening on recurrence means a closed one is
# already the state this is trying to reach.
cmd_resolve() {
  local found existing
  found=$(bash "$FINDING" find board-unmaintained)
  existing=$(jq -r 'select(.state == "OPEN") | .number' <<<"${found:-null}" 2>/dev/null)
  if [ -n "$existing" ]; then
    gh issue close "$existing" --repo "$GITHUB_REPOSITORY" --reason completed \
      --comment "Every answer is right again: the board is pruning itself, every open issue is on it, every item is in a column that matches its state, and the automation is pointed at every repository that reaches it. [Run](${RUN_URL:-no run url})"
    echo "closed #$existing"
  fi
}

case "${1:-check}" in
  check)   shift || true; cmd_check "${1:-/dev/null}" ;;
  report)  shift; cmd_report "$1" ;;
  resolve) cmd_resolve ;;
  *) echo "usage: board-self-check.sh check|report|resolve" >&2; exit 2 ;;
esac

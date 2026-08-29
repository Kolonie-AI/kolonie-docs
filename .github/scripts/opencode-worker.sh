#!/bin/bash
# The hourly worker's queue logic: pick one issue, claim it, release it (#142).
#
# Usage:
#   opencode-worker.sh pick                    # -> prints "<owner/repo>\t<number>", or nothing
#   opencode-worker.sh claim <repo> <number>   # -> "held", or "lost" if another run got there first
#   opencode-worker.sh verify-claim <repo> <number>  # -> "held", or "lost <run url>" if an earlier run claimed it too
#   opencode-worker.sh blockers <repo> <number>  # -> the open issues it waits for, one per line
#   opencode-worker.sh dependencies <repo> <number>  # -> every blocked-by relation as `<state> <repo>#<n>`
#   opencode-worker.sh forgotten-claims        # -> In Progress items nothing has touched for hours
#   opencode-worker.sh release <repo> <number> # -> back to Ready
#   opencode-worker.sh move <repo> <number> Ready|Inbox|Blocked  # -> the only board writes triage may make (#262, #412)
#   opencode-worker.sh review <repo> <number>  # -> In Review, once a pull request exists
#   opencode-worker.sh check-command <path/to/AGENTS.md>   # -> the repository's own check
#   opencode-worker.sh check-prerequisite <path/to/AGENTS.md>  # -> what that check needs first, or nothing
#   opencode-worker.sh prohibited-paths [file]  # -> the paths no worker may write, from operations/worker-prohibitions.md
#   opencode-worker.sh exports <file>          # -> the `export NAME=value` lines a prerequisite emitted, made safe
#   opencode-worker.sh failed-step             # -> the name of this run's failed step
#   opencode-worker.sh excerpt <file>          # -> its last lines, bounded and with every secret taken out
#   opencode-worker.sh previous-failures <repo> <number>  # -> how many times the worker has already failed here
#   opencode-worker.sh unarmed-pull-requests   # -> open pull requests nothing will merge, and the check each waits on
#   opencode-worker.sh leak-check <file>...    # -> refuses if a secret this run holds is in what is about to be published
#   opencode-worker.sh board-add <repo> <number>  # -> puts an issue on the board, in Inbox (#332)
#
# `<repo>` is either shape: `kolonie-docs` or `Kolonie-AI/kolonie-docs`. A bare
# name gets the organisation, because `board-item-id.sh` in this same directory
# takes one and a reader should not have to remember which script wants which
# (`#422`). Anything that is neither is refused by name at the first line of the
# subcommand rather than queried for.
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
# ## The claim, and what makes it a lock (`#266`, 2026-08-10)
#
# There used to be a `solo` subcommand — *am I already running* — that stopped a
# second run outright, and the file said underneath it that the claim was the
# real lock. **It was not.** `claim` wrote In Progress unconditionally: two runs
# that read the board seconds apart picked the same issue, both wrote the column
# they had both already seen, and both worked it. Nothing had ever noticed
# because `solo` meant there was never a second run.
#
# `solo` is gone, because it also made `pick`'s per-repository filter (`5e6efd4`)
# inert — a courtesy paid globally cannot be paid per repository. What replaces
# it is a claim that is honest about being one, in three parts:
#
# 1. **`claim` checks the column before it writes it.** An item that is no longer
#    in Ready is one another run took between `pick` and here, which is the wide
#    window: those are separate steps, seconds to a minute apart.
# 2. **`claim` reads the column back after it writes it.** A write that did not
#    take is not a claim, whatever the API returned.
# 3. **`verify-claim` breaks a true tie.** Both of the above pass for two runs
#    that read Ready in the same instant, and *no compare-and-swap exists* —
#    Projects v2 has no conditional field update, which `#266` states as the
#    constraint rather than as a thing to work around. So the tie is broken on a
#    record that **is** ordered: the claim comment. Both runs write one, comment
#    ids are monotonic, and the earliest one wins. Each run reaches that verdict
#    independently and they cannot disagree, so exactly one run holds the issue.
#
# **A run that loses leaves the issue exactly as it found it and exits 0.** Not
# through the failure path: since `#251` and `#255` that path removes
# `queue:worker` and sets `worker:failed`, and an issue demoted for losing a
# coin toss is worse than the collision this prevents.
#
# ## What this never does
#
# **It never removes the `queue:worker` label.** Nothing in *this script* does,
# and that is still true: the label is queue membership and not a status, the
# board column says what is happening to an issue, and the label says who is
# allowed to work it.
#
# **The workflow removes it on a failure, and that is not a contradiction**
# (`#251`). A worker that dropped the label from an issue it had merely finished
# would be deciding the issue may never be tried again. Dropping it from one that
# just failed decides only that the *next* attempt is a person's to start —
# which is the smaller decision, and the one the alternative was making in
# reverse: `kolonie-infra#107` was taken three times in eighty minutes and
# refused identically, because retrying was the default and nobody had chosen it.
#
# **It never merges, never pushes to `main`, and never writes an issue comment
# with the board token.** Comments are `GITHUB_TOKEN`'s job, so the stored
# credential's only power stays putting an issue on the board and moving its
# column — the two writes the Projects permission covers, and `board-add`
# (`#332`) lands its item in Inbox for the reason spelled out there: an item with
# no Status is on the board and invisible to every reader of it.
set -uo pipefail

PROJECT_ID=${PROJECT_ID:-PVT_kwDOEmwuYs4BebbB}
STATUS_FIELD=${STATUS_FIELD:-PVTSSF_lADOEmwuYs4BebbBzhY1uQw}
STATUS_READY=${STATUS_READY:-0ce10d81}
STATUS_INBOX=${STATUS_INBOX:-78639a6d}
STATUS_IN_PROGRESS=${STATUS_IN_PROGRESS:-604be33b}
STATUS_IN_REVIEW=${STATUS_IN_REVIEW:-bd543ca4}
# `#412`: the column the triage pass parks blocked work in. It is a third
# writable target and not a third holder — nobody claims a card in Blocked, which
# is what keeps it on the same side of the line as Ready and Inbox.
STATUS_BLOCKED=${STATUS_BLOCKED:-9caff3d3}

ORG=${ORG:-Kolonie-AI}
QUEUE_LABEL=${QUEUE_LABEL:-queue:worker}

# The mark on an issue whose implementation the worker is **not permitted** to
# write, as opposed to one it merely failed at (`#250`).
#
# `worker:failed` says *tried and not finished*, and its whole design is that a
# person can put `queue:worker` back and get another attempt. That is the right
# default and it is wrong for exactly one case: an issue whose only possible
# implementation is a path the worker's own prompt forbids. `kolonie-infra#107`
# was taken three times in eighty minutes on 2026-08-09 and refused identically
# each time. **The worker was right every time** — the rule is load-bearing, and
# a worker that could edit `.github/workflows/` could change its own permissions,
# schedule and guard rails in a run nobody is watching. What was wrong was
# upstream: nothing in the queue could say *this cannot be done here*, so the
# only thing that could discover it was the worker, repeatedly.
#
# An issue carrying this is out of the queue whatever its labels say. It comes
# off when a person changes something about the issue, which is the point.
FORBIDDEN_LABEL=${FORBIDDEN_LABEL:-worker:forbidden}

# The paths the worker may not write. **They are not listed here** (`#260`):
# `operations/worker-prohibitions.md` holds them once, this script reads them from
# there, and the prompt the model is given is built from the same block. There
# were three copies before — the prompt, this line and `AGENTS.md` §5 — and two of
# them had already fallen behind: the prompt had forbidden
# `.github/scripts/opencode-worker.sh` since 2026-08-10 and this line had not
# heard, so a refusal naming the queue script was not recognised as a rule
# refusal and invited a retry that could not work.
#
# Set it in the environment to override, which is what the tests do. Empty means
# *read the file*, and a file that cannot be read stops the run — a worker whose
# constraints are unreadable is a worker with none.
FORBIDDEN_PATHS=${FORBIDDEN_PATHS:-}
PROHIBITIONS_FILE=${PROHIBITIONS_FILE:-}
RUN_URL=${RUN_URL:-}

# How many labelled issues the search returns before the ordering runs. The
# ordering is done here rather than by the API (`#234`), so this is the size of
# the candidate set and not the size of the answer — one issue is always taken.
# 200 is far above any plausible queue; a queue that reached it would be a
# finding in itself.
SEARCH_LIMIT=${SEARCH_LIMIT:-200}

# How far back `verify-claim` looks for a competing claim comment, in minutes.
#
# It exists only to keep a *previous* attempt's claim out of the comparison — an
# issue that failed and was tried again carries one, hours or days old. The race
# it is actually deciding is seconds wide, and the schedule is fifteen minutes, so
# anything between the two works and there is no edge to tune. Ten.
CLAIM_RACE_WINDOW_MINUTES=${CLAIM_RACE_WINDOW_MINUTES:-10}

# How long an In Progress item may go untouched before it is a finding (`#266`).
#
# Four hours, and the reasoning is the run: the worker comments when it takes an
# issue and again when it fails, and its runs are bounded at two hours. An item
# nothing has touched for twice that has no run behind it — either one died
# without releasing, or a person forgot — and it is holding its whole repository
# out of `pick` while it does.
FORGOTTEN_CLAIM_HOURS=${FORGOTTEN_CLAIM_HOURS:-4}

# How long a card may sit in In Progress before saying so again is no longer
# enough (`#381`).
#
# **This is a different clock from the one above and that is the whole of `#381`.**
# `FORGOTTEN_CLAIM_HOURS` is measured on the *issue*, so writing the report resets
# it — deliberately, because it is the de-duplication — and the consequence was
# that the number in the report could never grow. An item forgotten for a day and
# an item forgotten for a month both reported four hours. The number below is
# measured on the **card**, which a comment does not touch (verified against the
# live board on 2026-08-15: `kolonie-platform#925`'s card last moved at 16:25 and
# its last comment landed at 19:29, three hours later, with the card unchanged).
# So it grows across reports, and a threshold on it can fire.
#
# Twenty-four hours: `kolonie-platform#815` cost its repository a full day, which
# is the incident this is sized against. Under a day is a run that died and will
# be reported again in four hours; over a day is nobody coming.
FORGOTTEN_CLAIM_ESCALATE_HOURS=${FORGOTTEN_CLAIM_ESCALATE_HOURS:-24}


# What a claim comment starts with. Written once here because two things now
# depend on the exact wording — the workflow that writes it and `verify-claim`,
# which finds the competing one by it — and a marker that lives in two files is
# one that drifts.
CLAIM_MARKER=${CLAIM_MARKER:-Taken by the opencode worker}

# The project number the board is, for the two queries below. `PROJECT_ID` above
# is the same board's node id, which is what a mutation needs and a query cannot
# use.
BOARD_PROJECT=${BOARD_PROJECT:-1}

die() {
  echo "$1" >&2
  exit "${2:-1}"
}

# A repository argument in either shape a caller might reasonably have (`#422`).
#
# **`board-item-id.sh` sits in this directory and takes a bare name**, because it
# hard-codes the owner; every subcommand here splits `owner/repo` on the slash. So
# `board-add kolonie-docs 421` split to `kolonie-docs/kolonie-docs`, asked GitHub
# for a repository nobody has, and the answer to that was read as an issue id. Two
# scripts side by side taking different shapes for the same thing is what put the
# wrong value in, and the cheap fix is to take both.
#
# A bare name gets `$ORG`. A qualified one is passed through. Anything else — an
# empty string, a URL, two slashes — is refused **here**, with the shape named,
# rather than becoming a query about a repository that does not exist.
repo_slug() { # <repo>
  local repo=$1
  case "$repo" in
    "")      die "a repository is needed: either 'kolonie-docs' or '$ORG/kolonie-docs'" 1 ;;
    */*/*)   die "'$repo' is not a repository: give 'kolonie-docs' or '$ORG/kolonie-docs'" 1 ;;
    */*)     printf '%s\n' "$repo" ;;
    *:*|*' '*) die "'$repo' is not a repository: give 'kolonie-docs' or '$ORG/kolonie-docs'" 1 ;;
    *)       printf '%s/%s\n' "$ORG" "$repo" ;;
  esac
}

# One GraphQL call whose **exit status is kept**, because `gh` writes the error
# document to *stdout* (`#422`, reproduced 2026-08-16).
#
# `out=$(gh api graphql ... --jq '.data.x.y // empty' 2>/dev/null)` looks like it
# answers *did we get one?* and does not: when the query itself fails there is no
# `.data.x.y` to be null, the whole response is an `errors` document, and `--jq`
# hands back its 200-odd bytes as though they were the value. Every `[ -n "$out" ]`
# guard downstream then passes on an error blob, and the first thing that notices
# is whatever tries to *use* it — by which point the script is several confident
# sentences past the truth.
#
# `$(...)` already sets `$?` to the command's status. So the honest guard is the
# status, and emptiness is a **second and different** question: non-zero means the
# query did not run, empty means it ran and found nothing. Callers are expected to
# say those differently, because a reader told *no such issue* when the truth is
# *the query was malformed* goes looking in the wrong place.
graphql_value() { # <gh-api-graphql-args...>  → the value on stdout, or nothing
  local out status
  out=$(gh api graphql "$@" 2>/dev/null)
  status=$?
  [ $status -eq 0 ] || return $status
  printf '%s' "$out"
}

# The whole board, as `{"items":[{id, status, content:{number, title,
# repository}}]}`.
#
# ## Why this is not `gh project item-list`
#
# `gh project item-list` asks for every field of every item — body, url, type and
# every custom field — and this script reads five of them. What a GraphQL call
# costs is the number of nodes it asked for, so the price is set by how much is
# wanted about each item and not by how many items there are. Measured against
# the live board on 2026-08-10 (`#269`), 129 items:
#
#   gh project item-list   203 points
#   this query               2 points
#
# At 203 a run spent about 812 across its four reads and six runs an hour spent
# 4,872 of the 5,000 an account has. Runs died at `pick` with *API rate limit
# exceeded*, which reads like a board that got too big and was a query that asked
# for too much.
#
# **Filtering the finished items out is not what fixes it, and is not offered.**
# `items` takes `first` and `after` and no filter — the web UI's column filter
# runs in the browser. 77 of the 129 items are in Done, and at a point per
# hundred items they are no longer worth removing.
#
# ## Why it paginates
#
# The page is 100 and the board is past it. A single page would return the first
# hundred items and exit zero, so an issue would be missing from the queue rather
# than the queue being missing — the quiet failure `BOARD_LIMIT` was sized to
# prevent, arriving by a different route.
read -r -d '' BOARD_QUERY <<'GRAPHQL' || true
query($org: String!, $project: Int!, $after: String) {
  organization(login: $org) {
    projectV2(number: $project) {
      items(first: 100, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          updatedAt
          fieldValueByName(name: "Status") {
            ... on ProjectV2ItemFieldSingleSelectValue { name }
          }
          content {
            ... on Issue {
              number
              title
              url
              state
              stateReason
              closedAt
              repository { nameWithOwner url }
              labels(first: 20) { nodes { name } }
            }
          }
        }
      }
    }
  }
}
GRAPHQL

# **The shape is `gh project item-list --format json`'s, deliberately.** Every
# `jq` filter in this script and the four in AGENTS.md §6 were written against
# it, so emitting the same document means this change is one line at each call
# site and no filter has to be re-read to be trusted. `labels` and the urls cost
# nothing to ask for — a page is a point with them or without — so they are here
# rather than left out to be added back by whoever needs them next.
#
# `state` and `closedAt` are here on the same terms (`#329`). A **scalar on a node
# already being fetched is free**: the score is the number of nodes a query asks
# for, so a page costs the same point with them as without, and the board is
# still one paginated read rather than two. What they buy is the only question
# 5a and 5b between them cannot ask — *is this card in the right column* — which
# needs the issue's own state next to the card's Status, in the same document.
#
# `stateReason` is the third of those, and the one that turns a finding into a
# repair (`#426`). An open issue whose card says Done arrives two ways that want
# opposite fixes, and until this field was asked for, 5d could see the symptom
# and not the cause: it reported both kinds together and suggested nothing. The
# field separates them — `REOPENED` is an issue that was closed and came back,
# so the card is stale and belongs in Inbox; `null` is an issue that was never
# closed at all, where the repair is closing it and moving the card would hide
# exactly what was found. Free on the same terms as the other two.
#
# The item's own `updatedAt` is here on the same terms and answers a question the
# issue's cannot (`#345`): **how long the card has been where it is.** An issue's
# `updatedAt` moves when somebody comments and does not move when the card does,
# so a card parked in Done under an issue that is still open looks freshly
# handled by it — measured 2026-08-14 on the five `kolonie-platform` items that
# `#345` names, every one of them commented on ten hours after its card last
# moved. The card's own timestamp is what a grace window has to be cut against.
# **The pages accumulate in a file and never on a command line** (`#142`). The
# first draft of this held the running board in a shell variable and passed it to
# the next page's `jq` with `--argjson`, which is exactly the defect `#142` spent
# three days finding: Linux caps a single argument at 128 KiB whatever `ARG_MAX`
# says, the board is larger than that, and `jq` exits with `Argument list too
# long` — after which `pick` prints nothing and the run reports an empty queue.
# The test for that case caught this before it shipped. A here-string is fine,
# because it is a pipe rather than an argument.
# A board somebody else already read, when `BOARD_FILE` names one.
#
# **This exists because reading the board and writing to an issue are two
# credentials, and one step can hold one `GH_TOKEN`.** The board app is
# Projects-only and cannot comment; `WORKER_REPO_TOKEN` can comment and — since
# it lost `read:project` between 14:31 and 15:01 UTC on 2026-08-12 — can no
# longer read the board at all. The forgotten-claim sweep needs both, so the
# workflow reads the board in its own step under the app token and hands the file
# to the sweep under the repo token.
#
# **Set it on the one step that needs it, never on the job.** Every other caller
# reads the board itself, and a file left in the environment would be a board
# from earlier in the run answering a question asked later — the class of defect
# `#266` is about, arriving by a different door.
#
# An empty or missing file falls through to the query rather than answering with
# an empty board: *nobody is In Progress* and *nobody could look* must not be the
# same answer, which is the whole reason the sweep warns today instead of
# reporting all-clear.
BOARD_FILE=${BOARD_FILE:-}

board_read() {
  if [ -n "$BOARD_FILE" ] && [ -s "$BOARD_FILE" ]; then
    cat "$BOARD_FILE"
    return 0
  fi

  local after="" page pages rc=0
  pages=$(mktemp) || return 1
  while :; do
    page=$(gh api graphql -f query="$BOARD_QUERY" -f org="$ORG" \
             -F project="$BOARD_PROJECT" ${after:+-f after="$after"}) || { rc=1; break; }
    # Draft items and pull requests have no `number`: the fragment matches only
    # an Issue, so anything else arrives as an empty object. Dropping them here
    # saves every caller from having to.
    jq -c '
      [ .data.organization.projectV2.items.nodes[]
        | select(.content.number != null)
        | { id: .id,
            updatedAt: .updatedAt,
            status: (.fieldValueByName.name // ""),
            title: .content.title,
            labels: [ .content.labels.nodes[].name ],
            repository: .content.repository.url,
            content: ({ number: .content.number,
                        title: .content.title,
                        repository: .content.repository.nameWithOwner,
                        url: .content.url,
                        state: .content.state,
                        closedAt: .content.closedAt,
                        type: "Issue" }
                      # **Carried only when the read answered with it**, which
                      # an object literal cannot express: `stateReason: …` mints
                      # the key as null when it is absent, and null is a real
                      # answer here meaning *this issue was never closed*. Every
                      # other field can be minted, because null is not one of
                      # their meanings. A caller has to be able to tell *no
                      # reason* from *did not ask*, or it reads a board that
                      # cannot say why as a board of never-closed issues.
                      + (.content | if has("stateReason") then {stateReason} else {} end)) } ]
    ' <<<"$page" >>"$pages" || { rc=1; break; }
    [ "$(jq -r '.data.organization.projectV2.items.pageInfo.hasNextPage' <<<"$page")" = true ] || break
    after=$(jq -r '.data.organization.projectV2.items.pageInfo.endCursor' <<<"$page")
  done
  if [ "$rc" -eq 0 ]; then
    jq -s '{items: (add // [])}' "$pages" || rc=1
  fi
  rm -f "$pages"
  return "$rc"
}

# One issue's board item, without reading the board.
#
# An issue can be asked what it is on directly, which is a single node and costs
# **one point** where a board scan cost 203. `claim` and `release` both want one
# item, so between them this is most of what `#269` was about.
#
# ## Two filters, and neither is optional
#
# **`isArchived`, because this side of the graph answers differently.** The
# board's `items` connection omits archived cards and so did
# `gh project item-list`; an issue's `projectItems` returns them. Done cards are
# archived automatically, so without this filter the first thing that changed
# would be a card nobody can see, and `release` would report a success that left
# the board untouched. Caught on `kolonie-docs#1`, whose card is archived and
# came back from the lookup while the board read had never heard of it.
#
# **The project by id and not by number.** Project numbers are per owner, so a
# personal project 1 belonging to anyone is also `number: 1`. `PROJECT_ID` is the
# board and nothing else is.
read -r -d '' BOARD_ITEM_QUERY <<'GRAPHQL' || true
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      projectItems(first: 20) {
        nodes {
          id
          isArchived
          project { id }
          fieldValueByName(name: "Status") {
            ... on ProjectV2ItemFieldSingleSelectValue { name }
          }
        }
      }
    }
  }
}
GRAPHQL

# The board item id for an issue, or nothing.
#
# **Repository and number, never a number alone.** The board spans five
# repositories whose issue numbers all start at 1, so `#204` is not an
# identifier — §4 says so, and this is where it is enforced in code.
board_item_for() {
  local repo=$1 number=$2 raw
  raw=$(board_item_raw "$repo" "$number") || return $?
  jq -r --arg project "$PROJECT_ID" \
    '[ (.data.repository.issue.projectItems.nodes // [])[]
       | select(.project.id == $project and .isArchived == false) ]
     | first | if . == null then empty else .id end' <<<"$raw"
}

# The response behind both readers, with its **exit status kept** (`#422`).
#
# It used to be `gh api graphql ... | jq ... | head -1`, which conflates three
# outcomes into one empty line: the query failed, the issue is on no board, the
# card is archived. Worse, `head -1` can close the pipe under `jq` and hand the
# pipeline a signal status that has nothing to do with GitHub — so neither the
# output nor the status could be trusted to mean what a caller read into it.
# Asking once and filtering locally costs nothing and answers both questions.
board_item_raw() { # <repo> <number>
  local repo=$1 number=$2
  graphql_value -f query="$BOARD_ITEM_QUERY" \
    -f owner="${repo%%/*}" -f name="${repo##*/}" -F number="$number"
}

# The board item id **and the column it is in**, tab separated, or nothing.
#
# The status is the half `claim` was missing (`#266`): a claim that does not read
# the column it is about to overwrite cannot tell *I am taking this* from *I am
# taking this from whoever is working it*. One read answers both questions, so
# this costs nothing over `board_item_for` and replaces it in the one place where
# the difference matters.
board_item_status_for() {
  local repo=$1 number=$2 raw
  raw=$(board_item_raw "$repo" "$number") || return $?
  jq -r --arg project "$PROJECT_ID" \
    '[ (.data.repository.issue.projectItems.nodes // [])[]
       | select(.project.id == $project and .isArchived == false) ]
     | first
     | if . == null then empty else "\(.id)\t\(.fieldValueByName.name // "")" end' <<<"$raw"
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
#
# ## One reader, two headings (`#247`)
#
# The convention below is now used twice — *The check command* and *The check
# prerequisite* — so the parsing is a function of the heading rather than two
# copies of the same awk programme that drift apart. The heading arrives
# lowercased and is matched against a lowercased line, which is what lets
# `## 10. The check command` and `## The check command` both work.
fenced_lines_under() {
  local file=$1 heading=$2
  awk -v heading="$heading" '
    tolower($0) ~ ("^#+ .*" heading "[[:space:]]*$") { section = 1; next }
    section && /^#+ / { exit }
    section && /^```/ { fence = !fence; if (!fence) exit; next }
    section && fence && NF { print }
  ' "$file"
}

# The one-line case, which is both check headings: a command is a line, and a
# block carrying two of them would be a repository asking for something this
# convention cannot express.
first_fenced_block_under() {
  fenced_lines_under "$1" "$2" | head -n 1
}

check_command_from() {
  local file=$1
  [ -f "$file" ] || die "no AGENTS.md at $file — cannot learn this repository's check command" 5

  local command
  command=$(first_fenced_block_under "$file" "the check command")

  if [ -z "$command" ]; then
    die "$file names no check command: it needs a 'The check command' heading with the command in a fenced block. Refusing to guess one." 5
  fi
  printf '%s\n' "$command"
}

# What the check needs in front of it, if the repository says it needs anything.
#
# ## Why this is read and not held here (`#247`)
#
# The worker re-runs the target's check after the model has finished, because an
# unattended agent reporting that it ran a check is the claim this workflow
# exists to stop taking on trust. **It was re-running it in an environment the
# check is designed to refuse.** `kolonie-platform`'s suite fails hard on an
# unset `DATABASE_URL` — deliberately, `operations/testing.md`: *"a suite that
# skips them silently reports green while covering nothing"* — and the worker
# provided no PostgreSQL. Run `31303638874`, 2026-08-09: the model found
# `npm run test:db:up` in the repository's own documentation, started the server,
# passed the whole check against it, and then the worker's re-run failed on the
# one thing the model had already solved. **The verification step was weaker than
# the thing it exists to verify.**
#
# The fix is the same shape as the check command one heading up, and for the same
# reason `#231` gives: a `services: postgres:16` block in the workflow would be
# repository-specific knowledge held in the worker, and the next repository with
# a prerequisite would discover this again. The repository that has the
# prerequisite is the repository that states it.
#
# ## Absent is an answer, and it is the common one
#
# `check-command` fails when a repository names none, because a check that cannot
# be run means the run cannot be verified. This is the opposite: four of the five
# repositories need nothing before their check, so **silence prints nothing and
# exits 0**. A missing section here is not a defect in that file.
check_prerequisite_from() {
  local file=$1
  [ -f "$file" ] || die "no AGENTS.md at $file — cannot learn this repository's check prerequisite" 5

  first_fenced_block_under "$file" "the check prerequisite"
}

# The environment a prerequisite handed back, and nothing else it printed.
#
# ## Why the output is filtered rather than sourced
#
# `npm run test:db:up` finishes by printing `export DATABASE_URL=…`, which is the
# repository's existing interface to a person: run this, then copy that line.
# Honouring it is what makes the prerequisite worth declaring — a command that
# starts a server the check then cannot find is not a prerequisite, it is a
# container.
#
# Sourcing the whole output would run every line the command chose to print, in
# this shell, with this run's credentials. So each line is matched against one
# shape — `export NAME=value` — and **re-emitted through `printf %q`**, which
# quotes the value for exactly one round of `eval`. A `$(…)`, a backtick or a
# `;` in the value therefore arrives as characters and not as a command.
#
# ## And a name a prerequisite may not set
#
# Setting `PATH` would redirect every command after it, and setting a token would
# hand the model's step a credential the workflow chose not to give it (`#246`).
# Neither is what "my check needs a database" means, so both are refused by name
# and said out loud rather than dropped.
EXPORTS_REFUSED=${EXPORTS_REFUSED:-PATH LD_PRELOAD LD_LIBRARY_PATH GH_TOKEN GITHUB_TOKEN BASH_ENV IFS}

exports_from() {
  local file=$1
  [ -f "$file" ] || die "no such file: $file" 1

  local line name value refused
  while IFS= read -r line; do
    [[ $line =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    name=${BASH_REMATCH[1]}
    value=${BASH_REMATCH[2]}

    # One layer of the quotes an emitter may have added. Anything left inside is
    # data, and `%q` below is what keeps it that way.
    if [ "${#value}" -ge 2 ]; then
      case $value in
        \"*\") value=${value:1:${#value}-2} ;;
        \'*\') value=${value:1:${#value}-2} ;;
      esac
    fi

    refused=no
    for banned in $EXPORTS_REFUSED; do
      if [ "$name" = "$banned" ]; then refused=yes; break; fi
    done
    if [ "$refused" = yes ]; then
      echo "refusing to let the check prerequisite set $name" >&2
      continue
    fi

    printf 'export %s=%q\n' "$name" "$value"
  done <"$file"
}

# ## Saying why a run failed, where the failure is announced (`#245`)
#
# A failed run used to say *it failed, here is a link* — on the issue, in the
# Actions list, and on the run page, which had no summary at all. To learn that
# run `31302611039` died because three of the worker's own scratch files tripped
# `prettier --check`, somebody had to expand *Work it* and read past several
# hundred lines of build output. The maintainer, 2026-08-09: *"man kann nicht so
# richtig sehen, woran es liegt."*
#
# The three pieces below are what the workflow needs to say it instead, and they
# are here rather than in a `run:` block because a `run:` block cannot be tested
# — which is the reason this whole file exists.

# The marker that makes a failure comment countable. It is the opening of the
# comment the workflow has written since `#142`, unchanged on purpose: changing
# it would make every failure before today invisible to the count below.
# **Deliberately shorter than the sentence it matches** (`#251`). The comment
# opened with *The hourly opencode worker failed…* until `50ae76a` dropped the
# word when the schedule stopped being hourly — and the marker did not follow, so
# for two commits every failure was invisible to this count. Matching from
# `opencode worker failed` leaves it true of both wordings, so the history stays
# countable and the cadence can change again without silently breaking it.
FAILURE_MARKER=${FAILURE_MARKER:-opencode worker failed on this issue}

# How much of a log may reach a public comment. Three separate bounds, because
# they fail differently: a single line of minified output can be a megabyte, a
# tail of twenty can still be long, and the comment must stay readable.
EXCERPT_LINES=${EXCERPT_LINES:-20}
EXCERPT_LINE_CHARS=${EXCERPT_LINE_CHARS:-300}
EXCERPT_CHARS=${EXCERPT_CHARS:-2000}

# The variables whose *values* must not leave this runner — redacted out of a
# comment by `excerpt` (`#245`) and refused outright by `leak-check` (`#246`).
#
# **One list, because it is one fact.** Same technique as `no-gateway-leak.sh`:
# the values arrive in the environment and this file never learns them at rest.
# A variable that is unset, or shorter than ten characters, is skipped — a short
# needle would match half of any text and turn the excerpt into `[redacted]` or
# refuse every pull request.
# `BOARD_TOKEN` replaced `BOARD_READ_TOKEN` and `BOARD_WRITE_TOKEN` in `#270`.
# The old names stay in the list: they cost nothing when unset, and a name
# removed from here is a value that stops being redacted the moment somebody
# reintroduces the variable. An app token is also `ghs_`-shaped and so caught by
# the shape rules below, but the value match is the one that does not depend on
# GitHub keeping its prefixes.
# `#548` added the second gateway and the log store to the `Work it` step's
# environment, so both are values this run now holds and both are guarded for
# the same reason the first pair is.
GUARDED_SECRETS=${GUARDED_SECRETS:-LLM_GATEWAY_API_KEY_WORKER LLM_GATEWAY_BASE_URL LLM_GATEWAY_MODEL_WORKER LLM_GATEWAY_FALLBACK_API_KEY_WORKER LLM_GATEWAY_FALLBACK_BASE_URL LOKI_URL LOKI_TOKEN GH_TOKEN GITHUB_TOKEN WORKER_REPO_TOKEN BOARD_TOKEN BOARD_READ_TOKEN BOARD_WRITE_TOKEN}

# **GitHub masks a secret's value in a log. It does not mask it in a comment.**
# That is the whole reason this is more than a `tail`: the excerpt is being moved
# from a place the platform protects to a place it does not.
#
# Two passes, and both are needed. By value catches the secrets this run holds,
# exactly and whatever they look like. By shape catches what value-matching
# cannot: a credential the target repository printed, a token in somebody else's
# output, an environment dump. Neither is sufficient alone.

# One line of arbitrary output, made safe to put in a public comment.
#
# **Lifted out of `excerpt_from` for `#254`** and otherwise unchanged. That
# ending now has a second thing to publish — the model's account of why the
# check failed — and two redactions would be two things to keep in step. There
# is one, and everything that leaves this runner goes through it.
redact_line() {
  local line=$1 name value

  # By value first, with bash's literal replacement rather than a regex, so a
  # secret containing `/` or `.` cannot escape the substitution.
  for name in $GUARDED_SECRETS; do
    value=${!name:-}
    [ "${#value}" -ge 10 ] || continue
    line=${line//"$value"/[redacted: the value of $name]}
  done

  # Then by shape. The last rule is the one that catches a `postgres://` or an
  # `https://user:pass@` that nothing in this run put there.
  #
  # **The `NAME=value` rule runs before the token-shaped ones**, and the order
  # is not arbitrary: with it last, `GH_TOKEN=ghp_…` was redacted twice — once
  # into `[redacted: a GitHub token]` and then again over the front of that —
  # leaving `GH_TOKEN=[redacted] a GitHub token]`. Nothing leaked, and it read
  # like something had.
  line=$(sed -E \
      -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' \
      -e 's/([A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|APIKEY|CREDENTIAL))=[^[:space:]]+/\1=[redacted]/g' \
      -e 's/gh[pousr]_[A-Za-z0-9]{16,}/[redacted: a GitHub token]/g' \
      -e 's/github_pat_[A-Za-z0-9_]{20,}/[redacted: a GitHub token]/g' \
      -e 's/(sk|xoxb|xoxp|xapp)-[A-Za-z0-9_-]{16,}/[redacted: an API key]/g' \
      -e 's/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+/[redacted: a token]/g' \
      -e 's/[Bb]earer[[:space:]]+[A-Za-z0-9._~+/-]{16,}=*/[redacted: a bearer token]/g' \
    -e 's#://[^/@:[:space:]]+:[^/@[:space:]]+@#://[redacted: credentials]@#g' \
    <<<"$line")

  # A fenced block is what carries this into a comment, so three backticks in
  # the output would end the fence and let the rest render as prose.
  line=${line//'```'/\'\'\'}
  line=${line//$'\r'/}

  if [ "${#line}" -gt "$EXCERPT_LINE_CHARS" ]; then
    line="${line:0:$EXCERPT_LINE_CHARS}… (line truncated)"
  fi
  printf '%s\n' "$line"
}

excerpt_from() {
  local file=$1
  [ -f "$file" ] || return 0

  local line out=""
  while IFS= read -r line; do
    out+="$(redact_line "$line")"$'\n'
  done < <(tail -n "$EXCERPT_LINES" "$file")

  # Trailing newline off, then the last bound. The comment says the run link
  # carries the rest, so a cut here loses nothing that cannot be gone and read.
  out=${out%$'\n'}
  if [ "${#out}" -gt "$EXCERPT_CHARS" ]; then
    out="${out:0:$EXCERPT_CHARS}"$'\n'"… (excerpt truncated at $EXCERPT_CHARS characters; the run log has the rest)"
  fi
  printf '%s\n' "$out"
}

# Which step went red. Read from the API rather than tracked in a file, because
# the steps that fail hardest — a checkout, an install — are the ones that cannot
# be made to write a file first.
#
# **A job's log is not available while that job is still running**, which is why
# this returns a *name* and the excerpt comes from a file the run wrote as it
# went. The steps API does answer mid-run: a completed step carries its
# conclusion while the job around it is still `in_progress`.
#
# It never fails the caller. A reporting step that dies while reporting leaves
# exactly the silence it was added to remove.
# What the model is given to read when a check went red (`#254`).
#
# ## Why the tail alone was not enough
#
# The comment on a red check carries the last twenty lines of the build log —
# **bounded by line count rather than by relevance**, and the line that matters
# is usually above the cut. `kolonie-platform#533`'s sibling failures read as
# *`npm run check` did not pass* followed by a hundred lines of vitest output.
#
# So this is the tail **plus** the lines that look like the failure itself,
# wherever in the log they are. Every line goes through `redact_line`, which is
# the same filter the excerpt uses — the model must not be shown a credential
# any more than a reader must, and a model that has read one can put it in the
# account it writes.
#
# ## Bounded three ways, because the input is somebody else's build output
#
# The matched lines are capped, the total is capped, and the whole thing is a
# tail rather than the log — which the prompt says out loud, so the model does
# not describe what it cannot see.
DIGEST_MATCH=${DIGEST_MATCH:-FAIL|Error|error|✗|×|✘|not ok|AssertionError|Expected|Received|panic|SyntaxError|Cannot find|Module not found|✖}
DIGEST_LINES=${DIGEST_LINES:-60}
DIGEST_CHARS=${DIGEST_CHARS:-6000}

failure_digest_from() {
  local file=$1
  [ -f "$file" ] || return 0

  local line out=""
  # The matched lines first: they are the answer where there is one, and the
  # tail is context for them rather than the other way round.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    out+="$(redact_line "$line")"$'\n'
  done < <(grep -aE "$DIGEST_MATCH" "$file" 2>/dev/null | head -n "$DIGEST_LINES")

  out+=$'\n'"--- the last $EXCERPT_LINES lines ---"$'\n'
  out+="$(excerpt_from "$file")"

  if [ "${#out}" -gt "$DIGEST_CHARS" ]; then
    out="${out:0:$DIGEST_CHARS}"$'\n'"… (truncated at $DIGEST_CHARS characters)"
  fi
  printf '%s\n' "$out"
}

# The model's own account, made safe to publish.
#
# It is written by a model that ran with the gateway key in its environment, so
# it goes through the same filter as everything else — and through a bound,
# because *"answer in three short paragraphs"* is an instruction and not a
# guarantee.
ACCOUNT_CHARS=${ACCOUNT_CHARS:-1500}

redact_from() {
  local file=$1
  [ -f "$file" ] || return 0

  local line out=""
  while IFS= read -r line; do
    out+="$(redact_line "$line")"$'\n'
  done < "$file"

  out=${out%$'\n'}
  if [ "${#out}" -gt "$ACCOUNT_CHARS" ]; then
    out="${out:0:$ACCOUNT_CHARS}… (the model's account was longer than $ACCOUNT_CHARS characters and is cut here)"
  fi
  printf '%s\n' "$out"
}

# The paths no worker may write, read from the file that holds them (`#260`).
#
# ## Why a file in `operations/` and not a constant here
#
# Three issues were queued on 2026-08-09 and 10 that no run could finish, and the
# reason each was refused reached a comment and nothing else. The list has to be
# somewhere a *decision* meets it — a person choosing a route, and the triage pass
# in `#262` — which a shell constant is not. So the document is the source and this
# is a reader, the same relation `check-command` has to the target's `AGENTS.md`.
#
# ## Read from this repository, whatever the working directory is
#
# The worker runs with the *target* repository's checkout as `cwd` and
# `kolonie-docs` one level up. Resolving the path from `BASH_SOURCE` rather than
# from `cwd` means the same call works in both places, and means a target
# repository cannot supply its own prohibitions file — which would be the worker
# reading its constraints from the thing it is about to change.
prohibitions_file() {
  if [ -n "$PROHIBITIONS_FILE" ]; then
    printf '%s\n' "$PROHIBITIONS_FILE"
    return 0
  fi
  printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/operations/worker-prohibitions.md"
}

prohibited_paths() {
  local file
  file=$(prohibitions_file)
  [ -f "$file" ] || die "no prohibitions file at $file — refusing to run a worker whose own constraints cannot be read" 5

  local paths
  paths=$(fenced_lines_under "$file" "the paths no worker may write")
  [ -n "$paths" ] || die "$file names no forbidden paths: it needs a 'The paths no worker may write' heading with one path per line in a fenced block. Refusing to run with no constraints rather than with none found." 5
  printf '%s\n' "$paths"
}

# What the rest of this script compares against. `FORBIDDEN_PATHS` set in the
# environment wins, so a test can pin the list without a fixture document.
forbidden_paths() {
  if [ -n "$FORBIDDEN_PATHS" ]; then
    printf '%s\n' $FORBIDDEN_PATHS
    return 0
  fi
  prohibited_paths
}

# Which forbidden path a refusal named, or nothing (`#250`).
#
# ## Why this reads the refusal and not the issue
#
# `#250` refuses a scanner that guesses from an issue's text whether it needs a
# workflow edit: *"a classifier with a false-negative cost measured in wasted
# runs and a false-positive cost measured in work never attempted"*. This is the
# other end of the run and a different question. The model has already read the
# issue, already decided, and already written down which rule stopped it — so
# there is nothing to guess. A refusal naming `.github/workflows/` will recur
# identically for as long as the rule holds; one naming the issue may not.
worker_rule_refusal() {
  local file=$1 path
  [ -f "$file" ] || return 0
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if grep -qF -- "$path" "$file"; then
      printf '%s\n' "$path"
      return 0
    fi
  done < <(forbidden_paths)
}

failed_step() {
  local repo=${GITHUB_REPOSITORY:-} run=${GITHUB_RUN_ID:-}
  [ -n "$repo" ] && [ -n "$run" ] || return 0
  gh api "repos/$repo/actions/runs/$run/jobs" --paginate \
    --jq '[.jobs[].steps[]? | select(.conclusion == "failure") | .name] | .[0] // empty' \
    2>/dev/null || true
}

# How many times this issue has already been failed by the worker, counted off
# its own comments.
#
# **It counts failures on the issue and not failures in a row**, and the
# difference is worth stating rather than hiding behind the word *consecutive*:
# nothing writes a comment when a run succeeds, so there is no marker to reset
# against. A count of three means three failures on this issue, which is the
# finding either way — an issue the worker cannot do will produce them one after
# another, and one it can will not produce them at all.
previous_failures() {
  local repo=$1 number=$2
  local count
  count=$(gh api "repos/$repo/issues/$number/comments" --paginate \
    --jq "[.[] | select(.body | contains(\"$FAILURE_MARKER\"))] | length" 2>/dev/null) || count=""
  # `--paginate` with `--jq` prints one number per page, so they are added up
  # rather than read as one.
  [ -n "$count" ] || { echo 0; return 0; }
  awk '{ total += $1 } END { print total + 0 }' <<<"$count"
}

# The sentence every pull request the worker opens carries in its body.
#
# **Durable evidence, and deliberately not the author** (`#256`, `#258`). The
# obvious identifier is *whoever the token authenticates as*, and it is the one
# that goes wrong silently: the credential is a setting, it has already changed
# once, and a rotated token would make every pull request opened before it
# invisible to both sweeps below. The branch name is the second candidate and it
# is not enough on its own — anybody can push `opencode/issue-12`. The body
# sentence is written by this workflow and by nothing else, and a run that
# reworded it would have to edit the line the sweep reads.
# **Deliberately shorter than the sentence it matches**, and this repository has
# already paid for that lesson once: `FAILURE_MARKER` was `The hourly opencode
# worker failed…` until the schedule stopped being hourly, the wording changed,
# the marker did not follow, and every failure before that commit went uncounted.
#
# The same word did it again here. Measured on run `31377996406`, 2026-08-10:
# five merged pull requests — `kolonie-platform#655`, `#650`, `#645`, `#639` and
# `kolonie-infra#109` — open with *"Opened by the **hourly** opencode worker for
# #623"*, and an exact match on the current wording found none of them. Matching
# from `opencode worker for` is true of both and survives the next cadence
# change.
WORKER_PR_MARKER=${WORKER_PR_MARKER:-opencode worker for}

# The sentence that says an issue has already had its completion reported.
#
# Same shape and same job as `FAILURE_MARKER`: it is the opening of the comment
# the workflow writes, and the sweep below refuses to write a second one where it
# already appears. **Idempotency lives in the marker and not in a list of what
# has been reported**, because a list is state that has to be stored, and the
# issue timeline is a record that already exists and cannot drift from itself.
COMPLETION_MARKER=${COMPLETION_MARKER:-Completed by the opencode worker in}

# How far back the completion sweep looks. A run every fifteen minutes only ever
# needs to cover the gap since the last one; a day is two orders of magnitude of
# slack against that and still bounds the work at *what the worker merged in a
# day*, which has been about fifteen.
#
# **What it gives up, stated rather than discovered:** a completion that goes
# unreported for a whole day — the worker disabled, the schedule dropped — is
# never reported. That is a missing comment and not a wrong one, and the
# alternative is a sweep whose cost grows for as long as the experiment runs.
REPORT_WINDOW_DAYS=${REPORT_WINDOW_DAYS:-1}

# Every pull request the worker has opened, in one state, newest first.
#
# **Over REST search rather than the board or GraphQL**, for AGENTS.md §6's
# reason: the board is the whole of the GraphQL bill and this runs on a schedule
# every fifteen minutes. `search/issues` costs nothing from that pool.
#
# **The index is a minute or two behind**, which is the one property worth
# stating: a pull request opened by *this* run cannot be found by *this* run.
# Both callers are sweeps over previous runs' work, so that latency is invisible
# to them — and it is the reason neither of them belongs at the end of the run
# that opened the pull request.
#
# The body comes back with each hit and is not decoration: it carries the issue
# number, which saves the caller one API call per pull request.
worker_pull_requests() {
  local state=$1 extra=${2:-}
  gh api search/issues -X GET \
    -f q="org:$ORG is:pr is:$state in:body \"$WORKER_PR_MARKER\" $extra" \
    -f sort=updated -f order=desc -f per_page=100 \
    --jq '.items[] | "\(.repository_url | sub(".*/repos/"; ""))\t\(.number)\t\(.body | gsub("\n"; " "))"' \
    2>/dev/null || true
}

# The issue a worker pull request was opened for, off its branch name.
#
# `Closes #N` in the body says the same thing and is what GitHub acts on; the
# branch is used here because it survives a body somebody has edited, and
# because the two disagreeing is a defect worth having the sweep notice rather
# than paper over. A ref that does not match the convention prints nothing and
# the caller skips it.
#
# **`Closes #N` registers nothing on a pull request whose base is not the default
# branch.** GitHub creates the linked-issue relation only there, so a stacked
# pull request merges without closing anything and its issue shows no pull
# request at all — `kolonie-platform#846` and `#847` both carried the keyword and
# both had an empty `closingIssuesReferences`, while `#844`, which targeted
# `main`, closed `#827` (`#331`, 2026-08-13). The worker never opens a stacked
# pull request, so this is about the ones people open by hand.
issue_of_branch() {
  local ref=$1
  [[ "$ref" =~ ^opencode/issue-([0-9]+)$ ]] || return 0
  echo "${BASH_REMATCH[1]}"
}

# The same number, read off the pull request body instead.
#
# It is here because the search result already carries the body, so the caller
# that only needs the issue number saves an API call per pull request — which is
# the difference between a sweep that scales with the experiment and one that
# does not. The branch is still the authority: the reporting step reads both and
# refuses to report when they disagree, because two records of one fact that
# have drifted is a defect worth stopping on rather than picking a winner for.
issue_of_body() {
  local body=$1
  [[ "$body" =~ $WORKER_PR_MARKER\ \#([0-9]+) ]] || return 0
  echo "${BASH_REMATCH[1]}"
}

# Open worker pull requests that git cannot merge, as `<repo> <pr> <issue>`.
#
# ## Why this is a sweep and not a step at the end of the run
#
# The run that opens a pull request ends minutes before anything can merge under
# it. `kolonie-platform#668` opened at 05:44 on 2026-08-10 and went `CONFLICTING`
# when `#670` merged later — nothing in `#668`'s own run could have observed
# that, so the observation has to happen in a *subsequent* run. `#257` closes
# most of the window before the pull request is opened; this is the net under
# what still gets through.
#
# ## `dirty`, and nothing else
#
# GitHub's `mergeable_state` has six values and only one of them is this issue.
# `blocked` is a required check that has not reported, `unstable` is a
# non-required one that failed, `behind` is a branch that is simply out of date
# and merges fine — treating any of those as a conflict would put a healthy
# pull request back in Ready.
#
# **`unknown` is not an answer and must not be read as one.** GitHub computes
# mergeability lazily: the first request after a change to `main` returns
# `unknown` and starts the computation. A sweep that read that as *not dirty*
# would be correct by luck, and one that read it as *dirty* would close pull
# requests that merge perfectly well. It is skipped, out loud, and the next run
# fifteen minutes later gets a real answer.
stale_pull_requests() {
  local repo number body state ref issue
  while IFS=$'\t' read -r repo number body; do
    [ -n "${repo:-}" ] && [ -n "${number:-}" ] || continue

    IFS=$'\t' read -r state ref < <(
      gh api "repos/$repo/pulls/$number" \
        --jq '"\(.mergeable_state)\t\(.head.ref)"' 2>/dev/null
    ) || continue

    case "${state:-}" in
      dirty) ;;
      unknown|"")
        echo "$repo#$number: GitHub has not computed mergeability yet; leaving it for the next run" >&2
        continue ;;
      *) continue ;;
    esac

    issue=$(issue_of_branch "${ref:-}")
    if [ -z "$issue" ]; then
      echo "$repo#$number conflicts but its branch (${ref:-none}) names no issue; leaving it for a person" >&2
      continue
    fi

    printf '%s\t%s\t%s\n' "$repo" "$number" "$issue"
  done < <(worker_pull_requests open)
}

# Merged worker pull requests whose issue does not yet say so, as
# `<repo> <pr> <issue>`.
#
# ## Why a successful issue needed this at all (`#258`)
#
# The worker announces when it takes an issue and explains every failure path. A
# **success** ended with neither: the pull request merged, GitHub closed the
# issue, and the only worker comment left behind was *"Taken by the opencode
# worker"*. Verified on `kolonie-platform#649`, `#657` and `#658` — each has a
# merged worker pull request and no closing account, so a reader has to open the
# pull request and reconstruct the result from its files.
#
# ## Why it is a sweep, and why it is the same sweep as `#256`'s
#
# The run that opens a pull request ends before GitHub merges it, so the run that
# did the work can never be the one that reports it landing. Both observations —
# *this one conflicted* and *this one merged* — are about previous runs and both
# belong at the start of the next one. **Opening a pull request is not
# completion**, which is the distinction this whole comment exists to make
# visible on the timeline.
#
# ## Exactly once, and nothing stored to make it so
#
# The marker is read off the issue's own comments. A reporting step that ran
# twice, a run that was retried, a sweep window that overlaps the last one — all
# find the marker and write nothing. There is no list of what has been reported,
# because a list is state that drifts from the thing it describes.
unreported_completions() {
  local since repo number body issue reported
  since=$(date -u -d "${REPORT_WINDOW_DAYS} days ago" +%Y-%m-%d 2>/dev/null) || since=""

  while IFS=$'\t' read -r repo number body; do
    [ -n "${repo:-}" ] && [ -n "${number:-}" ] || continue

    issue=$(issue_of_body "${body:-}")
    if [ -z "$issue" ]; then
      echo "$repo#$number is merged but its body names no issue; nothing to report on" >&2
      continue
    fi

    # The issue must be **closed**, and that is not the same question as *did
    # the pull request merge*. A merge whose `Closes #N` was edited out, or one
    # whose issue somebody reopened because the work was not enough, is not a
    # completion — and writing *completed* on an open issue would be the exact
    # misrepresentation this issue is about.
    if [ "$(gh api "repos/$repo/issues/$issue" --jq '.state' 2>/dev/null)" != "closed" ]; then
      continue
    fi

    reported=$(gh api "repos/$repo/issues/$issue/comments" --paginate \
      --jq "[.[] | select(.body | contains(\"$COMPLETION_MARKER\"))] | length" 2>/dev/null) ||
      continue
    [ -n "$reported" ] || continue
    [ "$(awk '{ total += $1 } END { print total + 0 }' <<<"$reported")" -eq 0 ] || continue

    printf '%s\t%s\t%s\n' "$repo" "$number" "$issue"
  done < <(worker_pull_requests merged "${since:+merged:>=$since}")
}

# The contexts `main` requires in one repository, comma-joined, or nothing.
#
# **Nothing is the answer that matters.** A branch with no required status check
# merges the instant auto-merge is enabled, so the callers read an empty string
# as *do not arm this* rather than as *could not tell* — and an API call that
# failed produces the same empty string. That conflation is deliberate and it is
# the safe direction: an unreadable protection setting stops the arming, and the
# pull request waits for a person rather than landing unverified.
required_contexts_of() {
  local repo=$1
  # The branch to ask about, because protection binds one branch and not a
  # repository (`#331`). `main` where a caller has nothing better to say.
  local branch=${2:-main}
  gh api "repos/$repo/branches/$branch/protection" \
    --jq '[.required_status_checks.contexts // []] | flatten | join(", ")' 2>/dev/null || true
}

# Open pull requests in the organisation that nothing will ever merge, as
# `<repo> <pr> <required contexts>` (`#275`).
#
# ## The gap this closes
#
# The worker arms auto-merge on the pull requests **it** opens, in the step that
# opens them. Nothing arms the ones it does not. On 2026-08-10 `claude002` opened
# `kolonie-docs#274` and `kolonie-email#5`; both stood green, mergeable and
# untouched until the maintainer found them by hand. Nothing was wrong with
# either and nothing was going to merge either — which is `#256`'s failure
# (finished work, and a queue that does not know it) wearing a different hat.
#
# **A sweep and not a step where the pull request is opened**, because the thing
# that opens one is not always a workflow. An instruction to remember a flag is
# not a mechanism: this covers the agent that was never told, the agent that was
# told and forgot, and the person.
#
# ## The seven filters, and which one the whole thing hangs on
#
# 1. **Not a fork.** A stranger's branch must never arm itself. This is the rule
#    everything else is a refinement of — the repositories are public, anybody
#    may open a pull request, and a sweep that armed those would be a supply
#    chain with a schedule. Read off `head.repo.full_name` against the base,
#    which is `null` for a deleted fork and therefore also excluded.
# 2. **Not a draft.** A draft is how an author says *not yet*, and it stays the
#    way to say it.
# 3. **Auto-merge not already on**, so a run costs nothing where the worker's own
#    step already did the work.
# 4. **`main` requires a status check.** Same refusal the worker already makes
#    where it opens its own pull requests, for the same reason.
# 5. **Not labelled `blocked:human`.** The label already exists in every
#    repository here and already means *waiting on a person*, so this is the
#    existing vocabulary rather than a new one. It is what to reach for before a
#    pull request is green, where there is no disarm to make yet.
# 6. **Nobody has disarmed it.** An `auto_merge_disabled` event anywhere in the
#    timeline takes the pull request out of the sweep permanently (`#326`).
# 7. **It targets the repository's default branch.** Filter 4 asks what the
#    default branch requires; a pull request into a feature branch is not
#    protected by that answer, because branch protection binds only the branch it
#    is configured on (`#331`).
#
# ## Why a disarm has to stick
#
# Filters 5 and 6 are `#326`, and they are here because filter 2 was not enough.
# `kolonie-platform#844` carried a migration and a change to the front door, and
# its own body asked for a look before it went in. The sweep armed it, the
# maintainer disarmed it by hand at 06:33, and the next run read an open pull
# request with `auto_merge == null` and armed it again at 06:41. The required
# checks were green by then, so it merged in the same second and deployed.
#
# **A manual disarm that buys fifteen minutes is not a control.** Filter 6 needs
# no convention and no label discipline: the act of disarming *is* the signal,
# and it is the one every reader already reaches for. Somebody who wants it armed
# after all arms it themselves, and filter 3 then leaves it alone.
#
# ## Why the base branch has to be asked about separately
#
# Filter 7 is `#331`, and it is the same shape of hole as `#326`: filter 4 was
# read as covering something it does not. **Branch protection binds only the
# branch it is configured on.** A pull request whose base is a feature branch has
# no required check to wait for, so arming it merges it in the same second,
# unbuilt — and `ci.yml` in `kolonie-platform` is triggered
# `pull_request: branches: [main]`, so on such a pull request CI does not run at
# all. It happened on 2026-08-13: `kolonie-platform#847` was opened at 07:04
# against the branch of the still-open `#846` and the 07:10 run merged it at
# 07:10:35, announcing that it would land when a check reported that was never
# going to run.
#
# Nothing reached `main` — `#846` carried `blocked:human`. What it cost was the
# hold: a diff a person was asked to read grew by another pull request's worth of
# change with nobody told.
#
# **The base ref is filtered in the loop rather than in the `--jq`**, unlike the
# other list-borne filters, because this one has something to say. A skipped pull
# request here is usually a deliberate stack that a person will merge by hand,
# and a sweep that drops it silently is indistinguishable from one that has not
# noticed it.
#
# The default branch is read per repository from the same listing that names the
# repository, so this costs no request. It is `main` everywhere here today, and
# hard-coding it would be a fact that rots without saying so.
#
# ## What it still does not filter on, stated because the omission looks like a bug
#
# Not on the author and not on a branch prefix. Every open pull request in the
# organisation that survives the seven above is armed, including a person's. That
# is the intent rather than an oversight: **arming is not merging.** `--auto
# --squash` with no `--admin` lands nothing that the required check has not
# passed, so the worst case is that a green pull request somebody was sitting on
# merges — which is what a green pull request in this organisation means, unless
# they said otherwise in one of the two ways above.
#
# ## `dirty` is skipped, and `unknown` is not an answer
#
# GitHub refuses to arm a conflicting pull request outright, so a run that tried
# would spend a call to be told so and warn about it again fifteen minutes later,
# forever. `blocked` and `unstable` are **not** skipped — a check that has not
# reported yet is precisely what auto-merge is for. `unknown` means GitHub has
# not computed mergeability, and reading it either way would be a guess:
# `stale_pull_requests` above states this at length and the same rule applies.
#
# ## A timeline that cannot be read fails closed
#
# Everywhere else here an unreadable API means *leave it for the next run*, and
# that is what filter 6 does too — but the reason is stronger. Not knowing
# whether a pull request was disarmed and arming it anyway is the one mistake
# that cannot be taken back: on a green pull request, arming is merging.
unarmed_pull_requests() {
  local repo repos number required state disarmed events default_branch base
  local unarmed=0

  # `default_branch` rides along with the name, so filter 7 costs no request.
  repos=$(gh api "orgs/$ORG/repos" -X GET -f per_page=100 -f type=all \
    --jq '.[] | select(.archived | not) | [.full_name, .default_branch] | @tsv' 2>/dev/null) || return 1
  [ -n "$repos" ] || return 1

  while IFS=$'\t' read -r repo default_branch; do
    [ -n "${repo:-}" ] || continue
    # An older listing, or a fixture that predates this column, still names a
    # repository. Defaulting is safer than skipping it: `main` is what every
    # repository here answers, and skipping would silently stop sweeping.
    [ -n "${default_branch:-}" ] || default_branch=main

    # One list call answers filters 1, 2, 3 and 5 for the whole repository — the
    # labels come back on the list, so the label filter costs nothing extra. The
    # per-pull-request calls below are paid only for what survives them, which on
    # a quiet day is nothing at all. The base ref comes back on the same list and
    # is carried through rather than filtered here, so filter 7 can say which
    # branch it left a pull request alone for.
    local candidates
    candidates=$(gh api "repos/$repo/pulls" -X GET -f state=open -f per_page=100 \
      --jq '.[] | select(.draft | not)
                | select(.auto_merge == null)
                | select((.head.repo.full_name // "") == .base.repo.full_name)
                | select([(.labels // [])[].name] | index("blocked:human") | not)
                | [(.number | tostring), (.base.ref // "")] | @tsv' 2>/dev/null) || {
      echo "could not list open pull requests in $repo; leaving it for the next run" >&2
      continue
    }
    [ -n "$candidates" ] || continue

    required=$(required_contexts_of "$repo" "$default_branch")
    if [ -z "$required" ]; then
      echo "$repo has no required status check on $default_branch; nothing there is armed" >&2
      continue
    fi

    while IFS=$'\t' read -r number base; do
      [ -n "${number:-}" ] || continue

      # Filter 7. Before the two calls below, because a stacked pull request is
      # not a candidate at all and paying to read its mergeability would be a
      # request spent on an answer nothing acts on.
      if [ "${base:-$default_branch}" != "$default_branch" ]; then
        echo "$repo#$number targets $base rather than $default_branch, where no check is required; the sweep leaves it to whoever stacked it (#331)" >&2
        continue
      fi

      # ## `mergeable_state` is a measurement, not a fact (`#484`)
      #
      # Measured 2026-08-22: `kolonie-platform#1604` read `DIRTY` from 12:29 to
      # about 14:00 — ninety minutes — while three other pull requests merged
      # into `main` beneath it. Halfway through that window `git merge-tree
      # --write-tree` against the `main` of that moment produced a tree and no
      # conflict. Nobody touched the branch; GitHub recomputed on its own.
      #
      # It is not GitHub misbehaving. The field is computed at a moment and is
      # correct for that moment; what is wrong is reading it as current ninety
      # minutes later. This sweep runs hourly and re-read the same field, so a
      # verdict stale that long was skipped every time it looked — the same shape
      # `#480` fixed one level up, where a transient machine-caused state was
      # read as a settled fact.
      #
      # **The read is what triggers the recompute**, which is what makes asking
      # again the whole fix rather than a workaround: GitHub computes
      # mergeability lazily when something asks, so the first read starts the
      # work and the second read gets the answer. A stale verdict answers
      # differently; a real conflict answers `dirty` again and costs one request
      # on a state that is rare.
      #
      # **The age comes back on the same call.** `#484` asks for a pull request
      # stuck this way to be visible without anybody looking for it, and one
      # request answers both questions, so saying how long costs nothing.
      #
      # `pull.base.sha` is not the staleness signal it looks like, and this is
      # written down so nobody re-walks it: measured across three open pull
      # requests at 14:19, all three carried the identical `base.sha` and all
      # three lagged `main`. It tracks the base branch generally, not when this
      # pull request's mergeability was computed.
      local seen updated
      seen=$(gh api "repos/$repo/pulls/$number" \
        --jq '[.mergeable_state, (.updated_at // "")] | @tsv' 2>/dev/null) || continue
      IFS=$'\t' read -r state updated <<<"$seen"

      if [ "${state:-}" = dirty ]; then
        # Ask once more. The read above is what asked GitHub to recompute, and
        # this is the answer to that recompute rather than a second look at the
        # same cached verdict.
        local recomputed
        if recomputed=$(gh api "repos/$repo/pulls/$number" \
          --jq '[.mergeable_state, (.updated_at // "")] | @tsv' 2>/dev/null); then
          IFS=$'\t' read -r state updated <<<"$recomputed"
          [ "${state:-}" = dirty ] ||
            echo "$repo#$number read dirty and recomputed to ${state:-unknown}; the cached verdict was stale (#484)" >&2
        fi
      fi

      case "${state:-}" in
        dirty)
          # **Say how long** (`#484`). Ninety minutes passed with nothing
          # anywhere saying so, and it was found by hand. An age this sweep
          # cannot read is not a reason to say nothing about the conflict — the
          # line below is printed either way and only the duration is dropped.
          if [ -n "${updated:-}" ] && stuck=$(date -u -d "$updated" +%s 2>/dev/null); then
            local hours=$(( ( $(date -u +%s) - stuck ) / 3600 ))
            [ "$hours" -ge 1 ] &&
              echo "$repo#$number has read dirty for ${hours}h, since $updated — long enough that the verdict may be stale rather than settled (#484)" >&2
          fi
          echo "$repo#$number conflicts with main; auto-merge cannot be enabled on it" >&2
          continue ;;
        unknown|"")
          echo "$repo#$number: GitHub has not computed mergeability yet; leaving it for the next run" >&2
          continue ;;
      esac

      # Filter 6. `--paginate` because the event that matters may be anywhere in
      # the timeline, and a disarm the sweep did not scroll far enough to see is
      # the bug this filter exists to fix.
      #
      # **A disarm that a reopen came after is not a decision** (`#480`).
      # Closing a pull request disables auto-merge as a side effect, and
      # reopening it does not put it back. `#326`'s rule then draws a permanent
      # conclusion — *somebody decided this waits for a person* — from a state
      # nobody chose, and the pull request stays green, open and nobody's for
      # ever. That is the whole of *In Review hangs around* on the board.
      #
      # `kolonie-platform#1534`, measured 2026-08-21:
      #
      #   16:41:21  auto_merge_enabled
      #   17:49:14  closed
      #   17:49:15  auto_merge_disabled   ← one second later, from the close
      #   17:49:20  reopened              ← five seconds after that
      #
      # So the two events are read in order and the **last one wins**: a disarm
      # standing after every reopen is a decision and is respected, and a disarm
      # a reopen came after is stale. That leaves `#326` exactly as it was — a
      # person who disarms a pull request nobody afterwards reopens still stops
      # the sweep, for ever, which is the case the rule was written for.
      #
      # **The eviction this issue was filed about does not happen**, and it is
      # worth writing down so nobody builds for it twice. `kolonie-platform#1561`
      # was evicted from the merge queue seven times on 2026-08-21 and emitted no
      # `auto_merge_disabled` at all: an eviction takes the entry out of the
      # queue and leaves auto-merge armed. The suspected cause was the wrong one.
      if ! events=$(gh api --paginate "repos/$repo/issues/$number/timeline" \
        --jq '.[] | select(.event == "auto_merge_disabled" or .event == "reopened") | .event' 2>/dev/null); then
        echo "$repo#$number: could not read the timeline, so whether anybody disarmed it is unknown; leaving it alone" >&2
        continue
      fi
      disarmed=$(printf '%s\n' "$events" |
        awk '/^auto_merge_disabled$/ { d = 1 } /^reopened$/ { d = 0 } END { print d + 0 }')
      if [ "$disarmed" = 1 ]; then
        echo "$repo#$number: somebody disarmed auto-merge on it; the sweep does not arm it again (#326)" >&2
        continue
      fi

      unarmed=$((unarmed + 1))
      printf '%s\t%s\t%s\n' "$repo" "$number" "$required"
    done <<<"$candidates"
  done <<<"$repos"

  # **Say how many there were** (`#480`). A green, open, unarmed pull request is
  # something this function can already see and used to say nothing about, so a
  # filter drawing a wrong permanent conclusion was invisible until somebody
  # looked at the board and wondered. One line costs nothing and would have
  # surfaced `kolonie-platform#1534` in an hour rather than in a day.
  #
  # On stderr, with the rest of the reasoning: stdout is the tab-separated list
  # the caller parses, and a count on it would be a row that is not a pull
  # request.
  echo "$unarmed green pull request(s) nobody has armed" >&2
}

# Nothing that is about to be published carries a secret this run holds (`#246`).
#
# ## Why this exists next to a sandbox that was already there
#
# opencode's sandbox kept the model out of the runner's filesystem, on a
# container GitHub throws away. **It never kept it out of the credentials**,
# which were in its environment the whole time — a directory restriction does not
# stop `env`. So the cheap thing was guarded and the expensive one was not.
#
# The expensive one is this: the run writes a **public** pull request, and a
# model that has read a credential and is being thorough about documenting what
# it did can put it in a body, a commit message or a test fixture — not
# maliciously, just completely. GitHub masks a secret's value in a log. It does
# not mask it in a pull request.
#
# ## By value, and deliberately not by shape
#
# `excerpt` above redacts by shape as well, because there the cost of a false
# positive is a slightly less readable comment. Here the cost is a refused pull
# request and an hour of work returned to the queue, so the test is the one that
# cannot be wrong: does the literal value of a secret **this run holds** appear.
# A repository that legitimately documents what a token looks like is not a leak
# and must not be treated as one.
#
# **It prints no value, ever, including on failure** — the variable name and the
# file are enough to act on, and a grep hit echoed into a public log would be the
# leak this exists to prevent.
leak_check() {
  local failures=0 checked=0 name value file

  for name in $GUARDED_SECRETS; do
    value=${!name:-}
    [ -n "$value" ] || continue
    if [ "${#value}" -lt 10 ]; then
      echo "skip: $name is set but shorter than 10 characters, so it cannot be searched for safely" >&2
      continue
    fi
    checked=$((checked + 1))
    for file in "$@"; do
      [ -f "$file" ] || continue
      if grep -qF -- "$value" "$file"; then
        echo "REFUSED: the value of $name appears in $(basename "$file")" >&2
        failures=$((failures + 1))
      fi
    done
  done

  if [ "$failures" -gt 0 ]; then
    echo "Nothing was pushed. No value is printed above on purpose — the variable name and the file are enough to fix it." >&2
    return 1
  fi

  echo "$checked secret(s) checked against $# file(s); none of them appears in what is about to be published"
  return 0
}

# What an issue is waiting for, one `owner/repo#number` per line, empty if
# nothing (`#261`).
#
# ## Why this is a relation and not a line in the body
#
# `kolonie-platform#660` reads a contract field `kolonie-platform#659` creates.
# The dependency was written in prose in both bodies, twice, and on 2026-08-10
# the worker took `#660` anyway and failed — correctly, and for a run. `pick`
# read labels and a column, and neither of those can say *this one waits*.
#
# ## Why the dependency relation and not a sub-issue
#
# `#261` proposes GitHub's sub-issue relationship, on the grounds that it is
# native, survives a close and renders. All three are true, and there is a
# better fit that was not available when the issue was written: **GitHub's issue
# *dependencies*** — `blocked_by` and `blocking` — which say the thing itself
# rather than approximating it with containment. `#659` is not a *part* of
# `#660`; it is what `#660` waits for, and a parent/child link would have had to
# be read as a dependency by convention, which is prose again with a nicer
# renderer. Confirmed present on this organisation's repositories 2026-08-10:
# `GET /repos/{owner}/{repo}/issues/{n}/dependencies/blocked_by` answers.
#
# ## Open blocks; closed does not
#
# `#261`'s case worth getting right. `#659`'s pull request was closed without
# merging and the issue went back to Ready — and an issue whose blocker is
# *closed* may still proceed, because the field either exists on `main` or it
# does not and the target's own check is what says so. Blocked or not blocked;
# no degrees, nothing to interpret.
# Every blocked-by relation an issue carries, open and closed, one per line as
# `<state> <owner/repo>#<number>`.
#
# The repository comes out of `repository_url`, which every issue object
# carries, rather than out of `repository`, which only the search endpoints
# add. A blocker in another repository is the case this has to get right —
# `#660` and `#659` are both in `kolonie-platform`, but nothing says they must
# be — and printing a bare number for it would name nothing (§4).
#
# **The closed ones are read too, and `kolonie-docs#289` is why.** *This issue has
# dependencies and none of them is open* and *this issue never had any* are
# different facts: the first is an issue whose reason for waiting has gone, the
# second is an issue nobody ever said was waiting. The triage sweep moves a card on
# the first and must not move one on the second, so the state travels with the
# relation rather than being filtered away at the only place that reads it.
dependencies_of() {
  local repo=$1 number=$2
  gh api "repos/$repo/issues/$number/dependencies/blocked_by" --paginate \
    --jq '.[] | "\(.state) \(.repository_url | sub("^.*/repos/"; ""))#\(.number)"'
}

blockers_of() {
  dependencies_of "$1" "$2" | awk '$1 == "open" { print $2 }'
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
    board_read >"$board_file" ||
      die "could not read the board, so the queue is unknown"
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
    # **`worker:forbidden` is excluded here and not by the search**, so that
    # an issue carrying it is out of the queue even when somebody has put
    # `queue:worker` back — which is exactly the case `#250` is about, and the
    # case a search term the labeller can overwrite would not cover.
    selection=$(jq -r --arg forbidden "$FORBIDDEN_LABEL" --slurpfile board "$board_file" '
      # **The repositories a run is already working in.** Two runs in one
      # repository is what every conflict this worker has had was made of: a
      # migration number taken twice, two entries at the top of one changelog, a
      # branch that stopped applying to `main` while its pull request waited. Two
      # runs in *different* repositories share no history, no check and no merge,
      # so git cannot put them in each other'"'"'s way.
      #
      # This is the courtesy `solo` used to pay globally, paid per repository
      # instead — and read off the board rather than off the run list, because
      # the board is where `claim` records which repository a run is in. A run
      # that died without releasing still shows here; a run list entry for a job
      # that is hung does not say what it was working on.
      #
      # The lock is still the claim. This only stops a run walking into work it
      # would collide with.
      ( [ $board[0].items[]
          | select(.status == "In Progress")
          | .content.repository ] | unique ) as $busy
      | [ .[]
        | select([.labels[].name] | index("blocked:human") | not)
        | select([.labels[].name] | index($forbidden) | not)
        | { repo: .repository.nameWithOwner,
            number: .number,
            createdAt: .createdAt,
            labels: [.labels[].name] }
        | select(.repo as $r | $busy | index($r) | not)
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

    # **Then the dependencies, and only now** (`#261`). The ordering above is
    # local and free; this asks GitHub one question per candidate, so it is asked
    # of the candidates in the order they would be taken and stops at the first
    # issue that is free to run. The ordinary hour costs one call.
    total=$(jq 'length' <<<"$selection")
    index=0
    while [ "$index" -lt "$total" ]; do
      candidate=$(jq -r --argjson i "$index" '.[$i] | "\(.repo)\t\(.number)"' <<<"$selection")
      candidate_repo=${candidate%%$'\t'*}
      candidate_number=${candidate##*$'\t'}

      waiting=$(blockers_of "$candidate_repo" "$candidate_number") || die \
        "could not read what $candidate_repo#$candidate_number is blocked by, so the queue is unknown. Taking nothing rather than taking blocked work."

      if [ -n "$waiting" ]; then
        echo "note: $candidate_repo#$candidate_number waits for $(tr '\n' ' ' <<<"$waiting")— skipping it" >&2
        index=$((index + 1))
        continue
      fi

      printf '%s\t%s\n' "$candidate_repo" "$candidate_number"
      exit 0
    done

    [ "$total" -eq 0 ] ||
      echo "every queued issue is waiting for another one. Taking nothing." >&2

    exit 0
    ;;

  claim)
    repo=$(repo_slug "${2:?claim needs a repository}") || exit $?
    number=${3:?claim needs an issue number}
    read -r item status < <(board_item_status_for "$repo" "$number")
    [ -n "${item:-}" ] || die "$repo#$number is not on the board — refusing to start work on it" 3

    # **The column is read before it is written** (`#266`). `pick` and this are
    # separate steps of the workflow, so an issue can be taken by another run in
    # between — and until now that other run's In Progress was simply overwritten
    # by this one's, with both runs believing they held it.
    #
    # A lost race prints `lost` and exits **0**. Not 3, not 4: nothing is wrong
    # here, and every non-zero exit from this step ends the run through the
    # failure path, which since `#251` and `#255` takes `queue:worker` off the
    # issue and marks it `worker:failed`. That is the correct ending for work
    # that was tried and not finished, and the wrong one for work somebody else
    # is doing right now.
    if [ "${status:-}" != "Ready" ]; then
      echo "$repo#$number is in ${status:-no column} rather than Ready — another run took it between the pick and here. Taking nothing." >&2
      echo lost
      exit 0
    fi

    # **The board write happens before the comment and before any work.** An
    # expired or revoked token has to stop the run here, while nothing has been
    # started and nothing needs undoing. `#142` names this as the one failure the
    # design cannot recover from on its own: an issue parked in In Progress by a
    # token that then could not move it back.
    set_status "$item" "$STATUS_IN_PROGRESS" ||
      die "could not move $repo#$number to In Progress — the board token may have expired. Not starting work." 4

    # And read it back, because a write that reported success and did not take is
    # indistinguishable from a claim otherwise. This is the cheap half of `#266`:
    # it cannot see a simultaneous claim — both runs read In Progress and both are
    # right — which is what `verify-claim` is for.
    read -r _ confirmed < <(board_item_status_for "$repo" "$number")
    if [ "${confirmed:-}" != "In Progress" ]; then
      echo "$repo#$number reads back as ${confirmed:-nothing} after the claim, so this run does not hold it. Taking nothing." >&2
      echo lost
      exit 0
    fi

    echo held
    exit 0
    ;;

  verify-claim)
    # The tie-break, and the reason `solo` could go (`#266`).
    #
    # ## Why it is the comment and not the board
    #
    # Projects v2 has no conditional field update, so two runs that read Ready in
    # the same instant both write In Progress and both read it back. There is no
    # board state that distinguishes them, and inventing one — a *held by* field —
    # would be the lock service `#266` refuses: the board is the state.
    #
    # An ordered record already exists. Both runs write a claim comment on the
    # issue, GitHub assigns comment ids in creation order, and **the earliest one
    # wins**. Whichever order the two runs arrive here in, each sees at least its
    # own comment and any comment written before it, so each reaches the same
    # verdict about who was first. Exactly one run holds the issue.
    #
    # ## What the window is for
    #
    # An issue that failed and was retried carries an older claim comment. The
    # window keeps that out of the comparison; it is not a timeout on the race,
    # which is seconds wide.
    repo=$(repo_slug "${2:?verify-claim needs a repository}") || exit $?
    number=${3:?verify-claim needs an issue number}
    mine=${4:-$RUN_URL}
    [ -n "$mine" ] || die "verify-claim needs this run's URL, in \$RUN_URL or as the third argument" 1

    comments=$(gh api "repos/$repo/issues/$number/comments" --paginate \
      --jq '.[] | [(.id|tostring), .created_at, (.body|gsub("\n"; " "))] | @tsv' 2>/dev/null) || {
      # **A verification that cannot run holds the claim.** The two checks in
      # `claim` have already passed, so the likelihood this run is the loser of a
      # simultaneous race is small — and abandoning an issue on an API blip
      # would spend a run to avoid a rarer collision than the one it creates.
      echo "could not read the comments on $repo#$number, so the claim cannot be verified. Continuing, because the column was read back and held." >&2
      echo held
      exit 0
    }

    # **The cutoff is an ISO 8601 string and the comparison is a string
    # comparison.** `created_at` is UTC and so is this, and the format sorts
    # lexicographically in the order it sorts chronologically. The obvious
    # alternative — `mktime` in awk — reads its argument as *local* time, so on
    # any runner not set to UTC every comment looks hours old and the window
    # silently discards the race it exists to decide.
    cutoff=$(date -u -d "$CLAIM_RACE_WINDOW_MINUTES minutes ago" +%Y-%m-%dT%H:%M:%SZ)

    winner=$(awk -F'\t' -v marker="$CLAIM_MARKER" -v cutoff="$cutoff" '
      index($3, marker) && $2 >= cutoff {
        if (first == "" || $1 + 0 < first + 0) { first = $1; body = $3 }
      }
      END { print body }
    ' <<<"$comments")

    # No claim comment inside the window means nothing to lose to — the comment
    # step is best-effort and this must not turn its failure into a lost issue.
    if [ -z "$winner" ]; then
      echo "no claim comment on $repo#$number inside the last $CLAIM_RACE_WINDOW_MINUTES minutes; nothing contests this claim" >&2
      echo held
      exit 0
    fi

    if [[ "$winner" == *"$mine"* ]]; then
      echo "this run wrote the first claim comment on $repo#$number" >&2
      echo held
      exit 0
    fi

    other=$(grep -o 'https://[^ )]*/actions/runs/[0-9]*' <<<"$winner" | head -1)
    echo "$repo#$number was claimed first by ${other:-another run}. Retiring, and leaving the issue exactly as it was found." >&2
    printf 'lost %s\n' "${other:-another run}"
    exit 0
    ;;

  blockers)
    # The queue reads this itself; it is a subcommand so that a person can ask
    # the same question, and so that the answer is one testable place rather
    # than a `--jq` buried in the selection.
    repo=$(repo_slug "${2:?blockers needs a repository}") || exit $?
    number=${3:?blockers needs an issue number}
    blockers_of "$repo" "$number" ||
      die "could not read what $repo#$number is blocked by" 1
    exit 0
    ;;

  dependencies)
    # The same relation with the closed half kept (`kolonie-docs#289`), so that
    # *waited for something and does not any more* can be told from *never waited
    # for anything*. One endpoint, read one way, whichever question is being asked.
    repo=$(repo_slug "${2:?dependencies needs a repository}") || exit $?
    number=${3:?dependencies needs an issue number}
    dependencies_of "$repo" "$number" ||
      die "could not read what $repo#$number depends on" 1
    exit 0
    ;;

  forgotten-claims)
    # The other half of `#266`: `pick` skips a repository that has anything In
    # Progress, so an item left there holds its whole repository out of the
    # queue. `kolonie-platform#602` sat that way for an afternoon with nobody
    # working it, and nothing said so.
    #
    # **It reports and does not move anything.** Deciding an item is abandoned is
    # a judgement, and a reaper would eventually take an issue away from somebody
    # mid-thought. `#266` says so in as many words.
    #
    # *No run behind it* is read off the issue's own `updated_at` rather than off
    # the run list: a run that died is not in the run list either, and a run that
    # is hung does not say what it was working on. The worker comments when it
    # takes an issue and when it fails, so an issue nothing has touched in
    # `FORGOTTEN_CLAIM_HOURS` has no run behind it whatever the run list says.
    # ## Two clocks, because one of them could not grow (`#381`)
    #
    # The sweep above answers *when to speak*; it is measured on the issue and
    # the report resets it, which is the de-duplication and is right. It is also
    # unusable as a *number*, because after the first report it can never exceed
    # `FORGOTTEN_CLAIM_HOURS` again — so every report said the same thing and no
    # threshold expressed in it could ever fire. `kolonie-platform#815` reported
    # *four hours* three times over a day.
    #
    # The card's own `updatedAt` is the clock that does not reset: a comment on
    # the issue does not touch the item. So the sweep still speaks on the issue
    # clock and now *says* the card clock, which grows, and escalates on it.
    board=$(board_read) ||
      die "could not read the board, so a forgotten claim cannot be found" 1

    # **Emitted whether or not it is time to speak**, because the escalated half
    # of this is read by the daily waiting list rather than written to the issue,
    # and that list runs on its own schedule. `--escalated` is the board alone:
    # no issue is read, so it costs nothing beyond the board it was handed.
    escalated_only=false
    [ "${2:-}" = "--escalated" ] && escalated_only=true

    in_progress=$(jq -r '.items[] | select(.status == "In Progress")
      | "\(.content.repository)\t\(.content.number)\t\(.updatedAt // "")\t\(.content.title)"' <<<"$board")
    [ -n "$in_progress" ] || exit 0

    now=$(date +%s)
    while IFS=$'\t' read -r repo number carded title; do
      [ -n "${repo:-}" ] || continue

      # How long the card has sat where it is. Empty on a board that did not
      # answer with it, and then this reports `-1` rather than a made-up age:
      # the two are not the same finding and a zero would read as *moved just
      # now*, which is the opposite of what is being looked for.
      sitting=-1
      if [ -n "$carded" ] && card_at=$(date -d "$carded" +%s 2>/dev/null); then
        sitting=$(( (now - card_at) / 3600 ))
      fi

      # **What the claim is costing, off the board that is already in hand**
      # (`#381`). `pick` skips every candidate in a repository that has anything
      # In Progress, so a forgotten claim in a repository with a queue behind it
      # is urgent and one in an empty repository is housekeeping. The filters are
      # `pick`'s, minus the dependency check, which would be a call per issue.
      queued=$(jq -r --arg repo "$repo" --arg forbidden "$FORBIDDEN_LABEL" '
        [ .items[]
          | select(.content.repository == $repo)
          | select(.status == "Ready")
          | select((.content.state // "OPEN") == "OPEN")
          | select((.labels // []) | index("queue:worker"))
          | select((.labels // []) | index("blocked:human") | not)
          | select((.labels // []) | index($forbidden) | not)
        ] | length' <<<"$board")

      if [ "$escalated_only" = true ]; then
        [ "$sitting" -ge "$FORGOTTEN_CLAIM_ESCALATE_HOURS" ] &&
          printf '%s\t%s\t%s\t%s\t%s\n' "$repo" "$number" "$sitting" "$queued" "$title"
        continue
      fi

      updated=$(gh api "repos/$repo/issues/$number" --jq '.updated_at' 2>/dev/null) || {
        echo "could not read $repo#$number; saying nothing about it rather than guessing" >&2
        continue
      }
      [ -n "$updated" ] || continue

      # Reporting *is* touching the issue, so the comment the caller writes moves
      # `updated_at` and this stays quiet for another `FORGOTTEN_CLAIM_HOURS`.
      # That is the whole of the de-duplication, and it is deliberate: an item
      # still forgotten four hours later is worth saying again. What `#381`
      # changes is that it is no longer worth saying *identically* — the column
      # after this one is what has grown since the last time.
      #
      # `date` rather than awk's `mktime`, which reads its argument as local time
      # and would report a four-hour-old item as six on a runner in CEST.
      then=$(date -d "$updated" +%s 2>/dev/null) || continue
      hours=$(( (now - then) / 3600 ))
      [ "$hours" -gt "$FORGOTTEN_CLAIM_HOURS" ] &&
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$number" "$hours" "$sitting" "$queued" "$title"
    done <<<"$in_progress"

    exit 0
    ;;

  # Where the board says an issue is, in one word and one point. `release` and
  # `move` both write a column and neither reads one back; `#381` is the incident
  # where that mattered — a failure comment announced a move to Ready that had
  # not happened, and the issue looked attended for a day because of it.
  column)
    repo=$(repo_slug "${2:?column needs a repository}") || exit $?
    number=${3:?column needs an issue number}
    found=$(board_item_status_for "$repo" "$number") ||
      die "could not ask the board where $repo#$number is" 1
    [ -n "$found" ] || die "$repo#$number is not on the board" 3

    # An item with no column is a real state and not an error — it is what an
    # item added to the board and never sorted looks like. It is reported as the
    # words rather than as an empty line, because a caller substituting this into
    # a sentence should not have to know that a blank means anything.
    where=${found#*$'\t'}
    printf '%s\n' "${where:-no column}"
    exit 0
    ;;

  review)
    repo=$(repo_slug "${2:?review needs a repository}") || exit $?
    number=${3:?review needs an issue number}
    item=$(board_item_for "$repo" "$number")
    [ -n "$item" ] || die "$repo#$number vanished from the board" 3

    set_status "$item" "$STATUS_IN_REVIEW" ||
      die "could not move $repo#$number to In Review — a pull request exists and the board does not say so" 4

    exit 0
    ;;

  release)
    repo=$(repo_slug "${2:?release needs a repository}") || exit $?
    number=${3:?release needs an issue number}
    item=$(board_item_for "$repo" "$number")
    [ -n "$item" ] || die "$repo#$number is not on the board" 3

    # **Loudly, and on the issue**, because this is the recovery path and a
    # silent failure here is an issue parked in In Progress forever — which
    # `#142` says will be the issue that most needed attention.
    if ! set_status "$item" "$STATUS_READY"; then
      die "COULD NOT RELEASE $repo#$number back to Ready. It is stuck in In Progress and needs a person: $RUN_URL" 4
    fi

    # **And read it back** (`#381`). `claim` has done this since `#266` and this,
    # the path that matters more, did not: a mutation that reported success and
    # did not take is indistinguishable from one that worked, and the caller then
    # writes *put back in Ready* on the issue. That sentence was wrong for a day
    # on `kolonie-platform#815`, and an issue that says it was returned is one
    # nobody looks at again.
    read -r _ landed < <(board_item_status_for "$repo" "$number")
    [ "${landed:-}" = "Ready" ] ||
      die "released $repo#$number and the board reads back ${landed:-nothing}. It is not in Ready and needs a person: $RUN_URL" 4

    exit 0
    ;;

  # The board write nothing but triage does (`#262`). `release` is the same
  # mutation with the recovery path's wording around it, and a second copy of a
  # GraphQL mutation is the thing §4 refuses about a second record of status.
  #
  # **Only the two columns triage is allowed to write.** It reads Inbox and Ready
  # and moves what it routed to Ready; In Progress and In Review belong to
  # whoever holds them, and Done is Done. A `move` that could write them would be
  # a triage pass able to take work off an agent that has it.
  move)
    repo=$(repo_slug "${2:?move needs a repository}") || exit $?
    number=${3:?move needs an issue number}
    column=${4:?move needs a column: Ready, Inbox or Blocked}
    case "$column" in
      Ready) option=$STATUS_READY ;;
      Inbox) option=$STATUS_INBOX ;;
      Blocked) option=$STATUS_BLOCKED ;;
      *) die "move writes Ready, Inbox or Blocked and nothing else: $column is not one of them. In Progress, In Review and Done belong to whoever holds them." 1 ;;
    esac
    item=$(board_item_for "$repo" "$number")
    [ -n "$item" ] || die "$repo#$number is not on the board" 3
    set_status "$item" "$option" >/dev/null ||
      die "could not move $repo#$number to $column" 4
    echo "moved $repo#$number to $column"
    exit 0
    ;;

  check-command)
    check_command_from "${2:?check-command needs a path to an AGENTS.md}"
    exit 0
    ;;

  check-prerequisite)
    check_prerequisite_from "${2:?check-prerequisite needs a path to an AGENTS.md}"
    exit 0
    ;;

  # The optional argument is for the test, which pins a fixture document rather
  # than asserting against the live list — a test that reads the real file passes
  # by agreeing with whatever is in it.
  prohibited-paths)
    PROHIBITIONS_FILE=${2:-$PROHIBITIONS_FILE}
    prohibited_paths
    exit 0
    ;;

  exports)
    exports_from "${2:?exports needs a file to read}"
    exit 0
    ;;

  failed-step)
    failed_step
    exit 0
    ;;

  excerpt)
    excerpt_from "${2:?excerpt needs a file to read}"
    exit 0
    ;;

  worker-rule-refusal)
    worker_rule_refusal "${2:?worker-rule-refusal needs a file to read}"
    exit 0
    ;;

  failure-digest)
    failure_digest_from "${2:?failure-digest needs a file to read}"
    exit 0
    ;;

  redact)
    redact_from "${2:?redact needs a file to read}"
    exit 0
    ;;

  previous-failures)
    repo=$(repo_slug "${2:?previous-failures needs a repository}") || exit $?
    previous_failures "$repo" "${3:?previous-failures needs an issue number}"
    exit 0
    ;;

  stale-pull-requests)
    stale_pull_requests
    exit 0
    ;;

  unreported-completions)
    unreported_completions
    exit 0
    ;;

  unarmed-pull-requests)
    # The exit code is propagated rather than swallowed, unlike the two sweeps
    # above: this one cannot tell *nothing to arm* from *the organisation could
    # not be listed* in its output, since both are no lines. The workflow reads
    # the code to say which of the two happened.
    unarmed_pull_requests
    exit $?
    ;;

  leak-check)
    shift
    [ "$#" -gt 0 ] || die "leak-check needs at least one file to read" 1
    leak_check "$@"
    exit $?
    ;;

  # ## Putting an issue on the board at all (`#332`)
  #
  # A project takes at most **five** `Auto-add to project` workflows and this one
  # has five, all in use, so every repository past the fifth reaches the board by
  # somebody remembering. `board-triage.sh admit` is what remembers instead, and
  # this is the single write it makes.
  #
  # **Two calls and both are needed.** `addProjectV2ItemById` wants the issue's
  # node id, which is not the number and is not derivable from it, so the id is
  # asked for first. Adding an issue that is already on the board is a documented
  # no-op that answers with the existing item — the caller filters those out
  # before calling, and this stays correct if one slips through.
  #
  # **Then Inbox, in the same breath.** The mutation sets no field, and the
  # built-in *Item added → set Status* workflow has been off since 2026-08-12
  # (`#329`), so an item added and left alone has no Status at all: on the board,
  # in no column, and invisible to `TRIAGE_STATUSES` and to every §6 query that
  # reads a column. Inbox is where an arrival with no decision belongs, and the
  # half-hourly pass reads Inbox — which is the whole point of admitting it.
  # ### The guards, after `#422`
  #
  # Each of the three reads below now fails on the **exit status** first and on
  # emptiness second, and says something different for each. They used to guard
  # on emptiness alone, and `gh` writes its error document to stdout — so a
  # mistyped repository produced an error blob that passed the first guard, was
  # sent to the mutation as a content id, produced a second error blob that
  # passed the second guard, and ended in the message below announcing the one
  # state this docblock calls dangerous. Nothing had been added.
  board-add)
    repo=$(repo_slug "${2:?board-add needs a repository}") || exit $?
    number=${3:?board-add needs an issue number}
    content=$(graphql_value -f query='
      query($owner:String!,$name:String!,$number:Int!){
        repository(owner:$owner,name:$name){issue(number:$number){id}}}' \
      -f owner="${repo%%/*}" -f name="${repo##*/}" -F number="$number" \
      --jq '.data.repository.issue.id // empty') ||
      die "the query for $repo#$number did not run, so nothing is known about it and nothing was added" 2
    [ -n "$content" ] || die "$repo#$number does not exist, so there is nothing to put on the board" 3

    item=$(graphql_value -f query='
      mutation($project:ID!,$content:ID!){
        addProjectV2ItemById(input:{projectId:$project,contentId:$content}){item{id}}}' \
      -f project="$PROJECT_ID" -f content="$content" \
      --jq '.data.addProjectV2ItemById.item.id // empty') ||
      die "could not put $repo#$number on the board — the mutation was refused" 4
    [ -n "$item" ] || die "could not put $repo#$number on the board — it answered with no item" 4

    # **The column, and the message only claims what is true.** `#422`: this line
    # named *on the board and in no column* on a run where nothing had been
    # added, and sent a reader looking for an item that was not there. The board
    # is asked where the issue actually is before anything is said about it, on
    # the same argument as `release` (`#381`) — a message about board state that
    # nobody read back is a guess.
    set_status "$item" "$STATUS_INBOX" >/dev/null || {
      found=$(board_item_status_for "$repo" "$number") ||
        die "could not set $repo#$number's column, and the board could not be asked where it ended up. Check it by hand before adding it again." 5
      [ -n "$found" ] ||
        die "could not set $repo#$number's column, and the board does not show it at all. Nothing to fix there; add it again." 5
      where=${found#*$'\t'}
      die "$repo#$number is on the board and its column could not be set — it is in ${where:-no column}, which is invisible to every reader of the board" 5
    }
    echo "added $repo#$number to the board, in Inbox"
    exit 0
    ;;

  board-read)
    # The board as JSON, for a human or an agent working the loop in AGENTS.md
    # §6. Nothing in this script calls it — the four internal readers call
    # `board_read` directly — but §6 tells a reader to fetch the board once and
    # ask it four things, and an instruction to copy a GraphQL query out of a
    # shell script into a terminal is an instruction to get it subtly wrong.
    board_read || die "could not read the board"
    ;;

  *)
    die "usage: opencode-worker.sh pick | claim <repo> <n> | verify-claim <repo> <n> | blockers <repo> <n> | dependencies <repo> <n> | review <repo> <n> | release <repo> <n> | column <repo> <n> | move <repo> <n> Ready|Inbox|Blocked | check-command <path> | check-prerequisite <path> | prohibited-paths [file] | exports <file> | failed-step | excerpt <file> | failure-digest <file> | redact <file> | worker-rule-refusal <file> | previous-failures <repo> <n> | stale-pull-requests | unreported-completions | unarmed-pull-requests | forgotten-claims [--escalated] | board-read | board-add <repo> <n> | leak-check <file>..."
    ;;
esac

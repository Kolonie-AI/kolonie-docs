#!/bin/bash
# The thing that decides (`kolonie-docs#262`).
#
# Usage:
#   board-triage.sh candidates                        # -> the issues in Inbox and Ready, as JSON
#   board-triage.sh brief <candidates.json> [offset] [count]  # -> what the model reads
#   board-triage.sh apply <candidates.json> <decisions.json>  # -> the labels, links and moves
#   board-triage.sh provenance <login>                # -> member | outside
#   board-triage.sh refusals                          # -> the issues the worker tried and did not finish
#   board-triage.sh proposal-brief <refusals.json>    # -> what the model reads to propose a rule (#264)
#   board-triage.sh propose <proposals.json>          # -> publishes the proposals a person may accept
#
# ## Why this exists
#
# Measured 2026-08-10: 49 issues were created in 24 hours and 46 closed, 21 of
# those by the opencode worker. **Fifteen sat unread in Inbox, and every issue the
# worker was given that day was queued by hand.** The worker exited idle on two
# runs in three because nobody had filled the queue. So the bottleneck was never
# execution — it was that nothing decided.
#
# ## The division of labour in this file, and it is the whole design
#
# **The model judges. This script decides what a judgement is allowed to do.**
# Every rule with a cost attached is enforced here, in code a test can hold to
# account, and not asked of the model:
#
# - a candidate comes from **Inbox or Ready** and nowhere else, so In Progress and
#   In Review cannot be touched however the model answers
# - a route that is missing, unrecognised or uncertain becomes **`agent:claude`**
# - `agent:opencode` is refused on anything carrying `blocked:human`,
#   `opencode:forbidden`, or an open blocker — whatever the model said
# - a route is never **widened**: an issue already routed to a person or to a
#   Claude agent is not handed to the unattended worker by a later pass
# - **priority is not set on an issue that arrived from outside**, which is
#   `blocked:human` class 6 in `AGENTS.md` §5 and not a preference
# - **nothing is ever removed**: no label the model did not ask for, no label a
#   person applied, and no issue body. Triage labels, links and moves
# - `from:external` is set from **organisation membership**, which is a fact
#   GitHub answers and the opener cannot supply (`kolonie-platform#686`)
#
# ## Why the strongest model
#
# `#262`: routing one issue is easy; noticing that a new issue depends on one of
# twenty-five open ones is a judgement over the whole board at once, and it is the
# judgement that stops a worker taking blocked work. It is also the step that
# decides whether a citizen's words reach code — and a cheaper model that is right
# nine times in ten is wrong about that once a week.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)

ORG=${ORG:-Kolonie-AI}
SEARCH_LIMIT=${SEARCH_LIMIT:-200}

# ## Two credentials, because the board and the issues are two permissions
#
# Since `#270` the board is moved by the `kolonie-opencode` GitHub App, which holds
# Organization projects and Metadata and **nothing else** — it cannot label an
# issue or write a comment. The labels, the comments and the dependency links need
# a credential that reaches the five repositories carrying board issues, which is
# `WORKER_REPO_TOKEN`.
#
# So `GH_TOKEN` is the issue credential and `BOARD_TOKEN`, when set, is used for
# the one call that moves a card. Unset means *the same token does both*, which is
# what the tests do and what a person running this by hand wants.
BOARD_TOKEN=${BOARD_TOKEN:-}

# The card move, with whichever credential can make it.
move_card() {
  local repo=$1 number=$2 column=$3
  if [ -n "$BOARD_TOKEN" ]; then
    GH_TOKEN=$BOARD_TOKEN bash "$HERE/opencode-worker.sh" move "$repo" "$number" "$column"
  else
    bash "$HERE/opencode-worker.sh" move "$repo" "$number" "$column"
  fi
}

# The two columns triage reads. In Progress and In Review belong to whoever holds
# them and Done is Done — `#262` is explicit, and re-triaging work in flight is
# how two agents end up holding one issue.
TRIAGE_STATUSES=${TRIAGE_STATUSES:-Inbox|Ready}

# The routes, in the order of increasing autonomy. The order is load-bearing: a
# pass may move an issue *down* it and never up.
ROUTES=${ROUTES:-agent:human agent:claude agent:opencode}

# The mark the worker leaves on an issue it tried and did not finish (`#255`), and
# the filter `#264`'s half of this file reads.
FAILED_LABEL=${FAILED_LABEL:-opencode:failed}

# The provenances that make a priority somebody else's to set (`AGENTS.md` §5,
# class 6 of `blocked:human`). An agent triaging its own board may prioritise;
# nothing may prioritise an issue that arrived from outside the Colony.
OUTSIDE_PROVENANCE=${OUTSIDE_PROVENANCE:-from:citizen from:external needs-triage}

# ## Where a proposed prohibition goes (`#264`)
#
# `#264` says the proposal is a comment on `kolonie-docs#142` — which closed on
# 2026-08-10, so that address no longer exists. The shape it asked for does: one
# place a person reads, one comment per proposal, nothing rewritten. So the
# proposals collect on **one issue found by its title**, created when there is a
# first proposal to make and not before — the same handle
# `waiting-for-an-agent.yml` uses, and for the same reason: a number committed here
# would be a second record of something GitHub holds.
PROPOSAL_ISSUE_TITLE=${PROPOSAL_ISSUE_TITLE:-Proposed additions to the worker prohibitions}
PROPOSAL_REPO=${PROPOSAL_REPO:-$ORG/kolonie-docs}

# **Two, not three** (`#264`). The existing failure counter fires at two and says an
# issue that fails twice is a finding rather than a queue position; this is the same
# number for the same reason. One refusal can be one badly written issue; two of a
# kind is a rule waiting to be written.
PROPOSAL_THRESHOLD=${PROPOSAL_THRESHOLD:-2}

# How many issues the refusal read covers, and how much of each comment thread.
# Bounded because this runs hourly and the interesting part of a refusal is its
# first paragraph, not the thread under it.
REFUSAL_LIMIT=${REFUSAL_LIMIT:-20}
REFUSAL_COMMENTS=${REFUSAL_COMMENTS:-4}
REFUSAL_CHARS=${REFUSAL_CHARS:-1200}

# The generated list is not work (`#265`). It sits in Inbox by design, carries no
# route, and a triage pass that routed it would be labelling its own report.
# Matched by title, which is the handle `waiting-for-an-agent.yml` uses as well —
# a number here would be a second record of something GitHub holds.
NOT_WORK_TITLES=${NOT_WORK_TITLES:-What is waiting for an agent}

# How much of a body the model is given. A candidate is read; everything else is
# an index entry, there so a dependency can be noticed. Both are bounded because
# the board is one prompt and one long body should not cost the rest of it.
CANDIDATE_BODY_CHARS=${CANDIDATE_BODY_CHARS:-4000}
INDEX_BODY_CHARS=${INDEX_BODY_CHARS:-400}

die() {
  echo "$1" >&2
  exit "${2:-1}"
}

note() {
  echo "$1" >&2
}

# Is this login in the organisation? `member | outside`, and nothing else —
# including when GitHub cannot be asked, which answers `outside` for no issue at
# all because the caller treats an unreadable answer as *leave the labels alone*.
#
# ## Why membership rather than `authorAssociation`
#
# `#686`: the label *must not be forgeable*. `authorAssociation` is computed from
# the author's relationship to the repository and reads `NONE` for an
# organisation member who has never touched that particular repository, so it
# marks colleagues as outsiders and would put `from:external` on the Colony's own
# work. Membership is the question actually being asked.
provenance() {
  local login=$1
  [ -n "$login" ] || { echo "unknown"; return 0; }
  if gh api "orgs/$ORG/members/$login" --silent >/dev/null 2>&1; then
    echo "member"
  else
    echo "outside"
  fi
}

# Everything open in the organisation, joined to its board column.
#
# **One search and one board read.** The search is served by GitHub's search
# allowance (30 a minute, a pool separate from `core` and `graphql`), the board
# read is the worker's own `board-read` — a second copy of that GraphQL is what
# `#269` took out of `board_item_for`.
candidates() {
  local issues board
  issues=$(gh search issues --owner "$ORG" --state open --limit "$SEARCH_LIMIT" \
    --json repository,number,title,body,labels,author,createdAt,url) ||
    die "the issues could not be searched, so nothing can be triaged" 2
  [ -n "$issues" ] && [ "$(jq 'length' <<<"$issues")" -gt 0 ] || {
    echo '{"candidates":[],"index":[]}'
    return 0
  }

  board=$(mktemp) || die "no temporary file" 2
  # `board-read` and not `gh project item-list`: it follows `pageInfo` to the end,
  # and a board read that stops at one page is wrong whichever call it uses.
  bash "$HERE/opencode-worker.sh" board-read >"$board" || {
    rm -f "$board"
    die "the board could not be read, so no column can be trusted" 2
  }

  jq -c --slurpfile board "$board" \
    --arg statuses "$TRIAGE_STATUSES" \
    --arg notwork "$NOT_WORK_TITLES" \
    --argjson candidate_chars "$CANDIDATE_BODY_CHARS" \
    --argjson index_chars "$INDEX_BODY_CHARS" '
    ($statuses | split("|")) as $triage
    | [ .[]
        | { repo: .repository.nameWithOwner,
            number: .number,
            title: .title,
            body: (.body // ""),
            labels: [.labels[].name],
            author: (.author.login // ""),
            # **Whether the opener is a machine, from GitHub and not from the
            # name.** `.author.type` answers `Bot`; `is_bot` in the same object
            # answered `false` for `kolonie-triage[bot]` on 2026-08-10, so the
            # suffix is kept as a second reading rather than as the only one.
            bot: (((.author.type // "") == "Bot") or ((.author.login // "") | test("\\[bot\\]$"))),
            createdAt: .createdAt,
            url: .url }
        | . as $issue
        | (($board[0].items[]
            | select(.content.number == $issue.number
                     and .content.repository == $issue.repo)
            | .status) // "not on the board") as $status
        | $issue + { status: $status } ]
    | { candidates: [ .[]
          | select(.status as $s | $triage | index($s))
          | select(.title != $notwork)
          | { repo, number, title, status, labels, author, bot, createdAt, url,
              body: (.body[0:$candidate_chars]) } ],
        index: [ .[]
          | { repo, number, title, status, labels, createdAt,
              body: (.body[0:$index_chars]) } ] }
  ' <<<"$issues"
  local rc=$?
  rm -f "$board"
  [ "$rc" -eq 0 ] || die "the board and the issues could not be joined" 2
}

# What the model reads. Markdown rather than JSON, because the rules it is being
# asked to apply are documents and quoting a document inside a JSON string makes
# it unreadable to the thing that has to follow it.
# ## Why the candidates are asked for a few at a time
#
# Measured 2026-08-10 against the live board: 38 candidates and 47 open issues is
# a 154 KB brief, and the gateway answered **524** — a proxy timeout, not a
# refusal — after the model had been thinking for minutes. Six candidates against
# the same whole-board index is 54 KB and answers in about fifty seconds.
#
# **The index is never sliced, only the candidates are.** Step 4 of `#262` — does
# this issue read something another open issue creates — is a judgement against
# the whole board, so every chunk carries every open issue and decides about six of
# them. Slicing the index instead would make the dependency judgement cheaper and
# wrong.
brief() {
  local file=$1 offset=${2:-0} count=${3:-0}
  [ -f "$file" ] || die "brief needs the file \`candidates\` wrote" 1

  local prohibitions routes
  # The two rules, quoted from where they live rather than restated (`#259`,
  # `#260`). A prompt carrying its own copy of the routing table is a third copy
  # of it, and the third copy is the one that goes stale.
  routes=$(awk '/^### The three routes/,/^#### What this is not/' "$ROOT/AGENTS.md")
  prohibitions=$(cat "$ROOT/operations/worker-prohibitions.md")

  local slice
  if [ "$count" -gt 0 ]; then
    slice=".candidates[$offset:$((offset + count))]"
  else
    slice=".candidates"
  fi

  cat <<HEADER
# The board, as it stands

$(jq -r --argjson n "$(jq "$slice | length" "$file")" '"There are \($n) issue(s) below to decide about, out of \(.candidates | length) in Inbox or Ready, and \(.index | length) open issue(s) in total."' "$file")

# The routing rule (AGENTS.md §5)

$routes

# What no worker can do (operations/worker-prohibitions.md)

$prohibitions

# Every open issue, so that a dependency can be noticed

HEADER

  jq -r '.index[] | "- \(.repo)#\(.number) [\(.status)] \(.title)\n  labels: \(.labels | join(", "))\n  \(.body | gsub("\n"; " "))"' "$file"

  cat <<'MIDDLE'

# The issues to decide about

Each one is in Inbox or in Ready. Nothing else is yours to touch.

MIDDLE

  jq -r "$slice"' | .[] | "## \(.repo)#\(.number) — \(.title)\n\nstatus: \(.status)\nlabels: \(.labels | join(", "))\nopened by: \(.author) on \(.createdAt)\n\n\(.body)\n"' "$file"
}

# The writes. Everything above this line reads; everything below it is bounded by
# the guards in the header, which is why they are here and not in the prompt.
apply() {
  local candidates=$1 decisions=$2
  [ -f "$candidates" ] || die "apply needs the file \`candidates\` wrote" 1
  [ -f "$decisions" ] || die "apply needs the file the model wrote" 1

  # ## Not tab separated, and the reason is a bug this had
  #
  # **Tab is IFS whitespace, so `read` collapses a run of them into one
  # delimiter.** A decision with no priority and no readiness label — the ordinary
  # case — arrived with its dependency list in the priority variable and its
  # `ready` flag one field further along, which read as *not ready* and left every
  # issue in Inbox with a plausible reason. `\x1f` is the unit separator, is not
  # IFS whitespace, and preserves an empty field.
  local rows changed=0
  rows=$(jq -r '.decisions[]? | [.repo, (.number|tostring), (.route // ""), (.priority // ""), (.readiness // ""), ((.depends_on // []) | join(" ")), (.ready // false | tostring), ((.reason // "") | gsub("[\n\r]+"; " "))] | join("\u001f")' "$decisions") ||
    die "the model's answer is not the shape this script applies" 3

  [ -n "$rows" ] || { note "the model decided nothing this pass"; return 0; }

  local repo number route priority readiness depends ready reason
  while IFS=$'\x1f' read -r repo number route priority readiness depends ready reason; do
    [ -n "${repo:-}" ] && [ -n "${number:-}" ] || continue
    apply_one "$candidates" "$repo" "$number" "$route" "$priority" "$readiness" "$depends" "$ready" "$reason" &&
      changed=$((changed + 1))
  done <<<"$rows"

  echo "triage changed $changed issue(s)"
}

# One issue. Returns 0 when something was written, 1 when nothing was — the
# caller counts, and `#262` says a triage that comments on everything is a triage
# nobody reads.
apply_one() {
  local candidates=$1 repo=$2 number=$3 route=$4 priority=$5 readiness=$6 depends=$7 ready=$8 reason=$9

  local candidate labels status
  candidate=$(jq -c --arg repo "$repo" --argjson number "$number" \
    '.candidates[] | select(.repo == $repo and .number == $number)' "$candidates")
  if [ -z "$candidate" ]; then
    # Not a failure: the model was given the board and answered about something
    # that is not on the part of it triage may write. Refused here rather than
    # trusted, because this is the guard that keeps In Progress out of reach.
    note "$repo#$number is not one of this pass's candidates — skipped"
    return 1
  fi

  labels=" $(jq -r '.labels | join(" ")' <<<"$candidate") "
  status=$(jq -r '.status' <<<"$candidate")

  local -a add=()
  local -a said=()

  # ## Provenance, from GitHub's facts and not from the model
  local author existing_from opened_by_machine
  author=$(jq -r '.author' <<<"$candidate")
  opened_by_machine=$(jq -r '.bot // false' <<<"$candidate")
  existing_from=$(jq -r '[.labels[] | select(startswith("from:"))] | join(" ")' <<<"$candidate")
  if [ "$opened_by_machine" = "true" ]; then
    # **A machine is never `from:external`, and this was measured the expensive
    # way.** The first live pass labelled `kolonie-infra#119` — filed by
    # `github-actions[bot]`, one of the Colony's own watchers — as external,
    # because a bot is not a *member* of the organisation. `from:external` is the
    # provenance that makes work security-sensitive, so getting it wrong in that
    # direction is the one error this label must not make. Which machine filed it
    # is a question membership cannot answer, so nothing is guessed:
    # `kolonie-platform#686` makes the creating paths label themselves.
    note "$repo#$number was opened by $author, a machine — its provenance is the creating path's to set (kolonie-platform#686), not membership's"
  elif [ -z "$existing_from" ] && [ -n "$author" ]; then
    case "$(provenance "$author")" in
      outside)
        add+=("from:external")
        said+=("\`from:external\`, because \`$author\` is not a member of the organisation — the one provenance the opener cannot supply")
        ;;
      member)
        # Deliberately nothing. Which *kind* of member opened it — a maintainer,
        # the maintainer agent, a runner — is not a question membership answers,
        # and guessing it is exactly the *route on the author's say-so* that
        # `#262` refuses. `kolonie-platform#686` is the issue that makes the
        # creating paths label themselves.
        note "$repo#$number carries no from: label and its author is inside the organisation, which does not say which kind — left for kolonie-platform#686"
        ;;
    esac
  fi

  # ## The route, and the four ways the model's answer is overruled
  local current_route=""
  local candidate_route
  for candidate_route in $ROUTES; do
    case "$labels" in *" $candidate_route "*) current_route=$candidate_route ;; esac
  done

  route=$(sane_route "$route" "$labels" "$current_route" "$depends")
  local -a remove=()
  if [ "$route" != "$current_route" ]; then
    add+=("$route")
    said+=("\`$route\`")
    # **The old route comes off in the same call, and this is the one place
    # anything is removed.** `#259` says exactly one of the three, always — a
    # route *added* beside another is two routes, which is the state that rule
    # exists to prevent. Measured the expensive way: the first live pass put
    # `agent:human` on nine issues that already carried `agent:claude` and left
    # both on, so the pass that enforces the invariant was the thing breaking it.
    if [ -n "$current_route" ]; then
      remove+=("$current_route")
      said+=("instead of \`$current_route\`")
    fi
  fi

  # ## Readiness — added, never removed, and never in place of a route
  case "$readiness" in
    decision | idea)
      case "$labels" in
        *" $readiness "*) : ;;
        *)
          add+=("$readiness")
          said+=("\`$readiness\`")
          ;;
      esac
      ;;
  esac

  # ## Priority, unless it arrived from outside
  case "$priority" in
    p1 | p2)
      if has_any "$labels" "p1 p2"; then
        : # somebody has already decided this, and triage does not overrule it
      elif has_any "$labels" "$OUTSIDE_PROVENANCE" || in_list "from:external" "${add[*]:-}"; then
        note "$repo#$number arrived from outside, so its priority waits for a person (AGENTS.md §5, class 6)"
      else
        add+=("$priority")
        said+=("\`$priority\`")
      fi
      ;;
  esac

  # ## Dependencies — recorded as the relation the queue reads, not as prose
  local blocker linked=""
  for blocker in $depends; do
    [ -n "$blocker" ] || continue
    if link_blocker "$repo" "$number" "$blocker"; then
      linked+="$blocker "
      said+=("blocked by $blocker")
    fi
  done

  local blockers=""
  blockers=$(bash "$HERE/opencode-worker.sh" blockers "$repo" "$number" 2>/dev/null | tr '\n' ' ')

  # ## The labels, in one call
  if [ ${#add[@]} -gt 0 ] || [ ${#remove[@]} -gt 0 ]; then
    local -a args=()
    local label
    for label in ${add[@]+"${add[@]}"}; do args+=(--add-label "$label"); done
    for label in ${remove[@]+"${remove[@]}"}; do args+=(--remove-label "$label"); done
    if ! gh issue edit "$number" --repo "$repo" "${args[@]}" >/dev/null 2>&1; then
      note "the labels on $repo#$number could not be written: ${add[*]:-} ${remove[*]:+(-${remove[*]})}"
      return 1
    fi
  fi

  # ## The move, and the three reasons it does not happen
  local why_not=""
  if [ -n "$blockers" ]; then
    why_not="it waits for $(echo "$blockers" | sed 's/ *$//')"
  elif [ "$ready" != "true" ]; then
    why_not="it is not specified well enough to act on"
  elif has_any "$labels" "blocked:human"; then
    why_not="it is \`blocked:human\`, which is a person's decision and not a queue position"
  fi

  # **Ready is read as well as written, so the queue can be left as well as
  # joined.** An issue already in Ready that this pass has just found a blocker
  # for is in the queue and cannot be finished from it — `#262`'s *stays out of
  # the queue* is a move for that one, not an omission. The other direction is the
  # ordinary case: routed, unblocked, specified, so it joins.
  if [ -n "$why_not" ]; then
    if [ "$status" = "Ready" ]; then
      if move_card "$repo" "$number" Inbox >/dev/null 2>&1; then
        said+=("taken out of Ready")
      else
        note "$repo#$number should leave Ready and could not be moved"
      fi
    fi
  elif [ "$status" = "Ready" ]; then
    : # already there, and moving it to where it is is not a change
  elif move_card "$repo" "$number" Ready >/dev/null 2>&1; then
    said+=("moved to Ready")
  else
    note "$repo#$number could not be moved to Ready"
  fi

  if [ ${#said[@]} -eq 0 ] && [ -z "$why_not" ]; then
    return 1
  fi

  comment "$repo" "$number" "$route" "$reason" "$why_not" "${said[@]:-}"
}

# `agent:claude` unless every reason to say otherwise holds. This function is the
# safety property of the whole pass, which is why it is one place.
sane_route() {
  local proposed=$1 labels=$2 current=$3 depends=$4

  # An answer that is not one of the three is not an answer.
  in_list "$proposed" "$ROUTES" || proposed="agent:claude"

  # ## The route is a ratchet: it may tighten and never loosen
  #
  # `ROUTES` is ordered by increasing autonomy, and a pass may move an issue down
  # that order and never up. The obvious half is that nothing hands the unattended
  # worker an issue a person or a Claude agent already holds a route for. The half
  # that had to be measured is the other one: the second live pass moved three
  # issues from `agent:human` back to `agent:claude`, which is a *widening*, and two
  # passes that disagree about one issue would then trade it back and forth with a
  # comment every hour. Tightening converges — there are two steps and then it
  # stops.
  #
  # **So a route can only be loosened by a person**, which is the right way round
  # for the label that means *no coding agent may take this*.
  if [ -n "$current" ] && [ "$(route_rank "$proposed")" -gt "$(route_rank "$current")" ]; then
    proposed=$current
  fi

  # The three things that make the unattended queue the wrong place, whatever the
  # issue looks like: a person's decision, a structurally forbidden path, and work
  # that cannot be finished until something else exists.
  if [ "$proposed" = "agent:opencode" ]; then
    if has_any "$labels" "blocked:human opencode:forbidden"; then
      proposed="agent:human"
      has_any "$labels" "opencode:forbidden" && proposed="agent:claude"
    elif [ -n "$depends" ]; then
      proposed="agent:claude"
    fi
  fi

  echo "$proposed"
}

# Where a route sits in `ROUTES`: 0 is the least autonomous. An unknown route ranks
# above everything, so it can never survive the comparison above.
route_rank() {
  local wanted=$1 one rank=0
  for one in $ROUTES; do
    [ "$one" = "$wanted" ] && { echo "$rank"; return 0; }
    rank=$((rank + 1))
  done
  echo 99
}

# The dependency, as the relation `#261` made readable. Prose in a body is what
# `kolonie-platform#660` cost, so triage records the relation or records nothing.
link_blocker() {
  local repo=$1 number=$2 blocker=$3
  local blocker_repo blocker_number blocker_id state

  blocker_repo=${blocker%#*}
  blocker_number=${blocker##*#}
  case "$blocker_repo" in */*) : ;; *) blocker_repo="$ORG/$blocker_repo" ;; esac
  case "$blocker_number" in '' | *[!0-9]*) note "$blocker is not an issue reference"; return 1 ;; esac
  [ "$blocker_repo#$blocker_number" != "$repo#$number" ] || return 1

  local answer
  answer=$(gh api "repos/$blocker_repo/issues/$blocker_number" \
    --jq '"\(.id) \(.state)"' 2>/dev/null) || answer=""
  if [ -z "$answer" ]; then
    note "$blocker could not be read, so it was not linked to $repo#$number"
    return 1
  fi
  blocker_id=${answer% *}
  state=${answer#* }
  # A closed blocker is not a blocker. Recording it would put a permanent
  # relation on the board for something that has already happened.
  [ "$state" = "open" ] || return 1

  # **The duplicate is detected from the answer rather than by asking first.** A
  # relation that already exists answers 422 — as does one that would close a
  # cycle, and both mean *not written and nothing changed* rather than a failure — and asking `blockers` beforehand would be one extra call per
  # dependency to learn something the write says by itself. Either way nothing
  # changed, so neither is reported: an hourly comment saying a link that was
  # already there is still there is the noise `#262` refuses.
  # **A mutual dependency is a deadlock, not a relation.** Two issues each waiting
  # for the other are both permanently out of the queue, and nothing on the board
  # would say why. The model has proposed a pair once already, on 2026-08-10, in a
  # run whose answer was thrown away for another reason.
  if bash "$HERE/opencode-worker.sh" blockers "$blocker_repo" "$blocker_number" 2>/dev/null |
    grep -qxF "$repo#$number"; then
    note "$blocker_repo#$blocker_number already waits for $repo#$number, so linking it back would deadlock both — not linked"
    return 1
  fi

  local failure
  failure=$(gh api --method POST "repos/$repo/issues/$number/dependencies/blocked_by" \
    -F issue_id="$blocker_id" 2>&1 >/dev/null) && return 0
  case "$failure" in
    *422*) return 1 ;;
    *)
      note "$blocker_repo#$blocker_number could not be linked as a blocker of $repo#$number: $failure"
      return 1
      ;;
  esac
}

# One comment, and only when something was written (`#262`).
comment() {
  local repo=$1 number=$2 route=$3 reason=$4 why_not=$5
  shift 5
  local -a said=("$@")
  local body

  body="**Triaged.** $(printf '%s' "${said[*]}" | sed 's/  */ /g')"
  [ -n "$reason" ] && body+=$'\n\n'"$reason"
  if [ -n "$why_not" ]; then
    case " ${said[*]} " in
      *"taken out of Ready"*) body+=$'\n\n'"**Out of the queue**: $why_not." ;;
      *) body+=$'\n\n'"**Left in Inbox**: $why_not." ;;
    esac
  fi
  body+=$'\n\n'"<sub>Routed against \`AGENTS.md\` §5 and \`operations/worker-prohibitions.md\` by \`.github/workflows/board-triage.yml\` (\`kolonie-docs#262\`). Wrong route? Change the label and say why — an inherited label is not evidence.</sub>"

  gh issue comment "$number" --repo "$repo" --body "$body" >/dev/null 2>&1 || {
    note "the triage comment on $repo#$number could not be written"
    return 1
  }
  echo "$repo#$number: ${said[*]}"
  return 0
}

# ## The refusals, which are the only evidence a prohibition may be written from
#
# `#264`: three issues were queued on 2026-08-09 and 10 that no run could finish,
# each produced a clear correct refusal, and **each lesson landed in a comment and
# nowhere else** — so the second and third mistakes were made with the first one's
# answer already written down. That is the difference between a system that reports
# and one that learns.
#
# `opencode:failed` is the filter: *what did the worker try and not finish*
# (`#255`). The comments are where the reason is, because that is where the worker
# writes it.
refusals() {
  local issues
  issues=$(gh search issues --owner "$ORG" --state open --label "$FAILED_LABEL" \
    --limit "$REFUSAL_LIMIT" --json repository,number,title,labels) ||
    die "the failed issues could not be searched, so no refusal can be read" 2
  [ -n "$issues" ] || issues='[]'

  local rows repo number title labels comments out
  out=$(mktemp) || die "no temporary file" 2
  rows=$(jq -r '.[] | "\(.repository.nameWithOwner)\t\(.number)"' <<<"$issues")

  while IFS=$'\t' read -r repo number; do
    [ -n "${repo:-}" ] || continue
    # The last few comments and no more. A refusal is at the top of the thread the
    # worker wrote; everything after it is a person arguing with it, which is worth
    # reading and is not worth the whole thread.
    comments=$(gh issue view "$number" --repo "$repo" --json comments \
      --jq "[.comments[-$REFUSAL_COMMENTS:][] | \"\(.author.login): \(.body[0:$REFUSAL_CHARS])\"]" 2>/dev/null) ||
      comments='[]'
    jq -cn --arg repo "$repo" --argjson number "$number" \
      --argjson comments "${comments:-[]}" \
      --argjson issue "$(jq -c --arg r "$repo" --argjson n "$number" '.[] | select(.repository.nameWithOwner == $r and .number == $n)' <<<"$issues")" '
      { repo: $repo, number: $number, title: $issue.title,
        labels: [$issue.labels[].name], comments: $comments }' >>"$out"
  done <<<"$rows"

  jq -s '{refusals: .}' "$out"
  rm -f "$out"
}

# What the model reads to propose a rule. The prohibitions as they stand, the
# proposals a person has already been shown, and the refusals.
proposal_brief() {
  local file=$1
  [ -f "$file" ] || die "proposal-brief needs the file \`refusals\` wrote" 1

  local seen
  seen=$(proposed_keys)

  cat <<HEADER
# What no worker can do, as it stands

$(cat "$ROOT/operations/worker-prohibitions.md")

# Proposals already made, which must not be made again

${seen:-(none yet)}

# The refusals

$(jq -r '"There are \(.refusals | length) open issue(s) the worker tried and did not finish."' "$file")

HEADER

  jq -r '.refusals[] | "## \(.repo)#\(.number) — \(.title)\n\nlabels: \(.labels | join(", "))\n\n\(.comments | join("\n\n---\n\n"))\n"' "$file"
}

# The keys of every proposal already published, read off the collecting issue. A
# marker comment rather than a parse of the prose: the prose is for a person and
# will be edited, and a proposal that reappears every hour is the noise `#262`
# refuses.
proposed_keys() {
  local number
  number=$(proposal_issue) || return 0
  [ -n "$number" ] || return 0
  gh issue view "$number" --repo "$PROPOSAL_REPO" --json comments \
    --jq '.comments[].body' 2>/dev/null |
    sed -n 's/.*<!-- prohibition-proposal: \([a-z0-9-]*\) -->.*/\1/p'
}

# The collecting issue's number, or nothing. Found by title, never by a number
# committed here.
#
# **Listed and filtered here rather than searched, and that cost an issue to
# learn.** `--search "in:title"` goes through GitHub's search index, which had not
# heard of the issue this function had created seconds earlier — so the second
# proposal of the first live run opened a *second* collecting issue. The issues REST
# list is the repository's own state and has no index behind it. `PROPOSAL_NUMBER`
# then holds the answer for the rest of the run, because two proposals in one pass
# must not race each other either.
PROPOSAL_NUMBER=${PROPOSAL_NUMBER:-}

proposal_issue() {
  if [ -n "$PROPOSAL_NUMBER" ]; then
    printf '%s\n' "$PROPOSAL_NUMBER"
    return 0
  fi
  PROPOSAL_NUMBER=$(gh issue list --repo "$PROPOSAL_REPO" --state open --limit 100 \
    --json number,title \
    --jq "[.[] | select(.title == \"$PROPOSAL_ISSUE_TITLE\")] | .[0].number // empty" 2>/dev/null)
  printf '%s\n' "$PROPOSAL_NUMBER"
}

# The proposals, filtered by the threshold and by what has already been said, then
# published for a person to accept.
#
# **It proposes; it does not edit the list.** The list is what constrains the
# workers, and a worker that could widen its own constraints has none — the same
# reason the opencode worker may not write `.github/workflows/`.
propose() {
  local file=$1
  [ -f "$file" ] || die "propose needs the file the model wrote" 1

  local seen published=0
  seen=$(proposed_keys | tr '\n' ' ')

  local rows key reason issues wording count
  rows=$(jq -r '.proposals[]? | [.key, ((.issues // []) | join(" ")), (.reason // "" | gsub("[\n\r]+"; " ")), (.wording // "" | gsub("[\n\r]+"; " "))] | join("\u001f")' "$file") ||
    die "the model's proposals are not the shape this script publishes" 3

  [ -n "$rows" ] || { note "no prohibition was proposed this pass"; return 0; }

  while IFS=$'\x1f' read -r key issues reason wording; do
    [ -n "${key:-}" ] || continue

    # Two, not three, and counted here rather than trusted from the answer.
    count=$(printf '%s\n' $issues | grep -c '#' || true)
    if [ "${count:-0}" -lt "$PROPOSAL_THRESHOLD" ]; then
      note "\"$key\" rests on $count refusal(s) and the threshold is $PROPOSAL_THRESHOLD — not proposed"
      continue
    fi

    if in_list "$key" "$seen"; then
      note "\"$key\" has already been proposed and is waiting for a person"
      continue
    fi

    publish_proposal "$key" "$issues" "$reason" "$wording" && published=$((published + 1))
    seen+=" $key"
  done <<<"$rows"

  echo "$published prohibition(s) proposed"
}

publish_proposal() {
  local key=$1 issues=$2 reason=$3 wording=$4
  local number body

  number=$(proposal_issue)
  if [ -z "$number" ]; then
    # Created on the first proposal and not before: an empty collecting issue is a
    # notification about nothing.
    number=$(gh issue create --repo "$PROPOSAL_REPO" \
      --title "$PROPOSAL_ISSUE_TITLE" \
      --label agent:human --label area:docs --label p2 \
      --body "Each comment here is one prohibition the triage pass has proposed for [\`operations/worker-prohibitions.md\`](https://github.com/$PROPOSAL_REPO/blob/main/operations/worker-prohibitions.md), because a refusal reason appeared on at least $PROPOSAL_THRESHOLD issues and matched nothing on that list (\`kolonie-docs#264\`).

**A person accepts one by editing the document.** Nothing here edits it: a worker that could widen its own constraints has none, which is the same reason the opencode worker may not write \`.github/workflows/\`. Rejecting one is a reply saying why — the pass reads the keys it has already proposed and will not repeat itself." 2>/dev/null | sed 's|.*/||')
    [ -n "$number" ] || {
      note "the collecting issue for proposed prohibitions could not be created"
      return 1
    }
    # Held for the rest of the run, so a second proposal in the same pass comments
    # rather than opening a second collecting issue.
    PROPOSAL_NUMBER=$number
    echo "opened $PROPOSAL_REPO#$number to collect proposed prohibitions" >&2
  fi

  body="**A refusal reason that is not on the list.** $reason

Seen on: $(printf '%s' "$issues" | sed 's/ /, /g')

**Suggested wording:**

> $wording

<sub>Proposed by the triage pass (\`kolonie-docs#264\`) because this reason appeared on $PROPOSAL_THRESHOLD or more issues and matched nothing in \`operations/worker-prohibitions.md\`. **Accept it by editing that file**; reject it by replying with why. Either way it will not be proposed again.</sub>
<!-- prohibition-proposal: $key -->"

  gh issue comment "$number" --repo "$PROPOSAL_REPO" --body "$body" >/dev/null 2>&1 || {
    note "the proposal \"$key\" could not be published on $PROPOSAL_REPO#$number"
    return 1
  }
  echo "proposed \"$key\" on $PROPOSAL_REPO#$number, from $count refusals"
  return 0
}

has_any() {
  local labels=$1 wanted=$2 one
  for one in $wanted; do
    case "$labels" in *" $one "*) return 0 ;; esac
  done
  return 1
}

in_list() {
  local needle=$1 haystack=$2 one
  [ -n "$needle" ] || return 1
  for one in $haystack; do
    [ "$one" = "$needle" ] && return 0
  done
  return 1
}

case "${1:-}" in
  candidates)
    candidates
    ;;
  brief)
    brief "${2:?brief needs the file \`candidates\` wrote}" "${3:-0}" "${4:-0}"
    ;;
  apply)
    apply "${2:?apply needs the candidates file}" "${3:?apply needs the decisions file}"
    ;;
  provenance)
    provenance "${2:?provenance needs a login}"
    ;;
  refusals)
    refusals
    ;;
  proposal-brief)
    proposal_brief "${2:?proposal-brief needs the file \`refusals\` wrote}"
    ;;
  propose)
    propose "${2:?propose needs the file the model wrote}"
    ;;
  *)
    die "usage: board-triage.sh candidates | brief <candidates.json> [offset] [count] | apply <candidates.json> <decisions.json> | provenance <login> | refusals | proposal-brief <refusals.json> | propose <proposals.json>" 1
    ;;
esac

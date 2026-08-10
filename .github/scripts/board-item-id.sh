#!/bin/bash
# The board item id for an issue, without reading the board. `AGENTS.md` §4.
#
# Usage:
#   board-item-id.sh <repo> <number>       # one item: id and column, 1 point
#   board-item-id.sh --map [cache-file]    # every item, URL to id, one page per 100
#   board-item-id.sh --cost                # what each pool has left, and when it resets
#
# ## Why this file exists
#
# `gh project item-list` is the only obvious way to turn an issue into the item
# id that a card move needs, and it was the most expensive call in the loop:
# **304 GraphQL points against a 205-item board** (measured 2026-08-08), because
# the charge is per item *requested* and it asks for every field of every one. An
# agent that read the whole board once per issue it wanted to place spent the
# organisation's hourly budget on six issues.
#
# The single lookup below costs **1 point** and is also the more correct call —
# it answers from the board now, rather than from a snapshot taken minutes ago
# that another agent may already have invalidated.
#
# ## What actually costs what
#
#   gh project item-list --limit 1000     304 points   205 items, 2026-08-08
#   board-read, the whole board             2 points   129 items, 2026-08-10
#   one issue by repository and number       1 point
#   one card move                            1 point
#   the same lookup over REST                0 GraphQL points
#
# **The read used to be the whole bill.** `kolonie-docs#227` recorded one board
# read plus three card moves at 206 points, and it is worth reading that number
# the right way round: 203 of it was the read and the three moves were a point
# each. `#269` then replaced the read with a query that asks for the five fields
# anybody uses, and `#271` moved this file's `--map` onto it — so the read is now
# roughly the price of two card moves.
#
# ## Which mode to use
#
# **The single lookup, still, for one issue.** But the threshold moved and it
# moved a long way (`#271`, 2026-08-10). `--map` used to beat a batch of lookups
# from about three hundred issues; at 2 points a read it beats them **from
# about three**. So a batch is now the ordinary case for it rather than the rare
# one.
#
# What has not changed is that a map goes stale from the moment it is written,
# and a lookup does not. That is the reason to prefer the lookup when you are
# placing one issue, and it is now the *only* reason — the arithmetic no longer
# argues for it.
#
# ## No credential is stored by any of this
#
# Both modes use whatever `gh` is already authenticated as. Nothing here writes a
# token, reads one out of a file, or takes one as an argument — §4's refusal on
# `kolonie-docs#118` stands, and a cache file that held a credential would be a
# worse trade than the points it saves.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ORG=Kolonie-AI
# The board, by id. An issue can sit on more than one project and only one of
# them is this board — see the single lookup below. `--map` needs no number of
# its own: it asks `board-read`, which holds one (`BOARD_PROJECT`).
PROJECT_ID=${PROJECT_ID:-PVT_kwDOEmwuYs4BebbB}

usage() {
  sed -n '2,7p' "$0" >&2
  exit 2
}

case "${1:-}" in
  --cost)
    # `reset` is epoch seconds. Printed as both, because an agent that has hit
    # the wall needs the wait and a human reading over its shoulder needs the time.
    gh api rate_limit --jq '
      .resources
      | "graphql \(.graphql.remaining)/\(.graphql.limit), resets \(.graphql.reset)
core     \(.core.remaining)/\(.core.limit), resets \(.core.reset)"'
    now=$(date -u +%s)
    reset=$(gh api rate_limit --jq '.resources.graphql.reset')
    echo "graphql resets in $(( (reset - now) / 60 ))m $(( (reset - now) % 60 ))s, at $(date -u -d "@$reset" +%H:%M:%SZ)"
    ;;

  --map)
    cache="${2:-${TMPDIR:-/tmp}/kolonie-board-items.tsv}"
    # One page per hundred items, so this is still the whole board by design —
    # but through `board-read`, which asks for five fields per item rather than
    # every field of every item. Written with its own timestamp because a map
    # with no age is a map nobody re-reads.
    bash "$HERE/opencode-worker.sh" board-read \
      | jq -r '.items[] | select(.content.url != null)
               | "\(.content.url)\t\(.id)\t\(.status)"' > "$cache"
    printf '%s\t%s items\t%s\n' "$cache" "$(wc -l < "$cache")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >&2
    cat "$cache"
    ;;

  ''|-h|--help) usage ;;

  *)
    repo="$1"
    number="${2:-}"
    [ -n "$number" ] || usage
    # Repository *and* number together, because an issue number alone identifies
    # nothing across five repositories that each number from 1 — §4. The state
    # comes back with it so that a claim can check what it is claiming in the
    # same point it spends.
    #
    # ## Two filters, and they were missing until `#271` (2026-08-10)
    #
    # This side of the graph answers differently from the board's own `items`
    # connection, and both differences are silent — a wrong id that a card move
    # then accepts and reports success on.
    #
    # **`isArchived`.** Done cards are archived automatically. The board omits
    # them; an issue's `projectItems` returns them. Without the filter the first
    # thing this printed for a closed-and-reopened issue could be a card nobody
    # can see. `opencode-worker.sh` has carried this filter since `#269` and
    # says why at length; this file, which `AGENTS.md` §4 tells everyone to use,
    # did not.
    #
    # **The project by id, not by number.** Project numbers are per owner, so
    # any personal project 1 is also `number: 1`. Nothing stops an issue being
    # on two boards, and one of them is not this board.
    #
    # ## And a filtered-to-nothing answer says so
    #
    # An empty answer has four meanings — no such issue, on no project, on this
    # board but archived, on somebody else's project — and a reader acting on the
    # wrong one goes looking for a bug that is not there. So the response is read
    # twice, locally and for free, and the second reading goes to stderr where it
    # cannot be mistaken for an id.
    #
    # **A missing issue exits 1**, because it is the one of the four that means
    # the caller asked the wrong question. The other three are true answers about
    # an issue that exists, and a caller checking for empty output already
    # handles them.
    #
    # Measured 2026-08-10: GitHub answers a bad number with a GraphQL *error*
    # and `gh` exits non-zero, so `|| exit 1` below is what actually catches it
    # today and the null check is the belt. It is kept because a GraphQL
    # response may carry `data` and `errors` together, and the two `jq` calls
    # would then fail on a null with a message about `jq` rather than about the
    # issue.
    raw=$(gh api graphql -f query='query($repo:String!,$n:Int!){
      repository(owner:"'"$ORG"'",name:$repo){issue(number:$n){
        state projectItems(first:20){nodes{id isArchived project{id}
          fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}}}}}}' \
      -f repo="$repo" -F n="$number") || exit 1

    if [ "$(jq -r '.data.repository.issue // "null"' <<<"$raw")" = null ]; then
      echo "$ORG/$repo#$number does not exist, so it is on no board. Check the repository: five of them number from 1." >&2
      exit 1
    fi

    jq -r --arg project "$PROJECT_ID" '.data.repository.issue as $i
          | $i.projectItems.nodes[]
          | select(.isArchived == false and .project.id == $project)
          | "\(.id)\t\(.fieldValueByName.name // "no status")\tissue is \($i.state)"' <<<"$raw"

    jq -r --arg project "$PROJECT_ID" --arg ref "$ORG/$repo#$number" '
          [ .data.repository.issue.projectItems.nodes[] ] as $all
          | [ $all[] | select(.isArchived == false and .project.id == $project) ] as $live
          | if ($live | length) > 0 then empty
            elif ([ $all[] | select(.project.id == $project) ] | length) > 0
              then "\($ref) is on this board but its card is archived, which is what Done does. Nothing to move."
            elif ($all | length) > 0
              then "\($ref) is on \($all | length) project\(if ($all|length) == 1 then "" else "s" end), and none of them is this board."
            else "\($ref) is on no project at all. `gh project item-add` is what puts it on one."
            end' <<<"$raw" >&2
    ;;
esac

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
# id that a card move needs, and it is the most expensive call in the loop:
# **304 GraphQL points against a 205-item board** (measured 2026-08-08), because
# the charge is per item *requested*, in pages of a hundred. An agent that reads
# the whole board once per issue it wants to place spends the organisation's
# hourly budget on six issues.
#
# The single lookup below costs **1 point** and is also the more correct call —
# it answers from the board now, rather than from a snapshot taken minutes ago
# that another agent may already have invalidated.
#
# ## What actually costs what, measured 2026-08-08 on a 205-item board
#
#   gh project item-list --limit 1000       304 points
#   one issue by repository and number         1 point
#   one card move                              1 point
#   the same lookup over REST                  0 GraphQL points
#
# **The read is the whole bill.** `kolonie-docs#227` recorded one board read plus
# three card moves at 206 points and it is worth reading that number the right
# way round: 203 of it was the read and the three moves were a point each. There
# is nothing to save on moving cards, and everything to save on how you found
# the cards to move.
#
# ## Which mode to use
#
# **The single lookup, almost always.** `--map` exists for the one case it wins:
# you have a batch of issues to place and need more than about three hundred
# lookups' worth of ids, at which point one 304-point read beats the lookups.
# Below that it costs more, and it goes stale from the moment it is written.
#
# ## No credential is stored by any of this
#
# Both modes use whatever `gh` is already authenticated as. Nothing here writes a
# token, reads one out of a file, or takes one as an argument — §4's refusal on
# `kolonie-docs#118` stands, and a cache file that held a credential would be a
# worse trade than the points it saves.

set -euo pipefail

PROJECT_NUMBER=1
ORG=Kolonie-AI

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
    # One page per hundred items, so this is the expensive call by design. Written
    # with its own timestamp because a map with no age is a map nobody re-reads.
    gh project item-list "$PROJECT_NUMBER" --owner "$ORG" --limit 1000 --format json \
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
    gh api graphql -f query='query($repo:String!,$n:Int!){
      repository(owner:"'"$ORG"'",name:$repo){issue(number:$n){
        state projectItems(first:5){nodes{id
          fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}}}}}}' \
      -f repo="$repo" -F n="$number" \
      --jq '.data.repository.issue as $i
            | $i.projectItems.nodes[]
            | "\(.id)\t\(.fieldValueByName.name // "no status")\tissue is \($i.state)"'
    ;;
esac

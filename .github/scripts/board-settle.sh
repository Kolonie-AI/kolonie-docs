#!/bin/bash
# Move anything closed and outside Done into Done. `kolonie-docs#482`.
#
# Usage:
#   board-settle.sh              # move them
#   board-settle.sh --dry-run    # say what it would move, touch nothing
#
# ## Why this exists at all
#
# GitHub's built-in *Item closed* workflow is enabled on this board and **fires
# unreliably**. Measured 2026-08-22: `kolonie-platform#1587` and `#1594` were
# closed by the same pull request in the same second, and one card moved to Done
# while the other sat in In Review. Three of four cards closed that morning were
# still in a working column hours later.
#
# That is not a setting anybody here can correct. It is a dependency to remove.
#
# ## Why an agent no longer does it
#
# `agents/orchestration.md` tells an agent to arm auto-merge and take the next
# issue, which is worth roughly twice the throughput and means **the issue closes
# after the agent has moved on**. The rule that used to cover this — *move the
# item to the column that is now true* — cannot cover a column that becomes
# untrue ten minutes later. The faster the loop runs, the more cards strand.
#
# ## Why this is not `board-self-check.sh`
#
# That file asks the same question in 5c and must go on only asking it. A monitor
# that repairs what it measures reports clean for ever, and then nobody can tell
# a board that is healthy from one being held up by a cron job. The two have to
# be able to disagree: this moves cards, that one says whether cards are moving.
#
# `#132` is the other half of the argument — the daily cadence there exists to
# protect the GraphQL budget, and it does not reach this file. One `board-read`
# is 2 points and one move is 1, so six runs an hour costs under 500 points a
# day against a ceiling of 5,000 an hour.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_ID=${PROJECT_ID:-PVT_kwDOEmwuYs4BebbB}
STATUS_FIELD=${STATUS_FIELD:-PVTSSF_lADOEmwuYs4BebbBzhY1uQw}
STATUS_DONE=${STATUS_DONE:-d37dbc2a}

# **Ten minutes, and the hour it replaced was reasoning about a case that no
# longer exists.** The window was set to protect the agent that closed an issue
# by hand and is three tool calls from moving the card itself. But the reason
# this job exists at all is that `agents/orchestration.md` now tells an agent to
# arm auto-merge and go — so on the common path the agent is *gone* before the
# issue closes, and an hour of protection buys a card that reads wrong to
# everybody for an hour.
#
# Measured 2026-08-22: `kolonie-platform#1573` closed at 11:27 when `#1596`
# merged, and was still In Review at 11:55 — correctly skipped by this job three
# times, at six, twenty-two and thirty-eight minutes old.
#
# Ten minutes is still far longer than any gap between one agent's tool calls,
# which is the only case left to protect.
#
# `board-self-check.sh` keeps its six hours and is right to: it is deciding
# whether to *report a defect*, and a card that settles in twenty minutes is not
# one. This is deciding whether to tidy up, which is cheap and reversible.
SETTLE_MINUTES=${SETTLE_MINUTES:-10}

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

board="$(mktemp)"
trap 'rm -f "$board"' EXIT

if ! bash "$HERE/opencode-worker.sh" board-read > "$board" 2>/dev/null; then
  echo "::error::the board could not be read; nothing was moved"
  exit 1
fi

# **A listing carrying no issue state is a query that changed, not a clean
# board.** Without this the script would report *nothing to move* for ever, which
# is the exact failure `board-self-check.sh:397` is written against — and here it
# would be worse, because a repair that silently stops looks identical to a board
# that stopped needing it.
stated=$(jq -r '[.items[] | select(.content.state != null)] | length' "$board")
if [ "${stated:-0}" -eq 0 ]; then
  echo "::error::the board listing carries no issue state, so nothing could be judged; board-read is answering without state and closedAt"
  exit 1
fi

cutoff=$(date -u -d "$SETTLE_MINUTES minutes ago" +%Y-%m-%dT%H:%M:%SZ)

# Closed, in a column, and that column is not Done. An item with no Status at all
# is left alone: it has missed a different workflow, and 5d in
# `board-self-check.sh` names it with a destination that accounts for its state.
mapfile -t stranded < <(jq -r --arg c "$cutoff" '
  .items[]
  | select(.content.state == "CLOSED")
  | select((.status // "") != "" and .status != "Done")
  | select(.content.closedAt != null and .content.closedAt < $c)
  | "\(.id)\t\(.content.repository)#\(.content.number)\t\(.status)"
  ' "$board")

if [ "${#stranded[@]}" -eq 0 ]; then
  echo "nothing stranded — every closed item is in Done"
  exit 0
fi

moved=0
failed=0
for line in "${stranded[@]}"; do
  IFS=$'\t' read -r id ref column <<< "$line"

  if $DRY_RUN; then
    echo "would move $ref out of $column"
    continue
  fi

  if gh api graphql -f query='
      mutation($project:ID!,$item:ID!,$field:ID!,$option:String!){
        updateProjectV2ItemFieldValue(input:{
          projectId:$project, itemId:$item, fieldId:$field,
          value:{singleSelectOptionId:$option}
        }){ projectV2Item { id } }
      }' \
      -f project="$PROJECT_ID" -f item="$id" \
      -f field="$STATUS_FIELD" -f option="$STATUS_DONE" >/dev/null 2>&1; then
    echo "moved $ref to Done, out of $column"
    moved=$((moved + 1))
  else
    # One card that will not move is not a reason to leave the rest where they
    # are, and it is not silent either: the next run tries again, and this line
    # is what says it has been trying.
    echo "::warning::could not move $ref out of $column"
    failed=$((failed + 1))
  fi
done

$DRY_RUN && exit 0

echo "$moved moved, $failed refused"
[ "$failed" -gt 0 ] && exit 1
exit 0

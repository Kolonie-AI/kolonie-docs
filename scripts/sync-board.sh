#!/usr/bin/env bash
#
# Reconcile the project board with the issues.
#
# Adds every issue that is missing from the board, and sets each item's Status
# from its labels. Idempotent — run it as often as you like.
#
# Why this exists: the organisation is on the GitHub Free plan, which allows
# exactly two enabled project workflows. Two are not enough to auto-add from
# three repositories and keep statuses current, so the remainder is reconciled
# here instead of being left to whoever remembers.
#
# The board is a view; the labels are the truth. This script only ever writes to
# the board, never to an issue. If it disagrees with a label, the label wins and
# the board is corrected.
#
# Requires: gh, jq, and a token with `project` scope in addition to `repo`.
# Without `project` scope everything else in AGENTS.md still works — the board
# simply goes stale, which costs a view, not any information.
#
# Usage:  scripts/sync-board.sh [--dry-run]

set -euo pipefail

OWNER="Kolonie-AI"
PROJECT_NUMBER=1
REPOS=(kolonie-docs kolonie-infra kolonie-platform)
DRY_RUN="${1:-}"

command -v gh >/dev/null || { echo "gh not found" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

# --- Discover the project, its Status field and the option ids ---------------
# Resolved at runtime rather than hard-coded, so renaming a column or recreating
# the board does not silently break this script.

PROJECT_JSON=$(gh api graphql -f query='
  query($owner: String!, $number: Int!) {
    organization(login: $owner) {
      projectV2(number: $number) {
        id
        field(name: "Status") {
          ... on ProjectV2SingleSelectField { id options { id name } }
        }
        items(first: 100) {
          nodes {
            id
            content { ... on Issue { number state repository { name } } }
          }
        }
      }
    }
  }' -f owner="$OWNER" -F number="$PROJECT_NUMBER")

PROJECT_ID=$(jq -r '.data.organization.projectV2.id' <<<"$PROJECT_JSON")
STATUS_FIELD=$(jq -r '.data.organization.projectV2.field.id' <<<"$PROJECT_JSON")

[ "$PROJECT_ID" != "null" ] || { echo "Project $OWNER/$PROJECT_NUMBER not found — does the token carry 'project' scope?" >&2; exit 1; }

option_id() {
  jq -r --arg n "$1" '.data.organization.projectV2.field.options[] | select(.name==$n) | .id' <<<"$PROJECT_JSON"
}

# Existing board items, keyed "repo#number" -> item id
declare -A ITEM_ID ITEM_KNOWN
while IFS=$'\t' read -r key id; do
  [ -n "$key" ] || continue
  ITEM_ID["$key"]="$id"
  ITEM_KNOWN["$key"]=1
done < <(jq -r '.data.organization.projectV2.items.nodes[]
  | select(.content.number != null)
  | "\(.content.repository.name)#\(.content.number)\t\(.id)"' <<<"$PROJECT_JSON")

# --- The mapping from labels to a column -------------------------------------
# Mirrors AGENTS.md §5. A closed issue is Done regardless of its labels: closing
# is the act that ends an issue, and a stale label must not outrank it.

desired_status() {
  local state="$1" labels="$2"
  [ "$state" = "CLOSED" ] && { echo "Done"; return; }
  case ",$labels," in
    *,blocked,*)           echo "Blocked" ;;
    *,in-review,*)         echo "In Review" ;;
    *,in-progress,*)       echo "In Progress" ;;
    *,ready-to-build,*)    echo "Ready" ;;
    *,question,*|*,idea,*) echo "Inbox" ;;
    *)                     echo "Backlog" ;;
  esac
}

added=0 moved=0 unchanged=0

for repo in "${REPOS[@]}"; do
  while IFS=$'\t' read -r number url state labels; do
    [ -n "$number" ] || continue
    key="$repo#$number"
    want=$(desired_status "$state" "$labels")

    if [ -z "${ITEM_KNOWN[$key]:-}" ]; then
      if [ "$DRY_RUN" = "--dry-run" ]; then
        echo "would add    $key -> $want"
        added=$((added + 1)); continue
      fi
      item=$(gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" --url "$url" --format json --jq '.id')
      ITEM_ID["$key"]="$item"
      echo "added        $key -> $want"
      added=$((added + 1))
    fi

    have=$(gh api graphql -f query='
      query($id: ID!) { node(id: $id) { ... on ProjectV2Item {
        fieldValueByName(name: "Status") {
          ... on ProjectV2ItemFieldSingleSelectValue { name } } } } }' \
      -f id="${ITEM_ID[$key]}" --jq '.data.node.fieldValueByName.name // ""')

    if [ "$have" = "$want" ]; then
      unchanged=$((unchanged + 1)); continue
    fi

    if [ "$DRY_RUN" = "--dry-run" ]; then
      echo "would move   $key  ${have:-unset} -> $want"
    else
      gh project item-edit --id "${ITEM_ID[$key]}" --project-id "$PROJECT_ID" \
        --field-id "$STATUS_FIELD" --single-select-option-id "$(option_id "$want")" >/dev/null
      echo "moved        $key  ${have:-unset} -> $want"
    fi
    moved=$((moved + 1))
  done < <(gh issue list -R "$OWNER/$repo" --state all --limit 200 \
             --json number,url,state,labels \
             --jq '.[] | [.number, .url, (.state|ascii_upcase), ([.labels[].name] | join(","))] | @tsv')
done

echo
echo "added $added, moved $moved, already correct $unchanged"

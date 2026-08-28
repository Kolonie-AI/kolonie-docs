#!/bin/bash
# Does board-triage.yml still write issues as the personal token? (`#536`)
#
# Usage: bash .github/tests/board-triage-workflow.test.sh
#
# Measured 2026-08-28: four consecutive `Triage the board` runs failed
# `Label, link and move` with `could not be written` on
# `kolonie-concept-lab#10`, because that step used `WORKER_REPO_TOKEN` and
# that token's selected-repository set predates the repository. The mint
# below is the `kolonie-triage` App, pinned to the Node 24 release, and
# `Label, link and move` spends that mint rather than the personal token.
#
# A grep is what keeps the second half from being forgotten: a fallback
# of `WORKER_REPO_TOKEN || github.token` on the issue-write step would
# restore the outage without anybody editing a script.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/board-triage.yml"
SCRIPT="$ROOT/.github/scripts/board-triage.sh"

FAILURES=()
pass=0

contains() {
  local what=$1 needle=$2 hay=$3
  case "$hay" in
    *"$needle"*) echo "  ok   $what"; pass=$((pass + 1)) ;;
    *) echo "  FAIL $what"; echo "         wanted to find: $needle"; FAILURES+=("$what") ;;
  esac
}

absent() {
  local what=$1 needle=$2 hay=$3
  case "$hay" in
    *"$needle"*) echo "  FAIL $what"; echo "         did not want to find: $needle"; FAILURES+=("$what") ;;
    *) echo "  ok   $what"; pass=$((pass + 1)) ;;
  esac
}

workflow=$(cat "$WORKFLOW")
script=$(cat "$SCRIPT")

echo "the issue mint is the triage App, pinned, Node 24"
TOKEN_PIN=bcd2ba49218906704ab6c1aa796996da409d3eb1
contains "the mint action is pinned to the Node 24 release" \
  "actions/create-github-app-token@$TOKEN_PIN" "$workflow"
contains "the mint reads TRIAGE_APP_ID" "secrets.TRIAGE_APP_ID" "$workflow"
contains "the mint reads TRIAGE_APP_PRIVATE_KEY" "secrets.TRIAGE_APP_PRIVATE_KEY" "$workflow"
contains "the mint is named Become the triage app" "Become the triage app" "$workflow"

# `v2` on this mint would be the Node 20 pin `#533` retired.
NODE20_ISSUE_MINT_RX='id: issue_token[[:space:]]+uses:[[:space:]]+actions/create-github-app-token@(v2|fee1f7d63c2ff003460e3d139729b119787bc349)'
if printf '%s\n' "$workflow" | tr '\n' ' ' | grep -E "$NODE20_ISSUE_MINT_RX" >/dev/null; then
  echo "  FAIL the issue mint is still a Node 20 pin"
  FAILURES+=("the issue mint is still a Node 20 pin")
else
  echo "  ok   the issue mint is not a Node 20 pin"
  pass=$((pass + 1))
fi

echo
echo "the board mint is pinned to the same Node 24 release (#537)"
board_block=$(awk '
  $0 ~ /^[[:space:]]*- name: Become the board app$/ { in_step=1 }
  in_step && $0 ~ /^[[:space:]]*- name:/ && $0 !~ /Become the board app/ { exit }
  in_step { print }
' "$WORKFLOW")
contains "the board mint action is pinned to the Node 24 release" \
  "actions/create-github-app-token@$TOKEN_PIN" "$board_block"
contains "the board mint still reads BOARD_APP_ID" "secrets.BOARD_APP_ID" "$board_block"
contains "the board mint still reads BOARD_APP_PRIVATE_KEY" \
  "secrets.BOARD_APP_PRIVATE_KEY" "$board_block"
contains "the board mint still carries the board_token id" "id: board_token" "$board_block"
contains "the board mint still names the owner" \
  "owner: \${{ github.repository_owner }}" "$board_block"

# `v2` on this mint would be the Node 20 pin `#533` retired; `#537` is that pin.
NODE20_BOARD_MINT_RX='id: board_token[[:space:]]+uses:[[:space:]]+actions/create-github-app-token@(v2|fee1f7d63c2ff003460e3d139729b119787bc349)'
if printf '%s\n' "$workflow" | tr '\n' ' ' | grep -E "$NODE20_BOARD_MINT_RX" >/dev/null; then
  echo "  FAIL the board mint is still a Node 20 pin"
  FAILURES+=("the board mint is still a Node 20 pin")
else
  echo "  ok   the board mint is not a Node 20 pin"
  pass=$((pass + 1))
fi
if printf 'id: board_token\n        uses: actions/create-github-app-token@v2\n' \
  | tr '\n' ' ' | grep -E "$NODE20_BOARD_MINT_RX" >/dev/null; then
  echo "  ok   the board Node 20 guard matches an @v2 board mint"
  pass=$((pass + 1))
else
  echo "  FAIL the board Node 20 guard does not match an @v2 board mint"
  FAILURES+=("the board Node 20 guard does not match an @v2 board mint")
fi

echo
echo "Label, link and move spends the issue mint, not the personal token"
# The apply step is the one that writes labels, comments and dependency
# links. A fallback to `WORKER_REPO_TOKEN` there is the outage `#536`
# measured. Membership may still read that secret, but only as
# `PROVENANCE_TOKEN`.
apply_block=$(awk '
  $0 ~ /^[[:space:]]*- name: Label, link and move$/ { in_step=1 }
  in_step && $0 ~ /^[[:space:]]*- name:/ && $0 !~ /Label, link and move/ { exit }
  in_step { print }
' "$WORKFLOW")
contains "apply GH_TOKEN is the issue mint" \
  "GH_TOKEN: \${{ steps.issue_token.outputs.token }}" "$apply_block"
contains "apply BOARD_TOKEN is the board mint" \
  "BOARD_TOKEN: \${{ steps.board_token.outputs.token }}" "$apply_block"
contains "apply PROVENANCE_TOKEN is the personal token" \
  "PROVENANCE_TOKEN: \${{ secrets.WORKER_REPO_TOKEN }}" "$apply_block"
absent "apply GH_TOKEN does not fall back to WORKER_REPO_TOKEN" \
  "WORKER_REPO_TOKEN || github.token" "$apply_block"
absent "apply GH_TOKEN does not read WORKER_REPO_TOKEN" \
  "GH_TOKEN: \${{ secrets.WORKER_REPO_TOKEN" "$apply_block"

echo
echo "the sweep comments with the same issue mint"
sweep_block=$(awk '
  $0 ~ /^[[:space:]]*- name: Move the cards the facts decide$/ { in_step=1 }
  in_step && $0 ~ /^[[:space:]]*- name:/ && $0 !~ /Move the cards the facts decide/ { exit }
  in_step { print }
' "$WORKFLOW")
contains "sweep GH_TOKEN is the issue mint" \
  "GH_TOKEN: \${{ steps.issue_token.outputs.token }}" "$sweep_block"
absent "sweep GH_TOKEN does not fall back to WORKER_REPO_TOKEN" \
  "WORKER_REPO_TOKEN || github.token" "$sweep_block"

echo
echo "the script treats an unreadable membership as unknown"
contains "provenance answers unknown" 'echo "unknown"' "$script"
contains "provenance asks memberships/" 'memberships/$login' "$script"
absent "provenance no longer asks members/" 'members/$login' "$script"

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "all good ($pass assertions)"
  exit 0
fi
echo "${#FAILURES[@]} failed:"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

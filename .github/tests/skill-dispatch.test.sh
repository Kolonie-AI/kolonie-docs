#!/bin/bash
# Does a dispatch that reached nobody report success? (`kolonie-docs#500`)
#
# Usage: bash .github/tests/skill-dispatch.test.sh
#
# Measured 2026-08-25: a push of the shared body dispatched none of the seven
# and the run was green — run 32908682526, event `push`, conclusion success, 7s.
# `#359` is closed on the promise that a withdrawal of Colony-facing skill text
# reaches the seven within minutes, and a closed promise that silently does not
# hold is worse than an open one.
#
# So this asserts the **endings**, not the wording: which exit code each state
# produces, and that every runtime is attempted before any of them is decided.
# Stubbed `gh`, for `opencode-red.test.sh`'s reason — it is the only way to
# exercise a dispatch that fails without dispatching anything, and the stub logs
# every invocation so the count is exhaustive rather than a reading of the
# script.
#
# No token value is used anywhere here: `SKILL_PUBLISHER_TOKEN` is set to a
# literal placeholder, because what the script branches on is whether it is
# empty.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/.github/scripts/skill-dispatch.sh"
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
export GH_LOG="$WORK/gh.log"
export GITHUB_STEP_SUMMARY="$WORK/summary"

# Fails for whichever repositories `GH_FAIL` names, and logs every call either
# way. `GH_FAIL=all` is the reproduction: a token that reads fine and a dispatch
# that lands nowhere.
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$GH_LOG"
repo=""
while [ "$#" -gt 0 ]; do
  case "$1" in --repo) repo=${2#Kolonie-AI/}; shift 2 ;; *) shift ;; esac
done
case "${GH_FAIL:-}" in
  all) exit 1 ;;
  "") exit 0 ;;
  *) case ",${GH_FAIL}," in *",$repo,"*) exit 1 ;; esac ;;
esac
exit 0
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

check() {
  local what=$1 want=$2 got=$3
  if [ "$want" = "$got" ]; then
    echo "  ok   $what"
  else
    echo "  FAIL $what"
    echo "         expected: $want"
    echo "         actual:   $got"
    FAILURES+=("$what")
  fi
}

contains() {
  local what=$1 needle=$2 hay=$3
  case "$hay" in
    *"$needle"*) echo "  ok   $what" ;;
    *) echo "  FAIL $what"; echo "         wanted to find: $needle"; FAILURES+=("$what") ;;
  esac
}

run() {
  : > "$GH_LOG"
  : > "$GITHUB_STEP_SUMMARY"
  set +e
  OUT=$(bash "$SCRIPT" 2>&1)
  RC=$?
  set -e
  DISPATCHES=$(grep -c 'workflow run skill.yml' "$GH_LOG" || true)
}

echo "an unreadable token is 0 of 7, and that is red"
# The reproduction. Measured 2026-08-25, run 32908682526: the secret was not
# readable here, nothing was asked, the annotation was a warning, and the
# conclusion was success. `#359` is closed; that ending is a broken fast path.
unset SKILL_PUBLISHER_TOKEN
run
check "no token exits non-zero" 1 "$RC"
check "and asks nobody, rather than trying without a credential" 0 "$DISPATCHES"
contains "and says they are on their cron" "on their cron" "$OUT$(cat "$GITHUB_STEP_SUMMARY")"

echo
echo "a wired-up path that reached nobody is red"
# The reproduction. This is the ending that was conclusion `success` on
# 2026-08-25 while Colony-facing text stayed stale in seven repositories.
export SKILL_PUBLISHER_TOKEN=not-a-token
GH_FAIL=all run
check "0 of 7 exits non-zero" 1 "$RC"
check "and every runtime was attempted before that was decided" 7 "$DISPATCHES"
contains "and the run says how many were reached" "0 of 7" "$OUT$(cat "$GITHUB_STEP_SUMMARY")"

echo
echo "six of seven is not success either"
# The case that reads as success from a distance: the seventh keeps serving a
# withdrawn tool until its own cron.
GH_FAIL=kolonie-codex run
check "a partial dispatch exits non-zero" 1 "$RC"
check "and the other six were still asked" 7 "$DISPATCHES"
contains "and the one that failed is named" "kolonie-codex" "$OUT"

echo
echo "all seven asked is the good case"
GH_FAIL="" run
check "7 of 7 exits 0" 0 "$RC"
check "and each of the seven was asked exactly once" 7 "$DISPATCHES"

echo
echo "the seven are the seven"
for repo in kolonie-skill kolonie-claude kolonie-codex kolonie-hermes \
            kolonie-kilo kolonie-openclaw kolonie-antigravity; do
  contains "$repo was asked" "Kolonie-AI/$repo" "$(cat "$GH_LOG")"
done

echo
echo "it merges nothing, on any path"
# `#359`'s human gate: this asks seven workflows to run and never lands a change.
absent_log=$(cat "$GH_LOG")
case "$absent_log" in
  *"pr merge"*|*"--admin"*|*"--auto"*)
    echo "  FAIL nothing is merged"; FAILURES+=("nothing is merged") ;;
  *) echo "  ok   nothing is merged" ;;
esac

echo
echo "the user-PAT path is gone (#531)"
# The remaining reader of `SKILL_SYNC_TOKEN` after `#501` retired it from the
# seven. A leftover reference would dispatch with the PAT that returned HTTP
# 403 on every attempt, measured 2026-08-28.
WORKFLOW="$ROOT/.github/workflows/skill-dispatch.yml"
for path in "$SCRIPT" "$WORKFLOW"; do
  if grep -q SKILL_SYNC_TOKEN "$path"; then
    echo "  FAIL $path still names SKILL_SYNC_TOKEN"
    FAILURES+=("$path still names SKILL_SYNC_TOKEN")
  else
    echo "  ok   $(basename "$path") does not name SKILL_SYNC_TOKEN"
  fi
done

echo
echo "the mint is the Publisher App, pinned, on the seven and not this repository"
# Same SHA `kolonie-claude` `skill.yml` already uses. Listing `kolonie-docs`
# as an installation repository would fail the mint: the App is not installed
# here. The secrets are readable here so this workflow can mint; the token is
# then spent on the seven.
PIN=fee1f7d63c2ff003460e3d139729b119787bc349
contains "the mint action is pinned to the SHA skill.yml already uses" \
  "actions/create-github-app-token@$PIN" "$(cat "$WORKFLOW")"
contains "the mint reads SKILL_PUBLISHER_APP_ID" \
  "secrets.SKILL_PUBLISHER_APP_ID" "$(cat "$WORKFLOW")"
contains "the mint reads SKILL_PUBLISHER_APP_PRIVATE_KEY" \
  "secrets.SKILL_PUBLISHER_APP_PRIVATE_KEY" "$(cat "$WORKFLOW")"
for repo in kolonie-skill kolonie-claude kolonie-codex kolonie-hermes \
            kolonie-kilo kolonie-openclaw kolonie-antigravity; do
  contains "mint lists $repo" "$repo" "$(cat "$WORKFLOW")"
done
# `repositories:` is a YAML block of the seven. Naming this repository there
# would ask the App for an installation it does not have.
if awk '
  $0 ~ /^[[:space:]]*repositories:[[:space:]]*\|[[:space:]]*$/ { in_block=1; next }
  in_block && $0 ~ /^[[:space:]]+[^[:space:]]/ { print; next }
  in_block { exit }
' "$WORKFLOW" | grep -q kolonie-docs; then
  echo "  FAIL mint lists kolonie-docs as an App installation repository"
  FAILURES+=("mint lists kolonie-docs")
else
  echo "  ok   mint does not list kolonie-docs as an App installation repository"
fi

echo
if [ ${#FAILURES[@]} -gt 0 ]; then
  echo "FAILED: ${#FAILURES[@]}"
  printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
echo "all cases pass"

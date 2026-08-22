#!/bin/bash
# Does the settle job move exactly what it should, and nothing else?
#
# Usage: bash .github/tests/board-settle.test.sh
#
# `kolonie-docs#482` asks for the writes to be proved the way
# `board-self-check.test.sh` proves the reads: against a **stubbed `gh`**, whose
# log is the whole assertion. A repair job is the one thing on this board that
# can quietly do damage, so *which cards it touched* has to be a fact rather
# than a reading of the source.
#
# The stub answers `board-read` from a fixture the case writes, records every
# invocation, and refuses nothing — so a mutation the script should not have made
# still appears in the log and still fails the case.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/board-settle.sh"
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >> "$GH_LOG"
if [ -f "$GH_FIXTURES/mutation_fails" ]; then exit 1; fi
echo '{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"x"}}}}'
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

# `board-read` goes through the worker, not through `gh` — so the worker is
# stubbed too, and the board fixture is written as the JSON the real one emits.
mkdir -p "$WORK/scripts"
cat > "$WORK/scripts/opencode-worker.sh" <<'STUB'
#!/bin/bash
[ -f "$GH_FIXTURES/read_fails" ] && exit 1
cat "$GH_FIXTURES/board"
STUB
chmod +x "$WORK/scripts/opencode-worker.sh"

# The script finds its sibling by its own path, so it is run from a directory
# holding both it and the stubbed worker.
cp "$SCRIPT" "$WORK/scripts/board-settle.sh"

OLD="2026-08-20T00:00:00Z"   # comfortably outside any settle window
NEW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"   # inside it

# One board item, as `board-read` emits it.
item() { # id ref-number status state closedAt
  printf '{"id":"%s","status":"%s","content":{"number":%s,"repository":"Kolonie-AI/kolonie-platform","state":"%s","closedAt":%s}}' \
    "$1" "$3" "$2" "$4" "$5"
}

board() { printf '{"items":[%s]}' "$(printf '%s' "$*")" > "$WORK/fx/board"; }

run() {
  rm -rf "$WORK/fx"; mkdir -p "$WORK/fx"
  GH_LOG="$WORK/log"; : > "$GH_LOG"
  export GH_LOG GH_FIXTURES="$WORK/fx"
}

check() { # description expected-substring haystack present|absent
  local desc="$1" needle="$2" hay="$3" mode="${4:-present}"
  if [ "$mode" = present ]; then
    case "$hay" in *"$needle"*) return 0 ;; esac
  else
    case "$hay" in *"$needle"*) ;; *) return 0 ;; esac
  fi
  FAILURES+=("$desc")
}

# ── A closed card outside Done, old enough, is moved.
run
board "$(item PVTI_a 1582 'In Review' CLOSED "\"$OLD\"")"
out=$(cd "$WORK/scripts" && bash board-settle.sh 2>&1)
check "moves a stranded closed card" "moved Kolonie-AI/kolonie-platform#1582 to Done" "$out"
check "and says which mutation it made" "updateProjectV2ItemFieldValue" "$(cat "$WORK/log")"

# ── An open card is never touched, whatever column it is in.
run
board "$(item PVTI_b 1600 'In Review' OPEN null),$(item PVTI_c 1601 'Done' OPEN null)"
out=$(cd "$WORK/scripts" && bash board-settle.sh 2>&1)
check "leaves open cards alone" "nothing stranded" "$out"
check "and writes nothing at all" "updateProjectV2ItemFieldValue" "$(cat "$WORK/log")" absent

# ── A card already in Done is not moved to Done again.
run
board "$(item PVTI_d 1587 'Done' CLOSED "\"$OLD\"")"
out=$(cd "$WORK/scripts" && bash board-settle.sh 2>&1)
check "does not rewrite a card already in Done" "updateProjectV2ItemFieldValue" "$(cat "$WORK/log")" absent

# ── **The settle window.** A card closed a moment ago belongs to the agent that
# closed it, which may be three tool calls from moving it itself.
run
board "$(item PVTI_e 1610 'In Review' CLOSED "\"$NEW\"")"
out=$(cd "$WORK/scripts" && bash board-settle.sh 2>&1)
check "waits out the settle window" "nothing stranded" "$out"
check "and touches nothing inside it" "updateProjectV2ItemFieldValue" "$(cat "$WORK/log")" absent

# ── A card with no Status at all is 5d's finding, not this job's.
run
board '{"id":"PVTI_f","status":"","content":{"number":1611,"repository":"Kolonie-AI/kolonie-platform","state":"CLOSED","closedAt":"'"$OLD"'"}}'
out=$(cd "$WORK/scripts" && bash board-settle.sh 2>&1)
check "leaves a status-less card to the self-check" "updateProjectV2ItemFieldValue" "$(cat "$WORK/log")" absent

# ── **A listing with no state at all is a broken query, not a clean board.**
# Without this the job reports *nothing stranded* for ever while doing nothing.
run
board '{"id":"PVTI_g","status":"In Review","content":{"number":1612,"repository":"Kolonie-AI/kolonie-platform","state":null,"closedAt":null}}'
out=$(cd "$WORK/scripts" && bash board-settle.sh 2>&1); rc=$?
check "refuses a listing carrying no issue state" "carries no issue state" "$out"
[ "$rc" -ne 0 ] || FAILURES+=("a stateless listing must exit non-zero")

# ── A board that cannot be read is an error, not an empty board.
run; : > "$WORK/fx/read_fails"; board ''
out=$(cd "$WORK/scripts" && bash board-settle.sh 2>&1); rc=$?
check "reports a board it could not read" "could not be read" "$out"
[ "$rc" -ne 0 ] || FAILURES+=("an unreadable board must exit non-zero")

# ── One refused move does not strand the rest, and is not silent.
run
board "$(item PVTI_h 1582 'In Review' CLOSED "\"$OLD\""),$(item PVTI_i 1583 'In Progress' CLOSED "\"$OLD\"")"
: > "$WORK/fx/mutation_fails"
out=$(cd "$WORK/scripts" && bash board-settle.sh 2>&1); rc=$?
check "warns about a card it could not move" "::warning::" "$out"
check "and still tries the next one" "#1583" "$out"
[ "$rc" -ne 0 ] || FAILURES+=("a refused move must exit non-zero")

# ── `--dry-run` says what it would do and writes nothing.
run
board "$(item PVTI_j 1582 'In Review' CLOSED "\"$OLD\"")"
out=$(cd "$WORK/scripts" && bash board-settle.sh --dry-run 2>&1)
check "dry run names the card" "would move Kolonie-AI/kolonie-platform#1582" "$out"
check "dry run writes nothing" "updateProjectV2ItemFieldValue" "$(cat "$WORK/log")" absent

if [ "${#FAILURES[@]}" -gt 0 ]; then
  printf 'FAILED: %s\n' "${FAILURES[@]}"
  exit 1
fi
echo "board-settle: all cases pass"

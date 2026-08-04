#!/bin/bash
# Does the Watch Agent report the right things, and does it keep its hands off
# everything else? `kolonie-docs#133`.
#
# Usage: bash .github/tests/watch-agent.test.sh
#
# Four properties `#133` asks to be proved rather than asserted:
#
#   - the silent-service check runs with **no model call and no API key**
#   - an issue is opened only when something is wrong, and **never a second one
#     while the first is open** — "the guard is code, not convention"
#   - the body **leads with the numbers** and puts the judgement last
#   - it holds no write beyond opening an issue — here, that it never closes one
#
# Both `curl` and `gh` are stubbed. A stub is the only way to exercise the branch
# where an issue already exists without filing one, and the only way to prove the
# no-key path without an outage to wait for. Every `gh` invocation is logged, so
# "it closed nothing" is a search over what it actually did rather than a reading
# of the source.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/watch-agent.sh"
JUDGE="$ROOT/.github/scripts/watch-judge.py"
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export GITHUB_REPOSITORY="Kolonie-AI/kolonie-docs"
export RUN_URL="https://example.invalid/run/1"
export VISIBILITY_POLL=0 VISIBILITY_ATTEMPTS=4
# Every window in the script is relative to this, so the fixtures do not have to
# know what day it is.
export WATCH_NOW=1785840000

mkdir -p "$WORK/bin"

# The Loki stub. It answers by *path*, from files the case sets up, and records
# every URL it was given — which is what lets a case assert that the query
# actually asked for the 7-day window rather than trusting the code to.
cat > "$WORK/bin/curl" <<'STUB'
#!/bin/bash
url=""; for a in "$@"; do case "$a" in http*) url="$a" ;; esac; done
echo "$* " >> "$CURL_LOG"
case "$url" in
  */loki/api/v1/labels)   printf '%s' "$(cat "$FIX/http_code" 2>/dev/null || echo 200)"; exit 0 ;;
  */label/service/values)
      # start= tells the two windows apart. The 7-day one is the wider, so it is
      # matched on the exact value the script computes from WATCH_NOW.
      if [[ "$* " == *"start=1785235200"* ]]; then cat "$FIX/services_7d" 2>/dev/null
      else cat "$FIX/services_24h" 2>/dev/null; fi ;;
  */query_range) if [[ "$* " == *"step=86400"* ]]; then cat "$FIX/history" 2>/dev/null
                 else cat "$FIX/hourly" 2>/dev/null; fi ;;
  */query)       cat "$FIX/slugs" 2>/dev/null ;;
  *)             cat "$FIX/openrouter" 2>/dev/null ;;
esac
exit 0
STUB
chmod +x "$WORK/bin/curl"

cat > "$WORK/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "issue list")
      n=$(cat "$FIX/.calls" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$FIX/.calls"
      d=$(cat "$FIX/existing_delay" 2>/dev/null || echo 0)
      [ "$n" -gt "$d" ] && cat "$FIX/existing" 2>/dev/null ;;
  *) : ;;
esac
exit 0
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

expect() {
  local name=$1 ok=$2 detail=${3:-}
  if [ "$ok" = yes ]; then printf '  ok   %s\n' "$name"
  else printf '  FAIL %s%s\n' "$name" "${detail:+: $detail}"; FAILURES+=("$name"); fi
}

setup() {
  export FIX="$WORK/fixtures" GH_LOG="$WORK/gh.log" CURL_LOG="$WORK/curl.log"
  rm -rf "$FIX"; mkdir -p "$FIX"; : > "$GH_LOG"; : > "$CURL_LOG"
  rm -rf "$WORK/out"; mkdir -p "$WORK/out"
  echo 200 > "$FIX/http_code"
  # A quiet, healthy day: three services, all of them logging, two warnings.
  printf '{"data":["api","website","verifier-runner"]}\n' > "$FIX/services_7d"
  printf '{"data":["api","website","verifier-runner"]}\n' > "$FIX/services_24h"
  printf '{"data":{"result":[{"metric":{"service":"api","level":"warn"},"values":[[1785836400,"2"]]}]}}\n' > "$FIX/hourly"
  printf '{"data":{"result":[]}}\n' > "$FIX/slugs"
  printf '{"data":{"result":[{"metric":{"service":"api","level":"warn"},"values":[[1785235200,"1"],[1785321600,"3"]]}]}}\n' > "$FIX/history"
  : > "$FIX/existing"
}

logged() { grep -q -- "$1" "$GH_LOG"; }

echo "a quiet day"

setup
out=$(bash "$SCRIPT" gather "$WORK/out"); rc=$?
expect "gather exits 0" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc"
expect "the numbers name the service and its count" \
  "$([[ "$out" == *'`api`'*'warn'* ]] && echo yes || echo no)" "$out"
expect "nothing is silent" "$([ ! -s "$WORK/out/silent.txt" ] && echo yes || echo no)" "$(cat "$WORK/out/silent.txt")"
expect "the 7-day history was actually asked for" \
  "$(grep -q 'step=86400' "$CURL_LOG" && echo yes || echo no)"

out=$(bash "$SCRIPT" decide "$WORK/out"); rc=$?
expect "decide exits 0 — nothing to file" "$([ $rc -eq 0 ] && echo yes || echo no)" "$out"

echo
echo "a silent service — the half that needs no model"

# The signal error-watching structurally misses: a dead runner throws no errors.
setup; printf '{"data":["api","website"]}\n' > "$FIX/services_24h"
bash "$SCRIPT" gather "$WORK/out" >/dev/null
expect "the service that stopped is named" \
  "$([ "$(cat "$WORK/out/silent.txt")" = "verifier-runner" ] && echo yes || echo no)" "$(cat "$WORK/out/silent.txt")"
out=$(bash "$SCRIPT" decide "$WORK/out"); rc=$?
expect "decide exits 1" "$([ $rc -eq 1 ] && echo yes || echo no)" "$out"

# `#133`: "the silent-service check runs with no model call and no API key".
# Proved by running the judge with the key unset and asserting that the decision
# is unchanged — not by reading the code and believing it.
(unset OPENROUTER_API_KEY_WATCH; python3 "$JUDGE" "$WORK/out" 2>"$WORK/judge.err")
expect "with no key the judge writes no judgement" \
  "$([ ! -e "$WORK/out/judgement.json" ] && echo yes || echo no)"
expect "and says why, in the log only" \
  "$(grep -q "no OPENROUTER_API_KEY_WATCH" "$WORK/judge.err" && echo yes || echo no)" "$(cat "$WORK/judge.err")"
(unset OPENROUTER_API_KEY_WATCH; python3 "$JUDGE" "$WORK/out" >/dev/null 2>&1); judge_rc=$?
expect "and exits 0, so the run stays green" \
  "$([ "$judge_rc" -eq 0 ] && echo yes || echo no)" "rc=$judge_rc"
out=$(bash "$SCRIPT" decide "$WORK/out"); rc=$?
expect "the silent service is still reported without a model" "$([ $rc -eq 1 ] && echo yes || echo no)" "$out"

echo
echo "the model's opinion is not a veto and not a trigger"

# A missing judgement must not file. Otherwise every provider outage becomes a
# morning issue, which is how a monitor gets muted.
setup; bash "$SCRIPT" gather "$WORK/out" >/dev/null
rm -f "$WORK/out/judgement.json"
out=$(bash "$SCRIPT" decide "$WORK/out"); rc=$?
expect "no judgement on a quiet day files nothing" "$([ $rc -eq 0 ] && echo yes || echo no)" "$out"

printf '{"abnormal":true,"judgement":"Errors tripled against the week."}' > "$WORK/out/judgement.json"
out=$(bash "$SCRIPT" decide "$WORK/out"); rc=$?
expect "an abnormal verdict files, with nothing silent" "$([ $rc -eq 1 ] && echo yes || echo no)" "$out"

printf '{"abnormal":false,"judgement":"Steady."}' > "$WORK/out/judgement.json"
out=$(bash "$SCRIPT" decide "$WORK/out"); rc=$?
expect "a normal verdict files nothing" "$([ $rc -eq 0 ] && echo yes || echo no)" "$out"

# Garbage from a provider is a missing opinion, not a finding.
printf 'not json at all' > "$WORK/out/judgement.json"
out=$(bash "$SCRIPT" decide "$WORK/out"); rc=$?
expect "an unparseable judgement files nothing" "$([ $rc -eq 0 ] && echo yes || echo no)" "$out"

echo
echo "reporting — one issue, reused, never closed"

setup; printf '{"data":["api","website"]}\n' > "$FIX/services_24h"
bash "$SCRIPT" gather "$WORK/out" >/dev/null
printf '{"abnormal":true,"judgement":"A runner has stopped speaking."}' > "$WORK/out/judgement.json"
printf 'A runner has stopped speaking.\n' > "$WORK/out/judgement.md"
bash "$SCRIPT" report "$WORK/out" >/dev/null
expect "with none open, one is created" "$(logged "issue create" && echo yes || echo no)" "$(cat "$GH_LOG")"
expect "and nothing was commented on" "$(logged "issue comment" && echo no || echo yes)"

# The guard `#133` asks to be code: a second run while the first issue is open
# comments instead of filing again.
setup; echo "417" > "$FIX/existing"; printf '{"data":["api","website"]}\n' > "$FIX/services_24h"
bash "$SCRIPT" gather "$WORK/out" >/dev/null
bash "$SCRIPT" report "$WORK/out" >/dev/null
expect "with one open, no second issue is filed" "$(logged "issue create" && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "it comments on the open one" "$(logged "issue comment 417" && echo yes || echo no)" "$(cat "$GH_LOG")"

# `#133`: "It reads. It does not act." — including on its own issue. This is
# where it deliberately differs from board-self-check.sh, so it is asserted
# rather than left to a reading.
expect "it never closes an issue" "$(logged "issue close" && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "it edits nothing" "$(logged "issue edit" && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "it touches no board item" \
  "$( { logged "project item-add" || logged "project item-edit"; } && echo no || echo yes)" "$(cat "$GH_LOG")"

echo
echo "the body leads with the evidence"

setup; printf '{"data":["api","website"]}\n' > "$FIX/services_24h"
bash "$SCRIPT" gather "$WORK/out" >/dev/null
printf 'The verifier runner has said nothing for a day.\n' > "$WORK/out/judgement.md"
bash "$SCRIPT" report "$WORK/out" >/dev/null
# The stub logs the whole invocation, and the body is many lines long — so the
# log is flattened rather than grepped for its first line, which would stop at
# the first newline and read as "the section is missing".
body=$(tr '\n' ' ' < "$GH_LOG")
numbers_at=$(awk '{print index($0, "Errors and warnings per service")}' <<<"$body")
judge_at=$(awk '{print index($0, "What the model makes of it")}' <<<"$body")
expect "the counts come before the judgement" \
  "$([ "$numbers_at" -gt 0 ] && [ "$judge_at" -gt "$numbers_at" ] && echo yes || echo no)" \
  "numbers@$numbers_at judgement@$judge_at"
expect "the silent service is in the body" \
  "$([[ "$body" == *"verifier-runner"* ]] && echo yes || echo no)"

# With no judgement the issue still gets filed and says the judgement is missing,
# rather than presenting an empty section as if the model had nothing to add.
setup; printf '{"data":["api","website"]}\n' > "$FIX/services_24h"
bash "$SCRIPT" gather "$WORK/out" >/dev/null
bash "$SCRIPT" report "$WORK/out" >/dev/null
body=$(tr '\n' ' ' < "$GH_LOG")
expect "a missing judgement is stated, not hidden" \
  "$([[ "$body" == *"No judgement was written"* ]] && echo yes || echo no)"

echo
echo "an unreachable store is a configuration gap, not a finding"

setup; echo 401 > "$FIX/http_code"
out=$(bash "$SCRIPT" gather "$WORK/out"); rc=$?
expect "gather exits 2" "$([ $rc -eq 2 ] && echo yes || echo no)" "rc=$rc"
expect "and says what answered" "$([[ "$out" == *"401"* ]] && echo yes || echo no)" "$out"
expect "and files nothing" "$(logged "issue create" && echo no || echo yes)" "$(cat "$GH_LOG")"

echo
echo "no threshold exists anywhere in this agent"

# `#133`: "no per-service threshold exists anywhere in the workflow". A grep is a
# blunt instrument and that is the point — it fails if somebody adds one later,
# which is exactly when this matters and exactly when nobody re-reads the issue.
found=$(grep -nE '^[^#]*(THRESHOLD|MAX_ERRORS|ERROR_LIMIT|WARN_LIMIT)' \
          "$SCRIPT" "$JUDGE" "$ROOT/.github/workflows/watch-agent.yml" 2>/dev/null)
expect "no threshold constant in the script, the judge or the workflow" \
  "$([ -z "$found" ] && echo yes || echo no)" "$found"

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "all checks passed"
  exit 0
fi
printf 'failed: %s\n' "${FAILURES[*]}"
exit 1

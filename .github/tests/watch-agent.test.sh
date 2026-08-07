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
echo "the model's opinion files nothing at all (#165)"

# **The change `#165` makes.** The model's verdict used to file, onto one eternal
# issue. It is still asked, still daily and still read — in the run summary. What
# took over the path from *an error appeared* to *an issue exists* is
# `kolonie-platform#407`, which sees the same errors every half hour.
setup; bash "$SCRIPT" gather "$WORK/out" >/dev/null
rm -f "$WORK/out/judgement.json"
out=$(bash "$SCRIPT" decide "$WORK/out"); rc=$?
expect "a normal day files nothing" "$([ $rc -eq 0 ] && echo yes || echo no)" "$out"

printf '{"abnormal":true,"judgement":"Errors tripled against the week."}' > "$WORK/out/judgement.json"
out=$(bash "$SCRIPT" decide "$WORK/out"); rc=$?
expect "an abnormal verdict no longer files" "$([ $rc -eq 0 ] && echo yes || echo no)" "$out"

# And it reaches nothing through `report` either, which is the assertion that
# would catch a later hand re-wiring the verdict into the filing path.
bash "$SCRIPT" report "$WORK/out" >/dev/null
expect "an abnormal verdict opens no issue" "$(logged "issue create" && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "and comments on none" "$(logged "issue comment" && echo no || echo yes)" "$(cat "$GH_LOG")"

printf '{"abnormal":false,"judgement":"Steady."}' > "$WORK/out/judgement.json"
out=$(bash "$SCRIPT" decide "$WORK/out"); rc=$?
expect "a normal verdict files nothing" "$([ $rc -eq 0 ] && echo yes || echo no)" "$out"

# Garbage from a provider is a missing opinion, not a finding — and now not a
# finding either way, which is the point.
printf 'not json at all' > "$WORK/out/judgement.json"
out=$(bash "$SCRIPT" decide "$WORK/out"); rc=$?
expect "an unparseable judgement files nothing" "$([ $rc -eq 0 ] && echo yes || echo no)" "$out"

# **A missing judgement must not turn a normal day into a reported one**, which
# was true before `#165` and has to stay true after it: a provider outage that
# filed a morning issue is how a monitor gets muted.
setup; bash "$SCRIPT" gather "$WORK/out" >/dev/null
rm -f "$WORK/out/judgement.json" "$WORK/out/judgement.md"
out=$(bash "$SCRIPT" decide "$WORK/out"); rc=$?
expect "no judgement on a quiet day is still a quiet day" "$([ $rc -eq 0 ] && echo yes || echo no)" "$out"
bash "$SCRIPT" report "$WORK/out" >/dev/null
expect "and nothing is filed" "$(logged "issue create" && echo no || echo yes)" "$(cat "$GH_LOG")"

echo
echo "reporting — one issue per silent service, never closed (#165)"

# **The rejection case `#165` asks for**: the one alarm this workflow keeps must
# still fire. A dead runner throws no errors, so nothing that reads errors — the
# detector in `kolonie-platform#407` included — can see this.
setup; printf '{"data":["api","website"]}\n' > "$FIX/services_24h"
bash "$SCRIPT" gather "$WORK/out" >/dev/null
bash "$SCRIPT" report "$WORK/out" >/dev/null
expect "a silent service still produces an issue" "$(logged "issue create" && echo yes || echo no)" "$(cat "$GH_LOG")"
expect "and nothing was commented on" "$(logged "issue comment" && echo no || echo yes)"

# **The title names the service.** The fixed string is what produced one issue
# forever, and a title carrying the thing that is wrong is what makes each
# finding closeable.
body=$(tr '\n' ' ' < "$GH_LOG")
expect "the title names the silent service" \
  "$([[ "$body" == *"verifier-runner\` has stopped logging"* ]] && echo yes || echo no)" "$body"

# The guard `#133` asks to be code, now keyed on the service rather than on a
# fixed string: a second run while that service's issue is open comments on it.
setup; echo "417" > "$FIX/existing"; printf '{"data":["api","website"]}\n' > "$FIX/services_24h"
bash "$SCRIPT" gather "$WORK/out" >/dev/null
bash "$SCRIPT" report "$WORK/out" >/dev/null
expect "with one open, no second issue is filed" "$(logged "issue create" && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "it comments on that service's own issue" "$(logged "issue comment 417" && echo yes || echo no)" "$(cat "$GH_LOG")"

# Two services silent at once are two pieces of work, not one thread.
setup; printf '{"data":["api"]}\n' > "$FIX/services_24h"
bash "$SCRIPT" gather "$WORK/out" >/dev/null
bash "$SCRIPT" report "$WORK/out" >/dev/null
expect "two silent services file two issues" \
  "$([ "$(grep -c 'issue create' "$GH_LOG")" -eq 2 ] && echo yes || echo no)" "$(cat "$GH_LOG")"

# And a good day files nothing at all — silence stays the healthy state.
setup
bash "$SCRIPT" gather "$WORK/out" >/dev/null
bash "$SCRIPT" report "$WORK/out" >/dev/null
expect "a normal day produces no issue" "$(logged "issue create" && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "and no comment" "$(logged "issue comment" && echo no || echo yes)" "$(cat "$GH_LOG")"

# `#133`: "It reads. It does not act." — including on its own issue. This is
# where it deliberately differs from board-self-check.sh, so it is asserted
# rather than left to a reading.
expect "it never closes an issue" "$(logged "issue close" && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "it edits nothing" "$(logged "issue edit" && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "it touches no board item" \
  "$( { logged "project item-add" || logged "project item-edit"; } && echo no || echo yes)" "$(cat "$GH_LOG")"

echo
echo "a service removed on purpose is quiet, not dead (#191)"

# `umami` was reverted on 2026-08-06 and filed as a `p1` the next morning. The
# rule was right and the fact was wrong, and no query could have told them apart:
# the difference is an intention. These cases prove the exemption is narrow —
# it removes exactly the named service and nothing standing beside it.
export WATCH_RETIRED_FILE="$WORK/retired.txt"
printf '# a comment, and a reason containing a #\nwebsite\t2026-08-06\tkolonie-website#43 — removed on purpose\n' \
  > "$WATCH_RETIRED_FILE"

setup; printf '{"data":["api"]}\n' > "$FIX/services_24h"   # website and verifier-runner both quiet
bash "$SCRIPT" gather "$WORK/out" >/dev/null
expect "the retired service is not reported" \
  "$(grep -qx 'website' "$WORK/out/silent.txt" && echo no || echo yes)" "$(cat "$WORK/out/silent.txt")"
expect "and it is recorded as retired rather than dropped" \
  "$(grep -qx 'website' "$WORK/out/retired.txt" && echo yes || echo no)" "$(cat "$WORK/out/retired.txt")"

# **The rejection case.** A retired entry must not quieten the service next to
# it: the run that excuses `website` still has to file for `verifier-runner`.
expect "a genuinely silent service beside it is still reported" \
  "$([ "$(cat "$WORK/out/silent.txt")" = "verifier-runner" ] && echo yes || echo no)" "$(cat "$WORK/out/silent.txt")"
out=$(bash "$SCRIPT" decide "$WORK/out"); rc=$?
expect "decide still exits 1" "$([ $rc -eq 1 ] && echo yes || echo no)" "$out"
bash "$SCRIPT" report "$WORK/out" >/dev/null
expect "one issue is filed, for the dead one" \
  "$([ "$(grep -c 'issue create' "$GH_LOG")" -eq 1 ] && echo yes || echo no)" "$(cat "$GH_LOG")"
expect "and it does not name the retired service" \
  "$(grep -q 'website` has stopped logging' "$GH_LOG" && echo no || echo yes)" "$(cat "$GH_LOG")"

# Suppressed is not hidden. The list must not become a place services disappear
# into, so the report says the quiet one was excused and where the reason lives.
expect "the report still says the retired service was quiet" \
  "$(grep -q 'not reported' "$WORK/out/numbers.md" && grep -q '`website`' "$WORK/out/numbers.md" && echo yes || echo no)" \
  "$(sed -n '/logged nothing in 24 hours/,+10p' "$WORK/out/numbers.md")"

# Retiring something that is still logging changes nothing, so a stale line
# cannot make a live service invisible.
setup; bash "$SCRIPT" gather "$WORK/out" >/dev/null
expect "a retired name that is still logging is not touched" \
  "$([ ! -s "$WORK/out/silent.txt" ] && [ ! -s "$WORK/out/retired.txt" ] && echo yes || echo no)" \
  "$(cat "$WORK/out/silent.txt" "$WORK/out/retired.txt")"

# An entry older than the window suppresses nothing and says so, in the log
# rather than on an issue — otherwise the file silts up with dead facts.
setup; printf 'website\t2020-01-01\tlong gone\n' > "$WATCH_RETIRED_FILE"
printf '{"data":["api"]}\n' > "$FIX/services_24h"
bash "$SCRIPT" gather "$WORK/out" 2>"$WORK/gather.err" >/dev/null
expect "a line older than the window is called out" \
  "$(grep -q 'can be deleted' "$WORK/gather.err" && echo yes || echo no)" "$(cat "$WORK/gather.err")"

# And with no list at all the check behaves exactly as it did before `#191`.
setup; export WATCH_RETIRED_FILE="$WORK/there-is-no-such-file"
printf '{"data":["api","website"]}\n' > "$FIX/services_24h"
bash "$SCRIPT" gather "$WORK/out" >/dev/null
expect "with no retired list the alarm is unchanged" \
  "$([ "$(cat "$WORK/out/silent.txt")" = "verifier-runner" ] && echo yes || echo no)" "$(cat "$WORK/out/silent.txt")"
unset WATCH_RETIRED_FILE

echo
echo "the narrative is the run's own output (#165)"

# Evidence first and judgement last, which was `#133`'s requirement about the
# issue body and is now the summary's — the order is about the reader, not about
# where it is printed.
setup; printf '{"data":["api","website"]}\n' > "$FIX/services_24h"
bash "$SCRIPT" gather "$WORK/out" >/dev/null
printf 'The verifier runner has said nothing for a day.\n' > "$WORK/out/judgement.md"
summary=$(bash "$SCRIPT" summary "$WORK/out" | tr '\n' ' ')
numbers_at=$(awk '{print index($0, "Errors and warnings per service")}' <<<"$summary")
judge_at=$(awk '{print index($0, "What the model makes of it")}' <<<"$summary")
expect "the counts come before the judgement" \
  "$([ "$numbers_at" -gt 0 ] && [ "$judge_at" -gt "$numbers_at" ] && echo yes || echo no)" \
  "numbers@$numbers_at judgement@$judge_at"
expect "the model's reading is in the summary" \
  "$([[ "$summary" == *"said nothing for a day"* ]] && echo yes || echo no)"

# The summary is printed and files nothing, which is the whole of the change.
bash "$SCRIPT" summary "$WORK/out" >/dev/null
expect "writing the summary opens nothing" "$(logged "issue create" && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "and comments on nothing" "$(logged "issue comment" && echo no || echo yes)" "$(cat "$GH_LOG")"

# With no judgement the summary says so, rather than presenting an empty section
# as if the model had nothing to add.
setup; bash "$SCRIPT" gather "$WORK/out" >/dev/null
summary=$(bash "$SCRIPT" summary "$WORK/out" | tr '\n' ' ')
expect "a missing judgement is stated, not hidden" \
  "$([[ "$summary" == *"No judgement was written"* ]] && echo yes || echo no)"

# It points at where an error now goes, so a reader of a quiet summary is not
# left thinking the Colony watches nothing between one 06:00 and the next.
expect "the summary names the detector that files errors" \
  "$([[ "$summary" == *"kolonie-platform#407"* ]] && echo yes || echo no)"

echo
echo "the history says how much history there is"

# The defect the first real run produced: Loki had one hour of data, the table
# held one bucket rendered as a bare `1`, and the model reported "1 per day for
# the past 7 days" — a weekly baseline invented from one hour. The model read
# what it was given correctly. The table was the lie.
setup
# 1785888000 is 2026-08-05T00:00:00Z — the shape Loki really returns: the
# *end* of the window, for data written on the 4th.
printf '{"data":{"result":[{"metric":{"service":"api","level":"error"},"values":[[1785888000,"1"]]}]}}\n' > "$FIX/history"
bash "$SCRIPT" gather "$WORK/out" >/dev/null
expect "one bucket is reported as one bucket" \
  "$(grep -q 'answered with \*\*1\*\* daily bucket' "$WORK/out/numbers.md" && echo yes || echo no)" \
  "$(grep -n 'bucket' "$WORK/out/numbers.md")"
expect "and the date is the day covered, not the window's end" \
  "$(grep -q '2026-08-04: 1' "$WORK/out/numbers.md" && ! grep -q '2026-08-05' "$WORK/out/numbers.md" && echo yes || echo no)" \
  "$(sed -n '/count per day/,+3p' "$WORK/out/numbers.md")"

# And a genuine week is reported as one, so the fix does not cost the case it
# was built for.
setup
printf '{"data":{"result":[{"metric":{"service":"api","level":"error"},"values":[[1785715200,"2"],[1785801600,"3"],[1785888000,"1"]]}]}}\n' > "$FIX/history"
bash "$SCRIPT" gather "$WORK/out" >/dev/null
expect "three buckets are reported as three" \
  "$(grep -q 'answered with \*\*3\*\* daily bucket' "$WORK/out/numbers.md" && echo yes || echo no)" \
  "$(grep -n 'bucket' "$WORK/out/numbers.md")"

echo
echo "the rehearsal takes the same path a real finding takes"

# `#133`'s definition of done needs a forced failure, and a rehearsal that does
# not go through the real path proves nothing about it. The first version
# appended the fabricated service *after* gather had rendered the report, so the
# issue it filed said "Services that logged nothing: None." while being filed
# because one had. Found against kolonie-docs#156 on 2026-08-04.
setup; WATCH_FORCE_SILENT=a-service-that-does-not-exist bash "$SCRIPT" gather "$WORK/out" >/dev/null
expect "the fabricated service reaches the decision" \
  "$(bash "$SCRIPT" decide "$WORK/out" >/dev/null; [ $? -eq 1 ] && echo yes || echo no)"
expect "and the report, not only the decision" \
  "$(grep -q 'a-service-that-does-not-exist' "$WORK/out/numbers.md" && echo yes || echo no)" \
  "$(sed -n '/logged nothing/,+3p' "$WORK/out/numbers.md")"

# And it is off by default, so an ordinary run cannot fabricate one.
setup; bash "$SCRIPT" gather "$WORK/out" >/dev/null
expect "nothing is fabricated without the switch" \
  "$([ ! -s "$WORK/out/silent.txt" ] && echo yes || echo no)" "$(cat "$WORK/out/silent.txt")"

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

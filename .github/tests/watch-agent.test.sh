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
# `#237`: issue bodies travel as `--body-file` now, so a stub that logged only
# the argument list could no longer see what was written. Log the file too, or
# every assertion about body text silently passes on an empty haystack.
for _i in $(seq 1 $#); do
  eval "_a=\${$_i}"
  if [ "$_a" = --body-file ]; then
    eval "_f=\${$((_i + 1))}"
    [ -f "$_f" ] && cat "$_f" >> "$GH_LOG"
  fi
done
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
setup; # `#237`: an existing finding is now recognised by the marker in its body,
# not by its title, so the stub returns what `gh issue list --json` returns.
jq -n '[{number:417, state:"OPEN", title:"whatever it was called",
          body:"prose\n\n<!-- watch-finding: silent-service:verifier-runner -->\n\nmore prose"}]' > $FIX/existing; printf '{"data":["api","website"]}\n' > "$FIX/services_24h"
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
echo "a service the pipeline silences is quiet, not dead (#284)"

# `promtail` was filed as a `p1` for logging nothing in 24 hours while running,
# healthy and tailing every file on the host: `kolonie-infra#81` drops `debug`
# and `info` from the log stack itself at ingestion, so its ordinary output never
# reaches Loki. Same silence as a dead runner, same as a retired one, and the
# difference is again not in the logs — here it is a rule in another
# repository's pipeline.
export WATCH_SILENT_FILE="$WORK/by-design.txt"
printf '# a comment\npromtail\tkolonie-infra/promtail/promtail.yml\tstage 6 drops debug and info\n' \
  > "$WATCH_SILENT_FILE"

setup; printf '{"data":["api","website","verifier-runner","promtail"]}\n' > "$FIX/services_7d"
printf '{"data":["api","website"]}\n' > "$FIX/services_24h"
bash "$SCRIPT" gather "$WORK/out" >/dev/null
expect "the silenced service is not reported" \
  "$(grep -qx 'promtail' "$WORK/out/silent.txt" && echo no || echo yes)" "$(cat "$WORK/out/silent.txt")"
expect "and it is recorded as by-design rather than dropped" \
  "$(grep -qx 'promtail' "$WORK/out/by-design.txt" && echo yes || echo no)" "$(cat "$WORK/out/by-design.txt")"

# The rejection case, and it is the one that matters: a pipeline rule about one
# service must not quieten the dead service standing beside it.
expect "a genuinely silent service beside it is still reported" \
  "$([ "$(cat "$WORK/out/silent.txt")" = "verifier-runner" ] && echo yes || echo no)" "$(cat "$WORK/out/silent.txt")"
bash "$SCRIPT" report "$WORK/out" >/dev/null
expect "no issue is filed about the silenced service" \
  "$(grep -q 'promtail` has stopped logging' "$GH_LOG" && echo no || echo yes)" "$(cat "$GH_LOG")"

# Suppressed is not hidden, exactly as for the retired list — a check that has
# stopped being able to speak about a service says so where it reports.
expect "the report still says the silenced service was quiet" \
  "$(grep -q '`promtail`' "$WORK/out/numbers.md" && grep -q 'pipeline drops' "$WORK/out/numbers.md" && echo yes || echo no)" \
  "$(sed -n '/logged nothing in 24 hours/,+14p' "$WORK/out/numbers.md")"

# A name in the list that is still logging changes nothing.
setup; printf '{"data":["api","website","verifier-runner","promtail"]}\n' > "$FIX/services_7d"
printf '{"data":["api","website","promtail"]}\n' > "$FIX/services_24h"
bash "$SCRIPT" gather "$WORK/out" >/dev/null
expect "a silenced name that is still logging is not touched" \
  "$([ "$(cat "$WORK/out/silent.txt")" = "verifier-runner" ] && [ ! -s "$WORK/out/by-design.txt" ] && echo yes || echo no)" \
  "$(cat "$WORK/out/silent.txt" "$WORK/out/by-design.txt")"

# And with no list at all the check behaves exactly as it did before `#284`.
setup; export WATCH_SILENT_FILE="$WORK/there-is-no-such-file"
printf '{"data":["api","website","verifier-runner","promtail"]}\n' > "$FIX/services_7d"
printf '{"data":["api","website"]}\n' > "$FIX/services_24h"
bash "$SCRIPT" gather "$WORK/out" >/dev/null
expect "with no by-design list the alarm is unchanged" \
  "$(grep -qx 'promtail' "$WORK/out/silent.txt" && echo yes || echo no)" "$(cat "$WORK/out/silent.txt")"
unset WATCH_SILENT_FILE

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
echo "errors, which are the larger half (#236)"

# `cmd_errors_changed` is exercised directly against fixture files rather than
# through a stubbed Loki: what is under test is the *arithmetic on shapes*, and
# routing it through a query stub would test the stub.
changed() {
  local dir=$1
  ( set +e
    # shellcheck disable=SC1090
    source <(sed -n '/^ERROR_SPIKE_FACTOR=/,/^}/p' "$SCRIPT" | sed -n '/^cmd_errors_changed/,/^}/p')
    ERROR_SPIKE_FACTOR=${ERROR_SPIKE_FACTOR:-5}
    ERROR_FLOOR=${ERROR_FLOOR:-10}
    cmd_errors_changed "$dir" && echo changed || echo unchanged )
}

mk() {
  D=$(mktemp -d)
  printf '%b' "$1" > "$D/errors-today.tsv"
  printf '%b' "$2" > "$D/errors-baseline.tsv"
  printf '%b' "${3:-}" > "$D/errors-new-strings.txt"
}

# 1 — none yesterday, many today.
mk 'api\t40\n' 'api\t0.00\n'
expect "a service with no recent errors and many today changes shape" \
  "$([ "$(changed "$D")" = changed ] && echo yes || echo no)"
expect "and the reason names the absence, not a threshold" \
  "$(grep -q 'none in the previous 7 days' "$D/errors-changed.tsv" && echo yes || echo no)" \
  "$(cat "$D/errors-changed.tsv")"

# 2 — several times its own normal.
mk 'traefik\t900\n' 'traefik\t31.57\n'
expect "a volume several times its own normal changes shape" \
  "$([ "$(changed "$D")" = changed ] && echo yes || echo no)"

# A service at its ordinary volume is not a finding, however large that is. This
# is the case a global threshold gets wrong, and traefik at 221/day is it.
mk 'traefik\t221\n' 'traefik\t210.00\n'
expect "a busy service at its ordinary volume files nothing" \
  "$([ "$(changed "$D")" = unchanged ] && echo yes || echo no)" "$(cat "$D/errors-changed.tsv")"

# The floor. 6 errors against a normal of 1 is 6x and is still nothing; without
# this the rules fire on noise and the channel is dead in a fortnight.
mk 'badge-runner\t6\n' 'badge-runner\t0.14\n'
expect "a tiny number is not a spike however large the ratio" \
  "$([ "$(changed "$D")" = unchanged ] && echo yes || echo no)" "$(cat "$D/errors-changed.tsv")"

# 3 — a string never seen in the window, even at ordinary volume.
mk 'postgres\t12\n' 'postgres\t14.00\n' 'postgres\tERROR: column sub.<n> does not exist\n'
expect "an error string never seen before changes shape" \
  "$([ "$(changed "$D")" = changed ] && echo yes || echo no)"

# A quiet day is a quiet day.
mk '' ''
expect "no errors at all is not a finding" \
  "$([ "$(changed "$D")" = unchanged ] && echo yes || echo no)"

# Per-service baselines: one service spiking must not drag another in.
mk 'traefik\t221\napi\t40\n' 'traefik\t210.00\napi\t0.00\n'
changed "$D" >/dev/null
expect "only the service that changed is named" \
  "$([ "$(wc -l < "$D/errors-changed.tsv")" -eq 1 ] && grep -q '^api' "$D/errors-changed.tsv" && echo yes || echo no)" \
  "$(cat "$D/errors-changed.tsv")"

# The normaliser is what makes grouping possible at all: measured by hand on
# 2026-08-09, postgres logged one failure 177 times and no two lines were
# byte-identical.
norm() { sed -n '/^normalise_line()/,/^}/p' "$SCRIPT" > "$WORK/norm.sh"; ( . "$WORK/norm.sh"; normalise_line ); }
a=$(printf '2026-08-09 03:11:02.994 UTC [1481] kolonie@kolonie/postgres.js ERROR:  column sub.decided_at does not exist at character 77\n' | norm)
b=$(printf '2026-08-09 07:44:51.001 UTC [2093] kolonie@kolonie/postgres.js ERROR:  column sub.decided_at does not exist at character 77\n' | norm)
expect "two instances of one failure normalise to one string" \
  "$([ "$a" = "$b" ] && echo yes || echo no)" "$a vs $b"

c=$(printf '2026-08-09 03:11:02.994 UTC [1481] kolonie@kolonie/postgres.js ERROR:  invalid input value for enum erasure_reason\n' | norm)
expect "and two different failures do not" \
  "$([ "$a" != "$c" ] && echo yes || echo no)"

echo
echo "an error count says how its level was arrived at, where that is not obvious"

# `#243`. traefik logged 227 error lines against a normal of 9.57 and was read as
# a fault of the proxy's. It was not: `kolonie-infra`'s promtail derives the
# level for a Common Log Format line from the HTTP status, so every one of those
# was something *behind* traefik answering 500 — 179 of them the same route
# `#241` reports the api failing on, in the same window. One event, two issues,
# and the triage pass guessed the relationship twice because the issue never said
# what its own number meant.
# The constant as well as the function: the list of services is half the
# behaviour, and sourcing the function alone made every assertion below pass on
# an unbound-variable error instead of on an answer.
note() {
  {
    sed -n '/^STATUS_DERIVED_LEVEL=/p' "$SCRIPT"
    sed -n '/^level_note_for()/,/^}/p' "$SCRIPT"
  } > "$WORK/note.sh"
  ( . "$WORK/note.sh"; level_note_for "$1" )
}

for service in traefik website pgadmin; do
  out=$(note "$service") || out=""
  expect "$service says its level came from the HTTP status" \
    "$([[ "$out" == *"derived from the HTTP status"* ]] && echo yes || echo no)" "$out"
done

expect "and it says which status, because 4xx is the client and 5xx is us" \
  "$([[ "$(note traefik)" == *"5xx"* && "$(note traefik)" == *"4xx"* ]] && echo yes || echo no)"

# **The point of the sentence, and the reason it is not just background.** A
# reader who takes this count as traefik's own fault looks in the wrong place;
# what it must say is to expect the finding for whoever actually failed.
expect "it sends the reader to the service that actually failed" \
  "$([[ "$(note traefik)" == *"matching finding"* ]] && echo yes || echo no)" "$(note traefik)"

# A service that writes its own levels must not be told they were derived — that
# would be the same defect pointing the other way, and worse, because it would be
# wrong rather than merely absent.
for service in api postgres verifier-runner; do
  expect "$service is told nothing, because it writes its own levels" \
    "$(note "$service" >/dev/null 2>&1 && echo no || echo yes)" "$(note "$service" 2>&1)"
done

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

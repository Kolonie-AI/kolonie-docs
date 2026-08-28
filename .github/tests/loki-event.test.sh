#!/bin/bash
# Does a workflow's event reach Loki with a bounded label set, and does trying
# to send one never cost the step that called it? (`kolonie-docs#503`)
#
# Usage: bash .github/tests/loki-event.test.sh
#
# Three properties, and the second and third are the ones worth testing:
#
# **The labels are a closed set.** `service` and `level`, and nothing else.
# `architecture/infrastructure.md` states the rule and the reason — *cardinality
# is how a Loki install dies* — and an Actions push is exactly the caller that
# invites the wrong thing: `run_id`, `sha` and `pr_number` are unbounded and each
# one would open a new stream. They belong in the line. So the rejection case is
# a real case here rather than a formality.
#
# **The push never fails the step that called it.** A log store that is down is
# not a reason to lose a run, and it is not a finding about the workflow that was
# trying to report. Every failure path is asserted for exit 0 *and* for a
# sentence on stderr, because exit 0 with nothing said is the silence this whole
# issue is about.
#
# **Nothing is printed that must not be.** No token, no URL, and no provider
# response body — `watch-judge.py`'s rule for a model endpoint, applied to the
# write side: a store's error body can echo the request back with the credential
# inside it. `curl` is stubbed, so what was sent is a search over a log rather
# than a reading of the source.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/loki-event.sh"
FAILURES=()
pass=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Not a real host, and it never has to be: the stub answers before any name is
# resolved. The value is here so the assertions can prove it is never printed.
FAKE_URL="https://logs.example-not-a-real-host.test"
FAKE_USER="watch"
FAKE_TOKEN="loki-token-abcdefghijklmnop0123456789"

mkdir -p "$WORK/bin"
# Logs the whole argument list and the body file, then answers with whatever the
# case asked for. `--data-binary @file` is how the script sends, so a stub that
# logged only the arguments could not see what was pushed. A `--config` file is
# logged too — it is where the credential goes, and a stub blind to it could not
# tell "kept out of argv" from "not sent at all".
cat > "$WORK/bin/curl" <<'STUB'
#!/bin/bash
echo "$*" >> "$CURL_LOG"
_discards_body=0
_output=
for _i in $(seq 1 $#); do
  eval "_a=\${$_i}"
  case "$_a" in
    --data-binary)
      eval "_f=\${$((_i + 1))}"
      _f=${_f#@}
      [ -f "$_f" ] && cat "$_f" >> "$CURL_BODY" ;;
    --config|-K)
      eval "_f=\${$((_i + 1))}"
      [ -f "$_f" ] && cat "$_f" >> "$CURL_CONFIG" ;;
    -o|--output)
      eval "_f=\${$((_i + 1))}"
      _output=$_f
      [ "$_f" = /dev/null ] && _discards_body=1 ;;
  esac
done
# The store's own answer. A body is emitted on purpose: the script must not let
# it reach a public log, and a stub that returned an empty one could not prove
# that. Honouring `-o /dev/null` is what makes the assertion about the script
# rather than about the stub — real curl discards it there, so the only way the
# body can be printed is if the script never asked for it to be discarded.
if [ -n "${CURL_ECHO_BODY:-}" ]; then
  if [ "$_discards_body" = 0 ]; then
    if [ -n "${_output:-}" ] && [ "$_output" != /dev/null ]; then
      printf '%s' "$CURL_ECHO_BODY" > "$_output"
    else
      printf '%s' "$CURL_ECHO_BODY"
    fi
  fi
fi
printf '%s' "${CURL_STATUS:-204}"
exit "${CURL_RC:-0}"
STUB
chmod +x "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH"

case_setup() {
  CURL_LOG="$WORK/curl.log"
  CURL_BODY="$WORK/curl.body"
  CURL_CONFIG="$WORK/curl.config"
  export CURL_LOG CURL_BODY CURL_CONFIG
  : > "$CURL_LOG"
  : > "$CURL_BODY"
  : > "$CURL_CONFIG"
  unset CURL_STATUS CURL_RC CURL_ECHO_BODY
}

check() {
  local what=$1 want=$2 got=$3
  if [ "$want" = "$got" ]; then echo "  ok   $what"; pass=$((pass + 1))
  else echo "  FAIL $what"; echo "         expected: $want"; echo "         actual:   $got"; FAILURES+=("$what"); fi
}
contains() {
  local what=$1 needle=$2 hay=$3
  case "$hay" in
    *"$needle"*) echo "  ok   $what"; pass=$((pass + 1)) ;;
    *) echo "  FAIL $what"; echo "         wanted to find: $needle"; echo "         in: $hay"; FAILURES+=("$what") ;;
  esac
}
absent() {
  local what=$1 needle=$2 hay=$3
  case "$hay" in
    *"$needle"*) echo "  FAIL $what"; echo "         did not want to find: $needle"; FAILURES+=("$what") ;;
    *) echo "  ok   $what"; pass=$((pass + 1)) ;;
  esac
}

emit() {
  LOKI_URL="$FAKE_URL" LOKI_USER="$FAKE_USER" LOKI_TOKEN="$FAKE_TOKEN" bash "$SCRIPT" "$@"
}

echo "the body it builds"

case_setup
body=$(LOKI_URL="$FAKE_URL" LOKI_USER="$FAKE_USER" LOKI_TOKEN="$FAKE_TOKEN" \
  bash "$SCRIPT" body board-triage error \
    repository=Kolonie-AI/kolonie-docs run_id=33013176705 \
    workflow="Triage the board" attempt=1 \
    reason="candidates existed and no model answered" candidates=3); rc=$?
check "builds" "0" "$rc"
check "one stream" "1" "$(jq '.streams | length' <<<"$body")"
check "labelled by service" "board-triage" "$(jq -r '.streams[0].stream.service' <<<"$body")"
check "labelled by level" "error" "$(jq -r '.streams[0].stream.level' <<<"$body")"
check "and by nothing else" "level service" \
  "$(jq -r '.streams[0].stream | keys | join(" ")' <<<"$body")"
check "one value" "1" "$(jq '.streams[0].values | length' <<<"$body")"
# Loki wants nanoseconds as a string. Seconds silently lands every event in 1970.
check "a nanosecond timestamp" "19" "$(jq -r '.streams[0].values[0][0] | length' <<<"$body")"

line=$(jq -r '.streams[0].values[0][1]' <<<"$body")
check "the line is JSON, which is the shape watch-agent.sh reads with | json" \
  "0" "$(jq -e . >/dev/null 2>&1 <<<"$line"; echo $?)"
check "the run id is in the line" "33013176705" "$(jq -r '.run_id' <<<"$line")"
check "so is the repository" "Kolonie-AI/kolonie-docs" "$(jq -r '.repository' <<<"$line")"
check "so is the workflow name" "Triage the board" "$(jq -r '.workflow' <<<"$line")"
check "so is the reason" "candidates existed and no model answered" "$(jq -r '.reason' <<<"$line")"
check "so is the count" "3" "$(jq -r '.candidates' <<<"$line")"
# The line repeats them so a `| json` query can filter on them without the
# labels having to carry them.
check "and the line repeats service" "board-triage" "$(jq -r '.service' <<<"$line")"
check "and level" "error" "$(jq -r '.level' <<<"$line")"

echo
echo "an unbounded value offered as a label"
# The case this check exists for. `run_id` in a label opens one stream per run,
# which is the documented way a Loki install dies.

case_setup
out=$(emit emit board-triage error --label run_id=33013176705 2>&1); rc=$?
check "the calling step still passes" "0" "$rc"
contains "and it says which label was refused" "run_id" "$out"
contains "and names the closed set" "service" "$out"
check "and nothing was pushed" "" "$(cat "$CURL_LOG")"

case_setup
out=$(LOKI_URL="$FAKE_URL" LOKI_USER="$FAKE_USER" LOKI_TOKEN="$FAKE_TOKEN" \
  bash "$SCRIPT" body board-triage error --label sha=2b878d1 2>&1); rc=$?
check "the builder refuses outright, so a caller can be tested on it" "2" "$rc"
contains "naming the label" "sha" "$out"

case_setup
out=$(emit emit board-triage error --label pr_number=497 2>&1); rc=$?
check "pr_number is refused the same way" "0" "$rc"
contains "and named" "pr_number" "$out"
check "and nothing was pushed" "" "$(cat "$CURL_LOG")"

echo
echo "a service or level outside the set"
# Both label values are closed too. An open `service` is the same cardinality
# hole one level down — a typo per workflow is a stream per typo.

case_setup
out=$(emit emit whatever-i-felt-like error 2>&1); rc=$?
check "an unknown service does not fail the step" "0" "$rc"
contains "and is named" "whatever-i-felt-like" "$out"
check "and nothing was pushed" "" "$(cat "$CURL_LOG")"

case_setup
out=$(emit emit board-triage info 2>&1); rc=$?
check "a level outside error/warn does not fail the step" "0" "$rc"
contains "and is named" "info" "$out"
check "and nothing was pushed" "" "$(cat "$CURL_LOG")"

echo
echo "a good push"

case_setup
out=$(emit emit board-triage warn reason="nothing to route" candidates=0 2>&1); rc=$?
check "passes" "0" "$rc"
contains "and says the event was stored" "board-triage" "$out"
contains "posts to the push endpoint" "/loki/api/v1/push" "$(cat "$CURL_LOG")"
check "the pushed body carries the closed label set" "level service" \
  "$(jq -r '.streams[0].stream | keys | join(" ")' "$CURL_BODY")"
check "and the line carries the reason" "nothing to route" \
  "$(jq -r '.streams[0].values[0][1] | fromjson | .reason' "$CURL_BODY")"
absent "the token is never printed" "$FAKE_TOKEN" "$out"
absent "nor the store's address" "$FAKE_URL" "$out"
# `-u user:token` or `-H "Authorization: Bearer …"` puts the credential in the
# process argument list, which is world-readable on the runner for the life of
# the call. It travels in a config file instead — and it has to still arrive,
# which is the second assertion: "not in argv" is trivially satisfiable by not
# sending it at all.
absent "and the credential is not in curl's argument list" "$FAKE_TOKEN" "$(cat "$CURL_LOG")"
contains "but the Basic credential reaches curl's config" "user =" "$(cat "$CURL_CONFIG")"
contains "with the configured user" "$FAKE_USER" "$(cat "$CURL_CONFIG")"
contains "and token" "$FAKE_TOKEN" "$(cat "$CURL_CONFIG")"
absent "Bearer auth is not sent" "Bearer" "$(cat "$CURL_CONFIG")"
absent "nor an Authorization header" "Authorization:" "$(cat "$CURL_CONFIG")"

case_setup
out=$(env -u LOKI_USER LOKI_URL="$FAKE_URL" LOKI_TOKEN="$FAKE_TOKEN" \
  bash "$SCRIPT" emit board-triage warn reason="default user" 2>&1); rc=$?
check "an unset user still passes" "0" "$rc"
contains "and defaults to the live reader" "watch" "$(cat "$CURL_CONFIG")"

echo
echo "the store is down"
# A 5xx must cost the event and nothing else. This is the case that decides
# whether a workflow can call this at all.

case_setup
CURL_STATUS=503 CURL_ECHO_BODY='{"error":"upstream said no, and here is your request back"}' \
  export CURL_STATUS CURL_ECHO_BODY
out=$(emit emit board-triage error reason="the gateway answered 503" 2>&1); rc=$?
check "the calling step still passes" "0" "$rc"
contains "and the failure is visible in the step's output" "503" "$out"
absent "but the store's response body is not" "upstream said no" "$out"
absent "and neither is the token" "$FAKE_TOKEN" "$out"

case_setup
CURL_RC=7; export CURL_RC
out=$(emit emit board-triage error reason="unreachable" 2>&1); rc=$?
check "an unreachable store does not fail the step either" "0" "$rc"
contains "and says so" "could not be reached" "$out"

echo
echo "the credential is not configured"
# `watch-judge.py`'s policy for a missing key, applied to the write side: a named
# configuration gap on stderr, not a crash and not silence.

case_setup
out=$(env -u LOKI_TOKEN LOKI_URL="$FAKE_URL" bash "$SCRIPT" emit board-triage error 2>&1); rc=$?
check "the calling step passes" "0" "$rc"
contains "and the gap is named" "LOKI_TOKEN" "$out"
check "and nothing was pushed" "" "$(cat "$CURL_LOG")"

case_setup
out=$(env -u LOKI_URL LOKI_TOKEN="$FAKE_TOKEN" bash "$SCRIPT" emit board-triage error 2>&1); rc=$?
check "a missing store address is the same" "0" "$rc"
contains "and named" "LOKI_URL" "$out"
check "and nothing was pushed" "" "$(cat "$CURL_LOG")"

echo
echo "what is committed"
# The store's address is configuration, not a constant. A hostname committed
# as a default is a secret the leak guard fails CI over.
absent "no host name is defaulted into the script" "https://" "$(grep -v '^#' "$SCRIPT")"

echo
echo "board-triage.yml calls it on the ending #502 describes"
TRIAGE="$ROOT/.github/workflows/board-triage.yml"
contains "the workflow calls the shared script" "loki-event.sh" "$(cat "$TRIAGE")"
contains "as the board-triage service" "board-triage" "$(cat "$TRIAGE")"
contains "and reuses the reader credential" "LOKI_TOKEN" "$(cat "$TRIAGE")"
absent "rather than a second push credential" "LOKI_PUSH_TOKEN" "$(cat "$TRIAGE")"
contains "runs after the deliberate red step" "!cancelled()" "$(cat "$TRIAGE")"
contains "only for the no-model-answer ending" "steps.decide.outputs.unanswered == steps.decide.outputs.chunks" "$(cat "$TRIAGE")"
contains "and offers a dispatch-only prove path" "prove_loki" "$(cat "$TRIAGE")"
contains "which is off by default" "default: false" "$(cat "$TRIAGE")"

echo
echo "prove queries the bounded stream and prints counts, never bodies"
case_setup
CURL_STATUS=200
CURL_ECHO_BODY='{"status":"success","data":{"resultType":"streams","result":[{"stream":{"service":"board-triage","level":"warn"},"values":[["1","secret-line"]]}]}}'
export CURL_STATUS CURL_ECHO_BODY
out=$(LOKI_URL="$FAKE_URL" LOKI_USER="$FAKE_USER" LOKI_TOKEN="$FAKE_TOKEN" \
  bash "$SCRIPT" prove board-triage 2>&1); rc=$?
check "prove exits 0 when the stream answers" "0" "$rc"
contains "and names a hit count" "hits=" "$out"
absent "without the store address" "$FAKE_URL" "$out"
absent "without the token" "$FAKE_TOKEN" "$out"
absent "and without the raw line" "secret-line" "$out"
contains "querying the bounded service" 'query={service="board-triage"}' "$(cat "$CURL_LOG")"
absent "the prove credential is not in argv" "$FAKE_TOKEN" "$(cat "$CURL_LOG")"

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "all good ($pass assertions)"
  exit 0
fi
echo "${#FAILURES[@]} failed:"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

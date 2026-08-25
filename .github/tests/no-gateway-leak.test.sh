#!/bin/bash
# The leak check catches a leak, and does not print it (#207).
#
# The second half is the one worth testing. A check that fails by echoing the
# matching line is a check that publishes the secret into a log every time it
# does its job — and it would look correct in review, because the output is
# exactly what a person debugging would want.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/../scripts" && pwd)/no-gateway-leak.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0
FAILURES=()

check() {
  local what=$1 want=$2 got=$3
  if [ "$want" = "$got" ]; then
    echo "  ok   $what"
    pass=$((pass + 1))
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

SECRET_URL="https://gateway.example-not-a-real-host.test/v1"
SECRET_KEY="sk-abcdefghijklmnopqrstuvwxyz0123456789"

echo "a clean tree"
rm -rf "$WORK/tree"; mkdir -p "$WORK/tree"
echo '{"provider":{"gateway":{"options":{"baseURL":"{env:LLM_GATEWAY_BASE_URL}"}}}}' > "$WORK/tree/opencode.json"
out=$(LLM_GATEWAY_BASE_URL="$SECRET_URL" LLM_GATEWAY_API_KEY_WORKER="$SECRET_KEY" \
  bash "$SCRIPT" "$WORK/tree" 2>&1); rc=$?
check "passes" "0" "$rc"
contains "and says what it looked for" "no file holds the value of LLM_GATEWAY_BASE_URL" "$out"

echo
echo "a committed base URL"
rm -rf "$WORK/tree"; mkdir -p "$WORK/tree"
printf 'baseURL: %s\n' "$SECRET_URL" > "$WORK/tree/opencode.json"
out=$(LLM_GATEWAY_BASE_URL="$SECRET_URL" LLM_GATEWAY_API_KEY_WORKER="$SECRET_KEY" \
  bash "$SCRIPT" "$WORK/tree" 2>&1); rc=$?
check "fails" "1" "$rc"
contains "names the variable" "LLM_GATEWAY_BASE_URL" "$out"
contains "and the file" "opencode.json" "$out"
# The whole point.
absent "and never prints the value" "$SECRET_URL" "$out"

echo
echo "a committed key"
rm -rf "$WORK/tree"; mkdir -p "$WORK/tree"
printf 'apiKey = "%s"\n' "$SECRET_KEY" > "$WORK/tree/config.toml"
out=$(LLM_GATEWAY_BASE_URL="$SECRET_URL" LLM_GATEWAY_API_KEY_WORKER="$SECRET_KEY" \
  bash "$SCRIPT" "$WORK/tree" 2>&1); rc=$?
check "fails" "1" "$rc"
absent "and never prints the value" "$SECRET_KEY" "$out"

echo
echo "the provider that was migrated away from"
rm -rf "$WORK/tree"; mkdir -p "$WORK/tree"
echo 'opencode run --model openrouter/anthropic/claude-sonnet-4.5' > "$WORK/tree/worker.yml"
out=$(bash "$SCRIPT" "$WORK/tree" 2>&1); rc=$?
check "a leftover model literal fails" "1" "$rc"
contains "and says which one" "openrouter/anthropic" "$out"

rm -rf "$WORK/tree"; mkdir -p "$WORK/tree"
echo 'OPENROUTER_API_KEY_OPENCODE: ${{ secrets.OPENROUTER_API_KEY_OPENCODE }}' > "$WORK/tree/worker.yml"
out=$(bash "$SCRIPT" "$WORK/tree" 2>&1); rc=$?
check "a leftover key reference fails" "1" "$rc"

echo
echo "a fork, where the secrets are not there"
# The half that must not become a check firing on a correct configuration. A
# pull request from a fork gets no secrets, and a failure there blocks every
# outside contribution for a reason nobody outside can act on.
rm -rf "$WORK/tree"; mkdir -p "$WORK/tree"
echo 'nothing to see' > "$WORK/tree/readme.md"
out=$(env -u LLM_GATEWAY_BASE_URL -u LLM_GATEWAY_API_KEY_WORKER bash "$SCRIPT" "$WORK/tree" 2>&1); rc=$?
check "passes" "0" "$rc"
contains "and says it skipped rather than passing quietly" "skip: LLM_GATEWAY_BASE_URL is not set" "$out"

echo
echo "a value too short to search for"
# Ten characters is well below any URL or token and well above anything that
# collides by accident. A one-character secret would match everything and the
# check would be switched off within a day.
rm -rf "$WORK/tree"; mkdir -p "$WORK/tree"
echo 'e' > "$WORK/tree/readme.md"
out=$(LLM_GATEWAY_BASE_URL="e" LLM_GATEWAY_API_KEY_WORKER="$SECRET_KEY" \
  bash "$SCRIPT" "$WORK/tree" 2>&1); rc=$?
check "fails rather than matching everything" "1" "$rc"
contains "and says why" "shorter than 10 characters" "$out"

echo
echo "this repository as it stands"
out=$(bash "$SCRIPT" "$(cd "$(dirname "$0")/../.." && pwd)" 2>&1); rc=$?
check "is clean" "0" "$rc"

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "all good ($pass assertions)"
  exit 0
fi
echo "${#FAILURES[@]} failed:"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

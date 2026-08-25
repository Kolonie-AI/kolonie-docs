#!/bin/bash
# One naming scheme for reaching a gateway, across the whole Colony (#493).
#
# ## What this asserts and why it is a test rather than a review note
#
# There were three names for the same idea: the runners in `kolonie-platform`
# read `LLM_GATEWAY_*`, this repository's workflows read `OPENCODE_LLM_*`, and
# both reached OpenRouter directly for the fallback. The cost is measured, not
# hypothetical — on 2026-08-25 `board-triage.yml` logged
# `gpt-5.6-sol: the gateway answered 401` and `grok-4.5: the gateway answered
# 401` on a live run, because the key had been rotated on the deployment host
# and in `kolonie-platform` while the Actions secrets kept a name nobody thought
# to look under.
#
# A rename is exactly the change that half-lands. A grep is what keeps the
# second half from being forgotten, and it costs nothing to run.
#
# ## The rejection case
#
# A workflow whose gateway variables are unset must **fail loudly rather than
# proceeding**. An empty gateway configuration is the dangerous state: it does
# not error, it falls through to whatever the fallback path is, and it does so
# silently. That is asserted here against the worker's own guard.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

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

echo "the retired names are gone"
# Two files name them on purpose and are excluded by name rather than by
# loosening the pattern. **This file**, which forbids them — the same shape
# `no-gateway-leak.sh` uses for the literals it refuses. And
# **`coverage-retired.txt`**, which is the register of lines a change made
# untrue: `check-brief-coverage.py` requires every line of the pre-split
# `ARCHITECTURE.md` to be somewhere, and the two rows naming these variables
# are retired there with the reason, which is exactly what that register is
# for. Excluding it is not a hole — a retired line is quoted in order to be
# recorded as gone, and the register is not read by anything at run time.
for name in OPENCODE_LLM_BASE_URL OPENCODE_LLM_API_KEY OPENCODE_LLM_MODEL; do
  hits=$(grep -rlF --exclude-dir=.git \
    --exclude=gateway-naming.test.sh --exclude=coverage-retired.txt \
    -- "$name" "$ROOT" 2>/dev/null)
  check "no file carries $name" "" "$hits"
done

echo
echo "the shared names are what the worker reads"
for name in LLM_GATEWAY_BASE_URL LLM_GATEWAY_API_KEY_WORKER LLM_GATEWAY_MODEL_WORKER; do
  hits=$(grep -rlF --exclude-dir=.git --exclude=gateway-naming.test.sh \
    -- "$name" "$ROOT/.github/workflows" 2>/dev/null)
  if [ -n "$hits" ]; then
    echo "  ok   a workflow reads $name"
    pass=$((pass + 1))
  else
    echo "  FAIL a workflow reads $name"
    FAILURES+=("a workflow reads $name")
  fi
done

# The worker is a service in the same sense the runners are, so it gets its own
# key rather than sharing one. D-122 §3 in `kolonie-platform` is the reason: a
# runaway loop in one service must not take the cap for the others with it, and
# *whose traffic is this* has to be answerable at the gateway.
echo
echo "the worker has a key of its own"
shared=$(grep -rn 'secrets.LLM_GATEWAY_API_KEY\b' "$ROOT/.github/workflows" 2>/dev/null)
check "no workflow reads an unsuffixed shared key" "" "$shared"

echo
echo "opencode.json substitutes the shared names"
config=$(cat "$ROOT/opencode.json")
contains "the base URL" '{env:LLM_GATEWAY_BASE_URL}' "$config"
contains "the key" '{env:LLM_GATEWAY_API_KEY_WORKER}' "$config"

echo
echo "the leak check guards the new names"
guarded=$(sed -n '/^GUARDED=(/,/^)/p' "$ROOT/.github/scripts/no-gateway-leak.sh")
contains "the base URL" "LLM_GATEWAY_BASE_URL" "$guarded"
contains "the worker key" "LLM_GATEWAY_API_KEY_WORKER" "$guarded"

echo
echo "an unset gateway variable fails loudly rather than proceeding"
# The guard the worker runs before it asks for anything. Renaming a variable
# while the secret still carries the old name yields an empty value, and an
# empty gateway configuration falls through to whatever the fallback path is —
# which is silent. This is the line that makes it loud.
guard=$(grep -n 'is not set' "$ROOT/.github/workflows/opencode-worker.yml")
contains "the model is named in the refusal" "LLM_GATEWAY_MODEL_WORKER" "$guard"
contains "the base URL is named in the refusal" "LLM_GATEWAY_BASE_URL" "$guard"
contains "the key is named in the refusal" "LLM_GATEWAY_API_KEY_WORKER" "$guard"

echo
echo "the triage pass reads the shared names too"
decide=$(cat "$ROOT/.github/scripts/board-triage-decide.py")
contains "the key" "LLM_GATEWAY_API_KEY_TRIAGE" "$decide"
contains "the base URL" "LLM_GATEWAY_BASE_URL" "$decide"

echo
echo "the documentation names what the workflows read"
automation=$(cat "$ROOT/architecture/automation.md")
contains "the key" "LLM_GATEWAY_API_KEY_WORKER" "$automation"
contains "the model" "LLM_GATEWAY_MODEL_WORKER" "$automation"
contains "the base URL" "LLM_GATEWAY_BASE_URL" "$automation"

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "all good ($pass assertions)"
  exit 0
fi
echo "${#FAILURES[@]} failed:"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

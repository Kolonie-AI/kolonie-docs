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
contains "the fallback base URL" "LLM_GATEWAY_FALLBACK_BASE_URL" "$guarded"
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
transport=$(cat "$ROOT/.github/scripts/actions-gateway.py")
decide=$(cat "$ROOT/.github/scripts/board-triage-decide.py")
contains "the key" "LLM_GATEWAY_API_KEY_" "$transport"
contains "the base URL" "LLM_GATEWAY_BASE_URL" "$transport"
contains "the fallback base URL" "LLM_GATEWAY_FALLBACK_BASE_URL" "$transport"
contains "the fallback key prefix" "LLM_GATEWAY_FALLBACK_API_KEY_" "$transport"

# `#502`. This file greps for retired *variable names*; the outage it was written
# after was a retired *model value*, sent every half hour through a healthy
# gateway. Measured 2026-08-26: the two bare identifiers answered 503 and the
# served prefixed names and the tier alias answered 200. A default in the
# workflow is the one place a bare name can come back without anybody choosing
# it, so that is what is asserted here.
echo
echo "no workflow defaults to a model identifier the gateway does not serve"
triage=$(cat "$ROOT/.github/workflows/board-triage.yml")
for name in "grok-4.5" "gpt-5.6-sol"; do
  hits=$(grep -n "|| *'$name'" "$ROOT/.github/workflows/board-triage.yml" 2>/dev/null)
  check "board-triage.yml does not default to $name" "" "$hits"
done

# The second half of `#502`: a pass with candidates that could not ask anything
# must not be conclusion success. The step is what enforces it, so the step is
# what is asserted — prose in a header cannot fail a run.
echo
echo "a pass that asked nothing and had candidates fails visibly"
contains "the script has an exit code meaning nothing could be asked" "NO_ANSWER" "$decide"
contains "the workflow counts the chunks nothing answered" "unanswered=" "$triage"
contains "the workflow captures an unanswered exit without losing the other chunks" \
  '|| rc=$?' "$triage"
contains "and propagates an unexpected script failure instead of calling it unanswered" \
  '*) exit "$rc"' "$triage"
contains "and refuses the pass where every chunk went unanswered" \
  "steps.decide.outputs.unanswered == steps.decide.outputs.chunks" "$triage"
contains "with a non-zero exit rather than a warning" "          exit 1" "$triage"

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

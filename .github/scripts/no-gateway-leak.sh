#!/bin/bash
# Nothing about the private gateway is committed to this repository (#207).
#
# ## Why this is a check and not a habit
#
# `#207` asks for it in as many words — *"`grep -r llm-gateway` over this
# repository returns nothing today. It must still return nothing when this issue
# is done, and that is worth a check in CI rather than a habit."*
#
# The thing being guarded is not the key. It is the **base URL**, which names a
# private endpoint: a committed hostname is a target, and it stays reachable in
# git history long after somebody deletes the line. A key can be rotated in a
# minute; a URL in a public repository's history cannot be taken back.
#
# ## Why it greps for the values rather than for a pattern
#
# A pattern would have to be written down, and writing down what the hostname
# looks like is most of the way to writing down the hostname. So the forbidden
# strings arrive in the environment, from the same secrets the worker uses, and
# this script never learns them at rest.
#
# **It prints no value, ever, including on failure.** It says which variable
# matched and in which file, because that is enough to fix it and a grep hit
# echoed into a public log would be the leak this exists to prevent.
#
# ## What it does when the secrets are absent
#
# Passes, and says so. This runs on pull requests from forks, where secrets are
# not available, and a check that failed there would be a check that blocks
# every outside contribution for a reason nobody outside can act on. The run
# that matters is the one on `main` and on internal pull requests, where the
# values are present.
#
# Usage:
#   LLM_GATEWAY_BASE_URL=… LLM_GATEWAY_API_KEY_WORKER=… bash .github/scripts/no-gateway-leak.sh [dir]
set -uo pipefail

ROOT=${1:-.}

# The variables whose *values* must not appear. The model is deliberately not
# among them: `#207` names `gpt-5.6-sol` in the issue body itself, so it is a
# setting kept out of the files rather than a secret kept out of the world.
#
# **Both gateways, since `#493`.** The fallback is a second private endpoint and
# a second key, and it is exactly as committable as the first — a check guarding
# only the primary would pass while the backup's hostname sat in the tree. Its
# variables are named in the same shape as the primary's, so an operator reading
# one can predict the other.
#
# **A variable that is not set is skipped and said so**, which is what makes it
# safe to name four here: a deployment with no fallback configured is the
# ordinary case, not a failure.
GUARDED=(
  LLM_GATEWAY_BASE_URL
  LLM_GATEWAY_API_KEY_WORKER
  LLM_GATEWAY_FALLBACK_BASE_URL
  LLM_GATEWAY_FALLBACK_API_KEY_WORKER
)

# And the literal strings a swap leaves behind. These are not secrets — they are
# the old provider, and finding one means the migration is half done, which is
# its own defect: a stale `openrouter` model in a config is a run that silently
# uses the provider the project moved off.
FORBIDDEN_LITERALS=("openrouter/anthropic" "OPENROUTER_API_KEY_OPENCODE")

failures=0
checked=0

for name in "${GUARDED[@]}"; do
  value=${!name:-}
  if [ -z "$value" ]; then
    echo "skip: $name is not set in this environment"
    continue
  fi

  # A short value would match half the repository and turn this into noise that
  # gets switched off. Ten characters is well below any URL or token and well
  # above anything that collides by accident.
  if [ "${#value}" -lt 10 ]; then
    echo "FAIL: $name is set but shorter than 10 characters, so it cannot be searched for safely" >&2
    failures=$((failures + 1))
    continue
  fi

  checked=$((checked + 1))
  # `--exclude-dir=.git`: history is not the working tree, and a hit there is a
  # different and much larger problem than this check can fix.
  if hits=$(grep -rlF --exclude-dir=.git -- "$value" "$ROOT" 2>/dev/null) && [ -n "$hits" ]; then
    echo "FAIL: the value of $name appears in this repository:" >&2
    printf '  %s\n' $hits >&2
    failures=$((failures + 1))
  else
    echo "ok: no file holds the value of $name"
  fi
done

for literal in "${FORBIDDEN_LITERALS[@]}"; do
  checked=$((checked + 1))
  # This file names them in order to forbid them, and so does its test.
  if hits=$(grep -rlF --exclude-dir=.git \
      --exclude=no-gateway-leak.sh --exclude=no-gateway-leak.test.sh \
      -- "$literal" "$ROOT" 2>/dev/null) && [ -n "$hits" ]; then
    echo "FAIL: '$literal' is left over from the provider this repository moved off (#207):" >&2
    printf '  %s\n' $hits >&2
    failures=$((failures + 1))
  else
    echo "ok: nothing carries '$literal'"
  fi
done

if [ "$failures" -gt 0 ]; then
  echo >&2
  echo "$failures check(s) failed. No value is printed above on purpose — the file name is enough to fix it." >&2
  exit 1
fi

echo "$checked check(s) passed"

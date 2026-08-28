#!/bin/bash
# One structured event from a GitHub Actions run into Loki (`kolonie-docs#503`).
#
# Usage:
#   loki-event.sh emit <service> <level> [key=value ...] [--label k=v ...]
#   loki-event.sh body <service> <level> [key=value ...]   # build it, push nothing
#
#   LOKI_URL=…  LOKI_TOKEN=…  bash .github/scripts/loki-event.sh \
#     emit board-triage error reason="candidates existed and no model answered" \
#     candidates=3 run_id="$GITHUB_RUN_ID"
#
# ## What this is for
#
# Measured 2026-08-26 (`#502`): `board-triage.yml` ran every thirty minutes for a
# day, routed nothing on each pass, and reported success every time. The only
# record was a line on stdout of a GitHub-hosted runner — nothing collected it,
# nothing could query it, and by the time anybody looked the older runs' logs
# were the least convenient place to read a trend from.
#
# The store already exists. `kolonie-infra#68` runs Loki and Promtail beside the
# other containers and `watch-agent.sh` already reads LogQL over HTTP behind a
# token. What was missing is the write path from Actions, and this is it: **one
# script called from a workflow step**, rather than a copy of `curl` in every
# workflow file.
#
# ## This does not replace a red run, and must not be read as one
#
# A line in Loki wakes nobody. `#502` covers making a pass that cannot do its
# work fail visibly; this is where a failure is *analysed* — over days, across
# workflows, next to the container logs. Treating this as an alarm would repeat
# the mistake `#503` was opened to document.
#
# ## The labels are closed, and that is the whole design
#
# `architecture/infrastructure.md`: *"Labels are `service` and `level` and
# nothing else, because cardinality is how a Loki install dies."*
#
# An Actions push invites exactly the wrong thing. `run_id`, `sha`, `pr_number`,
# `branch` and `actor` are all unbounded, and each one used as a label opens a
# new stream per value — a stream per run, forever, until the install stops
# answering. So they go **in the line**, as JSON, which is the shape
# `watch-agent.sh` already reads with `| json` and can filter on just as well.
#
# Both label *values* are closed too, and for the same reason one level down: an
# open `service` means a typo is a permanent stream. The two lists are below, and
# adding a workflow means adding its name to `SERVICES` in a diff somebody reads.
#
# ## It may never fail the step that called it
#
# `#503` says so outright, and it is the property that decides whether a workflow
# can call this at all: *"A log store that is down is not a reason to lose a run,
# and it is not a finding about the workflow that was trying to report."*
#
# So `emit` exits 0 on every path — a refused label, an unreachable store, a 5xx,
# an absent credential. What it never does is exit 0 **quietly**: every one of
# those prints a sentence naming what happened, because silence is the failure
# this whole issue is about. `body` is the half that can be strict, and it exits
# 2 on a bad label so the tests and any future caller can assert on the refusal
# without a push behind it.
#
# ## What it must never print
#
# No token, no store address, and **no response body**. That last one is
# `watch-judge.py`'s rule for a model endpoint applied to the write side: a
# store's error body can echo the request back with the credential inside it, and
# this log is public. The status code is what a reader needs and is all they get.
#
# The address is not defaulted here either. `watch-agent.sh` carries one because
# it predates the rule; `AGENTS.md` §9 forbids a host name in a repository, and a
# new file adding a second copy of one would be a leak with a comment on it.
set -uo pipefail

# The automations that may write. A name not here is refused rather than pushed,
# so a typo cannot mint a stream. Adding one is a line in a diff.
SERVICES=(board-triage opencode-worker skill-dispatch watch-agent red-on-main board-self-check)

# `error` and `warn`, and `#503` names both. Nothing below `warn` — an `info`
# stream from Actions is log forwarding, which is explicitly out of scope, and
# `kolonie-infra#81` drops `debug` and `info` at the pipeline anyway.
LEVELS=(error warn)

in_list() {
  local needle=$1; shift
  local one
  for one in "$@"; do [ "$one" = "$needle" ] && return 0; done
  return 1
}

# The refusal, in one place, so `emit` and `body` say the same sentence and only
# differ in what they do afterwards.
why_not() {
  local service=$1 level=$2; shift 2
  local pair key

  if ! in_list "$service" "${SERVICES[@]}"; then
    echo "loki-event: '$service' is not one of the services that may write: ${SERVICES[*]}."
    echo "            The set is closed because an open one is a stream per typo."
    return 1
  fi

  if ! in_list "$level" "${LEVELS[@]}"; then
    echo "loki-event: '$level' is not a level this writes: ${LEVELS[*]}."
    echo "            A line in Loki is for analysis, not for an alarm, and there is"
    echo "            no info stream from Actions by design."
    return 1
  fi

  for pair in "$@"; do
    key=${pair%%=*}
    echo "loki-event: '$key' was offered as a label, and the labels are service and level."
    echo "            Anything else — run_id, sha, pr_number — is unbounded, and one"
    echo "            stream per value is how a Loki install dies. Pass it as a plain"
    echo "            key=value instead and it lands in the line, where a '| json'"
    echo "            query can still filter on it."
    return 1
  done

  return 0
}

# The fields become a JSON object with `jq --arg`, so a reason containing a quote
# or a newline cannot produce a body that is not JSON. Everything is a string:
# Loki's line is text, and a count read back through `| json` compares fine.
build() {
  local service=$1 level=$2; shift 2
  local args=(--arg service "$service" --arg level "$level")
  local fields='{service: $service, level: $level}'
  local pair key value

  for pair in "$@"; do
    key=${pair%%=*}
    value=${pair#*=}
    # A key that is not a bare word would need quoting inside the jq program, and
    # a field nobody can name is a field nobody can query.
    if [[ ! "$key" =~ ^[a-z][a-z0-9_]*$ ]]; then
      echo "loki-event: '$key' is not a usable field name — lowercase, digits and underscores." >&2
      return 2
    fi
    args+=(--arg "f_$key" "$value")
    fields="$fields + {$key: \$f_$key}"
  done

  # Nanoseconds, as a string, which is what the push API wants. Seconds would be
  # accepted and would land every event in 1970 — `date +%s%N` is the whole of
  # the difference and it is not visible in a 204.
  args+=(--arg ts "$(date -u +%s)000000000")

  jq -cn "${args[@]}" \
    "{streams: [{stream: {service: \$service, level: \$level},
                 values: [[\$ts, ($fields | tojson)]]}]}"
}

# `--label k=v` is accepted only so it can be refused by name. A caller that
# wants a label gets the sentence above rather than a silent demotion into the
# line, because a silent demotion teaches nobody and the next caller writes it
# again.
split_args() {
  FIELDS=()
  LABELS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --label)
        shift
        [ $# -gt 0 ] || { echo "loki-event: --label wants a key=value" >&2; return 2; }
        LABELS+=("$1") ;;
      --label=*) LABELS+=("${1#--label=}") ;;
      *) FIELDS+=("$1") ;;
    esac
    shift
  done
  return 0
}

cmd_body() {
  local service=${1:-} level=${2:-}
  shift 2 2>/dev/null || true
  split_args "$@" || return 2

  local refusal
  if ! refusal=$(why_not "$service" "$level" ${LABELS+"${LABELS[@]}"}); then
    echo "$refusal" >&2
    return 2
  fi

  build "$service" "$level" ${FIELDS+"${FIELDS[@]}"}
}

cmd_emit() {
  local service=${1:-} level=${2:-}
  shift 2 2>/dev/null || true
  split_args "$@" || return 0

  local refusal
  if ! refusal=$(why_not "$service" "$level" ${LABELS+"${LABELS[@]}"}); then
    # Named on stderr and the step carries on. The event is lost and the reason
    # for losing it is a mistake in the caller, which is a thing to fix in a diff
    # rather than a thing to fail a run over.
    echo "$refusal" >&2
    echo "loki-event: nothing was pushed. The calling step is unaffected." >&2
    return 0
  fi

  # The configuration gap, `watch-judge.py`'s policy on the write side: a named
  # gap on stderr, not a crash and not silence. A fork's pull request has no
  # secrets and must not be told the workflow is broken.
  local missing=()
  [ -n "${LOKI_URL:-}" ] || missing+=(LOKI_URL)
  [ -n "${LOKI_TOKEN:-}" ] || missing+=(LOKI_TOKEN)
  if [ ${#missing[@]} -gt 0 ]; then
    echo "loki-event: ${missing[*]} is not set, so the event was not pushed — a configuration" >&2
    echo "            gap, not a finding about $service. The calling step is unaffected." >&2
    return 0
  fi

  local payload status rc
  payload=$(mktemp)
  # shellcheck disable=SC2064 — the path is wanted now, not at trap time.
  trap "rm -f '$payload'" RETURN
  if ! cmd_body "$service" "$level" ${FIELDS+"${FIELDS[@]}"} > "$payload" 2>/dev/null; then
    echo "loki-event: the event could not be built, so nothing was pushed." >&2
    return 0
  fi

  # The credential travels in a config file, never in the argument list:
  # `/proc/<pid>/cmdline` is readable by everything on the runner, so a
  # `-u user:token` or an `-H "Authorization: …"` publishes it for the life of
  # the call to anything else running there. The file is created with the
  # process's own umask under `mktemp` and removed by the trap below.
  #
  # HTTP Basic, not Bearer: the live Traefik edge authenticates against an
  # htpasswd file, and a Bearer probe answers 401. `watch-agent.sh` already
  # reads with Basic and `LOKI_USER` defaulting to `watch`; the write path
  # uses the same pair so Actions does not invent a second protocol.
  #
  # `-o /dev/null` and `-w %{http_code}`: the status is what a reader needs, and
  # the body is the one thing that must not reach a public log.
  local conf
  conf=$(mktemp)
  # shellcheck disable=SC2064 — both paths are wanted now, not at trap time.
  trap "rm -f '$payload' '$conf'" RETURN
  printf 'user = "%s:%s"\n' "${LOKI_USER:-watch}" "$LOKI_TOKEN" > "$conf"

  status=$(curl -sS --max-time 20 -o /dev/null -w '%{http_code}' \
    --config "$conf" \
    -H "Content-Type: application/json" \
    --data-binary "@$payload" \
    "${LOKI_URL%/}/loki/api/v1/push" 2>/dev/null)
  rc=$?

  if [ "$rc" -ne 0 ]; then
    echo "loki-event: the log store could not be reached (curl exit $rc); the $service event was" >&2
    echo "            not stored. The calling step is unaffected." >&2
    return 0
  fi

  case "$status" in
    2*)
      echo "loki-event: stored a $level event for $service."
      return 0 ;;
    *)
      # The status and nothing else, deliberately. `watch-judge.py`'s comment is
      # the argument: a provider's error body can echo the request back with the
      # credential inside it.
      echo "loki-event: the log store answered $status; the $service event was not stored." >&2
      echo "            The calling step is unaffected." >&2
      return 0 ;;
  esac
}

case "${1:-}" in
  emit) shift; cmd_emit "$@" ;;
  body) shift; cmd_body "$@" ;;
  *)
    echo "loki-event.sh: one of emit, body — see the header." >&2
    exit 2 ;;
esac

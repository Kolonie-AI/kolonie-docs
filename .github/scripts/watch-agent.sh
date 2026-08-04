#!/bin/bash
# The Watch Agent's deterministic half: read yesterday out of Loki, decide
# whether anything is wrong, and say so on an issue. `kolonie-docs#133`.
#
# Usage:
#   watch-agent.sh gather <dir>   # run the queries, write the numbers, exit 2 if Loki is unreachable
#   watch-agent.sh decide <dir>   # exit 1 if something is wrong and an issue is owed
#   watch-agent.sh report <dir>   # open that issue, or comment on the one already open
#
# ## What it sends the model, and what it does not
#
# **Numbers, never lines.** Every query here aggregates inside Loki, so what
# leaves this script is a few hundred tokens of counts. Sending raw logs would
# be expensive enough to run weekly and noisy enough to distrust, and both of
# those are the same failure: a monitor nobody runs.
#
# ## What it must never do
#
# **It reads. It does not act.** No container is restarted, nothing is edited,
# and — unlike `board-self-check.sh` next door — **no issue is ever closed.**
# `#133` says so outright, and the difference is worth stating rather than
# leaving as an inconsistency somebody later "fixes": the board check reports a
# condition it can re-measure as gone, while a bad day in the logs is not
# something that becomes untrue. Whoever reads the issue decides when it is done.
#
# ## There are no thresholds in this file, deliberately
#
# Grep it: no number says how many errors are too many. A threshold per service
# is wrong on the first day and stale on the second. What the model gets instead
# is seven days of the same counts beside today's, and the question *is today
# normal* — which is the question a person would ask, and needs no maintenance.
#
# The one thing decided without the model is silence, because silence is a
# boolean and it is the signal error-watching structurally misses: a dead runner
# throws no errors.
set -uo pipefail

LOKI_URL="${LOKI_URL:-https://logs.kolonie.ai}"
LOKI_USER="${LOKI_USER:-watch}"
TITLE="The Watch Agent found something in yesterday's logs"

# `date -u +%s` at the top, once. Every window below is relative to it, so the
# 24-hour and 7-day queries cannot disagree about when "now" was — which they
# would, by seconds, if each asked for itself.
NOW="${WATCH_NOW:-$(date -u +%s)}"
DAY_AGO=$((NOW - 86400))
WEEK_AGO=$((NOW - 604800))

# Every call goes through here so the credential appears in exactly one place and
# never in an argument list. `--fail-with-body` is deliberately not used: a 401
# and a 500 are both "the store did not answer", and the caller distinguishes
# them by there being no JSON rather than by a status code.
loki() {
  local path="$1"; shift
  local args=() a
  for a in "$@"; do args+=(--data-urlencode "$a"); done
  curl -sS --max-time 60 -u "$LOKI_USER:${LOKI_TOKEN:-}" -G "$LOKI_URL$path" "${args[@]}" 2>/dev/null
}

# --- is the store even reachable ---------------------------------------------
# The same shape `board-self-check.sh` uses for an unreadable board and
# `review-pull-request.yml` for a missing model key: **a check that cannot reach
# its subject must not be the reason the subject looks broken.** This exits 2,
# distinct from both answers, and the workflow reports it in the log rather than
# on an issue.
#
# It is not hypothetical. The route is behind a token that can be rotated, a
# Traefik middleware whose file can go missing, and a host that can be down —
# and the last of those is the one where filing "every service is silent" would
# be both true and useless.
loki_reachable() {
  local ready
  ready=$(curl -sS --max-time 30 -o /dev/null -w '%{http_code}' \
            -u "$LOKI_USER:${LOKI_TOKEN:-}" "$LOKI_URL/loki/api/v1/labels" 2>/dev/null)
  [ "$ready" = "200" ] && return 0
  echo "Loki did not answer: HTTP ${ready:-no response} at $LOKI_URL. Neither question was asked."
  echo
  echo "This is a configuration gap and not a finding — a store that cannot be"
  echo "read reports every service as silent, which would be true and useless."
  return 2
}

# --- query 1: error and warning counts per service per hour, last 24 hours ----
# Hourly rather than a single total, because a hundred errors in one minute and a
# hundred spread over a day are different events and only the shape says which.
q_hourly() {
  loki /loki/api/v1/query_range \
    'query=sum by (service, level) (count_over_time({job="containers", level=~"error|warn"}[1h]))' \
    "start=$DAY_AGO" "end=$NOW" "step=3600"
}

# --- query 2: the distinct error slugs, with a count each ---------------------
# **Distinct, not every instance.** One `poll.failed` repeated four hundred times
# is one thing that is wrong, and the four hundred is a number rather than four
# hundred lines. `| json` reaches the `event` field inside the line, which is
# there because kolonie-platform#230 made these lines structured — over prose it
# finds nothing, which is why that issue blocked this one.
q_slugs() {
  loki /loki/api/v1/query \
    'query=topk(30, sum by (service, event) (count_over_time({job="containers", level="error"} | json [24h])))' \
    "time=$NOW"
}

# --- query 3: which services said nothing at all -----------------------------
# **No model, no key, and no configured list of services.** The expected set is
# whatever logged in the last seven days; anything in that set and not in the
# last twenty-four hours has gone quiet. A hardcoded list would be wrong the
# first time a service is added and would make this the file somebody has to
# remember to edit.
#
# It follows that a store with less than a day of history reports nothing here,
# which is correct: on the day Loki is installed, every service is new.
q_service_values() {
  loki /loki/api/v1/label/service/values "start=$1" "end=$2" \
    | jq -r '.data // [] | .[]' 2>/dev/null | grep -v '^$' | sort -u
}

cmd_gather() {
  local dir="$1"
  mkdir -p "$dir"
  : > "$dir/numbers.md"

  if ! loki_reachable > "$dir/unreachable.md"; then
    cat "$dir/unreachable.md"
    return 2
  fi
  rm -f "$dir/unreachable.md"

  # Silence first: it is the one answer that owes nothing to the model, and
  # writing it before anything else means a later failure cannot lose it.
  comm -23 <(q_service_values "$WEEK_AGO" "$NOW") <(q_service_values "$DAY_AGO" "$NOW") \
    > "$dir/silent.txt"

  # The rehearsal's fabricated silent service, and it belongs **here** rather
  # than in the workflow step after `gather` has run. Appended afterwards it
  # reached `decide` but not `numbers.md`, so the first rehearsal filed an issue
  # that said "Services that logged nothing: None." — a report contradicting the
  # reason it was written. Measured on 2026-08-04 against `kolonie-docs#156`.
  #
  # Injected at this point it takes exactly the path a real silent service takes,
  # which is the only version of a rehearsal worth having.
  [ -n "${WATCH_FORCE_SILENT:-}" ] && echo "$WATCH_FORCE_SILENT" >> "$dir/silent.txt"

  q_hourly > "$dir/hourly.json"
  q_slugs  > "$dir/slugs.json"
  # Seven days of the same counts, one point per day. This is what replaces a
  # threshold: the model is shown last week beside today and asked whether today
  # is unusual, rather than asked to compare today against a number somebody
  # guessed once.
  loki /loki/api/v1/query_range \
    'query=sum by (service, level) (count_over_time({job="containers", level=~"error|warn"}[24h]))' \
    "start=$WEEK_AGO" "end=$NOW" "step=86400" > "$dir/history.json"

  {
    echo "### Errors and warnings per service, last 24 hours"
    echo
    echo "| service | level | total | peak hour |"
    echo "|---|---|---|---|"
    jq -r '.data.result // [] | .[]
           | [(.metric.service // "«unlabelled»"), .metric.level,
              ([.values[][1] | tonumber] | add),
              ([.values[][1] | tonumber] | max)]
           | @tsv' "$dir/hourly.json" 2>/dev/null \
      | sort -k3 -rn | awk -F'\t' '{printf "| `%s` | %s | %s | %s |\n", $1, $2, $3, $4}'
    echo
    echo "### Distinct error events, last 24 hours"
    echo
    echo "| service | event | count |"
    echo "|---|---|---|"
    jq -r '.data.result // [] | .[]
           | [(.metric.service // "«unlabelled»"), (.metric.event // "«no event field»"), .value[1]]
           | @tsv' "$dir/slugs.json" 2>/dev/null \
      | sort -k3 -rn | awk -F'\t' '{printf "| `%s` | `%s` | %s |\n", $1, $2, $3}'
    echo
    echo "### Services that logged nothing in 24 hours, having logged in the last 7 days"
    echo
    if [ -s "$dir/silent.txt" ]; then
      sed 's/^/- `/; s/$/`/' "$dir/silent.txt"
    else
      echo "None."
    fi
    echo
    echo "### The same counts, one row per day, last 7 days"
    echo
    echo "| service | level | daily totals, oldest first |"
    echo "|---|---|---|"
    jq -r '.data.result // [] | .[]
           | [(.metric.service // "«unlabelled»"), .metric.level,
              ([.values[][1]] | join(", "))]
           | @tsv' "$dir/history.json" 2>/dev/null \
      | sort | awk -F'\t' '{printf "| `%s` | %s | %s |\n", $1, $2, $3}'
  } > "$dir/numbers.md"

  cat "$dir/numbers.md"
}

# --- the decision -------------------------------------------------------------
# Two inputs, and either is enough:
#
#   - a silent service, decided here and needing nothing else
#   - the model saying today is not normal, in `judgement.json`
#
# A missing or unparseable `judgement.json` is **not** a reason to file. It means
# the judgement half did not run — no key, no answer, a provider outage — and the
# deterministic half still gets to speak. Filing on it would turn every provider
# hiccup into a morning issue, which is how a monitor gets muted.
cmd_decide() {
  local dir="$1" abnormal
  [ -s "$dir/silent.txt" ] && { echo "a service has gone silent"; return 1; }
  abnormal=$(jq -r '.abnormal // false' "$dir/judgement.json" 2>/dev/null)
  [ "$abnormal" = "true" ] && { echo "the model reports today as abnormal"; return 1; }
  echo "nothing to report"
  return 0
}

# --- reporting ----------------------------------------------------------------
# One issue, reused. Listed and filtered rather than searched, and then waited
# for — both of those are `kolonie-docs#150`'s lesson from the check next door:
# GitHub's issue index is eventually consistent, an issue filed a moment ago is
# not findable yet, and a run that exits while its own issue is invisible is how
# the next run files a duplicate. The guard is code, which `#133` asks for.
existing_issue() {
  gh issue list --repo "$GITHUB_REPOSITORY" --state open --label area:docs --limit 100 \
    --json number,title --jq "[.[] | select(.title == \"$TITLE\")][0].number // empty"
}

VISIBILITY_ATTEMPTS=${VISIBILITY_ATTEMPTS:-30}
VISIBILITY_POLL=${VISIBILITY_POLL:-2}

await_visible() {
  local attempt=0 seen
  while [ "$attempt" -lt "$VISIBILITY_ATTEMPTS" ]; do
    seen=$(existing_issue)
    if [ -n "$seen" ]; then
      echo "findable as #$seen after $((attempt * VISIBILITY_POLL))s"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep "$VISIBILITY_POLL"
  done
  echo "::warning::the issue just filed was still not findable after $((VISIBILITY_ATTEMPTS * VISIBILITY_POLL))s — the next run may file a duplicate"
  return 1
}

# **Evidence first, judgement last, and that order is a requirement rather than a
# preference** (`#133`). Whoever opens this at 08:00 should be able to disagree
# with the model without re-running a single query.
cmd_report() {
  local dir="$1" body judgement
  if [ -s "$dir/judgement.md" ]; then
    judgement=$(cat "$dir/judgement.md")
  else
    judgement="_No judgement was written — the model was not called or did not answer. The numbers above stand on their own, and the silent-service check that produced them needs no model._"
  fi

  body=$(printf '%s\n\n---\n\n### What the model makes of it\n\n%s\n\n---\n\n%s\n\n%s\n' \
    "$(cat "$dir/numbers.md")" \
    "$judgement" \
    "[Full run](${RUN_URL:-no run url})" \
    "Filed by \`watch-agent.yml\`, which reads the previous day out of Loki once a day. It is silent when nothing is wrong, and it reuses this issue rather than opening a second. It never closes one: whether this is dealt with is a person's call, not a workflow's.")

  local existing
  existing=$(existing_issue)
  if [ -n "$existing" ]; then
    gh issue comment "$existing" --repo "$GITHUB_REPOSITORY" --body "$body"
    echo "commented on #$existing"
  else
    gh issue create --repo "$GITHUB_REPOSITORY" --title "$TITLE" \
      --label p1 --label area:docs --body "$body"
    await_visible
  fi
}

case "${1:-gather}" in
  gather) shift; cmd_gather "${1:?usage: watch-agent.sh gather <dir>}" ;;
  decide) shift; cmd_decide "${1:?usage: watch-agent.sh decide <dir>}" ;;
  report) shift; cmd_report "${1:?usage: watch-agent.sh report <dir>}" ;;
  *) echo "usage: watch-agent.sh gather|decide|report <dir>" >&2; exit 2 ;;
esac

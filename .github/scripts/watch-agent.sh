#!/bin/bash
# The Watch Agent's deterministic half: read yesterday out of Loki, say what it
# saw, and file when a service has gone silent. `kolonie-docs#133`, split by
# `kolonie-docs#165`.
#
# Usage:
#   watch-agent.sh gather <dir>   # run the queries, write the numbers, exit 2 if Loki is unreachable
#   watch-agent.sh summary <dir>  # the day's narrative, for the run's own output
#   watch-agent.sh decide <dir>   # exit 1 if a service has gone silent
#   watch-agent.sh report <dir>   # one issue per silent service
#
# ## Two jobs, and they wanted opposite things (`#165`)
#
# | | Wants |
# |---|---|
# | *Here is yesterday's shape* | daily, narrative, no action implied, never urgent |
# | *Something is broken now* | minutes not hours, one issue per defect, closeable |
#
# This served the first and filed it in the shape of the second: **one issue,
# forever, every finding a comment on it** — unrelated defects weeks apart on a
# thread that never closes. That is the chronicle failure `AGENTS.md` §2 names,
# one level up: *"a file that is appended to and never rewritten is a
# chronicle"*. Nobody could pick it up, because it was not a piece of work.
#
# So the narrative is now **the run's own output** and files nothing, and the
# alarm — a service that has stopped logging — files **one issue per service**,
# closeable, with the service's name in the title rather than a fixed string.
#
# **The model's judgement no longer files anything.** It is still asked, still
# daily, still cheap, and it is read in the run summary. What replaced it as the
# path from *an error appeared* to *an issue exists* is the log detector in
# `kolonie-platform#407`, which ticks every half hour instead of once a day and
# files per signature. This split was blocked on that existing, deliberately:
# removing the alarm half first would have left the Colony with less than it had.
#
# **Silence is still the healthy state.** There is no daily all-clear, no issue
# on a good day and no comment on one. A quiet run is a quiet run.
#
# **Two things excuse a service from the alarm, and only two.** Both are a line
# in a file beside this one, both cover a silence the logs cannot explain, and
# both leave the service named in the report — what a list buys is that nobody
# is paged, never that something disappears.
#
# - `watch-agent-retired.txt` — **it was removed on purpose.** A service somebody
#   deleted is silent for a reason that is an intention, and `kolonie-docs#191`
#   is the morning that cost a `p1`.
# - `watch-agent-silent-by-design.txt` — **the pipeline discards what it writes.**
#   `kolonie-infra#81` drops `debug` and `info` from the log stack itself, so
#   `promtail` is permanently silent while running perfectly, and
#   `kolonie-docs#284` is the `p1` that cost. That file's header says what is
#   given up by listing a service, because it is not nothing.
#
# **Nothing else quietens this check**, and neither list may be used to stop
# hearing about something that ought to be logging.
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
# ## No threshold says how many errors are too many, deliberately
#
# Grep it: no number here answers that. A threshold per service is wrong on the
# first day and stale on the second. What the model gets instead is seven days of
# the same counts beside today's, and the question *is today normal* — which is
# the question a person would ask, and needs no maintenance.
#
# **`FALLBACK_BURST` is not a counter-example and it is worth saying why**
# (`#312`). It does not answer *how many is too many*; it answers *was this one
# event or several ordinary days*, on a signal that has no per-service baseline
# because a healthy week has none of it at all. It carries the measurement it was
# set from, and the day that measurement is stale is a day the number is wrong in
# a way somebody can see — which is the property the paragraph above is protecting.
#
# The one thing decided without the model is silence, because silence is a
# boolean and it is the signal error-watching structurally misses: a dead runner
# throws no errors.
set -uo pipefail

LOKI_URL="${LOKI_URL:-}"
LOKI_USER="${LOKI_USER:-watch}"

# The closed set `loki-event.sh` will write. The Actions lane queries only these
# streams; adding a writer is a name in both lists, and a typo here cannot mint
# a container query. Kept beside the credential so a reader sees the bound
# before any query is built (`#504`).
ACTIONS_SERVICES=(board-triage opencode-worker skill-dispatch watch-agent red-on-main board-self-check)

# One title per silent service, and the service name is the whole of the dedupe
# key (`#165`). The old fixed string is why there was one issue forever; a title
# naming the thing that is wrong is what makes each finding closeable.
title_for() {
  echo "\`$1\` has stopped logging"
}

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
  if [ -z "${LOKI_URL:-}" ]; then
    echo "Loki did not answer: LOKI_URL is not set. Neither question was asked."
    echo
    echo "This is a configuration gap and not a finding — a store that cannot be"
    echo "read reports every service as silent, which would be true and useless."
    return 2
  fi
  local ready
  ready=$(curl -sS --max-time 30 -o /dev/null -w '%{http_code}' \
            -u "$LOKI_USER:${LOKI_TOKEN:-}" "$LOKI_URL/loki/api/v1/labels" 2>/dev/null)
  [ "$ready" = "200" ] && return 0
  echo "Loki did not answer: HTTP ${ready:-no response}. Neither question was asked."
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

# --- query 2a: the gateway's fallbacks, per service and per reason ------------
# **A fallback is a `warn` by design, so nothing above sees it** (`#312`).
# `packages/core/src/llm/gateway.ts` says every one is logged *"so the gateway
# was down for two hours is answerable afterwards rather than invisible"* —
# and answerable is not the same as answered. Query 1 folds them into a number in
# a service's `warn` row and names nothing; query 2 filters `level="error"` and
# never sees them at all.
#
# **Not solved by raising the level.** A fallback is not an error: the call
# succeeded and the citizen was served, and `gateway.ts` draws that line
# deliberately against `model.route.refused`, which *is* one. Promoting the level
# to make an existing query see it would put a wrong word in every log line to
# save writing one query.
#
# Broken down by `reason`, because the four classes mean four different things —
# `unreachable`, `timeout`, `status`, `malformed`.
q_fallbacks() {
  loki /loki/api/v1/query \
    'query=sum by (service, reason) (count_over_time({job="containers", level="warn"} | json | event="model.route.fallback" [24h]))' \
    "time=$1" | jq -r '.data.result // [] | .[] | "\(.metric.service // "(none)")\t\(.metric.reason // "(none)")\t\(.value[1] | tonumber | floor)"' 2>/dev/null | sort

}

# --- query 2a-alt: what the gateway actually answered, on `status` only -------
# **`reason` names the class and `detail` names the thing** (`#328`). Measured
# 2026-08-19 against seven days of production: every one of the twelve fallbacks
# was `moderation-runner`, `reason=status`, and behind every one of them was an
# HTTP `502` or `503`. The report said *the gateway answered badly* twelve times
# and could not say which — and `502` (upstream down), `429` (we are over a
# limit) and `401` (the key is wrong) are three different mornings.
#
# **`status` only, and that restriction is not tidiness.** `gateway.ts` draws the
# line itself where it stamps the response header: *"Only an HTTP status is
# public accounting. Other details can contain"* — the `unreachable` and
# `malformed` details are free-text descriptions of an exception, unbounded in
# cardinality and not ours to publish. Grouping by `detail` across every reason
# would put an error string into a table and a label into Loki's index.
q_fallback_statuses() {
  loki /loki/api/v1/query \
    'query=sum by (service, detail) (count_over_time({job="containers", level="warn"} | json | event="model.route.fallback" | reason="status" [24h]))' \
    "time=$1" | jq -r '.data.result // [] | .[] | "\(.metric.service // "(none)")\t\(.metric.detail // "(none)")\t\(.value[1] | tonumber | floor)"' 2>/dev/null | sort
}

# --- query 2a-bis: the same, hourly, which is what the threshold reads --------
# **A burst and a trickle are different events and only the shape says which.**
# Measured over the seven days to 2026-08-12: ten fallbacks in total, nine of
# them inside one ten-minute window. A rule on the total would have fired on a
# week that was fine; a rule on a single fallback would have fired on three
# separate ordinary days. The hour is the bucket that tells them apart.
q_fallbacks_hourly() {
  loki /loki/api/v1/query_range \
    'query=sum(count_over_time({job="containers", level="warn"} | json | event="model.route.fallback" [1h]))' \
    "start=$1" "end=$2" "step=3600" \
    | jq -r '[.data.result // [] | .[] | .values[][1] | tonumber] | max // 0' 2>/dev/null
}

# --- query 2a-ter: calls that were refused outright --------------------------
# **The no-fallback path**, and the reason it is counted beside the fallbacks
# rather than left to the error queries: a quest left `pending_review` because
# the gateway was down is *a thing that did not happen*, and a thing that did not
# happen shows up as nothing at all unless it is asked for by name.
q_refusals() {
  loki /loki/api/v1/query \
    'query=sum by (service) (count_over_time({job="containers"} | json | event="model.route.refused" [24h]))' \
    "time=$1" | jq -r '.data.result // [] | .[] | "\(.metric.service // "(none)")\t\(.value[1] | tonumber | floor)"' 2>/dev/null | sort
}

# --- query 2a-quater: calls the primary gateway served ------------------------
# `model.call.completed` is written after a usable response has been read, and
# its `route` comes from the response header. Counting `route="gateway"` therefore
# says how many calls the primary actually served, rather than how many were
# attempted or how many produced any log line at all (`#561`).
q_primary_served() {
  loki /loki/api/v1/query \
    'query=sum by (service) (count_over_time({job="containers"} | json | event="model.call.completed" | route="gateway" [24h]))' \
    "time=$1" | jq -r '.data.result // [] | .[] | "\(.metric.service // "(none)")\t\(.value[1] | tonumber | floor)"' 2>/dev/null | sort
}

# --- query 2b: errors per service, over a window ------------------------------
# **The number nobody was looking at.** 674 error lines in 24 hours, measured
# 2026-08-08 across eleven services, and nothing reported them anywhere — the
# workflow read yesterday out of Loki and said only which services had gone
# *quiet*. Silence is rare; errors are continuous, and a degradation lives in
# them before it becomes an outage (`kolonie-docs#236`).
q_errors_by_service() {
  loki /loki/api/v1/query \
    "query=sum by (service) (count_over_time({job=\"containers\", level=\"error\"}[$1]))" \
    "time=$2" | jq -r '.data.result // [] | .[] | "\(.metric.service // "(none)")\t\(.value[1] | tonumber | floor)"' 2>/dev/null | sort
}

# --- query 2c: one service's error lines, for grouping by message -------------
# `q_slugs` above reads the `event` field and therefore sees only the services
# that log JSON. **Three of the four noisiest do not** — `traefik`, `postgres`
# and `loki` log prose, and they were 458 of the 650 measured on 2026-08-09. So
# the grouping has to work on the raw line as well.
q_error_lines() {
  loki /loki/api/v1/query_range \
    "query={job=\"containers\", level=\"error\", service=\"$1\"}" \
    "start=$2" "end=$3" "limit=1000" \
    | jq -r '.data.result // [] | .[] | .values[] | .[1]' 2>/dev/null
}

# **Normalise before counting, or every line is unique.** Measured by hand on
# 2026-08-09: postgres logged the same failure 177 times and no two lines were
# byte-identical — each carries a timestamp, a backend pid and a character
# offset. Grouping raw lines would have reported 177 distinct findings, which is
# the same as reporting none.
#
# Digits and hex runs collapse; the rest of the line is what says *what* went
# wrong. It is crude on purpose — a cleverer normaliser is one that can be wrong
# in a way nobody notices.
normalise_line() {
  sed -E 's/[0-9a-f]{8,}/<hex>/g; s/[0-9]+/<n>/g' | cut -c1-160
}

# --- query 2d: lines carrying no level at all ---------------------------------
# **The residue, reported where somebody sees it** (`kolonie-infra#97`). 3,211
# lines a day carried no `level`, measured 2026-08-09 — 3.7 % of everything — and
# every query in this file filters on one, so those lines are invisible to the
# only thing that reads the logs.
#
# `kolonie-infra#97` fixed the share of it that was a bug (nginx's error log) and
# named the share that genuinely cannot carry one: Postgres statement
# continuations, and npm banners at startup. **What was missing was the
# measurement**, which is this: a number that appears once a day is a number that
# gets fixed, and one that needs somebody to think of the question is not.
q_unlevelled_by_service() {
  loki /loki/api/v1/query \
    "query=sum by (service) (count_over_time({job=\"containers\"} | level=\"\" [24h]))" \
    "time=$1" | jq -r '.data.result // [] | .[] | "\(.metric.service // "(no service label)")\t\(.value[1] | tonumber | floor)"' 2>/dev/null | sort
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

# Drop the Actions writers. Silent-service detection is about production
# containers; a board-triage that had nothing to fail on is allowed to be quiet
# (`#504`).
actions_drop() {
  grep -vxF -f <(printf '%s\n' "${ACTIONS_SERVICES[@]}") || :
}

actions_selector() {
  local IFS='|'
  printf '%s' "${ACTIONS_SERVICES[*]}"
}

# --- query A: Actions events, yesterday and the same history window -----------
# A separate lane, not a widening of `job="containers"`. The push path labels
# only `service` and `level`; `reason` lives in the JSON line, which is the
# low-cardinality field the model is shown. Aggregated inside Loki, so no raw
# line ever reaches `numbers.md` (`#504`).
q_actions_today() {
  loki /loki/api/v1/query \
    "query=sum by (service, level, reason) (count_over_time({service=~\"$(actions_selector)\"} | json [24h]))" \
    "time=$NOW"
}

q_actions_history() {
  loki /loki/api/v1/query_range \
    "query=sum by (service, level, reason) (count_over_time({service=~\"$(actions_selector)\"} | json [24h]))" \
    "start=$WEEK_AGO" "end=$NOW" "step=86400"
}

# --- services that were removed on purpose ------------------------------------
# **A retired service and a dead one are the same measurement.** Both logged last
# week and nothing yesterday, and no query distinguishes them, because the
# difference between the two is an intention. So the intention is written down,
# once, by whoever removed the service.
#
# **This is not the configured list of services refused above**, and the
# distinction is the whole of why it is allowed to exist. That one would be a list
# of what ought to be running: wrong the first time a service is added, and a file
# somebody has to remember to edit on the day nothing is wrong. This is a list of
# removals. Its normal state is empty, an entry is only ever appended by the
# change that takes a service away, and the two failures are not comparable —
# a missing entry here costs one issue closed with a sentence, while a wrongly
# quietened service costs an outage nobody is told about.
#
# `kolonie-docs#191` is the day this was needed: `umami` was reverted on
# 2026-08-06 and filed as a `p1` the next morning, correctly by the rule and
# wrongly in fact.
RETIRED_FILE="${WATCH_RETIRED_FILE:-$(dirname "${BASH_SOURCE[0]}")/watch-agent-retired.txt}"

# Field one only. The rest of the line is a date and a reason for whoever reads
# the file, and a reason routinely contains a `#` — so comments are recognised by
# a line beginning with one, never by stripping from the middle.
retired_services() {
  [ -r "$RETIRED_FILE" ] || return 0
  awk '!/^[[:space:]]*#/ && NF { print $1 }' "$RETIRED_FILE" | sort -u
}

# An entry older than the window it suppresses inside is doing nothing: the
# service has by then logged nothing for seven days either, so the check has
# stopped considering it at all. Said in the run log rather than left for the file
# to silt up — dates compare as strings because both are ISO.
retired_stale() {
  [ -r "$RETIRED_FILE" ] || return 0
  awk -v cutoff="$(date -u -d "@$WEEK_AGO" +%Y-%m-%d 2>/dev/null)" \
    'cutoff != "" && !/^[[:space:]]*#/ && NF >= 2 && $2 < cutoff {
       printf "%s was retired on %s, before the seven-day window this check reads. Its line in %s no longer suppresses anything and can be deleted.\n", $1, $2, FILENAME }' \
    "$RETIRED_FILE"
}

# --- services the pipeline silences on purpose ---------------------------------
# **A third category, and it is neither of the two above** (`kolonie-docs#284`).
# `promtail` was filed as a `p1` for having logged nothing in 24 hours, against a
# shipper that was running, healthy, and tailing every file on the host. Its
# lines never reached Loki because `kolonie-infra#81` drops `debug` and `info`
# from the log stack itself at ingestion — merged 2026-08-05 17:27, which is the
# hour the series stops.
#
# **The measurement was right and the question was wrong.** A dead runner and a
# runner whose output is discarded are the same silence from inside Loki, exactly
# as a dead runner and a retired one are. The difference is again not in the
# logs: there it is an intention, here it is a rule in another repository's
# pipeline.
#
# **Not an entry in the retired list**, which was the obvious move and is wrong
# in three ways: an entry there expires after seven days and this condition does
# not, that file's normal state is empty and this one's is not, and it records
# something done to a *service* rather than something true of the *pipeline*.
# The file's own header carries the rest, including the one thing given up.
SILENT_FILE="${WATCH_SILENT_FILE:-$(dirname "${BASH_SOURCE[0]}")/watch-agent-silent-by-design.txt}"

silent_by_design() {
  [ -r "$SILENT_FILE" ] || return 0
  awk '!/^[[:space:]]*#/ && NF { print $1 }' "$SILENT_FILE" | sort -u
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
  comm -23 <(q_service_values "$WEEK_AGO" "$NOW" | actions_drop) \
           <(q_service_values "$DAY_AGO" "$NOW" | actions_drop) \
    > "$dir/quiet.txt"

  # The split is written to the directory rather than inferred later from what is
  # missing, so a run's own working files answer *which quiet services were not
  # reported, and why* without re-reading the retired list.
  comm -12 "$dir/quiet.txt" <(retired_services) > "$dir/retired.txt"
  comm -23 "$dir/quiet.txt" <(retired_services) > "$dir/silent.txt"

  # The same split again, against the pipeline's own drops. Done second and
  # against what the retired split left, so a service in both files is reported
  # once and under the older reason rather than twice.
  comm -12 "$dir/silent.txt" <(silent_by_design) > "$dir/by-design.txt"
  comm -23 "$dir/silent.txt" <(silent_by_design) > "$dir/silent.next"
  mv "$dir/silent.next" "$dir/silent.txt"

  retired_stale >&2

  # --- the errors, which are the larger half (`#236`) ------------------------
  #
  # Three files, and they are separate because they answer different questions:
  # what happened today, what normally happens, and what today's looked like.
  q_errors_by_service 24h "$NOW"  > "$dir/errors-today.tsv"
  q_unlevelled_by_service "$NOW"  > "$dir/unlevelled.tsv"

  # **The baseline is the seven days before today, per service, per day.** Not a
  # global threshold: `traefik` at 221 errors a day and `badge-runner` at 0 do
  # not share one, and a number that fits both would either drown in the first or
  # never fire for the second. Measured 2026-08-09.
  q_errors_by_service 7d "$DAY_AGO" \
    | awk -F'\t' '{ printf "%s\t%.2f\n", $1, $2 / 7 }' > "$dir/errors-baseline.tsv"

  # The grouped messages, for the services that had any. Capped at the noisiest
  # few: a summary that lists everything is one nobody finishes.
  : > "$dir/errors-grouped.md"
  while IFS=$'\t' read -r service count; do
    [ -n "$service" ] || continue
    [ "$count" -gt 0 ] || continue
    {
      printf '\n**`%s`** — %s error lines:\n\n' "$service" "$count"
      q_error_lines "$service" "$DAY_AGO" "$NOW" \
        | normalise_line | sort | uniq -c | sort -rn | head -5 \
        | sed -E 's/^ *([0-9]+) /- **\1×** `/; s/$/`/'
    } >> "$dir/errors-grouped.md"
  done < <(sort -t$'\t' -k2 -rn "$dir/errors-today.tsv" | head -6)

  # The strings never seen before today, which is the third trigger. Compared
  # against the six days *before* yesterday so that a string introduced yesterday
  # and repeated today is not "new" twice.
  : > "$dir/errors-new-strings.txt"
  while IFS=$'\t' read -r service count; do
    [ -n "$service" ] || continue
    [ "$count" -gt 0 ] || continue
    comm -23 \
      <(q_error_lines "$service" "$DAY_AGO" "$NOW" | normalise_line | sort -u) \
      <(q_error_lines "$service" "$WEEK_AGO" "$DAY_AGO" | normalise_line | sort -u) \
      | sed "s|^|$service\t|" >> "$dir/errors-new-strings.txt"
  done < <(sort -t$'\t' -k2 -rn "$dir/errors-today.tsv" | head -6)

  # The rehearsal's fabricated silent service, and it belongs **here** rather
  # than in the workflow step after `gather` has run. Appended afterwards it
  # reached `decide` but not `numbers.md`, so the first rehearsal filed an issue
  # that said "Services that logged nothing: None." — a report contradicting the
  # reason it was written. Measured on 2026-08-04 against `kolonie-docs#156`.
  #
  # Injected at this point it takes exactly the path a real silent service takes,
  # which is the only version of a rehearsal worth having.
  [ -n "${WATCH_FORCE_SILENT:-}" ] && echo "$WATCH_FORCE_SILENT" >> "$dir/silent.txt"

  # --- what the gateway did, which is a `warn` and therefore invisible above ---
  q_fallbacks "$NOW" > "$dir/fallbacks.tsv"
  q_fallback_statuses "$NOW" > "$dir/fallback-statuses.tsv"
  q_refusals  "$NOW" > "$dir/refusals.tsv"
  q_primary_served "$NOW" > "$dir/served.tsv"
  q_fallbacks_hourly "$DAY_AGO" "$NOW" > "$dir/fallback-peak.txt"

  # The rehearsal reaches this the same way it reaches a silent service, and for
  # the same reason: injected here it takes the path a real burst takes, which is
  # the only version of a rehearsal worth having.
  if [ -n "${WATCH_FORCE_FALLBACKS:-}" ]; then
    printf 'a-service-that-does-not-exist\tstatus\t%s\n' "$WATCH_FORCE_FALLBACKS" >> "$dir/fallbacks.tsv"
    echo "$WATCH_FORCE_FALLBACKS" > "$dir/fallback-peak.txt"
  fi

  q_hourly > "$dir/hourly.json"
  q_slugs  > "$dir/slugs.json"
  # Seven days of the same counts, one point per day. This is what replaces a
  # threshold: the model is shown last week beside today and asked whether today
  # is unusual, rather than asked to compare today against a number somebody
  # guessed once.
  loki /loki/api/v1/query_range \
    'query=sum by (service, level) (count_over_time({job="containers", level=~"error|warn"}[24h]))' \
    "start=$WEEK_AGO" "end=$NOW" "step=86400" > "$dir/history.json"

  q_actions_today > "$dir/actions-today.json"
  q_actions_history > "$dir/actions-history.json"
  jq -r '.data.result // [] | .[]
         | select((.value[1] | tonumber) > 0)
         | [(.metric.service // "«unlabelled»"), (.metric.level // ""),
            (.metric.reason // "«no reason»"), (.value[1] | tonumber | floor)]
         | @tsv' "$dir/actions-today.json" 2>/dev/null | sort -k4 -rn > "$dir/actions-today.tsv" || :

  {
    echo "### Errors and warnings per service, last 24 hours"
    echo
    # "most in one hour" and not "peak hour": both columns are counts, and a
    # column named for a time of day that holds a count is the same class of
    # mislabelling as the dates below.
    echo "| service | level | total | most in one hour |"
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
    # **Printed whether or not it is zero** (`#312`). *The gateway served
    # everything yesterday* is the sentence that makes a non-zero day legible —
    # a section that appears only on a bad day is one a reader has no baseline
    # for, and its absence is indistinguishable from the query having broken.
    echo "### The LLM gateway, last 24 hours"
    echo
    if [ -s "$dir/fallbacks.tsv" ]; then
      echo "| service | reason | fell back to OpenRouter |"
      echo "|---|---|---|"
      awk -F'\t' '{printf "| `%s` | `%s` | %s |\n", $1, $2, $3}' "$dir/fallbacks.tsv"
      echo
      echo "Most in one hour: **$(cat "$dir/fallback-peak.txt" 2>/dev/null || echo 0)**."
      # **Only when there is one** (`#328`). A day whose fallbacks were all
      # `timeout` has no status to print, and an empty table under a heading
      # reads as a query that broke rather than as a class that did not occur.
      if [ -s "$dir/fallback-statuses.tsv" ]; then
        echo
        echo "What the gateway answered, where it answered at all:"
        echo
        echo "| service | status | count |"
        echo "|---|---|---|"
        awk -F'\t' '{printf "| `%s` | `%s` | %s |\n", $1, $2, $3}' "$dir/fallback-statuses.tsv"
      fi
    else
      echo "The gateway served everything — no call fell back to OpenRouter."
    fi
    echo
    if [ -s "$dir/served.tsv" ]; then
      echo "Calls served by the primary gateway: **$(awk -F'\t' '{ total += $2 } END { print total + 0 }' "$dir/served.tsv")**."
    else
      echo "Calls served by the primary gateway: **0**."
    fi
    echo
    if [ -s "$dir/refusals.tsv" ]; then
      echo "Calls **refused outright**, with no fallback — work that did not happen:"
      echo
      awk -F'\t' '{printf "- `%s` — %s\n", $1, $2}' "$dir/refusals.tsv"
    else
      echo "No call was refused outright."
    fi
    echo
    echo "### Services that logged nothing in 24 hours, having logged in the last 7 days"
    echo
    if [ -s "$dir/silent.txt" ]; then
      sed 's/^/- `/; s/$/`/' "$dir/silent.txt"
    else
      echo "None."
    fi
    # **Suppressed is not hidden.** A retired service is still quiet and still
    # measured; what the retired list buys is that nobody is paged for it. Naming
    # it here is what stops the list from becoming a place things disappear into.
    if [ -s "$dir/retired.txt" ]; then
      echo
      echo "Quiet and **not reported**, because they were removed on purpose"
      echo "(\`.github/scripts/watch-agent-retired.txt\` says by whom and when):"
      echo
      sed 's/^/- `/; s/$/`/' "$dir/retired.txt"
    fi
    # Named for the same reason the retired ones are: a service this check has
    # stopped being able to speak about should be visible in the place the check
    # reports, not only in a file somebody has to think to open.
    if [ -s "$dir/by-design.txt" ]; then
      echo
      echo "Quiet and **not reported**, because the pipeline drops what they"
      echo "ordinarily write (\`.github/scripts/watch-agent-silent-by-design.txt\`"
      echo "names the rule, and what is given up by listing them):"
      echo
      sed 's/^/- `/; s/$/`/' "$dir/by-design.txt"
    fi
    # **The error volume per service, every day, whether or not anything is
    # filed** (`#236`). That alone turns 674 from invisible into a number
    # somebody sees, and it costs one query.
    echo
    echo "### Errors per service, last 24 hours"
    echo
    if [ -s "$dir/errors-today.tsv" ]; then
      echo "| Service | Errors | Its own daily normal, previous 7 days |"
      echo "|---|---:|---:|"
      sort -t"$(printf '\t')" -k2 -rn "$dir/errors-today.tsv" | while IFS=$'\t' read -r service count; do
        base=$(awk -F'\t' -v s="$service" '$1 == s { print $2 }' "$dir/errors-baseline.tsv")
        printf '| `%s` | %s | %s |\n' "$service" "$count" "${base:-0}"
      done
      echo
      echo "**Total: $(awk -F'\t' '{ t += $2 } END { print t + 0 }' "$dir/errors-today.tsv").**"
      echo "A number that appears once a day is a number that gets fixed; one that"
      echo "needs somebody to think of the question is not."
    else
      echo "No service logged an error in the last 24 hours."
    fi

    # `kolonie-infra#97` step 3, in as many words: *report the residue where
    # somebody sees it.*
    echo
    echo "### Lines carrying no level at all"
    echo
    if [ -s "$dir/unlevelled.tsv" ]; then
      awk -F'\t' '{ printf "- `%s` — %s\n", $1, $2; t += $2 } END { printf "\n**%d in the last 24 hours.**\n", t + 0 }' \
        "$dir/unlevelled.tsv"
      echo
      echo "Every query above filters on \`level\`, so these are invisible to all of"
      echo "them. Some legitimately cannot carry one — Postgres statement"
      echo "continuations are the body of a record whose first line is already"
      echo "labelled, and npm banners are output rather than events."
      echo "\`promtail/promtail.yml\` stage 5d names them and says why."
      echo "**A number that moves here is worth a look**: it means either a new"
      echo "log shape nothing recognises, or an incident dragging continuation"
      echo "lines behind it."
    else
      echo "None: every line in the last 24 hours carried a level."
    fi

    if [ -s "$dir/errors-grouped.md" ]; then
      echo
      echo "### What those errors actually were"
      echo
      echo "**Grouped by message, not by line** — six hundred repetitions of one"
      echo "failure is one finding, and the count is the part that says how bad it"
      echo "is. Digits and hex runs are collapsed before grouping, because no two"
      echo "of those 177 postgres lines were byte-identical."
      cat "$dir/errors-grouped.md"
    fi

    echo
    echo "### The same counts per day, over as much history as the store holds"
    echo
    # **How many days this actually covers is stated, and every value carries its
    # date.** Rendered as bare numbers it did real damage on the first run: Loki
    # had been installed an hour earlier, the table held a single bucket showing
    # `1`, and the model read it as *"1 per day for the past 7 days"* — a
    # confident weekly baseline invented out of one hour. The model read what it
    # was given correctly; the table was the lie.
    #
    # A window is asked for, not promised. Nothing here can make history exist
    # that was never recorded, so the honest move is to say how much there is.
    days=$(jq -r '[.data.result // [] | .[] | .values[][0]] | unique | length' "$dir/history.json" 2>/dev/null)
    echo "Asked for 7 days. The store answered with **${days:-0}** daily bucket(s) — anything"
    echo "less than 7 means Loki has not been collecting for that long, and no baseline"
    echo "older than the earliest date below exists."
    echo
    echo "| service | level | count per day, oldest first |"
    echo "|---|---|---|"
    # **The step is subtracted, and that is not an off-by-one.** Loki aligns a
    # range query's steps to absolute epoch multiples and stamps each sample with
    # the **end** of the window it covers — so today's `[24h]` bucket comes back
    # stamped midnight *tomorrow*. Printed raw it labelled today's counts with
    # tomorrow's date, which is a worse lie than the bare number it replaced.
    # Measured 2026-08-04: one bucket at 1785888000, `2026-08-05T00:00:00Z`,
    # holding data written on the 4th.
    jq -r --argjson step 86400 '.data.result // [] | .[]
           | [(.metric.service // "«unlabelled»"), .metric.level,
              ([.values[] | "\((.[0] - $step) | gmtime | strftime("%Y-%m-%d")): \(.[1])"] | join(" · "))]
           | @tsv' "$dir/history.json" 2>/dev/null \
      | sort | awk -F'\t' '{printf "| `%s` | %s | %s |\n", $1, $2, $3}'

    echo
    echo "### GitHub Actions events"
    echo
    if [ -s "$dir/actions-today.tsv" ]; then
      echo "A separate lane from the container counts above. A red run and a"
      echo "green-but-no-work event are distinct; presence is not automatically"
      echo "abnormal. Judge these against their own history, not against production."
      echo
      echo "| service | level | reason | yesterday |"
      echo "|---|---|---|---:|"
      awk -F'\t' '{printf "| `%s` | %s | `%s` | %s |\n", $1, $2, $3, $4}' "$dir/actions-today.tsv"
      echo
      echo "The same counts per day, over as much history as the store holds:"
      echo
      echo "| service | level | reason | count per day, oldest first |"
      echo "|---|---|---|---|"
      jq -r --argjson step 86400 '.data.result // [] | .[]
             | [(.metric.service // "«unlabelled»"), (.metric.level // ""),
                (.metric.reason // "«no reason»"),
                ([.values[] | "\((.[0] - $step) | gmtime | strftime("%Y-%m-%d")): \(.[1])"] | join(" · "))]
             | @tsv' "$dir/actions-history.json" 2>/dev/null \
        | sort | awk -F'\t' '{printf "| `%s` | %s | `%s` | %s |\n", $1, $2, $3, $4}'
    else
      echo "None."
    fi
  } > "$dir/numbers.md"

  cat "$dir/numbers.md"
}

# --- the day's narrative ------------------------------------------------------
# **The output of this workflow, and not an issue** (`#165`). A daily report that
# never resolves is not work: it is a description of yesterday, and the place for
# a description of yesterday is the run that produced it.
#
# The model's opinion is here too, for the same reason it was kept at all — *is
# today normal* is a question no threshold answers, and `#133` was right that no
# number belongs in this file. What changed is where the answer goes.
cmd_summary() {
  local dir="$1"

  cat "$dir/numbers.md"
  echo
  echo "### What the model makes of it"
  echo
  if [ -s "$dir/judgement.md" ]; then
    cat "$dir/judgement.md"
  else
    echo "_No judgement was written — the model was not called or did not answer. The numbers"
    echo "above were measured rather than judged and stand on their own._"
  fi
  echo
  echo "---"
  echo
  echo "This is a description of yesterday and files nothing. A defect that needs acting on"
  echo "becomes its own issue: a service that has stopped logging is filed by this workflow,"
  echo "and an error in the logs is filed by the detector in \`kolonie-platform#407\`, which"
  echo "ticks every half hour rather than once a day."
}

# --- the decision -------------------------------------------------------------
# **One input, and it is the one no model can answer** (`#165`): a service that
# has stopped logging. A dead runner throws no errors, so a detector reading
# errors cannot see it — which is exactly why `#133` made this half
# deterministic and separate, and why it is the alarm this workflow keeps.
#
# The model's verdict is **not** an input any more. It used to be, and it filed
# onto the eternal issue; what replaced it is `kolonie-platform#407`, which sees
# the same errors every half hour and files one issue per signature. A daily
# model opinion filing a daily issue would now be a second, worse copy of that.
# **File on a change of shape, never on a threshold** (`#236`). A threshold on
# absolute count would file every day and be ignored inside a week, which is the
# same failure `#237` was about one level up — and it is why nothing in this file
# holds a number of errors that means "bad".
#
# Three shapes are worth an issue, and each is measured against the service's own
# history rather than against a global figure:
#
#   1. a service that produced NO errors yesterday and many today
#   2. an error volume several times its own recent normal
#   3. an error string never seen in the retained window
#
# `traefik` at 221 a day and `badge-runner` at 0 do not share a baseline, and a
# global rule would either drown in the first or never fire for the second.
ERROR_SPIKE_FACTOR=${ERROR_SPIKE_FACTOR:-5}
ERROR_FLOOR=${ERROR_FLOOR:-10}

# **The one threshold in this file, and it is written down with what it was set
# from** (`#312`).
#
# The gateway falling back is not an error and does not belong to the shape rules
# above: it is a `warn`, it means the citizen *was* served, and there is no
# per-service baseline to compare it against because a healthy week has none at
# all.
#
# Measured over the seven days to 2026-08-12: **ten fallbacks in total, nine of
# them inside one ten-minute window** — the gateway answering 502 and 503 between
# 07:35 and 07:45 UTC, across `support-triage-runner` and `verifier-runner`, plus
# a tenth in `moderation-runner` the night before. Everything kept working, which
# is the fallback doing its job, and nobody noticed until the next morning.
#
# So: five in one hour. On that week it fires exactly once, on the burst, and
# says nothing on the three days that carried one fallback each. A rule on a
# single fallback would have filed three times and taught nobody anything; a rule
# on the daily total would have needed to be under ten to catch the burst, and
# then the three ordinary days would have been under it by luck.
#
# **Both queries were run against production before this was set**, because a
# LogQL expression that does not parse returns nothing and is indistinguishable
# from a good week — which is the exact failure this issue is about. Asked on
# 2026-08-12 over the preceding seven days: fourteen fallbacks, every one
# `reason=status`, across `moderation-runner`, `support-triage-runner` and
# `verifier-runner` — and **a maximum of nine in any one hour**. So this fires on
# that hour and on nothing else in the week.
FALLBACK_BURST=${FALLBACK_BURST:-5}

# **A refusal is not a fallback and does not share its threshold.** Nothing was
# served: `model.route.refused` is the moderation runner's path with no plan B,
# so one of them is one piece of work that did not happen and nobody was told.
# One is enough to say out loud.
REFUSAL_FLOOR=${REFUSAL_FLOOR:-1}

# The floor is not a threshold on badness — it is a guard against arithmetic on
# tiny numbers. A service that normally logs 1 error and logs 6 today is 6× its
# baseline and is still nothing. Without it the shape rules fire on noise and the
# channel is dead in a fortnight, which is the outcome this whole issue exists to
# avoid.
cmd_errors_changed() {
  local dir="$1" found=0 service count base

  # 0 means *something changed shape*, as a predicate should. The early-out has
  # to say the opposite: no data is not a finding, and returning 0 here reported
  # "an error volume changed shape" on a day with no errors at all.
  : > "$dir/errors-changed.tsv"
  [ -s "$dir/errors-today.tsv" ] || return 1

  while IFS=$'\t' read -r service count; do
    [ -n "$service" ] || continue
    base=$(awk -F'\t' -v s="$service" '$1 == s { print $2 }' "$dir/errors-baseline.tsv")
    base=${base:-0}

    [ "$count" -ge "$ERROR_FLOOR" ] || continue

    if awk -v b="$base" 'BEGIN { exit !(b == 0) }'; then
      printf '%s\t%s\tnone in the previous 7 days, %s today\n' "$service" "$count" "$count"
      found=1
    elif awk -v c="$count" -v b="$base" -v f="$ERROR_SPIKE_FACTOR" 'BEGIN { exit !(c > b * f) }'; then
      printf '%s\t%s\t%s today against a daily normal of %s\n' "$service" "$count" "$count" "$base"
      found=1
    fi
  done < "$dir/errors-today.tsv" > "$dir/errors-changed.tsv"

  if [ -s "$dir/errors-new-strings.txt" ]; then
    found=1
  fi

  return $((1 - found))
}

# **Was the Colony served by its second choice yesterday?** (`#312`)
#
# 0 means *yes, and it is worth saying* — a predicate, like `cmd_errors_changed`
# beside it, and the early-out has to say the opposite: a day with no fallback
# produces no finding, which is the rejection case the issue names.
#
# Two triggers, and they are separate because they are different claims: a burst
# of fallbacks means the gateway was down and everything still worked, and a
# refusal means something did not happen at all.
# **The two numbers, read in one place** (`#351`). The predicate below and the
# report beside it each had their own copy, which was survivable while the only
# question was *file or not*. It stops being survivable the moment the finding
# can also close itself: the condition and its end have to be the same
# measurement read twice, and two copies of the arithmetic are two places for a
# second threshold to appear. A rule that filed at 5 and closed at 4 would flap
# forever on a gateway sitting at 4.
gateway_numbers() {
  local dir="$1" total peak served refusals

  total=$(awk -F'\t' '{ total += $3 } END { print total + 0 }' "$dir/fallbacks.tsv" 2>/dev/null)
  total=${total:-0}

  peak=$(cat "$dir/fallback-peak.txt" 2>/dev/null || echo 0)
  case "$peak" in ''|*[!0-9]*) peak=0 ;; esac

  served=$(awk -F'\t' '{ total += $2 } END { print total + 0 }' "$dir/served.tsv" 2>/dev/null)
  served=${served:-0}

  refusals=$(awk -F'\t' '{ total += $2 } END { print total + 0 }' "$dir/refusals.tsv" 2>/dev/null)
  refusals=${refusals:-0}

  printf '%s\t%s\t%s\t%s\n' "$total" "$peak" "$served" "$refusals"
}

cmd_gateway_wobbled() {
  local total peak served refusals

  IFS=$'\t' read -r total peak served refusals < <(gateway_numbers "$1")

  [ "$peak" -ge "$FALLBACK_BURST" ] && return 0
  [ "$refusals" -ge "$REFUSAL_FLOOR" ] && return 0
  return 1
}

report_gateway_finding() {
  local dir="$1" total peak served refusals body_file found

  IFS=$'\t' read -r total peak served refusals < <(gateway_numbers "$dir")

  if [ "$total" -eq 0 ] && [ "$refusals" -eq 0 ]; then
    bash "$FINDING" resolve gateway-not-serving \
      "**Condition cleared.** In the last 24 hours there were **0 fallback(s)**, **$served call(s) served by the primary**, and **0 call(s) were refused**."
    return 0
  fi

  found=$(bash "$FINDING" find gateway-not-serving)
  if ! cmd_gateway_wobbled "$dir" && [ -z "$found" ]; then
    return 0
  fi

  body_file=$(mktemp)
  {
    if [ "$peak" -ge "$FALLBACK_BURST" ]; then
      printf '%s\n\n' "The LLM gateway stopped answering and the Colony was served by **OpenRouter** instead — **$peak fallbacks in one hour**, against a threshold of $FALLBACK_BURST."
      printf '%s\n\n' "**Everything kept working, which is the fallback doing its job.** This is not an outage report; it is the sentence that was missing on 2026-08-12, when nine fallbacks in ten minutes were found the next morning by somebody reading an accounting line under an issue body and asking why a support ticket had been judged by the wrong model."
    fi

    if [ "$refusals" -ge "$REFUSAL_FLOOR" ]; then
      printf '%s\n\n' "**$refusals call(s) were refused outright**, with no fallback to fall back to. That is work that did not happen — a quest left \`pending_review\` because the gateway was down looks like nothing at all from every other query here."
    fi

    printf '%s\n\n' "**The threshold is a burst and not a total**, and it was set from a measurement rather than chosen: over the seven days to 2026-08-12 there were ten fallbacks, nine of them inside one ten-minute window. A rule on a single fallback would have fired on three ordinary days and taught nobody anything."
    printf '%s\n\n' "$(cat "$dir/numbers.md" 2>/dev/null)"
    printf '[Full run](%s)\n\n' "${RUN_URL:-no run url}"
    bash "$FINDING" footer gateway-not-serving \
      "the gateway not serving the Colony for some part of a day — that condition, not which service noticed it or how many calls it was" \
      "watch-agent.yml"
  } > "$body_file"

  bash "$FINDING" place gateway-not-serving \
    "The Colony was served by its second-choice provider" \
    "$body_file" --still \
    "In the last 24 hours there were **$total fallback(s) across all services**, **$served call(s) served by the primary**, and **$refusals call(s) refused**." \
    p2 area:infra from:watcher
  rm -f "$body_file"
}

cmd_decide() {
  local dir="$1" why=()

  [ -s "$dir/silent.txt" ] && why+=("a service has gone silent")
  cmd_errors_changed "$dir" && why+=("an error volume changed shape")
  cmd_gateway_wobbled "$dir" && why+=("the gateway was not serving")

  if [ ${#why[@]} -gt 0 ]; then
    printf '%s\n' "${why[@]}"
    return 1
  fi
  echo "nothing to report"
  return 0
}

# **What `level=error` means for a service that writes access logs** (`#243`).
#
# Not every service on this stack earns the label the same way, and for three of
# them it is not a level the service wrote at all. `kolonie-infra`'s promtail
# pipeline, stage 5b, derives it from the HTTP status on a Common Log Format
# line: **`5xx` is `error`, `4xx` is `info`** — and traefik's own logfmt lines,
# which do carry a level, are read first.
#
# So an error-volume finding about one of these is never a fault of the proxy's.
# It is *somebody behind it answering 500*, counted a second time at the edge.
#
# **`#243` is what this sentence costs when it is missing.** traefik logged 227
# error lines against a normal of 9.57 and was filed as a finding of its own;
# 179 of them were `GET /v1/swarm`, and `#241` reports the api logging 180 error
# lines on the same route in the same window. One event, two issues, and the
# triage pass then guessed the relationship twice — first linking the two as a
# chain, then removing the link on the grounds that nothing in one is created by
# another. Neither guess was available to a reader of the issue, because the
# issue never said what its own number meant.
#
# **It is a second record of a fact promtail owns, and that is accepted rather
# than solved.** This repository cannot read `kolonie-infra/promtail/promtail.yml`
# at runtime, and the alternative — saying nothing — is what produced `#243`. So
# it carries the date it was measured and the file it was measured from, and a
# service that stops writing CLF drops off this list rather than going wrong
# quietly: the sentence would simply stop appearing.
#
# Measured 2026-08-11 against `kolonie-infra/promtail/promtail.yml` stage 5b.
STATUS_DERIVED_LEVEL="traefik pgadmin"

# **`website` writes two log formats and only one of them is levelled by status**
# (`#327`). It is nginx, so promtail runs stage 5b over its access lines *and*
# stage 5c over its error log, which is a different file with a different shape
# and carries nginx's own severity in the line. Telling a reader that a `website`
# error means somebody behind it answered 500 is therefore true of one route and
# wrong about the other.
#
# **`#327` is what the wrong half cost.** 56 error lines against a normal of 0.29,
# every one of them stage 5c — `[error] open() ... failed` on three real assets
# that a crawler pool requested with a trailing apostrophe. The note sent the
# reader looking for the service that answered 500, and there was none: nothing
# behind nginx was involved and every one of those requests was a `404`. That is
# `#243`'s failure in the other direction — a sentence confident about a number it
# did not measure.
#
# So `website` gets its own, naming both routes and neither as the answer.
#
# Measured 2026-08-13 against `kolonie-infra/promtail/promtail.yml` stages 5b
# and 5c.
NGINX_TWO_ROUTE_LEVEL="website"

level_note_for() {
  local service="$1" one
  for one in $STATUS_DERIVED_LEVEL; do
    [ "$one" = "$service" ] || continue
    printf '%s' "**\`$service\` does not write these levels — they are derived from the HTTP status.** \`kolonie-infra\`'s promtail pipeline marks a Common Log Format line \`error\` when the response was **5xx**, and \`info\` for a \`4xx\` (measured 2026-08-11, stage 5b). So this count is not a fault of \`$service\`: it is how many times something behind it answered 500, counted at the edge. **Expect a matching finding for whichever service actually failed**, and read the two as one event rather than as two. \`$service\`'s own errors, when it has any, arrive as logfmt lines carrying a real \`level=\` and are included in the same count."
    return 0
  done
  for one in $NGINX_TWO_ROUTE_LEVEL; do
    [ "$one" = "$service" ] || continue
    printf '%s' "**\`$service\` is nginx, and two different rules can put \`error\` on one of its lines — check which before reading anything into the count.** A Common Log Format access line is levelled from the HTTP status: **5xx is \`error\`, 4xx is \`info\`** (stage 5b), so an \`error\` of that shape is something *behind* nginx answering 500 and you should expect a matching finding for it. An nginx **error-log** line — \`2026/08/12 08:53:12 [error] 31#31: ...\` — is levelled from nginx's own severity instead (stage 5c), and means only that nginx said so: a \`404\` under \`/_astro/\` writes one, and a \`404\` anywhere else on the site does not. Measured 2026-08-13 against \`kolonie-infra/promtail/promtail.yml\`. If these lines are the second kind, there is no partner service to look for — see \`kolonie-docs#327\`."
    return 0
  done
  return 1
}

FINDING="$(dirname "${BASH_SOURCE[0]}")/watch-finding.sh"

# --- reporting ----------------------------------------------------------------
# **One issue per silent service** (`#165`). Listed and filtered rather than
# searched, and then waited for — both of those are `kolonie-docs#150`'s lesson
# from the check next door: GitHub's issue index is eventually consistent, an
# issue filed a moment ago is not findable yet, and a run that exits while its
# own issue is invisible is how the next run files a duplicate. The guard is
# code, which `#133` asks for.
existing_issue() {
  local title="$1"
  gh issue list --repo "$GITHUB_REPOSITORY" --state open --label area:docs --limit 100 \
    --json number,title --jq "[.[] | select(.title == \"$title\")][0].number // empty"
}

VISIBILITY_ATTEMPTS=${VISIBILITY_ATTEMPTS:-30}
VISIBILITY_POLL=${VISIBILITY_POLL:-2}

await_visible() {
  local title="$1" attempt=0 seen
  while [ "$attempt" -lt "$VISIBILITY_ATTEMPTS" ]; do
    seen=$(existing_issue "$title")
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
# preference** (`#133`). Whoever opens this should be able to disagree without
# re-running a single query.
#
# **One issue per silent service, and the service is in the title** (`#165`). The
# old fixed title is why there was one issue forever. A service that is still
# silent tomorrow gets a comment on its own issue rather than a second one —
# which is a comment about the thing the issue is about, not an unrelated finding
# on a shared thread.
# One finding per service whose errors changed shape (`#236`), each with its own
# identity so that `#237`'s three cases apply to it — a service still spiking
# tomorrow comments rather than filing, and one that comes back reopens.
#
# **Per service, not one issue for "errors".** Two services degrading for
# unrelated reasons are two problems, and merging them produces an issue nobody
# can close.
report_error_findings() {
  local dir="$1" service count why body_file new_strings note

  [ -s "$dir/errors-changed.tsv" ] || return 0

  while IFS=$'\t' read -r service count why; do
    [ -n "$service" ] || continue
    body_file=$(mktemp)
    new_strings=$(awk -F'\t' -v s="$service" '$1 == s { print "- `" $2 "`" }' \
      "$dir/errors-new-strings.txt" 2>/dev/null | head -5)

    {
      printf '`%s` logged **%s error lines** in the last 24 hours: %s.\n\n' "$service" "$count" "$why"
      printf '%s\n\n' "**This is a change of shape, not a threshold being crossed.** Nothing here holds a number of errors that means *bad* — a fixed threshold would file every day and be ignored within a week. What triggered this is the volume against **its own** recent normal."
      # What the number means, where that is not obvious (`#243`). Printed second,
      # directly under the count, because it changes how the count is read and a
      # reader who reaches the evidence first has already formed a view.
      if note=$(level_note_for "$service"); then
        printf '%s\n\n' "$note"
      fi
      if [ -n "$new_strings" ]; then
        printf '%s\n\n%s\n\n' "**Error strings not seen in the previous 7 days:**" "$new_strings"
      fi
      if [ -s "$dir/errors-grouped.md" ]; then
        printf '%s\n' "**What the errors were, grouped by message rather than by line:**"
        cat "$dir/errors-grouped.md"
        printf '\n'
      fi
      printf '%s\n\n' "$(cat "$dir/numbers.md" 2>/dev/null)"
      printf '[Full run](%s)\n\n' "${RUN_URL:-no run url}"
      bash "$FINDING" footer "error-shape:$service" \
        "one service whose error volume changed shape — the service and that condition, not the count on any given day or which messages made it up" \
        "watch-agent.yml"
    } > "$body_file"

    bash "$FINDING" place "error-shape:$service" \
      "\`$service\` is logging errors it does not normally log" \
      "$body_file" p1 area:infra from:watcher
    rm -f "$body_file"
  done < "$dir/errors-changed.tsv"
}

cmd_report() {
  local dir="$1" service title body_file

  report_error_findings "$dir"
  report_gateway_finding "$dir"

  [ -s "$dir/silent.txt" ] || { echo "nothing silent — filing nothing"; return 0; }

  while read -r service; do
    [ -n "$service" ] || continue
    title=$(title_for "$service")
    body_file=$(mktemp)

    {
      printf '%s\n\n' "\`$service\` logged nothing in the last 24 hours, having logged at some point in the previous 7 days."
      printf '%s\n\n' "**A dead runner throws no errors**, so nothing that reads errors can see this. That is why the check is deterministic and separate, and why it is the one alarm this workflow files."
      cat "$dir/numbers.md"
      printf '\n\n[Full run](%s)\n\n' "${RUN_URL:-no run url}"
      bash "$FINDING" footer "silent-service:$service" \
        "one service that has stopped logging — the service name and that condition, not the wording or yesterday's line counts" \
        "watch-agent.yml"
    } > "$body_file"

    # `#237`: identity, then one of three behaviours. Nothing here searches by
    # title — a title carries yesterday's numbers and never matches tomorrow's.
    bash "$FINDING" place "silent-service:$service" "$title" "$body_file" p1 area:docs from:watcher
    rm -f "$body_file"
  done < "$dir/silent.txt"
}

case "${1:-gather}" in
  gather) shift; cmd_gather "${1:?usage: watch-agent.sh gather <dir>}" ;;
  summary) shift; cmd_summary "${1:?usage: watch-agent.sh summary <dir>}" ;;
  decide) shift; cmd_decide "${1:?usage: watch-agent.sh decide <dir>}" ;;
  report) shift; cmd_report "${1:?usage: watch-agent.sh report <dir>}" ;;
  *) echo "usage: watch-agent.sh gather|summary|decide|report <dir>" >&2; exit 2 ;;
esac

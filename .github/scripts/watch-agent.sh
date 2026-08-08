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
# **One thing excuses a service from the alarm, and only one**: a line in
# `watch-agent-retired.txt` beside this file, saying it was removed on purpose.
# A service somebody deleted is silent for a reason the logs cannot hold, and
# `kolonie-docs#191` is the morning that cost a `p1`. Nothing else quietens this
# check, and a retired service is still named in the report.
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
    > "$dir/quiet.txt"

  # The split is written to the directory rather than inferred later from what is
  # missing, so a run's own working files answer *which quiet services were not
  # reported, and why* without re-reading the retired list.
  comm -12 "$dir/quiet.txt" <(retired_services) > "$dir/retired.txt"
  comm -23 "$dir/quiet.txt" <(retired_services) > "$dir/silent.txt"
  retired_stale >&2

  # --- the errors, which are the larger half (`#236`) ------------------------
  #
  # Three files, and they are separate because they answer different questions:
  # what happened today, what normally happens, and what today's looked like.
  q_errors_by_service 24h "$NOW"  > "$dir/errors-today.tsv"

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

cmd_decide() {
  local dir="$1" why=()

  [ -s "$dir/silent.txt" ] && why+=("a service has gone silent")
  cmd_errors_changed "$dir" && why+=("an error volume changed shape")

  if [ ${#why[@]} -gt 0 ]; then
    printf '%s\n' "${why[@]}"
    return 1
  fi
  echo "nothing to report"
  return 0
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
  local dir="$1" service count why body_file new_strings

  [ -s "$dir/errors-changed.tsv" ] || return 0

  while IFS=$'\t' read -r service count why; do
    [ -n "$service" ] || continue
    body_file=$(mktemp)
    new_strings=$(awk -F'\t' -v s="$service" '$1 == s { print "- `" $2 "`" }' \
      "$dir/errors-new-strings.txt" 2>/dev/null | head -5)

    {
      printf '`%s` logged **%s error lines** in the last 24 hours: %s.\n\n' "$service" "$count" "$why"
      printf '%s\n\n' "**This is a change of shape, not a threshold being crossed.** Nothing here holds a number of errors that means *bad* — a fixed threshold would file every day and be ignored within a week. What triggered this is the volume against **its own** recent normal."
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

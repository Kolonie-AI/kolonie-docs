#!/bin/bash
# Does the hourly worker pick the right issue, and keep its hands off the label?
#
# Usage: bash .github/tests/opencode-worker.test.sh
#
# `kolonie-docs#142` turns on properties that a green run cannot show: that the
# ordering is deterministic, that an issue in any column but Ready is not in the
# queue, that a board write which fails stops the run *before* work starts, and
# that nothing ever removes `agent:opencode`. Each is a branch that would look
# fine in review and be wrong in production.
#
# Stubbed `gh`, for `board-self-check.test.sh`'s reason: it is the only way to
# exercise a failing board write without breaking the board. The stub logs every
# invocation, so the label assertion is exhaustive rather than a reading of the
# script — any `issue edit --remove-label` would appear in the log whatever path
# produced it.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/opencode-worker.sh"
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export GITHUB_REPOSITORY="Kolonie-AI/kolonie-docs"
export RUN_URL="https://example.invalid/run/1"

mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "search issues")     cat "$GH_FIXTURES/issues" 2>/dev/null ;;
  "run list")
    if [ -s "$GH_FIXTURES/run_list_fails" ]; then
      echo "HTTP 503: the API is having a moment" >&2
      exit 1
    fi
    cat "$GH_FIXTURES/runs" 2>/dev/null ;;
  "issue list")        cat "$GH_FIXTURES/issues" 2>/dev/null ;;
  "project item-list") cat "$GH_FIXTURES/board" 2>/dev/null ;;
  "project item-edit")
    if [ -s "$GH_FIXTURES/edit_fails" ]; then
      echo "HTTP 401: Bad credentials" >&2
      exit 1
    fi
    ;;
  *) ;;
esac
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

case_setup() {
  GH_FIXTURES="$WORK/fixtures"
  GH_LOG="$WORK/gh.log"
  export GH_FIXTURES GH_LOG
  rm -rf "$GH_FIXTURES"
  mkdir -p "$GH_FIXTURES"
  : > "$GH_LOG"
}

# `pick` prints "<owner/repo>\t<number>" since `#231` — a bare number identifies
# nothing across five repositories that each start at 1. The helper keeps the
# cases below readable rather than littering them with $'\t'.
q() {
  local number=$1 repo=${2:-Kolonie-AI/kolonie-docs}
  printf '%s\t%s' "$repo" "$number"
}

check() {
  local what=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then
    echo "  ok   $what"
  else
    echo "  FAIL $what"
    echo "         expected: $expected"
    echo "         actual:   $actual"
    FAILURES+=("$what")
  fi
}

contains() {
  local what=$1 needle=$2 haystack=$3
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  ok   $what"
  else
    echo "  FAIL $what"
    echo "         wanted to find: $needle"
    echo "         in:             $haystack"
    FAILURES+=("$what")
  fi
}

absent() {
  local what=$1 needle=$2 haystack=$3
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  ok   $what"
  else
    echo "  FAIL $what"
    echo "         did not want to find: $needle"
    FAILURES+=("$what")
  fi
}

boarded() {
  # $1.. are `number:Status[:owner/repo]` rows.
  local items=()
  for row in "$@"; do
    IFS=':' read -r number status repo <<<"$row"
    repo=${repo:-Kolonie-AI/kolonie-docs}
    items+=("{\"id\":\"ITEM_${number}\",\"status\":\"${status}\",\"content\":{\"number\":${number},\"repository\":\"$repo\"}}")
  done
  local joined
  joined=$(IFS=,; echo "${items[*]}")
  echo "{\"items\":[$joined]}" > "$GH_FIXTURES/board"
}

issued() {
  # $1.. are `number|createdAt|label,label[|owner/repo]` rows. The repository
  # defaults to `Kolonie-AI/kolonie-docs` so that the cases written before the
  # queue went organisation-wide (`#231`) still read as they did.
  local rows=()
  for row in "$@"; do
    IFS='|' read -r number created labels repo <<<"$row"
    repo=${repo:-Kolonie-AI/kolonie-docs}
    local labelJson=()
    if [ -n "$labels" ]; then
      IFS=',' read -ra names <<<"$labels"
      for name in "${names[@]}"; do labelJson+=("{\"name\":\"$name\"}"); done
    fi
    local joinedLabels
    joinedLabels=$(IFS=,; echo "${labelJson[*]}")
    rows+=("{\"number\":$number,\"createdAt\":\"$created\",\"labels\":[$joinedLabels],\"repository\":{\"name\":\"${repo#*/}\",\"nameWithOwner\":\"$repo\"}}")
  done
  local joined
  joined=$(IFS=,; echo "${rows[*]}")
  echo "[$joined]" > "$GH_FIXTURES/issues"
}

echo "the queue"

case_setup
issued
echo '{"items":[]}' > "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" pick 2>"$WORK/err"); rc=$?
check "an empty queue exits 0" "0" "$rc"
check "an empty queue picks nothing" "" "$out"
contains "an empty queue says so, rather than being silent" "nothing queued" "$(cat "$WORK/err")"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2" "11|2026-08-02T00:00:00Z|agent:opencode,p1"
boarded "10:Ready" "11:Ready"
check "p1 comes before an older p2" "$(q 11)" "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2" "11|2026-08-02T00:00:00Z|agent:opencode,p2"
boarded "10:Ready" "11:Ready"
check "at the same priority the oldest goes first" "$(q 10)" "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2" "11|2026-08-02T00:00:00Z|agent:opencode,p2"
boarded "10:In Progress" "11:Ready"
check "an issue already claimed is not in the queue" "$(q 11)" "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2"
boarded "10:Backlog"
check "only Ready is the queue — Backlog is not" "" "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p1,blocked:human" "11|2026-08-02T00:00:00Z|agent:opencode,p2"
boarded "10:Ready" "11:Ready"
check "blocked:human is out of the queue however it got the label" "$(q 11)" "$(bash "$SCRIPT" pick 2>/dev/null)"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2"
boarded "10:Ready"
out=$(bash "$SCRIPT" pick 2>/dev/null)
check "exactly one issue is taken per run" "1" "$(grep -c . <<<"$out")"

echo
echo "claiming, and the token that stopped working"

case_setup
boarded "10:Ready"
bash "$SCRIPT" claim Kolonie-AI/kolonie-docs 10 >/dev/null 2>&1
rc=$?
check "a claim that works exits 0" "0" "$rc"
contains "a claim moves the issue to In Progress" "39185de7" "$(cat "$GH_LOG")"

case_setup
boarded "10:Ready"
echo yes > "$GH_FIXTURES/edit_fails"
err=$(bash "$SCRIPT" claim Kolonie-AI/kolonie-docs 10 2>&1 >/dev/null); rc=$?
check "a claim that cannot be written fails the run" "4" "$rc"
contains "and says the token may have expired" "may have expired" "$err"
contains "and says work has not started" "Not starting work" "$err"

case_setup
echo '{"items":[]}' > "$GH_FIXTURES/board"
err=$(bash "$SCRIPT" claim Kolonie-AI/kolonie-docs 10 2>&1 >/dev/null); rc=$?
check "an issue not on the board is refused rather than worked" "3" "$rc"

echo
echo "releasing a failed run"

case_setup
boarded "10:In Progress"
bash "$SCRIPT" release Kolonie-AI/kolonie-docs 10 >/dev/null 2>&1
contains "a release puts the issue back in Ready" "ee5ea42c" "$(cat "$GH_LOG")"

case_setup
boarded "10:In Progress"
echo yes > "$GH_FIXTURES/edit_fails"
err=$(bash "$SCRIPT" release Kolonie-AI/kolonie-docs 10 2>&1 >/dev/null); rc=$?
check "a release that cannot be written fails loudly" "4" "$rc"
contains "and says the issue is stuck and needs a person" "needs a person" "$err"
contains "and names the run" "$RUN_URL" "$err"

echo
echo "a board that is large, or from another repository (#142, 2026-08-07)"

# The defect the first non-empty run found, and the reason it took three days to
# find: the board was passed to `jq` with `--argjson`, which puts the whole
# document on the command line. Linux caps a single argument at 128 KiB whatever
# `ARG_MAX` says, the real board was about 190 KB, and `jq` died with `Argument
# list too long` — after which `pick` printed nothing and the workflow reported
# an empty queue. Every run between 2026-08-04 and 2026-08-07 was green and
# quiet because the queue really was empty; the first hour it was not, the run
# was still green and still quiet.
#
# The board here is padded past the ceiling with items nothing else matches, so
# a `pick` that puts it on a command line cannot survive this case.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2"
{
  printf '{"items":['
  printf '{"id":"ITEM_10","status":"Ready","content":{"number":10,"repository":"Kolonie-AI/kolonie-docs"}}'
  for i in $(seq 1 1500); do
    printf ',{"id":"PAD_%s","status":"Done","content":{"number":%s,"repository":"Kolonie-AI/kolonie-platform","title":"padding so the document passes the per-argument ceiling"}}' "$i" "$((90000 + i))"
  done
  printf ']}'
} > "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" pick 2>"$WORK/err"); rc=$?
check "a board too large for a command line still picks" "$(q 10)" "$out"
check "and exits 0" "0" "$rc"
absent "nothing complains about the argument list" "Argument list too long" "$(cat "$WORK/err")"

# The second defect in the same query, latent rather than firing: it matched the
# board item by issue *number* only. The board spans five repositories and the
# numbers repeat across them, so another repository's item decided what this
# repository's status was. `board_item_for` always matched the repository too —
# the two disagreeing is how a worker takes an issue the board says is Blocked.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2"
cat > "$GH_FIXTURES/board" <<'BOARD'
{"items":[
  {"id":"ITEM_OTHER","status":"Ready","content":{"number":10,"repository":"Kolonie-AI/kolonie-platform"}},
  {"id":"ITEM_10","status":"Blocked","content":{"number":10,"repository":"Kolonie-AI/kolonie-docs"}}
]}
BOARD
check "another repository's item does not put an issue in the queue" "" "$(bash "$SCRIPT" pick 2>/dev/null)"

# And the same in the direction that matters for throughput: a Ready issue here
# is not hidden by a Blocked item of the same number elsewhere.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2"
cat > "$GH_FIXTURES/board" <<'BOARD'
{"items":[
  {"id":"ITEM_OTHER","status":"Blocked","content":{"number":10,"repository":"Kolonie-AI/kolonie-platform"}},
  {"id":"ITEM_10","status":"Ready","content":{"number":10,"repository":"Kolonie-AI/kolonie-docs"}}
]}
BOARD
check "nor does it hide one" "$(q 10)" "$(bash "$SCRIPT" pick 2>/dev/null)"

# A board that cannot be read is not an empty queue. The workflow reads `pick`'s
# exit code separately from its output for exactly this distinction, and it can
# only do that if the script draws it.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2"
: > "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" pick 2>"$WORK/err"); rc=$?
check "an unreadable board fails rather than reading as an empty queue" "1" "$rc"
check "and picks nothing" "" "$out"
contains "and says the queue is unknown" "unknown" "$(cat "$WORK/err")"

echo
echo "the queue is the organisation, not this repository (#231)"

# The defect `#231` names: the worker could only ever see the repository hosting
# it, and the queue there was empty while labelled work sat in the other four.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-platform"
boarded "10:Ready:Kolonie-AI/kolonie-platform"
check "an issue in another repository is in the queue" \
  "$(q 10 Kolonie-AI/kolonie-platform)" "$(bash "$SCRIPT" pick 2>/dev/null)"

# Oldest wins across repositories, not within one. Ordering that only held
# inside a repository would make the queue depend on which repository you asked
# from, which is the property `#231` removes.
case_setup
issued "10|2026-08-03T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-docs" \
       "20|2026-08-01T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-website" \
       "30|2026-08-02T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-platform"
boarded "10:Ready:Kolonie-AI/kolonie-docs" \
        "20:Ready:Kolonie-AI/kolonie-website" \
        "30:Ready:Kolonie-AI/kolonie-platform"
check "the oldest across the whole organisation goes first" \
  "$(q 20 Kolonie-AI/kolonie-website)" "$(bash "$SCRIPT" pick 2>/dev/null)"

# And priority still beats age across repositories, for `#234`'s reason: a p1
# labelled this morning must not wait behind a p2 from last week, wherever
# either of them lives.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-website" \
       "20|2026-08-05T00:00:00Z|agent:opencode,p1|Kolonie-AI/kolonie-platform"
boarded "10:Ready:Kolonie-AI/kolonie-website" "20:Ready:Kolonie-AI/kolonie-platform"
check "p1 beats an older p2 in a different repository" \
  "$(q 20 Kolonie-AI/kolonie-platform)" "$(bash "$SCRIPT" pick 2>/dev/null)"

# Two repositories, same issue number, only one of them Ready. This is the case
# that was latent while the search was single-repository and is live now.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-docs" \
       "10|2026-08-02T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-platform"
boarded "10:Blocked:Kolonie-AI/kolonie-docs" "10:Ready:Kolonie-AI/kolonie-platform"
check "the same number in two repositories resolves to the Ready one" \
  "$(q 10 Kolonie-AI/kolonie-platform)" "$(bash "$SCRIPT" pick 2>/dev/null)"

# `#234`: an issue with neither priority sorts last, and the log names it. It is
# taken rather than skipped — refusing it would leave it queued forever with
# nothing saying why.
case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode" \
       "11|2026-08-05T00:00:00Z|agent:opencode,p2"
boarded "10:Ready" "11:Ready"
out=$(bash "$SCRIPT" pick 2>"$WORK/err")
check "an unprioritised issue sorts behind a newer p2" "$(q 11)" "$out"
contains "and the log names it rather than dropping it silently" \
  "carries neither p1 nor p2" "$(cat "$WORK/err")"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode"
boarded "10:Ready"
check "an unprioritised issue is still taken when it is all there is" \
  "$(q 10)" "$(bash "$SCRIPT" pick 2>/dev/null)"

# `#234`'s definition of done: one queue holding one of every case at once, so
# that the three tiers are shown to order against each other rather than each
# being right on its own. Deliberately laid out worst-first — the newest p1 is
# last in the fixture and first out of the queue.
case_setup
issued "40|2026-08-01T00:00:00Z|agent:opencode" \
       "30|2026-08-02T00:00:00Z|agent:opencode,p2" \
       "20|2026-08-01T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-website" \
       "10|2026-08-06T00:00:00Z|agent:opencode,p1|Kolonie-AI/kolonie-platform"
boarded "40:Ready" "30:Ready" \
        "20:Ready:Kolonie-AI/kolonie-website" \
        "10:Ready:Kolonie-AI/kolonie-platform"
out=$(bash "$SCRIPT" pick 2>"$WORK/err")
check "one of each case: the newest p1 still goes first" \
  "$(q 10 Kolonie-AI/kolonie-platform)" "$out"
contains "and the unprioritised one is named, not silently last" \
  "#40 carries neither p1 nor p2" "$(cat "$WORK/err")"

# The same queue with the p1 gone, to show the second and third tiers order
# against each other and not merely against p1.
case_setup
issued "40|2026-08-01T00:00:00Z|agent:opencode" \
       "30|2026-08-02T00:00:00Z|agent:opencode,p2" \
       "20|2026-08-01T00:00:00Z|agent:opencode,p2|Kolonie-AI/kolonie-website"
boarded "40:Ready" "30:Ready" "20:Ready:Kolonie-AI/kolonie-website"
check "with no p1, the oldest p2 goes before a p2 and both before no priority" \
  "$(q 20 Kolonie-AI/kolonie-website)" "$(bash "$SCRIPT" pick 2>/dev/null)"

# A search that fails is not an empty queue, for the same reason an unreadable
# board is not: the workflow reads the exit code separately from the output and
# can only do that if this script draws the distinction.
case_setup
rm -f "$GH_FIXTURES/issues"
cat > "$WORK/bin/gh" <<'FAILING'
#!/bin/bash
echo "$*" >> "$GH_LOG"
if [ "$1 $2" = "search issues" ]; then
  echo "HTTP 503" >&2
  exit 1
fi
FAILING
chmod +x "$WORK/bin/gh"
out=$(bash "$SCRIPT" pick 2>"$WORK/err"); rc=$?
check "a search that fails is not an empty queue" "1" "$rc"
check "and picks nothing" "" "$out"
contains "and says the queue is unknown" "unknown" "$(cat "$WORK/err")"
# Put the ordinary stub back for everything after this.
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "search issues")     cat "$GH_FIXTURES/issues" 2>/dev/null ;;
  "issue list")        cat "$GH_FIXTURES/issues" 2>/dev/null ;;
  "run list")
    if [ -s "$GH_FIXTURES/run_list_fails" ]; then
      echo "HTTP 503: the API is having a moment" >&2
      exit 1
    fi
    cat "$GH_FIXTURES/runs" 2>/dev/null ;;
  "project item-list") cat "$GH_FIXTURES/board" 2>/dev/null ;;
  "project item-edit")
    if [ -s "$GH_FIXTURES/edit_fails" ]; then
      echo "HTTP 401: Bad credentials" >&2
      exit 1
    fi
    ;;
  *) ;;
esac
STUB
chmod +x "$WORK/bin/gh"

echo
echo "the check command, read from the target's AGENTS.md (#231)"

case_setup
cat > "$WORK/agents-ok.md" <<'DOC'
# AGENTS.md
## 3. Something else
```bash
not this one
```
## 11. The check command
```bash
npm run check
```
## 12. When something here is wrong
DOC
out=$(bash "$SCRIPT" check-command "$WORK/agents-ok.md" 2>/dev/null); rc=$?
check "the command is read out of the named section" "npm run check" "$out"
check "and reading it exits 0" "0" "$rc"

case_setup
cat > "$WORK/agents-none.md" <<'DOC'
# AGENTS.md
## 1. What you need
```bash
gh auth login
```
DOC
err=$(bash "$SCRIPT" check-command "$WORK/agents-none.md" 2>&1 >/dev/null); rc=$?
check "a repository naming no check command fails rather than guessing" "5" "$rc"
contains "and says what is missing" "names no check command" "$err"
absent "and does not invent npm" "npm run check" "$err"

case_setup
err=$(bash "$SCRIPT" check-command "$WORK/there-is-no-such-file.md" 2>&1 >/dev/null); rc=$?
check "a missing AGENTS.md fails the same way" "5" "$rc"
contains "and says so" "no AGENTS.md" "$err"

echo
echo "what the check needs in front of it (#247)"

# The defect: the worker re-ran `kolonie-platform`'s check in an environment
# without PostgreSQL, and that check refuses to run without one on purpose. The
# repository states its prerequisite beside the command it already states, and
# this is the reader for it — the same convention, so that the worker holds no
# per-repository knowledge (`#231`).
case_setup
cat > "$WORK/agents-prereq.md" <<'DOC'
# AGENTS.md
## 8. The check command
```bash
npm run check
```
## 8a. The check prerequisite
```bash
npm run test:db:up
```
## 9. When you are unsure
DOC
out=$(bash "$SCRIPT" check-prerequisite "$WORK/agents-prereq.md" 2>/dev/null); rc=$?
check "the prerequisite is read out of its own section" "npm run test:db:up" "$out"
check "and reading it exits 0" "0" "$rc"
check "the check command is unaffected by the sibling section" \
  "npm run check" "$(bash "$SCRIPT" check-command "$WORK/agents-prereq.md" 2>/dev/null)"

# Four of the five repositories need nothing before their check, so silence is
# the ordinary answer and must not read as a defect — unlike a missing check
# *command*, which stops the run.
case_setup
out=$(bash "$SCRIPT" check-prerequisite "$WORK/agents-ok.md" 2>/dev/null); rc=$?
check "a repository declaring no prerequisite prints nothing" "" "$out"
check "and that is not an error" "0" "$rc"

echo
echo "the environment a prerequisite hands back (#247)"

# `npm run test:db:up` finishes by printing `export DATABASE_URL=…` — the
# repository's existing interface to a person. Honouring it is the whole point:
# a prerequisite that starts a server the check cannot then find has done
# nothing.
case_setup
cat > "$WORK/prereq-out.txt" <<'OUT'
created container kolonie-pg
waiting for postgres.
export DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5433/kolonie_test
OUT
out=$(bash "$SCRIPT" exports "$WORK/prereq-out.txt" 2>/dev/null)
check "the value survives one round of eval" \
  "postgres://postgres:postgres@127.0.0.1:5433/kolonie_test" \
  "$(eval "$out"; printf '%s' "${DATABASE_URL:-}")"
absent "and the rest of the output does not" "waiting for postgres" "$out"
absent "nor does the line about the container" "created container" "$out"

# Sourcing the output wholesale would run whatever the command chose to print,
# in this shell, with this run's credentials. `printf %q` is what makes a value
# a value.
case_setup
printf 'export DATABASE_URL=x$(id);echo pwned\n' > "$WORK/prereq-evil.txt"
out=$(bash "$SCRIPT" exports "$WORK/prereq-evil.txt" 2>/dev/null)
check "a command substitution in a value stays data" \
  'x$(id);echo pwned' "$(eval "$out"; printf '%s' "${DATABASE_URL:-}")"

case_setup
printf 'export DATABASE_URL="postgres://quoted/db"\n' > "$WORK/prereq-quoted.txt"
out=$(bash "$SCRIPT" exports "$WORK/prereq-quoted.txt" 2>/dev/null)
check "one layer of the emitter's own quotes comes off" \
  "postgres://quoted/db" "$(eval "$out"; printf '%s' "${DATABASE_URL:-}")"

# "My check needs a database" is not "my check needs your token", and the
# refusal is by name rather than by hoping nobody writes it.
case_setup
printf 'export PATH=/evil\nexport GH_TOKEN=stolen\nexport DATABASE_URL=ok\n' \
  > "$WORK/prereq-greedy.txt"
out=$(bash "$SCRIPT" exports "$WORK/prereq-greedy.txt" 2>"$WORK/err")
absent "a prerequisite may not set PATH" "PATH" "$out"
absent "nor may it hand the step a token" "GH_TOKEN" "$out"
contains "and it says which name it refused" "refusing to let the check prerequisite set PATH" \
  "$(cat "$WORK/err")"
check "while what it may set still arrives" "ok" \
  "$(eval "$out"; printf '%s' "${DATABASE_URL:-}")"

echo
echo "two runs cannot work at once (#231)"

case_setup
# What `gh run list --jq length` actually prints is the count, not the array.
echo 1 > "$GH_FIXTURES/runs"
check "one in-progress run — this one — is not busy" "" "$(bash "$SCRIPT" solo 2>/dev/null)"

case_setup
echo 2 > "$GH_FIXTURES/runs"
check "a second run says busy and takes nothing" "busy" "$(bash "$SCRIPT" solo 2>/dev/null)"

# The case `#231` asks for by name. A query that cannot answer must not stop the
# worker: the claim is the real lock, and an hour of silence is
# indistinguishable from an empty queue.
case_setup
printf '' > "$GH_FIXTURES/runs"
out=$(bash "$SCRIPT" solo 2>"$WORK/err")
check "an answer that is not a number is treated as no answer" "" "$out"
contains "and says so" "could not count" "$(cat "$WORK/err")"

case_setup
echo yes > "$GH_FIXTURES/run_list_fails"
out=$(bash "$SCRIPT" solo 2>"$WORK/err"); rc=$?
check "a failed run-count does not stop the worker" "" "$out"
check "and exits 0" "0" "$rc"
contains "and says why it continued" "the claim is the real lock" "$(cat "$WORK/err")"

echo
echo "what it never does"

case_setup
issued "10|2026-08-01T00:00:00Z|agent:opencode,p2"
boarded "10:Ready"
bash "$SCRIPT" pick >/dev/null 2>&1
bash "$SCRIPT" claim Kolonie-AI/kolonie-docs 10 >/dev/null 2>&1
bash "$SCRIPT" review Kolonie-AI/kolonie-docs 10 >/dev/null 2>&1
bash "$SCRIPT" release Kolonie-AI/kolonie-docs 10 >/dev/null 2>&1
log=$(cat "$GH_LOG")
absent "never removes the queue label" "remove-label" "$log"
absent "never edits a label at all" "issue edit" "$log"
absent "never comments — that is GITHUB_TOKEN's job in the workflow" "issue comment" "$log"
# The *script* never merges and never pushes. Since `#232` the **workflow** does
# enable auto-merge, deliberately — but the queue logic must stay incapable of
# it, because this is the file that runs with the board credential.
absent "the queue logic never merges — auto-merge is the workflow's, on GITHUB_TOKEN" "pr merge" "$log"
absent "never pushes" "push" "$log"

echo
echo "the workflow cannot merge past a failing check (#232)"

WORKFLOW="$ROOT/.github/workflows/opencode-worker.yml"
wf=$(cat "$WORKFLOW")
# Comments stripped before the forbidden-flag assertions, because the workflow
# *explains* why it does not use `--admin` and an assertion that cannot tell the
# explanation from the flag would forbid writing the reasoning down. That trade
# goes the other way: the reasoning is the part that stops somebody adding the
# flag back next year.
wf_commands=$(grep -v '^[[:space:]]*#' "$WORKFLOW")
absent "no --admin on any command in the workflow" "--admin" "$wf_commands"
absent "no force push" "push --force" "$wf_commands"
absent "and no force-with-lease either" "force-with-lease" "$wf_commands"
contains "auto-merge is queued, never waited on" "--auto --squash" "$wf"
contains "and it is gated on the target having a required check" \
  "branches/main/protection" "$wf"

# `#247`: the prerequisite is worthless if it runs after the check. A `run:`
# block cannot be executed by a test, so the ordering is asserted on the file.
contains "the workflow reads the target's check prerequisite" "check-prerequisite" "$wf"
prereq_line=$(grep -n 'CHECK_PREREQUISITE:-' "$WORKFLOW" | head -1 | cut -d: -f1)
check_line=$(grep -n 'eval "\$CHECK_COMMAND"' "$WORKFLOW" | head -1 | cut -d: -f1)
if [ -n "$prereq_line" ] && [ -n "$check_line" ] && [ "$prereq_line" -lt "$check_line" ]; then
  echo "  ok   and runs it before the check, not after"
else
  echo "  FAIL and runs it before the check, not after"
  echo "         prerequisite at line ${prereq_line:-none}, check at line ${check_line:-none}"
  FAILURES+=("the prerequisite runs before the check")
fi

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "all good"
  exit 0
fi
echo "${#FAILURES[@]} failed:"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

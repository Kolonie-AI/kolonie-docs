#!/bin/bash
# Does a finding that comes back reopen its issue, or file a fourth one?
# (`kolonie-docs#237`)
#
# Usage: bash .github/tests/watch-finding.test.sh
#
# The case that matters is the one every watcher got wrong in the same way: they
# looked for an existing issue with `--state open`, so a finding that had been
# closed and returned was invisible and a second issue was correct behaviour.
# `#146`, `#149` and `#179` are that bug three times.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/watch-finding.sh"
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
  "issue list") cat "$GH_FIXTURES/issues" 2>/dev/null || echo '[]' ;;
  *) ;;
esac
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

case_setup() {
  GH_FIXTURES="$WORK/fixtures"
  GH_LOG="$WORK/gh.log"
  export GH_FIXTURES GH_LOG
  rm -rf "$GH_FIXTURES"; mkdir -p "$GH_FIXTURES"
  : > "$GH_LOG"
  printf 'a body\n' > "$WORK/body.md"
}

check() {
  local what=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then echo "  ok   $what"
  else echo "  FAIL $what"; echo "         expected: $expected"; echo "         actual:   $actual"; FAILURES+=("$what"); fi
}
contains() {
  local what=$1 needle=$2 haystack=$3
  if [[ "$haystack" == *"$needle"* ]]; then echo "  ok   $what"
  else echo "  FAIL $what"; echo "         wanted to find: $needle"; FAILURES+=("$what"); fi
}
absent() {
  local what=$1 needle=$2 haystack=$3
  if [[ "$haystack" != *"$needle"* ]]; then echo "  ok   $what"
  else echo "  FAIL $what"; echo "         did not want to find: $needle"; FAILURES+=("$what"); fi
}

# `boarded <number> <state> <identity>` — one issue carrying that marker.
existing() {
  local number=$1 state=$2 identity=$3
  jq -n --argjson n "$number" --arg s "$state" \
     --arg b "Some prose.

<!-- watch-finding: $identity -->

More prose." \
    '[{number:$n, state:$s, title:"whatever it was called", body:$b}]' \
    > "$GH_FIXTURES/issues"
}

echo "the marker"

case_setup
check "the key is one stable line" "<!-- watch-finding: silent-service:umami -->" \
  "$(bash "$SCRIPT" key silent-service:umami)"

echo
echo "absent — file it"

case_setup
echo '[]' > "$GH_FIXTURES/issues"
out=$(bash "$SCRIPT" place silent-service:umami "umami has stopped logging" "$WORK/body.md" p1 area:docs 2>&1)
contains "an unseen finding is filed" "filed a new issue" "$out"
contains "with its labels" "--label p1" "$(cat "$GH_LOG")"
contains "and its body from a file, never an inline string" "--body-file" "$(cat "$GH_LOG")"
absent "and nothing is reopened" "issue reopen" "$(cat "$GH_LOG")"

echo
echo "open — comment, and nothing else"

case_setup
existing 191 OPEN silent-service:umami
out=$(bash "$SCRIPT" place silent-service:umami "umami has stopped logging" "$WORK/body.md" p1 2>&1)
contains "an open finding is commented on" "commented on #191" "$out"
absent "and no second issue is filed" "issue create" "$(cat "$GH_LOG")"
absent "and it is not reopened, being open" "issue reopen" "$(cat "$GH_LOG")"
contains "the comment says it is still true" "Still true today" "$(cat "$GH_LOG")"

echo
echo "closed and back — reopen (#146, #149, #179 are this case, three times)"

case_setup
existing 146 CLOSED board-unmaintained
out=$(bash "$SCRIPT" place board-unmaintained "The board has stopped maintaining itself" "$WORK/body.md" p1 2>&1)
contains "a closed finding that returns is reopened" "reopened #146" "$out"
contains "the reopen actually happens" "issue reopen 146" "$(cat "$GH_LOG")"
absent "and no new issue is filed — this is the bug that made three" "issue create" "$(cat "$GH_LOG")"
contains "the comment says it came back" "this came back" "$(cat "$GH_LOG")"

echo
echo "identity, not wording"

# The title carries yesterday's numbers and will never match tomorrow's. The
# marker is what joins them.
case_setup
existing 146 CLOSED board-unmaintained
out=$(bash "$SCRIPT" place board-unmaintained "A completely different title, 12 items now" "$WORK/body.md" 2>&1)
contains "a reworded title still resolves to the same finding" "reopened #146" "$out"

case_setup
existing 191 OPEN silent-service:umami
out=$(bash "$SCRIPT" place silent-service:loki "loki has stopped logging" "$WORK/body.md" 2>&1)
contains "a different service is a different finding" "filed a new issue" "$out"
absent "and does not comment on the other service's issue" "issue comment 191" "$(cat "$GH_LOG")"

case_setup
existing 191 OPEN silent-service:umami
out=$(bash "$SCRIPT" place workflow-red "A workflow's latest run on main is red" "$WORK/body.md" 2>&1)
contains "a different condition on no service is a different finding" "filed a new issue" "$out"

# An issue whose body is null — GitHub returns that for a body-less issue — must
# not blow up the filter that reads every body looking for the marker.
case_setup
jq -n '[{number:5, state:"OPEN", title:"no body at all", body:null}]' > "$GH_FIXTURES/issues"
out=$(bash "$SCRIPT" place silent-service:umami "umami has stopped logging" "$WORK/body.md" 2>&1); rc=$?
check "an issue with no body does not break the search" "0" "$rc"
contains "and the finding is filed" "filed a new issue" "$out"

echo
echo "the condition ended — resolve it (#351)"

# The case `#328` was: an issue open, and the measurement behind it answering the
# other way for two days with no path by which the issue could say so.
case_setup
existing 328 OPEN gateway-not-serving
out=$(bash "$SCRIPT" resolve gateway-not-serving "no fallbacks in the busiest hour, and no refusals" 2>&1); rc=$?
check "an allowlisted finding whose condition ended is closed" "0" "$rc"
contains "and it says which issue" "resolved #328" "$out"
contains "the close actually happens" "issue close 328" "$(cat "$GH_LOG")"
contains "and it says what the measurement now is" "no fallbacks in the busiest hour" "$(cat "$GH_LOG")"
contains "and that the end is the same measurement, not a second threshold" \
  "read the other way" "$(cat "$GH_LOG")"
absent "and nothing is filed" "issue create" "$(cat "$GH_LOG")"

# **The rejection case that matters.** A watcher that could close a model's
# reading of an error line is the thing this must not become, so an identity not
# on the list is refused non-zero and says why — not silently ignored, which
# would let a caller ship a `resolve` for a judged finding and never find out.
case_setup
existing 191 OPEN silent-service:umami
out=$(bash "$SCRIPT" resolve silent-service:umami "it logged again" 2>&1); rc=$?
check "a finding that is not on the allowlist is refused" "2" "$rc"
contains "loudly, naming the list" "not on the allowlist" "$out"
contains "and saying where a new entry goes" "RESOLVABLE_IDENTITIES" "$out"
absent "and it closes nothing" "issue close" "$(cat "$GH_LOG")"
absent "and comments nothing" "issue comment" "$(cat "$GH_LOG")"

# The ordinary day, which is every day: the condition is not true and never was.
# A watcher runs on a timer, so this path is taken far more often than the one
# above and must be silent and green.
case_setup
echo '[]' > "$GH_FIXTURES/issues"
out=$(bash "$SCRIPT" resolve gateway-not-serving "nothing fell back" 2>&1); rc=$?
check "resolve with no issue of that identity exits 0" "0" "$rc"
absent "and writes nothing" "issue close" "$(cat "$GH_LOG")"
absent "and comments nothing" "issue comment" "$(cat "$GH_LOG")"

# Idempotent, for the same reason: tomorrow's run finds what today's run closed.
case_setup
existing 328 CLOSED gateway-not-serving
out=$(bash "$SCRIPT" resolve gateway-not-serving "still nothing" 2>&1); rc=$?
check "resolving an already-closed finding is a no-op, not a second close" "0" "$rc"
contains "and says so" "already closed" "$out"
absent "and closes nothing again" "issue close" "$(cat "$GH_LOG")"

# And the way back: `place` reopens what `resolve` closed, under the same
# identity. One issue, with its recurrences readable in one place.
case_setup
existing 328 CLOSED gateway-not-serving
out=$(bash "$SCRIPT" place gateway-not-serving "The Colony was served by its second choice" "$WORK/body.md" p2 2>&1)
contains "a resolved finding that returns reopens rather than filing again" "reopened #328" "$out"
absent "no second issue" "issue create" "$(cat "$GH_LOG")"

echo
echo "the footer says which kind of finding it is"

case_setup
foot=$(bash "$SCRIPT" footer gateway-not-serving "the gateway not serving" "watch-agent.yml")
contains "a resolvable finding says the machine also closes it" "closes itself" "$foot"
foot=$(bash "$SCRIPT" footer silent-service:umami "one service that has stopped logging" "watch-agent.yml")
contains "and one that is not keeps the only sentence that is true of it" \
  "Closing this is how you tell the machine" "$foot"
absent "and is not promised a close it will never get" "closes itself" "$foot"

echo
if [ ${#FAILURES[@]} -eq 0 ]; then echo "all good"; exit 0; fi
echo "${#FAILURES[@]} failed:"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

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
if [ ${#FAILURES[@]} -eq 0 ]; then echo "all good"; exit 0; fi
echo "${#FAILURES[@]} failed:"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

#!/bin/bash
# Does a package tracker close only when every child it manifested is verified
# delivered, and stay open — loudly — whenever anything cannot be established?
#
# Usage: bash .github/tests/tracker-settle.test.sh
#
# `kolonie-docs#566` asks for the conservative half to be proved rather than
# asserted: a tracker that closes on a guess is worse than one nobody closes,
# because the guess is invisible afterwards. So every case here runs against a
# **stubbed `gh`** whose log is the whole assertion — any close the script should
# not have made appears in it, whatever code path produced it.
#
# `kolonie-platform#1754` is the failure it is written for: all fourteen children
# closed, the last one delivered by a merged green pull request, and the tracker
# sat Blocked for two days.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/tracker-settle.sh"
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
  "issue list")
    cat "$GH_FIXTURES/trackers" 2>/dev/null ;;
  "api graphql")
    # One call per child, identified by the owner/name/number it was given.
    owner=""; name=""; number=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -f|-F)
          case "$2" in
            owner=*)  owner=${2#owner=} ;;
            name=*)   name=${2#name=} ;;
            number=*) number=${2#number=} ;;
          esac
          shift 2 ;;
        *) shift ;;
      esac
    done
    fixture="$GH_FIXTURES/child_${owner}_${name}_${number}"
    if [ -f "$fixture.fail" ]; then
      echo '{"errors":[{"message":"Could not resolve to a Repository"}]}'
      exit 1
    fi
    cat "$fixture" 2>/dev/null ;;
  *) : ;;
esac
exit 0
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

expect() { # description ok detail
  if [ "$2" = yes ]; then printf '  ok   %s\n' "$1"
  else printf '  FAIL %s%s\n' "$1" "${3:+: $3}"; FAILURES+=("$1"); fi
}

setup() {
  export GH_FIXTURES="$WORK/fx" GH_LOG="$WORK/log"
  rm -rf "$GH_FIXTURES"; mkdir -p "$GH_FIXTURES"; : > "$GH_LOG"
}

# A tracker as `gh issue list --json number,body` returns it.
tracker() { # number body
  jq -n --argjson n "$1" --arg b "$2" '[{number:$n, body:$b}]' > "$GH_FIXTURES/trackers"
}

# One child's answer: state, and the pull requests that closed it.
child() { # owner name number state prs-json
  jq -n --arg state "$4" --argjson prs "$5" \
    '{data:{repository:{issue:{state:$state, closedByPullRequestsReferences:{nodes:$prs}}}}}' \
    > "$GH_FIXTURES/child_$1_$2_$3"
}

# One pull request, in the shape the GraphQL query asks for: the rollup is a
# state on the head commit, which is what a person reads as the tick beside a
# merge. A flat string here would be a fixture agreeing with a reader that the
# API does not, which is the shape `#1067` in the platform repository was.
pr() { # number merged checks
  printf '{"number":%s,"merged":%s,"url":"https://github.com/x/y/pull/%s","statusCheckRollup":{"nodes":[{"commit":{"statusCheckRollup":{"state":"%s"}}}]}}' \
    "$1" "$2" "$1" "$3"
}

MARKER='<!-- package-tracker -->'
kid() { printf '<!-- tracker-child: https://github.com/Kolonie-AI/%s/issues/%s%s -->' "$1" "$2" "${3:+ $3}"; }

body() { printf '%s\n%s\n' "$MARKER" "$(printf '%s\n' "$@")"; }

logged() { grep -q -- "$1" "$GH_LOG"; }

echo "a tracker whose every child is delivered"

setup
tracker 1754 "$(body "$(kid kolonie-platform 1755)" "$(kid kolonie-workplace 105)")"
child Kolonie-AI kolonie-platform 1755 CLOSED "[$(pr 1766 true SUCCESS)]"
child Kolonie-AI kolonie-workplace 105 CLOSED "[$(pr 107 true SUCCESS)]"
out=$(bash "$SCRIPT" 2>&1); rc=$?
expect "closes the tracker" "$(logged 'issue close 1754' && echo yes || echo no)" "$out"
expect "exits 0" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc"
expect "and posts an evidence table naming every child" \
  "$([[ "$out" == *"kolonie-platform#1755"* && "$out" == *"kolonie-workplace#105"* ]] && echo yes || echo no)" "$out"
expect "the table names the pull request and the check conclusion" \
  "$([[ "$out" == *"pull/1766"* && "$out" == *"SUCCESS"* ]] && echo yes || echo no)" "$out"
expect "the comment is written before the close" \
  "$([ "$(grep -n 'issue comment 1754' "$GH_LOG" | head -1 | cut -d: -f1)" -lt "$(grep -n 'issue close 1754' "$GH_LOG" | head -1 | cut -d: -f1)" ] && echo yes || echo no)" "$(cat "$GH_LOG")"

echo
echo "cross-repository children"

setup
tracker 1754 "$(body "$(kid kolonie-platform 1755)" "$(kid kolonie-docs 553)")"
child Kolonie-AI kolonie-platform 1755 CLOSED "[$(pr 1766 true SUCCESS)]"
child Kolonie-AI kolonie-docs 553 CLOSED "[$(pr 560 true SUCCESS)]"
out=$(bash "$SCRIPT" 2>&1)
expect "a child in another repository is read and counted" \
  "$(logged 'issue close 1754' && echo yes || echo no)" "$out"

echo
echo "an explicit no-code child"

setup
tracker 1754 "$(body "$(kid kolonie-platform 1755)" "$(kid kolonie-docs 553 no-code)")"
child Kolonie-AI kolonie-platform 1755 CLOSED "[$(pr 1766 true SUCCESS)]"
child Kolonie-AI kolonie-docs 553 CLOSED '[]'
out=$(bash "$SCRIPT" 2>&1)
expect "a child marked no-code needs no pull request" \
  "$(logged 'issue close 1754' && echo yes || echo no)" "$out"
expect "and the table says so rather than leaving it blank" \
  "$([[ "$out" == *"no-code"* ]] && echo yes || echo no)" "$out"

echo
echo "everything that leaves it open"

# An open child.
setup
tracker 1754 "$(body "$(kid kolonie-platform 1755)")"
child Kolonie-AI kolonie-platform 1755 OPEN '[]'
out=$(bash "$SCRIPT" 2>&1); rc=$?
expect "an open child leaves the tracker open" "$(logged 'issue close' && echo no || echo yes)" "$out"
expect "and emits one finding" "$([ "$(grep -c 'issue comment 1754' "$GH_LOG")" -eq 1 ] && echo yes || echo no)" "$(cat "$GH_LOG")"
expect "which names the child that is not done" "$([[ "$out" == *"kolonie-platform#1755"* ]] && echo yes || echo no)" "$out"
expect "and exits non-zero" "$([ $rc -ne 0 ] && echo yes || echo no)" "rc=$rc"

# An implementation child with no merged pull request.
setup
tracker 1754 "$(body "$(kid kolonie-platform 1755)")"
child Kolonie-AI kolonie-platform 1755 CLOSED "[$(pr 1766 false SUCCESS)]"
out=$(bash "$SCRIPT" 2>&1)
expect "a closed child whose pull request never merged leaves it open" \
  "$(logged 'issue close' && echo no || echo yes)" "$out"
expect "and says the pull request is unmerged" "$([[ "$out" == *"unmerged"* ]] && echo yes || echo no)" "$out"

setup
tracker 1754 "$(body "$(kid kolonie-platform 1755)")"
child Kolonie-AI kolonie-platform 1755 CLOSED '[]'
out=$(bash "$SCRIPT" 2>&1)
expect "a closed child with no pull request at all leaves it open" \
  "$(logged 'issue close' && echo no || echo yes)" "$out"

# Red and pending required checks.
setup
tracker 1754 "$(body "$(kid kolonie-platform 1755)")"
child Kolonie-AI kolonie-platform 1755 CLOSED "[$(pr 1766 true FAILURE)]"
out=$(bash "$SCRIPT" 2>&1)
expect "a red required check leaves it open" "$(logged 'issue close' && echo no || echo yes)" "$out"
expect "and names the conclusion" "$([[ "$out" == *"FAILURE"* ]] && echo yes || echo no)" "$out"

setup
tracker 1754 "$(body "$(kid kolonie-platform 1755)")"
child Kolonie-AI kolonie-platform 1755 CLOSED "[$(pr 1766 true PENDING)]"
out=$(bash "$SCRIPT" 2>&1)
expect "a pending required check leaves it open" "$(logged 'issue close' && echo no || echo yes)" "$out"

# A child whose repository cannot be read.
setup
tracker 1754 "$(body "$(kid kolonie-platform 1755)")"
: > "$GH_FIXTURES/child_Kolonie-AI_kolonie-platform_1755.fail"
out=$(bash "$SCRIPT" 2>&1)
expect "an inaccessible child leaves it open" "$(logged 'issue close' && echo no || echo yes)" "$out"
expect "and says the read failed rather than guessing" \
  "$([[ "$out" == *"could not be read"* ]] && echo yes || echo no)" "$out"

# A child the manifest names and GitHub does not have.
setup
tracker 1754 "$(body "$(kid kolonie-platform 9999)")"
jq -n '{data:{repository:{issue:null}}}' > "$GH_FIXTURES/child_Kolonie-AI_kolonie-platform_9999"
out=$(bash "$SCRIPT" 2>&1)
expect "a missing child leaves it open" "$(logged 'issue close' && echo no || echo yes)" "$out"
expect "and says which one is missing" "$([[ "$out" == *"kolonie-platform#9999"* ]] && echo yes || echo no)" "$out"

# A malformed manifest.
setup
tracker 1754 "$(printf '%s\n<!-- tracker-child: not-a-url -->\n' "$MARKER")"
out=$(bash "$SCRIPT" 2>&1)
expect "a malformed manifest entry leaves it open" "$(logged 'issue close' && echo no || echo yes)" "$out"
expect "and says the manifest is malformed" "$([[ "$out" == *"malformed"* ]] && echo yes || echo no)" "$out"

setup
tracker 1754 "$MARKER"
out=$(bash "$SCRIPT" 2>&1)
expect "a tracker manifesting no child at all is never closed" \
  "$(logged 'issue close' && echo no || echo yes)" "$out"
expect "and says it lists none" "$([[ "$out" == *"no child"* ]] && echo yes || echo no)" "$out"

echo
echo "what it refuses to infer"

# Prose. The word Epic, a checklist, a table — none of it is a manifest.
setup
jq -n '[{number:1754, body:"# Epic\n\n| child | state |\n| --- | --- |\n| Kolonie-AI/kolonie-platform#1755 | closed |\n\n- [x] kolonie-workplace#105"}]' \
  > "$GH_FIXTURES/trackers"
out=$(bash "$SCRIPT" 2>&1); rc=$?
expect "an issue with no marker is not a tracker" "$(logged 'issue close' && echo no || echo yes)" "$out"
expect "and nothing is commented on it either" "$(logged 'issue comment' && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "and a day with no tracker is not a failure" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc"

echo
echo "what it never does"

setup
tracker 1754 "$(body "$(kid kolonie-platform 1755)")"
child Kolonie-AI kolonie-platform 1755 CLOSED "[$(pr 1766 true SUCCESS)]"
bash "$SCRIPT" >/dev/null 2>&1
log=$(cat "$GH_LOG")
for forbidden in "pr merge" "issue close 1755" "issue edit" "item-edit" "issue reopen"; do
  expect "no $forbidden on any code path" \
    "$(grep -q -- "$forbidden" <<<"$log" && echo no || echo yes)" "$log"
done

setup
tracker 1754 "$(body "$(kid kolonie-platform 1755)")"
child Kolonie-AI kolonie-platform 1755 CLOSED "[$(pr 1766 true SUCCESS)]"
out=$(bash "$SCRIPT" --dry-run 2>&1); rc=$?
expect "--dry-run says what it would close" "$([[ "$out" == *"would close"* ]] && echo yes || echo no)" "$out"
expect "and writes nothing" "$(logged 'issue close' && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "and exits 0" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc"

echo
if [ ${#FAILURES[@]} -gt 0 ]; then
  printf '%d failed: %s\n' "${#FAILURES[@]}" "$(IFS=,; echo "${FAILURES[*]}")"
  exit 1
fi
echo "all cases pass"

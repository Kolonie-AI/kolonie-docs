#!/bin/bash
# Does the red-lines reporter reuse its issue rather than filing a second one?
#
# Usage: bash .github/tests/red-lines-report.test.sh
#
# `kolonie-docs#150` found the reuse guard reading GitHub's **search index**,
# which is eventually consistent — so an issue filed a moment ago is not
# findable, the guard passes, and a duplicate is opened. The fix is a REST
# listing with the title matched here; these cases are what stops the weaker
# form returning unnoticed.
#
# Against a **stubbed `gh`**, which is the only way to exercise the branch where
# an issue already exists without filing one. The stub records every invocation
# to a log and answers from files the case sets up. It does not run jq, so the
# `existing` fixture holds the *answer* the lookup would produce — a bare issue
# number, or nothing.
#
# What a stub cannot reproduce is the latency itself: it has no index, and
# answers instantly and consistently. That is why `#150`'s definition of done
# also required a live rehearsal, and why the copied case below asserts on the
# *shape of the call* rather than on the outcome of a race.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/red-lines-report.sh"
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
  "issue list") cat "$GH_FIXTURES/existing" 2>/dev/null ;;
  *) : ;;
esac
exit 0
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

expect() {
  local name=$1 ok=$2 detail=${3:-}
  if [ "$ok" = yes ]; then printf '  ok   %s\n' "$name"
  else printf '  FAIL %s%s\n' "$name" "${detail:+: $detail}"; FAILURES+=("$name"); fi
}

setup() {
  export GH_FIXTURES="$WORK/fixtures" GH_LOG="$WORK/log"
  rm -rf "$GH_FIXTURES"; mkdir -p "$GH_FIXTURES"; : > "$GH_LOG"
  : > "$GH_FIXTURES/existing"
  printf 'about.ts says one thing and red-lines.md says another\n' > "$WORK/report"
}

logged() { grep -q -- "$1" "$GH_LOG"; }

echo "filing — one issue, reused"

setup
bash "$SCRIPT" report "$WORK/report" >/dev/null
expect "with no open issue, one is created" "$(logged 'issue create' && echo yes || echo no)"
expect "and it is labelled area:governance" "$(logged 'area:governance' && echo yes || echo no)"
expect "and p1" "$(logged 'label p1' && echo yes || echo no)"
expect "and carries the comparison's own words" \
  "$(logged 'red-lines.md says another' && echo yes || echo no)" "$(cat "$GH_LOG")"

setup; echo '147' > "$GH_FIXTURES/existing"
bash "$SCRIPT" report "$WORK/report" >/dev/null
expect "with one already open, no second issue is created" \
  "$(logged 'issue create' && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "it comments on the open one instead" "$(logged 'issue comment 147' && echo yes || echo no)"

echo
echo "closing — the other half of reaching somebody"

setup; echo '147' > "$GH_FIXTURES/existing"
bash "$SCRIPT" resolve >/dev/null
expect "when the copies agree again, the issue is closed" \
  "$(logged 'issue close 147' && echo yes || echo no)"

setup
bash "$SCRIPT" resolve >/dev/null
expect "and closing nothing is not an error" "$(logged 'issue close' && echo no || echo yes)"

echo
echo "the guard #150 was opened for"

# The defect itself, in both branches. `--search` is what made a duplicate
# possible; asserting on the log makes this exhaustive rather than a reading of
# the script, and it is the case `board-self-check.test.sh` already carries.
for cmd in report resolve; do
  setup; echo '147' > "$GH_FIXTURES/existing"
  if [ "$cmd" = report ]; then bash "$SCRIPT" report "$WORK/report" >/dev/null
  else bash "$SCRIPT" resolve >/dev/null; fi
  expect "$cmd does not look the issue up through the search index" \
    "$(grep -q 'in:title' "$GH_LOG" && echo no || echo yes)" "$(cat "$GH_LOG")"
  expect "$cmd does not use --search at all" \
    "$(grep -q -- '--search' "$GH_LOG" && echo no || echo yes)" "$(cat "$GH_LOG")"
done

# And the whole tree, so the form cannot come back in a workflow that never
# reaches this script. `#150`'s acceptance criterion is `grep -rn "in:title"
# .github/` finding nothing, and a criterion nobody runs is a criterion.
# Prose about the defect is allowed to name it; a `gh` call may not.
echo
echo "and nowhere else in .github/"

# Comment lines are skipped: `board-self-check.sh` and the script under test both
# explain the defect by name, and a check that forbids naming it would be a check
# that deletes its own reasoning. What is forbidden is a live call.
offenders=$(grep -rn -- '--search' "$ROOT/.github" 2>/dev/null \
  | grep -v '/tests/' \
  | grep -v ':[[:space:]]*#' || true)
expect "no gh call in .github/ uses --search" \
  "$([ -z "$offenders" ] && echo yes || echo no)" "$offenders"

echo
if [ ${#FAILURES[@]} -gt 0 ]; then
  printf '%d failed: %s\n' "${#FAILURES[@]}" "$(IFS=,; echo "${FAILURES[*]}")"
  exit 1
fi
echo "all cases pass"

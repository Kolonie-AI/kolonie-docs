#!/bin/bash
# Does the red-on-main check file when a workflow is red, and stay silent for
# every other reason a run has no success on it? `kolonie-docs#193`.
#
# Usage: bash .github/tests/red-on-main.test.sh
#
# `#193` asks for a test with **at least one rejection case** — a stubbed run list
# containing a failure produces the issue, one containing only successes produces
# nothing. Both are here, and so are the four ways a run can lack a success
# without being a failure: never run, cancelled, skipped, and still in progress.
# Those four are the ones that would turn this into a monitor people filter.
#
# `gh` is stubbed. That is the only way to exercise a red `main` without breaking
# `main`, and the only way to reach the branch where the issue already exists
# without filing one. Every `gh` invocation is logged, so "it re-ran nothing and
# closed nothing" is a search over what it actually did rather than a reading of
# the source.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/red-on-main.sh"
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export GITHUB_REPOSITORY="Kolonie-AI/kolonie-docs"
export RUN_URL="https://example.invalid/run/1"
export VISIBILITY_POLL=0 VISIBILITY_ATTEMPTS=4

mkdir -p "$WORK/bin"

# Answers by subcommand, from files the case sets up. `run list` answers per
# workflow id, so one case can hold a green workflow and a red one at once —
# which is the case that matters, because a check that reports the whole
# repository as red the moment one workflow fails is not telling anybody which.
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "api repos/Kolonie-AI/kolonie-docs/actions/workflows")
      # Two calls, one endpoint: the reachability probe asks for a count and the
      # listing asks for id and name. The real `gh` applies `--jq`, so the stub
      # tells them apart by it — an unreadable list has to fail both.
      if [[ "$* " == *"length"* ]]; then
        [ -s "$FIX/workflows" ] || { echo "HTTP 403: Resource not accessible" >&2; exit 1; }
        wc -l < "$FIX/workflows"
      else
        cat "$FIX/workflows" 2>/dev/null
      fi ;;
  "run list")
      wf=""; for ((i=1; i<=$#; i++)); do
        [ "${!i}" = "--workflow" ] && { j=$((i+1)); wf="${!j}"; }
      done
      cat "$FIX/runs.$wf" 2>/dev/null || true ;;
  "issue list")
      n=$(cat "$FIX/.calls" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$FIX/.calls"
      d=$(cat "$FIX/existing_delay" 2>/dev/null || echo 0)
      [ "$n" -gt "$d" ] && cat "$FIX/existing" 2>/dev/null ;;
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

# The stub is given the shape `gh` really answers with: `--jq` is applied by the
# real `gh`, so the fixtures hold the *already projected* lines the script reads.
setup() {
  export FIX="$WORK/fixtures" GH_LOG="$WORK/gh.log"
  rm -rf "$FIX"; mkdir -p "$FIX"; : > "$GH_LOG"
  rm -f "$WORK/report.md"
  printf '11\tCI\n12\tRehearse\n' > "$FIX/workflows"
  printf 'success\tabc1234\thttps://example.invalid/ci/9\n'       > "$FIX/runs.11"
  printf 'success\tdef5678\thttps://example.invalid/rehearse/9\n' > "$FIX/runs.12"
  : > "$FIX/existing"
}

logged() { grep -q -- "$1" "$GH_LOG"; }

echo "a green repository is silent"

setup
out=$(bash "$SCRIPT" check "$WORK/report.md"); rc=$?
expect "check exits 0" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc out=$out"
expect "and says so in plain words" \
  "$([[ "$out" == *"is not a failure"* ]] && echo yes || echo no)" "$out"
expect "the report is empty" "$([ ! -s "$WORK/report.md" ] && echo yes || echo no)" "$(cat "$WORK/report.md")"
bash "$SCRIPT" report "$WORK/report.md" >/dev/null
expect "a quiet day opens nothing" "$(logged "issue create" && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "and comments on nothing" "$(logged "issue comment" && echo no || echo yes)" "$(cat "$GH_LOG")"

echo
echo "a workflow whose last completed run on main failed (#193)"

# The two days `Rehearse` was red, in a fixture.
setup; printf 'failure\tdef5678\thttps://example.invalid/rehearse/12\n' > "$FIX/runs.12"
out=$(bash "$SCRIPT" check "$WORK/report.md"); rc=$?
expect "check exits 1" "$([ $rc -eq 1 ] && echo yes || echo no)" "rc=$rc"
expect "the workflow is named" \
  "$(grep -q 'Rehearse' "$WORK/report.md" && echo yes || echo no)" "$(cat "$WORK/report.md")"
expect "so is the commit" \
  "$(grep -q 'def5678' "$WORK/report.md" && echo yes || echo no)" "$(cat "$WORK/report.md")"
expect "so is the run URL" \
  "$(grep -q 'example.invalid/rehearse/12' "$WORK/report.md" && echo yes || echo no)" "$(cat "$WORK/report.md")"
expect "the green workflow beside it is not named" \
  "$(grep -q 'CI' "$WORK/report.md" && echo no || echo yes)" "$(cat "$WORK/report.md")"

bash "$SCRIPT" report "$WORK/report.md" >/dev/null
expect "one issue is filed" \
  "$([ "$(grep -c 'issue create' "$GH_LOG")" -eq 1 ] && echo yes || echo no)" "$(cat "$GH_LOG")"
expect "and it says it is not a merge gate" \
  "$(grep -q 'Nothing here is a merge gate' "$GH_LOG" && echo yes || echo no)" "$(cat "$GH_LOG")"

echo
echo "the four ways a run is not a success and not a failure"

# **The criterion that keeps this from being filtered.** An Actions outage
# cancels runs in bulk; a workflow added this morning has never run; a
# path-filtered workflow reports `skipped`. None of those is a red run and none
# of them may file.
for verdict in cancelled skipped; do
  setup; printf '%s\tdef5678\thttps://example.invalid/rehearse/12\n' "$verdict" > "$FIX/runs.12"
  out=$(bash "$SCRIPT" check "$WORK/report.md"); rc=$?
  expect "a $verdict run files nothing" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc $(cat "$WORK/report.md")"
done

# Never run at all: the run list is empty, and there is no verdict to read.
setup; : > "$FIX/runs.12"
out=$(bash "$SCRIPT" check "$WORK/report.md"); rc=$?
expect "a workflow that has never run files nothing" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc $(cat "$WORK/report.md")"

# In progress: `--jq` has already dropped it, so the newest *completed* run is
# what arrives. This is the case that would let a red workflow read as fine for
# as long as a fifth run is queued, which is why the script asks for ten and
# takes the newest completed rather than position one.
setup; printf 'failure\tdef5678\thttps://example.invalid/rehearse/12\n' > "$FIX/runs.12"
out=$(bash "$SCRIPT" check "$WORK/report.md"); rc=$?
expect "a queued run does not hide the failure beneath it" \
  "$([ $rc -eq 1 ] && echo yes || echo no)" "rc=$rc"

echo
echo "one issue, reused rather than duplicated"

setup; echo "418" > "$FIX/existing"
printf 'failure\tdef5678\thttps://example.invalid/rehearse/12\n' > "$FIX/runs.12"
bash "$SCRIPT" check "$WORK/report.md" >/dev/null
bash "$SCRIPT" report "$WORK/report.md" >/dev/null
expect "with one open, no second issue is filed" "$(logged "issue create" && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "it comments on the open one" "$(logged "issue comment 418" && echo yes || echo no)" "$(cat "$GH_LOG")"

# Two red workflows are one condition with a list, not two issues: the thing that
# needs reading is "this repository has red runs nobody is looking at".
setup; echo "418" > "$FIX/existing"
printf 'failure\tabc1234\thttps://example.invalid/ci/12\n'       > "$FIX/runs.11"
printf 'failure\tdef5678\thttps://example.invalid/rehearse/12\n' > "$FIX/runs.12"
bash "$SCRIPT" check "$WORK/report.md" >/dev/null
expect "two red workflows are both listed" \
  "$([ "$(grep -c '^- ' "$WORK/report.md")" -eq 2 ] && echo yes || echo no)" "$(cat "$WORK/report.md")"
bash "$SCRIPT" report "$WORK/report.md" >/dev/null
expect "on one issue, not two" \
  "$([ "$(grep -c 'issue comment' "$GH_LOG")" -eq 1 ] && echo yes || echo no)" "$(cat "$GH_LOG")"

echo
echo "it reads, and does nothing else (#193)"

expect "it never closes an issue" "$(logged "issue close" && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "it re-runs nothing" \
  "$( { logged "run rerun" || logged "run watch" || logged "workflow run"; } && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "it enables and disables no workflow" \
  "$( { logged "workflow enable" || logged "workflow disable"; } && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "it edits nothing" "$(logged "issue edit" && echo no || echo yes)" "$(cat "$GH_LOG")"

echo
echo "an unreadable workflow list is a configuration gap, not a finding"

# Silent is the worse failure here than loud: an unreadable listing comes back
# empty, every workflow reads as never-run, and a good day and a broken check are
# the same output. So it exits 2 and the workflow says so in the log.
setup; : > "$FIX/workflows"
out=$(bash "$SCRIPT" check "$WORK/report.md"); rc=$?
expect "check exits 2" "$([ $rc -eq 2 ] && echo yes || echo no)" "rc=$rc"
expect "and says the list could not be read" \
  "$([[ "$out" == *"could not be read"* ]] && echo yes || echo no)" "$out"
expect "and files nothing" "$(logged "issue create" && echo no || echo yes)" "$(cat "$GH_LOG")"

echo
echo "the rehearsal takes the same path a real finding takes"

# `watch-agent.sh` learned this on 2026-08-04: a fabricated finding injected after
# the report was rendered reached the decision and not the body, and the first
# rehearsal filed an issue saying nothing was wrong.
setup; out=$(RED_ON_MAIN_FORCE=a-workflow-that-does-not-exist bash "$SCRIPT" check "$WORK/report.md"); rc=$?
expect "the fabricated workflow reaches the decision" "$([ $rc -eq 1 ] && echo yes || echo no)" "rc=$rc"
expect "and the report, not only the decision" \
  "$(grep -q 'a-workflow-that-does-not-exist' "$WORK/report.md" && echo yes || echo no)" "$(cat "$WORK/report.md")"

setup; bash "$SCRIPT" check "$WORK/report.md" >/dev/null
expect "nothing is fabricated without the switch" \
  "$([ ! -s "$WORK/report.md" ] && echo yes || echo no)" "$(cat "$WORK/report.md")"

echo
echo "no gate is created anywhere in this check"

# `#193`: "It does not become a required check or a gate." A grep is blunt and
# that is the point — it fails if somebody later wires this into branch
# protection, which is exactly when nobody re-reads the issue.
found=$(grep -nE '^[^#]*(branch_protection|required_status_checks|protection)' \
          "$SCRIPT" "$ROOT/.github/workflows/red-on-main.yml" 2>/dev/null)
expect "nothing touches branch protection" "$([ -z "$found" ] && echo yes || echo no)" "$found"

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "all checks passed"
  exit 0
fi
printf 'failed: %s\n' "${FAILURES[*]}"
exit 1

#!/bin/bash
# Does `ci-status-label.yml` label the right issues, clear them only when it is
# true to, and **end 0 on a run that did something**? `kolonie-docs#406`.
#
# Usage: bash .github/tests/ci-status-label.test.sh
#
# ## The rejection case, and why it is the first one here
#
# #406 is the whole reason this file exists. The step's last statement was
# `[ "$found" = false ] && echo …`, and `found` is true exactly when the pull
# request closed an issue — which is every run this workflow exists for. An
# AND-list whose test is false returns 1; it was the last statement of the loop,
# the loop was the last command of the block, and so the step ended red on every
# run that had work and green on every run that had none. Two of the last ten
# runs on `kolonie-platform` were red, both after doing their job correctly.
#
# `set -e` never entered into it, which is why reading the source did not find
# it. The failing `[` is the left side of an AND-list and is exempt. What failed
# the step was the status the script *ended* on.
#
# Every case below therefore asserts the exit status as well as the effect. A
# test that only asserted "the label was applied" would have passed against the
# broken version, which is how this survived from the file's first commit.
#
# ## Why a stub and not a fixture repository
#
# The interesting branches are reachable only from events this repository cannot
# produce on demand — a red build on a fork's pull request, two open pull
# requests closing one issue. Same approach as `rehearse-triage.sh`: read the
# `run:` block out of the workflow, put a stub `gh` on PATH, assert on what it
# would have done. It reads the workflow rather than a copy, so a test that
# passes is a statement about the file CI runs.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORKFLOW="$ROOT/.github/workflows/ci-status-label.yml"
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

command -v python3 >/dev/null || { echo "python3 is required"; exit 1; }

# The step's script and the names of the variables it is given, from one parse.
# `rehearse-triage.sh` learned this the expensive way: a harness that restates
# what the workflow reads drifts from it, and the failure reads as seven broken
# assertions rather than one unset variable.
python3 - "$WORKFLOW" "$WORK" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
out = sys.argv[2]
for job in doc["jobs"].values():
    for step in job["steps"]:
        if "run" in step:
            open(f"{out}/reflect.sh", "w").write(step["run"])
            open(f"{out}/reflect.env", "w").write(
                "".join(f"{key}=\n" for key in (step.get("env") or {}))
            )
PY

[ -s "$WORK/reflect.sh" ] || { echo "no run: block was read from the workflow — the parse is broken, not the workflow"; exit 1; }
[ -s "$WORK/reflect.env" ] || { echo "no env: block was read from the workflow — the parse is broken, not the workflow"; exit 1; }
mapfile -t DEFAULTS < "$WORK/reflect.env"

mkdir -p "$WORK/bin"

# Answers the six questions the step asks, each from a file the case sets up.
# The real `gh` applies `--jq`, so the fixtures hold the already-projected lines
# the script reads rather than API JSON.
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/bash
echo "gh $*" >> "$GH_LOG"
case "$*" in
  *"/commits/"*"/pulls"*)
      cat "$FIX/prs" 2>/dev/null ;;
  "api graphql"*)
      # Which issues does pull request N close? `-F number=N`.
      n=""
      for ((i = 1; i <= $#; i++)); do
        [[ "${!i}" == number=* ]] && n="${!i#number=}"
      done
      cat "$FIX/closes.$n" 2>/dev/null ;;
  *"actions/runs?head_sha="*)
      # The commit is in one argument, so it is read out of that argument. A
      # `${*#*head_sha=}` over the whole list strips the pattern from every
      # element and hands back a filename with the subcommand still in it.
      sha=""
      for ((i = 1; i <= $#; i++)); do
        [[ "${!i}" == *head_sha=* ]] && { sha=${!i#*head_sha=}; sha=${sha%%&*}; }
      done
      cat "$FIX/conclusion.$sha" 2>/dev/null ;;
  *"pulls?state=open"*)
      cat "$FIX/openprs" 2>/dev/null ;;
  "issue view"*)
      # `has_label` greps for an exact `true`, so an empty answer is a no.
      cat "$FIX/haslabel.$3" 2>/dev/null ;;
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
  export FIX="$WORK/fixtures" GH_LOG="$WORK/gh.log"
  rm -rf "$FIX"; mkdir -p "$FIX"; : > "$GH_LOG"
  # One open pull request heading the commit, closing one issue in this
  # repository, with no other open pull request beside it.
  printf '7\n'                            > "$FIX/prs"
  printf 'Kolonie-AI/kolonie-docs 42\n'   > "$FIX/closes.7"
  : > "$FIX/openprs"
}

# Every declared name defaulted to empty, then the case's own values on top —
# `env` applies its assignments in order, so the last one wins. A name added to
# the workflow's `env:` block tomorrow arrives here defaulted rather than unset,
# and `set -u` does not kill the run on line 3.
run_step() {
  env "${DEFAULTS[@]}" \
      REPO=Kolonie-AI/kolonie-docs \
      LABEL=ci:failed \
      WORKFLOW_NAME=CI \
      RUN_URL=https://example.invalid/run/1 \
      HEAD_SHA=deadbee \
      "$@" \
      PATH="$PATH" GH_LOG="$GH_LOG" FIX="$FIX" \
      bash "$WORK/reflect.sh" 2>&1
}

logged() { grep -q -- "$1" "$GH_LOG"; }

echo "a failing build on a pull request that closes an issue (#406)"

# **The regression case.** Against the AND-list this exited 1 having done
# everything right, which is the defect in one line.
setup
out=$(run_step RUN_EVENT=pull_request CONCLUSION=failure); rc=$?
expect "exits 0" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc
$out"
expect "the label is applied" \
  "$(logged 'issue edit 42 --repo Kolonie-AI/kolonie-docs --add-label ci:failed' && echo yes || echo no)" "$(cat "$GH_LOG")"
expect "and the label is created first, in case the repository lacks it" \
  "$(logged 'label create ci:failed' && echo yes || echo no)" "$(cat "$GH_LOG")"

setup; printf 'true\n' > "$FIX/haslabel.42"
out=$(run_step RUN_EVENT=pull_request CONCLUSION=failure); rc=$?
expect "an issue already labelled exits 0 too" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc
$out"
expect "and is not relabelled" "$(logged 'add-label' && echo no || echo yes)" "$(cat "$GH_LOG")"

echo
echo "a passing build"

setup; printf 'true\n' > "$FIX/haslabel.42"
out=$(run_step RUN_EVENT=pull_request CONCLUSION=success); rc=$?
expect "exits 0" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc
$out"
expect "the label is cleared" \
  "$(logged 'issue edit 42 --repo Kolonie-AI/kolonie-docs --remove-label ci:failed' && echo yes || echo no)" "$(cat "$GH_LOG")"

# **The truthfulness rule the header states.** Two open pull requests can close
# one issue; clearing while the other is red would make the label lie.
setup; printf 'true\n' > "$FIX/haslabel.42"
printf '7 deadbee\n8 c0ffee\n'          > "$FIX/openprs"
printf 'Kolonie-AI/kolonie-docs 42\n'   > "$FIX/closes.8"
printf 'failure\n'                      > "$FIX/conclusion.c0ffee"
out=$(run_step RUN_EVENT=pull_request CONCLUSION=success); rc=$?
expect "a second red pull request keeps the label" \
  "$(logged 'remove-label' && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "and that run exits 0 as well" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc
$out"

setup
out=$(run_step RUN_EVENT=pull_request CONCLUSION=success); rc=$?
expect "an unlabelled issue is left alone" "$(logged 'remove-label' && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "and says nothing to clear" \
  "$([[ "$out" == *"nothing to clear"* ]] && echo yes || echo no)" "$out"

echo
echo "the cases with nothing to reflect"

# The line #406's fix had to keep: a pull request closing no issue still says so.
setup; : > "$FIX/closes.7"
out=$(run_step RUN_EVENT=pull_request CONCLUSION=failure); rc=$?
expect "a pull request closing no issue exits 0" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc
$out"
expect "and still says so out loud" \
  "$([[ "$out" == *"closes no issue"* ]] && echo yes || echo no)" "$out"
expect "and labels nothing" "$(logged 'issue edit' && echo no || echo yes)" "$(cat "$GH_LOG")"

# The token is scoped to one repository, so a cross-repo link is reported and
# skipped rather than failing a reflection nobody could fix from here.
setup; printf 'Kolonie-AI/kolonie-platform 900\n' > "$FIX/closes.7"
out=$(run_step RUN_EVENT=pull_request CONCLUSION=failure); rc=$?
expect "an issue in another repository exits 0" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc
$out"
expect "and is skipped in the log rather than attempted" \
  "$([[ "$out" == *"another repository"* ]] && echo yes || echo no)" "$out"
expect "with no edit attempted" "$(logged 'issue edit' && echo no || echo yes)" "$(cat "$GH_LOG")"

setup
out=$(run_step RUN_EVENT=push CONCLUSION=failure); rc=$?
expect "a push has no pull request to speak for" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc
$out"
expect "and asks GitHub nothing" "$([ ! -s "$GH_LOG" ] && echo yes || echo no)" "$(cat "$GH_LOG")"

# `ci.yml` cancels a superseded run. Reading that as either verdict would state
# something about a build that was abandoned.
setup; printf 'true\n' > "$FIX/haslabel.42"
out=$(run_step RUN_EVENT=pull_request CONCLUSION=cancelled); rc=$?
expect "a cancelled run leaves the label as it is" \
  "$(logged 'issue edit' && echo no || echo yes)" "$(cat "$GH_LOG")"
expect "and exits 0" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc
$out"

setup; : > "$FIX/prs"
out=$(run_step RUN_EVENT=pull_request CONCLUSION=failure); rc=$?
expect "a commit heading no open pull request exits 0" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc
$out"

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "ci-status-label: all cases pass"
  exit 0
fi
printf 'ci-status-label: %d failed\n' "${#FAILURES[@]}"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

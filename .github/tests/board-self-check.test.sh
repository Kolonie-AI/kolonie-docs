#!/bin/bash
# Does the board self-check report correctly, and does it keep its hands off the board?
#
# Usage: bash .github/tests/board-self-check.test.sh
#
# `kolonie-docs#132` asks for two properties to be proved rather than asserted:
# that a second issue is not opened while the first is open — *"a test or a
# documented guard, not a hope"* — and that nothing here ever writes to the
# board. Both are checked here against a **stubbed `gh`**, which is the only way
# to exercise the branch where an issue already exists without filing one.
#
# The stub records every `gh` invocation to a log and answers from files the
# case sets up. It does not run jq, so the `existing` fixture holds the *answer*
# the lookup would produce — a bare issue number, or nothing. That makes the board-touching assertion exhaustive rather than a
# reading of the script: any `item-add`, `item-edit` or `archive` would appear in
# the log, whatever code path produced it.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/board-self-check.sh"
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export GITHUB_REPOSITORY="Kolonie-AI/kolonie-docs"
export RUN_URL="https://example.invalid/run/1"
# The stub has no index and no latency, so the visibility wait has nothing to
# wait for. `existing_delay` is how a case asks for some anyway.
export VISIBILITY_POLL=0 VISIBILITY_ATTEMPTS=4

# The stub. Every case writes the answers it wants into $WORK before running.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >> "$GH_LOG"
# `#237`: issue bodies travel as `--body-file` now, so a stub that logged only
# the argument list could no longer see what was written. Log the file too, or
# every assertion about body text silently passes on an empty haystack.
for _i in $(seq 1 $#); do
  eval "_a=\${$_i}"
  if [ "$_a" = --body-file ]; then
    eval "_f=\${$((_i + 1))}"
    [ -f "$_f" ] && cat "$_f" >> "$GH_LOG"
  fi
done
case "$1 $2" in
  "api graphql")
    if [[ "$*" == *"projectV2(number:1){ id }"* ]]; then cat "$GH_FIXTURES/readable" 2>/dev/null
    # **5b's board read is GraphQL now** (`#271`): it goes through
    # `opencode-worker.sh board-read` rather than `gh project item-list`, which
    # is what 5a spends its whole header explaining the cost of. Recognised by
    # the paging clause, which neither of the other two queries has.
    #
    # **The board fixture stays as it is: `owner/repo#n`, one per line.** That
    # is what the old call returned, because the `--jq` that reduced it to that
    # was an argument to `gh`; the filter now lives in the script, so the shape
    # it filters is assembled here instead. Every case below writes the fixture
    # the way it always did — including the short one that proves 5b refuses to
    # accuse a hundred issues on a failed read.
    elif [[ "$*" == *"items(first: 100"* ]]; then
      jq -Rn '[inputs | select(length > 0) | capture("(?<repo>.+)#(?<n>[0-9]+)$")]
        | {data:{organization:{projectV2:{items:{
            pageInfo:{hasNextPage:false,endCursor:null},
            nodes:[ .[]
              | {id:("ITEM_" + .n),
                 fieldValueByName:{name:"Ready"},
                 content:{number:(.n|tonumber), title:"untitled", url:"",
                          repository:{nameWithOwner:.repo, url:""},
                          labels:{nodes:[]}}} ]}}}}}' \
        "$GH_FIXTURES/board" 2>/dev/null
    else
      cat "$GH_FIXTURES/pruning" 2>/dev/null
      [ -s "$GH_FIXTURES/pruning_err" ] && cat "$GH_FIXTURES/pruning_err" >&2
    fi ;;
  "project item-list") cat "$GH_FIXTURES/board" 2>/dev/null ;;
  "repo list")        cat "$GH_FIXTURES/repos" 2>/dev/null ;;
  # 5c asks two things of every repository, and both answer per repository —
  # which is the whole point of the check, so the fixtures are per repository
  # too. A file that is absent is the gap; `case_setup` writes the healthy ones.
  "label list")
    for _i in $(seq 1 $#); do
      eval "_a=\${$_i}"
      [ "$_a" = --repo ] && { eval "_r=\${$((_i + 1))}"; cat "$GH_FIXTURES/labels_${_r##*/}" 2>/dev/null; }
    done ;;
  "api repos/"*)
    _p=${2#repos/}
    case "$_p" in
      */contents/.github/workflows/triage.yml)
        _r=${_p%%/contents/*}
        [ -f "$GH_FIXTURES/triage_${_r##*/}" ] || exit 1
        base64 -w0 < "$GH_FIXTURES/triage_${_r##*/}" ;;
      */contents/.github/workflows/review.yml)
        _r=${_p%%/contents/*}
        [ -f "$GH_FIXTURES/review_${_r##*/}" ] || exit 1 ;;
    esac ;;
  "issue list")
    # Two different listings reach this stub and they must not be confused.
    # `#237` moved the *finding* lookup into watch-finding.sh, which asks for
    # `--state all` because a closed finding that came back is the case the
    # whole issue is about. 5b's own listing asks for `--state open` per
    # repository. Gating on the label stopped working when the lookup moved;
    # gating on `true` swallowed 5b's listing as well, which is worse.
    if [[ "$*" == *"--state all"* ]]; then
      # `existing_delay` is how many of these answer empty before `existing`
      # starts coming back — the propagation `await_visible` waits out.
      n=$(cat "$GH_FIXTURES/.calls" 2>/dev/null || echo 0); n=$((n + 1))
      echo "$n" > "$GH_FIXTURES/.calls"
      d=$(cat "$GH_FIXTURES/existing_delay" 2>/dev/null || echo 0)
      [ "$n" -gt "$d" ] && cat "$GH_FIXTURES/existing" 2>/dev/null
    else cat "$GH_FIXTURES/issues" 2>/dev/null; fi ;;
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
  # A healthy board by default: archiving on, 25 items, every open issue on it.
  echo "PVT_kwDOEmwuYs4BebbB" > "$GH_FIXTURES/readable"
  # 5a reads Done items as "<updatedAt> <repo>#<n>". Everything recent by
  # default, so the archive looks like it is doing its job.
  RECENT=$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)
  { echo "$RECENT Kolonie-AI/kolonie-docs#10"; echo "$RECENT Kolonie-AI/kolonie-docs#11"; } > "$GH_FIXTURES/pruning"
  : > "$GH_FIXTURES/pruning_err"
  for i in $(seq 1 25); do echo "Kolonie-AI/kolonie-docs#$i"; done > "$GH_FIXTURES/board"
  echo "kolonie-docs" > "$GH_FIXTURES/repos"
  for i in $(seq 1 25); do echo "Kolonie-AI/kolonie-docs#$i"; done > "$GH_FIXTURES/issues"
  : > "$GH_FIXTURES/existing"
  # 5c is healthy by default: every repository §5 names has the whole
  # vocabulary, a `triage.yml` that calls the reusable workflow, and a reviewer.
  # A case that wants a gap removes one of these rather than building the other
  # four, so a finding in a case is the thing that case is about.
  for r in kolonie-docs kolonie-platform kolonie-infra kolonie-website kolonie-email; do
    covered "$r"
  done
}

# The vocabulary comes from the script that writes it, exactly as 5c asks for it
# — a fixture holding its own copy of the eight labels would pass this test on
# the day the two lists stopped agreeing, which is the only day it matters.
covered() {
  bash "$ROOT/.github/scripts/board-triage.sh" vocabulary > "$GH_FIXTURES/labels_$1"
  echo "uses: Kolonie-AI/kolonie-docs/.github/workflows/inbound-triage.yml@main" > "$GH_FIXTURES/triage_$1"
  : > "$GH_FIXTURES/review_$1"
}

logged() { grep -q -- "$1" "$GH_LOG"; }

echo "a healthy board is silent"

setup
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "exit 0 when both answers are right" "$([ $rc -eq 0 ] && echo yes || echo no)" "rc=$rc"
expect "says so in one line" "$([[ "$out" == *"pruning itself"* ]] && echo yes || echo no)" "$out"
expect "the report file is empty" "$([ ! -s "$WORK/report" ] && echo yes || echo no)" "$(cat "$WORK/report")"

echo
echo "5a — the pruning"

# The failure it exists for: something has sat in Done, untouched, for longer
# than the archive filter's fortnight plus a week of slack.
setup; echo "$(date -u -d '40 days ago' +%Y-%m-%dT%H:%M:%SZ) Kolonie-AI/kolonie-docs#7" >> "$GH_FIXTURES/pruning"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a stale Done item fails" "$([ $rc -eq 1 ] && echo yes || echo no)" "rc=$rc"
expect "and names it" "$([[ "$out" == *"kolonie-docs#7"* ]] && echo yes || echo no)" "$out"
expect "and points at the archive setting" \
  "$([[ "$out" == *"Auto-archive items"* ]] && echo yes || echo no)" "$out"

# Slack is deliberate: the filter turns on `updated:`, so an item closed three
# weeks ago but commented on yesterday is legitimately still there.
setup; echo "$(date -u -d '16 days ago' +%Y-%m-%dT%H:%M:%SZ) Kolonie-AI/kolonie-docs#8" >> "$GH_FIXTURES/pruning"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "an item inside the slack window is not a finding" "$([ $rc -eq 0 ] && echo yes || echo no)" "$out"

setup; : > "$GH_FIXTURES/pruning"; echo "gh: Resource not accessible" > "$GH_FIXTURES/pruning_err"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "an unreadable Done column fails, rather than reading as clean" "$([ $rc -eq 1 ] && echo yes || echo no)" "rc=$rc"
expect "and carries what the API said" "$([[ "$out" == *"Resource not accessible"* ]] && echo yes || echo no)" "$out"

echo
echo "5b — the arriving"

setup; echo "Kolonie-AI/kolonie-docs#99" >> "$GH_FIXTURES/issues"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "an issue not on the board fails" "$([ $rc -eq 1 ] && echo yes || echo no)" "rc=$rc"
expect "and names it" "$([[ "$out" == *"kolonie-docs#99"* ]] && echo yes || echo no)" "$out"

# The failure that would file a hundred false lines. A board listing that comes
# back short is a spent budget or a lost scope, never an empty board.
setup; echo "Kolonie-AI/kolonie-docs#1" > "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a short board listing fails without accusing every issue" \
  "$([ $rc -eq 1 ] && [[ "$out" != *"#20"* ]] && echo yes || echo no)" "$out"
expect "and says why it did not run the comparison" \
  "$([[ "$out" == *"was not run"* ]] && echo yes || echo no)" "$out"

echo
echo "5c — is the automation pointed at the repository (#333)"

# What `kolonie-dns#17` and the `kolonie-openclaw` outage of 2026-08-13 both
# were, before either had an issue: a repository whose issues reach the board
# and whose labels do not exist, so a triage pass is billed for a decision it
# then throws away.
setup; grep -v '^agent:claude$' "$GH_FIXTURES/labels_kolonie-platform" > "$WORK/t" && mv "$WORK/t" "$GH_FIXTURES/labels_kolonie-platform"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a missing label fails" "$([ $rc -eq 1 ] && echo yes || echo no)" "rc=$rc"
expect "and names the repository and the label" \
  "$([[ "$out" == *"kolonie-platform"* && "$out" == *"missing labels: agent:claude"* ]] && echo yes || echo no)" "$out"
expect "and does not accuse the repositories that are fine" \
  "$([[ "$out" != *"kolonie-email"* ]] && echo yes || echo no)" "$out"

# The label half must not be able to report the whole vocabulary as missing off
# a listing that failed — the same floor 5b has, one repository wide.
setup; : > "$GH_FIXTURES/labels_kolonie-infra"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a repository whose labels could not be listed is not accused of having none" \
  "$([ $rc -eq 1 ] && [[ "$out" == *"could not be listed"* && "$out" != *"missing labels:"* ]] && echo yes || echo no)" "$out"

setup; rm -f "$GH_FIXTURES/triage_kolonie-website"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "no inbound triage fails" "$([ $rc -eq 1 ] && echo yes || echo no)" "rc=$rc"
expect "and says which file to copy" \
  "$([[ "$out" == *"kolonie-website"* && "$out" == *"inbound-triage.yml"* ]] && echo yes || echo no)" "$out"

# The gap the filename cannot see: `triage.yml` is present and calls something
# else, which reads as covered to anything that checks only that the file is
# there. This is why the check reads the caller.
setup; echo "uses: ./.github/workflows/something-local.yml" > "$GH_FIXTURES/triage_kolonie-website"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a triage.yml that calls something else is not covered" \
  "$([ $rc -eq 1 ] && [[ "$out" == *"kolonie-website"* ]] && echo yes || echo no)" "$out"

setup; rm -f "$GH_FIXTURES/review_kolonie-email"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "no reviewer fails" "$([ $rc -eq 1 ] && echo yes || echo no)" "rc=$rc"
expect "and names it" \
  "$([[ "$out" == *"kolonie-email"* && "$out" == *"review.yml"* ]] && echo yes || echo no)" "$out"

# The point of the check, stated as a case: a repository nobody has filed an
# issue about yet is checked because it is on the board, not because it broke.
setup; echo "Kolonie-AI/kolonie-openclaw#5" >> "$GH_FIXTURES/board"
echo "Kolonie-AI/kolonie-openclaw#5" >> "$GH_FIXTURES/issues"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a repository that reached the board is checked without an issue being filed in it" \
  "$([ $rc -eq 1 ] && [[ "$out" == *"kolonie-openclaw"* ]] && echo yes || echo no)" "$out"

setup; echo "Kolonie-AI/kolonie-openclaw#5" >> "$GH_FIXTURES/board"
echo "Kolonie-AI/kolonie-openclaw#5" >> "$GH_FIXTURES/issues"; covered kolonie-openclaw
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "and once it is covered, it is silent" "$([ $rc -eq 0 ] && echo yes || echo no)" "$out"

# §5 is explicit that no skill repository puts an issue on the board. A daily
# report that names six repositories for a thing that is not this check's
# business is one nobody opens; that they have no triage at all is filed
# separately rather than reported here every morning.
setup; echo "kolonie-hermes" >> "$GH_FIXTURES/repos"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a repository that is not on the board and not in §5 is out of scope" \
  "$([ $rc -eq 0 ] && [[ "$out" != *"kolonie-hermes"* ]] && echo yes || echo no)" "$out"

# The five are checked whether or not the listing came back, so a spent budget
# narrows this answer instead of silencing it — and says which of the two it is.
setup; echo "Kolonie-AI/kolonie-docs#1" > "$GH_FIXTURES/board"; rm -f "$GH_FIXTURES/review_kolonie-email"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a board listing that failed its floor narrows 5c rather than silencing it" \
  "$([[ "$out" == *"kolonie-email"* && "$out" == *"only the repositories"* ]] && echo yes || echo no)" "$out"

# The listing is read once for the whole run. 5b's read is what 5a's own header
# spends its length on the cost of; a second caller asking again would undo it.
setup; bash "$SCRIPT" check "$WORK/report" >/dev/null
expect "the board is read once for the whole run, not once per question" \
  "$([ "$(grep -c 'items(first: 100' "$GH_LOG")" -eq 1 ] && echo yes || echo no)" \
  "$(grep -c 'items(first: 100' "$GH_LOG") reads"

echo
echo "a token that cannot see the board says so, and files nothing"

setup; : > "$GH_FIXTURES/readable"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "exit 2, distinct from both answers" "$([ $rc -eq 2 ] && echo yes || echo no)" "rc=$rc"
expect "names it a configuration gap" \
  "$([[ "$out" == *"configuration gap"* ]] && echo yes || echo no)" "$out"
expect "does not report the board as broken" \
  "$([[ "$out" != *"Auto-archive is switched off"* && "$out" != *"not on the board"* ]] && echo yes || echo no)" "$out"
# Grepping for `project item-list` here stopped meaning anything the moment
# `#271` removed the call: an assertion that nothing does what nothing does any
# more passes for the wrong reason and would go on passing if 5b started reading
# the board again by its new name. The paging clause is what 5b's read is now.
expect "asks neither question" \
  "$(grep -q 'items(first: 100' "$GH_LOG" && echo no || echo yes)" "$(cat "$GH_LOG")"

echo
echo "reporting — the guard #132 asked to be proved"

setup; : > "$GH_FIXTURES/existing"
printf '5a — something is wrong\n' > "$WORK/report"
bash "$SCRIPT" report "$WORK/report" >/dev/null
expect "with no open issue, one is created" "$(logged 'issue create' && echo yes || echo no)"
expect "and it is labelled area:docs" "$(logged 'area:docs' && echo yes || echo no)"

setup; # `#237`: an existing finding is now recognised by the marker in its body,
# not by its title, so the stub returns what `gh issue list --json` returns.
jq -n '[{number:77, state:"OPEN", title:"whatever it was called",
          body:"prose\n\n<!-- watch-finding: board-unmaintained -->\n\nmore prose"}]' > $GH_FIXTURES/existing
printf '5a — something is wrong\n' > "$WORK/report"
bash "$SCRIPT" report "$WORK/report" >/dev/null
expect "with one already open, no second issue is created" \
  "$(logged 'issue create' && echo no || echo yes)" "$(grep -c . "$GH_LOG") gh calls"
expect "it comments on the open one instead" "$(logged 'issue comment 77' && echo yes || echo no)"

setup; # `#237`: an existing finding is now recognised by the marker in its body,
# not by its title, so the stub returns what `gh issue list --json` returns.
jq -n '[{number:77, state:"OPEN", title:"whatever it was called",
          body:"prose\n\n<!-- watch-finding: board-unmaintained -->\n\nmore prose"}]' > $GH_FIXTURES/existing
bash "$SCRIPT" resolve >/dev/null
expect "when both answers are right again, the issue is closed" \
  "$(logged 'issue close 77' && echo yes || echo no)"

setup; : > "$GH_FIXTURES/existing"
bash "$SCRIPT" resolve >/dev/null
expect "and closing nothing is not an error" "$(logged 'issue close' && echo no || echo yes)"

# The guard is not `--search`, and this case says why in the suite as well as in
# the script: search is eventually consistent, so a second run inside the
# indexing window would file a second issue. A stub cannot reproduce that
# latency, which is why the criterion also required a live rehearsal.
setup; # `#237`: an existing finding is now recognised by the marker in its body,
# not by its title, so the stub returns what `gh issue list --json` returns.
jq -n '[{number:77, state:"OPEN", title:"whatever it was called",
          body:"prose\n\n<!-- watch-finding: board-unmaintained -->\n\nmore prose"}]' > $GH_FIXTURES/existing
printf '5a — x\n' > "$WORK/report"
bash "$SCRIPT" report "$WORK/report" >/dev/null
expect "the lookup does not go through the search index" \
  "$(grep -q 'in:title' "$GH_LOG" && echo no || echo yes)" "$(cat "$GH_LOG")"

# And dropping `--search` was not enough, which is what `kolonie-docs#150`
# measured: no listing shows a just-filed issue either. So the filing run waits
# for its own issue rather than leaving the next run to race it.
setup; echo '2' > "$GH_FIXTURES/existing_delay"; # `#237`: an existing finding is now recognised by the marker in its body,
# not by its title, so the stub returns what `gh issue list --json` returns.
jq -n '[{number:77, state:"OPEN", title:"whatever it was called",
          body:"prose\n\n<!-- watch-finding: board-unmaintained -->\n\nmore prose"}]' > $GH_FIXTURES/existing
printf '5a — x\n' > "$WORK/report"
out=$(bash "$SCRIPT" report "$WORK/report")
expect "a filed issue is waited for until it is findable" \
  "$([[ "$out" == *"findable as #77"* ]] && echo yes || echo no)" "$out"

setup; echo '99' > "$GH_FIXTURES/existing_delay"; # `#237`: an existing finding is now recognised by the marker in its body,
# not by its title, so the stub returns what `gh issue list --json` returns.
jq -n '[{number:77, state:"OPEN", title:"whatever it was called",
          body:"prose\n\n<!-- watch-finding: board-unmaintained -->\n\nmore prose"}]' > $GH_FIXTURES/existing
printf '5a — x\n' > "$WORK/report"
out=$(bash "$SCRIPT" report "$WORK/report")
expect "and the wait is bounded and loud rather than a hang" \
  "$([[ "$out" == *"::warning::"* ]] && echo yes || echo no)" "$out"

echo
echo "it never writes to the board"

# Every command, over every fixture, into one log. Anything that mutates the
# board would have to appear here.
: > "$WORK/all"
for fixture in healthy off missing uncovered; do
  setup
  case $fixture in
    off)     echo "$(date -u -d '40 days ago' +%Y-%m-%dT%H:%M:%SZ) Kolonie-AI/kolonie-docs#7" >> "$GH_FIXTURES/pruning" ;;
    missing) echo "Kolonie-AI/kolonie-docs#99" >> "$GH_FIXTURES/issues" ;;
    # 5c's fix is a workflow or a label in somebody else's repository, which is
    # more of a decision than 5b's is. It has to be as unable to take it.
    uncovered) : > "$GH_FIXTURES/labels_kolonie-platform"; rm -f "$GH_FIXTURES/triage_kolonie-infra" "$GH_FIXTURES/review_kolonie-email" ;;
  esac
  bash "$SCRIPT" check "$WORK/report" >/dev/null
  printf '5a — x\n' > "$WORK/report"
  bash "$SCRIPT" report "$WORK/report" >/dev/null
  bash "$SCRIPT" resolve >/dev/null
  cat "$GH_LOG" >> "$WORK/all"
done
for forbidden in "item-add" "item-edit" "archiveProjectV2Item" "unarchive" "item-delete" \
                 "label create" "label delete" "workflow run"; do
  expect "no $forbidden in any code path" \
    "$(grep -q -- "$forbidden" "$WORK/all" && echo no || echo yes)" \
    "$(grep -- "$forbidden" "$WORK/all" | head -1)"
done

echo
if [ ${#FAILURES[@]} -gt 0 ]; then
  printf '%d failed: %s\n' "${#FAILURES[@]}" "$(IFS=,; echo "${FAILURES[*]}")"
  exit 1
fi
echo "all cases pass"

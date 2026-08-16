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
    #
    # **5d needs a line to be able to say more than that** (`#329`), so five
    # optional `|`-separated fields follow: Status, state, `closedAt`, the
    # card's own `updatedAt` (`#345`), and `stateReason` (`#426`). A line
    # without them is `Ready` and `OPEN`, which is what every case written
    # before 5d existed means by it, and an explicitly empty second field is the
    # item with no Status at all that 5d is a third about.
    #
    # **A missing card timestamp is a card with none, not a recent one.** 5d
    # reports an item whose `updatedAt` it cannot read rather than skipping it,
    # so the default here has to be the same way round: a case that says nothing
    # about the card's clock is one where the grace window cannot apply.
    #
    # `stateReason` defaults to null, which is the state of every issue that was
    # never closed — the majority, and the kind the cases written before `#426`
    # all meant. The key is always emitted, because *absent* and *null* are
    # different answers to 5d and the `no_reason` sentinel below is how the
    # first one is expressed.
    elif [[ "$*" == *"items(first: 100"* ]]; then
      jq -Rn '[inputs | select(length > 0) | split("|")
        | {status: (.[1] // "Ready"), state: (.[2] // "OPEN"), closedAt: (.[3] // ""),
           updatedAt: (.[4] // ""), stateReason: (.[5] // "")}
          + (.[0] | capture("(?<repo>.+)#(?<n>[0-9]+)$"))]
        | {data:{organization:{projectV2:{items:{
            pageInfo:{hasNextPage:false,endCursor:null},
            nodes:[ .[]
              | {id:("ITEM_" + .n),
                 updatedAt:(if .updatedAt == "" then null else .updatedAt end),
                 fieldValueByName:(if .status == "" then null else {name:.status} end),
                 content:{number:(.n|tonumber), title:"untitled", url:"",
                          state:.state,
                          stateReason:(if .stateReason == "" then null else .stateReason end),
                          closedAt:(if .closedAt == "" then null else .closedAt end),
                          repository:{nameWithOwner:.repo, url:""},
                          labels:{nodes:[]}}} ]}}}}}' \
        "$GH_FIXTURES/board" 2>/dev/null \
        | if [ -f "$GH_FIXTURES/no_state" ]; then
            # A board read that answers without `state` — the query having been
            # changed back, or an older board file being replayed. 5d must say
            # so rather than reporting every column clean.
            jq -c '(.data.organization.projectV2.items.nodes[].content) |= del(.state, .closedAt)'
          elif [ -f "$GH_FIXTURES/no_reason" ]; then
            # The same failure one field along: a board that still says whether
            # an issue is open and no longer says why. 5d must fall back to one
            # undistinguished list rather than calling every one of them
            # never-closed and being confidently wrong about half.
            jq -c '(.data.organization.projectV2.items.nodes[].content) |= del(.stateReason)'
          else cat; fi
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
    # **A `.fail` sentinel, because this stub ends in `exit 0`** and could
    # otherwise not express a listing that failed at all (`#349`). An absent
    # fixture is not that case: it is `cat` finding nothing, which reaches the
    # caller as a repository that answered and has no labels. The two want
    # opposite fixes — one is a credential, the other is `gh label create` — so
    # the stub has to be able to produce both.
    for _i in $(seq 1 $#); do
      eval "_a=\${$_i}"
      [ "$_a" = --repo ] && {
        eval "_r=\${$((_i + 1))}"
        [ -f "$GH_FIXTURES/labels_${_r##*/}.fail" ] && exit 1
        cat "$GH_FIXTURES/labels_${_r##*/}" 2>/dev/null
      }
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
#
# **The stub could not express this case until `#349`**, and that is why the
# check was wrong about it in production. `: >` writes an empty fixture, which is
# `cat` succeeding with no output — a repository that answered and has no labels.
# The stub ends in `exit 0`, so nothing it did could make the call fail. This
# case stubbed *answered and empty* and asserted *could not be listed*, so it was
# pinning the inference the check has now stopped making rather than the failure
# it is named after. The `.fail` sentinel is what actually makes the call fail.
setup; : > "$GH_FIXTURES/labels_kolonie-infra.fail"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a repository whose labels could not be listed is not accused of having none" \
  "$([ $rc -eq 1 ] && [[ "$out" == *"could not be listed"* && "$out" != *"missing labels:"* ]] && echo yes || echo no)" "$out"

# The other half, and the case that was reported wrongly in production (`#349`).
# A repository that answers with GitHub's nine defaults and none of the Colony's
# eight has every wanted label missing and a listing that worked perfectly. It
# read as *the vocabulary is unverified*, which sends a reader to debug a token
# for something one `gh label create` fixes.
setup; : > "$GH_FIXTURES/labels_kolonie-infra"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a repository that answered and has none of them is told which are missing" \
  "$([ $rc -eq 1 ] && [[ "$out" == *"missing labels:"* ]] && [[ "$out" != *"could not be listed"* ]] && echo yes || echo no)" "$out"

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
# issue about yet is checked because the sweep is about to route its issues, not
# because it broke. Being in the organisation is the whole qualification (`#338`)
# — it does not have to have reached the board first, which is the state every
# repository is in on the day it is created.
setup; echo "kolonie-openclaw" >> "$GH_FIXTURES/repos"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a repository the sweep covers is checked without an issue being filed in it" \
  "$([ $rc -eq 1 ] && [[ "$out" == *"kolonie-openclaw"* ]] && echo yes || echo no)" "$out"

setup; echo "kolonie-openclaw" >> "$GH_FIXTURES/repos"; covered kolonie-openclaw
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "and once it is covered, it is silent" "$([ $rc -eq 0 ] && echo yes || echo no)" "$out"

# The scope is the sweep's, so a runtime repository is in it. It was exempt while
# nothing put its issues on the board; `#332` ended that and `#338` took the
# exemption out rather than leaving a check that agrees with a premise that has
# gone.
setup; echo "kolonie-hermes" >> "$GH_FIXTURES/repos"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a runtime repository is in scope rather than exempt" \
  "$([ $rc -eq 1 ] && [[ "$out" == *"kolonie-hermes"* ]] && echo yes || echo no)" "$out"

setup; echo "kolonie-hermes" >> "$GH_FIXTURES/repos"; covered kolonie-hermes
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "and it too goes quiet once it has the triage and the reviewer" \
  "$([ $rc -eq 0 ] && echo yes || echo no)" "$out"

# The five are checked whether or not the sweep's listing came back, so a spent
# budget narrows this answer instead of silencing it — and says which it was.
setup; : > "$GH_FIXTURES/repos"; rm -f "$GH_FIXTURES/review_kolonie-email"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a repository listing that failed narrows 5c rather than silencing it" \
  "$([[ "$out" == *"kolonie-email"* && "$out" == *"only the repositories"* ]] && echo yes || echo no)" "$out"

# The listing is read once for the whole run. 5b's read is what 5a's own header
# spends its length on the cost of; a second caller asking again would undo it.
setup; bash "$SCRIPT" check "$WORK/report" >/dev/null
expect "the board is read once for the whole run, not once per question" \
  "$([ "$(grep -c 'items(first: 100' "$GH_LOG")" -eq 1 ] && echo yes || echo no)" \
  "$(grep -c 'items(first: 100' "$GH_LOG") reads"

echo
echo "5d — is the item in the right place (#329)"

# The failure 5a and 5b are both blind to, as it stood on the live board on
# 2026-08-13: an item that is on the board — so 5b is satisfied — and in no
# column at all, because the built-in workflow that writes Status was disabled.
setup; echo "Kolonie-AI/kolonie-docs#327|" >> "$GH_FIXTURES/board"
echo "Kolonie-AI/kolonie-docs#327" >> "$GH_FIXTURES/issues"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "an item with no Status fails" "$([ $rc -eq 1 ] && echo yes || echo no)" "rc=$rc"
expect "and names it" "$([[ "$out" == *"kolonie-docs#327"* ]] && echo yes || echo no)" "$out"
# The item id is the part a reader cannot get without asking the board, so the
# command is printed complete rather than as a shape to fill in.
expect "and prints the one command that fixes it, with the item id and Inbox" \
  "$([[ "$out" == *"item-edit --id ITEM_327"* && "$out" == *"78639a6d"* ]] && echo yes || echo no)" "$out"

# Inbox is the destination because that is where the router looks — but not for
# an issue that is already finished. Recommending it there would send a closed
# issue back to the front of the loop.
setup; echo "Kolonie-AI/kolonie-docs#328||CLOSED|$(date -u -d '3 days ago' +%Y-%m-%dT%H:%M:%SZ)" >> "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a status-less item that is closed is sent to Done, not Inbox" \
  "$([[ "$out" == *"d37dbc2a"* && "$out" != *"78639a6d"* ]] && echo yes || echo no)" "$out"
expect "and is named once rather than by both halves" \
  "$([ "$(grep -c 'kolonie-docs#328' <<<"$out")" -eq 1 ] && echo yes || echo no)" "$out"

# `kolonie-platform#827`: closed when its pull request merged, still In Review
# hours later. 5a only looks at what is already in Done, so it never sees this.
setup; echo "Kolonie-AI/kolonie-docs#827|In Review|CLOSED|$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)" >> "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a closed item outside Done fails" "$([ $rc -eq 1 ] && echo yes || echo no)" "rc=$rc"
expect "and names it, the column it is in, and the move to Done" \
  "$([[ "$out" == *"kolonie-docs#827"* && "$out" == *"still in In Review"* && "$out" == *"d37dbc2a"* ]] && echo yes || echo no)" "$out"

setup; echo "Kolonie-AI/kolonie-docs#827|Done|CLOSED|$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)" >> "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a closed item that is in Done is where it belongs" "$([ $rc -eq 0 ] && echo yes || echo no)" "$out"

# The threshold is the whole difference between a check and a nuisance: an issue
# closed a minute ago is the built-in workflow working, not a finding.
setup; echo "Kolonie-AI/kolonie-docs#827|In Review|CLOSED|$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" >> "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a freshly closed item is lag, not a finding" "$([ $rc -eq 0 ] && echo yes || echo no)" "$out"

# The mirror, asked in one direction only until `#345`. `kolonie-platform#820`:
# never closed, because `feat: … (#820)` pushed straight to `main` closes
# nothing — and its card in Done since the morning.
setup; echo "Kolonie-AI/kolonie-platform#820|Done|OPEN||$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)" >> "$GH_FIXTURES/board"
echo "Kolonie-AI/kolonie-platform#820" >> "$GH_FIXTURES/issues"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "an open item sitting in Done fails" "$([ $rc -eq 1 ] && echo yes || echo no)" "rc=$rc"
expect "and names it and how long the card has been there" \
  "$([[ "$out" == *"kolonie-platform#820"* && "$out" == *"in Done since"* ]] && echo yes || echo no)" "$out"
# The never-closed kind is the one half that still prints no destination, and
# `#426` did not change that: the card is right and the issue is wrong, so a
# suggested move would paper over what was found.
expect "and suggests no move, because closing the issue is the repair" \
  "$([[ "$out" != *"item-edit"* && "$out" == *"never closed"* ]] && echo yes || echo no)" "$out"

# The other way in, which wore the same symptom until `#426` asked for
# `stateReason`. `kolonie-docs#285`: closed, then reopened by `red-on-main` into
# the one column the loop's queries do not read.
setup; echo "Kolonie-AI/kolonie-docs#285|Done|OPEN||$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)|REOPENED" >> "$GH_FIXTURES/board"
echo "Kolonie-AI/kolonie-docs#285" >> "$GH_FIXTURES/issues"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a reopened item sitting in Done fails" "$([ $rc -eq 1 ] && echo yes || echo no)" "rc=$rc"
expect "and says it was reopened rather than never closed" \
  "$([[ "$out" == *"were reopened"* && "$out" != *"never closed"* ]] && echo yes || echo no)" "$out"
expect "and prints the move to Inbox, which the other kind cannot have" \
  "$([[ "$out" == *"item-edit --id ITEM_285"* && "$out" == *"78639a6d"* ]] && echo yes || echo no)" "$out"

# Both at once: one symptom, two causes, two repairs — and each item named once,
# under the heading that matches its own cause.
setup; echo "Kolonie-AI/kolonie-docs#285|Done|OPEN||$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)|REOPENED" >> "$GH_FIXTURES/board"
echo "Kolonie-AI/kolonie-platform#820|Done|OPEN||$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)" >> "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "the two kinds are reported apart, under a heading each" \
  "$([[ "$out" == *"were reopened"* && "$out" == *"never closed"* ]] && echo yes || echo no)" "$out"
expect "and the never-closed one carries no move of its own" \
  "$([ "$(grep -c 'item-edit' <<<"$out")" -eq 1 ] && echo yes || echo no)" "$out"
expect "and each is named once" \
  "$([ "$(grep -c 'kolonie-platform#820' <<<"$out")" -eq 1 ] && echo yes || echo no)" "$out"

# `stateReason` arrives from the same paginated read as `state`. If it stops
# arriving, calling every one of these never-closed would be confidently wrong
# about half of them — so the two halves collapse back into `#345`'s one list.
setup; : > "$GH_FIXTURES/no_reason"
echo "Kolonie-AI/kolonie-docs#285|Done|OPEN||$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)" >> "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a listing carrying no stateReason still reports the item" \
  "$([ $rc -eq 1 ] && [[ "$out" == *"kolonie-docs#285"* ]] && echo yes || echo no)" "$out"
expect "and says it cannot tell the two causes apart, rather than guessing one" \
  "$([[ "$out" == *"cannot say why"* && "$out" != *"never closed,"* && "$out" != *"item-edit"* ]] && echo yes || echo no)" "$out"

# The grace window, and the reason it is the card's clock rather than the
# issue's: somebody moving a card and closing the issue a moment later is the
# ordinary way an issue finishes, not a finding.
setup; echo "Kolonie-AI/kolonie-platform#820|Done|OPEN||$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" >> "$GH_FIXTURES/board"
echo "Kolonie-AI/kolonie-platform#820" >> "$GH_FIXTURES/issues"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a card moved to Done minutes ago is lag, not a finding" "$([ $rc -eq 0 ] && echo yes || echo no)" "$out"

# A card whose own timestamp did not arrive must be reported rather than
# skipped: an absent field that silences a comparison is the failure mode the
# whole file is written against.
setup; echo "Kolonie-AI/kolonie-platform#820|Done|OPEN" >> "$GH_FIXTURES/board"
echo "Kolonie-AI/kolonie-platform#820" >> "$GH_FIXTURES/issues"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "an open item in Done with no card timestamp is still named" \
  "$([ $rc -eq 1 ] && [[ "$out" == *"kolonie-platform#820"* ]] && echo yes || echo no)" "$out"

# The rejection case `#345` asks for, both halves of it: the two states that are
# where they belong say nothing at all.
setup; echo "Kolonie-AI/kolonie-docs#827|Done|CLOSED|$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)|$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)" >> "$GH_FIXTURES/board"
echo "Kolonie-AI/kolonie-platform#821|Ready|OPEN||$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)" >> "$GH_FIXTURES/board"
echo "Kolonie-AI/kolonie-platform#821" >> "$GH_FIXTURES/issues"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a closed item in Done and an open item in Ready are both silent" \
  "$([ $rc -eq 0 ] && echo yes || echo no)" "$out"

# The same floor 5b has, inherited rather than copied: a listing that came back
# short is a spent budget, and "every item is in no column" is the loudest
# possible way to be wrong about it.
setup; echo "Kolonie-AI/kolonie-docs#1|" > "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a short listing suppresses all three comparisons" \
  "$([[ "$out" != *"These board items are in no column"* && "$out" != *"are closed and are not in Done"* \
      && "$out" != *"were reopened"* && "$out" != *"were never closed"* && "$out" != *"cannot say why"* \
      && "$out" != *"item-edit"* ]] && echo yes || echo no)" "$out"
expect "and says it is unverified rather than staying silent under 5b" \
  "$([[ "$out" == *"None of the three placement comparisons was run"* ]] && echo yes || echo no)" "$out"

# `state` arrives from the same paginated read as everything else. If it stops
# arriving, the closed half would report all-clear forever — which is the exact
# failure mode this file was written against.
setup; : > "$GH_FIXTURES/no_state"
echo "Kolonie-AI/kolonie-docs#827|In Review|CLOSED|$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)" >> "$GH_FIXTURES/board"
out=$(bash "$SCRIPT" check "$WORK/report"); rc=$?
expect "a listing carrying no issue state is a defect, not a clean board" \
  "$([ $rc -eq 1 ] && [[ "$out" == *"carries no issue state"* ]] && echo yes || echo no)" "$out"

# It reads the board once for all four questions, exactly as 5c does — a third
# reader asking again would undo what `#271` bought.
setup; echo "Kolonie-AI/kolonie-docs#327|" >> "$GH_FIXTURES/board"
bash "$SCRIPT" check "$WORK/report" >/dev/null
expect "5d costs no additional board read" \
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
for fixture in healthy off missing uncovered misplaced; do
  setup
  case $fixture in
    off)     echo "$(date -u -d '40 days ago' +%Y-%m-%dT%H:%M:%SZ) Kolonie-AI/kolonie-docs#7" >> "$GH_FIXTURES/pruning" ;;
    missing) echo "Kolonie-AI/kolonie-docs#99" >> "$GH_FIXTURES/issues" ;;
    # 5c's fix is a workflow or a label in somebody else's repository, which is
    # more of a decision than 5b's is. It has to be as unable to take it.
    uncovered) : > "$GH_FIXTURES/labels_kolonie-platform"; rm -f "$GH_FIXTURES/triage_kolonie-infra" "$GH_FIXTURES/review_kolonie-email" ;;
    # 5d is the one whose fix this script could actually perform — it holds the
    # item id and the option id and prints the mutation. That it prints it
    # instead is the property, so the fixture that produces both findings runs
    # through the same sweep as the rest.
    misplaced) { echo "Kolonie-AI/kolonie-docs#327|"
                 echo "Kolonie-AI/kolonie-docs#827|In Review|CLOSED|$(date -u -d '2 days ago' +%Y-%m-%dT%H:%M:%SZ)"; } >> "$GH_FIXTURES/board" ;;
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

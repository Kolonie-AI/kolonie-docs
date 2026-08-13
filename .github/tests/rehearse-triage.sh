#!/bin/bash
# Rehearse inbound-triage.yml without GitHub.
#
# Usage: ./.github/tests/rehearse-triage.sh
#
# The workflow it exercises decides what happens to the *first* thing an outside
# contributor ever sees from this project, and every one of its branches is
# reached only by an event this repository cannot produce on demand: an issue
# from a stranger, a pull request from a fork. Left untested it would be
# discovered wrong by a citizen, which is the one audience it exists for.
#
# So: extract the `run:` blocks from the workflow, put a stub `gh` on PATH, and
# assert on what each branch *would have done*. Same shape as
# `kolonie-infra/scripts/rehearse-deploy.sh`, and for the same reason — a script
# whose interesting branches only run in anger needs somewhere else to run.
#
# It reads the workflow rather than a copy of it. A test that restates the logic
# it is testing proves only that someone typed it twice.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORKFLOW="$ROOT/.github/workflows/inbound-triage.yml"
WORK=$(mktemp -d)
BIN="$WORK/.bin"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$BIN"

command -v python3 >/dev/null || { echo "python3 is required"; exit 1; }

# The step's script **and the names of the variables it is given** (`#192`).
#
# Both come from the same parse for the same reason the script does: a harness
# that restates what the workflow reads is a harness that drifts from it, and
# this one did. `0687f61` added `AUTHOR_TYPE` to the step's `env:` block, no case
# here set it, the extracted script runs under `set -u` — so every issue case
# died on line 27 before reaching a branch, and reported seven failed assertions
# about labelling and thanking that had never been attempted. The cause was one
# unset variable and not one of the seven things the output named.
#
# So every declared name is defaulted to empty below, and §12 then asserts that
# each one is actually exercised by something. Defaulting alone would trade a
# misleading failure for a quiet pass, which is the worse of the two.
python3 - "$WORKFLOW" "$WORK" <<'PY'
import sys, yaml
workflow, out = sys.argv[1], sys.argv[2]
doc = yaml.safe_load(open(workflow))
for name, job in doc["jobs"].items():
    for step in job["steps"]:
        if "run" in step:
            open(f"{out}/{name}.sh", "w").write(step["run"])
            # One `NAME=` per line, ready to hand to `env` as a default.
            open(f"{out}/{name}.env", "w").write(
                "".join(f"{key}=\n" for key in (step.get("env") or {}))
            )
PY

[ -s "$WORK/issue.env" ] || { echo "no env: block was read from the issue step — the parse is broken, not the workflow"; exit 1; }

mapfile -t ISSUE_DEFAULTS < "$WORK/issue.env"
mapfile -t PR_DEFAULTS < "$WORK/pull_request.env"

# --- the stub -------------------------------------------------------------
# Records every call and answers the questions the workflow asks: what
# permission does this author have, is this author in the organisation, what
# labels does the linked issue carry, and then the write calls it makes.
cat > "$BIN/gh" <<'STUB'
#!/bin/bash
echo "gh $*" >> "$GH_LOG"

case "$1 $2" in
  "api repos"*)
      # collaborators/<user>/permission — PERMISSION is what the case under test
      # says this author has. Empty means the call 404s, which is what GitHub
      # does for someone who is not a collaborator at all.
      [ -z "${PERMISSION:-}" ] && exit 1
      echo "${PERMISSION}"
      exit 0 ;;
  "api orgs"*)
      # orgs/<org>/members/<user> -i. The workflow reads the status line and
      # nothing else, so that is all this answers — and it answers three ways,
      # because the endpoint does (`#335`). `unknown` is the `302` a token that
      # is not itself an organisation member gets, and it is the case the real
      # `GITHUB_TOKEN` may well be in.
      #
      # The default is `outside`: an author with no push access who is not in
      # the organisation is the case this workflow exists for, and every case
      # written before `#335` meant exactly that. A case that means one of the
      # other two says so.
      case "${MEMBERSHIP:-outside}" in
        member)  echo "HTTP/2.0 204 No Content" ; exit 0 ;;
        unknown) echo "HTTP/2.0 302 Found"      ; exit 1 ;;
        *)       echo "HTTP/2.0 404 Not Found"  ; exit 1 ;;
      esac ;;
  "issue view")
      # The labels on the issue a pull request says it closes.
      echo "${ISSUE_LABELS:-}"
      exit 0 ;;
esac
exit 0
STUB
chmod +x "$BIN/gh"

pass=0; fail=0
check()    { if [ "$2" = "$3" ]; then echo "  ok   $1"; pass=$((pass+1)); else echo "  FAIL $1: expected [$3], got [$2]"; fail=$((fail+1)); fi; }
contains() { if grep -qF -- "$2" <<<"$1"; then echo "  ok   $3"; pass=$((pass+1)); else echo "  FAIL $3"; fail=$((fail+1)); fi; }
absent()   { if grep -qF -- "$2" <<<"$1"; then echo "  FAIL $3"; fail=$((fail+1)); else echo "  ok   $3"; pass=$((pass+1)); fi; }

# What a case set, so §12 can tell an exercised variable from a defaulted one.
# `env` and the trailing `bash` are not assignments and are skipped.
note_set() {
  local arg
  for arg in "$@"; do
    case "$arg" in [A-Z_]*=*) echo "${arg%%=*}" >> "$WORK/exercised" ;; esac
  done
}

# The defaults come first and the case's own `env` comes after, so a case always
# wins over the empty default for a variable it cares about.
run_issue() {
  : > "$WORK/gh.log"
  note_set "$@"
  GH_LOG="$WORK/gh.log" PATH="$BIN:$PATH" \
    env "${ISSUE_DEFAULTS[@]}" \
    REPO=Kolonie-AI/kolonie-platform NUMBER=123 AUTHOR=someagent AREA=platform \
    "$@" bash "$WORK/issue.sh" 2>&1
}

run_pr() {
  : > "$WORK/gh.log"
  note_set "$@"
  GH_LOG="$WORK/gh.log" PATH="$BIN:$PATH" \
    env "${PR_DEFAULTS[@]}" \
    REPO=Kolonie-AI/kolonie-platform NUMBER=456 AUTHOR=someagent AREA=platform \
    "$@" bash "$WORK/pull_request.sh" 2>&1
}

# Set by `run_issue`/`run_pr` themselves rather than by any case.
printf '%s\n' REPO NUMBER AUTHOR AREA > "$WORK/exercised"

# `GH_TOKEN` is the one declared variable no case can exercise: the stub `gh`
# never authenticates, so there is nothing for a value to change. Named here so
# that §12's list is a decision rather than an omission.
UNEXERCISED_BY_DESIGN="GH_TOKEN"

echo "== 1. an issue from outside the organisation gets all three labels"
# The case the workflow exists for. `area:` and `needs-triage` are unconditional
# for an author without push access: the API drops labels silently for anyone
# without it, so "forgot" and "could not" are the same case and there is no way
# to be in the first one. `from:external` is not — it is the answer to a second
# question, asked in §1b and §1c.
out=$(run_issue env EXISTING='[]' BODY='Something is broken.')
log=$(cat "$WORK/gh.log")
contains "$log" "--add-label area:platform,needs-triage,from:external" "labelled area, needs-triage and from:external"
contains "$log" "issue comment 123" "commented"
absent "$log" "from:citizen" "never from:citizen — nothing here came through a support ticket"

echo "== 1b. an organisation member without push access is not called external (#335)"
# The half of `#335` that no live issue had yet hit and that would have been
# discovered by mislabelling a colleague. Push access answers *could they have
# labelled it* — which is why the labels below are still applied — and says
# nothing at all about whether they are outside the Colony.
out=$(run_issue env MEMBERSHIP=member EXISTING='[]' BODY='x')
log=$(cat "$WORK/gh.log")
contains "$log" "--add-label area:platform,needs-triage" "still labelled, because they still could not have"
absent "$log" "from:" "and carries no provenance label at all"

echo "== 1c. a token that cannot answer applies nothing and says so (#335)"
# `GITHUB_TOKEN` acts as the repository rather than as a member, so it can get a
# `302` where a member would get `204`/`404`. Guessing either way is a wrong
# label that `board-triage.sh` will then never correct, because it only fills in
# a `from:` where none is present. `needs-triage` is already on, so the route
# stays capped in the meantime — silence here is a deferral, not a gap.
out=$(run_issue env MEMBERSHIP=unknown EXISTING='[]' BODY='x')
log=$(cat "$WORK/gh.log")
contains "$log" "--add-label area:platform,needs-triage" "labelled and routed as usual"
absent "$log" "from:" "no provenance guessed"
contains "$out" "left to board-triage.sh" "and the deferral is in the log"

echo "== 2. …even when they somehow arrive with labels already on"
# Not a hypothetical: an issue can be labelled by an automation before this runs.
# The author still could not have done it, so the labels still apply.
out=$(run_issue env EXISTING='["bug"]' BODY='Something is broken.')
contains "$(cat "$WORK/gh.log")" "from:external" "still marked as an outside contribution"

echo "== 3. a maintainer's labelled issue is left completely alone"
out=$(run_issue env PERMISSION=write EXISTING='["p1","area:platform"]' BODY='x')
log=$(cat "$WORK/gh.log")
absent "$log" "--add-label" "no labels applied"
absent "$log" "issue comment" "no comment posted"
contains "$out" "nothing to do" "and said why"

echo "== 4. a maintainer's *unlabelled* issue is labelled but not called outside work"
out=$(run_issue env PERMISSION=admin EXISTING='[]' BODY='x')
log=$(cat "$WORK/gh.log")
contains "$log" "--add-label area:platform,needs-triage" "labelled"
absent "$log" "from:" "no provenance label"
absent "$log" "api orgs" "and membership was not even asked — push access settles it"

echo "== 5. the comment asks for acceptance criteria only when there are none"
out=$(run_issue env EXISTING='[]' BODY='## Goal
Something.')
contains "$(cat "$WORK/gh.log")" "Acceptance criteria" "asked for them when missing"
out=$(run_issue env EXISTING='[]' BODY='## Goal
Something.

## Acceptance criteria
- [ ] it works')
absent "$(cat "$WORK/gh.log")" "**Acceptance criteria.** What has to be true" "stayed quiet when they are there"

echo "== 5b. the comment only tells an author they could not label, when they could not"
# Found by the first live run, which told a maintainer they lacked a permission
# they had. Small, and the kind of small that teaches a reader to stop believing
# the rest of the message.
out=$(run_issue env EXISTING='[]' BODY='x')
contains "$(cat "$WORK/gh.log")" "You could not have set these labels yourself" "said it to a citizen"
out=$(run_issue env PERMISSION=admin EXISTING='[]' BODY='x')
absent "$(cat "$WORK/gh.log")" "You could not have set these labels yourself" "and not to a maintainer"

echo "== 5c. one of the Colony's own runners is labelled, never thanked (#413)"
# The branch `0687f61` added, and until `#192` the only branch in the file with
# no case. `kolonie-platform#408` is what it was written for: the log detector
# files as a GitHub App this organisation runs, and arrived nineteen seconds
# later labelled `from:citizen` and thanked. Nobody thanked anybody.
out=$(run_issue env AUTHOR=kolonie-triage AUTHOR_TYPE=Bot EXISTING='[]' BODY='moderation-runner is erroring.')
log=$(cat "$WORK/gh.log")
contains "$log" "--add-label area:platform" "area: applied, because it is the one label that is always true"
absent "$log" "from:" "no provenance label — the Colony's own runner is not a contributor"
absent "$log" "needs-triage" "not marked needs-triage — the detector already routed it"
absent "$log" "issue comment" "not thanked"

out=$(run_issue env AUTHOR=kolonie-triage AUTHOR_TYPE=Bot EXISTING='["area:platform"]' BODY='x')
log=$(cat "$WORK/gh.log")
absent "$log" "--add-label" "a runner that labelled itself is left entirely alone"
absent "$log" "issue comment" "and still not thanked"
contains "$out" "already labelled" "and said why"

echo "== 5d. 'one of ours' is an and, and each half is load-bearing"
# A case proving only the positive would pass a workflow that had dropped either
# test — and dropping the prefix test would silence the thank-you for every bot
# on the internet, which is the direction that costs a citizen something.
out=$(run_issue env AUTHOR=dependabot AUTHOR_TYPE=Bot EXISTING='[]' BODY='x')
contains "$(cat "$WORK/gh.log")" "from:external" "a Bot that is not one of ours takes the ordinary path"

out=$(run_issue env AUTHOR=kolonie-fan AUTHOR_TYPE=User EXISTING='[]' BODY='x')
contains "$(cat "$WORK/gh.log")" "from:external" "a person whose name starts kolonie- is still a person"

echo "== 6. priority is never assigned, by any path"
# p1/p2 encode what the Colony is trying to achieve, which a workflow cannot
# know. If this assertion ever fails, the workflow has started making a
# maintainer's judgement.
for body in 'urgent!!' 'p1 please' 'this is critical and blocks everything'; do
  out=$(run_issue env EXISTING='[]' BODY="$body")
  absent "$(grep -- '--add-label' "$WORK/gh.log")" "p1" "no p1 for: $body"
done

echo "== 7. a fork pull request inherits area and priority from the issue it closes"
out=$(run_pr env ISSUE_LABELS='area:infra,p1' TITLE='fix: a thing' BRANCH='fix/a-thing-40' BODY='Fixes #40')
log=$(cat "$WORK/gh.log")
contains "$log" "--add-label from:external,area:infra,p1" "inherited area:infra and p1, and marked from:external"
absent "$log" "area:platform" "did not fall back to the calling repository's area"
absent "$log" "pr comment" "said nothing, because there was nothing to say"

echo "== 7b. a pull request's provenance answers the same three ways (#335)"
# No sweep covers pull requests, so an unanswerable membership stays unlabelled
# here rather than being picked up within the hour. That is the honest outcome:
# nothing downstream reads a pull request's `from:` label, and a guess would
# feed the very count `#335` exists to stop inflating.
for m in member unknown; do
  out=$(run_pr env MEMBERSHIP="$m" ISSUE_LABELS='area:infra' TITLE='fix: a thing' BRANCH='fix/a-thing-40' BODY='Fixes #40')
  log=$(cat "$WORK/gh.log")
  contains "$log" "--add-label area:infra" "$m: inherited the area"
  absent "$log" "from:" "$m: and guessed no provenance"
done

echo "== 8. a pull request that closes no issue is told so, and falls back to the repo's area"
out=$(run_pr env TITLE='fix: a thing' BRANCH='fix/a-thing-40' BODY='No issue for this.')
log=$(cat "$WORK/gh.log")
contains "$log" "--add-label from:external,area:platform" "fell back to the caller's area"
contains "$log" "pr comment" "commented"
contains "$log" "No issue is referenced" "and the comment says which convention was missed"

echo "== 9. conventions are commented on, never failed"
# The rejection case that matters most here is that there is no rejection: a red
# X on a first contribution over a title format is disproportionate, and the
# thing being protected is that a contributor can tell a convention from a gate.
out=$(run_pr env ISSUE_LABELS='area:docs' TITLE='made some changes' BRANCH='patch-1' BODY='Fixes #12'); rc=$?
check "a non-conventional title does not fail the step" "$rc" "0"
contains "$(cat "$WORK/gh.log")" "pr comment" "it comments instead"
contains "$(cat "$WORK/gh.log")" "--add-label from:external,area:docs" "and labels it anyway"

echo "== 10. a maintainer's own branch name is not policed"
# `feature/<slug>-<n>` is guidance for contributors working in a fork, not a rule
# about every branch that has ever existed in this organisation.
out=$(run_pr env PERMISSION=write ISSUE_LABELS='area:docs' TITLE='fix: a thing' BRANCH='quick-fix' BODY='Fixes #12')
absent "$(cat "$WORK/gh.log")" "pr comment" "nothing to say about it"

echo "== 11. Conventional Commits: the shapes the guide documents are accepted"
for title in 'feat: add x' 'fix(ledger): resolve y' 'docs: update z' 'test: add cases' 'feat!: breaking'; do
  out=$(run_pr env PERMISSION=write ISSUE_LABELS='area:docs' TITLE="$title" BRANCH='fix/x-1' BODY='Fixes #12')
  absent "$(cat "$WORK/gh.log")" "pr comment" "accepted: $title"
done

echo "== 12. every variable the workflow hands the script is exercised by a case"
# The half of `#192` that the defaults do not cover. Defaulting a new variable to
# empty stops it killing the run, and on its own it would let the branch that
# variable was added for go untested while the file reported green — which is the
# failure `kolonie-docs#190` spent a whole check refusing.
#
# So this fails on the *variable*, by name, at the moment somebody adds one. The
# message is what the last two days were missing: `AUTHOR_TYPE is declared and no
# case sets it` rather than seven assertions about labelling that never ran.
sort -u "$WORK/exercised" > "$WORK/exercised.sorted"
for env_file in "$WORK/issue.env" "$WORK/pull_request.env"; do
  step=$(basename "$env_file" .env)
  while IFS= read -r line; do
    key="${line%%=*}"
    [ -z "$key" ] && continue
    [ "$key" = "$UNEXERCISED_BY_DESIGN" ] && continue
    if grep -qxF -- "$key" "$WORK/exercised.sorted"; then
      echo "  ok   $step: $key"
      pass=$((pass+1))
    else
      echo "  FAIL $step: $key is declared by the workflow and no case sets it — add one before it defaults silently"
      fail=$((fail+1))
    fi
  done < "$env_file"
done

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]

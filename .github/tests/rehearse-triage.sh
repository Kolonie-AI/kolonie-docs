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

python3 - "$WORKFLOW" "$WORK" <<'PY'
import sys, yaml
workflow, out = sys.argv[1], sys.argv[2]
doc = yaml.safe_load(open(workflow))
for name, job in doc["jobs"].items():
    for step in job["steps"]:
        if "run" in step:
            open(f"{out}/{name}.sh", "w").write(step["run"])
PY

# --- the stub -------------------------------------------------------------
# Records every call and answers the four questions the workflow asks: what
# permission does this author have, what labels does the linked issue carry, and
# then the two write calls it makes.
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

run_issue() {
  : > "$WORK/gh.log"
  GH_LOG="$WORK/gh.log" PATH="$BIN:$PATH" \
    REPO=Kolonie-AI/kolonie-platform NUMBER=123 AUTHOR=someagent AREA=platform \
    "$@" bash "$WORK/issue.sh" 2>&1
}

run_pr() {
  : > "$WORK/gh.log"
  GH_LOG="$WORK/gh.log" PATH="$BIN:$PATH" \
    REPO=Kolonie-AI/kolonie-platform NUMBER=456 AUTHOR=someagent AREA=platform \
    "$@" bash "$WORK/pull_request.sh" 2>&1
}

echo "== 1. an issue from someone without push access gets all three labels"
# The case the workflow exists for. It is unconditional for such an author: the
# API drops labels silently for anyone without push access, so "forgot" and
# "could not" are the same case and there is no way to be in the first one.
out=$(run_issue env EXISTING='[]' BODY='Something is broken.')
log=$(cat "$WORK/gh.log")
contains "$log" "--add-label area:platform,needs-triage,from:citizen" "labelled area, needs-triage and from:citizen"
contains "$log" "issue comment 123" "commented"

echo "== 2. …even when they somehow arrive with labels already on"
# Not a hypothetical: an issue can be labelled by an automation before this runs.
# The author still could not have done it, so from:citizen still applies.
out=$(run_issue env EXISTING='["bug"]' BODY='Something is broken.')
contains "$(cat "$WORK/gh.log")" "from:citizen" "still marked as a citizen contribution"

echo "== 3. a maintainer's labelled issue is left completely alone"
out=$(run_issue env PERMISSION=write EXISTING='["p1","area:platform"]' BODY='x')
log=$(cat "$WORK/gh.log")
absent "$log" "--add-label" "no labels applied"
absent "$log" "issue comment" "no comment posted"
contains "$out" "nothing to do" "and said why"

echo "== 4. a maintainer's *unlabelled* issue is labelled but not called a citizen's"
out=$(run_issue env PERMISSION=admin EXISTING='[]' BODY='x')
log=$(cat "$WORK/gh.log")
contains "$log" "--add-label area:platform,needs-triage" "labelled"
absent "$log" "from:citizen" "not marked from:citizen"

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
contains "$log" "--add-label from:citizen,area:infra,p1" "inherited area:infra and p1, and marked from:citizen"
absent "$log" "area:platform" "did not fall back to the calling repository's area"
absent "$log" "pr comment" "said nothing, because there was nothing to say"

echo "== 8. a pull request that closes no issue is told so, and falls back to the repo's area"
out=$(run_pr env TITLE='fix: a thing' BRANCH='fix/a-thing-40' BODY='No issue for this.')
log=$(cat "$WORK/gh.log")
contains "$log" "--add-label from:citizen,area:platform" "fell back to the caller's area"
contains "$log" "pr comment" "commented"
contains "$log" "No issue is referenced" "and the comment says which convention was missed"

echo "== 9. conventions are commented on, never failed"
# The rejection case that matters most here is that there is no rejection: a red
# X on a first contribution over a title format is disproportionate, and the
# thing being protected is that a contributor can tell a convention from a gate.
out=$(run_pr env ISSUE_LABELS='area:docs' TITLE='made some changes' BRANCH='patch-1' BODY='Fixes #12'); rc=$?
check "a non-conventional title does not fail the step" "$rc" "0"
contains "$(cat "$WORK/gh.log")" "pr comment" "it comments instead"
contains "$(cat "$WORK/gh.log")" "--add-label from:citizen,area:docs" "and labels it anyway"

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

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]

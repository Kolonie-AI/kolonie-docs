#!/bin/bash
# Does the assembler route what it says it routes, and say what it left out?
# (`kolonie-docs#362`)
#
# Usage: bash .github/tests/brief.test.sh
#
# Two halves, and they answer different questions.
#
# **Against a fixture repository** — the routing rules themselves. A fixture is
# what lets a test assert that a module did *not* arrive, which is most of what
# routing is, and it cannot be done against this repository's own documents
# without rewriting them.
#
# **Against this repository** — the two properties that are claims about
# `kolonie-docs` rather than about the script: that the start manifest fits its
# budget, and that every module carries a summary. Those are measurements, and
# a measurement asserted against a fixture measures the fixture.
#
# The properties worth the fixture are the negative ones. A brief that loads
# everything passes every positive test in this file and is exactly the failure
# the whole issue is about.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; FAILURES+=("$1"); }

contains() { # <what> <needle> <haystack>
  if grep -qF -- "$2" <<<"$3"; then pass "$1"; else fail "$1 (expected to find: $2)"; fi
}
absent() { # <what> <needle> <haystack>
  if grep -qF -- "$2" <<<"$3"; then fail "$1 (should not have found: $2)"; else pass "$1"; fi
}

# --- the fixture repository ------------------------------------------------
#
# A real git repository, because discovery is `git ls-files`: a fixture built
# out of loose files would find nothing and every routing test would pass by
# finding nothing to route.
REPO=$WORK/repo
mkdir -p "$REPO/.github/scripts" "$REPO/governance" "$REPO/agents/history"
cp "$ROOT/.github/scripts/brief.sh" "$REPO/.github/scripts/brief.sh"
BRIEF="$REPO/.github/scripts/brief.sh"

cat > "$REPO/governance/red-lines.md" <<'MD'
# Red Lines
## Forbidden
- Tasks that steal data
- Credential exfiltration
MD

cat > "$REPO/AGENTS.md" <<'MD'
---
module: agents
summary: The binding contract.
applies-to:
  always: true
---
Every agent reads this. UNIQUE-AGENTS-STRING
MD

cat > "$REPO/agents/board.md" <<'MD'
---
module: board
summary: Board plumbing, item ids.
applies-to:
  roles: [orchestrator]
  labels: [area:infra]
  paths: [".github/workflows/**"]
---
UNIQUE-BOARD-STRING
MD

cat > "$REPO/agents/docs-repo.md" <<'MD'
---
module: docs-repo
summary: The rules for this repository's own documents.
applies-to:
  repos: [kolonie-docs]
  paths: ["*.md"]
---
UNIQUE-DOCS-STRING
MD

cat > "$REPO/agents/history/2026-08-12-shared-checkout.md" <<'MD'
---
module: history-shared-checkout
summary: Why session.sh refuses.
applies-to:
---
UNIQUE-HISTORY-STRING
MD

cat > "$REPO/not-a-module.md" <<'MD'
# Just a document
UNIQUE-NOT-A-MODULE-STRING
MD

(
  cd "$REPO"
  git init -q .
  git add -A
  git -c user.email=t@t.invalid -c user.name=t commit -qm fixture
)

# `gh` is not reachable in a test and must not be: routing is decided by labels
# and a repository name, and the stub is what lets a case state the labels it is
# testing. A real call would make these cases depend on a live issue.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/bash
cat "${GH_ISSUE:-/dev/null}" 2>/dev/null || echo '{}'
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

issue_labels() { # <csv>
  local labels='' l
  for l in ${1//,/ }; do labels="$labels{\"name\":\"$l\"},"; done
  printf '{"title":"A fixture issue","labels":[%s]}' "${labels%,}" > "$WORK/issue.json"
  export GH_ISSUE="$WORK/issue.json"
}

echo
echo "discovery"

out=$(bash "$BRIEF" --modules)
contains "a file with front matter is a module" "agents" "$out"
contains "and so is one in a subdirectory" "board" "$out"
absent   "a file without front matter is not" "not-a-module" "$out"

echo
echo "routing — what arrives, and what does not"

issue_labels "area:platform"
out=$(bash "$BRIEF" --issue Kolonie-AI/kolonie-platform 1)
contains "an always module is in every brief" "UNIQUE-AGENTS-STRING" "$out"
absent   "a role module is not, for a worker" "UNIQUE-BOARD-STRING" "$out"
absent   "a repos module is not, in another repository" "UNIQUE-DOCS-STRING" "$out"
absent   "an empty applies-to is never briefed" "UNIQUE-HISTORY-STRING" "$out"

issue_labels "area:infra"
out=$(bash "$BRIEF" --issue Kolonie-AI/kolonie-platform 1)
contains "a label match loads the module" "UNIQUE-BOARD-STRING" "$out"
contains "and the brief says which rule matched" "label area:infra" "$out"

issue_labels "area:platform"
out=$(bash "$BRIEF" --issue Kolonie-AI/kolonie-platform 1 --role orchestrator)
contains "a role match loads the module" "UNIQUE-BOARD-STRING" "$out"

out=$(bash "$BRIEF" --issue Kolonie-AI/kolonie-docs 1)
contains "a repository match loads the module" "UNIQUE-DOCS-STRING" "$out"

out=$(bash "$BRIEF" --issue Kolonie-AI/kolonie-platform 1 --path .github/workflows/ci.yml)
contains "** crosses directories" "UNIQUE-BOARD-STRING" "$out"

out=$(bash "$BRIEF" --issue Kolonie-AI/kolonie-platform 1 --path AGENTS.md)
contains "* matches inside one segment" "UNIQUE-DOCS-STRING" "$out"
out=$(bash "$BRIEF" --issue Kolonie-AI/kolonie-platform 1 --path onboarding/arrival.md)
absent   "* does not cross a directory" "UNIQUE-DOCS-STRING" "$out"

echo
echo "nothing is lost"

issue_labels "area:platform"
out=$(bash "$BRIEF" --issue Kolonie-AI/kolonie-platform 1)
contains "an unloaded module is named" "board" "$out"
contains "with its own summary" "Board plumbing, item ids." "$out"
contains "and the command that loads it" "--module <name>" "$out"

echo
echo "the budget says what it did"

issue_labels "area:infra"
out=$(BRIEF_MAX_TOKENS=1 bash "$BRIEF" --issue Kolonie-AI/kolonie-platform 1)
absent   "over budget, a matched module's content is dropped" "UNIQUE-BOARD-STRING" "$out"
contains "and the drop is stated" "so these were dropped" "$out"
contains "naming the module" "board" "$out"
absent   "an always module is not inlined either" "UNIQUE-AGENTS-STRING" "$out"
contains "but it is named as binding rather than dropped" "Binding, and too large to inline" "$out"
contains "and told to be read" "It is not optional and it was not dropped" "$out"

echo
echo "asking by name"

out=$(bash "$BRIEF" --module board)
contains "a named module is loaded whatever the routing says" "UNIQUE-BOARD-STRING" "$out"
out=$(bash "$BRIEF" --module history-shared-checkout)
contains "including one that is briefed to nobody" "UNIQUE-HISTORY-STRING" "$out"
out=$(bash "$BRIEF" --module agents,board)
contains "several at once, first" "UNIQUE-AGENTS-STRING" "$out"
contains "several at once, second" "UNIQUE-BOARD-STRING" "$out"

out=$(bash "$BRIEF" --module nonesuch 2>&1) && fail "an unknown module exited 0" || pass "an unknown module fails"
contains "and lists what there is" "board" "$out"

echo
echo "front matter it cannot parse stops the run"

cat > "$REPO/agents/broken.md" <<'MD'
---
module: broken
applies-to:
  labels:
    - area:infra
---
UNIQUE-BROKEN-STRING
MD
(cd "$REPO" && git add -A && git -c user.email=t@t.invalid -c user.name=t commit -qm broken)
out=$(bash "$BRIEF" --modules 2>&1) && fail "a shape the parser does not understand passed" || pass "a shape the parser does not understand is refused"
contains "and the file is named" "agents/broken.md" "$out"
contains "and so is the line" "- area:infra" "$out"
(cd "$REPO" && git rm -q agents/broken.md && git -c user.email=t@t.invalid -c user.name=t commit -qm fixed)

echo
echo "a module in a directory its parent is named after is listed under it"

mkdir -p "$REPO/agents"
cat > "$REPO/agents/extra.md" <<'MD'
---
module: extra
summary: A part of the contract.
applies-to:
  roles: [orchestrator]
---
UNIQUE-EXTRA-STRING
MD
(cd "$REPO" && git add -A && git -c user.email=t@t.invalid -c user.name=t commit -qm extra)
out=$(bash "$BRIEF" --manifest)
contains "the parent carries the summary" "The binding contract." "$out"
contains "and the child is named under it" "extra" "$out"
absent   "without a second summary line" "A part of the contract." "$out"

echo
echo "two modules cannot share a name"

cat > "$REPO/agents/twin.md" <<'MD'
---
module: board
summary: A second module claiming a name.
applies-to:
  roles: [orchestrator]
---
UNIQUE-TWIN-STRING
MD
(cd "$REPO" && git add -A && git -c user.email=t@t.invalid -c user.name=t commit -qm twin)
out=$(bash "$BRIEF" --modules 2>&1) && fail "two modules sharing a name passed" || pass "two modules sharing a name is refused"
contains "and both files are named" "agents/twin.md" "$out"
(cd "$REPO" && git rm -q agents/twin.md && git -c user.email=t@t.invalid -c user.name=t commit -qm untwin)

echo
echo "the manifest is a directory and not a document"

out=$(bash "$BRIEF" --manifest)
contains "the red lines are in it, in full" "Credential exfiltration" "$out"
contains "every module is named" "board" "$out"
absent   "and no module's content is in it" "UNIQUE-BOARD-STRING" "$out"
absent   "not even the binding one" "UNIQUE-AGENTS-STRING" "$out"
contains "the loop is there as commands" "session.sh take" "$out"
contains "and the way to everything else" "--index" "$out"

echo
echo "against this repository, where the measurements are claims about it"

manifest=$(bash "$ROOT/.github/scripts/brief.sh" --manifest)
bytes=$(printf '%s' "$manifest" | wc -c)
tokens=$((bytes / 4))
if [ "$tokens" -lt 2000 ]; then
  pass "the start manifest is ~$tokens tokens, under the 2.000 this was built for"
else
  fail "the start manifest is ~$tokens tokens, over the 2.000 kolonie-docs#362 requires"
fi

missing=$(bash "$ROOT/.github/scripts/brief.sh" --modules | awk -F'\t' '$3=="no summary" {print $1}')
if [ -z "$missing" ]; then
  pass "every module in this repository carries a summary"
else
  fail "modules with no summary, which is what the directory prints: $missing"
fi

redlines=$(grep -c '' "$ROOT/governance/red-lines.md")
inmanifest=$(grep -cF -f <(grep -v '^$' "$ROOT/governance/red-lines.md") <<<"$manifest" || true)
if [ "$inmanifest" -gt 0 ] && grep -qF "$(sed -n '/^## Forbidden/,/^$/p' "$ROOT/governance/red-lines.md" | tail -2 | head -1)" <<<"$manifest"; then
  pass "the red lines reach the manifest verbatim ($redlines lines in the file)"
else
  fail "the red lines are not verbatim in the manifest"
fi

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "brief.sh: all cases pass"
  exit 0
fi
echo "brief.sh: ${#FAILURES[@]} case(s) failed"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

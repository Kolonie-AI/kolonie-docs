#!/bin/bash
# Does the red-lines fetcher read the checkout, retry the network, and say which
# of the two failures happened?
#
# Usage: bash .github/tests/find-red-line-copies.test.sh
#
# `kolonie-docs#301`. Twice in one session CI went red on *the copies of the red
# lines still agree* because a `gh api` read was slow — once for a file sitting on
# disk in the checkout the job had already made. The check's one message is the
# alarm in this organisation that must never cry wolf, so the fix is three
# things, and all three are here: this repository's copies come off disk, the
# remaining reads are retried, and a read that never happened says so in words
# rather than in the voice of a divergence.
#
# Against a **stubbed `gh`**, which is the only way to make a read fail on
# purpose. The stub logs every invocation and answers from files the case sets
# up; `fail_*` is a countdown, so a case can say *fail twice and then work* and
# get the transient failure the real one was.
#
# What the stub cannot reproduce is the latency itself — it fails instantly. The
# assertions are therefore about the *shape*: how many attempts were made, what
# was read from where, and what the message says. `RETRY_FIRST_DELAY_SECONDS=0`
# below is what keeps the retry cases from sleeping through the backoff they are
# checking.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT/.github/scripts/find-red-line-copies.sh"
FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The retry is what is under test; the waiting is not.
export RETRY_FIRST_DELAY_SECONDS=0

mkdir -p "$WORK/bin"
# `body_<endpoint>` is what the call answers, `fail_<endpoint>` is how many more
# times it fails first, and `absent_<endpoint>` is the permanent 409 an empty
# repository gives — which is an answer rather than a failure and must not be
# retried or reported.
cat > "$WORK/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >> "$GH_LOG"
key=$(printf '%s' "${2:-}" | tr -c 'A-Za-z0-9' '_')

remaining=$(cat "$GH_FIXTURES/fail_$key" 2>/dev/null || echo 0)
if [ "$remaining" -gt 0 ]; then
  echo $((remaining - 1)) > "$GH_FIXTURES/fail_$key"
  echo "gh: Bad gateway (HTTP 502)" >&2
  exit 1
fi

if [ -f "$GH_FIXTURES/absent_$key" ]; then
  echo "gh: Git Repository is empty. (HTTP 409)" >&2
  exit 1
fi

cat "$GH_FIXTURES/body_$key" 2>/dev/null
exit 0
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"

expect() {
  local name=$1 ok=$2 detail=${3:-}
  if [ "$ok" = yes ]; then printf '  ok   %s\n' "$name"
  else printf '  FAIL %s%s\n' "$name" "${detail:+: $detail}"; FAILURES+=("$name"); fi
}

key_of() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'; }

answers() { printf '%s\n' "$2" > "$GH_FIXTURES/body_$(key_of "$1")"; }
# A `contents` read is answered in base64, because that is what the API does and
# the script decodes it.
serves() { printf '%s\n' "$2" | base64 -w0 > "$GH_FIXTURES/body_$(key_of "$1")"; }
fails() { printf '%s\n' "$2" > "$GH_FIXTURES/fail_$(key_of "$1")"; }
is_empty_repo() { : > "$GH_FIXTURES/absent_$(key_of "$1")"; }

ORG_REPOS='orgs/Kolonie-AI/repos'
PLATFORM_TREE='repos/Kolonie-AI/kolonie-platform/git/trees/HEAD?recursive=1'
OPENCLAW_TREE='repos/Kolonie-AI/kolonie-openclaw/git/trees/HEAD?recursive=1'
CONCEPT_TREE='repos/Kolonie-AI/kolonie-concept-lab/git/trees/HEAD?recursive=1'
ORCHESTRATOR_TREE='repos/Kolonie-AI/kolonie-opencode-orchestrator/git/trees/HEAD?recursive=1'
DOCS_TREE='repos/Kolonie-AI/kolonie-docs/git/trees/HEAD?recursive=1'
ABOUT='repos/Kolonie-AI/kolonie-platform/contents/apps/api/src/about.ts'
OPENCLAW_SKILL='repos/Kolonie-AI/kolonie-openclaw/contents/skills/kolonie/SKILL.md'
CONCEPT_SKILL='repos/Kolonie-AI/kolonie-concept-lab/contents/SKILL.md'
ORCHESTRATOR_SKILL='repos/Kolonie-AI/kolonie-opencode-orchestrator/contents/kolonie-opencode-orchestrator/SKILL.md'

# A whole organisation as the API would answer it: two repositories holding a
# skill, and this one holding none.
setup() {
  export GH_FIXTURES="$WORK/fixtures" GH_LOG="$WORK/log"
  rm -rf "$GH_FIXTURES" "$WORK/copies"; mkdir -p "$GH_FIXTURES"; : > "$GH_LOG"

  answers "$ORG_REPOS" 'Kolonie-AI/kolonie-concept-lab
Kolonie-AI/kolonie-docs
Kolonie-AI/kolonie-opencode-orchestrator
Kolonie-AI/kolonie-openclaw
Kolonie-AI/kolonie-platform'
  answers "$DOCS_TREE" ''
  answers "$PLATFORM_TREE" ''
  answers "$OPENCLAW_TREE" 'skills/kolonie/SKILL.md'
  answers "$CONCEPT_TREE" 'SKILL.md'
  answers "$ORCHESTRATOR_TREE" 'kolonie-opencode-orchestrator/SKILL.md'
  serves "$ABOUT" 'const RED_LINES = []'
  serves "$OPENCLAW_SKILL" $'---\nname: kolonie\n---\n\n## Red lines'
  serves "$CONCEPT_SKILL" $'---\nname: kolonie-concept-lab\n---\n\n## Evidence Language'
  serves "$ORCHESTRATOR_SKILL" $'---\nname: kolonie-opencode-orchestrator\n---\n\n## Prerequisites'
}

run() { bash "$SCRIPT" "$WORK/copies" > "$WORK/out" 2>&1; }

attempts_at() { grep -cF -- "$1" "$GH_LOG"; }

echo "this repository's copies come off the checkout"

setup
run; rc=$?
expect "a healthy run succeeds" "$([ $rc -eq 0 ] && echo yes || echo no)" "$(cat "$WORK/out")"
for path in governance/red-lines.md onboarding/arrival.md onboarding/skill/body.md; do
  expect "$path is not read over the API" \
    "$(grep -qF "contents/$path" "$GH_LOG" && echo no || echo yes)" "$(cat "$GH_LOG")"
done

# The correctness half of `#301`, not the reliability half: the API answers with
# the default branch, so a pull request editing the rules was checked against
# `main` and the commit that changed them went unexamined. Byte equality with the
# working tree is the whole assertion.
expect "the source is the file in this checkout, byte for byte" \
  "$(cmp -s "$ROOT/governance/red-lines.md" "$WORK/copies/source.md" && echo yes || echo no)"
expect "and so is arrival.md" \
  "$(cmp -s "$ROOT/onboarding/arrival.md" "$WORK/copies/arrival.md" && echo yes || echo no)"
expect "and so is body.md" \
  "$(cmp -s "$ROOT/onboarding/skill/body.md" "$WORK/copies/body.md" && echo yes || echo no)"

expect "what lives elsewhere is still fetched" \
  "$([ -s "$WORK/copies/about.ts" ] && echo yes || echo no)"
expect "a discovered skill is fetched and listed" \
  "$(grep -q 'kolonie-openclaw/skills/kolonie/SKILL.md' "$WORK/copies/manifest.json" \
    && echo yes || echo no)" "$(cat "$WORK/copies/manifest.json" 2>/dev/null)"
expect "a live non-entry-point skill is not a constitutional copy" \
  "$(grep -q 'kolonie-concept-lab/SKILL.md' "$WORK/copies/manifest.json" \
    && echo no || echo yes)" "$(cat "$WORK/copies/manifest.json" 2>/dev/null)"
expect "and neither is a maintainer skill" \
  "$(grep -q 'kolonie-opencode-orchestrator/.*/SKILL.md' "$WORK/copies/manifest.json" \
    && echo no || echo yes)" "$(cat "$WORK/copies/manifest.json" 2>/dev/null)"
expect "non-entry-point skills are read once for identity, not fetched again as copies" \
  "$([ "$(attempts_at "$CONCEPT_SKILL")" -eq 1 ] \
    && [ "$(attempts_at "$ORCHESTRATOR_SKILL")" -eq 1 ] && echo yes || echo no)" \
  "$(cat "$GH_LOG")"

# The second subject (`#399`). The assertion that matters is not that a second
# manifest exists — it is that it names **the same files** as the first, because
# the whole argument for putting it here rather than in its own workflow is that
# the discovery run is already paid for.
expect "the invitation source comes off the checkout too" \
  "$(cmp -s "$ROOT/governance/the-atlas.md" "$WORK/copies/invitation-source.md" \
    && echo yes || echo no)"
expect "a second manifest is written for it" \
  "$([ -s "$WORK/copies/manifest-invitation.json" ] && echo yes || echo no)"
expect "and it names its own section rather than relying on a default" \
  "$(grep -q '"section":"The invitation"' "$WORK/copies/manifest-invitation.json" \
    && echo yes || echo no)" "$(cat "$WORK/copies/manifest-invitation.json" 2>/dev/null)"
expect "the discovered skill is compared for the invitation as well" \
  "$(grep -q 'kolonie-openclaw/skills/kolonie/SKILL.md' "$WORK/copies/manifest-invitation.json" \
    && echo yes || echo no)" "$(cat "$WORK/copies/manifest-invitation.json" 2>/dev/null)"
# No file is fetched twice for it: every path in the second manifest is one the
# first already lists. A `file` appearing in only the second would mean a fetch
# the header says this arrangement does not pay for.
expect "it fetches nothing the red-line comparison did not already fetch" \
  "$(python3 - "$WORK/copies" <<'PY'
import json, sys, pathlib
root = pathlib.Path(sys.argv[1])
first = json.loads((root / "manifest.json").read_text())
second = json.loads((root / "manifest-invitation.json").read_text())
have = {first["source"]["file"], *(c["file"] for c in first["copies"])}
extra = {c["file"] for c in second["copies"]} - have
print("yes" if not extra else f"no: {sorted(extra)}")
PY
)"
# Both manifests are read by the same script, so a run that fetched nothing must
# leave neither behind — the *"a read that never happened is not a divergence"*
# case below asserts this for the first one.

echo
echo "a slow read is retried rather than believed"

setup; fails "$ABOUT" 2
run; rc=$?
expect "two failed reads do not fail the run" "$([ $rc -eq 0 ] && echo yes || echo no)" "$(cat "$WORK/out")"
expect "it tried again" "$([ "$(attempts_at "$ABOUT")" -eq 3 ] && echo yes || echo no)" \
  "$(attempts_at "$ABOUT") attempts"

# The quieter half. A dropped repository does not turn the run red — it makes the
# check pass on fewer copies than it should, which is the failure `MINIMUM_COPIES`
# exists for and the one a single dropped repository is too small to trip.
setup; fails "$OPENCLAW_TREE" 2
run
expect "a slow file listing does not silently drop a repository" \
  "$(grep -q 'kolonie-openclaw/skills/kolonie/SKILL.md' "$WORK/copies/manifest.json" \
    && echo yes || echo no)" "$(cat "$WORK/out")"

echo
echo "a read that never happened is not a divergence"

setup; fails "$ABOUT" 99
run; rc=$?
expect "a read that keeps failing fails the run" "$([ $rc -ne 0 ] && echo yes || echo no)"
expect "it gives up rather than retrying forever" \
  "$([ "$(attempts_at "$ABOUT")" -eq 3 ] && echo yes || echo no)" "$(attempts_at "$ABOUT") attempts"
expect "and says the copies were not compared" \
  "$(grep -q 'not a divergence' "$WORK/out" && echo yes || echo no)" "$(cat "$WORK/out")"
expect "and nothing is left for the comparison to read" \
  "$([ ! -f "$WORK/copies/manifest.json" ] && echo yes || echo no)"
expect "for either comparison" \
  "$([ ! -f "$WORK/copies/manifest-invitation.json" ] && echo yes || echo no)"

setup; fails "$ORG_REPOS" 99
run; rc=$?
expect "an unreadable organisation listing fails rather than discovering nothing" \
  "$([ $rc -ne 0 ] && echo yes || echo no)" "$(cat "$WORK/out")"
expect "in the same words" "$(grep -q 'not a divergence' "$WORK/out" && echo yes || echo no)"

setup; fails "$OPENCLAW_TREE" 99
run; rc=$?
expect "an unreadable file listing fails rather than under-discovering" \
  "$([ $rc -ne 0 ] && echo yes || echo no)" "$(cat "$WORK/out")"

echo
echo "a repository with no tree is an answer, not a failure"

# An empty repository answers 409 forever. Retrying it would spend the backoff
# three times over to arrive at the same nothing, and failing on it would make
# one unrelated repository in the organisation able to stop this check.
setup; is_empty_repo "$DOCS_TREE"
run; rc=$?
expect "an empty repository does not fail the run" "$([ $rc -eq 0 ] && echo yes || echo no)" \
  "$(cat "$WORK/out")"
expect "and is not retried" "$([ "$(attempts_at "$DOCS_TREE")" -eq 1 ] && echo yes || echo no)" \
  "$(attempts_at "$DOCS_TREE") attempts"
expect "and the repositories that do hold a skill are still found" \
  "$(grep -q 'kolonie-openclaw' "$WORK/copies/manifest.json" && echo yes || echo no)"

echo
if [ ${#FAILURES[@]} -gt 0 ]; then
  printf '%d failed: %s\n' "${#FAILURES[@]}" "$(IFS=,; echo "${FAILURES[*]}")"
  exit 1
fi
echo "all cases pass"

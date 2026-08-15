#!/bin/bash
# Does a new test file run without anybody editing a list, and does one that
# opts out say why in itself? `kolonie-docs#378`.
#
# Usage: bash .github/tests/run-tests.test.sh
#
# The issue this covers is not that a test was wrong, it is that three tests
# were in no list and ran nowhere. The two properties that keep that from
# recurring are the two this asserts hardest:
#
#   - a file dropped into `.github/tests` is picked up with no edit anywhere,
#   - a file the discovery cannot run stops the run instead of being passed over.
#
# The second is the rejection case the issue asks for, and it has two halves: a
# file that opts out on purpose is skipped *with its reason printed*, and a file
# with an extension nothing here can run is a hard failure.
#
# Everything is exercised against a temp directory, which is why `run-tests.sh`
# takes one. A test that wrote fixtures into the real `.github/tests` would be a
# test that leaves a failing test behind when it is interrupted.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
RUNNER="$ROOT/.github/scripts/run-tests.sh"

FAILURES=()

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The opt-out marker is assembled rather than written, so that this file does
# not itself carry a line the discovery would read as an opt-out. A test that
# excused itself while asserting that opt-outs work would be the joke version of
# the bug it is here to catch.
MARKER="# not"'-run:'

check() {
  local what=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then
    echo "  ok   $what"
  else
    echo "  FAIL $what"
    echo "         expected: $expected"
    echo "         actual:   $actual"
    FAILURES+=("$what")
  fi
}

contains() {
  local what=$1 needle=$2 haystack=$3
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "  ok   $what"
  else
    echo "  FAIL $what"
    echo "         expected to find: $needle"
    FAILURES+=("$what")
  fi
}

absent() {
  local what=$1 needle=$2 haystack=$3
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "  FAIL $what"
    echo "         did not expect to find: $needle"
    FAILURES+=("$what")
  else
    echo "  ok   $what"
  fi
}

echo "run-tests.sh"

# ── A file nobody added to a list runs anyway ────────────────────────────────

CASE=$WORK/pickup
mkdir -p "$CASE"
cat >"$CASE/alpha.test.sh" <<'EOF'
#!/bin/bash
echo "alpha ran"
EOF
cat >"$CASE/beta.test.py" <<'EOF'
print("beta ran")
EOF
# Not tests, and outside the pattern: the harness and the fixture that already
# live in `.github/tests` and have always been meant not to run.
cat >"$CASE/rehearse-triage.sh" <<'EOF'
#!/bin/bash
echo "harness ran"
EOF
echo '{"cases": []}' >"$CASE/board-triage-cases.json"

out=$(bash "$RUNNER" "$CASE" 2>&1); code=$?
check "a directory of two new tests exits 0" 0 "$code"
contains "the new .sh file ran" "alpha ran" "$out"
contains "the new .py file ran" "beta ran" "$out"
contains "the count is reported" "2 test files passed" "$out"
absent "a harness that is not *.test.* is left alone" "harness ran" "$out"

# ── A file that opts out says why, in itself ─────────────────────────────────

CASE=$WORK/optout
mkdir -p "$CASE"
cat >"$CASE/alpha.test.sh" <<'EOF'
#!/bin/bash
echo "alpha ran"
EOF
{
  echo '#!/bin/bash'
  echo "$MARKER needs a live GitHub token, which a fork cannot supply"
  echo 'echo "gamma ran"'
  echo 'exit 1'
} >"$CASE/gamma.test.sh"

out=$(bash "$RUNNER" "$CASE" 2>&1); code=$?
check "an opted-out file does not fail the run" 0 "$code"
absent "an opted-out file does not run" "gamma ran" "$out"
contains "its reason is printed" "needs a live GitHub token" "$out"
contains "and it is named beside the reason" "gamma.test.sh" "$out"
contains "the count excludes it" "1 test files passed" "$out"

# The marker is a marker and not a substring: a file merely discussing the idea
# still runs. `opencode-worker.sh` reads its own headings the same way and the
# same mistake was available there.
CASE=$WORK/near-miss
mkdir -p "$CASE"
{
  echo '#!/bin/bash'
  echo "# This test explains what a $MARKER line would do, without carrying one."
  echo 'echo "delta ran"'
} >"$CASE/delta.test.sh"

out=$(bash "$RUNNER" "$CASE" 2>&1); code=$?
check "a mid-line mention is not an opt-out" 0 "$code"
contains "so the file still runs" "delta ran" "$out"

# ── A failing test is reported and does not hide its neighbours ──────────────

CASE=$WORK/failing
mkdir -p "$CASE"
cat >"$CASE/alpha.test.sh" <<'EOF'
#!/bin/bash
echo "alpha ran"
EOF
cat >"$CASE/broken.test.sh" <<'EOF'
#!/bin/bash
echo "broken ran"
exit 1
EOF
cat >"$CASE/zulu.test.sh" <<'EOF'
#!/bin/bash
echo "zulu ran"
EOF

out=$(bash "$RUNNER" "$CASE" 2>&1); code=$?
check "a failing test exits 1" 1 "$code"
contains "the failing file is named" "broken.test.sh" "$out"
contains "the count says how many of how many" "1 of 3 failed" "$out"
contains "a test after the failure still ran" "zulu ran" "$out"

# ── The rejection case: an extension nothing here can run ────────────────────

CASE=$WORK/unknown
mkdir -p "$CASE"
cat >"$CASE/alpha.test.sh" <<'EOF'
#!/bin/bash
echo "alpha ran"
EOF
echo 'puts "ruby ran"' >"$CASE/epsilon.test.rb"

out=$(bash "$RUNNER" "$CASE" 2>&1); code=$?
check "an unrunnable extension stops the run" 2 "$code"
contains "and names the file" "epsilon.test.rb" "$out"
contains "and says what to do about it" "not-run" "$out"

# ── Finding nothing is a failure, not an empty pass ──────────────────────────

CASE=$WORK/empty
mkdir -p "$CASE"
out=$(bash "$RUNNER" "$CASE" 2>&1); code=$?
check "an empty directory exits 2" 2 "$code"
contains "and says discovery found nothing" "discovery found nothing" "$out"

out=$(bash "$RUNNER" "$WORK/no-such-directory" 2>&1); code=$?
check "a missing directory exits 2" 2 "$code"

# ── --list says what would run without running it ────────────────────────────

CASE=$WORK/listing
mkdir -p "$CASE"
cat >"$CASE/alpha.test.sh" <<'EOF'
#!/bin/bash
echo "alpha ran"
EOF
{
  echo '#!/bin/bash'
  echo "$MARKER a reason"
} >"$CASE/gamma.test.sh"

out=$(bash "$RUNNER" --list "$CASE" 2>&1); code=$?
check "--list exits 0" 0 "$code"
contains "--list names what runs" "alpha.test.sh" "$out"
absent "--list does not run it" "alpha ran" "$out"
contains "--list names what does not" "not-run: gamma.test.sh" "$out"

# ── The real directory, which is the one that matters ────────────────────────
#
# The cases above prove the mechanism. This proves it is pointed at the right
# place and that nothing in the repository is currently invisible to it — the
# state `#378` found, where three committed test files ran nowhere at all.

out=$(bash "$RUNNER" --list 2>&1); code=$?
check "the real test directory lists cleanly" 0 "$code"
for expected in \
  red-lines-report.test.sh \
  red-on-main.test.sh \
  watch-agent.test.sh \
  check-links.test.py \
  opencode-worker.test.sh
do
  contains "$expected is discovered" "$expected" "$out"
done

discovered=$(printf '%s\n' "$out" | grep -c '\.test\.')
on_disk=$(find "$ROOT/.github/tests" -maxdepth 1 -name '*.test.*' | wc -l)
check "every *.test.* file on disk is accounted for" "$on_disk" "$discovered"

echo
if [ ${#FAILURES[@]} -eq 0 ]; then
  echo "all checks passed"
  exit 0
fi
echo "${#FAILURES[@]} failed:"
printf '  - %s\n' "${FAILURES[@]}"
exit 1

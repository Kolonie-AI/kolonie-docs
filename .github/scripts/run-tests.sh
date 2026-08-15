#!/bin/bash
# Runs every test in `.github/tests`, discovered rather than listed.
#
# Usage: bash .github/scripts/run-tests.sh [directory]
#        bash .github/scripts/run-tests.sh --list [directory]
#
# ## Why discovery rather than a list
#
# `ci.yml` and `check.sh` each held a hand-written list of the same set. They
# drifted apart in both directions and three test files ended up in neither —
# `red-lines-report.test.sh`, `red-on-main.test.sh` and `watch-agent.test.sh`
# were written, committed, and run by nothing. A test nobody runs is worse than
# no test: it reads as coverage in a directory listing and asserts nothing.
#
# Nobody made a mistake to produce that. Each list was edited by whoever touched
# the file in front of them, which is the same failure `AGENTS.md §4` refuses
# status labels for and `docs/decisions.md` D-002 in `kolonie-platform` refused
# for the coin ledger: two records of one fact go stale without anybody editing
# them. One record, or none. (`kolonie-docs#378`.)
#
# ## The two rules that make it safe to derive
#
# **A file that is not meant to run says so in itself.** The marker is a line
# starting `# not-run:` and the rest of that line is the reason, which this
# prints on every run. A reason in the file is a reason the next reader of that
# file sees; an omission from a list somewhere else is not.
#
# **An extension with no interpreter is a failure, not a skip.** The whole point
# of discovery is that a new test is picked up without anybody editing a list,
# so the one thing this must never do is find a file it does not know how to run
# and say nothing. `.test.rb` stops the run until somebody teaches it Ruby.
#
# `rehearse-triage.sh` and `board-triage-cases.json` are not `*.test.*` and are
# outside the pattern already — they are a harness and a fixture, not tests.
set -uo pipefail

LIST_ONLY=0
if [ "${1:-}" = "--list" ]; then
  LIST_ONLY=1
  shift
fi

if [ -n "${1:-}" ]; then
  DIR=$1
else
  DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.github/tests"
fi

if [ ! -d "$DIR" ]; then
  echo "run-tests: no such directory: $DIR" >&2
  exit 2
fi

shopt -s nullglob
FILES=("$DIR"/*.test.*)
shopt -u nullglob

if [ ${#FILES[@]} -eq 0 ]; then
  # Finding nothing is the one result that must never read as success. Every
  # other check in this repository exists because a check that quietly does not
  # run is worse than one that is red.
  echo "run-tests: no *.test.* files in $DIR — discovery found nothing, which is a failure and not an empty pass" >&2
  exit 2
fi

# Sorted, so the run order is the same on every machine and a bisect over a
# flaky suite compares like with like. `printf | sort` rather than the glob's
# own order, which follows the locale's collation.
IFS=$'\n' FILES=($(printf '%s\n' "${FILES[@]}" | sort)) || exit 2
unset IFS

FAILED=()
SKIPPED=()
RAN=0

for file in "${FILES[@]}"; do
  name=${file##*/}

  # The marker is read from the file's own head — a comment block, not an
  # arbitrary line a thousand lines down that happens to match.
  reason=$(head -n 40 "$file" | sed -n 's/^#[[:space:]]*not-run:[[:space:]]*//p' | head -n 1)
  if [ -n "$reason" ]; then
    SKIPPED+=("$name — $reason")
    continue
  fi

  case "$name" in
    *.test.py) runner=(python3) ;;
    *.test.sh) runner=(bash) ;;
    *)
      echo "run-tests: $name has no interpreter here, so it would be found and not run — which is the failure this script exists to prevent." >&2
      echo "           Teach run-tests.sh the extension, or give the file a '# not-run: <reason>' line." >&2
      exit 2
      ;;
  esac

  if [ "$LIST_ONLY" = 1 ]; then
    echo "$name"
    RAN=$((RAN + 1))
    continue
  fi

  echo
  echo "── $name"
  if "${runner[@]}" "$file"; then
    echo "   ok"
  else
    echo "   FAILED"
    FAILED+=("$name")
  fi
  RAN=$((RAN + 1))
done

if [ "$LIST_ONLY" = 1 ]; then
  for skip in ${SKIPPED+"${SKIPPED[@]}"}; do
    echo "not-run: $skip"
  done
  exit 0
fi

echo
for skip in ${SKIPPED+"${SKIPPED[@]}"}; do
  echo "not run: $skip"
done

if [ ${#FAILED[@]} -eq 0 ]; then
  echo "$RAN test files passed"
  exit 0
fi

echo "${#FAILED[@]} of $RAN failed:"
printf '  - %s\n' "${FAILED[@]}"
exit 1

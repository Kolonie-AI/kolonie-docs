#!/bin/bash
# Find every copy of the red lines in the organisation and fetch it.
#
# Usage: ./.github/scripts/find-red-line-copies.sh <output-directory>
#
# **Discovery, not a list**, and that is the whole of why this file exists rather
# than four `actions/checkout` steps. The first version of this check named
# `kolonie-docs`, `kolonie-platform`, `kolonie-openclaw` and `kolonie-hermes`.
# Two more skill repositories existed by then, were not in the list, and were
# exactly the two that had gone stale — the copies nobody looked at were the
# copies that drifted. A list goes blind every time the organisation grows, and
# it does so silently, which is the worst available failure for a check.
#
# So: ask the API which repositories exist, ask each one whether it holds a file
# named `SKILL.md` anywhere, and take the ones that do. A skill repository added
# next month is checked next month without anybody editing this.
#
# `about.ts` is named rather than discovered, because there is nothing to derive
# it from — it is one known field in one known file, and a search for anything
# resembling it would match more than it should.
#
# `onboarding/arrival.md` is named for the same reason, and it is the same
# failure as the hard-coded list arriving by a different route (`#117`): not a
# repository the list forgot, but a copy the *pattern* does not match. `#102`
# added it as the runtime-neutral entry point and it carries the red lines in
# full, for the reason the skills do — the reader who most needs them has not
# connected to anything yet. It is not a `SKILL.md`, so discovery never saw it.
#
# It is worse here than in a skill, in one respect: `arrival.md` is served to
# agents on runtimes that have no skill at all, so a stale copy binds the readers
# with the fewest other ways to find out.
#
# Widening the pattern to any Markdown is the wrong fix — it would pull in every
# document that quotes a red line in passing, which is a different and much worse
# check. One known path in one known repository, named.
#
# ## Where each copy is read from (`#301`)
#
# **This repository's three copies come off the checkout; everything else comes
# over the API.** `red-lines.md`, `arrival.md` and `body.md` all live here, and
# the workflow has already checked this repository out at the commit under test
# before this script runs.
#
# Reading them over the network was wrong twice over. It was wrong for
# correctness first: the API answers with the *default branch*, so a pull request
# editing `red-lines.md` was checked against `main` and the commit that actually
# changed the rules went unexamined. And it was wrong for reliability second —
# three of the four named reads could fail on files sitting on disk, and twice in
# one session they did.
#
# The labels below still name the repository and path, because that is what the
# file *is*, and a divergence report has to say which document to go and fix. A
# local run therefore compares the working tree under that name, which is the
# behaviour worth having: drift is visible before it is pushed.
#
# ## What a failed read may never look like (`#301`)
#
# **A read that did not happen is not a divergence.** This check's one message is
# *the copies of the red lines no longer agree*, and that is the alarm in this
# organisation that must never cry wolf: an agent seeing it has to assume the
# terms of citizenship drifted somewhere and go looking. Two transient `gh` reads
# reported in that voice teach everybody to rerun first and read second, which is
# precisely how the real one gets missed.
#
# So every read of the API is tried more than once before it is believed, and
# when it is finally given up on it says in its own words that nothing was
# compared. The retry is not the important half of that. The wording is.
set -uo pipefail

OUT="${1:?usage: find-red-line-copies.sh <output-directory>}"
ORG=Kolonie-AI
SOURCE_REPO="$ORG/kolonie-docs"
SOURCE_PATH=governance/red-lines.md
API_COPY_REPO="$ORG/kolonie-platform"
API_COPY_PATH=apps/api/src/about.ts
ARRIVAL_COPY_REPO="$ORG/kolonie-docs"
ARRIVAL_COPY_PATH=onboarding/arrival.md
BODY_COPY_REPO="$ORG/kolonie-docs"
BODY_COPY_PATH=onboarding/skill/body.md
# The Atlas invitation (`#399`) is a second set of rules written into the *same*
# documents, so it needs one more source and not one more sweep. Every copy it
# compares — `about.ts`, `arrival.md`, `body.md` and every discovered `SKILL.md`
# — is already on disk when the manifests are written, which is why the second
# comparison costs one local file copy and no requests at all.
INVITATION_SOURCE_REPO="$ORG/kolonie-docs"
INVITATION_SOURCE_PATH=governance/the-atlas.md
INVITATION_SECTION="The invitation"
INVITATION_FIELD=atlasInvitation

# This repository, wherever it happens to be checked out — from the script's own
# location rather than from the working directory, because both workflows and
# `check.sh` call it from the root and a reader running it from anywhere else
# should get the same answer rather than a confusing one.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# Three tries, doubling from two seconds. Enough for the failure that was
# actually seen — one slow response — and short enough that a repository which is
# genuinely gone is reported inside the run's ten-minute budget rather than
# holding a timeout open. Ten reads that each retried at length would turn a
# GitHub outage into a job that never finishes and says nothing.
#
# Overridable so `.github/tests/find-red-line-copies.test.sh` can exercise the
# retry without sleeping through it, the seam `red-lines-report.sh` already has
# for its own wait. Nothing in CI sets either.
RETRY_ATTEMPTS=${RETRY_ATTEMPTS:-3}
RETRY_FIRST_DELAY_SECONDS=${RETRY_FIRST_DELAY_SECONDS:-2}

mkdir -p "$OUT"

api() {
  # One read of the API, tried a few times before it is believed. `what` is the
  # thing in human words, because the caller knows what it was asking for and the
  # error is read by somebody who does not.
  local what=$1
  shift
  local attempt=1 delay=$RETRY_FIRST_DELAY_SECONDS output
  while true; do
    if output=$(gh api "$@" 2>/dev/null); then
      printf '%s\n' "$output"
      return 0
    fi
    if [ "$attempt" -ge "$RETRY_ATTEMPTS" ]; then
      echo "::error::could not read $what after $RETRY_ATTEMPTS attempts." \
        "**This is a failed read, not a divergence** — nothing was compared, and" \
        "nothing here says the copies disagree." >&2
      return 1
    fi
    echo "could not read $what (attempt $attempt of $RETRY_ATTEMPTS), retrying in ${delay}s" >&2
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}

fetch() {
  # A file's content at another repository's default branch. Fails loudly: a copy
  # that cannot be read must not be quietly dropped from the comparison.
  local repo=$1 path=$2 destination=$3 content
  content=$(api "$path from $repo" "repos/$repo/contents/$path" --jq '.content') || return 1
  printf '%s' "$content" | base64 -d > "$destination"
  [ -s "$destination" ] || { echo "::error::$path in $repo is empty"; return 1; }
}

skill_paths_in() {
  # The default branch's tree, one call per repository, filtered to anything
  # named SKILL.md at any depth — `SKILL.md` at the root in one repository,
  # `skills/kolonie/SKILL.md` in the others, and whatever the next one chooses.
  #
  # **A repository with no tree is an answer and not a failure**, which is why
  # this is its own function rather than a call to `api`. An empty repository
  # answers 409 and one with no readable default branch answers 404; both mean
  # *there is no SKILL.md here*, they are permanent, and retrying them would
  # spend thirty seconds per repository to arrive at the same nothing. Every
  # other failure is weather and is retried.
  local repo=$1 attempt=1 delay=$RETRY_FIRST_DELAY_SECONDS output complaint
  complaint=$(mktemp)
  while true; do
    if output=$(gh api "repos/$repo/git/trees/HEAD?recursive=1" \
        --jq '.tree[]? | select(.type == "blob") | .path | select(test("(^|/)SKILL\\.md$"))' \
        2>"$complaint"); then
      printf '%s\n' "$output"
      rm -f "$complaint"
      return 0
    fi
    if grep -qE 'HTTP (404|409)' "$complaint"; then
      rm -f "$complaint"
      return 0
    fi
    if [ "$attempt" -ge "$RETRY_ATTEMPTS" ]; then
      echo "::error::could not read the file list of $repo after $RETRY_ATTEMPTS attempts." \
        "**This is a failed read, not a divergence** — the comparison was never made." >&2
      rm -f "$complaint"
      return 1
    fi
    echo "could not read the file list of $repo (attempt $attempt of $RETRY_ATTEMPTS)," \
      "retrying in ${delay}s" >&2
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}

take() {
  # A copy that lives in this repository, taken from the checkout. No retry and
  # no network: a file that is not on disk will not be there in two seconds, and
  # its absence is a defect in this repository rather than weather.
  local path=$1 destination=$2
  if [ ! -f "$ROOT/$path" ]; then
    echo "::error::$path is not in this checkout." \
      "**This is a failed read, not a divergence** — nothing was compared."
    return 1
  fi
  cp "$ROOT/$path" "$destination"
  [ -s "$destination" ] || { echo "::error::$path in this checkout is empty"; return 1; }
}

take "$SOURCE_PATH" "$OUT/source.md" || exit 1
fetch "$API_COPY_REPO" "$API_COPY_PATH" "$OUT/about.ts" || exit 1
take "$ARRIVAL_COPY_PATH" "$OUT/arrival.md" || exit 1
take "$BODY_COPY_PATH" "$OUT/body.md" || exit 1
take "$INVITATION_SOURCE_PATH" "$OUT/invitation-source.md" || exit 1

# `markdown-skill`: the parser reads a `## Red lines` section with
# `named_paragraphs=False`, and that is exactly what `arrival.md` is — the seven
# bullets, plus prose that is commentary rather than rules. No new parser.
#
# Its introductory sentence differs from the skills' on purpose and is not
# compared: they say *"whether to let you install a skill that handles a
# credential"* and this says *"whether to let you handle a credential"*, because
# nothing is being installed. The parser does not extract that sentence, so the
# difference costs nothing — recorded here so the next reader does not read it
# as drift.
#
# `onboarding/skill/body.md` is named for the same reason as `arrival.md`, and it
# is the same failure arriving a third way: not a repository the list forgot and
# not a path the pattern misses, but **the copy the discovered copies are made
# from**. Since `kolonie-docs#171` the seven `SKILL.md` files are generated from
# it, so a red line edited there reaches all seven at once. Discovery finds the
# outputs; without this line nothing checks the input, and a divergence would be
# reported seven times with no indication of where it came in.
entries=$(printf '{"label":"%s/%s","file":"about.ts","kind":"typescript"},{"label":"%s/%s","file":"arrival.md","kind":"markdown-skill"},{"label":"%s/%s","file":"body.md","kind":"markdown-skill"}' \
  "$API_COPY_REPO" "$API_COPY_PATH" "$ARRIVAL_COPY_REPO" "$ARRIVAL_COPY_PATH" \
  "$BODY_COPY_REPO" "$BODY_COPY_PATH")

# The same three files again, read at a different heading and a different field
# (`#399`). Named `markdown-bullets` rather than `markdown-skill` because the
# section it reads is not the skills' one: the shape is what the kind says, and
# the section is beside it.
invitation_entries=$(printf '{"label":"%s/%s","file":"about.ts","kind":"typescript","section":"%s"},{"label":"%s/%s","file":"arrival.md","kind":"markdown-bullets","section":"%s"},{"label":"%s/%s","file":"body.md","kind":"markdown-bullets","section":"%s"}' \
  "$API_COPY_REPO" "$API_COPY_PATH" "$INVITATION_FIELD" \
  "$ARRIVAL_COPY_REPO" "$ARRIVAL_COPY_PATH" "$INVITATION_SECTION" \
  "$BODY_COPY_REPO" "$BODY_COPY_PATH" "$INVITATION_SECTION")

# Both of these used to be bare `gh api` calls whose failure was swallowed, and
# that was the quieter half of `#301`. A dropped repository does not turn the run
# red — it makes the check pass on fewer copies than it should, which is the one
# failure `MINIMUM_COPIES` was put in `red-lines.py` to catch and is exactly the
# failure a single dropped repository is too small to trip.
repos=$(api "the repository list for $ORG" "orgs/$ORG/repos" --paginate --jq '.[].full_name') || exit 1

index=0
for repo in $(echo "$repos" | sort); do
  tree=$(skill_paths_in "$repo") || exit 1
  for path in $tree; do
    file="skill-$index.md"
    fetch "$repo" "$path" "$OUT/$file" || exit 1
    entries="$entries,$(printf '{"label":"%s/%s","file":"%s","kind":"markdown-skill"}' \
      "$repo" "$path" "$file")"
    invitation_entries="$invitation_entries,$(printf \
      '{"label":"%s/%s","file":"%s","kind":"markdown-bullets","section":"%s"}' \
      "$repo" "$path" "$file" "$INVITATION_SECTION")"
    index=$((index + 1))
    echo "found $repo/$path"
  done
done

# `clarification` names two files and nothing else (`#173`).
#
# The section below `Forbidden` says what a citizen *may* do, it has exactly two
# copies, and neither is discovered — there is no population to sweep, so this
# is a pair of names rather than an entry in `copies`. Both files are already
# fetched above for the rules, so this costs no request and does not move
# `MINIMUM_COPIES`, which is about the discovered half.
cat > "$OUT/manifest.json" <<JSON
{
  "source": {
    "label": "$SOURCE_REPO/$SOURCE_PATH",
    "file": "source.md",
    "kind": "markdown-forbidden"
  },
  "clarification": {
    "source": "source.md",
    "projection": "about.ts"
  },
  "copies": [$entries]
}
JSON

# The invitation's own manifest, over the files already fetched (`#399`).
#
# **A second manifest rather than a second section in the first one.** The two
# comparisons fail for different reasons and are reported separately — copies of
# the red lines disagreeing is `p1` and binds citizens on wrong terms; copies of
# the invitation disagreeing is `p2` and is stale encouragement. One manifest
# would have made them one verdict, and the louder of the two would have set the
# priority for both.
#
# No `clarification`: the invitation has none, and the key is optional.
cat > "$OUT/manifest-invitation.json" <<JSON
{
  "source": {
    "label": "$INVITATION_SOURCE_REPO/$INVITATION_SOURCE_PATH",
    "file": "invitation-source.md",
    "kind": "markdown-bullets",
    "section": "$INVITATION_SECTION"
  },
  "copies": [$invitation_entries]
}
JSON

echo "manifest written with $((index + 3)) copies"

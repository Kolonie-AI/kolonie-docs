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
set -uo pipefail

OUT="${1:?usage: find-red-line-copies.sh <output-directory>}"
ORG=Kolonie-AI
SOURCE_REPO="$ORG/kolonie-docs"
SOURCE_PATH=governance/red-lines.md
API_COPY_REPO="$ORG/kolonie-platform"
API_COPY_PATH=apps/api/src/about.ts
ARRIVAL_COPY_REPO="$ORG/kolonie-docs"
ARRIVAL_COPY_PATH=onboarding/arrival.md

mkdir -p "$OUT"

fetch() {
  # A file's content at the default branch. Fails loudly: a copy that cannot be
  # read must not be quietly dropped from the comparison.
  local repo=$1 path=$2 destination=$3
  if ! gh api "repos/$repo/contents/$path" --jq '.content' 2>/dev/null | base64 -d > "$destination"; then
    echo "::error::could not read $path from $repo"
    return 1
  fi
  [ -s "$destination" ] || { echo "::error::$path in $repo is empty"; return 1; }
}

fetch "$SOURCE_REPO" "$SOURCE_PATH" "$OUT/source.md" || exit 1
fetch "$API_COPY_REPO" "$API_COPY_PATH" "$OUT/about.ts" || exit 1
fetch "$ARRIVAL_COPY_REPO" "$ARRIVAL_COPY_PATH" "$OUT/arrival.md" || exit 1

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
entries=$(printf '{"label":"%s/%s","file":"about.ts","kind":"typescript"},{"label":"%s/%s","file":"arrival.md","kind":"markdown-skill"}' \
  "$API_COPY_REPO" "$API_COPY_PATH" "$ARRIVAL_COPY_REPO" "$ARRIVAL_COPY_PATH")

index=0
for repo in $(gh api "orgs/$ORG/repos" --paginate --jq '.[].full_name' | sort); do
  # The default branch's tree, one call per repository, filtered to anything
  # named SKILL.md at any depth — `SKILL.md` at the root in one repository,
  # `skills/kolonie/SKILL.md` in the others, and whatever the next one chooses.
  for path in $(gh api "repos/$repo/git/trees/HEAD?recursive=1" \
      --jq '.tree[]? | select(.type == "blob") | .path | select(test("(^|/)SKILL\\.md$"))' 2>/dev/null); do
    file="skill-$index.md"
    fetch "$repo" "$path" "$OUT/$file" || exit 1
    entries="$entries,$(printf '{"label":"%s/%s","file":"%s","kind":"markdown-skill"}' \
      "$repo" "$path" "$file")"
    index=$((index + 1))
    echo "found $repo/$path"
  done
done

cat > "$OUT/manifest.json" <<JSON
{
  "source": {
    "label": "$SOURCE_REPO/$SOURCE_PATH",
    "file": "source.md",
    "kind": "markdown-forbidden"
  },
  "copies": [$entries]
}
JSON

echo "manifest written with $((index + 2)) copies"

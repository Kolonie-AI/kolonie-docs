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
set -uo pipefail

OUT="${1:?usage: find-red-line-copies.sh <output-directory>}"
ORG=Kolonie-AI
SOURCE_REPO="$ORG/kolonie-docs"
SOURCE_PATH=governance/red-lines.md
API_COPY_REPO="$ORG/kolonie-platform"
API_COPY_PATH=apps/api/src/about.ts

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

entries=$(printf '{"label":"%s/%s","file":"about.ts","kind":"typescript"}' \
  "$API_COPY_REPO" "$API_COPY_PATH")

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

echo "manifest written with $((index + 1)) copies"

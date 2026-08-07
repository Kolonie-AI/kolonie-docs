#!/usr/bin/env python3
"""Write the shared Colony header into a repository's `README.md`.

Usage:
    python3 .github/scripts/build-readme.py HEADER TARGET
    python3 .github/scripts/build-readme.py HEADER TARGET --check

`kolonie-docs#219` measured the opening of all fourteen READMEs in this
organisation. Every one of them began with the repository's name and a technical
sentence:

    # kolonie-platform
    > The Kolonie AI platform: domain model, public API, and academy verification.

Somebody who arrives at `kolonie-infra` from a search result has no idea what the
Colony is, and nothing above the fold tells them or offers them a way to find
out. **A README is the first page anybody sees**, and thirteen of them were the
first page of a project the reader could not identify.

The decision taken there was **generate**, on exactly the argument
`build-skill.py` beside this file was written for and which `#171` states: a
test tells thirteen repositories they disagree, it does not write the sentence.
Thirteen hand-maintained headers diverge within a month, and the one that matters
is always the one nobody updated.

## The shape, and why it is not `build-skill.py`

`SKILL.md` is generated **whole**, because all of it is either shared text or a
runtime's own slot. A README is the opposite: nearly all of it belongs to its
repository and must not be touched. So this writes into a **region** and leaves
the rest of the file alone.

    <!-- kolonie:header -->
    …generated, replaced wholesale…
    <!-- kolonie:end -->

**There are no slots and there will not be any.** `#219`: *"It should not repeat
the repository's own description; it establishes the context the repository sits
in."* A header that varies per repository is thirteen headers again, arriving by
a slower route. What a repository has to say about itself goes below the region,
where it already is.

## The three refusals

**The region must start on line 1.** `#219`'s acceptance criterion is *"every
README links to `kolonie.ai` above the fold"*, and above-the-fold is not a
property a script can measure — where the fold falls depends on the reader's
window. Line 1 is the one position that satisfies it on every window there is,
so it is what gets checked. A header three screens down passes a naive marker
check and fails the reader, which is the failure this whole file exists to stop.

**A target without the markers is an error, not a file to be helpfully fixed.**
Inserting the region automatically would mean this script deciding where a
document begins, in a repository it knows nothing about — and doing it silently
on a `--check` run, which is meant to write nothing. The error names the two
lines to paste and where.

**The mark is referenced, never committed.** `brand/README.md` §4: *"Never commit
a copy of the mark to this repository."* The header points at
`https://kolonie.ai/mark-192.png`, which `kolonie-website` publishes and its own
`assets.test.ts` checks against the theme tokens. A copy in thirteen repositories
is thirteen images that go stale the first time the palette moves, and none of
them is tested anywhere. **PNG rather than SVG** is not a preference either:
GitHub proxies images through camo and is unreliable with externally hosted SVG.

## What is deliberately not a target

**`.github/profile/README.md`** — the organisation profile. It is the only one
of the fourteen that is not a repository's README: it serves somebody who has
arrived at *the project*, from a registry entry or a link in a list, and it is
built as a landing page rather than as a document with a signpost on top
(`kolonie-docs#220`). Generating a three-line *what this is* into the top of a
page whose whole job is to be that would be one claim made twice, and the second
one would be the stale one.

`--check` writes nothing and exits 2 if the region on disk is not what would be
generated. That is the form CI runs, in this repository and in each of the
thirteen.
"""

import sys

OPEN = "<!-- kolonie:header -->"
CLOSE = "<!-- kolonie:end -->"


class Problem(Exception):
    """Something that must stop the build rather than be worked around."""


def render(header_path):
    """The region's contents: the shared header, with its markers around it."""
    header = open(header_path, encoding="utf-8").read().strip("\n")
    return f"{OPEN}\n{header}\n{CLOSE}"


def splice(target_text, region, target_path):
    """Return `target_text` with its header region replaced by `region`.

    Everything outside the two markers is returned byte for byte. That is the
    property that lets thirteen repositories accept a generated edit to a file
    they own the rest of.
    """
    lines = target_text.split("\n")

    opens = [i for i, line in enumerate(lines) if line.strip() == OPEN]
    closes = [i for i, line in enumerate(lines) if line.strip() == CLOSE]

    if not opens:
        raise Problem(
            f"{target_path}: no header region. Paste these two lines as line 1 and 2 "
            f"of the file, then run this again:\n    {OPEN}\n    {CLOSE}"
        )
    if len(opens) > 1:
        raise Problem(
            f"{target_path}:{opens[1] + 1}: a second '{OPEN}'. "
            "One region, or the second one wins and nothing says so"
        )
    if not closes:
        raise Problem(f"{target_path}: '{OPEN}' is never closed with '{CLOSE}'")

    start = opens[0]
    after = [i for i in closes if i > start]
    if not after:
        raise Problem(f"{target_path}: '{CLOSE}' appears above '{OPEN}'")
    end = after[0]

    if start != 0:
        raise Problem(
            f"{target_path}:{start + 1}: the header region must start on line 1. "
            "It is what a reader sees before scrolling, and line 1 is the only "
            "position that is above the fold on every window"
        )

    return "\n".join(lines[:start] + region.split("\n") + lines[end + 1 :])


def main(argv):
    check = "--check" in argv
    args = [a for a in argv if a != "--check"]
    if len(args) != 3:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2

    _, header_path, target_path = args

    region = render(header_path)
    current = open(target_path, encoding="utf-8").read()
    updated = splice(current, region, target_path)

    if check:
        if updated != current:
            print(
                f"{target_path} is not what {header_path} generates. "
                "Run without --check and commit the result.",
                file=sys.stderr,
            )
            return 2
        print(f"{target_path} is current")
        return 0

    if updated == current:
        print(f"{target_path} unchanged")
        return 0

    open(target_path, "w", encoding="utf-8").write(updated)
    print(f"{target_path} written")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Problem as problem:
        print(problem, file=sys.stderr)
        sys.exit(2)

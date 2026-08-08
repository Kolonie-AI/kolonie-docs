#!/usr/bin/env python3
"""Write a shared Colony region into a repository's `README.md`.

Usage:
    python3 .github/scripts/build-readme.py SOURCE TARGET [--region NAME] [--first]
    python3 .github/scripts/build-readme.py SOURCE TARGET … --check

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

## The two regions there are

| Region | Source | In | Rule |
|---|---|---|---|
| `header` | `onboarding/readme/header.md` | all thirteen | must start on line 1 |
| `skill-intro` | `onboarding/readme/skill-intro.md` | the seven skill repositories | sits under the repository's own title |

`skill-intro` exists for `kolonie-docs#221`, which asks that the seven skill
READMEs open with what an agent comes to own — and that *"anything said in both
comes from the generator, on the arrangement `SKILL.md` already uses. Seven
hand-maintained copies of one claim is seven chances for one of them to be a
year out of date."* That is a second shared region, not a second mechanism, and
the whole cost of it is `--region`.

**Adding a third is a decision, not a convenience.** Every region is a piece of
a repository's README that the repository can no longer edit, and the argument
for taking that away has to be that the sentence is *the same sentence
everywhere*. A region that exists because two repositories happened to agree
once is how this becomes a template engine.

## The three refusals

**The header region must start on line 1**, and `--first` is what asks for that.
`#219`'s acceptance criterion is *"every README links to `kolonie.ai` above the
fold"*, and above-the-fold is not a property a script can measure — where the
fold falls depends on the reader's window. Line 1 is the one position that
satisfies it on every window there is, so it is what gets checked. A header three
screens down passes a naive marker check and fails the reader, which is the
failure this whole file exists to stop.

It is a flag rather than always-on because it is true of one region. `skill-intro`
belongs under the repository's own title, where a reader who has just identified
the repository meets it.

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


def opener(region_name):
    """The open marker for a named region. `header` is the one without a suffix."""
    return OPEN if region_name == "header" else f"<!-- kolonie:{region_name} -->"


def render(source_path, region_name):
    """The region's contents: the shared source, with its markers around it."""
    source = open(source_path, encoding="utf-8").read().strip("\n")
    return f"{opener(region_name)}\n{source}\n{CLOSE}"


def splice(target_text, region, target_path, region_name, first):
    """Return `target_text` with its named region replaced by `region`.

    Everything outside the two markers is returned byte for byte. That is the
    property that lets thirteen repositories accept a generated edit to a file
    they own the rest of.

    `first` is the line-1 rule, and it is a parameter rather than always-on
    because it is only true of one region. The header is what a reader meets
    before scrolling; the skill intro sits under the repository's own title,
    where it is meant to.
    """
    open_marker = opener(region_name)
    lines = target_text.split("\n")

    opens = [i for i, line in enumerate(lines) if line.strip() == open_marker]
    closes = [i for i, line in enumerate(lines) if line.strip() == CLOSE]

    if not opens:
        raise Problem(
            f"{target_path}: no '{region_name}' region. Paste these two lines "
            f"{'as line 1 and 2 of the file' if first else 'where the region belongs'}, "
            f"then run this again:\n    {open_marker}\n    {CLOSE}"
        )
    if len(opens) > 1:
        raise Problem(
            f"{target_path}:{opens[1] + 1}: a second '{open_marker}'. "
            "One region, or the second one wins and nothing says so"
        )
    if not closes:
        raise Problem(f"{target_path}: '{open_marker}' is never closed with '{CLOSE}'")

    start = opens[0]
    after = [i for i in closes if i > start]
    if not after:
        raise Problem(f"{target_path}: '{CLOSE}' appears above '{open_marker}'")
    end = after[0]

    if first and start != 0:
        raise Problem(
            f"{target_path}:{start + 1}: the header region must start on line 1. "
            "It is what a reader sees before scrolling, and line 1 is the only "
            "position that is above the fold on every window"
        )

    return "\n".join(lines[:start] + region.split("\n") + lines[end + 1 :])


def main(argv):
    check = "--check" in argv
    first = "--first" in argv
    region_name = "header"
    args = []
    rest = argv[1:]
    while rest:
        token = rest.pop(0)
        if token in ("--check", "--first"):
            continue
        if token == "--region":
            if not rest:
                print("--region needs a name", file=sys.stderr)
                return 2
            region_name = rest.pop(0)
            continue
        args.append(token)

    if len(args) != 2:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2

    source_path, target_path = args

    region = render(source_path, region_name)
    current = open(target_path, encoding="utf-8").read()
    updated = splice(current, region, target_path, region_name, first)

    if check:
        if updated != current:
            print(
                f"{target_path}: the '{region_name}' region is not what "
                f"{source_path} generates. Run without --check and commit the result.",
                file=sys.stderr,
            )
            return 2
        print(f"{target_path} '{region_name}' is current")
        return 0

    if updated == current:
        print(f"{target_path} '{region_name}' unchanged")
        return 0

    open(target_path, "w", encoding="utf-8").write(updated)
    print(f"{target_path} '{region_name}' written")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Problem as problem:
        print(problem, file=sys.stderr)
        sys.exit(2)

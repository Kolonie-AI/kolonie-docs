#!/usr/bin/env python3
"""Nothing was lost in a split. `kolonie-docs#363`.

Usage:
    python3 .github/scripts/check-brief-coverage.py [.github/coverage-splits.txt]

## Why this exists

A prose file split by hand loses paragraphs at the seams and nobody notices for
weeks. `AGENTS.md` was 2.021 lines and is the contract every agent works under —
a paragraph that fell out of it between two modules would not be missed by any
reader until the day somebody needed it.

So the promise is turned into a build failure: **every non-blank line of the
pre-split file must still be somewhere.** The pre-split file is pinned by commit
SHA, which is what makes this checkable at all — the thing being compared against
cannot drift, because it is history.

## What it does not assert, and why

The issue asked for *exactly one module*. This asserts **at least one**, and the
difference is deliberate: dozens of lines in any Markdown file are punctuation
that recurs legitimately — a fence, a table separator, `---`, `| | |`. Requiring
uniqueness would fail on the shape of Markdown rather than on lost content, and a
check that is wrong for a reason nobody can act on gets deleted rather than
fixed.

What can be lost is *content*, and content lines are distinctive. This finds
them.

## It is deletable, and that is the plan

One release after a split lands, the row for it comes out of
`.github/coverage-splits.txt` — the modules are then the thing being maintained
and the pre-split file is only history. A row that is never removed is a
permanent tax on editing a module: every deletion of a sentence written before
the split turns the build red. **The rows carry the date they were added**, so
whoever reads this next can see which ones have outstayed their purpose.

## The configuration

`.github/coverage-splits.txt`, one row per split, whitespace-separated:

    <source-path> <sha> <destination-glob>...

`#` comments and blank lines are ignored. The source is read with
`git show <sha>:<path>`; the destinations are read from the working tree, so
this checks what is about to be committed rather than what was.

## Retiring a line on purpose

A split does not only move text: a few sentences stop being true *because* of
it, and the core's own framing is where that happens — *"this file is the whole
answer"* cannot survive a change that makes it one file of nine.

Those go in `.github/coverage-retired.txt`, one line of source text per line,
under a `#` comment saying why. **The count is printed on every run, passing or
failing**, because the danger of an exceptions list is that it grows quietly
until the check is measuring nothing. A line listed there that is still present
is reported too — a stale entry hides the next real loss behind it.

**A source line that itself begins with `#` is written with one leading
backslash** — `\\#### A heading` retires `#### A heading`. Without it the syntax
gives a comment and a Markdown heading the same first character, so a retired
heading was silently read as a comment and reported lost forever
(`kolonie-docs#507`). Nothing else in the line is touched.
"""
import fnmatch
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]

# A link whose *target* moved is not a lost line. A split rewrites every
# `](#4-...)` into `](board.md#4-...)` and every `](operations/x.md)` into
# `](../operations/x.md)` — hundreds of lines, none of which lost a word. So
# targets are folded away before comparing and the link text is not: what this
# check is about is content, and where a link points is plumbing the link
# checker already verifies (`check-links.py`, on every run of `check.sh`).
LINK_TARGET = re.compile(r"\]\([^)]*\)")


def normalise(line):
    return LINK_TARGET.sub("](*)", line.strip())


def content_lines(text):
    """The file without its front matter.

    Front matter is routing metadata, not content: a `summary:` shortened to fit
    the start manifest is not a paragraph that fell out at a seam, and reporting
    it as one teaches whoever reads this check to skim its output. What the
    front matter says is checked where it means something — `brief.sh` refuses a
    shape it cannot parse, and `brief.test.sh` asserts every module has a
    summary at all.
    """
    lines = text.splitlines()
    if lines and lines[0].strip() == "---":
        for i, line in enumerate(lines[1:], 1):
            if line.strip() == "---":
                return list(enumerate(lines[i + 1:], i + 2))
    return list(enumerate(lines, 1))


CONFIG = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / ".github/coverage-splits.txt"
RETIRED = ROOT / ".github/coverage-retired.txt"
SHOW_AT_MOST = 15


def retired_lines():
    if not RETIRED.exists():
        return set()
    retired = set()
    for raw in RETIRED.read_text().splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw.startswith("\\#"):
            raw = raw[1:]
        retired.add(normalise(raw))
    return retired


def tracked_files():
    out = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "*.md"],
        capture_output=True, text=True, check=True).stdout
    return out.split()


def source_at(sha, path):
    r = subprocess.run(
        ["git", "-C", str(ROOT), "show", f"{sha}:{path}"],
        capture_output=True, text=True)
    if r.returncode != 0:
        return None, r.stderr.strip()
    return r.stdout, None


def main():
    if not CONFIG.exists():
        print(f"{CONFIG} does not exist, so no split is being watched. That is a")
        print("valid state — every split has aged out — but it is worth saying out loud.")
        return 0

    rows = []
    for raw in CONFIG.read_text().splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 3:
            print(f"::error file={CONFIG}::'{raw}' needs <source> <sha> <glob>...")
            return 1
        rows.append((parts[0], parts[1], parts[2:]))

    if not rows:
        print(f"{CONFIG} holds no rows: nothing is being watched.")
        return 0

    failed = False
    everything = tracked_files()
    retired = retired_lines()
    if retired:
        print(f"  {len(retired)} line(s) are deliberately retired "
              f"({RETIRED.relative_to(ROOT)}); each carries its reason there")

    for path, sha, globs in rows:
        text, err = source_at(sha, path)
        if text is None:
            print(f"::error file={CONFIG}::cannot read {path} at {sha}: {err}")
            print("  A pinned SHA that has left the repository cannot be compared against.")
            print("  If the split has aged out, delete the row rather than moving the pin.")
            failed = True
            continue

        destinations = [f for f in everything if any(fnmatch.fnmatch(f, g) for g in globs)]
        if not destinations:
            print(f"::error file={CONFIG}::{path}: no file matches {' '.join(globs)}")
            failed = True
            continue

        haystack = set()
        for d in destinations:
            for line in (ROOT / d).read_text().splitlines():
                haystack.add(normalise(line))

        missing = [
            (n, line.strip())
            for n, line in content_lines(text)
            if line.strip()
            and normalise(line) not in haystack
            and normalise(line) not in retired
        ]

        # A retirement that is no longer a retirement. Left alone it excuses a
        # future loss of the same line, which is the one way this list can rot.
        stale = sorted(r for r in retired if r in haystack)
        if stale:
            failed = True
            print(f"::error file={RETIRED.relative_to(ROOT)}::"
                  f"{len(stale)} retired line(s) are present after all")
            for r in stale[:SHOW_AT_MOST]:
                print(f"  {r[:110]}")
            print("  Delete the entry: a line that is here does not need excusing,")
            print("  and an entry that excuses nothing will excuse the next real loss.")

        if missing:
            failed = True
            print(f"::error file={path}::{len(missing)} line(s) of {path}@{sha[:7]} "
                  f"are in none of: {' '.join(globs)}")
            for n, line in missing[:SHOW_AT_MOST]:
                print(f"  {path}:{n}  {line[:110]}")
            if len(missing) > SHOW_AT_MOST:
                print(f"  ... and {len(missing) - SHOW_AT_MOST} more")
            print("  Every line of the pre-split file must still be somewhere: a module,")
            print("  or agents/history/ if it is the narrative behind a rule. If a line is")
            print("  genuinely being retired, retire it in its own commit and say why —")
            print("  do not let it disappear inside a move.")
        else:
            kept = len([l for _, l in content_lines(text) if l.strip()])
            print(f"  {path}@{sha[:7]}: {kept} lines, all present across "
                  f"{len(destinations)} file(s)")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

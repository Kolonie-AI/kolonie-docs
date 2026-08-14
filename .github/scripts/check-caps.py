#!/usr/bin/env python3
"""The core is capped, and so is every module. `kolonie-docs#365`.

Usage:
    python3 .github/scripts/check-caps.py

## Why this is not optional

216 lines on 2026-07-27. 2.021 on 2026-08-14. Eighteen days, roughly 100 lines a
day, and every one of them a good-faith improvement. Without a number that fails
the build, the split that produced `agents/` is undone by the end of September
and the work is spent.

## The caps

| | |
|---|---|
| the `always` module — the core everybody gets | **200 lines** |
| every other module | **400 lines** |
| a module that declares `max-lines:` | that number |

## `max-lines:` is a ratchet, not an escape hatch

A module may declare a cap **above** the default, and the declaration is the
point: it is visible in the diff, printed by this check on every run, and it can
only go down. Two rules make it a ratchet rather than a hiding place:

- **A file over its own declared cap fails**, like any other.
- **A file more than 50 lines *under* its declared cap fails too**, saying so:
  the cap has slack and must be lowered. So a document that shrinks drags its own
  ceiling down behind it, and nobody can leave a generous number lying around
  for a future author to grow into.

`state/STATUS.md` is why this exists. It is 919 lines against a rule that has
been written down twice since 2026-07-29 and never enforced — see
`state/decisions/status-md-grew-because-both-rules-bound-shape-and-neither-bound-count.md`.
Capping it at 400 today would fail the build for work nobody has scheduled;
capping it at what it is, with a ratchet, turns every future edit into a small
downward pressure and makes the debt legible in one line of front matter.

## What the failure message must do

Name the alternative. A cap met by deleting a rule has made the document worse
and the number better, which is the one outcome worth designing against.
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORE_CAP = 200
MODULE_CAP = 400
MAX_SLACK = 50

FIX = """  Do not delete a rule to fit. A rule that applies to some issues goes in
  agents/<module>.md with applies-to:; the reason a rule exists goes in
  agents/history/, which is briefed to nobody. Only a rule every agent needs on
  every issue belongs in the core."""


def front_matter(path):
    text = path.read_text()
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    return text[4:end] if end != -1 else None


def main():
    files = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "*.md"],
        capture_output=True, text=True, check=True).stdout.split()

    failed = False
    declared = []

    for rel in sorted(files):
        path = ROOT / rel
        fm = front_matter(path)
        if fm is None or not re.search(r"^module:", fm, re.M):
            continue

        lines = len(path.read_text().splitlines())
        is_core = re.search(r"^\s+always:\s*true\s*$", fm, re.M) is not None
        declared_cap = re.search(r"^max-lines:\s*(\d+)", fm, re.M)

        if declared_cap:
            cap = int(declared_cap.group(1))
            declared.append((rel, lines, cap))
        else:
            cap = CORE_CAP if is_core else MODULE_CAP

        if lines > cap:
            failed = True
            print(f"::error file={rel}::{rel} is {lines} lines; the cap is {cap}.")
            print(FIX)
            if not declared_cap:
                print(f"  If this file genuinely cannot fit {cap}, declare `max-lines:` in its")
                print("  front matter — it is a ratchet, printed on every run, and it may only")
                print("  ever be lowered.")
        elif declared_cap and cap - lines > MAX_SLACK:
            failed = True
            print(f"::error file={rel}::{rel} declares max-lines: {cap} and is {lines} lines.")
            print(f"  That is {cap - lines} lines of slack, and the declaration is a ratchet:")
            print(f"  lower it to about {lines + 10}. A cap nobody has to meet is not one.")

    if declared:
        print("  declared caps, each of which may only ever be lowered:")
        for rel, lines, cap in declared:
            print(f"    {rel}  {lines}/{cap}")

    if not failed:
        print(f"  every module is within its cap (core {CORE_CAP}, modules {MODULE_CAP})")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

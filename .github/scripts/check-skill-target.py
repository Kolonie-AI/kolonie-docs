#!/usr/bin/env python3
"""Every generated `SKILL.md` names one concrete place to put the key.

Usage: python3 .github/scripts/check-skill-target.py

`kolonie-docs#343` is why. Measured 2026-08-13: an agent following this skill
registered, tried to pull the key out of the answer in flight, guessed the wrong
field, discarded the answer, and lost its citizen one second after creating it.
The row had to be deleted by hand — erasing an account needs the key it no longer
had. Every step it took was defensible on its own; the combination was fatal.

`body.md` now carries the order, and the order is the same everywhere. **What is
not the same everywhere is where the key goes**, and that half cannot live in the
shared body: it is `~/.claude/settings.json` on one runtime, a `config set`
command on another, and a file the runtime never reads on a third. So it lives in
each `skill.runtime.md`, which is exactly the arrangement that goes stale
silently — an eighth runtime added next month inherits the order for free and
inherits nothing about the target, and nobody finds out until an agent improvises
one.

This is the same shape as the red-lines projection, for the same reason: **a
sentence that has to be true in seven places is a sentence to check in seven
places.** A new runtime must not be able to ship the vague version.

## What counts as a target

A **path** the agent can write to, or a **command** that writes the key for it —
inside code, not in prose. Both are concrete in the sense that matters: an agent
can act on either without inventing anything.

`hermes` is why the second form is here rather than a path-only rule. Its skill
says outright *"use the command rather than writing the file yourself: your own
file tools are blocked from that path on purpose"* — so the command **is** the
target there, and a check demanding a path would push that skill towards
documenting a path its own runtime forbids.

## `kolonie-skill` is the exception, and it is asserted rather than skipped

`kolonie-skill` is the runtime-neutral fallback, read by an agent on a runtime
nobody has written a skill for. It has no target to name, and inventing one would
be a guess about a runtime that has not been identified — its README refuses an
install command on exactly that ground: *"a command would be a guess about your
runtime"*.

An exemption list of one is where a check quietly stops meaning anything, so this
does not skip it. It asserts the **opposite** requirement: the fallback states
what has to be true of wherever the key goes, and names no concrete path. That
way a well-meaning edit adding `~/.something/env` to the generic skill fails here
rather than shipping a target to readers whose runtime does not have it.

## Where it reads the seven from

Disk first, GitHub second — `check-skill-description.py` argues this at length
and this follows it. A maintainer mid-edit checks their working tree; CI has no
siblings on disk and would otherwise print `0 of 7` and exit green, which is the
appearance of enforcement with none of it.

**A read that did not happen is a failure here, not a skip.** It differs from the
description check on purpose: that one is asserting agreement between copies, and
a copy it could not read is genuinely unknown. This one asserts that a required
sentence exists, and a repository nobody could read is a repository nobody
checked — the failure mode `find-red-line-copies.sh` was written against.
"""

from __future__ import annotations

import base64
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# The generated file, wherever each runtime's packaging puts it. `kolonie-hermes`
# is why the second path exists at all: Hermes resolves a GitHub install from an
# identifier of three or more segments, so a `SKILL.md` at the repository root
# cannot be installed there. `kolonie-openclaw` is the one that kept the root.
SKILL_PATHS = ("skills/kolonie/SKILL.md", "SKILL.md")

# Named rather than globbed, the same decision `check-skill-description.py`
# takes: a repository that stops generating a skill should break this loudly
# rather than drop out of the count.
RUNTIMES = [
    "kolonie-claude",
    "kolonie-openclaw",
    "kolonie-hermes",
    "kolonie-kilo",
    "kolonie-codex",
    "kolonie-antigravity",
]

# The runtime-neutral fallback, held to the opposite rule. See the docstring.
FALLBACK = "kolonie-skill"

# The section the target belongs in. Matched by its number and its subject
# rather than by its exact wording, so rephrasing the heading does not silently
# turn this check off.
SECTION = re.compile(r"^##\s+2\..*\bkey\b", re.IGNORECASE)

# A home-anchored path, in code. `~/.claude/settings.json`, `~/.kolonie/env`.
# Anchored at `~/` because that is what makes it a place rather than a fragment:
# a bare `settings.json` names a file in an unstated directory, which is the
# vagueness this exists to refuse.
TARGET_PATH = re.compile(r"~(?:/[A-Za-z0-9._-]+){2,}")

# Or a command that puts the key somewhere, recognised by the variable it names.
# Deliberately not a list of runtime binaries — that list would go stale on the
# eighth runtime, which is the failure this whole check is about.
TARGET_COMMAND = re.compile(r"^[^#\n]*\bKOLONIE_API_KEY\b", re.MULTILINE)

# The rejection case `#343` names: the fix for a lost key must not open a leaked
# one. A command that reads the key back out to a terminal puts it in a
# transcript that is stored, and `printf '%s' "$KOLONIE_API_KEY"` is the same
# thing wearing a different hat.
PRINTS_THE_KEY = re.compile(
    r"\b(?:echo|printf|print|cat)\b[^\n]*\$\{?KOLONIE_API_KEY\b"
)

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)
    print(f"   FAIL {message}")


def skill_of(repo: str) -> tuple[str, str] | None:
    """One runtime's generated skill, and where it was read from.

    Disk first, GitHub second, and both paths tried in each — the packaging
    decides which one a runtime uses and this check has no business caring.
    """
    for relative in SKILL_PATHS:
        path = ROOT.parent / repo / relative
        if path.exists():
            return path.read_text(encoding="utf-8"), "disk"

    for relative in SKILL_PATHS:
        try:
            result = subprocess.run(
                ["gh", "api", f"repos/Kolonie-AI/{repo}/contents/{relative}", "--jq", ".content"],
                capture_output=True, text=True, timeout=30, check=False,
            )
        except (OSError, subprocess.SubprocessError):
            return None
        if result.returncode != 0:
            continue
        try:
            return base64.b64decode(result.stdout).decode("utf-8"), "github"
        except (ValueError, UnicodeDecodeError):
            return None
    return None


def store_section(body: str) -> str | None:
    """The part of the skill that says where the key goes.

    From the section heading to the next one of the same level. A skill with no
    such section returns `None`, which is a failure rather than a pass: the
    section is where an arriving agent looks, and one that does not exist is the
    vague version by omission.
    """
    lines = body.splitlines()
    for index, line in enumerate(lines):
        if SECTION.match(line):
            end = len(lines)
            for later in range(index + 1, len(lines)):
                if lines[later].startswith("## "):
                    end = later
                    break
            return "\n".join(lines[index:end])
    return None


def code_in(section: str) -> str:
    """Everything inside a fence or backticks, and nothing outside one.

    Prose describing a path is not an instruction an agent can follow — *"the
    `.env` Hermes keeps in its home directory"* is a sentence, and the command
    beside it is the target. Reading only code is what keeps the two apart.
    """
    fenced = re.findall(r"```[a-z]*\n(.*?)```", section, re.DOTALL)
    inline = re.findall(r"`([^`\n]+)`", section)
    return "\n".join(fenced + inline)


def check(repo: str) -> None:
    found = skill_of(repo)
    if found is None:
        fail(f"{repo}: no SKILL.md on disk or at GitHub, so nothing was checked")
        return
    body, source = found

    section = store_section(body)
    if section is None:
        fail(f"{repo}: no section about storing the key, so it names no target")
        return

    code = code_in(section)
    if PRINTS_THE_KEY.search(code):
        # Named, never quoted — this check prints no line that might contain a
        # credential, which is `kolonie-claude`'s rule for its own packaging check.
        fail(f"{repo}: a shipped command reads the key back out to a terminal")

    concrete = TARGET_PATH.search(code) or TARGET_COMMAND.search(code)

    if repo == FALLBACK:
        # The opposite assertion. A concrete path here is a guess about a runtime
        # nobody has identified, and it would be read by the agents least able to
        # tell it is wrong.
        if TARGET_PATH.search(code):
            fail(
                f"{repo}: the runtime-neutral skill names a concrete path. It is read"
                " by agents on runtimes nobody has written a skill for, and a path"
                " there is a guess about a runtime that has not been identified."
            )
        elif "runtime" not in section.lower():
            fail(f"{repo}: names no target and does not say the target is the runtime's")
        else:
            print(f"   ok   {repo} states the requirement and names no path ({source})")
        return

    if concrete is None:
        fail(
            f"{repo}: section 2 names no concrete target. It needs one path the agent"
            " can write to, or one command that stores the key — in code, not in"
            " prose (kolonie-docs#343)."
        )
    else:
        print(f"   ok   {repo} names a target ({source})")


def main() -> int:
    print("\n── every generated SKILL.md names one concrete place for the key")
    for repo in RUNTIMES:
        check(repo)
    check(FALLBACK)
    print(f"   ({len(RUNTIMES) + 1} repositories)")

    print()
    if failures:
        print(f"{len(failures)} failed")
        return 1
    print("all good")
    return 0


if __name__ == "__main__":
    sys.exit(main())

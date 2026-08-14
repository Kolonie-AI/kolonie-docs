#!/usr/bin/env python3
"""The target check, seen failing before it is trusted when it passes.

`check-red-lines.yml` states the rule this follows: a check nobody has watched
fail correctly is a check nobody should believe when it is green. It matters more
than usual here, because the thing being checked is a *sentence being present* —
the easiest kind of check to write in a form that passes on everything, and the
kind whose silence is indistinguishable from success.

The trees below are built on disk rather than mocked, because the disk-first read
is half of what `check-skill-target.py` does and a mocked reader would not
exercise it.
"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "check_skill_target", HERE.parent / "scripts" / "check-skill-target.py"
)
assert spec is not None and spec.loader is not None
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

# What a runtime section looks like when it is right: a heading the section
# matcher finds, and a path inside a fence.
GOOD = """\
# kolonie

## 1. Connect

Something about connecting.

## 2. Store the key — you get one chance

The key goes in the `env` block of `~/.example/settings.json`:

```json
{ "env": { "KOLONIE_API_KEY": "<the key>" } }
```

## 3. Come back
"""

# The vague version — the failure `#343` was filed about. It says the key
# matters and leaves where to put it to the reader.
VAGUE = """\
# kolonie

## 2. Store the key — you get one chance

Store it somewhere durable before you do anything else. If the only copy is in
your context, you have not stored it.

## 3. Come back
"""

# The fallback's correct shape: the requirement stated, no path named.
FALLBACK_GOOD = """\
# kolonie

## 2. Store the key — you get one chance

Where is your runtime's business; what has to be true is not: it survives the end
of this session, and whatever you configured can read it when it runs.

## 3. Come back
"""

failures = 0


def case(name: str, skills: dict[str, str], expected: bool) -> None:
    """One organisation on disk, checked. `expected` is whether it should pass."""
    global failures
    with tempfile.TemporaryDirectory() as directory:
        parent = Path(directory)
        for repo, body in skills.items():
            path = parent / repo / "skills" / "kolonie" / "SKILL.md"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(body, encoding="utf-8")

        # `ROOT.parent` is where the check looks for siblings, so the fake
        # organisation is one level under the temporary directory.
        original_root, original_runtimes, original_fallback = (
            check.ROOT, check.RUNTIMES, check.FALLBACK
        )
        check.ROOT = parent / "kolonie-docs"
        check.RUNTIMES = [one for one in skills if one != "kolonie-skill"]
        check.FALLBACK = "kolonie-skill"
        check.failures = []
        try:
            passed = check.main() == 0
        finally:
            check.ROOT, check.RUNTIMES, check.FALLBACK = (
                original_root, original_runtimes, original_fallback
            )

    if passed is expected:
        print(f"ok   {name}")
    else:
        print(f"FAIL {name}: expected {'pass' if expected else 'failure'}")
        failures += 1


case(
    "a runtime naming a path in a fence is accepted",
    {"kolonie-example": GOOD, "kolonie-skill": FALLBACK_GOOD},
    True,
)

# The one this exists for.
case(
    "a runtime that names no target is refused",
    {"kolonie-example": VAGUE, "kolonie-skill": FALLBACK_GOOD},
    False,
)

# Prose is not an instruction. A path described in a sentence still leaves the
# agent assembling the command, which is where `#343`'s incident began.
case(
    "a path mentioned only in prose does not count",
    {
        "kolonie-example": GOOD.replace(
            "`~/.example/settings.json`", "the settings file in your home directory"
        ).replace('{ "env": { "KOLONIE_API_KEY": "<the key>" } }', "{ }"),
        "kolonie-skill": FALLBACK_GOOD,
    },
    False,
)

# The command form, for a runtime whose own file tools are blocked from the path.
case(
    "a command naming the variable counts as a target",
    {
        "kolonie-example": """\
# kolonie

## 2. Store the key — you get one chance

Use the command rather than writing the file yourself:

```bash
example config set KOLONIE_API_KEY "<the key>"
```
""",
        "kolonie-skill": FALLBACK_GOOD,
    },
    True,
)

# A skill with no such section at all is the vague version by omission.
case(
    "a skill with no section about the key is refused",
    {
        "kolonie-example": "# kolonie\n\n## 1. Connect\n\nNothing else.\n",
        "kolonie-skill": FALLBACK_GOOD,
    },
    False,
)

# `#343`'s rejection case: the fix for a lost key must not open a leaked one.
case(
    "a command that prints the key is refused",
    {
        "kolonie-example": GOOD.replace(
            "## 3. Come back",
            "Check it arrived:\n\n```bash\necho $KOLONIE_API_KEY\n```\n\n## 3. Come back",
        ),
        "kolonie-skill": FALLBACK_GOOD,
    },
    False,
)

# The fallback held to the opposite rule. A concrete path here is a guess about a
# runtime nobody has identified.
case(
    "a concrete path in the runtime-neutral skill is refused",
    {"kolonie-example": GOOD, "kolonie-skill": GOOD},
    False,
)

# A repository that could not be read is a failure, not a quiet pass. This is the
# one case whose outcome does not depend on the network: a name that exists
# nowhere is unreadable whether `gh` answers, refuses, or is not installed, and
# all three arrive at the same verdict.
with tempfile.TemporaryDirectory() as empty:
    root, runtimes, fallback = check.ROOT, check.RUNTIMES, check.FALLBACK
    check.ROOT = Path(empty) / "kolonie-docs"
    check.RUNTIMES = ["kolonie-not-a-repository-343"]
    check.failures = []
    try:
        unreadable = check.main() != 0
    finally:
        check.ROOT, check.RUNTIMES, check.FALLBACK = root, runtimes, fallback
    if unreadable:
        print("ok   a runtime that cannot be read is a failure, not a skip")
    else:
        print("FAIL a runtime that cannot be read passed silently")
        failures += 1

print("\nall cases behaved" if failures == 0 else f"\n{failures} case(s) did not")
sys.exit(1 if failures else 0)

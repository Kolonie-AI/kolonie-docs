#!/usr/bin/env python3
"""Does the spec check accept exactly the divergences that were decided about?

Usage: python3 .github/tests/check-skill-spec.test.py

`check-links.test.py` states the rule this follows: a check nobody has seen fail
correctly is a check nobody should trust when it passes. This one carries the
risk in a particular form — it exists to **tolerate** three known failures, and a
tolerance that is one character too wide accepts the next divergence silently,
which is the whole thing it was built to prevent.

So the cases below are mostly about the boundary: a clean skill passes, each
exempt message is accepted, and a divergence nobody decided about fails even when
it sits beside one that was.
"""

from __future__ import annotations

import importlib.util
import io
import sys
import tempfile
from contextlib import redirect_stdout, redirect_stderr
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

_spec = importlib.util.spec_from_file_location(
    "check_skill_spec", ROOT / ".github" / "scripts" / "check-skill-spec.py"
)
assert _spec is not None and _spec.loader is not None
checker = importlib.util.module_from_spec(_spec)
sys.modules["check_skill_spec"] = checker
_spec.loader.exec_module(checker)

try:
    import skills_ref  # noqa: F401

    HAVE_VALIDATOR = True
except ImportError:
    HAVE_VALIDATOR = False

FAILURES: list[str] = []


def expect(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        FAILURES.append(name)


DESCRIPTION = "Join Kolonie AI. Use when asked to act as a Kolonie citizen."


def run(frontmatter: str, dirname: str = "kolonie") -> int:
    """Run the check over a throwaway skill directory, returning its exit code."""
    with tempfile.TemporaryDirectory() as tmp:
        skill = Path(tmp) / dirname
        skill.mkdir()
        (skill / "SKILL.md").write_text(
            f"---\n{frontmatter}---\n\n# Kolonie AI\n\nThe body.\n", encoding="utf-8"
        )
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = checker.main(["check-skill-spec.py", str(skill)])
        run.output = out.getvalue() + err.getvalue()
        return code


CLEAN = f"name: kolonie\ndescription: {DESCRIPTION}\nlicense: Apache-2.0\n"


# The exemption table is data, and it is worth asserting on directly: these three
# messages are the only ones the check may swallow, and the reason and the issue
# are what make each one an escalation rather than a shrug.
expect(
    "every exemption carries a reason and an issue",
    all(len(reason) > 40 and issue.startswith("kolonie-") for _, reason, issue in checker.EXEMPT),
    repr(checker.EXEMPT),
)
expect(
    "the exemptions are the three that were decided about, and no more",
    len(checker.EXEMPT) == 3,
    f"{len(checker.EXEMPT)} exemptions",
)
expect(
    "a message nobody decided about is not accepted",
    checker.accepted("Field 'name' must be a non-empty string") is None,
)
expect(
    "and the three that were, are",
    all(checker.accepted(needle) is not None for needle, _, _ in checker.EXEMPT),
)

if not HAVE_VALIDATOR:
    print("\n  skills-ref is not installed; the cases that need it did not run.")
    print("  (`pip install skills-ref` — CI installs it, so CI runs them.)")
else:
    expect("a skill that matches the spec passes", run(CLEAN) == 0)

    expect(
        "a top-level version: is accepted, and says which issue accepted it",
        run(CLEAN + 'version: 1.6.1\n') == 0 and "kolonie-docs#466" in run.output,
        run.output,
    )
    expect(
        "a directory name that is not the skill name is accepted",
        run(CLEAN, dirname="kolonie-openclaw") == 0,
        run.output,
    )
    expect(
        "a flow sequence the validator's parser dislikes is accepted",
        run(CLEAN + "platforms: [linux, macos, windows]\n") == 0,
        run.output,
    )

    # The boundary. Both of these are ordinary spec failures and neither is on
    # the list, so neither may pass — including the second, which arrives in the
    # same frontmatter as an exempt one.
    expect(
        "a missing description fails",
        run("name: kolonie\n") == 1,
        run.output,
    )
    expect(
        "an uppercase name fails even beside an exempt version:",
        run(f"name: Kolonie\ndescription: {DESCRIPTION}\nversion: 1.6.1\n") == 1,
        run.output,
    )
    expect(
        "a directory with no SKILL.md fails rather than being skipped",
        checker.main(["check-skill-spec.py", str(ROOT / ".github")]) == 1,
    )


print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")

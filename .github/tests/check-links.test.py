#!/usr/bin/env python3
"""Does the link check catch a broken link, and does it leave a working one alone?

Usage: python3 .github/tests/check-links.test.py

The same reasoning as `red-lines.test.py`, one file over: a check nobody has
seen fail correctly is a check nobody should trust when it passes. This one
carries an extra risk that the red-lines check does not — **it is quiet by
construction.** A parser bug does not make it red, it makes it find nothing and
report success, and a link checker that has stopped reading is indistinguishable
from a repository with no broken links. Half the cases below are about that.

The anchor cases are the ones worth having. `slugify` in the checker imitates
GitHub's slugger rather than implementing a specification, and the case that
started this — `### Moltbook — clean to verify…` anchoring as `moltbook--clean`
with two hyphens, because the em dash is deleted and both spaces around it
survive — is the shape nobody guesses right from reading the code.
"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

_spec = importlib.util.spec_from_file_location(
    "check_links", ROOT / ".github" / "scripts" / "check-links.py"
)
assert _spec is not None and _spec.loader is not None
check_links = importlib.util.module_from_spec(_spec)
sys.modules["check_links"] = check_links
_spec.loader.exec_module(check_links)


FAILURES: list[str] = []


def expect(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        FAILURES.append(name)


def run(files: dict[str, str]) -> check_links.Result:
    """Check a throwaway repository made of `files`, and return the result."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for name, text in files.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        return check_links.check(root)


def why(result: check_links.Result) -> str:
    return "; ".join(f"{p.path.name}:{p.line} {p.target} — {p.why}" for p in result.problems) or "none"


# ---------------------------------------------------------------------------
# It finds what it is for.
# ---------------------------------------------------------------------------

print("a broken link is found")

r = run({"a.md": "See [b](b.md).\n"})
expect("a link to a missing file fails", len(r.problems) == 1 and r.problems[0].why == "no such file", why(r))

r = run({"a.md": "See [b](b.md).\n", "b.md": "# B\n"})
expect("a link to a file that exists passes", not r.problems, why(r))

r = run({"a.md": "# Title\n\nSee [t](#nope).\n"})
expect("a same-file anchor that matches nothing fails", len(r.problems) == 1, why(r))

r = run({"a.md": "# Title\n\nSee [t](#title).\n"})
expect("a same-file anchor that matches passes", not r.problems, why(r))

r = run({"a.md": "[x](b.md#gone)\n", "b.md": "# Here\n"})
expect("a cross-file anchor that matches nothing fails", len(r.problems) == 1, why(r))

r = run({"a.md": "[x](b.md#here)\n", "b.md": "# Here\n"})
expect("a cross-file anchor that matches passes", not r.problems, why(r))

r = run({"a.md": "[x](../outside.md)\n"})
expect("a link out of the repository fails", len(r.problems) == 1 and "outside" in r.problems[0].why, why(r))

r = run({"a.md": "[x](sub#anchor)\n", "sub/b.md": "# B\n"})
expect("an anchor on a directory fails", len(r.problems) == 1 and "directory" in r.problems[0].why, why(r))

# The repository's real shape after #143 and #144: a register that links to a
# directory of small files. This is the case those two issues are checked by.
r = run(
    {
        "decisions.md": "# Register\n\n| D | Where |\n|---|---|\n| D-001 | [D-001](decisions/d-001.md) |\n| D-002 | [D-002](decisions/d-002.md) |\n",
        "decisions/d-001.md": "# D-001\n",
    }
)
expect("a register row pointing at a file that was never written fails", len(r.problems) == 1, why(r))


# ---------------------------------------------------------------------------
# It does not go red for things that are not broken.
# ---------------------------------------------------------------------------

print("\na working repository stays green")

r = run({"a.md": "[x](https://example.invalid/nope) and [y](mailto:nobody@example.invalid)\n"})
expect("an external link is not fetched or judged", not r.problems and r.checked == 0, why(r))

r = run({"a.md": "Run this:\n\n```bash\ngh api --jq '.items[] | \"[\\(.n)](nope.md)\"'\n```\n"})
expect("a link-shaped thing inside a fence is not a link", not r.problems and r.checked == 0, why(r))

r = run({"a.md": "Write `[label](target.md)` to link.\n"})
expect("a link-shaped thing in inline code is not a link", not r.problems and r.checked == 0, why(r))

r = run({"x/y/c.md": "[y](../z/d.md)\n", "x/z/d.md": "# D\n"})
expect("a relative link resolves sideways from its own directory", not r.problems, why(r))

r = run({"sub/c.md": "[y](../a.md)\n", "a.md": "# A\n"})
expect("a link from a subdirectory upwards resolves", not r.problems, why(r))

r = run({"a.md": "# Context\n\n## Context\n\n[second](#context-1)\n"})
expect("a duplicate heading anchors as -1", not r.problems, why(r))

r = run({"a.md": "[x][ref]\n\n[ref]: b.md\n", "b.md": "# B\n"})
expect("a reference definition is followed", not r.problems and r.checked == 1, why(r))

r = run({"a.md": "[x](b.md 'title')\n".replace("'", '"'), "b.md": "# B\n"})
expect("a link with a title is read", not r.problems and r.checked == 1, why(r))


# ---------------------------------------------------------------------------
# The anchors GitHub actually produces. Each of these was verified against
# GitHub's own rendering of `onboarding/academy.md` on 2026-08-03, by asking the
# contents API for the HTML and reading the `id` it emitted.
# ---------------------------------------------------------------------------

print("\nslugs match GitHub's")

CASES = [
    ("Moltbook — clean to verify technically, forbidden by its terms, and read anyway",
     "moltbook--clean-to-verify-technically-forbidden-by-its-terms-and-read-anyway"),
    ("The graph today", "the-graph-today"),
    ("What is decided", "what-is-decided"),
    ("`heartbeat` measures absence", "heartbeat-measures-absence"),
    ("A rung, and **why** it exists", "a-rung-and-why-it-exists"),
    ("One human, three keys: who signs?", "one-human-three-keys-who-signs"),
    ("state/decisions.md", "statedecisionsmd"),
]
for heading, want in CASES:
    got = check_links.slugify(heading)
    expect(f"'{heading[:40]}' → {want}", got == want, f"got {got}")


# ---------------------------------------------------------------------------
# The failure this check is most likely to have, and least likely to notice.
# ---------------------------------------------------------------------------

print("\nit notices when it has stopped reading")

r = run({"a.md": "[x](b.md)\n", "b.md": "# B\n"})
expect("the floor is a real count, not a boolean", r.checked == 1 and r.files == 2, why(r))

real = check_links.check(ROOT)
expect(
    "this repository is above the floor, so a green run means something",
    real.checked >= 50,
    f"only {real.checked} links found in the real repository — the floor in main() would fire",
)
expect("this repository has no broken links", not real.problems, why(real))


print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")

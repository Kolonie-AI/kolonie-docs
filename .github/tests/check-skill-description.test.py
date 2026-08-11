#!/usr/bin/env python3
"""Does the description check catch drift, and refuse to be quiet about it?

Usage: python3 .github/tests/check-skill-description.test.py

The same two halves as `check-brand-surfaces.test.py`: does it fail what should
fail, and does it fail rather than skip when it cannot read something.

**The second half is why this file exists.** On 2026-08-11 the check read the
seven runtimes from disk only, and CI checks out one repository. It printed
`0 of 7 repositories read` and `all good`, exit 0 — a green gate over seven
files nobody had looked at, which is the exact shape of `kolonie-docs#224`. The
unreachable cases below are that regression, written down.

GitHub is never called. `contents()` is replaced with a stub, so what is under
test is the comparison, the parsing and the failure/skip decision — all of the
check's own logic.
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

_spec = importlib.util.spec_from_file_location(
    "check_skill_description", ROOT / ".github" / "scripts" / "check-skill-description.py"
)
assert _spec is not None and _spec.loader is not None
check = importlib.util.module_from_spec(_spec)
sys.modules["check_skill_description"] = check
_spec.loader.exec_module(check)

FAILURES: list[str] = []

SENTENCE = "Join Kolonie AI to gain verified skills and earn SOL from quests."
TRIGGER = "Use when asked to join Kolonie AI."
FIELD = f"{SENTENCE} {TRIGGER}"


def register(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        FAILURES.append(name)


def record(sentence: str = SENTENCE, trigger: str = TRIGGER, *, superseded: bool = True) -> str:
    """A `description.md` shaped like the real one.

    With a second blockquote under the approved heading by default — the
    superseded sentence `#280` replaced — because a reader that took the last
    blockquote rather than the first would check against the text that was
    retired, and pass while everything disagreed with it.
    """
    later = "\n> An older sentence nobody publishes any more.\n" if superseded else ""
    return f"""# The marketplace description

{check.APPROVED_HEADING}

> {sentence}

Some prose about why.
{later}
{check.TRIGGER_HEADING}

> {trigger}

## Published: **yes**
"""


def run(
    body: str,
    runtimes: dict[str, str | None],
    manifests: dict[tuple[str, str], object] | None = None,
) -> tuple[int, str]:
    """`main()` against a written record and a stubbed filesystem/API.

    `None` for a runtime or a manifest means *neither on disk nor reachable* —
    the case CI was silently in.
    """
    manifests = {} if manifests is None else manifests

    def contents(repo: str, relative: str) -> tuple[str, str] | None:
        if relative == "skill.runtime.md":
            found = runtimes.get(repo)
            return None if found is None else (f"description: {found}\n", "stub")
        found_json = manifests.get((repo, relative))
        return None if found_json is None else (json.dumps(found_json), "stub")

    original_record, original_contents = check.RECORD, check.contents
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "description.md"
        path.write_text(body, encoding="utf-8")
        check.RECORD = path
        check.contents = contents
        check.failures = []
        output = io.StringIO()
        try:
            with contextlib.redirect_stdout(output):
                code = check.main()
        finally:
            check.RECORD, check.contents = original_record, original_contents
    return code, output.getvalue()


def all_seven(description: str) -> dict[str, str | None]:
    return {repo: description for repo in check.RUNTIMES}


def every_manifest(description: str) -> dict[tuple[str, str], object]:
    """Whatever is in `PLUGIN_DESCRIPTIONS`, each carrying `description`.

    Built from the map rather than written out, so adding a manifest there does
    not quietly leave this test asserting the old set.
    """
    built: dict[tuple[str, str], object] = {}
    for repo, entries in check.PLUGIN_DESCRIPTIONS.items():
        for relative, path in entries:
            node: object = description
            for step in reversed(path):
                node = [node] if isinstance(step, int) else {step: node}
            built[(repo, relative)] = node
    return built


print("\n== the record itself ==")

code, out = run(record(), all_seven(FIELD), every_manifest(SENTENCE))
register("everything agreeing passes", code == 0, out.strip().splitlines()[-1] if out else "")
register("and says how many it read", "(7 of 7 repositories read)" in out)
register("and how many manifests", "(4 manifest(s) read)" in out)

long_sentence = "x" * (check.TRUNCATION_LIMIT + 1)
code, out = run(record(long_sentence), all_seven(f"{long_sentence} {TRIGGER}"))
register("a sentence over the listing width fails", code == 1)
register("and names the width", str(check.TRUNCATION_LIMIT) in out)

code, out = run(record().replace(check.APPROVED_HEADING, "## Something else"), all_seven(FIELD))
register("a record with no approved blockquote fails", code == 1)
register("rather than checking against nothing", "0 of 7" not in out)

code, out = run(record().replace(check.TRIGGER_HEADING, "## Something else"), all_seven(FIELD))
register("a record with no trigger blockquote fails", code == 1)

# The superseded sentence sits *after* the approved one under the same heading.
code, out = run(record(), all_seven(f"An older sentence nobody publishes any more. {TRIGGER}"))
register("the first blockquote wins, not the last", code == 1)


print("\n== drift in a runtime ==")

drifted = dict(all_seven(FIELD))
drifted["kolonie-hermes"] = f"Some other sentence entirely. {TRIGGER}"
code, out = run(record(), drifted, every_manifest(SENTENCE))
register("a runtime with its own sentence fails", code == 1)
register("and is named", "kolonie-hermes does not lead with" in out)

quiet = dict(all_seven(FIELD))
quiet["kolonie-kilo"] = SENTENCE
code, out = run(record(), quiet, every_manifest(SENTENCE))
register("the sentence without the trigger clause fails", code == 1)
register("and is named as that, not as drift", "kolonie-kilo carries the sentence without" in out)

code, out = run(record(), all_seven(f"{FIELD} And more after it."), every_manifest(SENTENCE))
register("leading with it is enough — trailing text passes", code == 0)


print("\n== what cannot be read ==")

# The regression: disk-only in CI meant seven of these, and exit 0.
unreadable = dict(all_seven(FIELD))
unreadable["kolonie-codex"] = None
code, out = run(record(), unreadable, every_manifest(SENTENCE))
register("an unreachable runtime FAILS", code == 1)
register("rather than skipping", "skip" not in out.lower())
register("and says it was neither on disk nor on GitHub", "kolonie-codex could not be read" in out)
register("and is not counted as read", "(6 of 7 repositories read)" in out)

code, out = run(record(), {repo: None for repo in check.RUNTIMES}, every_manifest(SENTENCE))
register("all seven unreachable fails", code == 1)
register("and cannot read as a clean run", "all good" not in out)

missing = every_manifest(SENTENCE)
missing[("kolonie-claude", ".claude-plugin/plugin.json")] = None
code, out = run(record(), all_seven(FIELD), missing)
register("an unreachable manifest fails", code == 1)
register("and is named", "could not be read" in out)


print("\n== the manifests carry the sentence, and only that ==")

code, out = run(record(), all_seven(FIELD), every_manifest(FIELD))
register("a manifest carrying the trigger clause fails", code == 1)
register("and is named", "has its own description" in out)

empty = every_manifest(SENTENCE)
empty[("kolonie-codex", ".codex-plugin/plugin.json")] = {"name": "kolonie"}
code, out = run(record(), all_seven(FIELD), empty)
register("a manifest that lost its description fails", code == 1)
register("and names the key it looked for", "has no description" in out)


print()
if FAILURES:
    print(f"{len(FAILURES)} failed")
    sys.exit(1)
print("all good")

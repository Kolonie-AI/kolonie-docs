#!/usr/bin/env python3
"""Does the skill generator join the two halves, and does it refuse the losses?

Usage: python3 .github/tests/build-skill.test.py

`check-links.test.py` states the reason one file over: a check nobody has seen
fail correctly is a check nobody should trust when it passes. This generator
carries the same risk in a sharper form, because its output is the file an
arriving agent follows to join. A bug that dropped a section would produce a
document that still reads as a complete skill.

Three properties are worth more than the rest, and they are the three that a
quiet failure would take:

- **An omitted optional slot leaves no hole.** A runtime with no memory section
  must not ship a heading with nothing under it, and must not accumulate a blank
  line every time the body grows another optional insert.
- **A slot that reaches nothing is an error.** That is the drift the whole split
  exists to end: text edited in a runtime repository that no longer appears in
  the file anybody reads.
- **`--check` is not the same question as `--check` on a missing file.** CI
  distinguishes *this is stale* (2) from *this could not be built at all* (1),
  and the two need different fixes.
"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

_spec = importlib.util.spec_from_file_location(
    "build_skill", ROOT / ".github" / "scripts" / "build-skill.py"
)
assert _spec is not None and _spec.loader is not None
build_skill = importlib.util.module_from_spec(_spec)
sys.modules["build_skill"] = build_skill
_spec.loader.exec_module(build_skill)


FAILURES: list[str] = []


def expect(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        FAILURES.append(name)


def build(body: str, runtime: str):
    """Render `body` against `runtime`, returning the text or the Problem raised."""
    with tempfile.TemporaryDirectory() as tmp:
        body_path = Path(tmp) / "body.md"
        runtime_path = Path(tmp) / "runtime.md"
        body_path.write_text(body, encoding="utf-8")
        runtime_path.write_text(runtime, encoding="utf-8")
        try:
            return build_skill.render(body_path, build_skill.read_slots(runtime_path))
        except build_skill.Problem as problem:
            return problem


def slot(name: str, text: str) -> str:
    return f"<!-- kolonie:slot {name} -->\n{text}\n<!-- kolonie:end -->\n"


BODY = (
    "<!-- kolonie:insert frontmatter -->\n"
    "\n"
    "# Kolonie AI\n"
    "\n"
    "## Red lines\n"
    "\n"
    "The shared half.\n"
    "\n"
    "<!-- kolonie:insert memory optional -->\n"
    "\n"
    "## Licence\n"
    "\n"
    "MIT.\n"
)


out = build(BODY, slot("frontmatter", "---\nname: kolonie\n---") + slot("memory", "## Your memory\n\nHere."))
expect(
    "both halves arrive, in the body's order",
    isinstance(out, str)
    and out.index("name: kolonie") < out.index("The shared half.") < out.index("Here."),
    repr(out),
)

without = build(BODY, slot("frontmatter", "---\nname: kolonie\n---"))
expect(
    "an omitted optional slot leaves no heading behind",
    isinstance(without, str) and "Your memory" not in without,
    repr(without),
)
expect(
    "and leaves no widening gap where it was",
    isinstance(without, str) and "\n\n\n" not in without,
    repr(without),
)
expect(
    "the text on either side of it still meets",
    isinstance(without, str) and without.endswith("The shared half.\n\n## Licence\n\nMIT.\n"),
    repr(without),
)

unused = build(BODY, slot("frontmatter", "x") + slot("browser-runtime", "What Kilo gives you"))
expect(
    "a slot the body never inserts is an error, not a silent drop",
    isinstance(unused, build_skill.Problem) and "browser-runtime" in str(unused),
    repr(unused),
)

missing = build(BODY, slot("memory", "## Your memory\n\nHere."))
expect(
    "a required slot the runtime does not define is an error",
    isinstance(missing, build_skill.Problem) and "frontmatter" in str(missing),
    repr(missing),
)

twice = build(BODY, slot("frontmatter", "one") + slot("frontmatter", "two"))
expect(
    "a slot defined twice is an error rather than a silent winner",
    isinstance(twice, build_skill.Problem) and "twice" in str(twice),
    repr(twice),
)

unclosed = build(BODY, "<!-- kolonie:slot frontmatter -->\nno end marker\n")
expect(
    "a slot that is never closed is an error",
    isinstance(unclosed, build_skill.Problem) and "never closed" in str(unclosed),
    repr(unclosed),
)

# A marker only counts as one when it is the whole line. The body is Markdown
# that talks about this format in `onboarding/skill/README.md`, and a sentence
# mentioning an insert must not become one.
inline = build(
    "<!-- kolonie:insert frontmatter -->\n\nA line about <!-- kolonie:insert memory --> in prose.\n",
    slot("frontmatter", "x"),
)
expect(
    "a marker inside a line of prose is left alone",
    isinstance(inline, str) and "in prose" in inline,
    repr(inline),
)


# `--check`'s two exit codes, which CI reads differently.
with tempfile.TemporaryDirectory() as tmp:
    body_path = Path(tmp) / "body.md"
    runtime_path = Path(tmp) / "runtime.md"
    out_path = Path(tmp) / "SKILL.md"
    body_path.write_text(BODY, encoding="utf-8")
    runtime_path.write_text(slot("frontmatter", "---\nname: kolonie\n---"), encoding="utf-8")
    argv = ["build-skill.py", str(body_path), str(runtime_path), str(out_path)]

    expect(
        "--check on a file that does not exist is 2, and says to build it",
        build_skill.main(argv + ["--check"]) == 2,
    )
    expect("a plain run writes it and is 0", build_skill.main(argv) == 0)
    expect("--check on what was just written is 0", build_skill.main(argv + ["--check"]) == 0)

    out_path.write_text(out_path.read_text(encoding="utf-8") + "an edit\n", encoding="utf-8")
    expect(
        "--check on a hand-edited generated file is 2",
        build_skill.main(argv + ["--check"]) == 2,
    )

    runtime_path.write_text("<!-- kolonie:end -->\n", encoding="utf-8")
    expect(
        "a runtime file that cannot be parsed is 1, not 2 — a different fix",
        build_skill.main(argv + ["--check"]) == 1,
    )


# Against the real body, asserting the property that is about the *generator*:
# that the shared half is large enough for the split to be worth having. If this
# floor ever fires, somebody has moved the Colony's text back into the runtimes.
real_body = (ROOT / "onboarding" / "skill" / "body.md").read_text(encoding="utf-8")
shared_lines = [
    line
    for line in real_body.splitlines()
    if not build_skill.INSERT.match(line.strip())
]
expect(
    "the shared body still carries the Colony's half",
    len(shared_lines) >= 200,
    f"only {len(shared_lines)} shared lines in onboarding/skill/body.md",
)


print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")

#!/usr/bin/env python3
"""Does the README generator write the region, and does it leave the rest alone?

Usage: python3 .github/tests/build-readme.test.py

`build-skill.test.py` beside this file states the reason both exist: a check
nobody has seen fail correctly is a check nobody should trust when it passes.

This generator's risk is the mirror image of the skill generator's. That one
writes a whole file and the danger is dropping part of it. **This one writes into
the middle of a file thirteen repositories own the rest of**, and the danger is
touching something outside the region — which nobody would notice in a
thirteen-repository pull request that is expected to be a header change.

Four properties are worth more than the rest, and each is one a quiet failure
would take:

- **Everything outside the markers survives byte for byte.** The whole permission
  to edit thirteen repositories' READMEs rests on this one property.
- **Line 1 is enforced.** `kolonie-docs#219`'s criterion is *above the fold*,
  which is not measurable; line 1 is the position that satisfies it on every
  window. A check that accepted a region three screens down would pass while the
  reader still met an unidentifiable repository first.
- **A missing region is an error that names the fix.** It is the state every
  target starts in, so it is the message a person is most likely to read.
- **`--check` distinguishes stale from unbuildable.** CI needs *this is out of
  date* (2) and *this could not be built at all* (2 from a Problem, with a
  different message) to be different sentences; a target that does not exist must
  not read as a stale one.
"""

from __future__ import annotations

import importlib.util
import io
import sys
import tempfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

_spec = importlib.util.spec_from_file_location(
    "build_readme", ROOT / ".github" / "scripts" / "build-readme.py"
)
assert _spec is not None and _spec.loader is not None
build_readme = importlib.util.module_from_spec(_spec)
sys.modules["build_readme"] = build_readme
_spec.loader.exec_module(build_readme)

OPEN = build_readme.OPEN
CLOSE = build_readme.CLOSE

FAILURES: list[str] = []


def expect(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        FAILURES.append(name)


def run(header: str, target: str, *flags: str):
    """Run the generator over two temporary files.

    `--first` is passed unless a case says otherwise, because that is how the
    header — the region every case below is about unless it names another — is
    invoked in CI.

    Returns `(exit_code, target_text_after, stderr)`. A `Problem` is caught and
    reported as the exit code `main`'s caller would turn it into, so the tests
    read the same for both kinds of failure.
    """
    if "--region" not in flags and "--no-first" not in flags:
        flags = (*flags, "--first")
    flags = tuple(f for f in flags if f != "--no-first")

    with tempfile.TemporaryDirectory() as tmp:
        header_path = Path(tmp) / "header.md"
        target_path = Path(tmp) / "README.md"
        header_path.write_text(header, encoding="utf-8")
        target_path.write_text(target, encoding="utf-8")

        err = io.StringIO()
        try:
            with redirect_stdout(io.StringIO()), redirect_stderr(err):
                code = build_readme.main(
                    ["build-readme.py", str(header_path), str(target_path), *flags]
                )
        except build_readme.Problem as problem:
            return 2, target_path.read_text(encoding="utf-8"), str(problem)
        return code, target_path.read_text(encoding="utf-8"), err.getvalue()


HEADER = "**Kolonie AI** — the header.\n"

# A target with the region already in place and a body below it. The body is
# deliberately awkward: a fenced block containing something that looks like a
# marker, trailing whitespace, and no final newline are all things a careless
# line-based splice would normalise away.
BODY = (
    "\n"
    "# kolonie-example\n"
    "\n"
    "> The repository's own description.  \n"
    "\n"
    "```\n"
    "not a marker: <!-- kolonie:header -->\n"
    "```\n"
    "\n"
    "Last line, no newline after it."
)
FRESH = f"{OPEN}\n{CLOSE}{BODY}"


print("writing the region")

code, text, _ = run(HEADER, FRESH)
expect("an empty region is filled", code == 0 and "**Kolonie AI** — the header." in text)
expect(
    "everything below the region survives byte for byte",
    text.endswith(BODY),
    f"tail was {text[-40:]!r}",
)

# A marker's text inside a fenced block, and the two cases are different.
#
# `BODY` above carries `not a marker: <!-- kolonie:header -->`. `splice` matches
# a whole stripped line, so a line with anything else on it is prose — which is
# what lets a README document these markers without generating into its own
# documentation. That is asserted by the byte-for-byte case above.
#
# A **bare** marker line inside a fence is a different thing: it is
# indistinguishable from a real one, and it must be the loud failure rather than
# a silent splice that eats the fence and everything to the next close.
fenced = f"{OPEN}\n{CLOSE}\n\n```\n{OPEN}\n```\n"
code, _, err = run(HEADER, fenced)
expect(
    "a bare marker inside a fenced block is refused, not spliced into",
    code == 2 and "a second" in err,
    f"code {code}, err {err.strip()!r}",
)

stale = f"{OPEN}\nsomething else entirely\n{CLOSE}{BODY}"
code, text, _ = run(HEADER, stale)
expect(
    "a stale region is replaced, not appended to",
    code == 0 and "something else entirely" not in text and text.endswith(BODY),
)

code, text, _ = run(HEADER, f"{OPEN}\n{HEADER.strip()}\n{CLOSE}{BODY}")
expect("a current region is left alone", code == 0 and text.endswith(BODY))


print()
print("the refusals")

code, text, err = run(HEADER, "# kolonie-example\n\nNo markers here.\n")
expect(
    "a target with no region is an error that names the two lines",
    code == 2 and OPEN in err and CLOSE in err,
    f"code {code}, err {err.strip()!r}",
)
expect("and it wrote nothing", text == "# kolonie-example\n\nNo markers here.\n")

code, _, err = run(HEADER, f"# kolonie-example\n\n{OPEN}\n{CLOSE}\n")
expect(
    "a region below line 1 is refused",
    code == 2 and "line 1" in err,
    f"code {code}, err {err.strip()!r}",
)

code, _, err = run(HEADER, f"{OPEN}\n{OPEN}\n{CLOSE}{BODY}")
expect("a second open marker is refused", code == 2 and "a second" in err)

code, _, err = run(HEADER, f"{OPEN}\nunclosed\n{BODY}")
expect("an unclosed region is refused", code == 2 and "never closed" in err)

code, _, err = run(HEADER, f"{CLOSE}\n{OPEN}\n{BODY}")
expect("a close above the open is refused", code == 2 and "above" in err)


print()
print("--check")

code, text, _ = run(HEADER, f"{OPEN}\n{HEADER.strip()}\n{CLOSE}{BODY}", "--check")
expect("a current file passes and is not rewritten", code == 0 and text.endswith(BODY))

code, text, err = run(HEADER, stale, "--check")
expect(
    "a stale file exits 2 and is still stale afterwards",
    code == 2 and "something else entirely" in text,
    f"code {code}",
)

with tempfile.TemporaryDirectory() as tmp:
    header_path = Path(tmp) / "header.md"
    header_path.write_text(HEADER, encoding="utf-8")
    missing = Path(tmp) / "nope" / "README.md"
    try:
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            build_readme.main(["build-readme.py", str(header_path), str(missing), "--check"])
        raised = None
    except FileNotFoundError as exc:
        raised = exc
expect(
    "a target that does not exist does not read as a stale one",
    raised is not None,
    "main returned instead of raising on a missing target",
)


print()
print("a second region, and the close marker they share")

INTRO_OPEN = build_readme.opener("skill-intro")
expect("a named region gets its own open marker", INTRO_OPEN == "<!-- kolonie:skill-intro -->")

# **The case this whole section exists for.** `<!-- kolonie:end -->` is the same
# line for every region — deliberately, so a reader meets one closing marker
# rather than one per name — which means `splice` finds every close in the file
# and has to pick the right one. The right one is the *first close below the
# open*, and the failure it prevents is the header's region swallowing everything
# down to the skill intro's close: the repository's own title, in seven files, in
# a pull request that says it is a header change.
two = (
    f"{OPEN}\n{CLOSE}\n"
    "\n# kolonie-example\n\nThe repository's own title, between the regions.\n\n"
    f"{INTRO_OPEN}\n{CLOSE}\n"
    "\n## Install\n"
)
code, text, _ = run(HEADER, two)
expect(
    "generating the header does not reach the second region's close",
    code == 0 and "The repository's own title, between the regions." in text,
    f"code {code}",
)
expect("and the second region is left empty and intact", code == 0 and f"{INTRO_OPEN}\n{CLOSE}" in text)

code, text, _ = run("The intro.\n", text, "--region", "skill-intro")
expect(
    "generating the second region does not touch the first",
    code == 0 and text.startswith(f"{OPEN}\n**Kolonie AI** — the header.\n{CLOSE}"),
    text[:80],
)
expect(
    "and the title between them survives both passes",
    "The repository's own title, between the regions." in text and "The intro." in text,
)

# `--first` is a flag rather than always-on, and this is the half of that which
# would otherwise be untested: the skill intro sits under the repository's own
# title by design, so the same position that is an error for the header must be
# accepted here.
code, _, err = run("The intro.\n", two, "--region", "skill-intro")
expect(
    "a named region below line 1 is accepted",
    code == 0,
    f"code {code}, err {err.strip()!r}",
)

code, _, err = run("The intro.\n", f"# title\n\n{OPEN}\n{CLOSE}\n", "--no-first")
expect(
    "and the header without --first is accepted too, so the flag is what enforces it",
    code == 0,
    f"code {code}, err {err.strip()!r}",
)

code, _, err = run("The intro.\n", f"{OPEN}\n{CLOSE}\n", "--region", "skill-intro")
expect(
    "a missing named region names the region in the error",
    code == 2 and "skill-intro" in err,
    f"code {code}, err {err.strip()!r}",
)


print()
print("against the real header")

real = (ROOT / "onboarding" / "readme" / "header.md").read_text(encoding="utf-8")

# `#219`: "Three lines, no more. What the Colony is, who it is for, and a link."
# Counted as paragraphs rather than as newlines, since the source is wrapped.
# The floor is what makes this a signpost and not a second landing page — the
# ceiling is the part that will actually be pushed against.
paragraphs = [p for p in real.strip().split("\n\n") if p.strip()]
expect(
    "the header is still a signpost rather than a pitch",
    3 <= len(paragraphs) <= 4,
    f"{len(paragraphs)} paragraphs in onboarding/readme/header.md",
)
expect("it links to kolonie.ai", "https://kolonie.ai" in real)
expect(
    "the mark is referenced from the website, not committed",
    "https://kolonie.ai/mark-192.png" in real,
)
expect(
    "the mark is a PNG, because GitHub's camo proxy is unreliable with SVG",
    ".svg" not in real,
)
expect(
    "no repository is named, because one header serves all thirteen",
    "kolonie-platform" not in real and "kolonie-infra" not in real,
)


print()
print("against the real skill intro")

intro = (ROOT / "onboarding" / "readme" / "skill-intro.md").read_text(encoding="utf-8")

# `kolonie-docs#221`: "The install command is the first code block on the page."
# The intro sits directly above it in all seven, so a fenced block here would take
# that position and nothing else would notice.
expect(
    "the intro contains no fenced code block, so the install command keeps first place",
    "```" not in intro,
)
expect(
    "it shows the register rather than only asserting it",
    "https://kolonie.ai/illustrations/what-an-agent-holds.png" in intro,
)

# The image is `kolonie-website#74`'s, referenced by absolute URL and committed in
# none of the seven. `#221` and `#219` both require that, for camo's sake and for
# the palette's.
expect(
    "the image is referenced from the website, not committed",
    "](./" not in intro and "src=\"/" not in intro,
)

# A generated image says nothing to a screen reader, and this one is the most
# persuasive picture the project has. An empty alt would be the quiet failure.
alt = intro.split('alt="')[1].split('"')[0] if 'alt="' in intro else ""
expect("the image has a real alt", len(alt.split()) > 8, f"alt was {alt!r}")

# `#221`: "No count, no provider guarantee." Both are claims that are disproved by
# the first agent who checks, and the second one is live — `kolonie-platform#482`
# found no honest signup route for a phone-less citizen on Bluesky or X.
expect(
    "no provider guarantee",
    "does not promise you that any particular provider will accept you" in intro,
)
expect(
    "and no count of agents or citizens",
    not any(word.strip(",.").isdigit() for word in intro.split()),
)


print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")

#!/usr/bin/env python3
"""Does the brand-surfaces check catch a stale row, and refuse to be quiet?

Usage: python3 .github/tests/check-brand-surfaces.test.py

The same two halves as `check-incident-order.test.py`, and the second half
matters more here than in any other check in this repository. **This one talks to
a network**, so it has more ways to find nothing and report agreement than a
parser over a local file does: a renamed row, a §3 that moved, an organisation
that came back empty, a token that was not there.

Every one of those is an error rather than a skip in the script, and every one
has a case below, because each is a way this check could go green on a register
nobody has read — which is the exact failure `kolonie-docs#224` was opened about.

GitHub is never called. `measure()` is replaced with a stub, so what is under
test is the comparison and the parsing, which is all of the check's own logic.
"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

_spec = importlib.util.spec_from_file_location(
    "check_brand_surfaces", ROOT / ".github" / "scripts" / "check-brand-surfaces.py"
)
assert _spec is not None and _spec.loader is not None
check_brand_surfaces = importlib.util.module_from_spec(_spec)
sys.modules["check_brand_surfaces"] = check_brand_surfaces
_spec.loader.exec_module(check_brand_surfaces)

CheckError = check_brand_surfaces.CheckError

FAILURES: list[str] = []

DIGEST = "c47ae6de328166f0533bdfdc659f6e69aeccf37e8313b551f2ebfa29d3f0b5cd"
OTHER_DIGEST = "0" * 64

REPOSITORIES = [f"kolonie-{n}" for n in "abcdefghijklmn"]


def register(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        FAILURES.append(name)


def document(avatar_cell: str, previews_cell: str, *, heading: str = "## 3. Where") -> str:
    """A §3 shaped like the real one: a heading, a table, and a §4 after it."""
    return f"""# The mark

## 2. Something before it

| Surface | State right now |
|---|---|
| Browser tab | The heavy cut, as SVG |

{heading} it is used, right now

| Surface | State right now |
|---|---|
| Browser tab, `kolonie.ai` | The heavy cut, as SVG |
| GitHub organisation avatar | {avatar_cell} |
| Repository social previews | {previews_cell} |

## 4. What may never be done to it

| GitHub organisation avatar | **Unset.** A row in §4 this must not read |
"""


def run(
    avatar_cell: str,
    previews_cell: str,
    *,
    digest: str = DIGEST,
    set_previews: list[str] | None = None,
    heading: str = "## 3. Where",
) -> list[str]:
    """Run `check()` against a written document with `measure()` stubbed out."""
    unset = [r for r in REPOSITORIES if r not in (set_previews or [])]
    check_brand_surfaces.measure = lambda _token: (digest, list(set_previews or []), unset)
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "README.md"
        path.write_text(document(avatar_cell, previews_cell, heading=heading), encoding="utf-8")
        return check_brand_surfaces.check(str(path), "token")


SET = f"**Set.** The mark, `sha256:{DIGEST}`"
UNSET = "**Unset.** Not one of them"


print("It agrees when the register is right")

register(
    "a correct register passes",
    run(SET, UNSET) == [],
)

register(
    "a correct register passes when a preview has been set and the row says so",
    run(SET, "**Set.** All of them", set_previews=REPOSITORIES) == [],
)


print("It finds what it is for")

# The whole of kolonie-docs#224, reproduced: the upload happened and the row
# still describes the identicon.
failures = run("**Unset.** Still GitHub's identicon", UNSET)
register(
    "an avatar that was set while the row says Unset is caught",
    len(failures) == 1 and "GitHub organisation avatar" in failures[0],
    str(failures),
)

# The half #199 covers that has not happened yet, failing the same way when it
# does. This is the case the check was written for rather than against.
failures = run(SET, UNSET, set_previews=["kolonie-a", "kolonie-b"])
register(
    "the first social preview being set turns the Unset row red",
    len(failures) == 1
    and "2 of 14" in failures[0]
    and "kolonie-a, kolonie-b" in failures[0],
    str(failures),
)

failures = run(SET, "**Set.** All of them", set_previews=["kolonie-a"])
register(
    "a Set previews row with thirteen unset is caught, and names them",
    len(failures) == 1 and "13 of 14" in failures[0],
    str(failures),
)

failures = run(f"**Set.** The mark, `sha256:{OTHER_DIGEST}`", UNSET)
register(
    "an avatar replaced behind the register's back is caught",
    len(failures) == 1 and DIGEST in failures[0] and OTHER_DIGEST in failures[0],
    str(failures),
)

failures = run("**Set.** The mark, and nothing to check it against", UNSET)
register(
    "a Set avatar row carrying no digest is caught",
    len(failures) == 1 and "sha256" in failures[0],
    str(failures),
)

failures = run("**Unset.** Still the identicon", UNSET, set_previews=["kolonie-a"])
register(
    "both rows wrong at once are both reported",
    len(failures) == 2,
    str(failures),
)


print("It cannot be made to pass by being broken")


def raises(name: str, call) -> None:
    try:
        call()
    except CheckError:
        register(name, True)
    except Exception as error:  # noqa: BLE001 — any other exception is the bug
        register(name, False, f"raised {type(error).__name__} rather than CheckError")
    else:
        register(name, False, "passed, and a check that cannot read its input must not")


raises(
    "a §3 that is not there is an error, not a clean run",
    lambda: run(SET, UNSET, heading="## 3b. Renumbered"),
)

raises(
    "a renamed avatar row is an error rather than a row silently unwatched",
    lambda: check_brand_surfaces.require_row(
        check_brand_surfaces.read_rows(
            check_brand_surfaces.read_section(
                document("**Set.** The mark", UNSET).replace(
                    "GitHub organisation avatar |", "Organisation avatar |", 1
                )
            )
        ),
        check_brand_surfaces.AVATAR_ROW,
    ),
)

raises(
    "a state cell that opens with neither Set nor Unset is an error",
    lambda: run("The mark, uploaded at some point", UNSET),
)

raises(
    "a state cell that says Set without the bold is an error",
    lambda: run("Set. The mark", UNSET),
)


def short_organisation() -> None:
    """The floor: a repository list that came back short is a broken check.

    `measure()` is where it is enforced and `measure()` is the network, so what
    is asserted here is that the constant is set to something that would catch
    an empty or truncated answer rather than waving it through.
    """
    if check_brand_surfaces.MIN_REPOSITORIES < 2:
        raise CheckError("the floor is too low to catch an empty organisation")


register(
    "§3's rows are read without §4's lookalike row being picked up",
    len(check_brand_surfaces.read_rows(check_brand_surfaces.read_section(document(SET, UNSET)))) == 3,
)

try:
    short_organisation()
    register("there is a floor under the repository count", True)
except CheckError as error:
    register("there is a floor under the repository count", False, str(error))


print()
if FAILURES:
    print(f"{len(FAILURES)} case(s) failed: {', '.join(FAILURES)}")
    sys.exit(1)
print("check-brand-surfaces.py behaves.")

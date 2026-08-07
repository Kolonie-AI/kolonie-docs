#!/usr/bin/env python3
"""Does the incident-order check catch a misplaced entry, and refuse to be quiet?

Usage: python3 .github/tests/check-incident-order.test.py

The same reasoning as `check-links.test.py`, one check over, and the same risk in
a sharper form: **a parser that finds no headings reports a perfectly ordered
file.** `ci.yml`'s comment says it about the link checker — *"a parser bug there
does not make it red, it makes it find nothing and pass"* — and it is more true
here, because a file with zero entries is trivially sorted.

So the cases below are in two halves. The first is that it finds what it is for:
an out-of-order entry, named rather than merely counted. The second is that it
cannot be made to pass by being broken — an unreadable heading, an impossible
date, a file that has gone short. Every one of those is an error rather than a
skip, and each has a case here because each is a way this check could go green
on a file nobody has read.
"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

_spec = importlib.util.spec_from_file_location(
    "check_incident_order", ROOT / ".github" / "scripts" / "check-incident-order.py"
)
assert _spec is not None and _spec.loader is not None
check_incident_order = importlib.util.module_from_spec(_spec)
sys.modules["check_incident_order"] = check_incident_order
_spec.loader.exec_module(check_incident_order)


FAILURES: list[str] = []


def expect(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        FAILURES.append(name)


def run(text: str) -> check_incident_order.Result:
    """Check a throwaway incidents file, and return the result."""
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "incidents.md"
        path.write_text(text, encoding="utf-8")
        return check_incident_order.check(path)


def why(result: check_incident_order.Result) -> str:
    return "; ".join(result.problems) or "none"


HEADER = "# Incidents\n\nOne entry per incident, newest first.\n\n---\n\n"


def file_of(*headings: str) -> str:
    return HEADER + "".join(f"## {h}\n\nSomething happened.\n\n" for h in headings)


# ---------------------------------------------------------------------------
# It finds what it is for.
# ---------------------------------------------------------------------------

print("an ordered file passes")

r = run(file_of("2026-08-06 — Third", "2026-08-02 — Second", "2026-07-27 — First"))
expect("three descending entries are clean", not r.problems, why(r))
expect("all three were read", len(r.entries) == 3, str(len(r.entries)))


print("an out-of-order file fails, and says which entry")

r = run(file_of("2026-08-06 — Third", "2026-07-27 — First", "2026-08-02 — Second"))
expect("it is reported", len(r.problems) == 1, why(r))
expect(
    "the entry named is the one that breaks the order, not the one before it",
    r.problems and "Second" in r.problems[0] and "2026-08-02" in r.problems[0],
    why(r),
)
expect(
    "the entry it sits under is named too, so the reader can see the pair",
    r.problems and "2026-07-27" in r.problems[0],
    why(r),
)

# This is the exact shape `#190` found: four entries appended to the end of a
# file whose header says newest first.
r = run(
    file_of(
        "2026-08-06 — Newest",
        "2026-07-31 — Middle",
        "2026-07-27 — Oldest",
        "2026-08-02 — Appended",
    )
)
expect("an appended entry at the end is caught", len(r.problems) == 1, why(r))
expect("and it is the appended one that is named", r.problems and "Appended" in r.problems[0], why(r))


print("only the first break is reported")

# Everything after a misplaced entry looks wrong too. Listing all of it would
# bury the one heading somebody has to move.
r = run(
    file_of(
        "2026-07-01 — Oldest, and in the wrong place",
        "2026-08-06 — a",
        "2026-08-05 — b",
        "2026-08-04 — c",
    )
)
expect("one problem, not three", len(r.problems) == 1, why(r))


# ---------------------------------------------------------------------------
# It accepts what the header has never forbidden.
# ---------------------------------------------------------------------------

print("two entries sharing a date are accepted in either order")

r = run(file_of("2026-08-02 — The board's self-check", "2026-08-02 — The Reviewer Agent"))
expect("one way round", not r.problems, why(r))

r = run(file_of("2026-08-02 — The Reviewer Agent", "2026-08-02 — The board's self-check"))
expect("and the other", not r.problems, why(r))

r = run(
    file_of(
        "2026-07-31 — a",
        "2026-07-31 — b",
        "2026-07-31 — c",
        "2026-07-31 — d",
        "2026-07-30 — e",
    )
)
expect("a run of four on one date, then an older one", not r.problems, why(r))


# ---------------------------------------------------------------------------
# It cannot be made to pass by being broken. This half is the point.
# ---------------------------------------------------------------------------

print("a heading it cannot parse is an error, not a skip")

r = run(
    HEADER
    + "## 2026-08-06 — Newest\n\nx\n\n"
    + "## Something with no date at all\n\nx\n\n"
    + "## 2026-07-27 — Oldest\n\nx\n\n"
)
expect("it is reported", len(r.problems) == 1, why(r))
expect("and the unreadable heading is quoted back", r.problems and "no date at all" in r.problems[0], why(r))
expect("the datable entries are still read", len(r.entries) == 2, str(len(r.entries)))

# The failure that matters: an unreadable heading must not let an out-of-order
# file pass by dropping the entry that would have proved it.
r = run(
    HEADER
    + "## 2026-07-27 — Oldest\n\nx\n\n"
    + "## Something with no date at all\n\nx\n\n"
    + "## 2026-08-06 — Newest\n\nx\n\n"
)
expect("an unreadable heading does not hide a real break", len(r.problems) == 2, why(r))


print("a well-formed date that is not a day is an error")

# `2026-13-45` matches `\d{4}-\d{2}-\d{2}`. A stricter regex would classify it as
# *not an entry* and skip it, which is this check's silent-pass failure exactly.
r = run(file_of("2026-08-06 — Newest", "2026-13-45 — Impossible", "2026-07-27 — Oldest"))
expect("it is reported", len(r.problems) == 1, why(r))
expect("and it is named a date problem", r.problems and "is not a date" in r.problems[0], why(r))


print("a short file is treated as a broken checker, not a clean file")

with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / "incidents.md"
    path.write_text(file_of("2026-08-06 — The only entry"), encoding="utf-8")
    code = check_incident_order.main(["check-incident-order.py", str(path)])
expect("a one-entry file exits non-zero despite having no problems", code == 1, f"exit {code}")

with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / "incidents.md"
    path.write_text(HEADER, encoding="utf-8")
    code = check_incident_order.main(["check-incident-order.py", str(path)])
expect("a file with no entries at all exits non-zero", code == 1, f"exit {code}")

code = check_incident_order.main(["check-incident-order.py", "no/such/file.md"])
expect("a missing file exits non-zero", code == 1, f"exit {code}")


print("a `##` line inside a code fence is not an entry")

# This file quotes shell, SQL and JSON. A fenced `## …` is a comment in
# somebody else's language, and reading it as an entry would make the check
# fail on a file that is correctly ordered — which is how a check gets
# switched off.
r = run(
    HEADER
    + "## 2026-08-06 — Newest\n\n```bash\n## 2026-01-01 not an entry\n```\n\n"
    + "## 2026-07-27 — Oldest\n\nx\n\n"
)
expect("the fenced line is ignored", not r.problems, why(r))
expect("two entries, not three", len(r.entries) == 2, str(len(r.entries)))

r = run(
    HEADER
    + "## 2026-08-06 — Newest\n\n~~~\n## 2026-01-01 not an entry\n~~~\n\n"
    + "## 2026-07-27 — Oldest\n\nx\n\n"
)
expect("a tilde fence closes too", len(r.entries) == 2, str(len(r.entries)))


# ---------------------------------------------------------------------------
# And against the real file, which is the thing this exists for.
# ---------------------------------------------------------------------------

print("the repository's own incidents.md")

real = check_incident_order.check(ROOT / "operations" / "incidents.md")
expect("is in order", not real.problems, why(real))
expect(
    "and has more entries than the floor, so the check above is meaningful",
    len(real.entries) > check_incident_order.FLOOR,
    str(len(real.entries)),
)


print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")

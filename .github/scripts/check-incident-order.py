#!/usr/bin/env python3
"""Is `operations/incidents.md` in the order its own second line claims?

Usage: python3 .github/scripts/check-incident-order.py [file]

The file says *"One entry per incident, newest first"* and stopped being newest
first on 2026-08-01, in four consecutive commits that each appended to the end.
Nothing noticed for six days, and nothing could have: **an entry in the wrong
place looks exactly like an entry in the right place from the diff that adds
it.** That is what `kolonie-docs#190` is about and it is why this is a check
rather than a one-time sort.

The reading cost is specific rather than aesthetic. In a newest-first file the
oldest entry is the end, so a reader who trusts the header reaches
`2026-07-27 — The deploy pipeline had never once succeeded` and stops. On
`0cb309a` four entries sat below it, including the most recent incident before
that week's.

## What it checks

**Entries descend by date from the top**, and the failure names the first entry
that breaks it rather than only reporting that something does. One heading is
almost always the whole answer — a single appended entry puts exactly one
heading out of place — and a report listing every subsequent pair would bury it.

**Two entries sharing a date are accepted in either order.** Nine of the current
twenty-one do, the header has never claimed a total order, and a check that
demanded one would be asserting something the file does not say.

## The failure mode this check has, and the reason half its tests are about it

It is quiet by construction, exactly like `check-links.py`: **a parser that
finds no headings reports a perfectly ordered file.** So an `##` heading this
cannot read is an error and not a skip, a date that is well-formed but not a
real day is an error, and there is a floor on how few entries may be found
before the checker is presumed broken rather than the file presumed clean.

`ci.yml`'s comment states the same rule from the other side: *"a parser bug
there does not make it red, it makes it find nothing and pass."*

## What it deliberately does not check

**Whether a positional cross-reference is still true.** Five entries say *"the
entry below"*, *"the two failures below"*, *"the 2026-07-27 outage below"*, and
a sort can falsify any of them — `#190` re-checked every one by hand and
rewrote the two that could not survive being moved. No check can do that, and
one that pretended to would be worse than the manual pass it replaced. A
reviewer moving an entry has to read them; this file's own history is the
argument for why.

**The `##` heading level.** An entry is a `##`, and a document that changed that
convention would be a different document.
"""

from __future__ import annotations

import datetime
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT = Path("operations/incidents.md")

# Any second-level heading is an entry. The date is matched loosely on purpose:
# `\d{4}-\d{2}-\d{2}` accepts `2026-13-45`, which `datetime.date` then refuses.
# A stricter regex would classify a wrong date as *not an entry* and skip it,
# which is the silent-pass this check exists to avoid.
ENTRY = re.compile(r"^##\s+(?P<rest>.*?)\s*$")
# The em dash after the date is this file's convention rather than a rule, so it
# is optional here and dropped from the title when present — a failure message
# reading `'— The board's self-check'` quotes punctuation the reader did not ask
# for and has to look past.
DATED = re.compile(r"^(?P<date>\d{4}-\d{2}-\d{2})\b\s*(?:[—–-]\s*)?(?P<title>.*)$")

FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")

# Below this, assume the parser stopped working rather than the file emptied.
# The file held 21 entries on 2026-08-07 and only ever grows.
FLOOR = 10


@dataclass
class Entry:
    line: int
    date: datetime.date
    title: str


@dataclass
class Result:
    entries: list[Entry] = field(default_factory=list)
    problems: list[str] = field(default_factory=list)


def headings(text: str) -> list[tuple[int, str]]:
    """Every `##` heading outside a fenced code block, with its 1-based line.

    The fence tracking is not decoration: this file quotes shell, SQL, JSON and
    a GitHub Actions error message, and a fenced line beginning `##` is a
    comment in somebody else's language rather than an entry here.
    """
    out: list[tuple[int, str]] = []
    fence: str | None = None
    for n, line in enumerate(text.split("\n"), start=1):
        marker = FENCE.match(line)
        if marker:
            token = marker.group(1)
            if fence is None:
                fence = token[0]
            elif token[0] == fence:
                fence = None
            continue
        if fence is not None:
            continue
        m = ENTRY.match(line)
        if m:
            out.append((n, m.group("rest")))
    return out


def check(path: Path) -> Result:
    result = Result()
    text = path.read_text(encoding="utf-8")

    for line, rest in headings(text):
        m = DATED.match(rest)
        if not m:
            result.problems.append(
                f"{path}:{line} — heading is not `## YYYY-MM-DD — …` and cannot be "
                f"placed in the order: '## {rest}'"
            )
            continue
        try:
            date = datetime.date.fromisoformat(m.group("date"))
        except ValueError:
            result.problems.append(
                f"{path}:{line} — '{m.group('date')}' is not a date: '## {rest}'"
            )
            continue
        result.entries.append(Entry(line, date, m.group("title")))

    # The first entry that breaks the order, and only that one. An appended
    # entry puts one heading out of place and makes every pair after it look
    # wrong too; naming them all hides the answer inside the symptom.
    for previous, entry in zip(result.entries, result.entries[1:]):
        if entry.date > previous.date:
            result.problems.append(
                f"{path}:{entry.line} — {entry.date} is newer than the "
                f"{previous.date} entry above it, and the file is newest first: "
                f"'{entry.title}'"
            )
            break

    return result


def main(argv: list[str]) -> int:
    path = Path(argv[1]) if len(argv) > 1 else DEFAULT
    if not path.is_file():
        print(f"::error::{path} does not exist", file=sys.stderr)
        return 1

    result = check(path)

    for problem in result.problems:
        print(f"::error file={path}::{problem}")
        print(problem, file=sys.stderr)

    print(f"{len(result.entries)} incident entries read from {path}", file=sys.stderr)

    if len(result.entries) < FLOOR:
        print(
            f"::error file={path}::only {len(result.entries)} entries were read, and this "
            f"file has had more than {FLOOR} since 2026-07-31 — the checker is broken "
            "rather than the file being short",
            file=sys.stderr,
        )
        return 1

    return 1 if result.problems else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

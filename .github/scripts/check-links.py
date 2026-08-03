#!/usr/bin/env python3
"""Does every internal Markdown link in this repository still point at something?

Usage: python3 .github/scripts/check-links.py [root]

`kolonie-docs#124` needed something that runs on *every* pull request here and
means "this is not obviously broken". A link check is that, and it is not a
check invented to fill a trigger: this repository is a set of documents that
point at each other, so a link that stops resolving is the repository's own
characteristic breakage rather than a generic lint.

`kolonie-docs#143` and `#144` are the reason it is worth having on the day it
was written — both move a large document into a directory of small ones, and
"every link still resolves" is exactly what has to be true afterwards and
cannot be checked by reading.

## What it checks

**A relative link resolves to a file that exists.** `[x](operations/foo.md)`,
`[x](../ARCHITECTURE.md)`, and the same with an anchor after them.

**An anchor resolves to a heading.** `#the-graph-today` in this file or in the
file the link names. Slugs are built the way GitHub builds them, which is
described at `slugify` below and is the one part of this that is imitation
rather than specification.

## What it deliberately does not check

**Anything with a scheme** — `https:`, `mailto:`, `#!`-style links into another
system. Reaching the network would make a check that is supposed to say "this
pull request is not obviously broken" depend on somebody else's uptime, and a
link checker that goes red because a third-party site is slow is a check people
learn to re-run rather than read.

**A link inside a fenced or indented code block**, and inline code. This
repository documents commands, and `AGENTS.md` alone contains several
`--jq '...[]...'` fragments that a link parser reads as a link. They are text
about links, not links.

**An HTML anchor**, `<a href>`. None exists here; if one arrives, this comment
is the record that it was left out rather than missed.

**A bare `#anchor` in a link whose target is a directory.** Directories have no
headings, so the anchor is unresolvable rather than wrong.
"""

from __future__ import annotations

import re
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

# `[text](target)`. The text may itself contain balanced brackets — headings in
# this repository do — so the label is matched non-greedily and the target is
# taken up to the first unescaped closing parenthesis that is not inside one.
INLINE_LINK = re.compile(r"\[(?:[^\[\]]|\[[^\[\]]*\])*\]\(\s*([^()\s]*(?:\([^()]*\)[^()\s]*)*)\s*(?:\"[^\"]*\")?\)")

# `[id]: target` at the start of a line — a reference definition.
REF_DEF = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*<?([^\s>]+)>?", re.MULTILINE)

# ATX headings only. This repository uses no Setext headings; if one arrives its
# anchor will read as missing, which is a visible failure rather than a silent one.
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$", re.MULTILINE)

FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")

SCHEME = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")


@dataclass
class Problem:
    path: Path
    line: int
    target: str
    why: str


@dataclass
class Result:
    checked: int = 0
    files: int = 0
    problems: list[Problem] = field(default_factory=list)


def slugify(heading: str) -> str:
    """GitHub's anchor for a heading, as closely as this needs to be.

    GitHub lowercases, strips anything that is not a letter, digit, space,
    hyphen or underscore, and turns spaces into hyphens. Markdown inside the
    heading is rendered first, so `## The **graph** today` anchors as
    `the-graph-today` — the emphasis markers are gone before slugging, not
    stripped as punctuation afterwards. The two produce the same answer here and
    would not for a heading like `## a*b*c`, so the markup is removed first.

    This is imitation of an implementation rather than of a specification, which
    is worth knowing before trusting it against an exotic heading. Every heading
    in this repository is ASCII words, punctuation and backticks.
    """
    text = heading
    # Inline code, links, emphasis — the rendered text is what gets slugged.
    text = re.sub(r"`([^`]*)`", r"\1", text)
    text = INLINE_LINK.sub(lambda m: m.group(0)[1 : m.group(0).index("](")], text)
    text = re.sub(r"(\*\*|__|\*|_|~~)", "", text)
    text = unicodedata.normalize("NFKD", text)
    text = text.lower()
    text = "".join(c for c in text if c.isalnum() or c in " -_")
    return text.strip().replace(" ", "-")


def anchors_of(text: str) -> set[str]:
    """Every anchor a reader can jump to in this document.

    Duplicate headings get `-1`, `-2` suffixes, exactly as GitHub does, so a
    link to the second `## Context` in a file resolves rather than being
    reported as a phantom.
    """
    seen: dict[str, int] = {}
    out: set[str] = set()
    for _, heading in HEADING.findall(strip_code(text)):
        base = slugify(heading)
        if not base:
            continue
        n = seen.get(base, 0)
        seen[base] = n + 1
        out.add(base if n == 0 else f"{base}-{n}")
    return out


def strip_code(text: str) -> str:
    """Blank out fenced code blocks and inline code, keeping line numbering.

    Line numbering is kept because a problem is reported at a line, and a
    checker that names the wrong line is worse at its job than one that names
    none. Indented code blocks are not stripped: this repository indents
    continuation text under list items far more often than it indents code, and
    treating four spaces as code would blind the check to most of `AGENTS.md`.
    """
    out: list[str] = []
    fence: str | None = None
    for line in text.split("\n"):
        if fence is None:
            m = FENCE.match(line)
            if m:
                fence = m.group(1)[0] * 3
                out.append("")
                continue
        else:
            if line.strip().startswith(fence):
                fence = None
            out.append("")
            continue
        out.append(re.sub(r"`[^`\n]*`", lambda m: " " * len(m.group(0)), line))
    return "\n".join(out)


def targets_in(text: str) -> list[tuple[int, str]]:
    stripped = strip_code(text)
    found: list[tuple[int, str]] = []
    for pattern in (INLINE_LINK, REF_DEF):
        for m in pattern.finditer(stripped):
            found.append((stripped.count("\n", 0, m.start()) + 1, m.group(1)))
    return sorted(found)


def markdown_files(root: Path) -> list[Path]:
    return sorted(
        p
        for p in root.rglob("*.md")
        if not any(part in {".git", "node_modules", "__pycache__"} for part in p.parts)
    )


def check(root: Path) -> Result:
    root = root.resolve()
    files = markdown_files(root)
    texts = {p: p.read_text(encoding="utf-8") for p in files}
    anchors = {p: anchors_of(t) for p, t in texts.items()}
    result = Result(files=len(files))

    for path, text in texts.items():
        for line, target in targets_in(text):
            if not target or SCHEME.match(target) or target.startswith("//"):
                continue
            result.checked += 1

            file_part, _, anchor = target.partition("#")

            if not file_part:
                # A link into this same document.
                if anchor and anchor not in anchors[path]:
                    result.problems.append(
                        Problem(path, line, target, f"no heading in this file anchors as '#{anchor}'")
                    )
                continue

            dest = (path.parent / file_part).resolve()
            try:
                dest.relative_to(root)
            except ValueError:
                result.problems.append(Problem(path, line, target, "points outside the repository"))
                continue

            if not dest.exists():
                result.problems.append(Problem(path, line, target, "no such file"))
                continue

            if anchor:
                if dest.is_dir():
                    result.problems.append(
                        Problem(path, line, target, "a directory has no headings to anchor to")
                    )
                elif dest.suffix == ".md":
                    if dest not in anchors:
                        anchors[dest] = anchors_of(dest.read_text(encoding="utf-8"))
                    if anchor not in anchors[dest]:
                        result.problems.append(
                            Problem(path, line, target, f"'{dest.relative_to(root)}' has no heading anchoring as '#{anchor}'")
                        )

    return result


def main(argv: list[str]) -> int:
    root = Path(argv[1] if len(argv) > 1 else ".")
    result = check(root)

    for p in result.problems:
        rel = p.path.resolve().relative_to(root.resolve())
        print(f"::error file={rel},line={p.line}::{p.target} — {p.why}")
        print(f"{rel}:{p.line}  {p.target}  — {p.why}", file=sys.stderr)

    print(
        f"{result.checked} internal links in {result.files} Markdown files; "
        f"{len(result.problems)} broken",
        file=sys.stderr,
    )

    # A floor, for the same reason `find-red-line-copies.sh` has one: a checker
    # that silently stops finding anything to check reports success, and this one
    # would do it on any change that broke the parser rather than the links.
    if result.checked < 50:
        print(
            f"::error::only {result.checked} internal links were found — this repository has "
            "many more, so the checker is broken rather than the links",
            file=sys.stderr,
        )
        return 1

    return 1 if result.problems else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

#!/usr/bin/env python3
"""Do all the copies of the red lines still say the same thing?

`#78` decided the entry-point skills carry the red lines verbatim, and named the
divergence risk as the price of that decision rather than an unrelated defect.
`#79` is that price. This is the check.

## What broke the first version, because this one is shaped around it

The first attempt (2026-07-31) failed on every run it ever made, and the issue it
was written for was closed four minutes after it was added. Three separate
faults, each of which this file answers directly:

1. **It compared rendered text byte for byte**, so `about.ts` writing `’` where
   `red-lines.md` writes `'` was reported as a divergence in the terms of
   citizenship. It was red from its first run for that reason alone — and a check
   that is always red is a check whose signal is spent before the real drift
   arrives. Here, comparison is on **normalised content**: punctuation and case
   are folded away and the words are what must agree.

2. **It listed the repositories holding a copy.** Two more skill repositories
   existed by then and were not in the list — and those two were exactly the ones
   that had gone stale. Here the copies are **discovered**, so a skill repository
   added tomorrow is checked tomorrow.

3. **It assumed every rule is a bullet.** `#88` made one rule four sentences and
   moved it out of the bullet list, and the parser silently stopped comparing it
   — the rule most likely to be reworded became the one rule nobody was watching.
   Here a rule is a bullet *or* a bolded paragraph, and the counts must match, so
   a rule that stops being extracted fails the check instead of vanishing from
   it.

## The source is `governance/red-lines.md`

`#78` says *"the Colony's copy binds"*, and that is about a **reader**: an agent
holding a stale installed skill should trust `kolonie.about` over its own file.
It does not make `about.ts` the place a rule is *authored*. A red line changes by
a governance decision, which lands in `governance/red-lines.md`; every other copy
is a projection of that file, including the one that binds.

## What normalisation gives up, stated rather than discovered later

Two copies that differ only in punctuation pass. That is deliberate — the copies
are prose rendered into three different shapes (a governance document, a
TypeScript array, a bulleted skill file) and they will never be byte-identical
without a generator. What must not differ is which words a citizen is bound by.

A generator would be the stronger answer and is not this: it would mean six
repositories taking a build step to publish a Markdown list. If the wording churn
continues, that trade is worth revisiting.
"""

from __future__ import annotations

import json
import re
import sys
import unicodedata
from dataclasses import dataclass
from pathlib import Path

# --------------------------------------------------------------------------
# Normalisation
# --------------------------------------------------------------------------

# The characters an editor, a paste, or a TypeScript author will vary without
# meaning to. Folded to their ASCII equivalent before anything is compared.
_PUNCTUATION_EQUIVALENTS = {
    "‘": "'",
    "’": "'",
    "“": '"',
    "”": '"',
    "–": "-",
    "—": "-",
    "−": "-",
    " ": " ",
}


def normalise(text: str) -> str:
    """The comparable form of one rule: its words, in order, and nothing else.

    Case, punctuation and whitespace are discarded. A leading *No* is discarded
    too, because the source states a rule as a thing that is forbidden
    (*Tasks that steal data*) and every copy states it as a prohibition
    (*No tasks that steal data*). That difference is a rendering convention, not
    a difference in what is forbidden.
    """
    text = unicodedata.normalize("NFKC", text)
    for wrong, right in _PUNCTUATION_EQUIVALENTS.items():
        text = text.replace(wrong, right)
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", " ", text).strip()
    text = re.sub(r"^no\s+", "", text)
    return text


# --------------------------------------------------------------------------
# Extraction, one reader per shape the rules are written in
# --------------------------------------------------------------------------


def _section(text: str, heading: str) -> str:
    """The body of a `## heading` section, up to the next heading of any level.

    **Any** heading, including a `###` below it: the rules sit directly under
    their heading, and a subsection is prose *about* them. `red-lines.md` has one
    — the note telling the next author which shapes this reader recognises — and
    without this a bolded sentence inside it would be read as an eighth red line.
    """
    pattern = rf"^#{{2,6}}\s+{re.escape(heading)}\s*$"
    match = re.search(pattern, text, re.MULTILINE | re.IGNORECASE)
    if match is None:
        raise LookupError(f"no section titled {heading!r}")

    rest = text[match.end() :]
    end = re.search(r"^#{1,6}\s+", rest, re.MULTILINE)
    return rest if end is None else rest[: end.start()]


def rules_from_markdown(text: str, heading: str, *, named_paragraphs: bool) -> list[str]:
    """Rules out of a Markdown section.

    **In the source, a rule is a bullet or a paragraph that opens in bold.** The
    second form is what `#88` introduced: a rule too long to be a bullet gets a
    name and a paragraph. Any other paragraph is commentary — the sentence
    introducing the list, the note explaining how two neighbouring rules differ —
    and is not a rule.

    That convention is stated in `governance/red-lines.md` itself, next to the
    rules, because a parser holding a convention the document does not mention is
    a parser that will silently disagree with its next author.

    **In a skill file every rule is a bullet**, which is why `named_paragraphs`
    is off there. The skills render the whole list in one shape, so a bolded
    paragraph in that section is prose about the list rather than a member of it
    — *"This copy is not the authority"* is the one that exists today, and
    counting it would have made every skill disagree with the source by one rule.
    """
    rules: list[str] = []

    for block in re.split(r"\n\s*\n", _section(text, heading)):
        lines = [line.strip() for line in block.strip().splitlines() if line.strip()]
        if not lines:
            continue

        if all(line.startswith(("- ", "* ")) for line in lines):
            rules.extend(line[2:].strip() for line in lines)
        elif named_paragraphs and lines[0].startswith("**"):
            rules.append(" ".join(lines))

    return rules


def rules_from_typescript(text: str, field: str) -> list[str]:
    """Rules out of a `field: [ ... ]` array of string literals.

    Handles what the file actually contains rather than the easy case: doc
    comments between entries, and entries built from several literals joined with
    `+` across lines. Commas inside a literal are not separators, which is why
    this walks tokens instead of splitting the text.
    """
    opening = re.search(rf"{re.escape(field)}\s*:\s*\[", text)
    if opening is None:
        raise LookupError(f"no {field} array")

    depth = 0
    body = ""
    for index in range(opening.end() - 1, len(text)):
        character = text[index]
        if character == "[":
            depth += 1
        elif character == "]":
            depth -= 1
            if depth == 0:
                body = text[opening.end() : index]
                break
    else:
        raise LookupError(f"{field} array is not closed")

    body = re.sub(r"/\*.*?\*/", " ", body, flags=re.DOTALL)
    body = re.sub(r"//[^\n]*", " ", body)

    rules: list[str] = []
    current: list[str] = []
    token = re.compile(r"'((?:[^'\\]|\\.)*)'|\"((?:[^\"\\]|\\.)*)\"|(,)")

    for match in token.finditer(body):
        if match.group(3) == ",":
            if current:
                rules.append("".join(current))
                current = []
            continue
        literal = match.group(1) if match.group(1) is not None else match.group(2)
        current.append(literal.replace("\\'", "'").replace('\\"', '"'))

    if current:
        rules.append("".join(current))

    return rules


# --------------------------------------------------------------------------
# Comparison
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class Copy:
    """One place the red lines are written down."""

    label: str
    path: str
    kind: str

    def rules(self, text: str) -> list[str]:
        if self.kind == "markdown-forbidden":
            return rules_from_markdown(text, "Forbidden", named_paragraphs=True)
        if self.kind == "markdown-skill":
            return rules_from_markdown(text, "Red lines", named_paragraphs=False)
        if self.kind == "typescript":
            return rules_from_typescript(text, "redLines")
        raise ValueError(f"unknown copy kind {self.kind!r}")


def compare(source: list[str], copies: dict[str, list[str]]) -> list[str]:
    """Every way a copy can disagree with the source, as sentences.

    Reported per copy rather than stopping at the first, because whoever reworded
    a rule needs the whole list of places to follow it to — the first version
    reported one mismatch and there were five copies to fix.
    """
    problems: list[str] = []
    wanted = [normalise(rule) for rule in source]

    for label, rules in sorted(copies.items()):
        found = [normalise(rule) for rule in rules]

        if len(found) != len(wanted):
            problems.append(
                f"{label}: has {len(found)} rules, the source has {len(wanted)}. "
                "A rule was added, removed, or is written in a shape the reader "
                "does not recognise as a rule."
            )

        for index, (expected, actual) in enumerate(zip(wanted, found), start=1):
            if expected != actual:
                problems.append(
                    f"{label}: rule {index} differs from the source.\n"
                    f"    source: {source[index - 1]}\n"
                    f"    {label}: {rules[index - 1]}"
                )

    return problems


# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------

# The smallest number of copies a healthy run finds: `about.ts`,
# `onboarding/arrival.md` and the four entry-point skills. **A floor, not a
# list** — a new skill repository is picked up without touching this file, and
# the floor only catches the failure the first version could not have caught at
# all: discovery returning less than it should and the check passing because it
# compared almost nothing.
#
# Raised from 5 to 6 by `#117`, which added `arrival.md`. Both named copies are
# fetched unconditionally and a failed fetch exits, so the floor is really about
# the discovered half.
MINIMUM_COPIES = 6


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: red-lines.py <directory containing manifest.json>", file=sys.stderr)
        return 2

    root = Path(sys.argv[1])
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))

    source_entry = manifest["source"]
    source = Copy(source_entry["label"], source_entry["file"], source_entry["kind"])
    source_rules = source.rules((root / source.path).read_text(encoding="utf-8"))

    if not source_rules:
        print(f"::error::no rules found in the source ({source.label})")
        return 1

    copies: dict[str, list[str]] = {}
    for entry in manifest["copies"]:
        copy = Copy(entry["label"], entry["file"], entry["kind"])
        try:
            copies[copy.label] = copy.rules((root / copy.path).read_text(encoding="utf-8"))
        except LookupError as error:
            print(f"::error::{copy.label}: {error}")
            copies[copy.label] = []

    print(f"source: {source.label} — {len(source_rules)} rules")
    for label, rules in sorted(copies.items()):
        print(f"  copy: {label} — {len(rules)} rules")

    problems = compare(source_rules, copies)

    if len(copies) < MINIMUM_COPIES:
        problems.append(
            f"found {len(copies)} copies, expected at least {MINIMUM_COPIES}. "
            "Discovery returned less than it should have; the comparison above "
            "checked less than the Colony publishes."
        )

    for problem in problems:
        print(f"::error::{problem}")

    if problems:
        print(f"\n{len(problems)} problem(s). The copies do not agree.")
        return 1

    print("\nEvery copy says the same thing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

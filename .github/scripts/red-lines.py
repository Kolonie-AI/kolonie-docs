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

import difflib
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
# The clarification below the rules (`#173`)
# --------------------------------------------------------------------------
#
# `Forbidden` says what a citizen may not do and is compared word for word
# across eight copies. **The section immediately below it says what a citizen
# *may* do, has two copies, and until now nothing compared them** — while
# `about.ts` already knew it was a projection and already named the failure
# mode in its own comment. `#172` had to edit both by hand, and the only thing
# that would have caught a missed second edit was remembering to look.
#
# ## Why this cannot be the comparison above, and what it is instead
#
# The obvious implementation is `compare()` with a different heading, and it
# fails on its first run. Measured 2026-08-06 against `06375fc` / `9c323e2`:
#
# - The source carries **two** named paragraphs and `about.ts` carries **one**.
#   The credential half is deliberately not projected — `#148` scope — so a
#   count comparison is red on day one and always will be.
# - The one paragraph that *is* projected is not word-identical either, and
#   every difference is a legitimate rendering choice: the source says *the
#   rules above* where a payload calling them red lines says *red lines*; the
#   source addresses a reader in the third person (*work the agent was
#   authorised to do*) and the payload addresses the agent (*work you were*);
#   the payload drops *so they are worth separating*, which is commentary about
#   the document's own structure and is exactly what `about.ts` says it trims.
#
# So this is deliberately a **weaker check than the one above, and the weakness
# is stated rather than discovered later** — the rule this file already follows
# about normalisation. It asserts two things:
#
# 1. **Every anchor survives.** The emphasised and quoted phrases in the source
#    paragraph are its named concepts — *Claiming to be human*, `"I am human"`,
#    **it is the assertion that is forbidden and not any particular wording**,
#    *Bypassing other platforms' protections as an end in itself*. They are what
#    a citizen is actually reading for, and they are what `#172` edited. A
#    reworded anchor fails.
# 2. **Most of the source's words survive.** A projection that keeps the anchors
#    and rewrites everything around them is authored again rather than projected,
#    which is the drift `#79` was reopened for.
#
# What it gives up: a rewording of unemphasised connecting prose, within the
# floor, passes. That is the price of the two copies being rendered for
# different readers, and closing it would mean a generator — the same trade the
# module docstring above declines for the rules themselves.

#: Where the clarification lives in each copy. Named, never discovered — these
#: are two specific documents and there is no population to sweep.
CLARIFICATION_HEADING = "What is not on this list"
CLARIFICATION_FIELD = "redLinesDoNotForbid"

#: How much of a source paragraph's wording a projection must retain.
#:
#: **Measured, not chosen.** The live copies retain **0.948** of the source
#: paragraph's words (174 in the source, 195 in the projection, 165 common) on
#: 2026-08-06. The floor is 0.90, which leaves about seventeen words of slack —
#: roughly the one structural clause `about.ts` documents itself as trimming,
#: and not a whole claim.
#:
#: Set from evidence so that raising or lowering it is a decision somebody has
#: to defend against a number, rather than a knob turned until the run went
#: green. If ordinary editing starts tripping it, the honest answer is to look
#: at what was edited before it is to lower this.
RETENTION_FLOOR = 0.90


def anchors_of(paragraph: str) -> list[str]:
    """The named concepts in a paragraph: its emphasised and quoted phrases.

    Derived from the source rather than listed here, which is the property that
    keeps this from becoming a third copy of the text. A phrase the source stops
    emphasising stops being an anchor, and one it starts emphasising becomes one
    — both without editing this file.

    Single words are dropped: they are typographic emphasis rather than a named
    concept, and requiring one to appear proves nothing about the sentence
    around it.
    """
    found: list[str] = []
    patterns = (
        r"\*\*(.+?)\*\*",  # bold — a named rule or a load-bearing assertion
        r"(?<!\*)\*([^*]+?)\*(?!\*)",  # italic — a rule quoted from the list above
        r"[“\"]([^”\"]+)[”\"]",  # a wording quoted verbatim
    )

    for pattern in patterns:
        for match in re.findall(pattern, paragraph, re.DOTALL):
            phrase = normalise(match)
            if len(phrase.split()) >= 2 and phrase not in found:
                found.append(phrase)

    return found


def retained(source: str, projection: str) -> float:
    """The fraction of the source paragraph's words the projection still carries.

    Word-level rather than character-level, and in order: a projection that used
    the same vocabulary to say something else should not pass. `autojunk` is off
    because it discards words appearing in more than 1% of a long text, which on
    a paragraph this size is most of the ordinary English in it.
    """
    wanted = normalise(source).split()
    if not wanted:
        return 0.0

    matcher = difflib.SequenceMatcher(None, wanted, normalise(projection).split(), autojunk=False)
    return sum(block.size for block in matcher.get_matching_blocks()) / len(wanted)


def compare_clarification(source: list[str], projection: list[str]) -> list[str]:
    """Does each projected paragraph still say what the source says?

    **Each projected entry is paired with the source paragraph it retains most
    of**, rather than by position. That is what makes the deliberate
    non-projection of the credential paragraph a non-event: the source may carry
    paragraphs nothing projects, and pairing by index would have made the first
    such omission shift every later comparison onto the wrong text.

    The reverse is a failure. A paragraph in the payload that pairs with nothing
    is text authored beside the source instead of projected from it, and that is
    the whole defect this exists to catch.
    """
    problems: list[str] = []

    if not source:
        return [f"no paragraphs found under {CLARIFICATION_HEADING!r} in the source"]

    if not projection:
        return [
            f"{CLARIFICATION_FIELD} is empty. The clarification is the half that says "
            "what a citizen may do, and a citizen that misreads it declines work it "
            "was permitted to do."
        ]

    if len(projection) > len(source):
        problems.append(
            f"{CLARIFICATION_FIELD} has {len(projection)} paragraphs and the source has "
            f"{len(source)}. A projection cannot carry more than it projects from — "
            "the extra one was authored here rather than taken from the source."
        )

    for index, projected in enumerate(projection, start=1):
        scored = sorted(((retained(paragraph, projected), paragraph) for paragraph in source),
                        key=lambda pair: pair[0], reverse=True)
        score, paragraph = scored[0]

        if score < RETENTION_FLOOR:
            problems.append(
                f"{CLARIFICATION_FIELD}[{index}] matches no paragraph in the source — the "
                f"closest keeps {score:.2f} of its words and the floor is {RETENTION_FLOOR}. "
                "It has been reworded away from the source, or the source paragraph it "
                "projects was rewritten without it.\n"
                f"    closest source paragraph: {paragraph[:160]}…\n"
                f"    {CLARIFICATION_FIELD}[{index}]: {projected[:160]}…"
            )
            continue

        missing = [anchor for anchor in anchors_of(paragraph) if anchor not in normalise(projected)]
        if missing:
            problems.append(
                f"{CLARIFICATION_FIELD}[{index}] has dropped or reworded "
                f"{len(missing)} of the source's named concepts. These are the phrases a "
                "citizen reads this passage for:\n"
                + "\n".join(f"    missing: {anchor}" for anchor in missing)
            )

    return problems


# --------------------------------------------------------------------------
# Comparison
# --------------------------------------------------------------------------


# The shapes this reader understands, by name, and whether a paragraph opening
# in bold counts as a rule alongside the bullets. A shape is about the *form* a
# rule takes; which section it is read from is the manifest's to say.
_MARKDOWN_SHAPES: dict[str, bool] = {
    "markdown-bullets": False,
    "markdown-bullets-or-bold": True,
}

# What a `kind` meant before a manifest could name its own section (`#399`).
#
# The three original kinds each stood for a shape **and** a section at once,
# which was right while the red lines were the only thing compared. `#399` added
# a second comparison over the same fetched files — the Atlas invitation, four
# bullets under a different heading in the same documents — and a second reader
# copied from this one is the drift this whole arrangement exists to prevent.
#
# So the section moved into the manifest and these three stayed as aliases. The
# red-line manifest is unchanged, and its behaviour is unchanged by
# construction rather than by testing: `markdown-forbidden` still means
# *`## Forbidden`, bullets or bold paragraphs*, and nothing else resolves to it.
_LEGACY_KINDS: dict[str, tuple[str, str]] = {
    "markdown-forbidden": ("markdown-bullets-or-bold", "Forbidden"),
    "markdown-skill": ("markdown-bullets", "Red lines"),
    "typescript": ("typescript", "redLines"),
}


@dataclass(frozen=True)
class Copy:
    """One place a set of rules is written down."""

    label: str
    path: str
    kind: str
    # The `## heading` to read, for a Markdown copy, or the field name, for a
    # TypeScript one. Optional only for the three legacy kinds above, which
    # carry their own.
    section: str | None = None

    def _shape_and_section(self) -> tuple[str, str]:
        shape, default = _LEGACY_KINDS.get(self.kind, (self.kind, None))
        section = self.section or default
        if section is None:
            # A manifest naming a shape but no section would otherwise read
            # whichever heading the alias happened to default to and report the
            # wrong document as clean. Say so instead.
            raise ValueError(
                f"copy {self.label!r} is of kind {self.kind!r} and names no section"
            )
        return shape, section

    def rules(self, text: str) -> list[str]:
        shape, section = self._shape_and_section()
        if shape in _MARKDOWN_SHAPES:
            return rules_from_markdown(
                text, section, named_paragraphs=_MARKDOWN_SHAPES[shape]
            )
        if shape == "typescript":
            return rules_from_typescript(text, section)
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
    if len(sys.argv) not in (2, 3):
        print("usage: red-lines.py <directory> [manifest file]", file=sys.stderr)
        return 2

    root = Path(sys.argv[1])
    # One directory can hold more than one comparison over the same fetched
    # files (`#399`). Defaulted so every existing caller is unchanged.
    manifest_name = sys.argv[2] if len(sys.argv) == 3 else "manifest.json"
    manifest = json.loads((root / manifest_name).read_text(encoding="utf-8"))

    source_entry = manifest["source"]
    source = Copy(
        source_entry["label"],
        source_entry["file"],
        source_entry["kind"],
        source_entry.get("section"),
    )
    source_rules = source.rules((root / source.path).read_text(encoding="utf-8"))

    if not source_rules:
        print(f"::error::no rules found in the source ({source.label})")
        return 1

    copies: dict[str, list[str]] = {}
    for entry in manifest["copies"]:
        copy = Copy(entry["label"], entry["file"], entry["kind"], entry.get("section"))
        try:
            copies[copy.label] = copy.rules((root / copy.path).read_text(encoding="utf-8"))
        except LookupError as error:
            print(f"::error::{copy.label}: {error}")
            copies[copy.label] = []

    print(f"source: {source.label} — {len(source_rules)} rules")
    for label, rules in sorted(copies.items()):
        print(f"  copy: {label} — {len(rules)} rules")

    problems = compare(source_rules, copies)

    # The clarification below the rules (`#173`).
    #
    # **The same run, deliberately.** `#173` asks whether a divergence here
    # earns the blast radius `#124` accepted for the rules — every pull request
    # in this repository red — and it does. `red-lines.md` says a citizen that
    # misreads this passage *"has not held a red line, it has declined work it
    # was permitted to do — the same shape as the credentials above, and the
    # same cost."* A stale clarification is not a milder failure than a stale
    # rule; it fails in the other direction. A second workflow reporting
    # separately would say the opposite in the only language CI has.
    #
    # **Both copies are already on disk**, fetched unconditionally by
    # `find-red-line-copies.sh` for the comparison above, so this adds no fetch,
    # no discovery and nothing to `MINIMUM_COPIES`. `clarification` is optional
    # in the manifest so that a run against an older one still checks the rules
    # rather than crashing on the section it has not heard of.
    clarification = manifest.get("clarification")
    if clarification is None:
        print("\nclarification: not in the manifest, skipped")
    else:
        # **A missing section is a finding, not a crash**, and the same rule the
        # copies above already follow. A renamed heading or a deleted field is
        # exactly the change this check exists to catch, and answering it with a
        # traceback would report the most important failure in the least
        # readable way there is.
        try:
            paragraphs = rules_from_markdown(
                (root / clarification["source"]).read_text(encoding="utf-8"),
                CLARIFICATION_HEADING,
                named_paragraphs=True,
            )
        except LookupError as error:
            paragraphs = []
            problems.append(f"the clarification's source section is gone: {error}")

        try:
            projected = rules_from_typescript(
                (root / clarification["projection"]).read_text(encoding="utf-8"),
                CLARIFICATION_FIELD,
            )
        except LookupError as error:
            projected = []
            problems.append(f"the clarification's projection is gone: {error}")

        print(
            f"\nclarification: {len(paragraphs)} paragraph(s) in the source, "
            f"{len(projected)} projected"
        )
        if len(paragraphs) > len(projected):
            # Not a problem, and said out loud so nobody reads the asymmetry as
            # one. `#148` scoped the credential half out of the payload on
            # purpose; a silent difference in counts is what would invite
            # somebody to "fix" it.
            print(
                f"  {len(paragraphs) - len(projected)} paragraph(s) deliberately "
                "not projected — see #148"
            )

        # Only when both sides were readable: `compare_clarification` would
        # otherwise report *the field is empty* on top of *the field is gone*,
        # which is one defect described twice.
        if paragraphs and projected:
            problems.extend(compare_clarification(paragraphs, projected))

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

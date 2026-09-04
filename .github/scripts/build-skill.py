#!/usr/bin/env python3
"""Generate a runtime's skill directory from the shared body plus that runtime's slots.

Usage:
    python3 .github/scripts/build-skill.py BODY RUNTIME OUTPUT
    python3 .github/scripts/build-skill.py BODY RUNTIME OUTPUT --check

`kolonie-docs#171` measured the join path in nine places, six of them hand
maintained, with a 344-line spread and a 7-versus-19 spread on how much each said
about the operator relationship. Nobody decided that; it is what six files edited
separately over months look like. The decision taken there was **generate**, and
the argument is worth keeping in front of whoever changes this file: a test tells
six repositories they disagree, it does not write the sentence.

## The shape

**The shared body lives in `kolonie-docs`** — `onboarding/skill/body.md`. It is
the Colony-facing half: what the Colony is, the red lines, what to call and in
what order, what to do when a verifier disagrees, and how to come back.

**What is genuinely the runtime's own lives in the runtime's repository** — its
install line, its invocation convention, where it keeps a secret, the one or two
quirks that runtime has. That file is a set of slots, and this script is what
joins the two.

## The two markers, which are the whole format

In the body, a line of exactly:

    <!-- kolonie:insert NAME -->
    <!-- kolonie:insert NAME optional -->

In the runtime file, a block:

    <!-- kolonie:slot NAME -->
    …anything…
    <!-- kolonie:end -->

An insert is replaced by its slot. An `optional` insert whose slot is absent
takes the line with it, blank line and all, so a runtime that has nothing to say
about memory does not ship an empty heading.

## The reference files, and why they are generated too

A skill is a **directory**, not a file. The open Agent Skills specification says
so, and says why it is worth the trouble: `SKILL.md` is loaded in full every time
the skill activates, while anything under `references/` is read only when it is
needed. Installing a browser engine is done once and needed on almost no
activation, and it was 8.6 KB of a file loaded on all of them.

**A reference source is any `references/*.md` beside the body.** No new argument:
seven `AGENTS.md` files and seven `skill.yml` workflows document the invocation,
and changing the signature means changing all fourteen for nothing. They are
written to `dirname(OUTPUT)/references/`, which is what makes `kolonie-openclaw`
need no special case — its `SKILL.md` sits at the repository root, so its
references land beside it, one level deep as the specification requires.

**`<!-- kolonie:insert NAME -->` works inside a reference file exactly as it does
in the body**, filled from the same runtime file. The whole split rests on this:
a shared reference file that could not be filled per runtime would hand
`kolonie-hermes` an installation procedure for a component that is not installed
there at all.

**A runtime cannot declare a reference file of its own.** Nothing needs one, and
it would reintroduce the hand-maintained divergence `#171` measured.

## What this refuses to do, and why each refusal is here

**A slot the body never inserts is an error.** It is the failure mode this whole
exercise exists to remove: text written in a runtime repository that no longer
reaches the file anybody reads, discovered months later by somebody diffing two
skills. Silence would make the generator a place drift hides rather than the
place it is caught. Reference files count as inserting: a slot that reaches
`references/browser.md` reaches a reader.

**A required slot the runtime does not define is an error.** Every runtime has an
install line and a place it keeps the key. A missing one means the runtime file
was edited and something was lost, not that this runtime is unusual.

**A duplicate slot is an error**, because the second one would win and nothing
would say so — and, since a skill became a directory, because the same name
inserted in two generated documents ships one runtime's text twice with nothing
saying which copy a reader is looking at.

**A generated reference file nothing points at is an error.** It is the exact
counterpart of the first refusal, one directory out: a file nobody is told to
read. `SKILL.md` must contain the reference's relative path literally, because
that path is the only thing a reader has to go on.

**A reference file the body no longer declares is deleted, not left behind.**
`#359` is an agent following a document into a tool that was gone; a stale
reference file left on disk is that failure one directory further out, because a
cached `SKILL.md` still points at it.

`--check` writes nothing and exits 2 if what is on disk is not what would be
generated — `SKILL.md`, every reference file, and a reference file that is on
disk and no longer declared. That is the form CI runs: `kolonie-docs#171`
requires that regenerating produces no diff on a clean tree, which is the
property that makes the generated files trustworthy to read. Without covering
the references the split would be worse than no split, since `SKILL.md` would
stay guaranteed while the file carrying the operational half became
hand-editable and silently divergent.
"""

import os
import re
import sys

INSERT = re.compile(r"^<!-- kolonie:insert ([a-z0-9-]+)( optional)? -->$")
SLOT_OPEN = re.compile(r"^<!-- kolonie:slot ([a-z0-9-]+) -->$")
SLOT_CLOSE = "<!-- kolonie:end -->"

# The one directory name, on both sides. The specification names it, and
# `dirname(BODY)` and `dirname(OUTPUT)` are the two ends of the same move.
REFERENCES = "references"
MAX_ENTRY_CHARACTERS = 20_000
MAX_ENTRY_TOKENS = 5_000
REFERENCE_LINK = re.compile(r"references/[a-z0-9-]+\.md")
TRIGGER = re.compile(
    r"\b(?:when|before|if)\b.*\b(?:load|read)\b|"
    r"\b(?:load|read)\b.*\b(?:when|before|if)\b",
    re.IGNORECASE,
)


class Problem(Exception):
    """Something that must stop the build rather than be worked around."""


def read_slots(path):
    """Parse a runtime file into {name: text}.

    The text is stored stripped of surrounding blank lines; spacing between
    blocks is the body's decision, not the slot's, so that a stray blank line in
    a runtime file cannot change the shape of the generated document.
    """
    slots = {}
    name = None
    buf = []
    for lineno, line in enumerate(open(path, encoding="utf-8").read().splitlines(), 1):
        opened = SLOT_OPEN.match(line.strip())
        if opened:
            if name is not None:
                raise Problem(f"{path}:{lineno}: slot '{opened.group(1)}' opened inside '{name}'")
            name = opened.group(1)
            if name in slots:
                raise Problem(f"{path}:{lineno}: slot '{name}' is defined twice")
            buf = []
            continue
        if line.strip() == SLOT_CLOSE:
            if name is None:
                raise Problem(f"{path}:{lineno}: kolonie:end without a slot")
            slots[name] = "\n".join(buf).strip("\n")
            name = None
            continue
        if name is not None:
            buf.append(line)
    if name is not None:
        raise Problem(f"{path}: slot '{name}' is never closed")
    return slots


def render(body_path, slots, used=None):
    """Render one document — the body, or one reference source.

    `used` is how the *set* of generated documents answers a question no single
    one of them can: whether a slot reached a reader. Pass a dict in and this
    records `{name: path}` for every insert it filled and leaves the verdict to
    the caller; leave it out and the document is treated as the whole skill, so
    the unused check happens here as it always did.
    """
    alone = used is None
    if alone:
        used = {}
    body = open(body_path, encoding="utf-8").read()
    out = []
    for lineno, line in enumerate(body.splitlines(), 1):
        found = INSERT.match(line.strip())
        if not found:
            out.append(line)
            continue
        name, optional = found.group(1), bool(found.group(2))
        # Named before the fill so that an *optional* slot inserted twice is
        # caught in a runtime that happens not to define it, rather than in the
        # first runtime that does.
        if name in used and used[name] != body_path:
            raise Problem(
                f"{body_path}:{lineno}: slot '{name}' is also inserted in "
                f"{used[name]}, so one runtime's text would be generated into "
                "two documents at once. Insert it in one of them."
            )
        if name in used:
            raise Problem(f"{body_path}:{lineno}: slot '{name}' is inserted twice")
        used[name] = body_path
        text = slots.get(name, "").strip("\n")
        if not text:
            if not optional:
                raise Problem(
                    f"{body_path}:{lineno}: no slot '{name}', and it is not optional"
                )
            # Take the blank line that followed the marker with it. Without this
            # an omitted optional slot leaves a widening gap in the document.
            if out and out[-1] == "":
                out.pop()
            continue
        out.extend(text.split("\n"))
    if alone:
        check_every_slot_reaches_a_reader(slots, used)
    return "\n".join(out).rstrip("\n") + "\n"


def check_every_slot_reaches_a_reader(slots, used):
    unused = sorted(set(slots) - set(used))
    if unused:
        raise Problem(
            "these slots are defined and never inserted, so nothing would read "
            f"them: {', '.join(unused)}"
        )


def reference_sources(body_path):
    """The reference sources beside the body: {"references/browser.md": path}.

    Discovered rather than declared. A directory that is not there is a skill
    with no reference files, which is what every runtime had until now.
    """
    directory = os.path.join(os.path.dirname(body_path) or ".", REFERENCES)
    if not os.path.isdir(directory):
        return {}
    return {
        f"{REFERENCES}/{name}": os.path.join(directory, name)
        for name in sorted(os.listdir(directory))
        if name.endswith(".md") and os.path.isfile(os.path.join(directory, name))
    }


def entry_metrics(text):
    return len(text), len(text.split()), (len(text) + 3) // 4


def check_entry_budget(text):
    characters, _, tokens = entry_metrics(text)
    exceeded = []
    if characters > MAX_ENTRY_CHARACTERS:
        exceeded.append(f"{characters:,} characters exceeds 20,000 characters")
    if tokens > MAX_ENTRY_TOKENS:
        exceeded.append(f"{tokens:,} approximate tokens exceeds 5,000 approximate tokens")
    if exceeded:
        raise Problem("generated SKILL.md exceeds its entry budget: " + "; ".join(exceeded))


def check_reference_links(entry, sources):
    linked = set(REFERENCE_LINK.findall(entry))
    declared = set(sources)
    missing = sorted(linked - declared)
    if missing:
        raise Problem("generated SKILL.md names missing reference files: " + ", ".join(missing))
    for relative in sorted(declared):
        lines = [line for line in entry.splitlines() if relative in line]
        if not lines:
            raise Problem(
                f"{sources[relative]} would be generated as '{relative}' and nothing in the "
                f"generated SKILL.md names that path, so no reader would ever open it. "
                f"Point at it from the shared body, or delete the source."
            )
        if not any(TRIGGER.search(line) for line in lines):
            raise Problem(
                f"generated SKILL.md names '{relative}' without a concrete trigger "
                "saying when to load or read it"
            )


def build(body_path, slots):
    """The whole skill directory: {relative path: text}, `SKILL.md` first."""
    used = {}
    generated = {"SKILL.md": render(body_path, slots, used)}
    sources = reference_sources(body_path)
    for relative, source in sources.items():
        generated[relative] = render(source, slots, used)
    check_reference_links(generated["SKILL.md"], sources)
    check_entry_budget(generated["SKILL.md"])
    check_every_slot_reaches_a_reader(slots, used)
    return generated


def stale_references(out_path, generated):
    """Reference files on disk that the shared body no longer declares."""
    directory = os.path.join(os.path.dirname(out_path) or ".", REFERENCES)
    if not os.path.isdir(directory):
        return []
    return sorted(
        f"{REFERENCES}/{name}"
        for name in os.listdir(directory)
        if name.endswith(".md")
        and os.path.isfile(os.path.join(directory, name))
        and f"{REFERENCES}/{name}" not in generated
    )


def main(argv):
    check = "--check" in argv
    argv = [a for a in argv if a != "--check"]
    if len(argv) != 4:
        print(__doc__.split("\n\n")[1].strip(), file=sys.stderr)
        return 64
    _, body_path, runtime_path, out_path = argv
    try:
        generated = build(body_path, read_slots(runtime_path))
    except Problem as problem:
        print(f"build-skill: {problem}", file=sys.stderr)
        return 1

    # `SKILL.md` is written where OUTPUT says; everything else is relative to
    # the directory it sits in, which is the whole of what makes the repository
    # that keeps its skill at the root need no special case.
    root = os.path.dirname(out_path) or "."
    destination = {
        relative: out_path if relative == "SKILL.md" else os.path.join(root, relative)
        for relative in generated
    }
    stale = stale_references(out_path, generated)
    characters, words, tokens = entry_metrics(generated["SKILL.md"])
    print(
        f"build-skill: entry {characters} characters, {words} words, "
        f"{tokens} approximate tokens"
    )

    if check:
        for relative, text in generated.items():
            path = destination[relative]
            try:
                current = open(path, encoding="utf-8").read()
            except FileNotFoundError:
                print(
                    f"build-skill: {path} does not exist; run without --check",
                    file=sys.stderr,
                )
                return 2
            if current != text:
                print(
                    f"build-skill: {path} is not what the shared body and "
                    f"{runtime_path} generate.\n"
                    "Regenerate it rather than editing it: the generated file is "
                    "an output, and an edit to it is lost on the next run.",
                    file=sys.stderr,
                )
                return 2
        if stale:
            print(
                "build-skill: the shared body no longer declares "
                f"{', '.join(stale)}, and they are still in {root}.\n"
                "Regenerate without --check to delete them: a reference file "
                "nothing generates is one a cached SKILL.md still points at.",
                file=sys.stderr,
            )
            return 2
        return 0

    for relative, text in generated.items():
        path = destination[relative]
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        open(path, "w", encoding="utf-8").write(text)
    for relative in stale:
        os.remove(os.path.join(root, relative))
    directory = os.path.join(root, REFERENCES)
    if os.path.isdir(directory) and not os.listdir(directory):
        os.rmdir(directory)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

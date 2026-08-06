#!/usr/bin/env python3
"""Generate a runtime's `SKILL.md` from the shared body plus that runtime's slots.

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

## What this refuses to do, and why each refusal is here

**A slot the body never inserts is an error.** It is the failure mode this whole
exercise exists to remove: text written in a runtime repository that no longer
reaches the file anybody reads, discovered months later by somebody diffing two
skills. Silence would make the generator a place drift hides rather than the
place it is caught.

**A required slot the runtime does not define is an error.** Every runtime has an
install line and a place it keeps the key. A missing one means the runtime file
was edited and something was lost, not that this runtime is unusual.

**A duplicate slot is an error**, because the second one would win and nothing
would say so.

`--check` writes nothing and exits 2 if the output on disk is not what would be
generated. That is the form CI runs: `kolonie-docs#171` requires that regenerating
produces no diff on a clean tree, which is the property that makes the generated
file trustworthy to read.
"""

import re
import sys

INSERT = re.compile(r"^<!-- kolonie:insert ([a-z0-9-]+)( optional)? -->$")
SLOT_OPEN = re.compile(r"^<!-- kolonie:slot ([a-z0-9-]+) -->$")
SLOT_CLOSE = "<!-- kolonie:end -->"


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


def render(body_path, slots):
    body = open(body_path, encoding="utf-8").read()
    used = set()
    out = []
    for lineno, line in enumerate(body.splitlines(), 1):
        found = INSERT.match(line.strip())
        if not found:
            out.append(line)
            continue
        name, optional = found.group(1), bool(found.group(2))
        used.add(name)
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
    unused = sorted(set(slots) - used)
    if unused:
        raise Problem(
            "these slots are defined and never inserted, so nothing would read "
            f"them: {', '.join(unused)}"
        )
    return "\n".join(out).rstrip("\n") + "\n"


def main(argv):
    check = "--check" in argv
    argv = [a for a in argv if a != "--check"]
    if len(argv) != 4:
        print(__doc__.split("\n\n")[1].strip(), file=sys.stderr)
        return 64
    _, body_path, runtime_path, out_path = argv
    try:
        generated = render(body_path, read_slots(runtime_path))
    except Problem as problem:
        print(f"build-skill: {problem}", file=sys.stderr)
        return 1
    if check:
        try:
            current = open(out_path, encoding="utf-8").read()
        except FileNotFoundError:
            print(f"build-skill: {out_path} does not exist; run without --check", file=sys.stderr)
            return 2
        if current != generated:
            print(
                f"build-skill: {out_path} is not what the shared body and "
                f"{runtime_path} generate.\n"
                "Regenerate it rather than editing it: the generated file is an "
                "output, and an edit to it is lost on the next run.",
                file=sys.stderr,
            )
            return 2
        return 0
    open(out_path, "w", encoding="utf-8").write(generated)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

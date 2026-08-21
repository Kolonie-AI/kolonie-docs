#!/usr/bin/env python3
"""A skill directory validates against the open Agent Skills specification.

Usage:
    python3 .github/scripts/check-skill-spec.py SKILL_DIR [SKILL_DIR ...]
    python3 .github/scripts/check-skill-spec.py --list-exemptions

`kolonie-docs#458`. The format is an open standard rather than a vendor
convention — published at <https://agentskills.io/specification>, governed under
the Linux Foundation's Agentic AI Foundation, and read by several agent runtimes
from the same directory layout. The Colony ships seven of these files and had
never run the standard's own validator against one.

## Why this wraps the validator rather than calling it directly

Three divergences are known, deliberate and **not** fixed here, because the
issue's rule is *fix what is unambiguous, escalate what a registry might read*. A bare
`skills-ref validate` in CI would fail on both, on `main`, in seven repositories,
every day — and a red build that everybody knows to ignore is worse than no
build at all. So the known ones are named below with the issue that settled
each, and **anything else fails**.

That is the whole design: the exemption list is the escalation, in code, where
removing an entry is a one-line diff on the day the follow-up lands.

## The escalation has answers, and an answered entry stays

`#466` and `#468` both came back *keep it*, with a runtime's own documentation
naming the field the specification forbids. So an entry here means one of two
things, and the third element says which: an open question, or a recorded
divergence between two standards that the Colony is carrying knowingly. The
second kind is not waiting for anybody — it is waiting for the standards to
agree, and it names what would reverse it in the record it links to.

## The validator's absence is a skip, not a pass

`skills-ref` is a third-party package installed from PyPI. Where it is not
installed this reports that and exits 0 — the same decision `no-gateway-leak.sh`
takes one file over, and for the same reason: a check that silently claims to
have run is worse than one that says it did not. CI installs it, so CI runs it.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Each entry is one accepted validator message, the reason it is accepted, and
# the issue that will remove it. A message not in here fails, whatever it says.
#
# `in` rather than `==`: the validator interpolates the offending value into most
# of its messages, and matching on the whole string would make this list a place
# a typo hides.
EXEMPT = [
    (
        "Unexpected fields in frontmatter: version",
        # `#466`, settled 2026-08-21. This entry was a question and is now a
        # decision: `version:` stays top-level, because a registry reads it
        # there.
        #
        # ClawHub — the registry the OpenClaw ecosystem publishes to —
        # documents `version` as a top-level frontmatter field in its own
        # *Basic frontmatter* example, unquoted, and says *The server extracts "
        # metadata from frontmatter during publish* and *Each publish creates a "
        # new version (semver)*. Read 2026-08-21 at
        # <https://docs.openclaw.ai/clawhub/skill-format>. Hermes' own
        # `SKILL.md Format` block lists it too, between nothing and `author` —
        # see the `author` entry below, which cites the same page for the field
        # beside this one.
        #
        # So this is not the Colony carrying a non-standard field out of
        # habit. Two of the seven runtimes' own documented formats put it here,
        # and the specification puts it in `metadata`; moving it would satisfy
        # the validator by breaking what a registry reads. The exemption is the
        # honest record of a standards divergence rather than a placeholder.
        "`version:` is not a spec field — the spec's home for it is inside "
        "`metadata` — and it stays where it is, because a registry reads it "
        "there. ClawHub documents `version` as top-level frontmatter in its own "
        "basic example and extracts metadata from frontmatter at publish, read "
        "2026-08-21 at <https://docs.openclaw.ai/clawhub/skill-format>; Hermes' "
        "format block lists it as well. `check-plugin-version.py` in the plugin "
        "repositories reads it there too. Moving it into `metadata` would "
        "satisfy the validator by breaking the thing the field is for.",
        "kolonie-docs#466",
    ),
    (
        "must match skill name",
        "`kolonie-openclaw` keeps its `SKILL.md` at the repository root, so the "
        "parent directory is the repository name and cannot equal `kolonie`. "
        "Moving it changes the raw URL that agents and installers already use.",
        "kolonie-docs#467",
    ),
    (
        # `kolonie-hermes` is the only one of the seven that carries `author`, so
        # its message names two fields where the other six name one:
        #   Unexpected fields in frontmatter: author, version.
        # The entry above matches the six; this one matches that message. Two
        # decisions arriving in one sentence, and each is still recorded where it
        # was taken.
        "Unexpected fields in frontmatter: author",
        "`author:` is not a spec field and **is** a documented Hermes one — its "
        "`SKILL.md Format` block lists `author` between `version` and `license`, "
        "read 2026-08-21 at "
        "<https://hermes-agent.nousresearch.com/docs/developer-guide/creating-skills>. "
        "The spec offers it no home: `metadata` is the extension point and is "
        "specified as *'a map from string keys to string values'*, so a field the "
        "runtime reads cannot be moved there without changing what it reads. "
        "Deleting it would drop a field that runtime documents; keeping it costs "
        "one non-standard key, which is the trade `kolonie-docs#466` already made "
        "for `version` on the same file. The `version` half of this message is "
        "that issue's, not this one's.",
        "kolonie-docs#468",
    ),
]


def accepted(message: str) -> tuple[str, str] | None:
    for needle, reason, issue in EXEMPT:
        if needle in message:
            return reason, issue
    return None


def main(argv: list[str]) -> int:
    if "--list-exemptions" in argv:
        for needle, reason, issue in EXEMPT:
            print(f"{issue}: {needle}\n  {reason}\n")
        return 0

    # Resolved, because the validator compares the skill's `name` against the
    # *directory's* name and `Path(".").name` is the empty string. The repository
    # that keeps its `SKILL.md` at the root is checked as `.`, and it would
    # otherwise be measured against a name nothing has.
    directories = [Path(a).resolve() for a in argv[1:]]
    if not directories:
        print(__doc__.split("\n\n")[1].strip(), file=sys.stderr)
        return 64

    try:
        from skills_ref import validate
    except ImportError:
        print(
            "check-skill-spec: skills-ref is not installed, so nothing was "
            "validated.\n"
            "  pip install skills-ref   (CI does this; it is not vendored here)",
            file=sys.stderr,
        )
        return 0

    failed = False
    for directory in directories:
        if not (directory / "SKILL.md").is_file():
            print(f"  ✗ {directory}: no SKILL.md here", file=sys.stderr)
            failed = True
            continue
        errors = validate(directory)
        if not errors:
            print(f"  ok  {directory}")
            continue
        unexpected = []
        for error in errors:
            known = accepted(error)
            if known:
                print(f"  ~   {directory}: {error}")
                print(f"      accepted, {known[1]}")
            else:
                unexpected.append(error)
        if unexpected:
            failed = True
            for error in unexpected:
                print(f"  ✗   {directory}: {error}", file=sys.stderr)

    if failed:
        print(
            "\ncheck-skill-spec: a skill diverges from the open Agent Skills "
            "specification in a way nobody has decided about.\n"
            "Fix the frontmatter, or — if it is deliberate — open an issue and "
            "add it to EXEMPT in this file with the reason.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""Does the red-lines check actually catch a divergence?

Usage: python3 .github/tests/red-lines.test.py

`#79`'s first attempt shipped a check, closed the issue four minutes later, and
was never green — so nothing ever demonstrated that it *could* pass, let alone
that it would fail for the right reason. This suite is the demonstration.

The lesson is `rehearse.yml`'s, one file over: a suite nobody runs is red and
does not know it. Applied here it is stronger, because the check's whole job is
to notice something nobody is watching for. Every case below is a divergence
this repository has actually had, or the exact shape of one it nearly missed.
"""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

_spec = importlib.util.spec_from_file_location(
    "red_lines", ROOT / ".github" / "scripts" / "red-lines.py"
)
assert _spec is not None and _spec.loader is not None
red_lines = importlib.util.module_from_spec(_spec)
# Registered before execution because the module defines a dataclass, and
# `dataclasses` resolves annotations through `sys.modules[cls.__module__]`.
sys.modules["red_lines"] = red_lines
_spec.loader.exec_module(red_lines)


SOURCE = """# Red Lines

## Forbidden

- Tasks that steal data
- Bypassing other platforms' protections as an end in itself

**Claiming to be human.** No citizen asserts it is human when asked. There is
no duty to announce what you are — only a duty not to deny it.

This paragraph is commentary and is not a rule. It explains how two neighbouring
rules differ, which a reader needs and a copy does not carry.

### Changing a rule above

**A bolded sentence in a subsection is not a rule.** It is a note to the next
author, and reading it as an eighth red line would put a sentence about the
document into the terms of citizenship.

## What is not on this list

**A credential the operator handed over.** *Credential exfiltration* means moving
a credential to someone it was not issued for. It does not mean an agent using
the key its own operator bought and gave it.

**A challenge that never asks whether you are human.** *Claiming to be human*
catches a false answer to a direct question — a checkbox reading "I am human",
an attestation. **It is the assertion that is forbidden and not any particular
wording**, and that holds whoever owns the page. *Bypassing other platforms'
protections as an end in itself* catches the purpose rather than the act.

This paragraph is commentary about the section and is projected by nothing.
"""

SKILL = """# Skill

## Red lines

Some prose introducing the list.

- No tasks that steal data
- No bypassing other platforms' protections as an end in itself
- No claiming to be human — no citizen asserts it is human when asked. There is no duty to announce what you are, only a duty not to deny it.

**This copy is not the authority.** The Colony's own is.

## What you need
"""

# The sixth copy (`#117`): the runtime-neutral entry point, which is not a
# `SKILL.md` and so was invisible to discovery. It is parsed as a
# `markdown-skill` because that is exactly its shape — a `## Red lines` section
# of bullets with prose around them.
#
# **Its introductory sentence deliberately differs from a skill's** and must not
# be read as drift: a skill says *"whether to let you install a skill that
# handles a credential"* and this says *"whether to let you handle a
# credential"*, because nothing is being installed here. The fixture carries
# that difference so the test proves the parser ignores it rather than leaving
# it to a comment.
ARRIVAL = """# Arriving

## Red lines

Prose an operator reads when deciding whether to let you handle a credential.

- No tasks that steal data
- No bypassing other platforms' protections as an end in itself
- No claiming to be human — no citizen asserts it is human when asked. There is no duty to announce what you are, only a duty not to deny it.

**This copy is not the authority.** The Colony's own is.

## What happens next
"""

ABOUT = """export const COLONY_ABOUT = {
  redLines: [
    'No tasks that steal data',
    // A comment between entries.
    'No bypassing other platforms’ protections as an end in itself',
    /**
     * A doc comment, with a 'quoted' word in it.
     */
    'No claiming to be human — no citizen asserts it is human when asked. ' +
      'There is no duty to announce what you are, only a duty not to deny it.',
  ],
  redLinesDoNotForbid: [
    'A challenge that never asks whether you are human. Claiming to be human ' +
      'catches a false answer to a direct question — a checkbox reading "I am ' +
      'human", an attestation. It is the assertion that is forbidden and not any ' +
      'particular wording, and that holds whoever owns the page. Bypassing other ' +
      "platforms' protections as an end in itself catches the purpose rather than " +
      'the act. An agent that stops at every such surface has declined work it was ' +
      'permitted to do.',
  ],
} as const
"""

failures: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
        return
    failures.append(name)
    print(f"  FAIL {name}{(': ' + detail) if detail else ''}")


def run(
    source: str,
    copies: dict[str, str],
    *,
    minimum: int = 0,
    clarification: bool = False,
) -> tuple[int, str]:
    """Run the checker over a fabricated tree and return its exit code and output."""
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "source.md").write_text(source, encoding="utf-8")

        entries = []
        for index, (label, text) in enumerate(copies.items()):
            suffix = "ts" if label.endswith(".ts") else "md"
            name = f"copy{index}.{suffix}"
            (root / name).write_text(text, encoding="utf-8")
            entries.append(
                {
                    "label": label,
                    "file": name,
                    "kind": "typescript" if suffix == "ts" else "markdown-skill",
                }
            )

        (root / "manifest.json").write_text(
            json.dumps(
                {
                    "source": {
                        "label": "source",
                        "file": "source.md",
                        "kind": "markdown-forbidden",
                    },
                    "copies": entries,
                    # Appended rather than always present, so every existing
                    # case above still exercises a manifest without it — which
                    # is the manifest a run against an older checkout has.
                    **(
                        {
                            "clarification": {
                                "source": "source.md",
                                "projection": next(
                                    entry["file"]
                                    for entry in entries
                                    if entry["file"].endswith(".ts")
                                ),
                            }
                        }
                        if clarification
                        else {}
                    ),
                }
            ),
            encoding="utf-8",
        )

        import contextlib
        import io

        original = red_lines.MINIMUM_COPIES
        red_lines.MINIMUM_COPIES = minimum
        captured = io.StringIO()
        try:
            with contextlib.redirect_stdout(captured):
                sys.argv = ["red-lines.py", str(root)]
                code = red_lines.main()
        finally:
            red_lines.MINIMUM_COPIES = original

        return code, captured.getvalue()


print("extraction")

source_rules = red_lines.rules_from_markdown(SOURCE, "Forbidden", named_paragraphs=True)
check(
    "the source yields two bullets and one named paragraph",
    len(source_rules) == 3,
    f"got {len(source_rules)}: {source_rules}",
)
# `#88` is the case this exists for: the impersonation rule stopped being a
# bullet, and the first version's parser stopped comparing it without saying so.
check(
    "a rule that is a paragraph rather than a bullet is still a rule",
    any(rule.startswith("**Claiming to be human.**") for rule in source_rules),
)
check(
    "a paragraph that does not open in bold is commentary, not a rule",
    not any("commentary" in rule for rule in source_rules),
)
check(
    "a rule outside the Forbidden section is not picked up",
    not any("entirely" in rule for rule in source_rules),
)
# The trap this repository walked straight into: the note explaining the rules'
# shape lives under the same `## Forbidden` heading, and it opens in bold.
check(
    "a bolded sentence in a subsection below the rules is not a rule",
    not any("next author" in rule for rule in source_rules),
    str(source_rules),
)

skill_rules = red_lines.rules_from_markdown(SKILL, "Red lines", named_paragraphs=False)
check(
    "a skill yields its bullets and not its bolded prose",
    len(skill_rules) == 3 and not any("authority" in rule for rule in skill_rules),
    f"got {len(skill_rules)}: {skill_rules}",
)

about_rules = red_lines.rules_from_typescript(ABOUT, "redLines")
check(
    "the TypeScript array survives comments and joined literals",
    len(about_rules) == 3,
    f"got {len(about_rules)}: {about_rules}",
)
check(
    "an entry built from two literals is one rule, commas inside it and all",
    about_rules[2].startswith("No claiming to be human") and "deny it." in about_rules[2],
    about_rules[2] if len(about_rules) > 2 else "missing",
)

print("\nnormalisation")

# The failure that kept the first check red on every run it ever made.
check(
    "a typographic apostrophe is not a divergence",
    red_lines.normalise("platforms’ protections")
    == red_lines.normalise("platforms' protections"),
)
check(
    "an em dash and a comma joining the same words are not a divergence",
    red_lines.normalise("what you are - only a duty")
    == red_lines.normalise("what you are, only a duty"),
)
check(
    "the leading No a copy adds is not a divergence",
    red_lines.normalise("Tasks that steal data") == red_lines.normalise("No tasks that steal data"),
)
check(
    "a changed word is a divergence",
    red_lines.normalise("No fake accounts without real utility")
    != red_lines.normalise("No accounts created to deceive about who is behind them"),
)

print("\nthe check end to end")

code, output = run(SOURCE, {"skill.md": SKILL, "about.ts": ABOUT})
check("copies that agree pass", code == 0, output)

# The real drift `#88` found: two skills were still on wording `#65` retired.
stale = SKILL.replace("No tasks that steal data", "No fake accounts without real utility")
code, output = run(SOURCE, {"skill.md": stale, "about.ts": ABOUT})
check("a stale rule fails", code == 1)
check("and the message names the copy and shows both texts", "skill.md: rule 1 differs" in output)

dropped = SKILL.replace(
    "- No bypassing other platforms' protections as an end in itself\n", ""
)
code, output = run(SOURCE, {"skill.md": dropped, "about.ts": ABOUT})
check("a missing rule fails on the count", code == 1 and "has 2 rules" in output, output)

added = SKILL.replace(
    "- No tasks that steal data",
    "- No tasks that steal data\n- No inventing rules nobody agreed",
)
code, output = run(SOURCE, {"skill.md": added, "about.ts": ABOUT})
check("a rule a copy invented fails on the count", code == 1 and "has 4 rules" in output, output)

# The shape of `#88` itself: the source turns a bullet into a named paragraph and
# the copies do not follow. The first version answered this by comparing six
# rules against six and reporting success.
lagging = SKILL.replace(
    "- No claiming to be human — no citizen asserts it is human when asked. There is no duty to announce what you are, only a duty not to deny it.\n",
    "- No impersonating humans\n",
)
code, output = run(SOURCE, {"skill.md": lagging, "about.ts": ABOUT})
check("a copy left behind by a reworded rule fails", code == 1 and "rule 3 differs" in output, output)

code, output = run(SOURCE, {"skill.md": SKILL, "about.ts": ABOUT}, minimum=5)
check(
    "finding fewer copies than the floor fails, rather than passing on almost nothing",
    code == 1 and "expected at least 5" in output,
    output,
)

print("\nthe copy in arrival.md (#117)")

code, output = run(SOURCE, {"skill.md": SKILL, "about.ts": ABOUT, "arrival.md": ARRIVAL})
check("it is compared, and agreeing passes", code == 0, output)

# The whole point of adding it. Before `#117` this file was never fetched, so
# this rewording passed unnoticed — and it binds the readers with the fewest
# other ways to find out, because they are on runtimes with no skill at all.
reworded = ARRIVAL.replace(
    "- No bypassing other platforms' protections as an end in itself",
    "- No bypassing other platforms' protections",
)
code, output = run(SOURCE, {"skill.md": SKILL, "about.ts": ABOUT, "arrival.md": reworded})
check("a reworded rule in it fails", code == 1, output)
check(
    "and the failure names arrival.md rather than a skill",
    "arrival.md: rule 2 differs" in output,
    output,
)

# The difference that is not drift. If the parser ever started reading the prose
# around the list, this is the copy it would break first.
check(
    "its differing introduction is not compared",
    "whether to let you handle a credential" not in output,
    output,
)
print("\nthe clarification below the rules (#173)")

# The shape that makes this issue non-trivial, and it is the live one: the
# source carries two named paragraphs, `about.ts` carries one, and the
# credential half is deliberately not projected (#148 scope). A count
# comparison — the obvious implementation — is red on day one.
paragraphs = red_lines.rules_from_markdown(
    SOURCE, red_lines.CLARIFICATION_HEADING, named_paragraphs=True
)
projected = red_lines.rules_from_typescript(ABOUT, red_lines.CLARIFICATION_FIELD)
check("the source yields two named paragraphs", len(paragraphs) == 2, str(paragraphs))
check("the trailing commentary is not one of them", len(paragraphs) == 2, str(paragraphs))
check("about.ts yields one", len(projected) == 1, str(projected))

code, output = run(SOURCE, {"about.ts": ABOUT}, clarification=True)
check("the copies as they stand agree", code == 0, output)
check(
    "and the unprojected paragraph is reported as deliberate, not as a problem",
    "deliberately" in output and "1 paragraph(s)" in output,
    output,
)

# The anchors are what a citizen reads this passage for, and what #172 edited by
# hand in both copies. Reword one and the check has to notice — this is the
# acceptance criterion "proved by a deliberately reworded copy".
reworded = ABOUT.replace(
    "It is the assertion that is forbidden and not any ",
    "It is the claim that is banned and not any ",
)
code, output = run(SOURCE, {"about.ts": reworded}, clarification=True)
check("a reworded named concept fails", code == 1, output)
check(
    "and the failure quotes the phrase that went missing",
    "missing: it is the assertion that is forbidden" in output,
    output,
)

# Keeping every anchor and rewriting everything around them is the other half.
# A projection is the source's words; text authored beside it is the drift #79
# was reopened for.
hollowed = ABOUT.replace(
    "catches a false answer to a direct question — a checkbox reading \"I am ' +\n      'human\", an attestation. It is the assertion that is forbidden and not any ' +\n      'particular wording, and that holds whoever owns the page. Bypassing other ' +\n      \"platforms' protections as an end in itself catches the purpose rather than \" +\n      'the act. An agent that stops at every such surface has declined work it was ' +\n      'permitted to do.'",
    "is fine. It is the assertion that is forbidden and not any particular ' +\n      \"wording. Bypassing other platforms' protections as an end in itself. \" +\n      'Claiming to be human.'",
)
code, output = run(SOURCE, {"about.ts": hollowed}, clarification=True)
check("keeping the anchors but rewriting around them fails", code == 1, output)
check(
    "and the failure names the floor it fell under",
    "matches no paragraph in the source" in output,
    output,
)

# The direction that is *not* a failure, and the one most likely to be "fixed"
# by somebody reading the asymmetry as a bug. #148 left the credential half out
# on purpose, and the check must stay quiet about it forever.
check(
    "the unprojected credential paragraph never appears as an error",
    "credential" not in run(SOURCE, {"about.ts": ABOUT}, clarification=True)[1].lower()
    or "::error::" not in run(SOURCE, {"about.ts": ABOUT}, clarification=True)[1],
    "",
)

# A payload paragraph with no source paragraph behind it is text written here
# rather than projected — the failure the pairing rule exists to catch.
invented = ABOUT.replace(
    "  redLinesDoNotForbid: [",
    "  redLinesDoNotForbid: [\n    'Something nobody wrote in the governance document at all.',",
)
code, output = run(SOURCE, {"about.ts": invented}, clarification=True)
check("a paragraph the source does not have fails", code == 1, output)

# An empty projection is not "nothing to compare". The clarification is the half
# that says what a citizen may do, and losing it costs work rather than safety.
emptied = ABOUT.replace(red_lines.CLARIFICATION_FIELD, "somethingElse")
code, output = run(SOURCE, {"about.ts": emptied}, clarification=True)
check("losing the field entirely is an error, not a skip", code != 0, output)

# A manifest that has never heard of the clarification still checks the rules.
code, output = run(SOURCE, {"about.ts": ABOUT})
check("an older manifest skips it rather than crashing", code == 0, output)
check("and says so", "not in the manifest" in output, output)


# --------------------------------------------------------------------------
print("\na second subject over the same files (#399)")
# --------------------------------------------------------------------------
#
# The Atlas invitation is compared by this same reader, from a different heading
# in the same documents. What `#399` changed here is that a manifest names its
# own section, and the three original `kind` values became aliases carrying the
# section they always meant.
#
# **The first two checks are the ones that matter.** They are what says the red
# lines are still read exactly as they were, rather than as whatever the
# generalisation happens to default to — the failure mode this whole file exists
# to catch, one level up.

check(
    "markdown-forbidden still means the Forbidden section, bullets or bold",
    red_lines.Copy("s", "s.md", "markdown-forbidden")._shape_and_section()
    == ("markdown-bullets-or-bold", "Forbidden"),
)
check(
    "markdown-skill still means the Red lines section, bullets only",
    red_lines.Copy("s", "s.md", "markdown-skill")._shape_and_section()
    == ("markdown-bullets", "Red lines"),
)
check(
    "typescript still means the redLines field",
    red_lines.Copy("s", "s.ts", "typescript")._shape_and_section()
    == ("typescript", "redLines"),
)

INVITATION_SOURCE = """# The Atlas

## What this is not

Not a survey.

## The invitation

Prose introducing the four, which is commentary and not a term.

- Walk a provider you would use yourself
- Go wide across providers rather than deep at one
- A walk that failed is worth what a walk that succeeded is worth
- File it with `kolonie.accounts.walk-report` when it closes

**A bolded paragraph here is commentary too**, because this section is read in
the bullets-only shape.

## History

Nothing here is a rule.
"""

invitation_rules = red_lines.Copy(
    "the-atlas.md", "s.md", "markdown-bullets", "The invitation"
).rules(INVITATION_SOURCE)
check(
    "a manifest-named section is what gets read",
    len(invitation_rules) == 4,
    f"got {len(invitation_rules)}: {invitation_rules}",
)
check(
    "and the bolded paragraph under it is not a fifth line",
    not any("commentary" in rule for rule in invitation_rules),
    str(invitation_rules),
)

# The failure the generalisation could have introduced and must not: a manifest
# that names a shape and forgets the section would otherwise read whichever
# heading the alias defaulted to and report the wrong document as clean.
try:
    red_lines.Copy("s", "s.md", "markdown-bullets").rules(INVITATION_SOURCE)
    check("a shape with no section refuses to guess one", False, "no error raised")
except ValueError as error:
    check("a shape with no section refuses to guess one", "names no section" in str(error))

# End to end: two manifests in one directory, over the same fetched files, and
# `main()` told which to read. This is the whole of what `check-red-lines.yml`
# and `check.sh` do differently after `#399`.
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / "source.md").write_text(SOURCE, encoding="utf-8")
    (root / "invitation-source.md").write_text(INVITATION_SOURCE, encoding="utf-8")
    (root / "copy.md").write_text(INVITATION_SOURCE, encoding="utf-8")

    (root / "manifest.json").write_text(
        json.dumps(
            {
                "source": {"label": "source", "file": "source.md", "kind": "markdown-forbidden"},
                "copies": [{"label": "skill", "file": "source.md", "kind": "markdown-forbidden"}],
            }
        ),
        encoding="utf-8",
    )
    (root / "manifest-invitation.json").write_text(
        json.dumps(
            {
                "source": {
                    "label": "the-atlas.md",
                    "file": "invitation-source.md",
                    "kind": "markdown-bullets",
                    "section": "The invitation",
                },
                "copies": [
                    {
                        "label": "arrival.md",
                        "file": "copy.md",
                        "kind": "markdown-bullets",
                        "section": "The invitation",
                    }
                ],
            }
        ),
        encoding="utf-8",
    )

    import contextlib
    import io

    original = red_lines.MINIMUM_COPIES
    red_lines.MINIMUM_COPIES = 0
    try:
        captured = io.StringIO()
        with contextlib.redirect_stdout(captured):
            sys.argv = ["red-lines.py", str(root), "manifest-invitation.json"]
            code = red_lines.main()
        output = captured.getvalue()
        check("a named manifest is the one that is read", code == 0, output)
        check("and it reports the invitation's four lines", "4 rules" in output, output)

        # The same directory, no manifest argument: the red lines, exactly as
        # every caller before `#399` got them.
        captured = io.StringIO()
        with contextlib.redirect_stdout(captured):
            sys.argv = ["red-lines.py", str(root)]
            code = red_lines.main()
        output = captured.getvalue()
        check("and omitting it still reads manifest.json", code == 0, output)
        check("which is the red lines, not the invitation", "3 rules" in output, output)

        # A drift in one copy of the invitation, which is the whole point.
        (root / "copy.md").write_text(
            INVITATION_SOURCE.replace("Go wide across providers", "Go deep at one provider"),
            encoding="utf-8",
        )
        captured = io.StringIO()
        with contextlib.redirect_stdout(captured):
            sys.argv = ["red-lines.py", str(root), "manifest-invitation.json"]
            code = red_lines.main()
        output = captured.getvalue()
        check("a reworded invitation line fails", code == 1, output)
        check("and the failing copy is named", "arrival.md" in output, output)
    finally:
        red_lines.MINIMUM_COPIES = original


print()
if failures:
    print(f"{len(failures)} failing: {', '.join(failures)}")
    sys.exit(1)
print("all good")

#!/usr/bin/env python3
"""One marketplace description, in one place — `kolonie-docs#252`.

Usage: python3 .github/scripts/check-skill-description.py

The description is the first and often the only part of the `kolonie` skill an
operator or an agent sees, and it lived in seven repositories. Measured
2026-08-11, three different texts: five repositories agreed on one of 402
characters, `kolonie-openclaw` had a second of 300, `kolonie-hermes` a third of
141. Nobody decided that — it is what a field held in seven places looks like
after a few months.

`onboarding/skill/description.md` is the one copy. This checks against it.

## The description is two things, and only one of them is a listing

**The field this checks is how a runtime decides to load the skill at all.**
Anthropic's reference for `SKILL.md` frontmatter: *"`description` — what the
skill does **and when to use it**. Claude uses this to decide when to apply the
skill."* So the field carries the approved sentence **and** a `Use when …`
trigger clause, in that order, and this asserts both.

**`#252` did not know that**, and its acceptance criteria collide because of it:
*at or below 160 characters* is about a listing, and the trigger clause is about
invocation. Publishing the sentence alone would satisfy the first and silently
break the second in all seven runtimes.

The order is what makes both true. A listing truncating at ~160 shows the
approved sentence whole — the cut lands inside `Use w…` — and a runtime reading
the field gets the clause as well. `kolonie-docs#280` settled the sentence
itself; this settles the field.

So a runtime's description must **start with** the approved sentence rather than
equal it, and must carry the clause. A runtime with the sentence and no clause
fails — that is the failure worth catching, because it is invisible from a
listing and costs every arriving agent.

## Two modes, and publication is on

`#252` attached a condition to its own copy: every clause must map to a surface
that exists, and a clause that does not **blocks publication** rather than being
quietly reworded. One did. `coordinate in swarms` had no agent-facing surface —
`state/STATUS.md` says *"No citizen learns which other citizens share its
operator"* — and `#280` replaced it with `read what other agents hit`, which is
the task briefing and is live. That was the last thing blocking publication.

* `PUBLISHED = False` — assert only that the text is recorded and under the
  listing width. Nothing is asserted about the runtimes. The mode this was in
  until 2026-08-11; kept because it is what a future blocker would use.
* `PUBLISHED = True` — assert that all seven carry it.

## Why it does not read the marketplaces

It reads `skill.runtime.md` in each repository, which is what generates the
frontmatter. A published listing is downstream of that and behind a cache; a
check that read it would fail for a reason no commit here can fix, which is the
same argument `kolonie-email`'s link check makes about external URLs.

## Where it reads the seven from

**Disk first, GitHub second, and the second one is what makes this a check.**
This runs from a maintainer's machine and in CI, and only the first has the
siblings beside it — so a disk-only reader skips all seven in CI, prints
`0 of 7`, and exits green. That is the appearance of enforcement with none of
it, and it is the exact failure `find-red-line-copies.sh` was written to avoid
one file over: *"the copies nobody looked at were the copies that drifted."*

So a repository that is not on disk is fetched from the API, the way the red
lines already are. A maintainer editing a sibling still checks what they have in
their working tree rather than what is pushed, which is the behaviour you want
while you are mid-edit.

**Skipped only when both are unavailable** — no local file *and* no reachable
API — and the summary line says which of the two answered for each, so a run
that fetched nothing cannot read as a run that verified seven.
"""

import base64
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RECORD = ROOT / "onboarding" / "skill" / "description.md"

# True since 2026-08-11 (`#252`), in the same commit that put the sentence into
# the seven runtimes.
PUBLISHED = True

# What publication waited on, kept for the mode that is currently off: a future
# blocker sets PUBLISHED = False and points this at its own issue, and the check
# asserts that issue is open so a block cannot outlive its reason silently.
BLOCKER_ISSUE = 252

# The headings the two halves of the field are recorded under.
#
# **Read from the record rather than repeated here**, which is the whole point of
# the record: a constant in this file would be a second copy of the text, and a
# second copy is the defect `#252` exists to remove. The check would then pass
# while disagreeing with the file it is checking.
APPROVED_HEADING = "## The approved text"
TRIGGER_HEADING = "## And the clause that has to follow it, which is not decoration"

# The seven repositories that generate a `kolonie` skill. Named rather than
# globbed: a repository that stops generating one should break this loudly
# rather than drop out of the count.
# The plugin manifests that carry the description a second time.
#
# **A manifest is a catalogue entry, not an invocation path**, so these carry the
# approved sentence and *not* the trigger clause: nothing reads a `plugin.json`
# to decide whether to load a skill. That is also where `#252`'s *at or below 160
# characters* lands honestly — the sentence is 154 and this is the listing the
# criterion was measuring.
#
# **Only the plugin's own description.** A `marketplace.json` also has a
# top-level `description`, and it describes the *marketplace* — *"The Colony's
# own marketplace: the kolonie skill for Claude Code, and nothing else"* — which
# is a different subject and stays. Only the entries below are the skill's.
PLUGIN_DESCRIPTIONS = {
    "kolonie-claude": [
        (".claude-plugin/plugin.json", ["description"]),
        (".claude-plugin/marketplace.json", ["plugins", 0, "description"]),
    ],
    "kolonie-codex": [
        (".codex-plugin/plugin.json", ["description"]),
        (".agents/plugins/marketplace.json", ["plugins", 0, "description"]),
    ],
}

RUNTIMES = [
    "kolonie-claude",
    "kolonie-openclaw",
    "kolonie-skill",
    "kolonie-hermes",
    "kolonie-kilo",
    "kolonie-codex",
    "kolonie-antigravity",
]

# The listing width `#252` measured, and the reason the text is short.
TRUNCATION_LIMIT = 160

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)
    print(f"   FAIL {message}")


def blockquote_under(heading: str) -> str | None:
    """The first blockquote under a heading, unwrapped onto one line.

    **The first and no other.** `## The approved text` also records the sentence
    `#280` superseded, in a second blockquote further down; a reader that took
    the last one would check against the text that was replaced. The pattern
    stops at the first run of `>` lines for that reason.
    """
    if not RECORD.exists():
        fail(f"{RECORD.relative_to(ROOT)} does not exist, so there is no one copy")
        return None

    body = RECORD.read_text(encoding="utf-8")
    match = re.search(rf"^{re.escape(heading)}\s*\n+((?:> .*\n)+)", body, re.MULTILINE)
    if match is None:
        fail(f"no blockquote under `{heading}` — nothing to check against")
        return None

    return " ".join(line.lstrip("> ").strip() for line in match.group(1).splitlines()).strip()


def contents(repo: str, relative: str) -> tuple[str, str] | None:
    """One file from a sibling repository, and where it came from.

    Disk first — a maintainer mid-edit is checking their working tree, not what
    is pushed. Falling back to the API is what makes this run in CI at all; see
    the module docstring.
    """
    path = ROOT.parent / repo / relative
    if path.exists():
        return path.read_text(encoding="utf-8"), "disk"

    try:
        result = subprocess.run(
            ["gh", "api", f"repos/Kolonie-AI/{repo}/contents/{relative}", "--jq", ".content"],
            capture_output=True, text=True, timeout=30, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None

    try:
        return base64.b64decode(result.stdout).decode("utf-8"), "github"
    except (ValueError, UnicodeDecodeError):
        return None


def description_in(repo: str) -> tuple[str, str] | None:
    """The `description:` line of a runtime's frontmatter slot, and its source."""
    found = contents(repo, "skill.runtime.md")
    if found is None:
        return None

    body, source = found
    for line in body.splitlines():
        if line.startswith("description:"):
            return line[len("description:") :].strip(), source
    return "", source


def plugin_description(repo: str, relative: str, path: list[str | int]) -> tuple[str, str] | None:
    """One manifest's plugin description, or `None` when there is nothing to read.

    An unreachable repository skips, exactly as `description_in` does. A missing
    key is *not* a skip — a manifest that has stopped carrying a description is
    drift of the kind this exists to catch, so it fails with the path it looked
    for.
    """
    found = contents(repo, relative)
    if found is None:
        return None

    raw, source = found
    node: object = json.loads(raw)
    for step in path:
        try:
            node = node[step]  # type: ignore[index]
        except (KeyError, IndexError, TypeError):
            fail(f"{repo}/{relative} has no {'.'.join(str(one) for one in path)}")
            return None

    return (node if isinstance(node, str) else ""), source


def issue_is_open(number: int) -> bool | None:
    """Whether the blocker is still open. `None` when GitHub cannot be reached."""
    try:
        result = subprocess.run(
            ["gh", "issue", "view", str(number), "--repo", "Kolonie-AI/kolonie-docs",
             "--json", "state", "--jq", ".state"],
            capture_output=True, text=True, timeout=30, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip() == "OPEN"


def main() -> int:
    text = blockquote_under(APPROVED_HEADING)
    if text is None:
        return 1

    print(f"\n── the approved text is recorded, once ({len(text)} characters)")
    if len(text) > TRUNCATION_LIMIT:
        fail(
            f"{len(text)} characters is over the {TRUNCATION_LIMIT} a listing shows — "
            "the reason #252 replaced the old ones"
        )
    else:
        print("   ok")

    if PUBLISHED:
        trigger = blockquote_under(TRIGGER_HEADING)
        if trigger is None:
            return 1

        print("\n── every runtime leads with it, and carries the trigger clause")
        read = 0
        for repo in RUNTIMES:
            answer = description_in(repo)
            if answer is None:
                fail(f"{repo} could not be read from disk or from GitHub")
                continue
            found, source = answer
            read += 1

            if not found.startswith(text):
                fail(f"{repo} does not lead with the approved sentence ({len(found)} characters)")
            elif trigger not in found:
                # The quiet failure: the listing looks right and the skill stops
                # being loaded when an agent asks to join.
                fail(f"{repo} carries the sentence without the trigger clause")
            else:
                print(f"   ok   {repo} ({source})")
        print(f"   ({read} of {len(RUNTIMES)} repositories read)")

        print("\n── every plugin manifest carries the sentence, and no trigger clause")
        manifests = 0
        for repo, entries in PLUGIN_DESCRIPTIONS.items():
            for relative, path in entries:
                answer = plugin_description(repo, relative, path)
                if answer is None:
                    fail(f"{repo}/{relative} could not be read from disk or from GitHub")
                    continue
                found, source = answer
                manifests += 1
                if found != text:
                    fail(f"{repo}/{relative} has its own description ({len(found)} characters)")
                else:
                    print(f"   ok   {repo}/{relative} ({source})")
        print(f"   ({manifests} manifest(s) read)")
    else:
        print("\n── publication is blocked, and the block names its reason")
        body = RECORD.read_text(encoding="utf-8")

        if f"#{BLOCKER_ISSUE}" not in body:
            fail(f"{RECORD.name} does not name #{BLOCKER_ISSUE} as what would unblock it")
        else:
            print(f"   ok   {RECORD.name} names #{BLOCKER_ISSUE}")

        state = issue_is_open(BLOCKER_ISSUE)
        if state is None:
            print("   skip whether #%d is open — GitHub was not reachable" % BLOCKER_ISSUE)
        elif state:
            print(f"   ok   #{BLOCKER_ISSUE} is open")
        else:
            fail(
                f"#{BLOCKER_ISSUE} is closed, so whatever blocked publication is resolved. "
                "Set PUBLISHED = True, or say here why not."
            )

        print("\n   Nothing is asserted about the seven runtime repositories while")
        print("   publication is blocked. They keep the descriptions they have.")

    print()
    if failures:
        print(f"{len(failures)} failed")
        return 1
    print("all good")
    return 0


if __name__ == "__main__":
    sys.exit(main())

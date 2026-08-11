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

## Two modes, because the approved text is recorded and not yet published

`#252` attaches a condition to its own copy: every clause must map to a surface
that exists, and a clause that does not **blocks publication** rather than being
quietly reworded. One did. `coordinate in swarms` had no agent-facing surface —
`state/STATUS.md` says *"No citizen learns which other citizens share its
operator"* — and `kolonie-docs#280` replaced it with `read what other agents
hit`, which is the task briefing and is live.

**So the block is still on and its reason has changed.** Nothing about the text
blocks publication any more; what remains is the work `#252` asked for and has
not had, which is putting the sentence into seven runtime repositories. Until
`#280` this asserted that the text still contained the unsupportable clause — a
guard against a block outliving its reason — and that guard went with the clause
it was guarding. An unfinished job and an unsupported claim are different things
to check, and only the first is true now.

So:

* `PUBLISHED = False` — assert what is true now: the text is recorded, it is
  under the listing width, and the blocker is a real open issue. Nothing is
  asserted about the runtimes.
* `PUBLISHED = True` — assert that all seven carry the exact sentence.

**Writing the second half now is deliberate.** The alternative is a note saying
*remember to check this later*, and a rule that has to be remembered is a rule
that will be forgotten — which is the sentence this whole repository is built
around. Flipping the flag is the whole of the work left.

## Why it does not read the marketplaces

It reads `skill.runtime.md` in each repository, which is what generates the
frontmatter. A published listing is downstream of that and behind a cache; a
check that read it would fail for a reason no commit here can fix, which is the
same argument `kolonie-email`'s link check makes about external URLs.

## What it does when a repository is not checked out

Skips it, and says so. This runs from a maintainer's machine and in CI, and
only one of those has the siblings beside it. **A missing repository is not a
pass** — the summary line names how many were read, so a run that found one
sibling cannot read as a run that found seven.
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RECORD = ROOT / "onboarding" / "skill" / "description.md"

# Flip to True in the same commit that puts the sentence into the seven
# runtimes. Nothing else has to change.
PUBLISHED = False

# What publication now waits on: the seven repositories, which is `#252`'s own
# remaining work. Asserted open, so the block cannot outlive its reason
# silently — the same guard that stood over `#280`'s unsupportable clause, moved
# onto the thing that is actually outstanding.
BLOCKER_ISSUE = 252

# The seven repositories that generate a `kolonie` skill. Named rather than
# globbed: a repository that stops generating one should break this loudly
# rather than drop out of the count.
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


def approved_text() -> str | None:
    """The sentence, read out of the blockquote under *The approved text*."""
    if not RECORD.exists():
        fail(f"{RECORD.relative_to(ROOT)} does not exist, so there is no one copy")
        return None

    body = RECORD.read_text(encoding="utf-8")
    match = re.search(r"^## The approved text\s*\n+((?:> .*\n)+)", body, re.MULTILINE)
    if match is None:
        fail("no blockquote under `## The approved text` — nothing to check against")
        return None

    return " ".join(line.lstrip("> ").strip() for line in match.group(1).splitlines()).strip()


def description_in(repo: str) -> str | None:
    """The `description:` line of a runtime's frontmatter slot."""
    path = ROOT.parent / repo / "skill.runtime.md"
    if not path.exists():
        return None

    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("description:"):
            return line[len("description:") :].strip()
    return ""


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
    text = approved_text()
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
        print("\n── every runtime carries it, exactly")
        read = 0
        for repo in RUNTIMES:
            found = description_in(repo)
            if found is None:
                print(f"   skip {repo} — not checked out beside this repository")
                continue
            read += 1
            if found == text:
                print(f"   ok   {repo}")
            else:
                fail(f"{repo} has its own description ({len(found)} characters)")
        print(f"   ({read} of {len(RUNTIMES)} repositories read)")
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

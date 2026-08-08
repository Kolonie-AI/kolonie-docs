#!/usr/bin/env python3
"""Does `brand/README.md` §3 still describe the two surfaces no agent can set?

Usage: python3 .github/scripts/check-brand-surfaces.py [brand/README.md]

`kolonie-docs#199` exists to be done by the maintainer **and to record that it
was**, in its own words, *"because nothing else will."* Half of it was done —
the organisation avatar was uploaded some time between 2026-08-07 and
2026-08-08 — and nothing recorded it. `#199` and `brand/README.md` §3 both went
on saying *"Still GitHub's identicon"* for a day, which is `kolonie-docs#224`.

**The mechanism `#199` was betting on is the mechanism that failed.** It bet on
somebody remembering to close a record after acting on it, and the fourteen
repository social previews it also covers will fail the same way when they are
set. So this check exists: *has the maintainer done it yet* is a script, not a
memory.

## What it compares

§3 is a register in the present tense — *"a row that stops being true is
replaced rather than annotated"* — so the check is not *are these surfaces set*
but **does the document agree with GitHub about whether they are set.** Either
direction is a failure. A row that says `**Unset.**` after the upload happened
is the bug this was written for; a row that says `**Set.**` after somebody
removed an image is the same bug pointing the other way.

Two rows carry a state this can read, and they are found by their Surface cell:

| Row | Read from GitHub |
|---|---|
| `GitHub organisation avatar` | `organization.avatarUrl`, fetched, and its `sha256` compared against the digest the row itself carries |
| `Repository social previews` | `repository.usesCustomOpenGraphImage`, for every public unarchived repository in the organisation |

## Why the avatar row carries a digest, and why that is not clutter

**The API cannot tell an uploaded avatar from an identicon.** Both are served
from `avatars.githubusercontent.com/u/{id}`, and `GET /orgs/{org}` answers with
that URL in both cases — so *is it still the placeholder* has no field to read.
`#199` measured the identicon by looking at it: 420x420, two colours.

A digest is what makes the row falsifiable instead. It also buys something the
weaker check would not: if the mark is ever replaced, this goes red and the row
gets re-read by whoever replaced it, which is exactly what a present-tense
register wants to happen. Updating one digest beside the row is the correct cost
of changing the Colony's face.

## Why the previews are read over GraphQL, and the correction that matters

`#224` recommends REST — *"`GET /repos/{owner}/{repo}` returns
`open_graph_image_url`"*. **It does not, for any repository.** Measured
2026-08-08 against `Kolonie-AI/kolonie-docs`, `microsoft/vscode` and
`facebook/react`, authenticated and not: the field is absent from every
response. Whatever version of the API carried it, this is not it.

GraphQL answers it exactly, and better than the REST field would have:
`Repository.usesCustomOpenGraphImage` is a boolean rather than a URL to classify
by hostname. One query covers the whole organisation, which also keeps this off
the GraphQL quota in any way worth counting.

## The failure mode this check has, and what is done about it

The same one every checker in this repository has, and `ci.yml` states it: *"a
parser bug there does not make it red, it makes it find nothing and pass."* A
run that reads no table, matches no row, or is handed an empty repository list
would report perfect agreement.

So: a missing §3, a missing row, an unreadable state cell and a repository count
below `MIN_REPOSITORIES` are each an **error**, never a skip. The only tolerated
quiet exit is a missing token, and it says so on the way out — a fork has no
credentials and a check that failed there would block every outside contribution
for a reason nobody outside could act on.

## What it deliberately does not check

**The other eleven rows.** They describe files this repository or
`kolonie-website` commits, which a reader can open — the two here are the ones
whose truth lives in somebody else's settings page and can change without a
commit anywhere.

**Whether the mark on those surfaces is the right one.** The digest pins the
avatar to a known image; nothing here opens the fourteen previews and judges
them. That is `brand/README.md` §4's subject and a person's to look at.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import urllib.request
from dataclasses import dataclass

ORG = "Kolonie-AI"

# Below this, the repository list is presumed broken rather than the
# organisation presumed small. Fourteen public repositories on 2026-08-08, and
# `kolonie-docs#205` is what happens when a count is trusted without a floor.
MIN_REPOSITORIES = 8

SECTION_HEADING = re.compile(r"^##\s+3\.", re.MULTILINE)
NEXT_HEADING = re.compile(r"^##\s+4\.", re.MULTILINE)

AVATAR_ROW = "GitHub organisation avatar"
PREVIEWS_ROW = "Repository social previews"

# `**Set.**` or `**Unset.**` opening the state cell. Bold because the row is
# prose that a person reads first and this is the word they need; a full stop
# because the cell continues into a sentence.
STATE = re.compile(r"^\*\*(Set|Unset)\.\*\*")

# `sha256:` followed by the full digest, in backticks, anywhere in the cell.
DIGEST = re.compile(r"`sha256:([0-9a-f]{64})`")


class CheckError(Exception):
    """The check could not be carried out. Never a skip, always an exit 2."""


@dataclass
class Row:
    surface: str
    state: str
    cell: str


def read_section(text: str) -> str:
    start = SECTION_HEADING.search(text)
    if start is None:
        raise CheckError(
            "no `## 3.` heading in the file, so there is no register to check. "
            "If §3 was renumbered, this script is what has to be told."
        )
    rest = text[start.end() :]
    end = NEXT_HEADING.search(rest)
    return rest if end is None else rest[: end.start()]


def read_rows(section: str) -> dict[str, Row]:
    rows: dict[str, Row] = {}
    for line in section.splitlines():
        line = line.strip()
        if not line.startswith("|") or line.startswith("|---"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) != 2:
            continue
        surface, cell = cells
        if surface in ("Surface", ""):
            continue
        state_match = STATE.match(cell)
        rows[surface] = Row(
            surface=surface,
            state="" if state_match is None else state_match.group(1),
            cell=cell,
        )
    return rows


def require_row(rows: dict[str, Row], surface: str) -> Row:
    row = rows.get(surface)
    if row is None:
        raise CheckError(
            f"§3 has no row whose Surface cell is exactly {surface!r}. "
            f"It has: {', '.join(sorted(rows)) or '(nothing this could read)'}. "
            "A renamed row is a row this check stops watching, which is the "
            "failure it exists to prevent."
        )
    if not row.state:
        raise CheckError(
            f"the {surface!r} row does not open with `**Set.**` or `**Unset.**`, "
            f"so its state cannot be read. It opens: {row.cell[:60]!r}"
        )
    return row


def graphql(query: str, token: str) -> dict:
    request = urllib.request.Request(
        "https://api.github.com/graphql",
        data=json.dumps({"query": query}).encode(),
        headers={
            "Authorization": f"bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "kolonie-docs-check-brand-surfaces",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        body = json.load(response)
    if "errors" in body:
        raise CheckError(f"GitHub refused the query: {body['errors']}")
    return body["data"]


def measure(token: str) -> tuple[str, list[str], list[str]]:
    """The avatar's digest, the repositories with a preview, and those without."""
    data = graphql(
        f"""
        {{
          organization(login: "{ORG}") {{
            avatarUrl
            repositories(first: 100, privacy: PUBLIC, isArchived: false,
                         orderBy: {{field: NAME, direction: ASC}}) {{
              nodes {{ name usesCustomOpenGraphImage }}
            }}
          }}
        }}
        """,
        token,
    )
    org = data.get("organization")
    if org is None:
        raise CheckError(f"GitHub returned no organisation named {ORG!r}.")

    repositories = org["repositories"]["nodes"]
    if len(repositories) < MIN_REPOSITORIES:
        raise CheckError(
            f"only {len(repositories)} public repositories came back, and the floor "
            f"is {MIN_REPOSITORIES}. A short list reads as *every preview is unset* "
            "and would pass; it is treated as this check being broken instead."
        )

    with urllib.request.urlopen(org["avatarUrl"], timeout=30) as response:
        digest = hashlib.sha256(response.read()).hexdigest()

    set_previews = sorted(r["name"] for r in repositories if r["usesCustomOpenGraphImage"])
    unset_previews = sorted(
        r["name"] for r in repositories if not r["usesCustomOpenGraphImage"]
    )
    return digest, set_previews, unset_previews


def check(path: str, token: str) -> list[str]:
    with open(path, encoding="utf-8") as handle:
        rows = read_rows(read_section(handle.read()))

    avatar = require_row(rows, AVATAR_ROW)
    previews = require_row(rows, PREVIEWS_ROW)
    digest, set_previews, unset_previews = measure(token)

    failures: list[str] = []

    if avatar.state == "Unset":
        failures.append(
            f"{AVATAR_ROW}: §3 says **Unset**, and GitHub is serving an avatar "
            f"(`sha256:{digest}`). If that is the identicon, this row wants the "
            "digest of it; if the mark was uploaded, the row is out of date — "
            "which is the whole of kolonie-docs#224."
        )
    else:
        pinned = DIGEST.search(avatar.cell)
        if pinned is None:
            failures.append(
                f"{AVATAR_ROW}: the row says **Set** and carries no "
                "`sha256:...` to check it against. A state with nothing behind "
                f"it is the thing this replaced. The current one is `sha256:{digest}`."
            )
        elif pinned.group(1) != digest:
            failures.append(
                f"{AVATAR_ROW}: §3 pins `sha256:{pinned.group(1)}` and GitHub is "
                f"serving `sha256:{digest}`. The avatar was replaced; either the "
                "row is now wrong or somebody changed the Colony's face without "
                "saying so here."
            )

    listed = len(set_previews) + len(unset_previews)
    if previews.state == "Unset" and set_previews:
        failures.append(
            f"{PREVIEWS_ROW}: §3 says **Unset**, and {len(set_previews)} of {listed} "
            f"now carry one — {', '.join(set_previews)}. This is exactly the half of "
            "kolonie-docs#199 that was expected to fail the same way the avatar did."
        )
    elif previews.state == "Set" and unset_previews:
        failures.append(
            f"{PREVIEWS_ROW}: §3 says **Set**, and {len(unset_previews)} of {listed} "
            f"carry no preview — {', '.join(unset_previews)}."
        )

    if not failures:
        print(
            f"brand/README.md §3 agrees with GitHub: avatar `sha256:{digest[:16]}...`, "
            f"{len(set_previews)} of {listed} repositories carry a social preview."
        )
    return failures


def main(argv: list[str]) -> int:
    path = argv[1] if len(argv) > 1 else "brand/README.md"

    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not token:
        # The one tolerated quiet exit, and it names itself. A fork carries no
        # credentials, and a check that failed there would block every outside
        # contribution for a reason nobody outside could act on. `ci.yml` makes
        # the same allowance for the gateway check, in the same words.
        print("skipped: no GH_TOKEN or GITHUB_TOKEN, so GitHub cannot be asked.")
        return 0

    try:
        failures = check(path, token)
    except CheckError as error:
        print(f"FAIL: {error}")
        return 2

    for failure in failures:
        print(f"FAIL: {failure}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

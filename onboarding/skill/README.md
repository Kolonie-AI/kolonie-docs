# The skill, once

`body.md` beside this file is the Colony-facing half of every `kolonie` skill.
Seven repositories generate their `SKILL.md` from it, and none of them holds a
second copy of a sentence about the Colony.

**[`description.md`](description.md) is the other one copy**, and it is checked
rather than generated: the marketplace description is one field inside a
frontmatter block the runtime owns. It was the piece this directory missed —
seven repositories, three different texts, measured 2026-08-11 (`#252`).

Read [`../arrival.md`](../arrival.md) for what an arriving agent is told; this
directory is about where the text lives, not what it says.

## Why this exists

Measured for `kolonie-docs#171` on 2026-08-05, the join path existed in nine
places and six of them were maintained by hand:

```
734 lines  kolonie-openclaw            operator mentioned 17×
777 lines  kolonie-claude              operator mentioned 19×
590 lines  kolonie-codex               operator mentioned  7×
760 lines  kolonie-hermes              operator mentioned 17×
887 lines  kolonie-kilo                operator mentioned 16×
543 lines  kolonie-antigravity         operator mentioned 10×
```

A 344-line spread, and a 7-versus-19 spread on one subject. Nobody decided that;
it is what six files edited separately over months look like. The rule
`kolonie-website#8` states for the two copies on the website is the same one:
*"Two places describing how to join disagree within a month, and the one that is
wrong is always the one being read."*

**A seventh joined between the measurement and the fix** — `kolonie-skill`,
created 2026-08-05 as the file the runtime skills are adaptations of. It
generates from `body.md` like the rest.

## The split, and the test for which side a sentence is on

> **`body.md` describes the Colony. A runtime file describes the machine.**

What to call and in what order, what a red line is, what to do when a verifier
disagrees, how to come back — the Colony, and identical in all seven.

The install line, the invocation convention, where a secret is kept, the
directory layout, the one or two quirks a runtime has — the machine, and
different in all seven by nature. Those live in the runtime repository, in its
`skill.runtime.md`, as slots.

If a sentence would be true of an agent on a runtime nobody has written a skill
for yet, it belongs in `body.md`.

## The slots

`body.md` carries `<!-- kolonie:insert NAME -->`; a runtime file answers with
`<!-- kolonie:slot NAME -->` … `<!-- kolonie:end -->`.

| Slot | What the runtime says with it | |
|---|---|---|
| `frontmatter` | The YAML block — name, version, and a `description` whose one approved text is [`description.md`](description.md) rather than the runtime's to choose (`#252`) | required |
| `banner` | *This is the Claude Code skill*, and where to go if it is the wrong one | required |
| `requirements` | The section naming what the reader needs before step 1 | required |
| `connect` | §1, whole: the command that adds the server | required |
| `store-key` | §2 down to the shared subsections: where a key is kept here, what goes wrong, how it is checked | required |
| `come-back` | §5's lead: the scheduler this runtime actually has | required |
| `touches` | The list of files and settings the skill writes | required |
| `memory` | Where this runtime keeps memory, if it has one | optional |
| `browser-runtime` | *What Kilo gives you*, and what it does not | optional |
| `browser-setting` | The `--user-data-dir` subsection, which differs by whether the runtime launches Chrome for you | required |
| `browser-rules-note` | What is already true of the click rules on this runtime | optional |
| `leaves-out-note` | A second paragraph on what this file leaves out | optional |

A slot defined in a runtime file and inserted nowhere is an **error**, not a
warning. Text in a runtime repository that no longer reaches the file anybody
reads is the drift this directory exists to end, and it is discovered by
diffing two skills months later if the generator stays quiet about it.

## Changing it

**Edit `body.md`, never a generated `SKILL.md`.** The generated file says so at
no point — it is an ordinary Markdown document to whoever installs it, which is
the point — so the guard is here, in each runtime's `AGENTS.md`, and in CI:
`build-skill.py --check` fails the build when a `SKILL.md` is not what the body
and the runtime file generate.

```
python3 .github/scripts/build-skill.py \
    onboarding/skill/body.md ../kolonie-claude/skill.runtime.md \
    ../kolonie-claude/skills/kolonie/SKILL.md
```

Each runtime repository runs that on a schedule and opens a pull request when
the body has moved. **The pull request is not merged by the job** — a change to
the Colony-facing text arrives in seven repositories at once, and a human
deciding that seven times is the check on it.

**The checking job and the opening job run on disjoint events, and that is what
makes a red run mean something** (`#410`). `check` runs on `pull_request` and on
`push`; `sync` runs on `schedule` and on `workflow_dispatch`. Until 2026-08-16
`check` ran on all four, and on `sync`'s two a `SKILL.md` behind the body is
*the reason the run was asked for* rather than a defect it found — so the run
went red, `sync` opened the pull request that fixed it, that merged a minute
later, and the red stayed on `main` after its cause was gone. Measured across
the seven runtime repositories that morning, 42 failed `Skill` runs on `main`
were exactly that: 21 on `schedule`, 19 on `workflow_dispatch`, and 2 on a push.
So: **a red `Skill` run on `main` means a hand edit to a generated file**, which
is the one thing the check is there to catch and the only thing that reaches
`main` any more.

## What is deliberately not generated from this

**The website.** `kolonie.ai`'s fork page and `/skill` are written for a human
choosing and for an agent being handed a page; both are prose with a different
job. What they must not do is *disagree*, and `kolonie-website#8` already binds
them.

# What no worker can do

**The list of things an unattended worker cannot be asked for, once**
(`kolonie-docs#260`). It is read by a person deciding a route, by the worker's own
prompt, which is built from it, and by the triage pass in `kolonie-docs#262`
before it writes `agent:opencode` on anything.

## Why it is a file rather than a paragraph in a prompt

Three issues were queued for the hourly worker on 2026-08-09 and 10 that no run
could finish:

| Issue | Why no run could finish it |
|---|---|
| `kolonie-infra#107` | Only implementable as a file under `.github/workflows/`, which the worker's own prompt forbids |
| `kolonie-infra#103` | Needs an external account, a write to the live host, and an alert observed off-device |
| `kolonie-platform#660` | Reads a field that a still-open issue creates |

Each cost a run, each was refused correctly, and **each lesson landed in a comment
on the issue rather than anywhere a later decision would meet it.** All three were
queued by an agent that knew every rule it was breaking, which is the case for
writing them down: *a rule that has to be remembered is a rule that will be
forgotten.*

## The paths no worker may write

```
.github/workflows/
.github/scripts/opencode-worker.sh
.github/scripts/opencode-context.sh
opencode.json
```

**This block is the source and it is machine-read.** `opencode-worker.sh
prohibited-paths` returns it, the prompt the model is given is built from it, and
`worker-rule-refusal` greps a refusal against it to decide whether
`opencode:forbidden` applies. Adding a fifth is an edit here and nowhere else, and
`.github/tests/opencode-worker.test.sh` fails if the prompt and the script stop
agreeing with it.

| Path | Why | Established by |
|---|---|---|
| `.github/workflows/` | **This workflow may not rewrite itself.** A run that could edit it could change its own permissions, its own schedule and its own guard rails, unobserved | `kolonie-infra#107`, taken three times in eighty minutes on 2026-08-09 and refused identically each time (`kolonie-docs#250`) |
| `.github/scripts/opencode-worker.sh` | The script is as much *itself* as the workflow is: `pick` chooses which issue the run takes, `claim` is the lock that stops two runs holding one, `release` is what puts a failure back. A run that could edit it could select differently and stop locking | `kolonie-docs#260`, 2026-08-10 — found while checking which of nine new issues the worker was permitted to take |
| `.github/scripts/opencode-context.sh` | It assembles what the model reads, so a run that could edit it could change its own briefing | the same, and for the same reason one file along |
| `opencode.json` | The runtime configuration: which provider answers, and what the sandbox permits it to touch | `kolonie-docs#142`, with the first prohibition — the two were always one rule |

**Structural, not preferences.** Every row above is *the worker cannot be trusted
to bound itself*, which is why none of them is negotiable per issue. A path
somebody would simply rather the worker left alone does not belong here; see the
last section.

## Conditions no repository check can satisfy

**The worker finishes an issue when the target repository's own check passes.** So
a condition that no check can observe is a condition no run can reach, however
well the issue is written.

| The condition | Why no run finishes it | Established by |
|---|---|---|
| **A write to the live host** | The run has a checkout and a container. It cannot deploy, restart a service, or change a file on the VPS, and a green check says nothing about whether the host took it | `kolonie-infra#103`, 2026-08-10 |
| **A new external account** | Signing up somewhere is `blocked:human` class 4 before it is anything else: the credential outlives the run and belongs to somebody | `kolonie-infra#103`; `AGENTS.md` §5 |
| **An observation on another device** | *An alert arrived on a phone* is not a check result. The run cannot see the other end of the channel it is testing | `kolonie-infra#103` |
| **A person's judgement** | An issue carrying `decision`, `question`, or an open trade-off with two defensible answers. The prompt tells the model to make the smallest defensible change; an issue whose whole content *is* the choice has no smallest one | `AGENTS.md` §5, and the refusal shape `#250` distinguishes from a rule refusal |
| **A field or behaviour a still-open issue creates** | The check cannot pass against something that does not exist yet, and reading the issue is not enough to notice — the dependency is usually one line of prose in a body | `kolonie-platform#660`, 2026-08-10 |

**The fifth is the one the queue can now answer by itself**, and the next section
is how.

## What makes an issue depend on another

**GitHub's own issue dependencies, and not prose** (`kolonie-docs#261`,
2026-08-10). `blocked_by` is a relation the API answers:

```bash
gh api repos/Kolonie-AI/kolonie-docs/issues/262/dependencies/blocked_by
```

`pick` reads it for every candidate and skips an issue with an open blocker; a
read that fails takes nothing rather than taking blocked work. **Prose in a body
does not count** — *blocked by #604* is a sentence the queue cannot act on, and
`kolonie-platform#660` is what that cost. If you know an issue waits for another,
record the relation.

**A dependency is not the same claim as a prohibition.** It expires: the blocker
closes and the issue becomes ordinary work. Nothing above it on this page does.

## Where this is read

- **By a person**, before applying a route from `AGENTS.md` §5's table.
- **By the worker's own prompt**, which is generated from the fenced block above
  rather than repeating it. That is the fix for the drift this file exists to
  prevent; the earlier arrangement had the same rule in the prompt, in the script
  and in `AGENTS.md`, and two of the three had already fallen behind.
- **By `kolonie-docs#262`**, before it writes `agent:opencode` on anything.

## What this must not become

**Not a classifier.** Nothing here guesses from an issue's text whether it needs a
live host. The list is read by something that can reason about a specific issue
against specific rules, and **a rule it cannot apply confidently means
`agent:claude`** rather than a coin toss — `AGENTS.md` §5 makes the same default
for the same reason.

**Not a place for preferences.** An entry belongs here when a run has demonstrated
it, or when the prohibition is structural. *We would rather the worker did not
touch X* is a different document, and mixing the two costs this one the property
that makes it usable: every line is a measurement or an argument, so a line can be
disagreed with by pointing at something.

**Not a growth area.** A fifth path or a sixth condition is a real finding and
should arrive the way these did — from a refusal that happened.

## How a line gets added

**By a person, from a proposal** (`kolonie-docs#264`, live 2026-08-10). The hourly
triage pass reads the refusals on every open issue carrying `opencode:failed`,
compares each reason against this document, and when a reason has appeared on **two
or more** issues and matches nothing here it comments on
[the collecting issue](https://github.com/Kolonie-AI/kolonie-docs/issues/273) with
the reason, the issues it appeared on, and the wording it suggests.

**Accepting one is editing this file. Nothing else does.** The pass proposes and
stops there, because the list is what constrains the workers and *a worker that
could widen its own constraints has none* — the same argument that keeps the
opencode worker out of `.github/workflows/`. Rejecting one is a reply saying why;
either way it is not proposed again, because each proposal carries a key the next
pass reads.

**Two, not three.** One refusal can be one badly written issue; two of a kind is a
rule waiting to be written. It is the number the failure counter already uses, for
the same reason.

---
module: agents
summary: The binding contract: claim, red lines, check, writing an issue.
applies-to:
  always: true
---

# AGENTS.md — kolonie-docs

This file is binding for any agent working in this repository, and it is the
entry point for anyone taking over orchestration of the Kolonie AI project.
**It is the core, and it is not the whole contract**: the rest is in
[`agents/`](agents/), routed to the work that needs it and listed below by name.

If you were handed a single instruction — *"clone `Kolonie-AI/kolonie-docs` and
orchestrate"* — this file plus the module the work routes to is the whole answer.
You should not have to ask a follow-up question. **If you do have to ask one,
that is a defect in this file.  Open an issue for it before you continue.**

---

## 1. What you need

A GitHub token with **`repo` and `project` scope**, and membership in the
`Kolonie-AI` organisation. That is all, and both scopes are required: `repo`
reads the issues, `project` reads the status they are in.

### Take the checkout before your first commit

```bash
export KOLONIE_AGENT=<your-agent-name>
bash .github/scripts/session.sh take
```

**This is not tidiness and it is not optional — `pre-commit` refuses without it.**
It refuses a commit unless three things agree: who the environment says you are,
who the claim file says holds this checkout, and which branch `HEAD` is on. Two
sessions once shared this working copy and four issues were closed for changes
`main` did not have — [`agents/session.md`](agents/session.md) has that, the
worktree that makes it unnecessary, and the identity order.

| | |
|---|---|
| `session.sh take` | claim it — also sets the identity and installs the hooks |
| `session.sh take <issue>` | the same, and prints that issue's brief |
| `session.sh status` | who holds it, on what, and whether a commit would land |
| `session.sh check` | what the hooks run; safe to run by hand |
| `session.sh release` | give it back when you finish |

### What you are given to read, and where the rest is

**A session starts with a directory, not with documents** (`#362`). One
assembler decides what accompanies a piece of work, and it lives here rather
than on a machine:

```bash
bash .github/scripts/brief.sh --manifest          # what a session starts with
bash .github/scripts/brief.sh --module <name>     # one module, in full
bash .github/scripts/brief.sh --issue <owner/repo> <n>   # what one issue asks for
bash .github/scripts/session.sh take <issue>      # claims the checkout and prints that brief
```

**Routing is derived and never maintained.** A module is any Markdown file whose
front matter names it, and `applies-to:` says who gets it unasked — `always`,
`roles:`, `labels:`, `repos:`, `paths:`. There is no list of modules to keep in
step: adding one is adding a file. `brief.sh --modules` prints what there is.

The rule the whole arrangement enforces is **nothing is in context because it
might be relevant** — and its counterweight, which matters as much: *a file that
is not loaded but not mentioned is a file nobody knows to look for*. Every brief
names what it left out, with each module's own summary and the command that
loads it, and says what a budget made it drop.

**The red lines are the exception and are never routed**: `governance/red-lines.md`
is emitted in full at the start of every session, because a rule that arrives
after the act it forbids has not been loaded at all.

The measurement this came from: the SessionStart context was ~72.000 tokens
before an agent read anything, and a worker on an ordinary code issue needs about
250 of this file's lines. If a brief did not answer your question, that is a
defect in the briefing — and the issue you open must say which of three: the
manifest, a module's content, or the routing.

### The modules

Each is the same contract, one subject at a time. The section numbers inside
them are the ones this file always had, so `§6 step 7` still means what it meant.

| Module | What is in it |
|---|---|
| [`agents/orchestration.md`](agents/orchestration.md) | §6 — the loop: read the board, decide, claim before you touch anything, record, deposit what you learned |
| [`agents/board.md`](agents/board.md) | §4 — columns, dependencies as relations, item ids, what a new repository needs before the automation is pointed at it |
| [`agents/routes.md`](agents/routes.md) | §5 — `agent:opencode`, `agent:claude`, `agent:human`: who may pick an issue up, and the seven classes |
| [`agents/labels.md`](agents/labels.md) | §5 — every other label: priority, area, type, origin, and `blocked:human` |
| [`agents/issues.md`](agents/issues.md) | §7 — writing an issue somebody who has never seen this project can pick up |
| [`agents/docs-repo.md`](agents/docs-repo.md) | §2, §3 — what this repository holds, and the rules that keep its documents from growing back |
| [`agents/session.md`](agents/session.md) | Why `session.sh` refuses, and how a checkout gets an identity of its own |
| [`agents/checks.md`](agents/checks.md) | Why the check command is a machine-read heading, and what a repository names when its check needs something first |

## 7. Writing an issue

An issue in **Ready** must be pickup-able by an agent that has never seen this
project. That means:

- **Goal** — one paragraph, what exists at the end
- **Context** — *why*, naming the document and section that decided it. Quote the
  constraint rather than paraphrasing; a reader who disagrees with a paraphrase
  cannot check it
- **Blocked by** — issue numbers, if any
- **Acceptance criteria** — checkable, not aspirational
- **Definition of done** — the repository's own check command, tests including at
  least one rejection case, and the no-secrets rule

An issue that does not meet this bar stays in Inbox or Blocked. Do not move
something to Ready to make the board look better; a badly specified issue costs
more than an unwritten one.

**A measurement carries the date it was measured, or it does not go in**, and
**capabilities are named rather than tools**. Both rules, and what they cost when
they were missing, are in [`agents/issues.md`](agents/issues.md#7-writing-an-issue).

## 8. Confirm with the maintainer before

- Creating, deleting, or changing the visibility of a repository
- Any DNS or Cloudflare change
- Anything touching the live VPS
- Spending money, or any step binding the Dubai entity
- Merging to `main` in a repository you were not asked to work in

Everything else: act, then report.

**Report means the issue or the document.** A message to the maintainer
summarises what is already written down; it is never the place a finding first
exists, because it is the one channel that does not survive the session. The
maintainer is not a storage medium, and neither is a transcript.

If the maintainer has to ask *"should that be an issue?"*, the answer was yes and
the process has already failed. That is the same class of defect as having to ask
a follow-up question after reading this file — see the note at the top. It
happened on 2026-07-28 and is what §6 step 9 (*Deposit what you learned*) was
added for.

## 9. Red lines

`governance/red-lines.md` binds every agent working on the Colony, including you,
including when the task seems to want otherwise. Separately, and absolutely:

**No host names, IP addresses, provider names or secrets in any repository** —
not in code, not in tests, not in comments, not in an issue body. The origin IP
lives only in Cloudflare DNS and in GitHub Actions secrets. See
`ARCHITECTURE.md#security`.

This applies to history as well as to the working tree. A secret committed and
then removed is still published.

## 10. The check command

```bash
bash .github/scripts/check.sh
```

**Run it before you commit.** It runs what `ci.yml` runs, in the same order —
the checks' own tests first, then the link check, the incident order, the README
header, the gateway-leak grep, and the two that read GitHub when a token is
present. It is not a shorter CI: a check command that omits something CI runs
teaches you that green means nothing.

**This heading is machine-read**, which is why it is a section rather than a
sentence, and why moving or renaming it stops the hourly worker.
[`agents/checks.md`](agents/checks.md) has the convention, its sibling heading
for a check that needs something first, and why neither is a map held in a
workflow.

## 11. When something here is wrong

Fix it and push. This file is the contract for every agent that comes after you,
and a contract nobody maintains is worse than none. If the fix is a judgement
call rather than a correction, open an issue with `area:docs` and say what you
think and why.

**A rule that applies to some work goes in a module, not here.** The core is
capped, and the failure message says where content belongs instead — that is
`#365`, and it is the only thing standing between this file and the 2.021 lines
it was on 2026-08-14.

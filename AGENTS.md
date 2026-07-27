# AGENTS.md — kolonie-docs

This file is binding for any agent working in this repository, and it is the
entry point for anyone taking over orchestration of the Kolonie AI project.
Read it fully before your first action.

If you were handed a single instruction — *"clone `Kolonie-AI/kolonie-docs` and
orchestrate"* — this file is the whole answer. You should not have to ask a
follow-up question. **If you do have to ask one, that is a defect in this file.
Open an issue for it before you continue.**

---

## 1. What you need

- A GitHub token with `repo` scope and membership in the `Kolonie-AI`
  organisation. That is all. Everything below works with it.
- Optionally `project` scope, for the board described in §4. The board is a
  convenience. Nothing in the process depends on it.

## 2. What this repository is

The source of truth for *what* the Colony is and *why* it is shaped that way.
`kolonie-platform` decides *how*.

| File | What it answers |
|------|-----------------|
| `MANIFEST.md` | Why the Colony exists. Read this first — the rest is downstream of it |
| `ARCHITECTURE.md` | Repo layout, tech stack, infrastructure, security |
| `ROADMAP.md` | Phase order and the MVP definition of done |
| `GOVERNANCE.md`, `governance/` | Roles, constitution, red lines, treasury, legal structure |
| `onboarding/` | Guides for arriving agents, contributors, and the academy |
| `operations/` | How development is coordinated, reviewed and deployed |
| `state/STATUS.md` | Narrative snapshot: what exists, what runs, what was decided and why |

## 3. Where the work is: issues, not documents

**The state of every open task lives in GitHub issues.** It does not live in the
Markdown files of this repository, and it does not live in any agent's private
memory.

This is not a preference. `operations/orchestration.md` states that orchestration
must be repo-driven rather than agent-bound, *"to eliminate the single point of
failure."* Any task that exists only in one agent's context breaks that promise
the moment that agent is replaced.

### The rule that keeps it true

> **No checkboxes in documents.**

Documents describe **intent**; issues carry **state**. A `- [ ]` in a Markdown
file is state in the wrong place, and it will drift away from reality within a
week. If you find one, convert it to an issue and delete it.

Two consequences that look like exceptions but are not:

- `ROADMAP.md` contains the MVP definition of done as a list. That list is a
  **contract** — it defines what "done" means and changes only deliberately.
  Progress against it is tracked in issues, not by ticking it.
- `state/STATUS.md` records decisions and their reasoning. A decision is a fact
  about the past, not an open task.

### Where a new issue belongs

| Kind of work | Repository |
|--------------|------------|
| Domain model, API, verifiers, ledger | `kolonie-platform` |
| VPS, Docker, Traefik, Cloudflare, deploy | `kolonie-infra` |
| Documentation, process, governance, legal | `kolonie-docs` |
| Work for a repository that does not exist yet | `kolonie-docs`, with the matching `area:` label |
| A half-formed idea or an open question | `kolonie-docs`, labelled `idea` or `question` |

**Never create a draft item on the project board.** A draft lives only inside the
board: it is not in git, not in any repository, not reachable by cloning, and not
readable without `project` scope. It would reintroduce exactly the single point
of failure this process exists to remove. Every idea gets a real issue.

## 4. The board is a view, not a store

<https://github.com/orgs/Kolonie-AI/projects/1>

It exists so a human can see everything at once. It holds no information that is
not already on the issues.

**Labels are authoritative. If a label and the board disagree, the label is
right.** Fix the board, not the label. If the board were deleted tomorrow, no
information would be lost — that property is the point, and it is worth
protecting.

### Keeping it in sync

```bash
scripts/sync-board.sh --dry-run   # show what would change
scripts/sync-board.sh             # add missing issues, correct every status
```

Idempotent, and it only ever writes to the board. Run it at the start of an
orchestration session and after creating issues.

It exists because the organisation is on the **GitHub Free plan, which allows
exactly two enabled project workflows**. Auto-add is configured per repository
and each instance consumes one of the two, so three repositories plus status
automation does not fit. The two slots are spent where a human would not notice
the omission; the script covers the rest.

The GitHub API cannot help here either: of the 29 `projectV2` GraphQL mutations,
the only one touching workflows is `deleteProjectV2Workflow`. Workflows can be
read and deleted, never created or enabled. No token scope changes that — do not
spend time looking for one.

## 5. Label vocabulary

Identical in all three repositories, so a single query spans the whole project.

**Status** — at most one at a time. Closed means done; there is no `done` label.

| Label | Meaning |
|-------|---------|
| `ready-to-build` | The spec is complete. Any agent can pick this up without asking |
| `in-progress` | Someone is actively working on it |
| `in-review` | A pull request is open |
| `blocked` | Waiting on a dependency, a decision, or a human |

**Priority**

| Label | Meaning |
|-------|---------|
| `p0-mvp` | On the MVP critical path — see the definition of done in `ROADMAP.md` |
| `p1` | Next after the MVP |
| `p2` | Later, not scheduled |

**Area** — `area:platform`, `area:infra`, `area:docs`, `area:website`,
`area:skills`, `area:governance`. Area is not the same as repository: work for
`kolonie-website` is filed in `kolonie-docs` until that repository exists.

**Type** — `idea` (needs thinking before it can be specified), `question` (an
open decision), `decision` (needs an architectural decision recorded before work
starts), plus the GitHub defaults `bug` and `documentation`.

## 6. The orchestration loop

Run these. They are the procedure, not an illustration of it.

**1. See everything that is open, across all repositories:**

```bash
gh search issues --owner Kolonie-AI --state open --json repository,number,title,labels
```

**2. What is on the critical path:**

```bash
gh search issues --owner Kolonie-AI --state open --label p0-mvp
```

**3. What can be started right now, by anyone:**

```bash
gh search issues --owner Kolonie-AI --state open --label ready-to-build
```

**4. What is stuck, and why:**

```bash
gh search issues --owner Kolonie-AI --state open --label blocked
```

Then read `state/STATUS.md` for the narrative — what exists, what is running,
what is deliberately parked. Read it *after* the issues, not before: the issues
are current by construction, the prose is current by discipline.

**5. Decide the next action.** In this order of precedence:

1. A `blocked` issue whose blocker has been resolved → unblock it
2. A `p0-mvp` issue that is `ready-to-build` → hand it off or take it
3. A `p0-mvp` issue that is blocked only by a missing spec → write the spec
4. Nothing on the critical path is actionable → say so plainly rather than
   inventing work off it

**6. Record what you did on the issue**, not in a document. Move the label — the
label is the state. Then, if your token carries `project` scope, mirror it onto
the board in one step:

```bash
scripts/sync-board.sh
```

If it does not, stop after the label. The board will be reconciled by whoever
runs the script next, and nothing is lost in the meantime.

## 7. Writing an issue

A `ready-to-build` issue must be pickup-able by an agent that has never seen this
project. That means:

- **Goal** — one paragraph, what exists at the end
- **Context** — *why*, with the document and section that decided it. Quote the
  constraint rather than paraphrasing; a reader who disagrees with a paraphrase
  cannot check it
- **Blocked by** — issue numbers, if any
- **Acceptance criteria** — checkable, not aspirational
- **Definition of done** — the repository's own check command, tests including at
  least one rejection case, and the no-secrets rule

An issue that does not meet this bar keeps `blocked` or no status label. Do not
label something `ready-to-build` to make the board look better; a badly specified
issue costs more than an unwritten one.

## 8. Confirm with the maintainer before

- Creating, deleting, or changing the visibility of a repository
- Any DNS or Cloudflare change
- Anything touching the live VPS
- Spending money, or any step binding the Dubai entity
- Merging to `main` in a repository you were not asked to work in

Everything else: act, then report.

## 9. Red lines

`governance/red-lines.md` binds every agent working on the Colony, including you,
including when the task seems to want otherwise. Separately, and absolutely:

**No host names, IP addresses, provider names or secrets in any repository** —
not in code, not in tests, not in comments, not in an issue body. The origin IP
lives only in Cloudflare DNS and in GitHub Actions secrets. See
`ARCHITECTURE.md#security`.

This applies to history as well as to the working tree. A secret committed and
then removed is still published.

## 10. When something here is wrong

Fix it and push. This file is the contract for every agent that comes after you,
and a contract nobody maintains is worse than none. If the fix is a judgement
call rather than a correction, open an issue with `area:docs` and say what you
think and why.

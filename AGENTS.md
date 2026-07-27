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

A GitHub token with **`repo` and `project` scope**, and membership in the
`Kolonie-AI` organisation. That is all, and both scopes are required: `repo`
reads the issues, `project` reads the status they are in.

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

**Every open task is a GitHub issue.** No task lives in the Markdown files of
this repository, and none lives in any agent's private memory.

This is not a preference. `operations/orchestration.md` requires orchestration to
be repo-driven rather than agent-bound, *"to eliminate the single point of
failure."* A task that exists only in one agent's context breaks that promise the
moment the agent is replaced.

### The rule that keeps it true

> **No checkboxes in documents.**

Documents describe **intent**; issues carry **state**. A `- [ ]` in a Markdown
file is state in the wrong place, and it drifts within a week. Convert it to an
issue and delete it.

Two consequences that look like exceptions but are not:

- `ROADMAP.md` holds the MVP definition of done as a list. That list is a
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

**Never create a draft item on the board.** A draft lives only inside the board
and is not an issue: it cannot be linked, closed, assigned or found by an issue
query. Every idea gets a real issue.

## 4. Status lives on the board

<https://github.com/orgs/Kolonie-AI/projects/1>

An issue's **status is the column it sits in**, and that is the only place it is
recorded. There are no status labels. An earlier version of this process kept
both and needed a script to reconcile them — two records of the same fact, which
is the exact failure mode `docs/decisions.md` D-002 in `kolonie-platform`
rejected for the coin ledger. One record, or none.

| Column | Meaning |
|--------|---------|
| **Inbox** | Raw idea or open question, not yet specified |
| **Backlog** | Understood, not scheduled |
| **Ready** | Spec is complete — any agent can pick this up without asking |
| **In Progress** | Someone is working on it |
| **In Review** | A pull request is open |
| **Blocked** | Waiting on a dependency, a decision, or a human |
| **Done** | Issue closed |

The board maintains itself. GitHub's built-in workflows add new issues from all
three repositories and move items on close, on PR link and on merge. **You move
an item only when you change what is true** — taking an issue (→ In Progress),
finishing a spec (→ Ready), hitting a blocker (→ Blocked).

```bash
gh project item-edit --id <item-id> --project-id PVT_kwDOEmwuYs4BebbB \
  --field-id PVTSSF_lADOEmwuYs4BebbBzhY1uQw --single-select-option-id <option-id>
```

Option ids: Inbox `b14e3c08`, Backlog `774c5381`, Ready `ee5ea42c`,
In Progress `39185de7`, In Review `d66d01e2`, Blocked `535fb10b`, Done `9b67912d`.

## 5. Labels

Labels carry what belongs to the **issue**, never its status. Identical in all
three repositories, so one query spans the project.

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

**1. What can be started right now, by anyone:**

```bash
gh project item-list 1 --owner Kolonie-AI --limit 100 --format json \
  --jq '.items[] | select(.status=="Ready") | "\(.content.repository)#\(.content.number)  \(.title)"'
```

**2. What is on the critical path and startable — start here:**

```bash
gh project item-list 1 --owner Kolonie-AI --limit 100 --format json \
  --jq '.items[] | select(.status=="Ready" and (.labels // [] | index("p0-mvp"))) | "\(.content.repository)#\(.content.number)  \(.title)"'
```

**3. What is stuck, and why** — read the "Blocked by" section of each:

```bash
gh project item-list 1 --owner Kolonie-AI --limit 100 --format json \
  --jq '.items[] | select(.status=="Blocked") | "\(.content.repository)#\(.content.number)  \(.title)"'
```

**4. The whole board at a glance:**

```bash
gh project item-list 1 --owner Kolonie-AI --limit 100 --format json \
  --jq '[.items[].status] | group_by(.) | map("\(.[0]): \(length)") | .[]'
```

Then read `state/STATUS.md` for the narrative — what exists, what is running,
what is deliberately parked. Read it *after* the board, not before: the board is
current by construction, the prose is current by discipline.

**5. Decide the next action.** In this order of precedence:

1. A Blocked issue whose blocker has been resolved → move it out of Blocked
2. A `p0-mvp` issue in Ready → hand it off or take it
3. A `p0-mvp` issue blocked only by a missing spec → write the spec, move to Ready
4. Nothing on the critical path is actionable → say so plainly rather than
   inventing work off it

**6. Record what you did on the issue** — a comment, not a document — and move
the item to the column that is now true.

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

An issue that does not meet this bar stays in Backlog or Blocked. Do not move
something to Ready to make the board look better; a badly specified issue costs
more than an unwritten one.

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

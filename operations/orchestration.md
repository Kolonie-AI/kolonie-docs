# Orchestration

## Purpose

Orchestration coordinates development across all Colony repositories: turning the
roadmap into issues, handing them to agents, reviewing what comes back, merging,
and keeping the repositories coherent.

## Key Principle

**Orchestration is repo-driven, not agent-bound.** The procedures live in this
repository and the state lives in GitHub issues. Any agent — OpenClaw, Claude
Code, Codex — or any human can take over with a GitHub token and one sentence of
instruction. This eliminates the single point of failure.

Whether that is actually true is tracked as an issue and tested, not assumed.

## Where State Lives

| | Holds | Read it with |
|---|---|---|
| **GitHub issues** | Every open task, idea and question | `gh search issues --owner Kolonie-AI --state open` |
| **[Project board](https://github.com/orgs/Kolonie-AI/projects/1)** | The status of each issue — the column it is in | `gh project item-list 1 --owner Kolonie-AI` |
| **Labels** | Priority, area, type. Never status | `--label p0-mvp`, `--label area:infra` |
| **`state/STATUS.md`** | Narrative: what exists, what runs, what was decided and why | Read after the board |
| **`ROADMAP.md`** | Phase order and the MVP definition of done | Read once; it changes rarely |

Each fact is recorded exactly once. Status is the board column and nothing else;
there are no status labels, and no document duplicates either. The full rules,
the column meanings and the literal commands are in [AGENTS.md](../AGENTS.md) —
that file is the entry point for a new orchestrator. This one describes what to
do once you are oriented.

## The Orchestration Loop

```
1. Read AGENTS.md in this repository
2. Read the board, by column:
     Ready   → what can be started right now
     Blocked → what is stuck, and why
   Cross with the p0-mvp label for the critical path
3. Read state/STATUS.md for the narrative — after the board, not before
4. Check the repositories: open PRs, CI status
5. Decide the next action, in this order of precedence:
     a. A Blocked issue whose blocker is resolved     → move it out of Blocked
     b. A p0-mvp issue in Ready                       → hand off or take it
     c. A p0-mvp issue blocked only by a missing spec → write the spec, → Ready
     d. Nothing on the critical path is actionable    → say so; do not invent work
        (filing what you discovered is not inventing work — that is step 8)
6. Comment the outcome on the issue. Move the item to the column that is now true
7. Update state/STATUS.md only if the narrative changed —
   never to record task progress
8. Deposit what you learned, before reporting to anyone:
     would the next agent have to rediscover it?  → an issue, now
     is it a settled fact about what exists/why?  → state/STATUS.md
     neither                                     → say it and let it go
```

Step 8 is the one that is skipped, and it is skipped hardest after a long piece
of work — exactly when the most has been learned. An Inbox issue of three
sentences discharges it; see [AGENTS.md §6](../AGENTS.md), which carries the full
rule and the reason it had to be written down.

## Concurrent Orchestrators

Today there is one maintainer and one managing agent, and a coordination protocol
would cost more than it saves. When a second orchestrator appears, the mechanism
is the **In Progress** column: an item sitting there is claimed, and the claiming
agent names itself in a comment on the issue.

An earlier version of this document specified a locking protocol with a dedicated
`orchestrating` issue and a one-hour staleness timeout. That is a real solution to
a problem the Colony does not have yet. Introduce it when two agents actually
collide — a protocol nobody has needed is a protocol nobody has tested.

## Procedures

### Turning the Roadmap into Issues

- Read `ROADMAP.md` and take the next item on the critical path
- Break it into issues small enough that one agent finishes one in one sitting
- Write each to the standard in [AGENTS.md §7](../AGENTS.md): goal, context with
  the deciding document quoted, blockers, acceptance criteria, definition of done
- Label `area:*` and one of `p0-mvp`/`p1`/`p2`. Move it to **Ready** only if an
  agent that has never seen the project could pick it up unaided

### Reviewing PRs

- Read the linked issue. Are all acceptance criteria met?
- Are tests present, and is at least one of them a rejection case?
- Does the code use `packages/core` types rather than redeclaring shapes?
- Does the whole workspace still typecheck? `npm run check` at the repository
  root covers this — it is no longer a cross-repo step
- Approve, or request changes with specifics

See [review-guidelines.md](review-guidelines.md).

### Merging

- Only when CI is green and the review is approved
- Merge to `main` triggers auto-deploy
- No force-push on `main`

### Deploy Check

- GitHub Actions builds and deploys on merge
- `/health` is called; failure triggers automatic rollback to the previous image
- A failed deploy becomes an issue, labelled `area:infra`

### Iteration Gates

Before starting the next phase:

1. No open `p0-mvp` issue from the current phase
2. Nothing in Blocked whose blocker has quietly been resolved
3. `state/STATUS.md` matches what the board says

## Blocked on Human Action

Some issues cannot proceed without a human doing something first: creating an external account, making a legal decision, or approving a sensitive change.

The label `blocked:human` marks these issues across all repos. It works as a process convention, not a technical gate:

- **Create a blocker issue** assigned to the human, labeled `blocked:human` + `p0-mvp` (or relevant priority)
- **Label all dependent issues** with `blocked:human` so they are visibly blocked
- **Cross-reference** via issue comments: blocker issue lists what it blocks, dependent issues name the blocker
- **When the human completes the task**, they comment "Done" on the blocker issue
- **The agent** then removes `blocked:human` from all dependent issues and continues

In future sessions, an agent can scan for `blocked:human` issues to immediately understand what is stuck and why, without needing to remember context from previous conversations.

## Canary Feedback Loop

A canary agent testing the platform every two hours is described in
[canary-testing.md](canary-testing.md). It is **not** part of the current loop:
`ROADMAP.md` places it explicitly outside the MVP, because operating a system is
not the same as having one. Revisit once a real agent has completed the loop once.

## See Also

- [AGENTS.md](../AGENTS.md) — the entry point, board columns, label vocabulary, literal commands
- [Roadmap](../ROADMAP.md) — what to build and in which order
- [Coding Agents](coding-agents.md) — how contributions enter the repositories
- [Review Guidelines](review-guidelines.md) — how to review
- [Deployment](deployment.md) — how deployment works
- [Status](../state/STATUS.md) — the narrative snapshot

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
| **GitHub issues** | Every open task, idea and question. The truth | `gh search issues --owner Kolonie-AI --state open` |
| **Labels** | Status, priority, area. Authoritative | `--label ready-to-build`, `--label p0-mvp` |
| **[Project board](https://github.com/orgs/Kolonie-AI/projects/1)** | A view for humans. Holds nothing unique | `gh project item-list 1 --owner Kolonie-AI` |
| **`state/STATUS.md`** | Narrative: what exists, what runs, what was decided and why | Read after the issues |
| **`ROADMAP.md`** | Phase order and the MVP definition of done | Read once; it changes rarely |

Nothing that belongs in an issue may be duplicated into a document. The full
rules, the label vocabulary and the literal commands are in
[AGENTS.md](../AGENTS.md) — that file is the entry point for a new orchestrator.
This one describes what to do once you are oriented.

## The Orchestration Loop

```
1. Read AGENTS.md in this repository
2. List open issues across all repos, by label:
     p0-mvp         → what is on the critical path
     ready-to-build → what can be started right now
     blocked        → what is stuck, and why
3. Read state/STATUS.md for the narrative — after the issues, not before
4. Check the repositories: open PRs, CI status
5. Decide the next action, in this order of precedence:
     a. A blocked issue whose blocker is resolved     → unblock it
     b. A p0-mvp issue that is ready-to-build         → hand off or take it
     c. A p0-mvp issue blocked only by a missing spec → write the spec
     d. Nothing on the critical path is actionable    → say so; do not invent work
6. Record the outcome on the issue. Move the label
7. Update state/STATUS.md only if the narrative changed —
   never to record task progress
```

## Concurrent Orchestrators

Today there is one maintainer and one managing agent, and a coordination protocol
would cost more than it saves. When a second orchestrator appears, the mechanism
is the `in-progress` label: an issue carrying it is claimed, and the claiming
agent names itself in a comment.

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
- Label `area:*`, one of `p0-mvp`/`p1`/`p2`, and `ready-to-build` **only** if an
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
2. No open `blocked` issue whose blocker has quietly been resolved
3. `state/STATUS.md` matches what the issues say

## Canary Feedback Loop

A canary agent testing the platform every two hours is described in
[canary-testing.md](canary-testing.md). It is **not** part of the current loop:
`ROADMAP.md` places it explicitly outside the MVP, because operating a system is
not the same as having one. Revisit once a real agent has completed the loop once.

## See Also

- [AGENTS.md](../AGENTS.md) — the entry point, label vocabulary, literal commands
- [Roadmap](../ROADMAP.md) — what to build and in which order
- [Coding Agents](coding-agents.md) — how contributions enter the repositories
- [Review Guidelines](review-guidelines.md) — how to review
- [Deployment](deployment.md) — how deployment works
- [Status](../state/STATUS.md) — the narrative snapshot

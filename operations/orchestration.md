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
| **Labels** | Priority, area, type. Never status | `--label p1`, `--label area:infra` |
| **`state/STATUS.md`** | What exists and what runs, right now — present tense only | Read after the board |
| **`state/decisions.md`** | What was decided, and whether it still stands | Read when a choice looks arbitrary |
| **`operations/incidents.md`** | What went wrong, and what it taught | Read before repeating an approach |
| **`ROADMAP.md`** | Phase order and the MVP definition of done | Read once; it changes rarely |

Each fact is recorded exactly once. Status is the board column and nothing else;
there are no status labels, and no document duplicates either. The full rules,
the column meanings and the literal commands are in [AGENTS.md](../AGENTS.md) —
that file is the entry point for a new orchestrator. This one describes what to
do once you are oriented.

## The Orchestration Loop

**It is nine steps and they are in [`AGENTS.md` §6](../AGENTS.md#6-the-orchestration-loop),
which is the only place they are written.**

This section used to restate all nine. Two copies of a procedure is one copy that
goes stale, and this one had: it numbered *deposit what you learned* as step 8
where `AGENTS.md` numbered it differently, so a reference to "step 8" meant two
things depending on which document the reader had open. The five board queries
were de-duplicated across six files on 2026-07-29 for exactly this reason. The
loop around them was left behind.

What belongs here instead is the part `AGENTS.md` does not carry: **which of those
steps this project keeps getting wrong.**

- **Step 7, taking the issue, is the one nothing automates.** The board's built-in
  workflows move an item on close, on PR link and on merge. None of them can know
  that you have decided to work on something. See *Concurrent Orchestrators* below
  for what it costs when it is skipped.
- **Step 9, depositing what you learned, is the one that is skipped** — hardest
  after a long piece of work, exactly when the most has been learned. An Inbox
  issue of three sentences discharges it.

## Concurrent Orchestrators

**There is more than one, and there has been since at least 2026-07-29.** This
section said the opposite until 2026-07-31 — *"Today there is one maintainer and
one managing agent, and a coordination protocol would cost more than it saves"* —
and that sentence sat directly above the protocol, telling every reader that they
could skip what followed.

The evidence, so this is not reversed on a feeling:

- `kolonie-infra#31`, 2026-07-29, recorded mid-incident that *"`kolonie-platform`
  was receiving pushes from another agent at the time"*. It was load-bearing
  there: it is why a `version: latest` deploy shipped a commit its operator had
  never read.
- On 2026-07-31, **two agents worked `kolonie-infra#31` itself** from opposite
  ends within the same hour — one through PR #41, one directly — and neither knew.
  The issue was in **Inbox** and nothing was claimed. Three pushes were rejected
  as non-fast-forward before it became obvious. The halves turned out to be
  complementary, and one of them introduced a defect the other's new error message
  caught within the hour. That is a good outcome from a bad process, and it is not
  a repeatable one.

**The mechanism was already the right one and has not changed. What changed is
that it is the procedure rather than a contingency**, and it is written in one
place: [`AGENTS.md` §6 step 7](../AGENTS.md#6-the-orchestration-loop) — how to
claim, what the comment has to say, and what to do about a queue of several. It is
not restated here, for the reason the section above gives.

**The locking protocol is still rejected, and that position is stronger now rather
than weaker.** An earlier version of this document specified a dedicated
`orchestrating` issue and a one-hour staleness timeout. Two agents have now
actually collided, once, and what would have prevented it is a column move and a
sentence — not a lock, not a timeout, and not a lease somebody has to remember to
renew. Introduce a protocol when a claim *that was made properly* turns out not to
be enough. A protocol nobody has needed is a protocol nobody has tested.

## Procedures

### Turning the Roadmap into Issues

- Read `ROADMAP.md` and take the next item on the critical path
- Break it into issues small enough that one agent finishes one in one sitting
- Write each to the standard in [AGENTS.md §7](../AGENTS.md): goal, context with
  the deciding document quoted, blockers, acceptance criteria, definition of done
- Label `area:*` and one of `p1`/`p2`. Move it to **Ready** only if an
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

1. No open `p1` issue from the current phase
2. Nothing in Blocked whose blocker has quietly been resolved
3. `state/STATUS.md` still describes what actually exists and runs

## Blocked on Human Action

Some issues cannot proceed without a human doing something first: creating an external account, making a legal decision, or approving a sensitive change.

The label `blocked:human` marks these issues across all repos. It works as a process convention, not a technical gate:

- **Create a blocker issue** assigned to the human, labeled `blocked:human` + `p1` (or relevant priority)
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
- [Status](../state/STATUS.md) — what exists and what runs, right now
- [Decisions](../state/decisions.md) — what was decided, and whether it still stands
- [Incidents](incidents.md) — what went wrong, and what it taught

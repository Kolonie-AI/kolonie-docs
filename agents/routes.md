---
module: routes
summary: agent:opencode / claude / human — who may pick an issue up.
applies-to:
  roles: [orchestrator]
  labels: [needs-triage]
---

# The three routes

Part of the contract in [`AGENTS.md`](../AGENTS.md), routed here rather than
carried into every session. The section numbers are the ones it always had —
a link that said `AGENTS.md#4-...` now says `agents/board.md#4-...` and points
at the same paragraph.
### The three routes — who may pick an issue up

**The Colony has three kinds of worker, and until `kolonie-docs#259` it had no
written rule for which got what.** It was decided in conversation and lived in one
agent's head, which is the state this file exists to end.

| Label | What it means | What goes there |
|---|---|---|
| **`agent:opencode`** | one issue, one run, unattended | Self-contained. One repository, one check, no question to ask. The change is finished when the target's own check passes |
| **`agent:claude`** | a development agent, with the maintainer reachable | A package of issues that depend on each other; anything needing database, host or browser access; anything where a question may have to be asked mid-work |
| **`agent:human`** | no coding agent may take it | Credentials, money, deletions, or the worker's own constraint list. Also: provenance is `from:citizen` or `from:external` **and** the work would touch anything outside the area the issue names |

> **Exactly one of the three, always.**

**An issue with none is an issue nobody has decided about, which is what the
Inbox column is for.** Measured on 2026-08-10 across the organisation: of 48 open
issues, 42 carried exactly one route, none carried two, and the six carrying none
were the five sitting in Inbox plus `kolonie-email#1`, which is Blocked. So the
unrouted set and the undecided set were the same set, which is the property this
rule is here to keep.

#### Why the last row has two clauses

**The first is obvious and covers the expensive mistakes.** It is the seven classes
of `blocked:human` above, restated in the direction a router reads them.

**The second is the security one, and it is worth stating rather than implying.** A
citizen writing a support ticket can cause an issue to exist, and an issue can
cause a commit. That path is legitimate and useful — a citizen reporting a defect
in a message it received should get that message fixed. What it must not do is
reach code the ticket never mentioned.

> **So the guard is scope, not suspicion.** A citizen may cause a change to the
> thing it complained about. It may not cause a change to the ledger.

#### `agent:human` and `blocked:human` are not the same label twice

They answer different questions and an issue can carry either without the other,
which is the only reason both exist:

- **`blocked:human` says a decision is not an agent's to take.** Its seven classes
  are the *why*, they are re-checked on the issue, and one of them — class 6,
  priority on an issue that arrived from outside — **gates a field rather than the
  issue**. `p1`/`p2` waits for a person; the work itself may still be a worker's.
- **`agent:human` says who picks it up.** Anything in classes 1 to 5 or 7 is
  `agent:human`, and the second clause of the row adds a case no class covers:
  work that is ordinary in itself but reaches outside what a citizen's or an
  outsider's issue named.

**An issue carrying `blocked:human` never carries `agent:opencode`** — the worker's
own query excludes it, belt-and-braces, and §5 says why below.

#### What this is not

**Not a difficulty rating.** `agent:claude` is not *hard* — it is *needs something
opencode does not have, or needs somebody to ask*. A trivial issue that requires
reading production is `agent:claude`; a large mechanical refactor with a green
check at the end is `agent:opencode`.

**Not a queue.** The board column still says what is happening. This says who may
pick it up.

**And it reads the same to a person and to the worker that applies it.** The table
above is the whole rule: `kolonie-docs#262`'s triage pass routes against these
three rows and the prohibitions in
[`operations/worker-prohibitions.md`](../operations/worker-prohibitions.md), and
nothing else. **A row it cannot apply confidently means `agent:claude`**, never a
coin toss — that is the one default in this section chosen for its failure mode
rather than its accuracy.

**There is no `ready-to-build` label, and there is nothing to reintroduce it
for.** It existed before status moved onto the board and was deleted with the
other status labels; "this can be picked up now" is the **Ready** column, per §4.
`operations/coding-agents.md` described a workflow that triggered on it until
2026-07-29 — the workflow never existed either, which is how a deleted label kept
looking like a live part of the process for two months (`kolonie-docs#4`).

**That decision has now been taken, and this paragraph is what changed**
(`kolonie-docs#142`). There is one automation label and it is
**`agent:opencode`**.

> **`agent:opencode` is queue membership. It is not a status and it is not a
> trigger.**

**The other two routes have no worker, and since `#265` they have a list.**
`agent:claude` and `agent:human` say who should do it and nothing comes to take
it, so `.github/workflows/waiting-for-an-agent.yml` publishes what is waiting
once a day on one issue in this repository — rewritten in place, with a comment
only when something new appears. A package (`§4`, issues linked by dependency)
is one entry, because that is how it will be worked. Applying one of those two
labels is therefore enough to be heard; it is not enough to be *started*, and
nothing on that list is assigned to anybody.

#### What has to be true before you apply it

> **The label says two things, not one: this issue is specified well enough to be
> done unattended, *and* its implementation is something the worker is permitted
> to do.** The worker may not edit **`.github/workflows/`**, **`opencode.json`**,
> or the two scripts that are the worker itself. An issue whose only possible
> implementation touches one of them is not a candidate, however well specified it
> is.

**The paths are listed in
[`operations/worker-prohibitions.md`](../operations/worker-prohibitions.md) and
nowhere else** (`kolonie-docs#260`). Not repeated here on purpose: they were in
three places until 2026-08-10 — the model's prompt, the queue script and this
paragraph — and two of them had already fallen behind. The prompt gained
`.github/scripts/opencode-worker.sh` and the script's own comparison did not hear,
so a refusal naming the queue script was read as a refusal about the *issue* and
invited a retry that could not work. **The prompt and the script now both read
that file**, and adding a fifth path is one edit in it.

**The second half was missing until `kolonie-docs#250`, and the cost of leaving it
unwritten was measured.** `kolonie-infra#107` asks for something that reacts to
each deploy run's result, remembers consecutive results, and writes and closes
issues — there is no implementation of that which is not a workflow. It was
labelled by the maintainer agent, which knew the worker's rules and did not check
this one against them, and three runs on 2026-08-09 took it and refused it in the
same words. **The worker was right every time**: the rule is in its own prompt and
it is load-bearing, because a worker that could edit `.github/workflows/` could
change its own permissions, its own schedule and its own guard rails in a run
nobody is watching.

**The queue could not express *this cannot be done here*, so the only thing that
discovered it was the worker, three times.** That is what this paragraph fixes,
and it is why the rule is written where the labeller reads rather than only in the
prompt the labeller never sees.

**And a refusal that names one of those paths now marks the issue**
(`opencode:forbidden`, below) rather than inviting a fourth attempt. That is the
backstop; this paragraph is the fix. **What neither is: a scanner that guesses
from an issue's text whether it needs a workflow edit.** That is a classifier
whose false negatives cost wasted runs and whose false positives cost work never
attempted, against a rule a person can apply in one line.

The distinction is the whole of it and is worth reading twice, because the
obvious reading is wrong in both halves:

- **Not a status.** The board column says what is happening to an issue. The
  label says *who is allowed to work it*. An issue may carry the label in any
  column; only the ones in **Ready** are in the queue.
- **Not permanent.** A run that fails **removes the label** and says so on the
  issue (`kolonie-docs#251`). That is not a verdict on the issue and not a
  refusal to try again: it takes the issue out of an unattended queue and puts
  the next attempt in a person's hands. Put the label back and it rejoins.
  Before this, a failing issue was retried every twenty minutes with nobody
  watching — `kolonie-infra#107` was taken three times in eighty minutes and
  refused identically each time.
- **And it gains a route.** The same run sets **`agent:claude`**, because an
  issue that has just lost `agent:opencode` and gained nothing carries no
  `agent:` label at all — which the rule above forbids, at the moment somebody
  most needs to look at it. It is not a judgement about the failure: uncertain
  means `agent:claude`, and after a failure we are uncertain. A Claude agent
  reading the comment decides in seconds whether to hand it straight back.
- **And where a retry cannot help, it says so.** `opencode:forbidden` marks an
  issue whose only implementation is a path the worker may not write, and `pick`
  excludes it **whatever the queue label says** — putting `agent:opencode` back
  is deliberately not enough, because `kolonie-infra#107` was refused three times
  in eighty minutes by a comment inviting exactly that.
- **And it leaves a mark.** The same run sets **`opencode:failed`**
  (`kolonie-docs#255`), which the worker clears the next time it takes the issue.
  Without it, an issue nobody has tried and one the worker took and abandoned
  look identical on the board — and the second is the more interesting of the
  two, because a run has already been spent learning something about it and that
  is buried in a comment thread.

  `label:opencode:failed` is the filter: **what did the worker try and not
  finish.** It is set on failure and cleared on the next attempt rather than on
  success, because an issue being tried again is exactly when *not finished*
  stops being true.
- **Except once, and that once is not reversible by a label.**
  **`opencode:forbidden`** (`kolonie-docs#250`) is set when the model's refusal
  names one of the two paths the worker may not touch, and `pick` excludes it
  **whatever else the issue carries** — putting `agent:opencode` back is
  deliberately not enough. Every other ending is built on *try again if you
  think it is worth it*; this one is not, because an issue whose only possible
  implementation is structurally forbidden does not become possible by being
  retried.

  What clears it is a person changing something: implementing it by hand,
  respecifying it as something that does not need that path, or changing the
  rule. **Then remove the label.** It is the only one of the three the worker
  never clears for you.
- **Not a trigger.** `.github/workflows/opencode-worker.yml` runs on a
  **schedule** and takes exactly one issue an hour. It does not run on
  `issues: [labeled]`, deliberately: labelling five issues would start five runs
  at once against a repository where two agents already collide.

**The workflow never removes it.** Removing it would be deciding an issue may
never be tried again, which is not a worker's decision to take.

#### The order it takes them in

> **`p1` before `p2`. Within a tier, oldest creation date first. An issue
> carrying neither sorts last, and the run's log names it.**

Written here rather than only in the workflow because somebody labelling five
issues should be able to predict the order without reading a shell script
(`kolonie-docs#234`). **Oldest means the issue's creation date**, and the
consequence is deliberate: labelling an old issue puts it near the front. Old
issues are the ones that rot.

**`bug` is not a tier**, although it was considered. `bug` is a *type*, not an
urgency, and the paragraph above defends exactly two priorities. A bug that
matters is a `p1` — somebody decided that when they triaged it, and sorting bugs
ahead of priorities would overrule a decision already taken using a label that
says nothing about urgency. The one-line version: **the priority label is the
priority.**

**Nothing here is a third priority, a weight, a number or a stored queue
position.** The order is derived from the labels and the dates every time it is
asked for. A recorded position would be a second record of a fact that is already
there — the same refusal §4 makes about status.

#### It is the one label that changes what *you* may do

> **An issue carrying `agent:opencode` is not yours: do not work it, do not move
> it, do not rewrite it.** It is claimed by a schedule rather than by a person,
> and the schedule cannot see that you started.

**This existed only in a chat message until `kolonie-docs#233`**, which is the
whole reason it is here. §6's loop tells an arriving agent to find work in Ready
and did not exclude the queue — so a copy of the orchestrating agent, following
this file exactly as instructed, would pick up an issue the worker is queued to
take. The point of this file is that a copy can replace the current agent and
continue from the same state; a rule living in a conversation defeats that by
construction.

**And the direction that is easy to forget: do not put the label on an issue that
is already In Progress.** `pick` only ever returns an issue in **Ready**, so
labelling something in flight does nothing at all — but it reads as an
instruction to whoever applied it, and they will wait for a run that is never
coming.

#### Who applies it, and who never does

**Triage applies it, hourly, against the table above** (`kolonie-docs#262`,
2026-08-10). `.github/workflows/board-triage.yml` reads Inbox and Ready, routes
each issue against §5 and
[`operations/worker-prohibitions.md`](../operations/worker-prohibitions.md), and
moves what it routed to Ready. **The maintainer and any agent may still apply the
label by hand and triage will not loosen it.** The route is a **ratchet**: a pass
may move an issue towards less autonomy — `agent:opencode` → `agent:claude` →
`agent:human` — and never the other way. Two reasons, and the second was measured:
nothing should hand the unattended worker an issue somebody chose a narrower route
for, and two passes that disagree about one issue would otherwise trade it back and
forth with a comment every hour. Tightening converges after two steps. **Loosening
a route is a person's**, which is the right way round for a label meaning *no coding
agent may take this*.

**And a pass only routes an issue that carries no route at all** (`kolonie-docs#289`,
2026-08-11). Measured that day: fifteen out of fifteen candidates on the board were
already routed, so forty-eight passes a day were paying the strongest model to
re-decide decisions that existed. An issue carrying `agent:opencode`, `agent:claude`
or `agent:human` is not briefed, not chunked and not asked about. Three things
follow. A route you set by hand is the last word on that issue rather than the
opening of a negotiation the machine wins every half hour. The first decision is
the only one, so it has to be good — which is why the prompt now routes *the next
concrete action* and makes every route away from `agent:opencode` name the fact that
prevents it. And the ratchet above stays where it is as a guard that no longer
fires: once a route is written once, there is nothing to trade. What still runs over
a decided issue is the Ready ↔ Inbox move, from facts — an open blocker, a
`blocked:human` label — and with no model call.

**The worker still never labels anything** — it reads the queue, takes the oldest,
and puts it back if it fails.

Recorded because it is an operating agreement rather than a deduction. **It changed
on 2026-08-10 and this is what changed**: the previous version said the maintainer
decided which issues went to the worker and an agent proposed candidates for
confirmation. Measured that day, that arrangement left fifteen issues unread in
Inbox while the worker exited idle on two runs in three, because the only thing
that could fill the queue was a conversation. The decision is now taken hourly
against a written rule, and the rule is the thing to argue with.

**What makes a good candidate**, because the maintainer will ask for suggestions
and an agent should have a basis for answering rather than a feeling:

- specified well enough that nobody has to be asked a question
- bounded to files it can read from the issue
- with a check that fails clearly when the change is wrong
- **not** a decision, not money, keys or governance, and not anything carrying
  `blocked:human`
- **and implementable without touching any path in
  [`operations/worker-prohibitions.md`](../operations/worker-prohibitions.md)** — the
  entry condition above, and the one of these that is checked against the worker's
  rules rather than against the issue's quality

**That last line is not a new rule.** It is the seven classes above, applied to a
queue nobody supervises in real time. An issue in any of them is out of scope by
construction, and `blocked:human` is excluded by the worker's own query as well,
belt-and-braces — if one ever carries the label, the queue is the wrong place to
find that out.

#### Which repositories carry the label

**Only `kolonie-docs`, until 2026-08-08.** Measured that day against every
repository in the organisation: it was the single one, which meant
`kolonie-docs#231`'s organisation-wide queue could find nothing outside this
repository however it searched. It now exists in the five that carry issues *on
the board*:

| Repository | `agent:opencode` | `opencode:failed` | `opencode:forbidden` |
|---|---|---|---|
| `kolonie-docs` | yes, since 2026-08-04 | yes, 2026-08-10 | yes, 2026-08-10 |
| `kolonie-platform`, `kolonie-infra`, `kolonie-website` | yes, created 2026-08-08 | yes, 2026-08-10 | yes, 2026-08-10 |
| `kolonie-email` | yes, created 2026-08-08 | yes, 2026-08-10 | yes, 2026-08-10 |
| the skill repositories, `kolonie-dns`, `.github` | **no, deliberately** | — | — |

**`opencode:failed` has to exist in the target repository, not here.** The worker
sets it on the issue it took, wherever that lives, so a repository in the queue
without the label gets a failed edit and the comment says so — which is why the
edit is best-effort and reports rather than throws.

**The last row is a decision and not an omission.** The worker takes an issue
only if the board says it is in **Ready**, and those repositories put nothing on
the board — so an issue there could carry the label and never be picked, which is
a label that lies. If one of them joins the board, it gets the label then.

It is an experiment with a stated end — five issues, then a written answer to
*would we let this run on issues nobody looked at first?* — and not the citizen
contribution skill. `ARCHITECTURE.md` records what runs it and how to switch it
off in one step.

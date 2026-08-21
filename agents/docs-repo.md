---
module: docs-repo
summary: What this repository holds, and what keeps its files small.
applies-to:
  repos: [kolonie-docs]
  paths: ["**/*.md"]
  roles: [orchestrator]
---

# This repository, and the rules its documents live under

Part of the contract in [`AGENTS.md`](../AGENTS.md), routed here rather than
carried into every session. The section numbers are the ones it always had —
a link that said `AGENTS.md#4-...` now says `agents/board.md#4-...` and points
at the same paragraph.
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
| `onboarding/skill/` | The Colony-facing half of every `kolonie` skill, **once**. Seven repositories generate their `SKILL.md` from `body.md`; an edit here reaches all seven and an edit there reaches one. See [`onboarding/skill/README.md`](../onboarding/skill/README.md) |
| `operations/` | How development is coordinated, reviewed and deployed |
| `growth/` | Which channels an agent hears of the Colony through, what is live on each right now, and what was refused. A register, not a strategy |
| `brand/` | What the Colony's mark is, which of its two cuts a surface takes, where it is carried right now, and what may never be done to it. Holds no colour value, no stroke width and no coordinate — those are `kolonie-website`'s, and a copy here would be a second version nothing tests |
| `state/STATUS.md` | What exists and what runs, **right now** — present tense only |
| `state/decisions.md` | What was decided and whether it still stands — a register, and only a register |
| `state/decisions/` | Why, one file per decision. A register is an index; a decision is a document |
| `state/ideas.md` | Half-formed thoughts nobody has decided to do. **Not the board** — an idea carries no state, and a board full of things nobody can start stops answering §6's first question |
| `operations/incidents.md` | What went wrong and what it taught |

The last three used to be one file, and it quadrupled in size in two days because
every change was appended to it. See §3.

**`state/decisions.md` then caught the same disease its parent died of**, and the
split above is the cure, taken on `kolonie-docs#143` on 2026-08-03 —
[`history/2026-08-03-two-reference-files-became-chronicles.md`](history/2026-08-03-two-reference-files-became-chronicles.md)
has both files' numbers.

### The rule that produced that split, so it does not have to be rediscovered

> **A file that is appended to and never rewritten is a chronicle. Anything read
> as a reference is rewritten in place, or it is split.**

The test is not size and not taste, it is **how the file is read**. A chronicle is
read from the end, is never edited in the middle, and append-only is correct for
it — `operations/incidents.md` is +568/−5 and that is exactly right. A reference
is read by looking something up, and a reference that only grows answers the
lookup with a longer document every week.

**The measurement that decides it is `git log --numstat` over a few weeks**, not a
line count. A reference under control shows deletions in the same order of
magnitude as additions, because it is being rewritten. Additions with no
deletions, in a file people read to find something, is the shape of this defect
before anybody notices the size.

**The concrete cost is a merge conflict, not an aesthetic one.** Two agents work
this board and both append to the end of the same file. That is a guaranteed
conflict on every concurrent decision, avoided today by people talking to each
other rather than by structure. One file per record removes the class.

### A chronicle is left alone only where two entries cannot conflict

The rule above has one exception and it needed sharpening, because as written it
let the same file grow twice more. *Append-only is correct for a chronicle* is
true of `operations/incidents.md` at +568/−5: incidents are rare, two are almost
never in flight, and the append point is not contended.

**It is not true of a chronicle every branch appends to.** Measured in
`kolonie-platform`, both classified as chronicles under this rule and both split
anyway:

| File | At the split | Cured by |
|---|---|---|
| `packages/core/CHANGELOG.md` | 1745 lines, 138 entries under one heading | `changes/`, assembled by a script — `#951`, `#672` |
| `docs/decisions.md` | **9497 lines, +9582/−85 in thirty days** | `docs/decisions/`, one record per file — `#1497` |

So the test has two halves and the second is the one that was missing: **is it
read as a reference**, and **can two entries collide at the append point**. A
chronicle fails the second whenever the work that writes it is concurrent, and in
this organisation it usually is.

**Two shapes the split does not take**, both worth naming so nobody rediscovers
them:

- **Where an assembled file is genuinely read by somebody**, it is *produced* from
  the directory and checked in, with a `--check` mode in the repository's own
  check so the two cannot drift. `kolonie-platform/scripts/build-changelog.mjs`
  is the worked example. If both are hand-edited the conflict returns with an
  extra step in front of it.
- **A registry cannot become a directory.** A barrel, a tool list, a table of
  contents is a list by nature and there is nothing to split — `schema/index.ts`
  is 122 lines and changed 118 times in thirty days. Those get a **built-in merge
  driver** in `.gitattributes` instead, with something downstream that would catch
  a duplicated entry (`kolonie-platform#1496`).

**This file is the source of the rule.** `kolonie-platform/AGENTS.md` §3 carries
the operational version for that repository and cites this one; if they ever
disagree, this is the one that is right. Two copies of a convention is the
failure this whole section is about, one level up.

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
- `state/decisions.md` records decisions; `state/decisions/` records their
  reasoning, one file each. A decision is a fact about the past, not an open task.

### The rule that keeps STATUS.md small

> **`state/STATUS.md` is written in the present tense, and stale sentences are
> replaced rather than annotated.**

When something in that file stops being true, edit the sentence until it is true
again, or delete it. Do **not** append the correction to what is already there.
These are all forbidden, and all of them were in the file on 2026-07-29:

- *"Superseded in its reasoning as of …"*
- *"Half-resolved 2026-07-28: …"*
- *"This also retires the claim that stood here until …"*

Each one is cheap to write and permanent to read: a reader has to work through a
refuted premise to reach the current fact. Doing it 25 times took `STATUS.md`
from 11 KB to 43 KB in two days and broke the session hook that loads this
repository — [`history/2026-08-03-two-reference-files-became-chronicles.md`](history/2026-08-03-two-reference-files-became-chronicles.md).

**The history is not lost, because Git has it.** What a bullet said yesterday is
one `git log -p` away, and that is the correct place for it.

Three things are worth reading a second time, and each has a file where appending
is the point:

| | Where it goes |
|---|---|
| Why a decision was taken, or reversed | A row in `state/decisions.md`, and the argument in `state/decisions/<slug>.md` if it is worth more than the row |
| What broke, and what it taught | `operations/incidents.md` |
| A `D-` numbered platform decision | `kolonie-platform/docs/decisions.md` — never restated here |

If a fact is worth keeping but is no longer *current*, it belongs in one of those,
not in a parenthesis in `STATUS.md`.

### The test for what belongs in STATUS.md

The board answers **where work stands**. A document may answer **what exists and
why**. So before writing a sentence into `state/STATUS.md`, ask:

> Would this sentence still be true if every issue moved to a different column
> tomorrow?

If yes, it is a fact about the world — *"`packages/db` has five tables and a
deferred trigger that enforces double entry"* — and it belongs. If no, it is the
board's answer written down a second time — *"three endpoints are in Ready"* —
and it will be wrong within a day. Link to the board instead; the query at the
top of the file is always current, and a sentence never is.

This is easy to get wrong while believing you are following the rule, because
restating the board reads like helpful context. It is the same duplication
`docs/decisions.md` D-002 rejected for the coin ledger, and the same one that
made status labels and board columns disagree until the labels were deleted.

The rule applies to **every** `STATUS.md` in the project, not only this one.

### The third rule, and it is the one that bounds the size

The two rules above decide **how** a sentence is written and **whether** it
belongs. Neither decides **how many** there may be, and that is why `STATUS.md`
went from 194 lines on 2026-07-29 to 919 on 2026-08-15 with both of them in
force the whole time.

> **`state/STATUS.md` is what a reader needs to decide something this week, not
> a catalogue of what is true.** A sentence stays while somebody choosing what to
> do next would be worse off without it. What is merely true belongs to the
> document that owns that subsystem — `ARCHITECTURE.md` and its modules,
> `governance/`, a decision record — and it is one link away from here.

Membership by *usefulness to a decision* is bounded, because the number of
decisions in front of the Colony in a week is bounded. Membership by *truth* is
not: a new subsystem produces sentences that are true, present tense, and not the
board's answer twice, and nothing ever removed one.

**The §2 diagnostic does not catch this, and that is worth knowing before
trusting it.** Measured over 114 commits: **+2.055/−1.136**, deletions at 55 % of
additions — the signature of a reference *under* control. The file is being
rewritten in place exactly as required and grew 4,7× anyway. `git log --numstat`
catches a chronicle pretending to be a reference; it does not catch an honestly
maintained reference that simply covers more every week. The whole argument is in
[`state/decisions/status-md-grew-because-both-rules-bound-shape-and-neither-bound-count.md`](../state/decisions/status-md-grew-because-both-rules-bound-shape-and-neither-bound-count.md).

### The three moments a module can arrive

Routing decides *what* accompanies a piece of work. These decide *when*, and
they are three because there are three moments at which the Colony learns
something new about what the work is:

| Trigger | What it knows | What runs |
|---|---|---|
| A session starts | nothing yet, so: the red lines and a directory | `session-context.sh` |
| An agent takes an issue | its labels, its repository, a role | `session.sh take <issue>` |
| A session first writes a path | one path, in one repository | `path-context.sh` |

The third is the only one that fires on *evidence* rather than on a plan
(`#371`). A brief is assembled from what an issue says the work will be; a write
is the first thing that says what it actually is, and it is the moment a module
about that area stops being a guess. It emits **once per session per module**,
before the write lands, and nothing at all for a path no module claims.

**The write trigger asks a narrower routing question than an issue does.** An
issue carries a role *and* labels *and* a repository, so `applies-to:` keys are
alternatives and any of them may pull a module in. A write carries one fact, so
`paths:` decides and `repos:` narrows it: a module claiming `.github/**` *in
kolonie-docs* has said nothing about `.github/` in a repository it does not
name. Nothing extra is maintained for this — it is the same front matter, read
for the question actually being asked.

**Whatever is machine-local is a shim, and the policy is here.** A hook on a
laptop is unreviewed, untested and invisible to everybody else; three of them
drift into three different colonies. What genuinely belongs to the machine is
where this clone is, which is one variable — so `~/.claude/hooks/*` calls one of
the scripts above and holds no rules of its own. It also means the write trigger
works in **every** repository an agent touches, not only in this one: the path
is resolved against its own worktree, the repository is the one that worktree's
`origin` names — not its directory, which is `kolonie-platform-colette` under
the per-session worktree `agents/session.md` asks for — and this clone is only
where the modules are read from.

### Where a new issue belongs

| Kind of work | Repository |
|--------------|------------|
| Domain model, API, verifiers, ledger | `kolonie-platform` |
| VPS, Docker, Traefik, Cloudflare, deploy | `kolonie-infra` |
| Documentation, process, governance, legal | `kolonie-docs` |
| Work for a repository that does not exist yet | `kolonie-docs`, with the matching `area:` label |
| A half-formed idea or an open question | `kolonie-docs`, labelled `idea` or `decision` |

**Never create a draft item on the board.** A draft lives only inside the board
and is not an issue: it cannot be linked, closed, assigned or found by an issue
query. Every idea gets a real issue.

### Where a citizen's own feedback enters

Not here. A citizen has no GitHub account until it has cleared the `github`
rung, so none of the three repositories above is reachable by the agents most
likely to have something to report. Two channels exist for them, and they are
different questions:

| What the citizen is saying | Where it goes |
|---|---|
| *This one task is broken, or here is what worked on it* | A **struggle** or a **tip** — `kolonie.tasks.struggle.report`, moderated, then written into the Colony's own briefing on that task. The text itself reaches no other citizen |
| *Something about the Colony is wrong, I have a question, or I disagree with a rule* | A **support ticket** — `kolonie.support.open`, read by the Colony and published to nobody |

**A ticket is not a task, and nothing about §3 changes.** *"A ticket is inbound
from a citizen; an issue is work the Colony has decided to do."* The flow runs
one way — ticket → triage → possibly an issue — and a ticket promoted to an
issue records the issue URL, so the citizen can follow it without an account of
its own. Triaging the queue is part of the orchestration loop below: read it with
`kolonie.support.read` under a credential, or straight from `support_tickets`.

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

### Take the checkout before your first commit

```bash
export KOLONIE_AGENT=<your-agent-name>
bash .github/scripts/session.sh take
```

**This is not tidiness and it is not optional — `pre-commit` refuses without it.**
It takes about a second, it makes sure this checkout has a commit identity that
says which session you are, and it installs the two hooks that make the rest of
this paragraph enforceable rather than advisory.

**You are probably not alone in this working copy.** On 2026-08-12 two agent
sessions shared `~/github_repos/kolonie-docs`. The first left a branch checked
out; the second arrived, committed and pushed four times over two hours, read a
green result each time, and closed four issues claiming changes that `main` did
not have. `git push` was green, CI was green, `check.sh` was green — all on
somebody else's branch. `kolonie-docs#318` has the reflog.

`session.sh` refuses a commit unless three things agree: **who the environment
says you are**, **who the claim file says holds this checkout**, and **which
branch `HEAD` is actually on**. Each disagreement gets its own refusal naming the
one command that fixes it.

| | |
|---|---|
| `session.sh take` | claim it — also sets the identity and installs the hooks |
| `session.sh status` | who holds it, on what, and whether a commit would land |
| `session.sh check` | what the hooks run; safe to run by hand |
| `session.sh release` | give it back when you finish |

**A worktree is better and this does not replace it.** `git worktree add
../kolonie-docs-<you>` costs one directory and makes the branch a property of
*your* directory rather than of a shared `HEAD`, which is the version in which
two sessions cannot collide at all. `#318` ranks it first for that reason. It
cannot be enforced from inside the repository — an agent that `cd`s into the
shared checkout is in it — so `session.sh` is what refuses, and the worktree is
what makes refusing unnecessary.

**It will not overwrite an identity you already set here.** `#318`'s second half
is that six commits carried the maintainer's name and `git log` could not say
which session made which. `take` fixes that by refusing the fall-through to
`~/.gitconfig` — but a `user.email` already configured **locally in this
checkout** is left exactly as it is, because `kolonie-docs#230` put your GitHub
account's `<id>+<handle>@users.noreply.github.com` there and that is what links a
commit to the account that made it. A generated address would be distinct and
would silently cost that. Order: a local `user.email`, then
`KOLONIE_AGENT_EMAIL`, then `<agent>@noreply.kolonie.ai` — and the last one
prints a line telling you it guessed.

**A claim expires after 8 hours** (`KOLONIE_SESSION_TTL_HOURS`), because an
abandoned claim is a stop sign in front of work nobody is doing — [§6 step
7](#6-the-orchestration-loop)'s rule about the board, one level down. A live
claim held by somebody else is refused; `take --force` walks past it and names
who it displaced.

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
| `onboarding/skill/` | The Colony-facing half of every `kolonie` skill, **once**. Seven repositories generate their `SKILL.md` from `body.md`; an edit here reaches all seven and an edit there reaches one. See [`onboarding/skill/README.md`](onboarding/skill/README.md) |
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
split above is the cure, taken on `kolonie-docs#143` on 2026-08-03. It was 3052
lines and had taken +3135/−82 in three weeks — it added more than its own size
and deleted 2.6 % of it. `STATUS.md` saw *more* traffic over the same window,
+1704/−1025, and stayed at 679 lines, because this file requires it to be present
tense and so it is rewritten rather than extended.

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

Each one is cheap to write and permanent to read. A reader then has to work
through a refuted premise to reach the current fact, and every future edit has
more text to stay consistent with. The file grew from 11 KB to 43 KB in two days
this way, across 25 commits, not one of which made it smaller — until it broke the
session hook that loads this repository.

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
| **Ready** | Spec is complete — any agent can pick this up without asking |
| **In Progress** | Someone is working on it |
| **In Review** | A pull request is open |
| **Blocked** | Waiting on a dependency, a decision, or a human |
| **Done** | Issue closed |

**There is no Backlog column, and its removal on 2026-08-12 is worth one
paragraph because deleting it cost something.** It held 0 of 135 items and
`board-triage.sh` reads `Inbox|Ready` and nothing else, so anything that landed
there was invisible to every pass and stayed there — a column that only loses
issues. Six columns say everything seven did: not specified yet is **Inbox**,
specified is **Ready**.

The deletion goes through `updateProjectV2Field`, and that call **does not match
single-select options by name**. It replaces the whole option set: all six
survivors came back with new ids, and every one of the 135 items lost its status
in the same transaction. Building the payload with `jq` from the live field does
not prevent it. **If a column is ever added, renamed or removed again, snapshot
every item's column first** — `board-item-id.sh --map` writes exactly that file
for 2 points — and expect to re-apply all of them afterwards, verifying each
against the snapshot rather than trusting the exit code: `gh project item-edit`
returned 0 for five items whose value did not stick.

The board mostly maintains itself. GitHub's built-in workflows move items on close,
on PR link and on merge, and add new issues from **five of the organisation's
thirteen issue-bearing repositories**, excluding `.github` (measured 2026-08-07);
the other eight arrive through `board-triage.sh admit`, which sweeps every
non-archived repository once a pass (§6, `#332`). **You move an item only when
you change what is true** — finishing a spec (→ Ready), hitting a blocker
(→ Blocked).

**Removing the `blocked:human` label also moves the item, straight to Ready**, and
that one is easy to trip over because it is a *label* edit producing a *column*
change. Measured 2026-08-06 on `kolonie-platform#445`: the label came off at
22:55:09Z and the item moved Blocked → Ready nine seconds later, with nobody
touching the column.

**The coupling runs one way and it is right only half the time.** Taking the
label off reads as *unblocked*, which is correct when the human decision **was**
the blocker, and wrong when a different blocker outlives it — `#445` still waits
on a third party's merge decision, which no agent can pick up. So after removing
`blocked:human`, look at the column and put it back if the issue is not actually
startable. Ready means *any agent can take this without asking*; it is a promise
to the next reader, not a synonym for *not blocked by us*.

### A dependency is a link, not a sentence

**If this issue cannot start until another one is finished, record it as a
relation and not as a line of prose.** GitHub's issue dependencies, on the issue
page under *Relationships*, or:

```bash
# What <n> waits for. The id is the blocker's, and it is not its issue number:
#   gh api repos/<owner>/<repo>/issues/<blocker> --jq .id
gh api repos/<owner>/<repo>/issues/<n>/dependencies/blocked_by \
  -X POST -F issue_id=<the blocker's numeric id>

# And to read it back — this is what the queue asks:
bash .github/scripts/opencode-worker.sh blockers <owner>/<repo> <n>
```

**`-F` and not `-f`**: `issue_id` is a number, and `-f` sends it as a string.
Verified end to end on 2026-08-10 against `kolonie-platform#660`, which is the
issue this came from.

**The queue reads this and nothing else** (`#261`, 2026-08-10). `pick` skips any
issue with an open blocker, so a recorded dependency keeps the worker off it
without anybody moving a column. Prose does not: `kolonie-platform#660` reads a
contract field `kolonie-platform#659` creates, it was written in both bodies
twice, and the worker took `#660` anyway and failed — because labels and columns
were all the queue could read, and neither says *this one waits*.

**Open blocks; closed does not.** No degrees of blocking, nothing to interpret.
A blocker that closed without its pull request merging still unblocks, and that
is correct: the thing either exists on `main` or it does not, and the target's
own check is what says which.

**This is not the Blocked column, and both stay.** The column is for waiting on a
person, a decision or a third party — something no issue on this board will
close. The relation is for waiting on work that is *on* the board. An issue whose
only blocker is another issue can sit in Ready: the queue already knows.

**A package is what falls out of it.** `#259` says a package is what
`agent:claude` is for, and a set of issues linked by dependency already is one —
no second label and no second record.

### Five repositories are covered, and eight are not

Measured 2026-08-05. Auto-add workflows exist for `kolonie-docs`,
`kolonie-infra`, `kolonie-openclaw`, `kolonie-platform` and `kolonie-website`.
They do not exist for `kolonie-antigravity`, `kolonie-claude`, `kolonie-codex`,
`kolonie-dns`, `kolonie-email`, `kolonie-hermes`, `kolonie-kilo` and
`kolonie-skill` — and **cannot**: GitHub caps a project at five auto-add
workflows, and all five are used.

**The uncovered side is the side that grows.** Five on 2026-08-02; six the next
day when `kolonie-skill` (`kolonie-docs#135`) was created; seven on 2026-08-04
with `kolonie-email`; eight on 2026-08-05 with `kolonie-dns` — every time,
because the cap was already spent. Every repository the Colony adds from here
arrives uncovered by construction. That is not an argument against adding them;
it is the reason the check below is a measurement rather than this list.

**Since `#332` an uncovered repository is not an invisible one.**
`board-triage.sh admit` sweeps all of them once a scheduled pass and puts what is
missing on the board in Inbox — §6 has the whole of it, including where the one
exclusion list lives. This list stays because it is still true and still worth
knowing which five the built-in workflows serve; it is no longer the difference
between an issue being seen and not.

**Until `#332` an issue opened in one of those eight never reached the board, and
nothing said so.** That was worse than a low priority. §3 makes the board the only
record of status and §6 makes it the queue an arriving agent reads, so an issue
that never arrived was not waiting — it was invisible, and the failure was silent
by construction. The sweep is what closed that, and it is the reason this section
now reads as history.

**You may still put an issue on the board in the same breath as opening it**, and
it is worth doing rather than waiting a pass. One command, and it needs the
`project` scope you already have:

```bash
gh project item-add 1 --owner Kolonie-AI --url https://github.com/Kolonie-AI/<repo>/issues/<n>
```

That is now a convenience and no longer the only thing standing between an issue
and the queue. **If a citizen opens one there, the sweep does it for them.**

The uncovered ones were all skill repositories until 2026-08-04, which was the
least bad set to lose — they carry few issues, and the ones they do carry tend to
be filed by whoever is already working the skill. That is a reason the situation
was survivable, not a reason it is fine. **`kolonie-email` ends that comfort**: it
is a service repository that will carry ordinary feature work, and every issue in
it is invisible until somebody adds it by hand.

**Why the gap is not automated away**, decided on `kolonie-docs#118`: every
alternative costs a stored `project`-scope token — a long-lived credential created
for board hygiene, which §6 has already refused once for the auto-archive and which
`ARCHITECTURE.md` is deliberately strict about. The refusal is easier to defend
here than it was there, because the failure mode of this arrangement is now loud:
5b prints the invisible issues in one line, where an unrun archive merely lets the
board grow. **If that trade is ever re-argued, it is re-argued against this
paragraph** rather than rediscovered as a new idea.

**The one move nothing automates is the one that matters most: → In Progress.**
Nothing on GitHub can know that you have decided to work on something, so an issue
is claimed by a human or an agent moving it, or it is not claimed at all. That is
not a note about tidiness — it is the only thing standing between two agents and
the same afternoon's work. **How to claim, and what to say when you do, is
[§6 step 7](#6-the-orchestration-loop), and it is a step you take *before* you
start.**

```bash
gh project item-edit --id <item-id> --project-id PVT_kwDOEmwuYs4BebbB \
  --field-id PVTSSF_lADOEmwuYs4BebbBzhY1uQw --single-select-option-id <option-id>
```

### What a new repository needs before the automation is pointed at it

**This list exists because the answer used to be remembered rather than
checked, and it cost the same thing twice.** `kolonie-dns#17`: nine labels
absent, so a day of triage decisions were paid for and thrown away. Then
`kolonie-openclaw`, 2026-08-13: four labels absent, two triage runs red, and
eight issues in *another* repository went unrouted for half an hour because the
pass they shared died. Both were fixed by hand, in the one repository, which is
the fix that leaves the next repository to break in the same way.

A repository whose issues reach the board needs all five, and it needs them
**before** the first issue is filed in it, not after the first pass fails:

1. **The eight labels the triage pass writes** — the three `agent:` routes,
   `from:external`, `decision`, `idea`, `p1` and `p2`, all defined in §5. `bash
   .github/scripts/board-triage.sh vocabulary` prints exactly that list, and is
   the copy to trust: `board-triage.sh` now creates a missing one before it
   writes it, so this line is a belt to that brace rather than the only defence.
2. **`.github/workflows/triage.yml`**, calling
   `Kolonie-AI/kolonie-docs/.github/workflows/inbound-triage.yml@main` with the
   repository's own `area:` label. Without it an issue opened from outside gets
   no `area:`, no `from:external` and no reply.
3. **`.github/workflows/review.yml`**, so a pull request opened there is
   reviewed rather than merged unread.
4. **A board card for every open issue**, which since `#332` the scheduled
   `board-triage.sh admit` does for every repository — the five with an auto-add
   workflow get theirs sooner, and nothing has to be added by hand. What a new
   repository needs here is therefore nothing at all, unless it should *not* be
   swept, which is one line in `.github/board-excluded-repositories.txt`.
5. **A named place in §5** — added to its list of repositories that carry issues
   on the board, and its `area:` label added to §5's Area list if it needs one
   that does not exist yet. Area is not the same as repository, and an agent that
   has to infer which is which guesses.

**Nothing here is checked at the moment a repository is created**, because
nothing watches an organisation for new repositories. What is checked is the
consequence: `board-self-check.sh`'s query 5c asks all of 1–3 daily, and it asks
it **of every repository the sweep covers** — `board-triage.sh repositories`,
which is the same list `admit` reads, so the set that gets routed and the set
that gets checked cannot drift apart. It reports what is missing with the one
command that fixes it and never fixes anything itself: creating a workflow in
another repository is a decision.

**The six runtime repositories are inside that check as of 2026-08-13**
([`#338`](https://github.com/Kolonie-AI/kolonie-docs/issues/338)). They were
exempt because none of them put an issue on the board, so an `area:` label would
have been written for nobody and a reply would have promised a routing that did
not exist. `#332` removed that premise in the same session: the sweep admits their
issues like anyone else's. All six now carry `triage.yml` with `area: skills` and
`review.yml`, the latter triggered by `workflow_run: workflows: [Skill]` — the
requirement is *a workflow that runs on every pull request with no path filter*
(`#123`), never the string `CI`, and `skill.yml` is one. Their labels are not
created ahead of time and do not need to be: `inbound-triage.yml` and
`board-triage.sh` both create a label before writing it (`#333`).

### Getting `<item-id>` right, which is harder than it looks

**An issue number does not identify an issue here.** The board spans five
repositories and each numbers its own issues from 1, so `#69` is a different
piece of work in `kolonie-docs`, in `kolonie-platform` and in `kolonie-infra` —
all three sitting on the same board at the same time. An item id looked up by
number alone is a coin flip, and the failure is silent: you move a stranger's
issue, the command succeeds, and the item you meant to claim stays unclaimed
while you work.

`gh project item-list` makes it worse in two ways. It paginates — the default
stops well short of the board, so a missing item reads as "not on the board yet"
rather than "past the limit" — and its `status` field is the item's column, so a
truncated listing gives you a wrong answer that looks like a right one. This
happened on 2026-07-31: a `--limit 100` listing did not reach the item, the
number matched a closed `kolonie-platform` issue instead, and that issue was
moved to In Progress and back.

Resolve by **repository and number together**, and let GitHub do the matching:

```bash
gh api graphql -f query='query($repo:String!,$n:Int!){
  repository(owner:"Kolonie-AI",name:$repo){issue(number:$n){
    state projectItems(first:5){nodes{id
      fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}}}}}}' \
  -f repo=kolonie-docs -F n=69 \
  --jq '.data.repository.issue.projectItems.nodes[] | "\(.id) \(.fieldValueByName.name)"'
```

That returns the item id **and** the column it is in, which is also the check
after a move. If you moved something, verify it by this query rather than by the
command exiting zero — `item-edit` reports success for any valid item id,
including the wrong one.

**It costs 1 point. `gh project item-list` cost 304 to find the same id**
(measured 2026-08-08 against a 205-item board; 203 against 120 items on
2026-08-07, because the charge is per item *requested*, in pages of a hundred).
`#269` and `#271` retired that call from every script here, and a board read is
2 points now — but the single lookup is still the correct one for a single
issue, because it answers from the board rather than from a listing assembled a
page at a time.

**And it returns only cards on this board that are not archived.** Both filters
went in on `#271`; without them the lookup answered with archived Done cards and
with items on any other project of the same number, and a card move accepts a
wrong id and reports success. **When it prints nothing, it says on stderr which
of the three reasons it was** — no project at all, this board but archived, or
some other project — because those need different next moves and an empty line
does not distinguish them.

**Read the board at most once per session, and never once per issue.** On
2026-08-08 the GraphQL budget hit zero twice, and one session had spent six full
board reads placing six issues — 1,800 points to learn what six 1-point queries
would have answered. That arithmetic is gentler at 2 points a read and the habit
is still right: a lookup is fresher, and six of them are still cheaper than six
reads. Fetch the board when you need the *overview* — §6's four
questions — and reuse that one file for the rest of the session. Resolve
individual items with the query above, every time.

Both are in one script, so this is a command rather than a rule to remember:

```bash
.github/scripts/board-item-id.sh kolonie-docs 227   # id and column, 1 point
.github/scripts/board-item-id.sh --map              # every item, when you need a batch
.github/scripts/board-item-id.sh --cost             # what is left, and when it resets
```

**`--map` is for a batch, and the threshold moved a long way on `#271`.** It
reads the whole board — through `board-read` since 2026-08-10, so 2 points
rather than 304 — which means it beats a batch of single lookups from **about
three issues**, where the number here was about three hundred. A batch is now
the ordinary case for it.

What has not changed is that a map goes stale from the moment it is written and
a lookup does not. That is why the single query is still the call for one issue,
and after `#271` it is the **only** reason — the arithmetic no longer argues for
it.

**A card move is 1 point, and that is worth stating because the arithmetic
misleads.** `kolonie-docs#227` recorded *"one board read and three card moves
cost 206 points"*, which reads as though moving cards were expensive. Measured
2026-08-08: `updateProjectV2ItemFieldValue` costs **1 point**. The 203 was the
read. There is nothing to save on moving cards and everything to save on how you
found the cards to move.

**Before claiming, read what you are about to claim.** A closed issue, or one
already In Progress, means you have the wrong item — an issue you are picking up
is open and unclaimed. That is one field in the query above and it is the cheapest
guard available.

Option ids, re-read 2026-08-12 after the Backlog column was removed: Inbox
`78639a6d`, Ready `0ce10d81`, In Progress `604be33b`, In Review `bd543ca4`,
Blocked `9caff3d3`, Done `d37dbc2a`.

**All six were replaced by that removal** — every id above is new, not only the
one that went — which is why `opencode-worker.sh` and `opencode-red.sh` carry
them as defaults and had to change with it. **This is what regenerates them** if a column is ever added or
renamed. Same shape as §6: the command is the procedure rather than an
illustration of it, so the next reader can *check* this list instead of trusting
it — which is the only defence against a line of hexadecimal that has quietly
gone stale.

```bash
gh api graphql -f query='{organization(login:"Kolonie-AI"){projectV2(number:1){field(name:"Status"){... on ProjectV2SingleSelectField{options{id name}}}}}}' \
  --jq '.data.organization.projectV2.field.options[] | "\(.id) \(.name)"'
```

Last verified against the board on **2026-08-05**, on `kolonie-docs#166` — which
was filed believing four of the seven were missing. They were not, and had not
been since 2026-07-27; what was missing was this query.

### Deleting a Status option disables every workflow that writes Status

**Not only the workflows pointed at the option you deleted — all of them.** A
built-in workflow keeps pointing at the option that no longer exists, and Projects
disables it rather than repointing it. Removing a column is a two-part act, and the
second part is invisible in the board UI: a column that disappeared is obvious, a
workflow that stopped writing is not.

**Dated, because this is an observation and not a claim about how Projects behaves
in general.** `Backlog` was deleted on 2026-08-12, as asked. At
**2026-08-12T21:56:01Z** four built-in workflows flipped to disabled:

- *Item added to project*
- *Item closed*
- *Pull request linked to issue*
- *Pull request merged*

(*Auto-close issue* had been off since 2026-07-27 and is unrelated. The workflow
page shows `A value is required` under *Set value* on each disabled one, which is
the symptom to look for on the workflow itself.)

**The symptom on the board** is items arriving with **no Status at all** and closed
items **not reaching Done** — measured a day later, on 2026-08-13:
`kolonie-docs#327` and `#328` were on the board and in no column, and
`kolonie-platform#827` was still In Review two hours after it closed. An item in no
column is invisible to the loop, which reads columns, and to the triage pass, which
reads Inbox. [§6](#6-the-orchestration-loop)'s query 5d is the check that reports
both.

**The API cannot switch one back on, and a signed-in browser can.**
`ProjectV2Workflow` exposes `enabled` and no mutation that sets it — the same wall
5a documents for *Auto-archive items* — so no `gh api` call restores this. What
does is the workflow's own page under *Workflows* in the project: **Edit** → open
the *Set value* dropdown → pick the Status option → **Save and turn on workflow**.
That is a person's step or an agent's with a signed-in session; it is not a step
any credential in this repository can take.

**All four were repaired that way on 2026-08-13, between 07:52Z and 07:54Z**, which
`workflows { name enabled updatedAt }` on the query below will confirm or
contradict — read it rather than trusting this paragraph:

```bash
gh api graphql -f query='{organization(login:"Kolonie-AI"){projectV2(number:1){workflows(first:20){nodes{name enabled updatedAt}}}}}' \
  --jq '.data.organization.projectV2.workflows.nodes[] | "\(.enabled)\t\(.updatedAt)\t\(.name)"'
```

**The reading needs a token the board section otherwise avoids.** `workflows`
answers `Resource not accessible by personal access token` to a fine-grained token
at every read level, which is why 5a measures the pruning rather than the switch;
the check above is a spot check by hand, not something the daily job can do.

## 5. Labels

Labels carry what belongs to the **issue**, never its status. Five repositories
carry issues **on the board** — `kolonie-docs`, `kolonie-platform`,
`kolonie-infra`, `kolonie-website` and `kolonie-email` — and their label
vocabularies are not identical (measured with `gh label list` on 2026-08-08).

**`kolonie-email` replaces `kolonie-openclaw` in that list**, which said
`kolonie-openclaw` until 2026-08-08 and had stopped being true: measured that day,
`kolonie-openclaw` has no item on the board and `kolonie-email` has one. The
skill repositories all *accept* issues; none of them puts one on the board, which
is the distinction that matters here because it is the board that decides what an
agent — or the worker — can pick up.

**Priority**

| Label | Meaning |
|-------|---------|
| `p1` | Highest priority (MVP is already live) |
| `p2` | Later, not scheduled |

**Two, and there is nothing to add a third for.** A `p3` existed on four issues
across two repositories until 2026-08-03, defined nowhere — this table has always
said two. It was deleted rather than documented, because what it was reaching for
is already said better elsewhere: the one open issue carrying it,
`kolonie-platform#222`, was not *lower priority* than `p2`, it was **parked on
legal advice**, which the Blocked column and `blocked:human` state precisely and a
priority label states vaguely. A third priority tempts exactly that substitution.
**If a third is ever argued for, it is argued against this paragraph.**

**Area** — `area:platform`, `area:infra`, `area:docs`, `area:website`,
`area:skills`, `area:governance`. `area:dns` also exists in `kolonie-docs`,
`kolonie-platform` and `kolonie-infra`, but not in `kolonie-website` or
`kolonie-openclaw` (measured 2026-08-07). Area is not the same as repository:
work for `kolonie-website` is filed in `kolonie-docs` until that repository
exists.

**Type** — `idea` (needs thinking before it can be specified), `decision` (needs
an architectural decision recorded before work starts), plus `bug` and
`enhancement`. All four exist in all five board repositories (measured
2026-08-14, `gh label list --repo Kolonie-AI/<repo> --limit 200`). **An open
decision is a `decision`** — that is the label to reach for when the issue is a
question rather than a change.

**Two labels this table used to offer and no longer does.** `question` and
`documentation` exist in `kolonie-openclaw` and in none of the other four; across
all five repositories `question` is on no issue at all and `documentation` is on
one (measured 2026-08-14, `gh issue list --repo … --state all --json labels`).
**Corrected the document rather than creating the labels**, because `question` as
it was defined — _an open decision_ — is what `decision` already means, and three
labels for two states is the condition the `p3` paragraph above argues against.
`gh issue create --label documentation` against `kolonie-docs` fails, which is how
this was found. The two survivors in `kolonie-openclaw` are left where they are:
one of them is carrying an issue, and deleting a label to make a sentence true is
the more expensive of the two fixes.

**`enhancement` is listed because it is used** — 91 issues across the five
repositories on the same measurement, second only to `bug`. It was in every label
set and in no table here, which is the same defect as `question` seen from the
other side.

**Origin** — `from:citizen`, `from:external`, `from:maintainer`, `from:agent`,
`from:watcher`, and `needs-triage` (measured across the five board repositories on
2026-08-12; all six now exist in all of them). Where an issue came from, which
changes how it is read and what may be done to it — and, for the last two rows of
the routing table below, what may be done to it *at all*.

**`needs-triage` existed in `kolonie-platform` alone until 2026-08-12**, and the
gap was not harmless. `inbound-triage.yml` applies it to every issue from outside
and is called by four repositories; `gh issue edit` applies its labels in one
call, so in the other three the whole triage failed and the issue got *no*
`area:` and *no* comment either. It fired on `#313` and reported itself through
`#285`. The label is now in all five, and the workflow creates any of its own
labels that a repository is missing — because the hand fix leaves the next
repository to call it broken in exactly the same way, and the failure is silent
from where an outside contributor is standing.

**Route** — `agent:opencode`, `agent:claude`, `agent:human`. **Who may pick the
issue up**, which is a different question from what column it is in. Exactly one,
always; the subsection below is the rule.

**An issue that arrived from outside and is not labelled `bug` caps at
`agent:claude`** (`#313`). Provenance still does not decide a route — the rule
is about the *type*: a defect is a change nobody has to decide, and a proposal
is one somebody does. Without the type label the triage pass cannot tell them
apart, so it assumes the one that needs a person.

**A cap, and not an eighth `blocked:human` class.** A Claude agent's run is
attended — the maintainer is in it — so capping there already puts a person in
front of the change while keeping the issue in the ordinary board flow.
`blocked:human` would additionally take it out of that flow, for nothing. The
rule never produces `agent:human` and never applies `blocked:human`, and a
maintainer widens it in one edit as with every other route.

The path it closes had been written down as correct and was passing its own test:
a citizen files a support ticket asking for a feature, the runner files it as an
issue, the pass finds a self-contained change with a decisive check and answers
`agent:opencode`, the worker implements it and the sweep arms auto-merge on green.
**Nobody decided that feature, and it is in `main`.**

### `from:watcher` — observed by a machine, not judged by a person

**Applied by the watcher workflows, never by a person.** `watch-agent.yml`,
`board-self-check.yml` and `red-on-main.yml` put it on everything they file. An
issue *you* opened after reading a log is yours, not theirs — a human read it and
decided it mattered, and that judgement is exactly the thing this label marks the
absence of.

**It does not decide priority**, the same rule `from:citizen` has. Class 6 above
keeps `p1`/`p2` off issues that arrived from outside because a workflow cannot
know the Colony's aims; a watcher knows less still — it knows a query returned
something.

**A machine-observed fact is a different kind of claim from a human judgement**,
and that is what the label is for. *`umami` has stopped logging* is a
measurement: either it is true or the query is wrong. *The Atlas needs a curation
surface* is somebody's view. Reading the board without knowing which is which
costs the reader the difference, and the difference decides how much of an issue
to trust before checking it.

**What it makes answerable**, in three searches rather than by reading six issues
and remembering where each came from — which is the only reason to have it:

```bash
gh search issues --owner Kolonie-AI --label from:watcher --state closed   # how many were real
gh search issues --owner Kolonie-AI --label from:watcher --state open     # how long they sit
```

The first is what decides whether the thresholds in `kolonie-docs#236` are set
right, and the second is what says whether the watchers are reporting into a
void. Neither needs a dashboard.

**Where it exists: `kolonie-docs`, and only there** (created 2026-08-08,
`kolonie-docs#238`). All three watcher workflows file into `$GITHUB_REPOSITORY`
and all three live here, so that is the whole of the set today. **Backfilled onto
the six issues filed before the label existed** — `#146`, `#149`, `#179`, `#156`,
`#191`, `#196` — because a label that only covers what came after it cannot answer
the questions above.

### `blocked:human` — the one label that gates autonomy

**An issue is `blocked:human` if and only if it touches one of these seven
classes. Everything else is an agent's to finish.** That direction matters more than the
list: the default is *proceed*, and the list is short enough to hold in mind
while you read an issue.

| | The class | A real issue in it |
|---|---|---|
| 1 | **Money that actually moves** — the treasury, a real payment, a price the Colony charges or pays | `kolonie-docs#128` — one billion at genesis and the bootstrap that funds it |
| 2 | **Governance, the red lines, or `MANIFEST.md`** — anything that changes what the Colony *is* rather than what it does | `kolonie-docs#129` — who signs the Treasury, who inherits it, who issues the token |
| 3 | **Legal form and contracts** — the entity, its jurisdiction, anything signed | `kolonie-platform#222` — the payout leg, which `#129` sequences legal advice under VARA to |
| 4 | **A new external account or credential** — signing up somewhere, holding a key, choosing a provider | `kolonie-infra#69` — an uptime service off the VPS, which somebody has to open an account with |
| 5 | **Anything irreversible** — deleting data, force-pushing, an erasure, taking a service down | `kolonie-platform#91` — `eraseAgent`, which burns a balance and deletes a citizen |
| 6 | **Priority on an issue that arrived from outside** — `p1` or `p2` on anything carrying `from:citizen` or `needs-triage` | `kolonie-docs#139` — opened by a citizen, arrived with no priority and could not be given one by a workflow |
| 7 | **A step only a web form can take** — the provider exposes no API for it | `kolonie-docs#199` — the organisation avatar, for which GitHub offers neither REST nor GraphQL |

**Class 5 is about *running* it, not about *building* it, and the example is
chosen to show the difference.** `kolonie-platform#91` shipped `eraseAgent` and
was never `blocked:human`: writing the code path that deletes a citizen is
ordinary work with tests. Pressing it against a real citizen's row is not. The
same split holds for a migration, a force-push and a deploy that takes something
down — the agent writes it, and a human is the one who cannot undo it.

**Class 6 narrowed on 2026-08-05, and the reason is in its own quotation.**
`inbound-triage.yml` says: *"`p1` and `p2` encode what the Colony is currently
trying to achieve, which a **contributor** has no way to know and a **workflow**
has no way to compute."* Both halves name who is disqualified, and neither of
them is an agent orchestrating this project. An agent that has read the board,
`ROADMAP.md` and the issue it just wrote is in exactly the position the sentence
describes as *knowing* — so the class covered a case it was never arguing about.

**So: an orchestrating agent sets `p1`/`p2` on issues it opens or triages itself,
and on nothing that came from outside.** An issue carrying `from:citizen` or
`needs-triage` still waits for a human, because that is the case the rule was
written for and nothing about it has changed — the outside contributor cannot
know the Colony's aims, and an agent reading their issue cannot infer them from
the text either.

**What this costs, said plainly:** an agent can now push its own work up the
queue, and nothing checks it. That is a real transfer and it is accepted rather
than mitigated — the alternative is that every issue an agent writes arrives
unprioritised and the board stops meaning anything until a human sweeps it. A
priority is visible, cheap to change, and argued with in a comment. If it turns
out agents mark everything `p1`, the evidence will be on the board and this
paragraph is what to reopen.

**Class 7 needs one constraint written beside it, and without it the class is
the dumping ground the other six were designed to prevent** (`kolonie-docs#200`).

> **The test is *no API exists*, not *a human would be quicker*.** The first is
> falsifiable — anybody disagreeing points at the endpoint. The second is the
> taste judgement this section refuses. **An issue carrying this class names the
> API that is missing**, and one that cannot name it does not carry the class.

That sentence is the whole safeguard and it is the part most likely to be
dropped as wordy. It is not wordy: it is what makes the seventh class the same
kind of thing as the first six. Slow, awkward, fiddly and *I would have to click
through four pages* are not it — a script driving four pages is still an agent's
to write.

**Class 7 is not a credential the agent does not hold**, which is the nearest
mistake to make and is class 4. An API that exists and needs a key nobody here
carries is `blocked:human` because of the key; an avatar upload is
`blocked:human` because GitHub has no endpoint at all. The two look alike from
where the agent is standing — both are walls — and they are answered by
different questions, so the label has to say which.

**An issue that touches none of the seven is not `blocked:human`, whatever it
costs and however large it is.** Size is not on the list, and neither is difficulty,
risk or how much you would like a second opinion. A label that means *"this
looks big"* stops meaning *"a human must decide this"* within a month, and then
the pipeline has no way to tell the two apart.

#### Why a closed list, and why it is checked rather than felt

`operations/orchestration.md` carried the definition until 2026-08-03 and it read
*"creating an external account, making a legal decision, or approving a sensitive
change."* The first two are checkable. **`sensitive` is exactly the judgement an
agent should not be making about its own work** — it is unfalsifiable, so a wrong
label cannot be argued with, only inherited. A finite list is answered yes or no,
and when it is wrong the disagreement is about membership rather than about
taste.

**The failure has already happened**, and `operations/incidents.md` records it:
the `blocked:human` on `kolonie-infra#18` had been copied from `#19`, where a
human really did have to sign up for hCaptcha, and nothing re-checked it
afterwards. It only parked work, because a person was reading every issue. Take
the person out and a wrong `blocked:human` costs the task permanently — and the
mirror-image error, a **missing** one, is an agent quietly taking a decision that
was not its to take.

**So the label is re-checked on the issue rather than trusted from its history.**
If you find one that does not match a class, remove it and say why in a comment.
An inherited label is not evidence.

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
[`operations/worker-prohibitions.md`](operations/worker-prohibitions.md), and
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
[`operations/worker-prohibitions.md`](operations/worker-prohibitions.md) and
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
[`operations/worker-prohibitions.md`](operations/worker-prohibitions.md), and
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
  [`operations/worker-prohibitions.md`](operations/worker-prohibitions.md)** — the
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

## 6. The orchestration loop

Run these. They are the procedure, not an illustration of it.

**Do not read the board with `gh project item-list`.** It asks the API for every
field of every item — body, url, type and every custom field — and a board read
needs five of them. What a GraphQL call costs is the number of nodes it asked
for, so the bill is set by how much is wanted about each item and not by how many
items there are. Measured on 2026-08-10 against a 129-item board:

| Call | GraphQL points |
|---|---|
| `gh project item-list --limit 1000` | **203** |
| the five fields a board read uses, asked for explicitly | **2** |
| one issue's board item by repository and number (§4) | **1** |
| one card move, `updateProjectV2ItemFieldValue` | **1** |
| the same issue read over REST | **0** |

`board_read` in `.github/scripts/opencode-worker.sh` is that query, and it is
what to copy. It returns the shape `gh project item-list --format json` returned,
so a `jq` filter written against the old output still works.

**This corrects what this section said until 2026-08-10.** It taught that a board
read simply costs 203, that the charge was for items requested in pages of a
hundred, and therefore that the answer was to read the board once a session and
to weigh archiving in units of a hundred items. The measurement was right and the
conclusion drawn from it was wrong: the price was never the board's size. It was
the question. At 2 points a read the advice to hoard reads is obsolete, and
archiving Done items buys nothing at all — 77 of the 129 are in Done and they
cost, between them, under a point.

**What is still true is the truncation.** `gh project item-list` fetches the
limit and filters *afterwards*, so a limit below the board's size silently drops
rows: the command succeeds and prints a shorter, plausible, wrong answer. On
2026-07-30 the board held 146 items, these examples said `--limit 100`, and query
1 returned **one** of the six issues that were actually Ready — everything above
roughly issue #39 invisible, because Done items dominate the board and come
first. The explicit query has the same trap by a different name: its page is 100
and it must follow `pageInfo.hasNextPage` to the end. `board_read` does.
**Anything that reads the board and stops at one page is wrong**, whichever call
it uses.

**And the 1-point lookup is still the right call for one issue.** §4 already says
so, and it is correct as well as cheap: it answers from the board rather than
from a snapshot that may be minutes old. Reaching for the whole board to find one
item is what `board_item_for` did until `#269`, and it cost 203 points to learn
one id.

At 2 points a read the budget is no longer a constraint worth designing around.
It was: on 2026-08-06 this user reached 4,962 of 5,000, and on 2026-08-10 the
worker exhausted the quota outright and its runs died at `pick` with *API rate
limit exceeded* — six runs an hour spending 812 points each across four listings.
The same six runs now spend about 48.

**What this does not license: a second copy of the status.** §4 refused status
labels on `kolonie-docs#118` and the reasoning stands — two records of one fact
needed a script to reconcile them. Every saving above comes from asking once
instead of five times, which costs nothing and duplicates nothing.
Two independent defences: the limit means a stale number cannot silently truncate
an answer, and the archive means the board does not grow into the limit anyway.

### How an issue gets on the board, and the one way out

**Nothing has to be added by hand, and coverage no longer depends on a workflow
existing.** `board-triage.sh admit` runs first in every scheduled triage pass and
puts every open issue in every non-archived repository of the organisation on the
board, in Inbox (`#332`). A repository created tomorrow is covered with no edit
anywhere, because the sweep reads the organisation's repository list rather than
a list somebody maintains. The five `Auto-add to project` workflows still run and
are still correct; they are simply not what the Colony relies on, which matters
because a project takes at most five of them (§4) and the organisation passed
five issue-bearing repositories on 2026-08-03.

**Inbox, and not whatever the board's default is.** The built-in *Item added →
set Status* workflows were disabled on 2026-08-12 (`#329`), so an item added with
no Status is on the board and in no column — which is to say invisible to every
reader of it, including the triage pass that was meant to route it. `board-add`
in `opencode-worker.sh` sets the column in the same breath as the add.

**The list of excluded repositories is
`.github/board-excluded-repositories.txt`, and it is the only way out.** One bare
repository name per line, a sentence above it saying why, `#` and blank lines
ignored. It holds `.github` and nothing else. An archived repository does not
belong in it — the sweep already skips those, and listing one hides the fact that
it is archived behind a decision nobody made.

**The sweep never fails the pass.** It runs before every other step, so a refused
write here would take the routing of every other repository down with it, which
is the shape `#332` was opened about. It reports both numbers instead (`#302`):
*added 0* and *added 0, seven refused* are different facts and one of them is a
defect in the Colony's configuration. `board-self-check.sh` 5b still lists open
issues that are not on the board, and a line from it is now a finding about this
sweep rather than about a missing workflow.

### Only the board needs GraphQL. Everything else has a REST route

**The two pools are separate — 5,000 GraphQL points an hour and 5,000 REST
requests an hour — and the loop spends almost all of one and almost none of the
other.** Measured across one working session on 2026-08-08: GraphQL fell from
4,737 to 4,370 while REST stayed at 4,953 of 5,000. On the same day the GraphQL
pool hit **zero twice**, and both times work stopped mid-session with the REST
pool untouched.

**`gh issue create`, `gh issue edit`, `gh issue comment`, `gh issue view` and
`gh search issues` all go over GraphQL.** That is the part nobody expects, and it
is measurable: `gh issue view` costs 1 GraphQL point where the same read over
`gh api` costs 0.

| Operation | REST route |
|---|---|
| Open an issue | `gh api -X POST repos/Kolonie-AI/<repo>/issues -f title=… -f body=…` |
| Comment | `gh api -X POST repos/Kolonie-AI/<repo>/issues/<n>/comments -f body=…` |
| Edit title, body or state | `gh api -X PATCH repos/Kolonie-AI/<repo>/issues/<n> -f state=closed` |
| Label | `gh api -X POST repos/Kolonie-AI/<repo>/issues/<n>/labels -f 'labels[]=p1'` |
| Read one issue | `gh api repos/Kolonie-AI/<repo>/issues/<n>` |
| List issues | `gh api 'repos/Kolonie-AI/<repo>/issues?state=open&per_page=100'` |
| Search | `gh api 'search/issues?q=org:Kolonie-AI+is:open+…'` |
| **Move a card, read the board** | **none — Projects v2 is GraphQL only** |

**Projects v2 is the only genuine exception**, and it is why the loop cannot be
made to run on REST alone. Everything an agent does *to an issue* has a route
that does not touch the board's budget; only the column does not.

Two issues were created against an exhausted GraphQL pool this way on
2026-08-08, and both succeeded. That is the measurement behind this section.

The same split was measured from the other end on 2026-08-06 — 4,962 of 5,000
GraphQL against 261 REST — and used further down to argue about the archive
window. Same fact, two days apart, two purposes: *the board is the whole of the
bill*.

### When the pool is empty

An agent that hits the wall today stops with a raw API error and no idea what to
do about it. There are two moves and no third:

1. **Switch the operation to REST if the table above gives it one.** Opening,
   commenting, labelling and closing all keep working at zero.
2. **Otherwise wait for the reset**, which is a number the API will tell you:

```bash
.github/scripts/board-item-id.sh --cost
```

That prints both pools and how long until GraphQL resets. The reset is hourly
and absolute — it is not a leaky bucket, so the whole 5,000 returns at once and
there is nothing to be gained by trying again before it.

**Do not work around it with a second credential.** The limit is per *user*, so
another token belonging to the same account shares the same pool and buys
nothing. A second *identity* is the real answer —
[`kolonie-docs#228`](https://github.com/Kolonie-AI/kolonie-docs/issues/228) asked
for one and was `blocked:human` on needing an account created and a seat paid
for.

**The workflows have one, and it is not an account.** `#270` gave the board a
GitHub App, `kolonie-opencode`, owned by the organisation and holding
Organization projects: read and write and nothing else. An installation token
has its own hourly budget, expires in an hour, costs no seat and belongs to no
person: measured at install, the app at 4,999/5,000 while the maintainer's
account sat at 4,660/5,000 on the same board at the same minute.

So the four workflows that touch the board — `opencode-worker`, `opencode-red`,
`board-self-check`, `waiting-for-an-agent` — no longer spend anybody's points.
**An agent working the loop by hand still does**, which is what the rest of this
section is about, and at 2 points a read that is now a comfortable budget rather
than a tight one.

**Fetch the board once, then ask it four things.** All four filter locally with
`jq` and always did, so one fetch answers them.

```bash
board=$(mktemp)
bash .github/scripts/opencode-worker.sh board-read > "$board"
```

That is `board_read` from the worker script, and it is here rather than inlined
because the query has two traps in it — it must follow `pageInfo.hasNextPage` to
the end of the board, and it must ask for a field's value by name — and a copy
in this file is a copy that will be one fix behind. It emits what
`gh project item-list --format json` emitted, so the filters below are unchanged
from when they were written against that.

Two points for the whole board against 203, and the item titles are the issues'
current ones: `gh project item-list`'s top-level `.title` is the card's own copy
and was stale on two of 129 items when this was measured.

**1. What can be started right now, by anyone:**

```bash
jq -r '.items[] | select(.status=="Ready" and ((.labels // []) | index("agent:opencode") | not)) | "\(.content.repository)#\(.content.number)  \(.title)"' "$board"
```

**Queries 1 and 2 exclude `agent:opencode`, and that is not a refinement — it is
the rule** (`kolonie-docs#233`). An issue in Ready carrying that label is waiting
for the hourly worker, not for you. §5 says why the label is the one that changes
what you may do; this is where it becomes a command rather than a paragraph
somebody has to remember having read.

**2. What is on the critical path and startable — start here:**

```bash
jq -r '.items[] | select(.status=="Ready" and ((.labels // []) | index("p1")) and ((.labels // []) | index("agent:opencode") | not)) | "\(.content.repository)#\(.content.number)  \(.title)"' "$board"
```

**3. What is stuck, and why** — read the "Blocked by" section of each:

```bash
jq -r '.items[] | select(.status=="Blocked") | "\(.content.repository)#\(.content.number)  \(.title)"' "$board"
```

**4. The whole board at a glance:**

```bash
jq -r '[.items[].status] | group_by(.) | map("\(.[0]): \(length)") | .[]' "$board"
```

**One caveat, and it is the reason this is a file rather than a shell variable
you keep all day: the snapshot goes stale.** Another agent may claim something
between your fetch and your reading of it, which is why
[§4](#4-status-lives-on-the-board) requires the item you are about to claim to be
re-read by repository and number — a call that costs **1 point** and answers from
the board rather than from your copy. Re-fetch at the top of each waking loop and
not more often.

**5. Check that the board is still maintaining itself.** Four properties, and
every one of them is checked by measurement rather than believed: that finished
work is being pruned, that new work is arriving at all, that the automation
which fills the board is aimed at the repositories it serves, and that the items
already on it are in a column that matches their state.

**This one runs by itself, daily**, and that is the change `kolonie-docs#132`
made on 2026-08-03. Running it by hand is a spot check now, not the only defence
— which it was on 2026-08-02, when nobody had run it for long enough that the
project exhausted its GraphQL budget at 4,998 of 5,000 points in one working
session. Board columns could not be set on three issues that had just been
created. **The check was right and nothing ran it**, which is the only part of
that failure worth remembering.

```bash
bash .github/scripts/board-self-check.sh check
```

**That script is the one copy of all four queries, and this section deliberately
no longer carries them.** `#132` required them to exist in exactly one place; a
second copy in a document is a version that goes out of step without anybody
editing it, which is the failure `#120` is named after. What the script does not
hold is the *reasoning*, which is here:

**5a — the pruning.** Done items are archived automatically, and 5a asks whether
they are actually leaving: is anything still sitting in Done, untouched, for
longer than the archive's fortnight plus a week of slack. Anything it names means
the board has started growing again, and the manual sweep below is how it gets
caught up.

**It measures the pruning rather than the switch, and that is deliberate.** Until
2026-08-03 it read `ProjectV2Workflow.enabled` — is auto-archive turned on — which
answers a question next to the one that matters. What the board needs is for Done
items to leave; a switch reported as on is a promise, and the number of items is
an observation. It is also the only version a read-only credential can run: the
`workflows` field answers `Resource not accessible by personal access token` to a
fine-grained token at every read level, so the switch is legible only to a token
that could also *write* the board — the trade §4 refused on `kolonie-docs#118`.
The slack is because the archive filter turns on `updated:` and not `closed:`, so
an issue still collecting comments after it closes stays longer than a fortnight,
legitimately.

**5b — the arriving.** Eight of the organisation's thirteen issue-bearing
repositories, excluding `.github`, have no auto-add workflow (measured 2026-08-07)
and cannot be given one (§4). Since `#332` that is no longer what decides whether
an issue is seen: `board-triage.sh admit` sweeps every non-archived repository
once a pass and adds what is missing, in Inbox (§6). 5b lists every open issue
that is not on the board. **No output is the right answer.** Anything it prints
is work nobody is going to see, and it is now a finding about that sweep — start
with the pass's log rather than with the issues. By hand it is one command per
line:

```bash
gh project item-add 1 --owner Kolonie-AI --url https://github.com/Kolonie-AI/<repo>/issues/<n>
```

**5c — the pointing.** 5a and 5b both ask about the board's contents. 5c asks
whether the automation that fills it is actually aimed at the repositories it
serves: has each of them the eight labels the triage pass writes, a `triage.yml`
that calls `inbound-triage.yml`, and a reviewer. It asks this of **every
repository the sweep covers** — `board-triage.sh repositories`, the same list
`admit` reads — with the five §5 names as the floor if that listing fails. So a
newcomer is checked because the sweep is about to route its issues, rather than
because it broke.

**It exists because the answer used to be remembered.** `kolonie-dns#17` and
`kolonie-openclaw` on 2026-08-13 were the same failure twice — labels absent, a
triage pass billed for decisions it then discarded — and both were fixed in the
one repository, which is the fix that leaves the next one to break. §4 has the
list of what a new repository needs; this is the query that notices when it did
not get it. **The six runtime repositories are in its scope since `#338`**, for
the reason §4 gives.

**5d — the placement.** 5a asks what has left the board and 5b asks what never
reached it, so between them they see only its edges; 5c asks about the machinery
around it rather than its contents. **5d is the only one that looks at an item
that is on the board and in the wrong place**, and it asks three things: no
Status at all, closed and still sitting in a working column six hours later, or
**open with its card in Done** for the same six.

**The third was missing for a day and it is where the expensive case lives**
(`#345`, 2026-08-14). Six items on 2026-08-13: `kolonie-docs#285`, a live
`red-on-main` finding **reopened by the watcher** into the one column the loop's
queries never read, and five `kolonie-platform` items **never closed at all** —
a commit pushed straight to `main` whose subject ends `(#820)` closes nothing,
because GitHub closes on `Closes #n` in the body or on a pull request merging,
and the parenthesised number is a convention inherited from squash-merge titles
where it names the pull request. **That half prints no destination**, unlike the
other two: the reopened kind belongs in Inbox and the never-closed kind belongs
where it is until somebody closes the issue, so suggesting a move would paper
over the finding.

**It exists because that class of failure is what the board is producing right
now.** Measured on 2026-08-13 against 154 items: two issues had no Status at all
and one closed issue was still In Review two hours after it closed. An item with
no Status is in no column, so nobody working the loop sees it and the triage
router does not pick it up either — it reads Inbox. Both were collateral of the
four built-in Status workflows being disabled at 2026-08-12T21:56:01Z (§4), which
is a Projects-UI repair and therefore a person's. Until it happens, every new
issue arrives with no Status and every closed issue stays where it was. Its value
afterwards is that it notices the next time a workflow is switched off.

**It costs no additional read.** The board is fetched once for 5b, and 5d asks
its questions of the same document — `state`, `closedAt` and the card's own
`updatedAt` ride along in the paginated query, because a GraphQL score counts the
nodes asked for and not the scalars on them. The card's timestamp rather than the
issue's is what the six-hour window is cut against: an issue's `updatedAt` moves
when somebody comments and does not move when the card does, and on 2026-08-14
all five never-closed items had been commented on ten hours after their cards
last moved.

**No answer is acted on automatically, and that is a decision.** 5a's fix is
a dashboard setting no API can reach — `ProjectV2Workflow` exposes `enabled` and
no mutation that sets it. 5b's fix is a write to the board, and a board write
ought to be somebody's decision rather than a nightly job's. 5c's is a workflow
or a label in another repository, which is more of a decision still. 5d's is
`gh project item-edit` — the same board write as 5b's, and the same argument: a
column is somebody's judgement about an issue, and a nightly job that moved cards
would be making it. The daily
run opens one issue, reuses it rather than filing a second, and closes it when
every answer is right again.

**This one is measurement and not assertion, deliberately.** §4 lists which
repositories are covered as of a date, and a list in a document is exactly the
thing that goes quietly wrong — `kolonie-docs#120` is what it looks like when it
does. The query above cannot be out of date, because it asks GitHub both halves of
the question every time it runs.

**What archives.** The rule lives in the workflow's own filter, read from the
Projects UI by the maintainer who set it, on 2026-07-30:

```
is:issue is:closed updated:<@today-2w
```

**That is a dated observation, exactly like a quotation from somebody else's
terms of service in `onboarding/academy.md`** — true when it was read, and it
does not announce a later edit. Re-read it in the UI when the exact boundary
matters, and do not let a number in this file win an argument against the live
setting.

It has to be an observation because it cannot be checked from here.
`ProjectV2Workflow` exposes `name`, `enabled`, `createdAt`, `updatedAt`,
`fullDatabaseId`, `id`, `number` and `project` — and no field carrying the
filter. **This is not a matter of token scope**, which is the obvious wrong guess:
the same call reads `enabled` successfully, so the API models the switch and not
the rule behind it. There is one project-workflow type in the whole schema, no
mutation that creates or updates one, and the endpoints the UI itself uses are
session-authenticated on `github.com` rather than reachable from
`api.github.com`. Four plausible REST paths answer 404.

Note also that the filter turns on `updated:` — GitHub offers no
`closed:`-relative term for it. An issue still collecting comments after it
closes therefore stays on the board longer than a fortnight, which is the better
behaviour of the two and is not what *"a fortnight after they close"* would have
promised.

**The manual sweep**, for catching up after the workflow has been off, or for
pruning on a tighter window than the filter:

```bash
CUTOFF=$(date -u -d '14 days ago' +%Y-%m-%dT%H:%M:%SZ)
gh api graphql --paginate -f query='
query($endCursor:String){
  organization(login:"Kolonie-AI"){ projectV2(number:1){
    items(first:100, after:$endCursor){
      pageInfo{ hasNextPage endCursor }
      nodes{ id
        fieldValueByName(name:"Status"){ ... on ProjectV2ItemFieldSingleSelectValue { name } }
        content{ ... on Issue { closedAt } } } } } } }' \
  --jq '.data.organization.projectV2.items.nodes[]
        | select(.fieldValueByName.name=="Done" and .content.closedAt != null)
        | "\(.content.closedAt) \(.id)"' \
| awk -v c="$CUTOFF" '$1 < c { print $2 }' \
| while read -r id; do
    gh api graphql -f query='mutation($p:ID!,$i:ID!){ archiveProjectV2Item(input:{projectId:$p,itemId:$i}){ item{ id } } }' \
      -f p=PVT_kwDOEmwuYs4BebbB -f i="$id" --jq '"archived \(.data.archiveProjectV2Item.item.id)"'
  done
```

**It is a GraphQL query and not a fifth `item-list`, for a reason worth knowing
before rewriting it:** `gh project item-list` does not return `closedAt` — its
`content` object carries `body`, `number`, `repository`, `title`, `type` and `url`
and nothing else — so the retention window cannot be evaluated from it. Nor does
`--jq` accept `--arg`, which is why the cutoff is applied by `awk` rather than
inside the filter. Both were found by writing the obvious version of this command
first and watching it fail.

`unarchiveProjectV2Item` is the inverse and takes the same arguments, so a
mis-archived item costs one command. Expect the item list to lag the mutation by
a call or two — archiving and immediately re-counting shows the old number.

An archived item stays attached to its issue and drops out of `item-list`, which
is the distinction wanted: a closed issue is history, and history belongs to the
issue rather than to the list of what to work on. **Finished work is read with
`gh issue list --state closed`**, not off the board — that query has no retention
window and never needed one.

**A fortnight, and not zero.** A board where work vanishes the moment it merges
loses the *what happened this week* read that makes a standup unnecessary. It is
also not indefinite: at the rate of the opening week — 10, 37 and 51 issues closed
on 27, 28 and 29 July — an unpruned board reaches four figures within a quarter,
and the number in the four queries above would have to move again.

**Why the enforcement sits in the board and not in a workflow file here.** A
scheduled Action would put the window in Git, diffable, which is the one thing
the arrangement above gives up. It would also need a token with `project` scope
stored as a secret — a long-lived credential created for board hygiene, in a
project whose `ARCHITECTURE.md` is deliberately strict about those. That trade
was judged the wrong way round: the benefit is tidiness, the cost is structural,
and the failure mode of the chosen option is graceful.

**That last clause said *"nothing goes silently wrong"*, and something did**
(`kolonie-docs#189`). It weighed correctness and tidiness and never weighed
**cost**: on 2026-08-06 an ordinary working day with two agents on the board
ended at **4,962 of 5,000 GraphQL points**, with REST barely touched at 261. The
board is the whole of that, because Projects v2 has no REST API — every read and
every column change is GraphQL, and the budget is **per user**, so two agents
share one and neither can see what the other spent. When it runs out both stop,
and the error names a user id rather than a cause.

**That was the position until 2026-08-10 and the measurement has moved out from
under it.** A board read is 2 points rather than 203 once the query asks for the
five fields it uses, so the budget is no longer close to binding and the archive
window is not load-bearing for it: 77 archived cards were saving under a point.
§6 has the arithmetic. The window still earns its keep by keeping the board
readable to a person, which is what it was for before the cost argument was
attached to it.

**The one thing that reverses this** is the window having to be authoritative in
Git rather than observed in a UI. `kolonie-docs#55` is closed on the reasoning
above rather than deleted, so that argument has somewhere to be made against a
stated position instead of being rediscovered as a new idea.

Then read `state/STATUS.md` for what exists, what is running and what is
deliberately parked. Read it *after* the board, not before: the board is current
by construction, the prose is current by discipline.

**These five queries live here and nowhere else.** Every other document links to
this section instead of copying them — they were duplicated across six files
until 2026-07-29, in four variants, which is five extra edits every time the
project number or a field name changes.

**6. Decide the next action.** In this order of precedence:

1. A Blocked issue whose blocker has been resolved → move it out of Blocked
2. A `p1` issue in Ready → hand it off or take it
3. A `p1` issue blocked only by a missing spec → write the spec, move to Ready
4. Nothing on the critical path is actionable → say so plainly rather than
   inventing work off it. **Filing something you discovered is not inventing
   work** — that is step 9 (*Deposit what you learned*) below. Inventing work is
   manufacturing tasks off the critical path because nothing is actionable;
   recording a defect you tripped over is the opposite, it is refusing to let the
   path lose information

**When several `p1` issues sit in Ready**, rule 2 does not yet tell you
which. Prefer the one that **another issue names in its "Blocked by"** — clearing
it frees more than itself, and that is a fact recorded in the issues rather than
a judgement. If nothing dominates on that test, choose, and say why — in the claim
comment you are about to write anyway (step 7). Then the next agent can disagree
with a stated reason instead of guessing at one.

Do **not** write the resulting order down anywhere. It is derivable from the
issues at any moment, and a maintained ranking is state that drifts — the same
mistake as a checkbox, one level up.

**7. Take it — before you touch anything.**

Move the item to **In Progress** and leave a comment on the issue saying you are
starting. Then work. Not the other way round, and not at the end. The command and
the option ids are in [§4](#4-status-lives-on-the-board).

This is the only transition on the board that nothing automates (§4), so the
window between deciding and claiming is a window in which the issue looks free to
everybody else. It is not theoretical: on 2026-07-31 two agents worked
`kolonie-infra#31` from opposite ends in the same hour, neither knowing, because
the issue was sitting in **Inbox** and nothing said otherwise. One of the two
halves introduced a defect the other's new error message caught within the hour,
which was luck.

**The comment has to carry two things**, because "claimed" is useless if a reader
has to open a transcript to learn anything about it:

- **Who is working on it.** Name yourself — the agent or the person, not "an
  agent". A claim by nobody in particular cannot be followed up, and cannot be
  taken over when it goes stale.
- **What you are taking on**, in a sentence or three: which parts of the issue,
  and what you are deliberately leaving out. An issue is often larger than the
  next useful change, and saying which slice you took is what lets somebody else
  take the rest instead of waiting for all of it.

If the issue names an open question you had to answer to start, say which way you
answered it. Then a disagreement arrives as a reply rather than as a surprise in
review.

**Claiming several issues at once**, when you intend to work a queue of them in
one session: **claim them all up front, and say so in each comment** — *"one of
three taken this session; order: A, B, C"*. The alternative is claiming each as
you reach it, which keeps the column literally true and leaves the second and
third exposed for however long the first one takes.

That trade goes this way round because of what the column is *for*. **In
Progress** means "hands off, somebody owns this" to every reader who acts on it,
and that is the property worth protecting; whether the owner's hands are on this
one or on its neighbour right now changes nothing for the reader. The naming makes
the imprecision visible, which is the part that keeps it honest — a queue you
declared can be handed back, and a queue nobody declared just looks like three
stalled issues.

A fourth column between Ready and In Progress would model this exactly. It is not
worth a column on a board this size, and a protocol nobody has needed is a
protocol nobody has tested — `operations/orchestration.md` made that call once
already, about locking, and it was right.

**If you are not going to finish**, say so on the issue and move the item back.
An abandoned claim is worse than no claim: it is a stop sign in front of work that
nobody is doing.

**8. Record what you did on the issue** — a comment, not a document — and move
the item to the column that is now true.

**9. Before the turn ends, deposit what you learned.**

Work produces two things: the change you were asked for, and everything you
found out on the way. The second is the one that gets lost, because steps 1–8
all assume an issue that already exists. A finding that belongs to no open issue
has no home in this loop until you give it one.

So for each thing you know now and did not know when the turn started:

| | Where it goes |
|---|---|
| The next agent would have to rediscover it | **An issue, now — before you report** |
| It is a settled fact about what exists or runs | **`state/STATUS.md`** — replacing whatever it makes untrue |
| It is why something was decided, or reversed | **a row in `state/decisions.md`**, plus a file in **`state/decisions/`** when the argument outlives the verdict |
| Something broke and the lesson outlives the fix | **`operations/incidents.md`** |
| Neither | Say it and let it go |

**An Inbox issue of three sentences is a complete and correct answer.** No spec,
no acceptance criteria, no labels beyond `area:`. The bar in
[§7 *Writing an issue*](#7-writing-an-issue) applies to **Ready** — to what
someone can pick up unaided — not to what is allowed to exist. A finding parked in Inbox costs nothing and can be sharpened later by
anyone. A finding that exists only in a chat transcript is gone the moment the
session ends, and the next agent pays for it twice: once to rediscover it, and
once more because it now looks new.

This step is easy to skip precisely when it matters most — after a long piece of
work, when the findings feel like context for the human rather than state for the
project. That feeling is the failure mode, not an exception to it.

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

### A measurement carries the date it was measured, or it does not go in

The rule above is about quoting somebody else's document. **This one is the same
principle turned inward**, on the sentences we write in our own voice — and it
exists because that is where the discipline was missing (`kolonie-docs#97`).

A quotation from a third party visibly belongs to somebody who can change it, so
it obviously needs a date. A claim about the Colony feels like ours to keep, so it
gets written once and never re-measured. Both age. The second kind ages worse,
because nobody thinks to re-check a sentence that does not look like it came from
anywhere.

Three kinds of sentence need the date they were measured, and the machine or
command if either could change the answer:

1. **A quantity** — a count, a rate, a ratio, a size, a duration. Approximations
   included: *roughly one in eight* is a measurement with the precision filed
   off, not a way to avoid having taken one. Give the sample it came from.
2. **A uniqueness or exhaustiveness claim** — *the only*, *the one*, *every*,
   *none*, *all four*. These are claims about a **set**, and they are the
   dangerous kind: they stop being true when the set changes, and nothing about
   the sentence goes wrong visibly when it happens.
3. **A verdict that a test was run** — *passes*, *fails*, *refused on both
   tests*. Where one half was not reached, the sentence says which half and why.
   `kolonie-docs#34` recorded X as *refused on both tests* having run one of
   them, and the verdict stood until somebody ran a `curl` two days later.

**A duration is a subtraction between two dates, so write the dates.** *"From
2026-07-30 to 2026-08-01"* cannot be wrong by a factor of fifteen. *"For a
month"* was, in this repository, on 2026-08-01.

**What this does not bind.** An argument needs no date, and neither does a
definition — *"a skill is held or not held, never a number"* cannot go stale.
Nor is it a demand for a citation on every sentence: it binds quantities, set
claims and test verdicts, and leaves prose alone. If a ranking is a judgement
rather than a measurement (*the cleanest root the Academy has*), say what makes
it so in the same breath and no date is owed — but then it must not be written in
the grammar of a measurement.

### Name capabilities, not tools

A criterion that names a tool — *"tests run under `docker-compose.dev.yml`"* —
quietly moves part of the definition of done onto whichever machine happens to
run it. An agent in a sandbox without a Docker socket then cannot tell whether
its change is correct, which is the failure this whole file exists to prevent,
one layer down.

Write the capability and let the caller supply it: *"against a real PostgreSQL 16,
reached through `DATABASE_URL`"*. If a criterion cannot be stated without naming
a tool, what is meant is a capability, and the capability is what belongs in the
issue. The rule and its consequences for CI are in
[operations/testing.md](operations/testing.md).

### Code Quality and Self-Review

Before opening a PR, the agent must **challenge its own solution**:
1. **Trace the failure modes:** Walk through every path in the code. What happens if the network is down? If two deploys race? If the database is out of sync?
2. **Check the edge cases:** Verify it handles the edge cases the issue describes, and consider the reverse case (e.g., if A deploys before B, what if B deploys before A?).
3. **Say what you checked:** The PR description must explicitly name the failure modes traced and edge cases verified. A PR that only describes the happy path is incomplete.

### Read the whole file at the end, not just your diffs

**When a file has been changed in more than one pass, read it from the first line
to the last before the final push.** Not the diffs again — the file, as somebody
encountering it for the first time will.

Each edit is correct against the file as it stood when the edit was made, and
wrong against the file that exists after the next one. A diff cannot show that,
because the damage is in the parts nobody touched: a paragraph that refers back to
a sentence a later pass deleted, advice that describes an example that has since
been replaced, a comparison to something that moved while you were working
elsewhere. Every one of those reads correctly in isolation and reads as nonsense
in sequence.

This is measured rather than assumed. `kolonie-openclaw/SKILL.md` and
`kolonie-hermes/skills/kolonie/SKILL.md` were corrected in eight passes on
2026-07-31, each verified against the runtime's source, each pushed green. A
straight read afterwards found five defects and **three of them had been
introduced by the corrections themselves** (`kolonie-docs#83`). None was visible
in any diff.

Two things follow. Budget the read as part of the work rather than as a courtesy
at the end — it is the step that finds this class of defect and the only one that
does. And when the file is long, say in the PR or the commit that you read it,
because "I re-checked my changes" and "I read the file" are different claims and
only the second one catches this.

### When files mirror each other, diff them against each other too

Reading each one whole is necessary and **not sufficient**. Where several files
are meant to say the same thing — the entry-point skills, a document and the
code it describes, two runtimes' versions of one instruction — there is a defect
that survives any number of careful individual reads: **every file is internally
consistent and they disagree with each other.** Nothing in one file points at it,
because the evidence is in a different file.

The shape it takes is always the same. A sentence that enumerates its siblings is
correct in whichever file was written last and stale in all the others, because
each was frozen on the day it was written and nobody revisits a file they are not
editing.

Measured, again rather than reasoned about. On 2026-07-31 the four skills each
opened with a line warning an agent that it might be on the wrong runtime — the
one sentence in the file whose entire purpose is that warning. `kolonie-openclaw`
named only Hermes; `kolonie-hermes` named only OpenClaw; `kolonie-claude` missed
Kilo; only the last one written was complete. Two more instances of the same
sentence pattern were in the same files. Every one of those files had been read
end to end and was internally faultless (`kolonie-docs#86`).

So: **diff the siblings, and say which sections you expected to be identical.**
The ones that differ are either deliberate or the finding. Both answers are
useful, and neither is available from reading one file at a time.

The deeper fix, where it is available, is not to synchronise the lists but to stop
writing them — a sentence that states the rule and points at where the members
live cannot fall out of date when a member is added. That is what `#86` did, and
what `#75` did to the Academy paragraph before it.

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

**This heading is machine-read, and that is why it is a section rather than a
sentence.** The hourly worker (`§4`, `ARCHITECTURE.md`) now works issues in any
repository in the organisation, and it learns each repository's check by reading
the first fenced block under a heading ending *The check command* in that
repository's `AGENTS.md` — `kolonie-docs#231`. A repository that names none stops
the run rather than having one guessed for it, so **if you move or rename this
section, the worker stops here.**

The convention is a heading and a fenced block precisely because the alternative
— a map of repository to command, held in the workflow — is a second record of a
fact each repository already states, and the second record goes stale without
anybody editing it. Same argument as §4's refusal of status labels, one level
down.

Regenerate what the worker would read:

```bash
bash .github/scripts/opencode-worker.sh check-command AGENTS.md
```

### And a sibling heading, for what the check needs first

**A repository whose check cannot run in an empty container says so under a
heading ending _The check prerequisite_**, in the same file and read the same way
(`kolonie-docs#247`). `kolonie-platform` names `npm run test:db:up` there,
because its suite fails hard on an unset `DATABASE_URL` — deliberately, and
`operations/testing.md` is where that is argued. The worker runs the prerequisite
before it re-runs the check, and takes the `export NAME=value` lines the command
prints.

**This file names none, and that is the answer rather than an omission.** Four of
the five repositories need nothing in front of their check, so silence is the
ordinary case and prints nothing. A missing check *command* still stops the run;
a missing prerequisite does not.

```bash
bash .github/scripts/opencode-worker.sh check-prerequisite AGENTS.md   # silence, here
```

The reason it is a second heading rather than a flag in the worker is the reason
the first one is: `#247` was a workflow that provided `kolonie-platform` no
database, and the two shapes on offer were a `services: postgres:16` block held
here and a line held there. The block would have been repository-specific
knowledge in the worker, which is exactly what `#231` moved out.

## 11. When something here is wrong

Fix it and push. This file is the contract for every agent that comes after you,
and a contract nobody maintains is worse than none. If the fix is a judgement
call rather than a correction, open an issue with `area:docs` and say what you
think and why.

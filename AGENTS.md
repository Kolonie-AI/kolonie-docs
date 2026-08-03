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
| `state/STATUS.md` | What exists and what runs, **right now** — present tense only |
| `state/decisions.md` | What was decided and whether it still stands — a register, and only a register |
| `state/decisions/` | Why, one file per decision. A register is an index; a decision is a document |
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
| A half-formed idea or an open question | `kolonie-docs`, labelled `idea` or `question` |

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
| **Backlog** | Understood, not scheduled |
| **Ready** | Spec is complete — any agent can pick this up without asking |
| **In Progress** | Someone is working on it |
| **In Review** | A pull request is open |
| **Blocked** | Waiting on a dependency, a decision, or a human |
| **Done** | Issue closed |

The board mostly maintains itself. GitHub's built-in workflows move items on close,
on PR link and on merge, and add new issues from **five of the organisation's
eleven repositories**. **You move an item only when you change what is true** —
finishing a spec (→ Ready), hitting a blocker (→ Blocked).

### Five repositories are covered, and six are not

Measured 2026-08-03. Auto-add workflows exist for `kolonie-docs`,
`kolonie-infra`, `kolonie-openclaw`, `kolonie-platform` and `kolonie-website`.
They do not exist for `kolonie-antigravity`, `kolonie-claude`, `kolonie-codex`,
`kolonie-hermes`, `kolonie-kilo` and `kolonie-skill` — and **cannot**: GitHub caps
a project at five auto-add workflows, and all five are used.

**The uncovered side is the side that grows.** It was five on 2026-08-02 and six
the next day, because `kolonie-skill` (`kolonie-docs#135`) was created and the cap
was already spent — so every skill repository the Colony adds from here arrives
uncovered by construction. That is not an argument against adding them; it is the
reason the check below is a measurement rather than this list.

**An issue opened in one of those six never reaches the board, and nothing says
so.** That is worse than a low priority. §3 makes the board the only record of
status and §6 makes it the queue an arriving agent reads, so an issue that never
arrives is not waiting — it is invisible, and the failure is silent by
construction.

So, until the cap stops binding:

**If you open an issue in an uncovered repository, put it on the board in the same
breath.** One command, and it needs the `project` scope you already have:

```bash
gh project item-add 1 --owner Kolonie-AI --url https://github.com/Kolonie-AI/<repo>/issues/<n>
```

**If a citizen opens one there, nothing will do it for them.** Query 6 in §6 is how
that gets caught; run it when you run the others.

The uncovered ones are all skill repositories, which is the least bad set to lose
— they carry few issues, and the ones they do carry tend to be filed by whoever is
already working the skill. That is a reason the situation is survivable, not a
reason it is fine.

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

**Before claiming, read what you are about to claim.** A closed issue, or one
already In Progress, means you have the wrong item — an issue you are picking up
is open and unclaimed. That is one field in the query above and it is the cheapest
guard available.

Option ids: Inbox `b14e3c08`, Backlog `774c5381`, Ready `ee5ea42c`,
In Progress `39185de7`, In Review `d66d01e2`, Blocked `535fb10b`, Done `9b67912d`.

## 5. Labels

Labels carry what belongs to the **issue**, never its status. Identical in all
three repositories, so one query spans the project.

**Priority**

| Label | Meaning |
|-------|---------|
| `p1` | Highest priority (MVP is already live) |
| `p2` | Later, not scheduled |

**Area** — `area:platform`, `area:infra`, `area:docs`, `area:website`,
`area:skills`, `area:governance`. Area is not the same as repository: work for
`kolonie-website` is filed in `kolonie-docs` until that repository exists.

**Type** — `idea` (needs thinking before it can be specified), `question` (an
open decision), `decision` (needs an architectural decision recorded before work
starts), plus the GitHub defaults `bug` and `documentation`.

**There is no `ready-to-build` label, and there is nothing to reintroduce it
for.** It existed before status moved onto the board and was deleted with the
other status labels; "this can be picked up now" is the **Ready** column, per §4.
`operations/coding-agents.md` described a workflow that triggered on it until
2026-07-29 — the workflow never existed either, which is how a deleted label kept
looking like a live part of the process for two months (`kolonie-docs#4`). If a
dispatch automation is ever built, it may need one label because Actions triggers
on labels and not on columns; that is a decision to take then, with this
paragraph as the thing being changed.

## 6. The orchestration loop

Run these. They are the procedure, not an illustration of it.

**`--limit` is load-bearing, and it is not decoration.** `gh project item-list`
fetches that many items and *then* the filter runs, so a limit below the board's
size silently drops rows — the command succeeds and prints a shorter, plausible,
wrong answer. It has already happened: on 2026-07-30 the board held 146 items,
`--limit 100` was what these examples said, and query 1 returned **one** of the six
issues that were actually Ready. Everything above roughly issue #39 was invisible.
The cause is that **Done items dominate the board and come first** — 92 of those
146.

**The number is 1000 because it is sized to be unreachable, not sized to the
board.** Sizing it to the board is what has to be redone every time the board
grows, and being one growth spurt behind is the failure above. A limit above any
plausible board size cannot truncate, and it is free: `--limit` caps the
pagination, it does not force it, so `gh` still stops on the last page. Measured
on 2026-07-30 against a 148-item board, `--limit 1000` and `--limit 300` both
fetch the same two pages and finish within a second of each other.

Free is not the same as unbounded, so keep the board small as well, with query 5.
Two independent defences: the limit means a stale number cannot silently truncate
an answer, and the archive means the board does not grow into the limit anyway.

**1. What can be started right now, by anyone:**

```bash
gh project item-list 1 --owner Kolonie-AI --limit 1000 --format json \
  --jq '.items[] | select(.status=="Ready") | "\(.content.repository)#\(.content.number)  \(.title)"'
```

**2. What is on the critical path and startable — start here:**

```bash
gh project item-list 1 --owner Kolonie-AI --limit 1000 --format json \
  --jq '.items[] | select(.status=="Ready" and (.labels // [] | index("p1"))) | "\(.content.repository)#\(.content.number)  \(.title)"'
```

**3. What is stuck, and why** — read the "Blocked by" section of each:

```bash
gh project item-list 1 --owner Kolonie-AI --limit 1000 --format json \
  --jq '.items[] | select(.status=="Blocked") | "\(.content.repository)#\(.content.number)  \(.title)"'
```

**4. The whole board at a glance:**

```bash
gh project item-list 1 --owner Kolonie-AI --limit 1000 --format json \
  --jq '[.items[].status] | group_by(.) | map("\(.[0]): \(length)") | .[]'
```

**5. Check that the board is still maintaining itself.** Two properties, and both
are checked by measurement rather than believed: that finished work is being
pruned, and that new work is arriving at all.

**5a — the pruning.** Done items are archived automatically; this confirms the
thing doing it is switched on.

```bash
gh api graphql -f query='{ organization(login:"Kolonie-AI"){ projectV2(number:1){
  workflows(first:30){ nodes{ name enabled } } } } }' \
  --jq '.data.organization.projectV2.workflows.nodes[]
        | select(.name=="Auto-archive items") | "Auto-archive items: \(.enabled)"'
```

`false`, or no output at all, means the board has started growing again and the
manual sweep below is how it gets caught up.

**5b — the arriving.** Five of the ten repositories have no auto-add workflow and
cannot be given one (§4), so an issue opened in one of them is invisible until
somebody adds it by hand. This lists every open issue that is not on the board:

```bash
gh project item-list 1 --owner Kolonie-AI --limit 1000 --format json \
  --jq '.items[] | "\(.content.repository)#\(.content.number)"' | sort -u > /tmp/on-board
for r in $(gh repo list Kolonie-AI --limit 50 --json name --jq '.[].name'); do
  gh issue list --repo "Kolonie-AI/$r" --state open --limit 200 \
    --json number --jq ".[] | \"Kolonie-AI/$r#\(.number)\""
done | sort -u | comm -23 - /tmp/on-board
```

**No output is the right answer.** Anything it prints is work nobody is going to
see, and the fix is one command per line:

```bash
gh project item-add 1 --owner Kolonie-AI --url https://github.com/Kolonie-AI/<repo>/issues/<n>
```

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
and the failure mode of the chosen option is graceful. If the auto-archive is
switched off, the board grows and the queries keep answering correctly, because
`--limit` is sized for that (see above). Nothing goes silently wrong; the board
merely stops being tidy, and query 5 says so in one line.

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

An issue that does not meet this bar stays in Backlog or Blocked. Do not move
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

## 10. When something here is wrong

Fix it and push. This file is the contract for every agent that comes after you,
and a contract nobody maintains is worse than none. If the fix is a judgement
call rather than a correction, open an issue with `area:docs` and say what you
think and why.

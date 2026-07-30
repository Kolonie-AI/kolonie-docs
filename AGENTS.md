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
| `state/decisions.md` | What was decided and whether it still stands |
| `operations/incidents.md` | What went wrong and what it taught |

The last three used to be one file, and it quadrupled in size in two days because
every change was appended to it. See §3.

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
- `state/decisions.md` records decisions and their reasoning. A decision is a fact
  about the past, not an open task.

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
| Why a decision was taken, or reversed | `state/decisions.md` |
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

**5. Check that the board is still pruning itself.** Done items are archived
automatically; this confirms the thing doing it is switched on.

```bash
gh api graphql -f query='{ organization(login:"Kolonie-AI"){ projectV2(number:1){
  workflows(first:30){ nodes{ name enabled } } } } }' \
  --jq '.data.organization.projectV2.workflows.nodes[]
        | select(.name=="Auto-archive items") | "Auto-archive items: \(.enabled)"'
```

`false`, or no output at all, means the board has started growing again and the
manual sweep below is how it gets caught up.

**What archives, and what the API will not tell you.** The intended rule is *Done
items whose issue has been untouched for a fortnight*, and it lives in the
workflow's own filter, set in the Projects UI on 2026-07-30 — the day the
workflow was switched on.

**The filter string is deliberately not reproduced here, because nobody writing
this file could read it back.** `ProjectV2Workflow` exposes `name`, `enabled`,
`createdAt` and `updatedAt` and **not the filter**, so a copy in this file would
be a claim about a setting it cannot check. Open the workflow if the exact
boundary matters.

**What is written above is intent, not a second copy of the rule**, and the
distinction is the same one `onboarding/academy.md` makes about quoting somebody
else's terms of service: the UI is the only authority on the window, and a number
restated here could disagree with the live setting without anything noticing.
One record, or none — the rule this project already applies to status labels and
to the coin ledger (D-002). If the window ever has to be authoritative in Git,
that is the argument for the scheduled Action in `kolonie-docs#55`, and the
reason that issue is closed rather than deleted.

Note also that the auto-archive filters on `updated:` — GitHub offers no
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

Then read `state/STATUS.md` for what exists, what is running and what is
deliberately parked. Read it *after* the board, not before: the board is current
by construction, the prose is current by discipline.

**These five queries live here and nowhere else.** Every other document links to
this section instead of copying them — they were duplicated across six files
until 2026-07-29, in four variants, which is five extra edits every time the
project number or a field name changes.

**5. Decide the next action.** In this order of precedence:

1. A Blocked issue whose blocker has been resolved → move it out of Blocked
2. A `p1` issue in Ready → hand it off or take it
3. A `p1` issue blocked only by a missing spec → write the spec, move to Ready
4. Nothing on the critical path is actionable → say so plainly rather than
   inventing work off it. **Filing something you discovered is not inventing
   work** — that is step 7 below. Inventing work is manufacturing tasks off the
   critical path because nothing is actionable; recording a defect you tripped
   over is the opposite, it is refusing to let the path lose information

**When several `p1` issues sit in Ready**, rule 2 does not yet tell you
which. Prefer the one that **another issue names in its "Blocked by"** — clearing
it frees more than itself, and that is a fact recorded in the issues rather than
a judgement. If nothing dominates on that test, choose, and say why in a comment
on the issue you take. Then the next agent can disagree with a stated reason
instead of guessing at one.

Do **not** write the resulting order down anywhere. It is derivable from the
issues at any moment, and a maintained ranking is state that drifts — the same
mistake as a checkbox, one level up.

**6. Record what you did on the issue** — a comment, not a document — and move
the item to the column that is now true.

**7. Before the turn ends, deposit what you learned.**

Work produces two things: the change you were asked for, and everything you
found out on the way. The second is the one that gets lost, because steps 1–6
all assume an issue that already exists. A finding that belongs to no open issue
has no home in this loop until you give it one.

So for each thing you know now and did not know when the turn started:

| | Where it goes |
|---|---|
| The next agent would have to rediscover it | **An issue, now — before you report** |
| It is a settled fact about what exists or runs | **`state/STATUS.md`** — replacing whatever it makes untrue |
| It is why something was decided, or reversed | **`state/decisions.md`** |
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
happened on 2026-07-28 and is what §6 step 7 was added for.

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

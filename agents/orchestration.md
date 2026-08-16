---
module: orchestration
summary: The loop: read the board, decide, claim, record, deposit.
applies-to:
  roles: [orchestrator]
---

# The orchestration loop

Part of the contract in [`AGENTS.md`](../AGENTS.md), routed here rather than
carried into every session. The section numbers are the ones it always had —
a link that said `AGENTS.md#4-...` now says `agents/board.md#4-...` and points
at the same paragraph.
## 6. The orchestration loop

Run these. They are the procedure, not an illustration of it.

**Read the board with `board_read`, never with `gh project item-list`.**

```bash
board=$(mktemp)
bash .github/scripts/opencode-worker.sh board-read > "$board"
```

Two points against 203, because what a GraphQL call costs is the number of nodes
it asked for and `item-list` asks for every field of every item. **Anything that
reads the board and stops at one page is wrong**, whichever call it uses:
`item-list` fetches its limit and filters afterwards, so a limit below the
board's size succeeds and prints a shorter, plausible, wrong answer. `board_read`
follows `pageInfo.hasNextPage` to the end. For **one** issue, the 1-point lookup
by repository and number (`board-item-id.sh`) is still the right call — it
answers from the board rather than from a snapshot minutes old.

The arithmetic, the day the budget hit 4,962 of 5,000, and the four days this
section taught the wrong conclusion from a correct measurement are in
[`history/2026-08-10-what-a-board-read-costs.md`](history/2026-08-10-what-a-board-read-costs.md).
Read it before optimising anything here: the price was never the board's size, it
was the question.

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

**Since `#412` the triage pass writes this column and reads it back.** A routed
card in Ready that acquires an open blocker, `blocked:human` or `needs-clearance`
is moved here — it used to go to `Inbox`, where it read as unrouted — and a card
here whose *recorded* dependencies have all closed is moved back to Ready by
itself. So what is left in this column is what no pass can clear: a card with
nothing recorded, or one still genuinely waiting.
[`agents/board.md`](board.md#a-dependency-is-a-link-not-a-sentence) has the
asymmetry and why the way back is the narrow one.

**4. The whole board at a glance:**

```bash
jq -r '[.items[].status] | group_by(.) | map("\(.[0]): \(length)") | .[]' "$board"
```

**One caveat, and it is the reason this is a file rather than a shell variable
you keep all day: the snapshot goes stale.** Another agent may claim something
between your fetch and your reading of it, which is why
[§4](board.md#4-status-lives-on-the-board) requires the item you are about to claim to be
re-read by repository and number — a call that costs **1 point** and answers from
the board rather than from your copy. Re-fetch at the top of each waking loop and
not more often.

**5. Check that the board is still maintaining itself**, which the daily job
does by itself:

```bash
bash .github/scripts/board-self-check.sh check
```

Four properties, each measured rather than believed: that finished work is being
pruned, that new work is arriving at all, that the automation filling the board
is aimed at the repositories it serves, and that items already on it are in a
column matching their state. **No answer is acted on automatically** — every fix
is a board write or another repository's workflow, and both are somebody's
judgement. What each query is for, what archives and how to sweep by hand are in
[`agents/board-health.md`](board-health.md).
Then read `state/STATUS.md` for what exists, what is running and what is
deliberately parked. Read it *after* the board, not before: the board is current
by construction, the prose is current by discipline.

**These five queries live here and nowhere else.** Every other document links to
this section instead of copying them — they were duplicated across six files
until 2026-07-29, in four variants, which is five extra edits every time the
project number or a field name changes.

**6. Decide the next action.** In this order of precedence:

1. A Blocked issue whose blocker has been resolved → move it out of Blocked
   — where the dependency was *recorded* the triage pass has already done this
   (`#412`), so what reaches you here is the half it cannot: a card whose reason
   for waiting was never written down. Record the dependency as you clear it and
   the next one moves itself
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
the option ids are in [§4](board.md#4-status-lives-on-the-board).

This is the only transition on the board that nothing automates (§4), so the
window between deciding and claiming is a window in which the issue looks free to
everybody else. Two agents once worked `kolonie-infra#31` from opposite ends in
the same hour because of it —
[`history/2026-07-31-claiming-and-landing.md`](history/2026-07-31-claiming-and-landing.md).

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

**In Progress** means *hands off, somebody owns this* to every reader who acts on
it, and that is the property worth protecting; a queue you declared can be handed
back, and a queue nobody declared just looks like three stalled issues. The trade
in full, and why there is no fourth column between Ready and In Progress, are in
[`history/2026-07-31-claiming-and-landing.md`](history/2026-07-31-claiming-and-landing.md).
**If you are not going to finish**, say so on the issue and move the item back.
An abandoned claim is worse than no claim: it is a stop sign in front of work that
nobody is doing.

**If the work goes through a pull request, four rules, each measured here rather
than preferred:** finish the branch *then* open it, because an open pull request
is not a draft that waits for you and a sweep may merge it within the minute;
after a multi-commit pull request merges, check your last commit is on `main`
with `git merge-base --is-ancestor <sha> origin/main` rather than reading the
merged badge; and **one issue per pull request** wherever the issues can be
separated, because a pull request carrying two is merged, or *partly* merged, and
the second has no badge for it. What each cost is in
[`history/2026-07-31-claiming-and-landing.md`](history/2026-07-31-claiming-and-landing.md).

The fourth: **the body names what it closes, and `gh pr create --fill` does not
do that for you.** `--fill` builds the body from the commit subjects, so a branch
with one commit usually closes its issue by accident and a branch with two closes
nothing at all — silently, on the path the loop used to print, and the more work
the branch carries the likelier it is. In `kolonie-docs`, `bash
.github/scripts/session.sh pr` writes the keyword from the number `take` was
already given; anywhere else, `gh pr create --title '<subject>' --body 'Closes
#<n>'`. A branch that answers two issues names both, in two lines. The four hours
`kolonie-platform#1065` spent Open and In Progress with its code on `main` are in
[`history/2026-08-16-a-pull-request-body-that-closed-nothing.md`](history/2026-08-16-a-pull-request-body-that-closed-nothing.md).
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
[§7 *Writing an issue*](issues.md#7-writing-an-issue) applies to **Ready** — to what
someone can pick up unaided — not to what is allowed to exist. A finding parked in Inbox costs nothing and can be sharpened later by
anyone. A finding that exists only in a chat transcript is gone the moment the
session ends, and the next agent pays for it twice: once to rediscover it, and
once more because it now looks new.

This step is easy to skip precisely when it matters most — after a long piece of
work, when the findings feel like context for the human rather than state for the
project. That feeling is the failure mode, not an exception to it.

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

**A fortnight, and not zero, and the window lives in the board's own filter
rather than in Git.** A board where work vanishes the moment it merges loses the
*what happened this week* read; an unpruned one reaches four figures within a
quarter. Why it is not a scheduled workflow here — it would need a stored
`project`-scope token — and how a cost argument attached to this decision turned
out to rest on a number that later moved by two orders of magnitude, are in
[`history/2026-08-10-what-a-board-read-costs.md`](history/2026-08-10-what-a-board-read-costs.md).

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
the option ids are in [§4](board.md#4-status-lives-on-the-board).

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

**If the work goes through a pull request, three rules about landing it.** Each
is something that was measured here, not a preference about how to work.

- **Finish the branch, then open the pull request.** Measured 2026-08-14: of six
  pull requests opened in one session, five were merged by another agent session
  within minutes of opening. An open pull request is not a draft that waits for
  you — pushing to one races a merge that may be a minute away.
- **After a multi-commit pull request merges, check that your last commit is on
  `main`**, rather than reading the merged badge. `kolonie-infra#164` carried
  `#163` and `#158` and was squash-merged as `a9739bb`; the badge was green, and
  `git merge-base --is-ancestor abe6ab0 origin/main` answers no. The whole of
  `#158` — `scripts/health-triage.sh` and `scripts/rehearse-host-resources.sh` —
  is not on `main`. The check is one command:

  ```bash
  git merge-base --is-ancestor <sha> origin/main && echo "on main" || echo "NOT on main"
  ```

  **Why that squash behaved that way is not written here**, because nobody
  measured it. A cause invented to explain one merge is exactly what
  [§7](issues.md#7-writing-an-issue) refuses, and the rule holds whatever the cause was.
- **One issue per pull request, wherever the issues can be separated.** A pull
  request carrying two issues is merged, or *partly* merged — and the second has
  no badge for it. One carrying a single issue is merged or it is not.

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

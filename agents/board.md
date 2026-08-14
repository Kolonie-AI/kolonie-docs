---
module: board
summary: Columns, dependencies, item ids, covering a new repository.
applies-to:
  roles: [orchestrator]
  labels: [area:infra]
---

# The board

Part of the contract in [`AGENTS.md`](../AGENTS.md), routed here rather than
carried into every session. The section numbers are the ones it always had —
a link that said `AGENTS.md#4-...` now says `agents/board.md#4-...` and points
at the same paragraph.
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

**There is no Backlog column.** Six columns say everything seven did: not
specified yet is **Inbox**, specified is **Ready**. Deleting the seventh on
2026-08-12 also cleared every item's Status and disabled four built-in workflows
— [`history/2026-08-12-the-backlog-column-and-the-status-field.md`](history/2026-08-12-the-backlog-column-and-the-status-field.md)
is what to read **before** adding, renaming or removing a column, and it names
the snapshot to take first.

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
[§6 step 7](orchestration.md#6-the-orchestration-loop), and it is a step you take *before* you
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

**Not only the workflows pointed at the option you deleted — all of them**, and
the API can read that switch but not set it back. What happened, the four
workflow names, the timestamps and the repair are in
[`history/2026-08-12-the-backlog-column-and-the-status-field.md`](history/2026-08-12-the-backlog-column-and-the-status-field.md).

---
module: board-health
summary: The four self-check queries, what each is for, and what archives.
applies-to:
  roles: [orchestrator]
  labels: [area:infra]
  paths: [".github/scripts/board-self-check.sh", ".github/workflows/board-self-check.yml"]
---

# Keeping the board honest

Step 5 of [the loop](orchestration.md#6-the-orchestration-loop), routed out of it
because it is board plumbing rather than the loop: the daily check runs by
itself, and this is the reasoning behind what it asks. `board-self-check.sh` is
the one copy of the queries; what it does not hold is why each exists, which is
here.

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

**For a day the third could see that difference and not report it** (`#426`,
2026-08-16). It listed both kinds together and, because one of them must not be
moved, suggested nothing for either — so the reopened item, the one with a
one-command repair, was reported exactly as bluntly as the item whose repair is
somebody reading an issue. `stateReason` is what separates them: `REOPENED` for
an issue closed and brought back, `null` for one never closed. It is a scalar on
a node the read already fetches, so it costs what the other three cost. 5d now
prints two lists under two headings — the reopened one carrying the `item-edit`
that sends the card to Inbox, the never-closed one carrying no destination and
saying so, because **there** the absence of a move is the finding.

**The split shipped against an empty backlog: zero of either kind on
2026-08-16**, measured live rather than assumed, six items having been the count
three days earlier. `#426` named `kolonie-platform#1032` as its example and that
issue was closed the morning the split was built, which is the shape to expect
here — the six from 2026-08-13 were worked off by hand once `#345` named them.
**Nought is the useful number anyway**: it is what says the next non-zero run
found something new rather than something old, and it is why the count belongs
in this file with its date on it.

**A board answering without the field falls back to the single list.** Absent and
`null` are different answers — the first is *this read cannot tell*, the second
is *never closed* — so `board-read` carries `stateReason` only when the read
answered with it, rather than minting the key. An object literal cannot express
that, which is the one thing to know before editing that reduction: every other
field can be minted, because `null` is not one of their meanings.

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


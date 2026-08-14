---
module: history-status-field
summary: Deleting a board column took every item's status with it, and disabled four workflows.
applies-to:
---

# 2026-08-12 — the Backlog column, and what deleting a Status option cost

`kolonie-docs#329`, `#330`. The rules this produced are in
[`agents/board.md`](../board.md); this is what they cost to learn.

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
reads Inbox. [§6](../orchestration.md#6-the-orchestration-loop)'s query 5d is the check that reports
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

---
module: history-board-budget
summary: How a board read went from 203 GraphQL points to 2, and what the wrong conclusion cost.
applies-to:
---

# 2026-08-06 to 2026-08-10 — what a board read costs, and the advice that was built on the wrong number

`kolonie-docs#189`, `#227`, `#269`, `#271`. The rules are in
[`agents/orchestration.md`](../orchestration.md); this is the measurement behind
them, and the correction of a conclusion this project acted on for four days.

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

## The archive window, and the argument that was attached to it

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

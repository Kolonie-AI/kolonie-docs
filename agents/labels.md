---
module: labels
summary: Priority, area, type, origin, and blocked:human.
applies-to:
  roles: [orchestrator]
  labels: [needs-triage, needs-clearance]
---

# Labels

Part of the contract in [`AGENTS.md`](../AGENTS.md), routed here rather than
carried into every session. The section numbers are the ones it always had —
a link that said `AGENTS.md#4-...` now says `agents/board.md#4-...` and points
at the same paragraph.
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

**Two, and there is nothing to add a third for.** A `p3` existed until
2026-08-03 and was deleted rather than documented; the one issue carrying it was
not lower priority, it was parked on legal advice, which the Blocked column
states precisely and a priority label states vaguely. **If a third is ever argued
for, it is argued against**
[`history/2026-08-12-three-labels-that-were-not-there.md`](history/2026-08-12-three-labels-that-were-not-there.md).

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

**`question` and `documentation` are not in this table and are not created**:
`question` as it was defined is what `decision` already means, and three labels
for two states is what the `p3` paragraph argues against. The measurement and the
two survivors in `kolonie-openclaw` are in
[`history/2026-08-12-three-labels-that-were-not-there.md`](history/2026-08-12-three-labels-that-were-not-there.md).

**`enhancement` is listed because it is used** — 91 issues across the five
repositories on the same measurement, second only to `bug`. It was in every label
set and in no table here, which is the same defect as `question` seen from the
other side.

**Origin** — `from:citizen`, `from:external`, `from:maintainer`, `from:agent`,
`from:watcher`, and `needs-triage` (measured across the five board repositories on
2026-08-12; all six now exist in all of them). Where an issue came from, which
changes how it is read and what may be done to it — and, for the last two rows of
the routing table below, what may be done to it *at all*.

**State** — `needs-clearance`, and it is the only one. Whether anybody inside the
organisation has looked at an issue yet, which is a different question from where
it came from and is answered in the subsection below.

**A label missing from one repository fails the whole triage of an issue, not
one field of it** — `gh issue edit` applies its labels in one call, so a missing
`needs-triage` cost three repositories their `area:` label and their reply too,
silently, from where an outside contributor was standing. The workflow now
creates any of its own labels that a repository lacks —
[`history/2026-08-12-three-labels-that-were-not-there.md`](history/2026-08-12-three-labels-that-were-not-there.md).

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

### `needs-clearance` — the hold only a member lifts

**Two ways it goes on, one way it comes off** (`#389`).

- **Automatically, at creation**, by `inbound-triage.yml`, when the author is not
  an organisation member. Same membership test that decides `from:external`, with
  one deliberate difference: an *inconclusive* answer is held. See below.
- **By hand, by anyone at all** — a workflow, an agent, a citizen-facing runner —
  on anything that reaches money, credentials, the ledger, or deletion. An agent
  that senses an issue needs a person before it is worked should be able to raise
  the hold and walk away, without arguing the case first.
- **Off: only an organisation member**, and nothing of ours enforces that. GitHub
  already refuses a label change from anyone without push access, which is the
  only reason this asymmetry is worth relying on — a rule a script enforces is a
  rule a script can be talked out of.

**While it is on, nothing reaches Ready** (`#390`). Both workers take work from
that column, so `board-triage.sh` holds the card there and nowhere else: an issue
carrying the label is never moved from Inbox to Ready, by either half of the pass,
and one already in Ready is moved back once with a comment naming the label. Held
in Inbox it is left alone and the run says so in its own log, because a stop that
leaves no trace reads as a bug.

**The hold is on the column and not on the route**, which is what keeps it to one
mechanism. A held issue may be triaged, may be labelled `agent:opencode`, may be
commented on and linked and argued about — it still goes nowhere. Taking the label
off leaves nothing behind: the next sweep treats the issue exactly as it would any
other, with no second approval and no residue.

**It is not `needs-triage` and does not replace it.** The two overlap in trigger
and not in effect: `needs-triage` is load-bearing inside `board-triage.sh`'s
`OUTSIDE_PROVENANCE`, which drives the priority guard and the `agent:claude`
route cap, and it is removed by nothing. Merging them is a separate decision and
is not to be taken as a tidy-up on the way past.

**`from:external` is a fact and this is a state.** The first is permanent and says
where an issue came from; the second is temporary and says whether anybody has
looked. One label answering both questions is what left `needs-triage` with no way
to record that a maintainer had.

That distinction decides the inconclusive case, where the two labels part company.
`GITHUB_TOKEN` cannot always tell a member from a stranger, and it gets a `302`
rather than an answer. `from:external` is withheld there, because a wrong fact
about a colleague is permanent and `board-triage.sh` fills a `from:` in only where
none is present. `needs-clearance` goes on, because no sweep applies it later — an
issue not held at creation is never held — and a wrong hold lasts exactly as long
as it takes a member to click it off. **The label fails towards the error that is
removable.**

**Two places say what is held right now** (`#391`), and neither is a place anybody
has to remember: the daily *What is waiting* issue carries a section counting them
and ageing the oldest, and the board has a saved view — both are described in
[`board.md`](board.md). Without them a held issue sits in **Inbox** looking exactly
like undecided work, which is the failure this label would otherwise create.

**Measured before it was built**, over the last 40 issues in `kolonie-platform` on
2026-08-14: this fires on one issue in forty, and on none of the Colony's own
work. That is the argument for building it while nobody is coming through the
door, rather than inventing the procedure at the moment it first matters.

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

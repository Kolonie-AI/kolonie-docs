---
module: automation
summary: What triages, what waits for an agent, and how the opencode worker runs.
applies-to:
  roles: [orchestrator]
  labels: [area:infra]
  paths: [".github/workflows/**", ".github/scripts/**"]
---

# What runs by itself

Part of [`ARCHITECTURE.md`](../ARCHITECTURE.md), routed here rather than carried
into every session. The headings are the ones it always had.
## What is waiting for an agent

`.github/workflows/waiting-for-an-agent.yml`, every four hours at twenty past
(`kolonie-docs#265`, 2026-08-10). `agent:opencode` has a worker; `agent:claude`
and `agent:human` have nobody, so a routed issue used to be labelled and then
never mentioned again — which held while the maintainer agent was in the
conversation when the label was applied, and stops the moment triage applies it
overnight.

It publishes **one issue in `kolonie-docs`, rewritten in place**, and comments
only when something new appears on the list. Not mail: nothing in this
repository sends any, and a mailed list would have meant a credential. Not a
comment per issue: that is a notification per routing decision. Not a queue:
nothing is assigned, because a Claude agent takes a *package* and asks questions
mid-work.

**The body says when it was read, and is a reading rather than a live view**
(`#409`, 2026-08-16). Every entry on it was open at the minute of the run and
any of them can be closed at the next one; there is no cheaper way to know than
to ask, and asking is a run. So the stamp is what lets a reader judge the age of
the list — the wording before it said the body was always right, which is how a
package built from a list written that morning turned out to be a third
finished. The four-hourly cadence above is the other half and came from the same
issue: it ran daily at 07:20 until then.

A package — issues linked by GitHub's dependency relation (`#261`) — is one
entry with its parts in order. The clause saying why an issue is not
`agent:opencode` is derived from its labels, which is all there is to read until
triage records a reason. Logic in `.github/scripts/waiting-list.sh`, tested
against a stubbed `gh` in `.github/tests/waiting-list.test.sh`, which the
workflow runs before it publishes anything.

## What triages

`.github/workflows/board-triage.yml`, at **:20 and :50** (`kolonie-docs#262`,
2026-08-10). Measured that day: 49 issues created in 24 hours, 46 closed, 21 of
those by the opencode worker — and **fifteen sitting unread in Inbox while every
issue the worker was given had been queued by hand.** The worker exited idle on two
runs in three. The bottleneck was not execution; nothing decided.

One pass over **Inbox and Ready** and nothing else, in two halves that cost
differently (`kolonie-docs#289`, 2026-08-11).

**Triage decides once.** The model is asked only about issues carrying no route.
For those: provenance, route, readiness, dependencies, priority — then what it
routed moves to Ready and the rest stays in Inbox with a reason, one comment when
it changed something and silence otherwise. Measured on the live board that day,
**fifteen of the twenty-two issues in the two columns were already routed**, so
forty-eight passes a day were paying the strongest model on the gateway to
re-decide decisions that existed, and a route set by hand survived at most half an
hour. A decided issue is not briefed, not chunked and not asked about.

**What a decided issue still needs is the Ready ↔ Inbox move**, and that turns on
two facts rather than a judgement: an open blocker or `blocked:human` sends it to
Inbox, every recorded dependency closed brings it to Ready, and an issue with no
recorded dependencies is left where it is. `board-triage.sh sweep` makes that move
over every routed candidate, at no token cost, **before** the model step — so a
gateway that is down costs the pass its judgement and not its bookkeeping.

| | |
|---|---|
| **The model** | `gpt-5.6-sol`, the strongest on the gateway, and the reason is the dependency step: noticing that a new issue reads something one of forty-odd open ones creates is a judgement over the whole board at once. It is also what decides whether a citizen's words reach code. A setting (`TRIAGE_LLM_MODEL`), so the strongest model in six months is one variable away |
| **What the model is given** | The board, the routing table quoted out of `AGENTS.md` §5, and `operations/worker-prohibitions.md`. **No copy of either rule lives in the prompt** — a third copy is the one that goes stale |
| **Chunked, six at a time** | Measured 2026-08-10: 38 candidates and 47 open issues is a 154 KB brief and the gateway answers **524**, a proxy timeout. Six candidates against the *same whole-board index* is 54 KB and answers in about fifty seconds. Only the candidates are chunked; the dependency judgement always sees every open issue |
| **What it may write** | Labels, GitHub dependency relations, one comment, and the Status field for **Ready and Inbox only**. `opencode-worker.sh move` refuses the other columns: In Progress and In Review belong to whoever holds them, and a triage pass that could write them could take work off an agent that has it |
| **What overrules the model** | Every rule with a cost, in `board-triage.sh` and not in the prompt: a candidate comes from Inbox or Ready or is skipped; an unrecognised or absent route becomes `agent:claude`; `agent:opencode` is refused on `blocked:human`, `opencode:forbidden` or an open blocker; a priority is never set on an issue that arrived from outside (`blocked:human` class 6); nothing is ever removed. The route ratchet — a pass tightens a route and only a person loosens it — stays as a second line and no longer fires, because since `#289` a routed issue is not a candidate at all |
| **The routing cases** | `.github/tests/board-triage-cases.json`: eight issues the pass has to get right, each with the route it should produce and the one sentence that decides it. CI holds the half that needs no provider — which cases are briefed, that the brief quotes the routing table and the prohibitions, that each expected route is applied unchanged, that `opencode:forbidden` overrules any answer. `board-triage.sh cases-brief` builds the same brief from the file so the judgement half can be run by hand against a live model, touching no board |
| **`from:non-member`** | From organisation membership, which the opener cannot supply and the model is not asked about (`kolonie-platform#686`). Membership rather than `authorAssociation`, which reads `NONE` for a colleague who has never touched that repository |
| **When it cannot ask** | It writes no decisions and exits 0, per chunk. Forty-eight passes a day means a provider hiccup that turned red would produce red runs nobody believes — `watch-judge.py`'s policy, one workflow along. A pass that decided nothing says so in the log |
| **Credentials** | The `kolonie-opencode` app token to read the board and move cards, and `WORKER_REPO_TOKEN` for the labels and comments it writes across the five board repositories. `github.token` can do neither |
| **What it proposes** | A prohibition the list does not carry (`#264`). It reads the refusals on every open `opencode:failed` issue, and a reason that has appeared on **two or more** with no match in `operations/worker-prohibitions.md` becomes one comment on a collecting issue, labelled `agent:human`: the reason, the issues, the wording. **It proposes and stops** — accepting one is a person editing the document, because a worker that could widen its own constraints has none. Each proposal carries a key, so a rejected one is not proposed again |
| **Logic** | `.github/scripts/board-triage.sh` and `.github/scripts/board-triage-decide.py`, tested against a stubbed `gh` in `.github/tests/board-triage.test.sh` — which asserts what happens when the model answers *wrongly*, since its judgement cannot be tested and every place the script overrules it can |

**To switch it off: disable the workflow in the Actions tab, or delete the file.**
The board keeps every label it has; nothing else reads the schedule. What returns
is the state `#262` measured: a queue that only a conversation fills.

**Everything above assumes an issue reaches Inbox with a Status on it, and that is
Projects' own doing rather than this repository's.** Four built-in workflows write
the Status field, and **deleting a Status option disables all of them** — the
mechanism, the four names, the date it happened and how it is repaired are in
`AGENTS.md` [§4](../agents/board.md#deleting-a-status-option-disables-every-workflow-that-writes-status),
which is where the field and its option ids live. It is worth knowing here because
the symptom looks like a triage failure: issues that sit in no column are not
issues the pass declined to route, they are issues it never saw.

## The opencode worker

**An experiment with a stated end** (`kolonie-docs#142`), not a permanent part of
the architecture and not the citizen contribution skill. It exists to answer one
question that every larger version of the contributor plan is a bet on: *can an
agent nobody is talking to take a specified issue to a pull request worth
reviewing?*

Recorded here so it does not have to be reconstructed from a workflow file.

| | |
|---|---|
| **What runs** | `.github/workflows/opencode-worker.yml` in `kolonie-docs`, every ten minutes, and on `workflow_dispatch`. Set by the maintainer on 2026-08-10. A twenty-minute cadence the day before produced six runs in four hours and then an hour of none, so more triggers is not known to mean more runs — measure started against scheduled over a full day before believing either number. **Never on an issue or label event.** |
| **Queue** | Issues labelled `agent:opencode` sitting in **Ready**, without `blocked:human`, **anywhere in the organisation** (`#231`, 2026-08-08 — it was `kolonie-docs` only until then, and the queue there emptied). `p1` before `p2`, then oldest by creation date; an issue with neither priority sorts last and the log names it. Then, in that order, the first candidate **nothing open blocks** (`#261`, 2026-08-10) — GitHub's issue-dependency relation, read one candidate at a time, so the ordinary hour costs one call. A dependency the queue cannot read is not a dependency: `kolonie-platform#660` said in prose twice that it waited for `#659`, and was taken and failed |
| **Which repository** | Whichever the picked issue lives in. It is checked out at `target/` beside `kolonie-docs`, worked there, and the pull request opens there. One search call for all five, served by GitHub's **search** allowance — a third pool, separate from `core` and `graphql` |
| **The target's check** | Read from the target repository's own `AGENTS.md`: the first fenced block under a heading ending *The check command*. **Never a map held in the workflow** — that would be a second record of a fact each repository already states. A repository naming none stops the run instead of having one guessed |
| **What that check needs first** | Same file, sibling heading — *The check prerequisite* (`#247`, 2026-08-09). The worker runs it after the model and before the re-run, and takes the `export NAME=value` lines it prints, filtered to that one shape and quoted for exactly one `eval`. **A repository naming none is the ordinary case**: only `kolonie-platform` declares one, `npm run test:db:up`, because its suite fails hard on an unset `DATABASE_URL` by design. Before this the worker re-ran that check with no database at all and failed work that had passed |
| **Code write across repositories** | `WORKER_REPO_TOKEN` — contents and pull-requests write on the repositories the worker may work. It did not exist when this row was written on 2026-08-08 and does now. `github.token` is scoped to the repository hosting the workflow and the board token is Projects-only, so without it a `kolonie-docs` issue would run as before and anything else would stop with the reason and return to Ready. **It is still a personal token**, deliberately: moving it to the app would change the author of every worker commit to a bot and change how branch protection reads those pull requests, and auto-merge has to keep working because nobody reads them |
| **How much** | Exactly one issue per run, and **runs may overlap** since `#266` (2026-08-10). Neither of the two global locks survives: the `concurrency` group went on 2026-08-07 (it held the second run pending, so the step meant to detect it never counted more than one), and the *am I already running* step went with `#266`, because a global lock made `pick`'s per-repository filter inert. What bounds a second run now is `pick` skipping any repository with work in flight, and a claim that is actually a lock: it reads the column before writing it, reads it back after, and breaks a same-instant tie on the claim comment, which is ordered where Projects v2 — having no compare-and-swap — is not. **A run that loses the tie changes nothing and exits 0**; taking the failure path would demote an issue for having been wanted twice |
| **The agent** | `opencode run`, pinned to **v1.18.13** from `anomalyco/opencode` releases — **not** the official action, and not `latest`. Why both, below |
| **The model** | **A setting, not a constant.** `OPENCODE_LLM_MODEL`, repository secret. Change the secret and the next scheduled run uses it; no model is named in `opencode.json` or in the workflow, and there is no committed default to fall back to |
| **Provider** | The maintainer's own OpenAI-compatible gateway, which serves its whole catalogue on one key — so a model change is a value rather than a migration |
| **Provider key and endpoint** | `OPENCODE_LLM_API_KEY` and `OPENCODE_LLM_BASE_URL`, repository secrets, both reaching opencode by `{env:…}` substitution in the committed `opencode.json`. **The URL is a secret and not merely the key**: it names a private endpoint, and a committed hostname is a target that stays reachable in git history after the line is deleted. `.github/scripts/no-gateway-leak.sh` greps the tree for both values on every run of `CI` and prints neither |
| **Merging** | **Auto-merge, squash** (`#232`, 2026-08-08) — it enables it and the run ends; the branch lands when the checks report. It never merges past a red check: no `--admin`, no force, no retry that disables a job. **Only where `main` requires a status check** — the workflow asks the target repository rather than holding a list, because auto-merge with nothing required merges instantly, which is a push wearing a pull request's clothes. **Measured 2026-08-11: thirteen of the fourteen repositories require one — all of them but `.github`, which has no check to require and receives no pull requests.** That was four on 2026-08-08; `kolonie-email` gained its protection on 2026-08-10 (`kolonie-email#5`) and the six skill repositories plus `kolonie-dns` on 2026-08-11 (`#278`). **The last seven are the interesting ones**: they receive generated pull requests — one edit to `onboarding/skill/body.md` opens six at once — and until then the sweep below was a no-op in exactly the repositories where nobody reads what lands |
| **Where the worker's own files live** | `/tmp/opencode`, granted by name in `opencode.json` — `external_directory: {"*": "deny", "/tmp/opencode/*": "allow"}` (`#246`, 2026-08-09). **That is opencode's own scratch directory**: read out of the pinned v1.18.13 binary, `Path.tmp` is `path.join(os.tmpdir(), "opencode")` and it is created at startup. The 2026-08-07 refusal was one directory too high — `Tool.assertExternalDirectory` asks for `dirname(path) + "/*"`, so reading `/tmp/issue.json` requested `/tmp/*`, which is everything a runner keeps there. `/tmp` stays denied. This removes `#244`'s workaround: the files are no longer in the target's worktree, so nothing has to be swept out before its check reads the tree |
| **What the model's process can reach** | The gateway, and **not `GH_TOKEN`** (`#246`). It runs under `env -u GH_TOKEN`; the token is present in the step for the push, the pull request and the auto-merge, and absent while the model runs. **A directory restriction never stopped `env`** — measured 2026-08-09, the model's environment held the gateway key, the gateway URL and a `repo` token for all five repositories, none of which the sandbox was ever guarding. The injection boundary from `#235` is unchanged: the assigned issue is the only instruction |
| **Nothing leaves carrying a secret** | Before the **push** — not merely before the pull request, because the push is what publishes — the diff, the branch's commit messages and the pull request body are checked for the literal value of every secret this run holds, and the run refuses rather than warns (`#246`). By value and deliberately not by shape: a refused pull request costs an hour of work, and a repository that documents what a token looks like is not leaking one. It prints no value, ever |
| **When it fails** | The reason goes where the failure is announced (`#245`, 2026-08-09). A **job summary** on the run page — failed step, which issue, and the last twenty lines — and the **failure comment carries the same**, plus whether *the work* failed (the target's check said no; requeueing is right) or *the worker* failed (a token, a checkout, its own files; the next hour fails identically). The third failure on one issue says so. The excerpt is bounded in lines, line length and total characters, and filtered twice — by the value of every secret this run holds, and by shape for tokens it has never seen. **GitHub masks a secret in a log and not in a comment**, which is why that is more than a `tail` |
| **When the check goes red** | The comment carries **the model's account of why**, above the log excerpt (`#254`, 2026-08-10). One call on that ending only — a commit exists and the target's check failed — bounded to 120 seconds, reading the failing lines plus the tail rather than a log that can be megabytes. **A refusal is not summarised**: the model's own reason is the artefact there and a paraphrase of it is a loss. The account is **attributed and never presented as the Colony's finding**, because a model diagnosing a failure it caused has an interest in the answer. It runs from an empty directory with bash and every external directory denied, so the process holding the gateway key cannot be asked to print its environment, and what it wrote goes through the same redaction the excerpt does. A call that cannot be made is a missing paragraph and never a failed reporting step |
| **Board read and write** | The **`kolonie-opencode` GitHub App** (`#270`, 2026-08-10), owned by the organisation, holding Organization → Projects: read and write, and Metadata: read. Nothing else — no contents, no issues, no webhook — so the narrowness the old `BOARD_WRITE_TOKEN` had by careful scoping is now a property of what the app *is*. Each job mints its own token from `BOARD_APP_ID` and `BOARD_APP_PRIVATE_KEY`, and it **expires in an hour** rather than on a date somebody has to remember. Four workflows use it: `opencode-worker`, `opencode-red`, `board-self-check`, `waiting-for-an-agent`. **It has its own hourly GraphQL budget**, which is the reason it exists: the tokens it replaced were the maintainer's, and on 2026-08-10 the worker exhausted that person's 5,000 points and runs died at `pick`. Measured at install, same board and same minute: the app at 4,999/5,000, the account at 4,660/5,000 |
| **Issue comments** | The built-in `GITHUB_TOKEN`, deliberately, so the stored credential's only power stays moving a board column |
| **A migration merges itself too** | There is no diff the worker opens that waits for a person (`#276`, 2026-08-11, withdrawing `#263`). `#263` held one class back — anything touching `packages/db/drizzle/` — on an asymmetry that is real: `deploy.sh` applies a migration before the new image is healthy, so a wrong one has run against production by the time anybody reads it. What the day of data said is that the gate bought the wrong thing. Three pull requests waited, fourteen merged themselves, and all three of the waiters wrote migration `0204` — because a queue longer than one manufactures the collision, and then the first merge makes the other two `dirty` for the stale sweep to close and re-run. The gate converted a rare bad migration into a routine conflict. The protection that stays is the required status check: what merges is what went green, and `#275`'s sweep arms nothing in a repository that has none |
| **Queue logic** | `.github/scripts/opencode-worker.sh`, tested against a stubbed `gh` in `.github/tests/opencode-worker.test.sh`, which the workflow runs before anything else |
| **An In Progress item nobody is behind** | Reported, never moved (`#266`, 2026-08-10). Because `pick` skips a repository with anything In Progress, a forgotten claim holds that whole repository out of the queue — `kolonie-platform#602` did for an afternoon. An item whose issue nothing has touched for four hours gets one comment saying so; deciding it is abandoned stays a person's judgement, and the comment itself resets the clock |
| **The `main` it opens against** | The one that exists, not the one it started from (`#257`, 2026-08-10). Immediately before the pull request — after the target's check, because the window is the work itself — the run fetches `main` and rebases onto it. A conflict **aborts**: nothing is pushed, the run ends as *the work failed*, and the comment names the conflicting paths and what landed under the branch. **No run resolves a conflict**, because the other change is in a commit the model has not read and was told not to widen its scope to |
| **A pull request that cannot merge** | Swept at the start of the **next** run (`#256`, 2026-08-10), because the run that opened it exits minutes before anything can merge under it. A worker pull request whose `mergeable_state` is `dirty` is closed with its branch, its issue is commented, put back to **Ready**, loses `agent:opencode` and gains `opencode:failed`. Only `dirty` — `blocked`, `behind` and `unstable` are healthy states, and `unknown` means GitHub has not computed it yet and is left for the next run. The sweep finds its own pull requests by the sentence their body opens with rather than by their author, so a rotated token does not hide the history. **Nothing in it can fail the run**: a sweep that cannot reach the API warns and the queue work continues |
| **A pull request that merged** | Reported on its issue by the same sweep (`#258`, 2026-08-10), because the run that opened it exits before GitHub merges it. One comment per completed issue: the title the change landed under, the files and the line counts, the check that passed and the required context auto-merge waited on, and the merged pull request. **Derived from the pull request and never paraphrased** — no model is reached from this path, because a model summarising its own work has an interest in the answer. Exactly once, enforced by a marker on the issue rather than by a stored list; only where the pull request merged *and* the issue is closed. Bounded to what merged in the last day, so the sweep's cost does not grow with the experiment |
| **A pull request nobody armed** | Armed by a third sweep in the same place (`#275`, 2026-08-11). The worker arms auto-merge on the pull requests **it** opens and nothing armed the others — on 2026-08-10 `claude002` opened two that stood green, mergeable and untouched until a person found them. It arms every open pull request in the organisation that is **not a fork**, **not a draft**, not already armed, and whose base repository requires a status check on `main`; `--auto --squash`, never `--admin`, so a red check still stops it. The fork rule is the one everything hangs on: the repositories are public, anybody may open a pull request, and a sweep that armed those would be a supply chain with a schedule. It filters on no author and no branch prefix, because **arming is not merging**. Two filters were added on 2026-08-13 (`#326`), because on a pull request that is already green arming *is* merging: one labelled `blocked:human` is left alone, and **a disarm is permanent** — an `auto_merge_disabled` event anywhere in the timeline takes it out of the sweep for good. `kolonie-platform#844` was disarmed by hand at 06:33 and armed again by the 06:41 run, which merged and deployed it eight minutes after a person had said no. This does not reverse `#276`: the worker still holds nothing back by what the diff touches, and what is new is only that a person can say *not this one* and be heard next run. **A seventh followed hours later (`#331`, 2026-08-13): it arms nothing whose base is not the repository's default branch**, read per repository off the listing it already makes. Requiring a check protects the branch it is configured on and no other, so on a pull request into a feature branch there is nothing to wait for and arming is merging outright — `kolonie-platform#847` was opened at 07:04 against the branch of the held `#846` and the 07:10 run merged it at 07:10:35, unbuilt, announcing a check that `ci.yml`'s `pull_request: branches: [main]` trigger meant would never run. Nothing reached `main`; what it cost was the hold, which stopped the branch landing but not the branch changing |
| **A pull request that goes red afterwards** | `.github/workflows/opencode-red.yml` (`#240`, 2026-08-09), on `check_suite: completed`. The worker has exited by the time CI reports, so this is a separate trigger rather than a step: it **closes the pull request, keeps the branch, and returns the issue to Ready**. Only `opencode/issue-<n>` branches, only a conclusive `failure` or `timed_out`, idempotent, and it never touches `agent:opencode`. Logic in `.github/scripts/opencode-red.sh`, tested in `.github/tests/opencode-red.test.sh`. **It sees `kolonie-docs` pull requests only** — a `check_suite` event fires in the repository it happened in, so the other four wait on the same credential `#231` and `#232` do |
| **What it reads** | The assigned issue, **plus background** — `.github/scripts/opencode-context.sh` gathers the issues that issue references, depth one, at most five, organisation only, each with its board column and state (`#235`). `kolonie-docs` is checked out beside the target so the documents those issues quote are readable |
| **The boundary on that background** | The gathered text is untrusted input reaching a model with write access. It arrives fenced, labelled per item by provenance, under a header saying the assigned issue is the only instruction; `from:citizen` items are **included and marked** rather than excluded; no URL found in any issue body is ever fetched, and a URL fragment cannot become a reference. `.github/tests/opencode-context.test.sh` feeds it an issue whose reference says *ignore your previous instructions* |

**To switch it off: disable the workflow in the Actions tab, or delete the file.**
Nothing else depends on it. The label stays where it is, the board stays where it
is, and no other workflow reads either.

**What it may never do.** Push to `main`, remove the `agent:opencode` label, or
edit its own workflow.

**Merging was on that list until `#232`, and the replacement is narrower than
"it may not merge" was.** It may not merge *unchecked* work: it enables
auto-merge and GitHub performs the merge when the target's **required** status
check reports green, with no `--admin`, no force and no retry that disables a
job. A repository with no required check gets no auto-merge at all and the pull
request waits for a person, because auto-merge there would land the moment it was
enabled — a direct push wearing a pull request's clothes. Measured 2026-08-10:
sixteen worker pull requests, sixteen auto-merges, no review event on any of
them, and on the fastest the required check went green two seconds before the
merge. **The measurement the experiment exists to take is unaffected** — it is
whether an unwatched agent produces work worth landing, and a check that ran
before the code landed is a better answer to that than a human clicking merge
without reading.

**Two deviations from `#142` as written**, both measured 2026-08-05 and both
recorded because a reader comparing the issue to the file would otherwise think
something was skipped:

- **`opencode run`, not the official action.** `anomalyco/opencode/github` is
  *mention-driven* — it reads a comment event, looks for `/opencode`, and answers
  in context. It has no shape for *a schedule picked this issue*. `#142` names
  the alternative itself. The reason behind its pin-to-a-SHA requirement is kept:
  a pinned version, because something in a third-party namespace runs with write
  access here and `latest` means that path can change without a commit in it.
- **`sst/opencode` is now `anomalyco/opencode`.** The repository moved after
  `#142` was written.

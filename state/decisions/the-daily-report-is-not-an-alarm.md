# The daily report is not an alarm

[← the register](../decisions.md)

**The Watch Agent's daily narrative and its alarms are two jobs, and they wanted
opposite things.** The narrative — how yesterday compared with the week — is now
the workflow run's own summary and files nothing. The alarm — a service that has
stopped logging — files one issue per service, with the service's name in the
title. Nothing else the Watch Agent notices files at all.

## What went wrong, and it is a shape rather than a bug

`kolonie-docs#133` built a good thing and gave it one output. Its dedupe was an
exact match against **one fixed title**, so there was exactly one Watch Agent
issue, ever, and every day's findings were comments on it: unrelated defects,
weeks apart, on a thread that never closes. Its own footer stated the
consequence, and was right about half of it:

> It never closes one: whether this is dealt with is a person's call, not a
> workflow's.

That is correct about *closing* and wrong about *filing*. **An issue appended to
and never closed is the chronicle failure `AGENTS.md` §2 already names**, one
level up:

> A file that is appended to and never rewritten is a chronicle. Anything read as
> a reference is rewritten in place, or it is split.

Nobody could pick anything up, because a chronicle is not a piece of work.

| | Wants |
|---|---|
| *Here is yesterday's shape* | daily, narrative, no action implied, reused deliberately, never urgent |
| *Something is broken now* | minutes not hours, one issue per defect, closeable, assignable |

The design served the first and filed it in the shape of the second.

## What each half is now

**The narrative is the run.** `watch-agent.sh summary` writes the counts, the
seven-day comparison and the model's reading into `$GITHUB_STEP_SUMMARY`. It
opens nothing and comments on nothing. A daily report that never resolves is not
work; the place for a description of yesterday is the run that produced it.

**The model's judgement is kept, kept daily, kept cheap — and files nothing.**
*Is today normal* is a question no threshold answers, and `#133` was right that
no number belongs in that file. What changed is where the answer goes.

**The alarm is a silent service, and it is the one this workflow keeps.** A dead
runner throws no errors, so anything reading errors — including the detector
below — is structurally blind to it. That is exactly why `#133` made the check
deterministic and separate. It now files **one issue per service**, titled with
the service, and a service still silent tomorrow gets a comment on **its own**
issue rather than a second one.

**Silence is still the healthy state.** No daily all-clear, no issue on a good
day, no comment on one.

## Why this waited for `kolonie-platform#407`

**Removing the alarm half first would have left the Colony with less than it
had.** Before `#407`, the model's *today is abnormal* verdict was the only path
from an error appearing in the logs to a person seeing it. Turning that into a
run summary without a replacement would have meant an error spike reaching
nobody.

`kolonie-platform#407` is the replacement and it is strictly better at the job:
it ticks every half hour rather than once a day, dedupes on a **signature**
rather than a title, files into the repository that owns the service, and
produces one issue per defect. Measured against `kolonie-platform#404` — a
`ZodError` that broke a citizen-facing tool three minutes after a deploy — the
Watch Agent would have surfaced it seventeen hours later.

So the sequence was a precondition rather than a preference, and it was checked
against `watch-agent.sh` rather than taken on trust before the work began.

## What this does not change

**`#133`'s reasoning is not deleted.** Every argument it made survives: no
threshold anywhere in the agent, numbers rather than lines sent to the model,
evidence before judgement, a store that cannot be read reported as a
configuration gap and never as a finding, a missing model verdict meaning *no
opinion* rather than *nothing is wrong*, and the deterministic half running
first and needing no key. Each of those still has a test.

**Nothing is closed by a workflow** — including a silent service's issue when
that service starts logging again. A service that came back is a thing somebody
should know happened, and whether it is finished with is a person's call.

**The Watch Agent still runs in Actions and not on the host.** A watcher that
dies with the thing it watches is not a watcher, and that argument is untouched.

## What would reverse this

- **The daily narrative turning out to be read by nobody in a run summary.** If
  it is genuinely never opened, the honest answer is to stop producing it rather
  than to file it as an issue again — this record exists so that the second
  option is recognised as the thing already tried.
- **`kolonie-platform#407` being withdrawn or proving unusable.** The alarm half
  moved on the strength of that detector existing. If it goes, this record is the
  argument for putting an error path back into the Watch Agent, and it should be
  put back as *issues per signature* rather than as comments on one.
- **A silent service turning out to be catchable by the error detector**, which
  would make this workflow's one remaining alarm redundant. It is not today, for
  the reason it was built: silence throws nothing.

A reversal stays in the register as a reversal. The question was asked once, and
the next reader should see the answer and its date rather than ask it again from
scratch.

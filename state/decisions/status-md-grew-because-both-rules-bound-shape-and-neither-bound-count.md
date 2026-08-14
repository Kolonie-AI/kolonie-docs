# STATUS.md grew because both rules bound the shape of a sentence and neither bound how many there are

[← the register](../decisions.md)

`kolonie-docs#366` refused to restructure `state/STATUS.md` before establishing
why it grew, on the grounds that *a split that leaves the accumulation running
buys three weeks*. This is that answer, and it is not the one the issue expected.

## The measurement

| | |
|---|---|
| 2026-07-29 | 194 lines |
| 2026-08-03 | 679 lines |
| 2026-08-08 | 893 lines |
| 2026-08-15 | 919 lines |
| 114 commits since 2026-07-25 | **+2.055 / −1.136** |

## The expected answer, and why it is wrong

`AGENTS.md` §2 gives a diagnostic for a document that has stopped being a
reference:

> A reference under control shows deletions in the same order of magnitude as
> additions, because it is being rewritten. Additions with no deletions, in a
> file people read to find something, is the shape of this defect before anybody
> notices the size.

**`STATUS.md` passes that test.** Deletions are 55 % of additions across 114
commits — the file *is* being rewritten in place, exactly as the present-tense
rule requires, and it grew 4,7× anyway. So the accumulation is not stale
sentences piling up behind live ones, and the fix the issue guessed at — move the
historical material to `state/decisions/` — would find little to move.

**That makes the §2 diagnostic a false negative here, and it is worth saying so
where §2 lives.** It catches a chronicle pretending to be a reference. It does
not catch a reference that is honestly maintained and simply covers more every
week.

## What is actually happening

Both rules that govern this file are about **one sentence at a time**:

- *the present-tense rule* — when something stops being true, replace the
  sentence rather than annotating it. This decides **how** a line is written.
- *the test for what belongs* — would this still be true if every issue moved to
  a different column tomorrow? This decides **whether** a line belongs at all.

A new subsystem produces sentences that pass both: they are true, present tense,
and not the board's answer written twice. Every one of them is individually
correct and the file has no rule that ever removes one. **A document whose
membership test is *is it true* grows exactly as fast as the system it
describes.**

That is the whole finding. It is not a discipline failure, which is why more
discipline was never going to fix it.

## The rule that changes it

> **`STATUS.md` is what a reader needs to make a decision this week, not a
> catalogue of what is true.** A sentence stays while somebody choosing what to
> do next would be worse off without it. What is merely true belongs to the
> document that owns that subsystem — `ARCHITECTURE.md` and its modules,
> `governance/`, a decision record — and it is one link away from here.

Membership by *usefulness to a decision* is bounded, because the number of
decisions in front of the Colony in a week is bounded. Membership by *truth* is
not.

The rule is in [`agents/docs-repo.md`](../../agents/docs-repo.md) beside the two
it joins, and the per-module cap in `check.sh` (`kolonie-docs#365`) is what makes
it fail rather than merely be written down. The cap is the part that matters:
this file has had two rules against growing since 2026-07-29 and grew every
single week that both of them were in force.

## Why the file is not being split

Routing it would put a subsystem's paragraph in front of the agents working on
that subsystem, and it would leave the accumulation running one level down — the
issue's own warning. `#362` already removed the reason the size was urgent:
`STATUS.md` is a module, loaded when something asks for it, and it is not in what
a session starts with. What is left is a file that is too long for the person who
reads it end to end, and the answer to that is a retirement rule, not a knife.

**If it is over the cap again in a month, the rule above is what failed** — and
the next argument should be against this paragraph rather than starting over.

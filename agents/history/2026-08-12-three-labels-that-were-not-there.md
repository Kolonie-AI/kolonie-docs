---
module: history-labels
summary: p3, question/documentation, and needs-triage in one repository — why each was decided that way.
applies-to:
---

# 2026-08-03 to 2026-08-14 — three arguments about the label vocabulary

The vocabulary is in [`agents/labels.md`](../labels.md). These are the arguments
behind three of its lines, each of which will otherwise be reopened from scratch.

## Why there is no p3

**Two, and there is nothing to add a third for.** A `p3` existed on four issues
across two repositories until 2026-08-03, defined nowhere — this table has always
said two. It was deleted rather than documented, because what it was reaching for
is already said better elsewhere: the one open issue carrying it,
`kolonie-platform#222`, was not *lower priority* than `p2`, it was **parked on
legal advice**, which the Blocked column and `blocked:human` state precisely and a
priority label states vaguely. A third priority tempts exactly that substitution.
**If a third is ever argued for, it is argued against this paragraph.**

## Why `question` and `documentation` were removed from the table rather than created

**Two labels this table used to offer and no longer does.** `question` and
`documentation` exist in `kolonie-openclaw` and in none of the other four; across
all five repositories `question` is on no issue at all and `documentation` is on
one (measured 2026-08-14, `gh issue list --repo … --state all --json labels`).
**Corrected the document rather than creating the labels**, because `question` as
it was defined — _an open decision_ — is what `decision` already means, and three
labels for two states is the condition the `p3` paragraph above argues against.
`gh issue create --label documentation` against `kolonie-docs` fails, which is how
this was found. The two survivors in `kolonie-openclaw` are left where they are:
one of them is carrying an issue, and deleting a label to make a sentence true is
the more expensive of the two fixes.

## What a label missing from one repository cost

**`needs-triage` existed in `kolonie-platform` alone until 2026-08-12**, and the
gap was not harmless. `inbound-triage.yml` applies it to every issue from outside
and is called by four repositories; `gh issue edit` applies its labels in one
call, so in the other three the whole triage failed and the issue got *no*
`area:` and *no* comment either. It fired on `#313` and reported itself through
`#285`. The label is now in all five, and the workflow creates any of its own
labels that a repository is missing — because the hand fix leaves the next
repository to call it broken in exactly the same way, and the failure is silent
from where an outside contributor is standing.

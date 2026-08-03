# Why a batch of issues is claimed up front

[← the register](../decisions.md)

**In Progress** means *someone is working on it*, and an agent that claims three
issues to work in one session is telling that truth about one of them and a
prediction about two. The alternative — claim each as you reach it — keeps the
column literally accurate and leaves the second and third looking free for however
long the first one takes. Both options are wrong in one direction; the question is
which direction costs more.

**Claiming the batch, and naming it as a batch, is the answer**, because of what
the column is *for*. Every reader who acts on **In Progress** reads it as "hands
off, somebody owns this". Whether that owner's hands are on this issue or on its
neighbour right now changes nothing for them. What would change something is
finding the issue unclaimed, starting it, and colliding — which is the failure this
is defending against and which the precise-column option leaves wide open for two
of the three.

The naming is what keeps it honest. *"One of three taken this session; order: A,
B, C"* is a claim somebody can hand back, take over, or argue with. A queue nobody
declared is indistinguishable from three stalled issues.

**A fourth column — `Claimed`, between Ready and In Progress — models this
exactly, and is rejected on size.** It is a column, a set of option ids, an extra
transition in every agent's loop, and a second thing to get wrong, bought to
remove an imprecision that costs a reader nothing. `operations/orchestration.md`
made the same call about a locking protocol and was right: a protocol nobody has
needed is a protocol nobody has tested.

**What made this urgent rather than tidy.** Two agents worked `kolonie-infra#31`
from opposite ends within the same hour on 2026-07-31, neither knowing, because
the issue sat in Inbox and nothing was claimed. `operations/orchestration.md` had
said since it was written that a second orchestrator was hypothetical — directly
above the protocol for handling one, which taught every reader to skip it. It is
not hypothetical and has not been since at least 2026-07-29, when `kolonie-infra#31`
itself recorded another agent pushing to `kolonie-platform` mid-incident.

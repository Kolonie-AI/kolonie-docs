# Why the Reviewer Agent is parked

[← the register](../decisions.md)

`operations/review-guidelines.md` describes review by a human maintainer, and that
is what happens. An automated reviewer (`kolonie-docs#42`) was specified and is
**not being built next**, and the reason is a claim about what the Colony does not
yet know.

**The next thing worth learning is which Academy tasks actually work.** That comes
from running a whole group of agents through the graph and reading the corpus they
leave — the struggles, the tips, the walls nobody got past. A reviewer that judges
pull requests answers a different question, and it answers it for a traffic volume
the Colony does not have: the citizen pull requests to date are countable on one
hand, and a human can read every one of them.

**What is deliberately accepted.** The human stays in the loop for pull requests,
so `#37`'s "no human in the loop" holds for the Academy and not for contributions.
That is a narrower claim than the MVP made and it is the true one. The open
question inside #42 — GitHub Action or a job on the VPS — is left undecided rather
than decided in advance of a build, because the argument for the VPS rests on fork
PRs and that balance may look different when there is enough traffic to justify
either.

**The trigger to revisit:** citizen pull requests arriving faster than the operator
reads them, or a group run producing contributions rather than only submissions.

One consequence reaches `kolonie-platform#88`: the `reviewer` role was the next
one worth defining *because* a Reviewer Agent was coming. With #42 parked, it is
not, and `builder` is the only role with a live reason to exist.

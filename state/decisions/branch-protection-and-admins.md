# Why branch protection does not bind administrators

[← the register](../decisions.md)

Decided 2026-08-01, on `kolonie-docs#96`. `enforce_admins` stays `false` in every
repository that has branch protection, and the documents stop calling the result
*enforced* without qualification.

**The argument is that the alternative blocks the only path anybody ships
through.** A required status check cannot be satisfied by a direct push in
principle: CI runs on the commit, so at the moment the push is evaluated nothing
has reported and the branch is "expected" to have a check. Routine work here goes
straight to `main`. Turning `enforce_admins` on would therefore not tighten a
loose rule — it would stop the maintainer working, and the first thing that
follows is the rule being turned off again, which is worse than never having
claimed it.

**What is kept instead.** The bypass is logged, and every push emits the
violation it bypassed. One maintainer, an audit trail, and a documented
expectation is a defensible posture for a project this size — *"Operating a system
is not the same as having one"* (`ROADMAP.md`) applies to process as much as to
canaries.

**What is given up, stated rather than glossed.** Nothing mechanically stops an
administrator merging a red build, and no reviewer verdict can stop it either
(no repository requires a review). The Reviewer Agent's own rule — it may not
approve a change to the ledger, the verifiers, governance or erasure — is
enforced inside the action, and there is no branch-level counterpart. That is
deliberate: an approval that could merge is a process gating itself.

**What would reverse this.** A second person with admin rights. The whole
argument above rests on there being one, and it stops holding the day it is two —
at that point the bypass is no longer an audit trail with a single reader, and
`enforce_admins` should go on for whichever repositories touch the ledger.

**What this decision does not cover.** Whether `kolonie-hermes`, `kolonie-claude`
and `kolonie-kilo` get branch protection at all is a separate question and is
still open on `kolonie-docs#96`.

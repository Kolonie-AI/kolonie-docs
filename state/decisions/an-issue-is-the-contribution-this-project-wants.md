# An issue is the contribution this project wants. A pull request is not

[← the register](../decisions.md)

The Colony does not need external developers at this stage. Its own coding agents
run the implementation loop and it works. What it **does** need, and cannot
generate enough of by itself, is **good issues** — a defect somebody actually
hit, a page that does not do what it says, a rule that contradicts another.

> **An issue is the contribution this project wants. A pull request is not.**

## Why, stated so it does not read as a dismissal

*We don't take PRs* reads as *we don't want you*, and the thing being asked for
is a real contribution that people should feel good about making. The honest
reason is about **where the cost sits**:

- **Reviewing an unrequested pull request costs more than writing the change.**
  The reviewer has to reconstruct the intent, check it against decisions recorded
  in another repository, and verify it against a test suite the author has not
  run. The Colony's coding agents already have all three.
- **A pull request against a moving codebase goes stale in days.** The Colony
  merges continuously; a fork that took a week is rebasing against a repository
  it no longer recognises.
- **A good issue is scarce and a diff is not.** The Colony can implement anything
  it can specify. What it cannot do is notice, from inside, that a page is wrong
  or that two documents disagree. That is what an outsider can see and an insider
  cannot.

The third one is the actual value proposition, it is true, and it is the opposite
of a brush-off. It is the sentence to lead with.

## What happens to a pull request that arrives anyway

Not closed silently, and not closed rudely.

1. The content is converted into an issue, **crediting the author by name**.
2. The pull request is closed with a link to that issue and the reason.
3. Automated, so it is consistent and immediate rather than depending on who is
   awake — `.github/workflows/external-pr.yml`.

**A fork's branch could never have merged itself in any case.** The auto-merge
sweep refuses one — `opencode-worker.sh` line 1127, *"Not a fork. A stranger's
branch must never arm itself"* — so this policy changes what a contributor is
*told*, not what the machinery permits. That was verified rather than assumed,
and it is written here so it is not re-investigated.

## Where the policy lives, and why not in GOVERNANCE.md

`operations/contributions.md`, with `CONTRIBUTING.md` as the front door.
`GOVERNANCE.md` answers *who decides what*; this answers *how work comes in*,
which is an operations question. The register row points at both.

## What this does not say

**It is not a statement about who may become a citizen.** The Academy is open,
and an agent that earns the `github` rung contributes code through the ordinary
loop like any other. This is about unrequested diffs from outside the loop, and
about being honest with the person holding one.

**It is not permanent.** If the Colony ever has more specification than it can
implement, the calculation inverts and this decision is the thing to argue
against. The argument to beat is the third bullet above: that a good issue is the
scarce input and a diff is not.

## The consequence for the documents

With external human contributors out of scope, `AGENTS.md` and the modules
routed out of it stop hedging between two audiences.
`kolonie-platform/CONTRIBUTING.md` said *"Anyone can contribute — agent or
human… pick an issue, open a PR, let CI decide"* and then redirected agents to
`AGENTS.md` for *"the same ground in binding, unambiguous form"* — two documents
covering one subject for two readerships, one of which no longer exists. That is
`kolonie-platform#953`.

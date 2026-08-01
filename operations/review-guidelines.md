# Review Guidelines

## Purpose

Every PR is reviewed for correctness, architecture compliance, and cross-repo coherence. This document defines the review standard.

## Review Checklist

### 1. Issue Fulfillment
- Does the PR solve the linked issue?
- Are all acceptance criteria met?
- Are tests present and passing?
- Is the definition of done satisfied?

### 2. Code Quality
- TypeScript strict mode? No `any` without justification?
- Error handling present? No swallowed errors?
- Secrets not in code? Environment variables used?
- Dependencies in `package.json`, not inline installed?

### 3. Architecture Compliance
- Does the code use `packages/core` types correctly?
- Does it follow the declared architecture?
- Does it respect AGENTS.md conventions?

### 4. Cross-Repo Coherence
- If `packages/core` types change: does the whole workspace still typecheck?
- If kolonie-platform API changes: does kolonie-website still work?
- If the `Verifier` interface changes: are all verifier modules and the runner updated in the same commit?

## Review Outcomes

- **Approve:** PR is correct, can be merged
- **Request Changes:** specific feedback on what is missing or wrong
- **Comment:** the call needs a human — say which part and why

## Review Rules

- TDD enforced? (Tests first, then implementation)
- Docker used for services, not native installation?
- No force-push on main
- No secrets in code
- CI must pass before review begins

**What of that is configured rather than asked for, measured 2026-08-01** with
`gh api repos/Kolonie-AI/<repo>/branches/main/protection` across all eight
repositories (`kolonie-docs#96`):

| Repository | `main` protected | Required check | Binds admins |
|---|---|---|---|
| `kolonie-platform` | yes | `format, lint, build, typecheck, test` | no |
| `kolonie-website` | yes | `check` | no |
| `kolonie-docs` | yes | none | no |
| `kolonie-infra` | yes | none | no |
| `kolonie-openclaw` | yes | none | no |
| `kolonie-hermes`, `kolonie-claude`, `kolonie-kilo` | **no** | — | — |

There are no rulesets at repository or organisation level; the above is classic
branch protection. Read the table as a dated observation, the way this repository
reads a quotation from somebody else's terms — re-run the command rather than
letting the table win an argument against the live setting.

So, precisely:

- **Force-pushes and deletions are refused** wherever protection exists — five of
  eight repositories. The three per-platform skill repositories have no branch
  protection at all, and whether they should is still open on `kolonie-docs#96`.
- **A red check blocks the merge in two repositories**, not in every repository
  that has a CI workflow. `kolonie-docs` runs six workflows and requires none of
  them; `kolonie-infra` runs five and requires none.
- **None of it binds an administrator.** `enforce_admins` is `false` everywhere,
  and **that is a decision rather than an oversight** (2026-08-01,
  `state/decisions.md`). Routine work goes straight to `main`, a required status
  check cannot be green at the moment a direct push is evaluated — CI has not run
  yet — so turning it on would block the only path anybody currently ships
  through. The bypass is logged, and the audit trail is what the rule is for here.

**Read the first two bullets as *enforced against a contributor*, and the third as
what that enforcement is worth against a maintainer: nothing, by design.** A
document that says *enforced* without that sentence is claiming a guarantee the
configuration does not make.

## Who Reviews

**The Reviewer Agent first, a human maintainer second.** In `kolonie-platform`,
a pull request receives an automated review without anyone being asked. The
maintainer then reads that review rather than producing it, which is what #37
means by "no human in the loop".

It is a GitHub Action, and the reasoning is in
[`state/decisions.md`](../state/decisions.md). What matters to a contributor is
when it speaks and what it may say:

- **It reviews only after CI passes.** The rule two sections up is not a request
  to the reviewer; it is how the reviewer is triggered. A red, cancelled or
  missing build is never reviewed and never approved.
- **It judges the diff against the linked issue's acceptance criteria**, plus
  this document. An issue with no acceptance criteria gets a weaker review, which
  is one more reason `AGENTS.md` §7 asks for them.
- **It reads. It does not run anything.** No test is executed. A criterion it
  cannot confirm from the diff is reported as *unverified* rather than as met,
  and that list is deliberately the most prominent part of the review.
- **It cannot approve a change to the ledger, the verifiers, governance or
  erasure.** Those are forced to a comment however it votes. A process that could
  reward its own results cannot gate itself.
- **It never pushes to your branch.**

A pull request still merges by a human's hand. If the review is wrong, say so on
the pull request — it is a first reader, not a gate.

**And *not a gate* is literal, which matters for the constraint above about the
ledger and the verifiers.** No repository requires a pull request review to merge
(measured 2026-08-01, `kolonie-docs#96`), so the agent's approval is not
sufficient for anything and its *request changes* blocks nothing. The rule that it
cannot approve a ledger or verifier change is enforced **inside the action**,
where it decides its own verdict — not by the branch, which would let it through
either way. That is a coherent arrangement rather than a gap: a reviewer whose
approval could merge is a process that gates itself, which is the thing the rule
exists to prevent. It is written here so nobody reads the constraint as a
branch-level guarantee.

Repositories other than `kolonie-platform` do not have it yet: it hangs off a CI
workflow, and that is where CI is.

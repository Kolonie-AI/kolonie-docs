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

The last two are enforced, not requested: `main` is protected in every repository,
force-pushes and deletions are refused, and in the repositories that have a CI
workflow a red check blocks the merge.

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

Repositories other than `kolonie-platform` do not have it yet: it hangs off a CI
workflow, and that is where CI is.

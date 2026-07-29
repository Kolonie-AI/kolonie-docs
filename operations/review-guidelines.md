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

**Today: a human maintainer, and only a human maintainer.** Every PR waits for
one. This is the honest statement of the process, and it is a bottleneck rather
than a design — a citizen who opens a PR is currently blocked on the operator
reading it.

The intended end state is an automated reviewer that runs first, against this
document, and leaves a real verdict; the maintainer then reads the review rather
than producing it. That is [kolonie-docs#42](https://github.com/Kolonie-AI/kolonie-docs/issues/42),
and it is what #37 means by "no human in the loop".

Two things will not change when it exists: a red or missing CI check is never
approved, and changes touching the ledger, the verifiers or governance always
reach a human. A process that could reward its own results cannot gate itself.

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
- **Auto-Approve:** trivial PRs (docs, lint fixes, tests)

## Review Rules

- TDD enforced? (Tests first, then implementation)
- Docker used for services, not native installation?
- No force-push on main
- No secrets in code
- CI must pass before review begins

## Who Reviews

- Reviewer Agent (automated) for initial review
- Human maintainer for final approval on significant changes
- Trivial PRs can be auto-approved by the Reviewer Agent

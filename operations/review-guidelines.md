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

**What of that is configured rather than asked for, measured 2026-08-02** with
`gh api repos/Kolonie-AI/<repo>/branches/main/protection` across all ten
repositories (`kolonie-docs#96`):

| Repository | `main` protected | Required check | Binds admins |
|---|---|---|---|
| `kolonie-platform` | yes | `format, lint, build, typecheck, test` | no |
| `kolonie-website` | yes | `check` | no |
| `kolonie-docs` | yes | `check` (since 2026-08-03) | no |
| `kolonie-infra` | yes | `check` (since 2026-08-03) | no |
| `kolonie-openclaw` | yes | `check` (since 2026-08-03) | no |
| `kolonie-antigravity`, `kolonie-claude`, `kolonie-codex`, `kolonie-hermes`, `kolonie-kilo` | **no** | — | — |

**The last three rows read `none` until 2026-08-03, and the reason was not the
protection setting.** There was no check to require. `kolonie-docs#124` measured
it: a pull request editing `ARCHITECTURE.md`, or `traefik/dynamic/routes.yml`, or
`SKILL.md` in `kolonie-openclaw`, ran **nothing at all** — the workflows those
repositories had were path-filtered to something narrower, so the checks list on
an ordinary pull request was not empty but short enough to look deliberate. Each
of the three now has a workflow named `CI` with no path filter, and its `check`
job is required. What each one runs is in the workflow's own header.

**Run it rather than reading the table**, and note the trap in doing so: on a
repository with no protection, `gh api` answers `404 Branch not protected` and
prints that JSON **to stdout**. A loop that tests whether the output is empty
therefore reads every unprotected repository as protected-with-no-checks. Check
the exit status, not the output — that mistake was made while measuring this table
on 2026-08-02 and it inverted half of it.

There are no rulesets at repository or organisation level; the above is classic
branch protection. Read the table as a dated observation, the way this repository
reads a quotation from somebody else's terms — re-run the command rather than
letting the table win an argument against the live setting.

So, precisely:

- **Force-pushes and deletions are refused** wherever protection exists — five of
  ten repositories. **The per-platform skill repositories are deliberately left
  unprotected** (2026-08-01, `kolonie-docs#96`): there were four of them when that
  was decided and there are five now, `kolonie-codex` having arrived since. The
  reasoning is unchanged by the count and was re-measured on 2026-08-02 — all five
  run no CI workflows at all, and they have received **one pull request between
  them ever**: `kolonie-hermes#1`, opened by the maintainer on 2026-07-31. None has
  yet received a contribution from outside, and protection there would guard a door
  nobody has walked through. This is a judgement about today's traffic and not a
  position on whether skill repositories deserve less care — **the first citizen
  pull request against one is the signal to revisit it**, and whoever sees that
  pull request should say so.
- **A red check blocks the merge in five repositories** — every one that has
  protection at all. That was **two** until 2026-08-03, and the sentence here
  used to explain the gap as a configuration choice: *"`kolonie-docs` runs six
  workflows and requires none of them."* That was true and it was the smaller
  half of the truth. Those six workflows were path-filtered, so on an ordinary
  pull request there was no check to require in the first place
  (`kolonie-docs#124`). **A required check is worth exactly as much as the
  workflow behind it runs**, and a table that records only the requirement
  cannot show the difference.
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
- **It never approves anything, in GitHub's sense of the word.** Every review
  arrives as a comment, and the verdict — *approve*, *request changes* or
  *comment* — is the first line of it. GitHub refuses a review posted with the
  `APPROVE` state by a workflow (`422 GitHub Actions is not permitted to approve
  pull requests`) unless an organisation-wide switch is turned on that lets every
  workflow approve every pull request. That switch was not worth turning on for a
  verdict which, per the paragraph below, carries no authority anyway.
- **It never pushes to your branch.**

**On the first pull request it ever saw, this was a silent failure and not a
design.** `kolonie-platform#214`, 2026-08-02: the reviewer read the diff, wrote
the review, decided *approve*, and got a 422 on the last call. The job failed, the
contributor received nothing, and the only trace was a red check on a workflow
nobody was watching — a reviewer that goes quiet exactly when it agrees with you.

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

# Open Contribution Model

How work actually enters the Kolonie AI repositories, as of 2026-07-29.

This document described an automated coding-agent pipeline until that date. The
pipeline never existed — no workflow, no label, no dispatch — and the section
that described it has been removed rather than annotated. `kolonie-docs#4` is
the issue that called it in; the reasoning is at the bottom under
[Why the automation was removed rather than built](#why-the-automation-was-removed-rather-than-built).

## Principle

Every repository is developable by any agent or human — the process assumes no
privileged position and no private knowledge. Any external agent (Claude Code,
Codex, Gemini, SWE-agent, human developer) can pick up an issue and submit a PR.

**The repositories are public.** `kolonie-docs`, `kolonie-platform`,
`kolonie-website` and `kolonie-openclaw` since 2026-07-28; `kolonie-infra`
followed on 2026-07-29 — decided 2026-07-27 to stay closed because it described
how to reach the Colony's own machines, reversed once its history no longer did.
Tracked as the tripwire issue `kolonie-docs#6`. "Open contribution" now describes
who can reach the process and not only how it was built, which was the point of
building it that way.

The constraint it placed on the work does not relax now that it is satisfied:
nothing here may assume access that only an org member has, and the process must
work for a stranger. That was always the real requirement — the private phase
only made it easy to forget.

## Where work is picked up

There is one place: the [project board](https://github.com/orgs/Kolonie-AI/projects/1).
An issue in the **Ready** column is specified well enough to start without asking
anyone. The column *is* the status — there are no status labels, and there is no
`ready-to-build` label. [`AGENTS.md`](../AGENTS.md) §4 and §5 are the single
definition of the columns and the label vocabulary; neither is restated here, and
neither are the queries — those are [`AGENTS.md` §6](../AGENTS.md#6-the-orchestration-loop).

## Three ways work enters a repository

All three exist today. None of them is automated.

### Path 1: An orchestrator hands an agent a specific issue

The orchestrator reads the board, picks an issue per `AGENTS.md` §6, and gives a
coding agent that issue number and nothing else. The agent reads the repository's
own `AGENTS.md` for conventions, implements, and opens a PR. The orchestrator
reviews and merges.

**This is a human or an agent invoking another agent by hand.** There is no
trigger, no queue and no workflow: somebody decides to start it every time.

### Path 2: An external contributor

Anyone — agent or human — reads the public issues, implements, and opens a PR.
CI runs on the PR. A reviewer approves, the orchestrator merges. Contributors can
suggest issues at any time; an Inbox issue of three sentences is a complete
contribution in itself (`AGENTS.md` §6 step 7).

This path assumes nothing that Path 1 does not. That is deliberate, and it is the
whole content of the Open Contribution principle.

### Path 3: The maintainer pushes to `main` directly

The maintainer, and an agent working as the maintainer, commits and pushes
straight to `main` — no branch, no PR, no review round-trip. This is the path
most changes have actually taken so far.

**Why it is written down rather than treated as an unspoken exception.** The
Colony is in its foundation phase with a single operator, and a PR reviewed by
its own author is ceremony that buys nothing. But a process document describing a
review gate that everyone quietly steps around teaches the next reader to
discount the rest of it — which is the defect `kolonie-docs#4` was opened for,
one section down. If the honest answer is "the maintainer pushes to main", the
document says so.

It is a phase, not a principle. It ends when there is more than one committer,
and Paths 1 and 2 are what it ends *into* — which is why they, and not this, are
the contract.

What it does not license: `AGENTS.md` §8 still holds. Repository creation and
visibility, DNS and Cloudflare, the live VPS, money, and the Dubai entity are
confirmed with the maintainer first, whichever path the change arrives by.

## Workflow per issue (Paths 1 and 2)

1. Issue exists and is in **Ready**
2. Contributor picks it up and moves it to **In Progress**
3. Reads the repository's `AGENTS.md` for context and conventions
4. Creates branch: `feature/<issue-slug>-<issue-number>`
5. Writes tests first
6. Implements until tests pass
7. Runs the repository's own check command locally — `npm run check` in
   `kolonie-platform`
8. Pushes the branch and opens a PR against `main`, body carrying
   `Fixes #<issue-number>`
9. CI runs on the PR
10. Red CI: the contributor fixes it and pushes again
11. Green CI: a reviewer reviews
12. On approval, the orchestrator merges
13. Merge deploys — see [deployment.md](deployment.md)

Steps 4 and 8 are what Path 3 skips, and nothing else.

## AGENTS.md (per repository)

Each repository has an `AGENTS.md` that tells every coding agent:

- What this repository does
- What conventions apply
- What the architecture looks like, and which workspace owns what
- Where dependencies lie, including other repositories
- What is forbidden — no secrets, no host names, no IP addresses
- How tests run, and which capabilities the ones with a backing service need
- What the PR check includes
- How to open a PR

`AGENTS.md` is the constitution for every coding agent. It must be good enough
that a foreign agent can contribute without a human explaining anything. The
handover test for that claim is `kolonie-docs#5`.

## CONTRIBUTING.md (per repository)

For human contributors: how to start the repository locally and what is genuinely
required to do so, how to run the tests and which capabilities the ones with a
backing service need (see [testing.md](testing.md)), how to open a PR, what
conventions apply, and how to suggest issues.

## What coding agents do not do

- Merge their own PRs
- Take architecture decisions that are not in the issue — say so in the issue
  instead (`AGENTS.md` §8 in `kolonie-platform`)
- Deploy by hand
- Approve another agent's PR as its only reviewer

Creating issues is **not** on this list, and used to be. An agent that trips over
a defect and cannot file it has nowhere to put what it learned except a chat
transcript that ends with the session — which `AGENTS.md` §6 step 7 exists to
prevent. File it.

## Why the automation was removed rather than built

The removed section described a GitHub Actions workflow triggering on a
`ready-to-build` label, in which OpenCode read `AGENTS.md`, implemented the
issue, and opened a PR. It printed the workflow YAML. None of it existed: the
workflow was never written, and the label was removed when status moved onto the
project board.

Building it now would automate a handoff that has never once been performed by
hand, which produces automation shaped around a guess. Run Path 1 manually a few
more times first.

Two things worth keeping from the attempt, for whoever does build it:

- Actions triggers on **labels** far more easily than on a board column. That is
  an argument for reintroducing exactly one label for that single purpose — not
  for duplicating status, which `AGENTS.md` §4 rejects for reasons that still
  hold.
- The dispatch needs a credential that can push and open pull requests, held by
  whatever runs the agent. That is a secret with real blast radius, and it is why
  this is a deliberate step rather than a convenience.

When it is built it gets a new issue with its own spec, not this one reopened.

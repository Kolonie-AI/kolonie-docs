# Orchestration

## Purpose

The orchestrator coordinates development across all Colony repositories: breaking roadmaps into issues, coordinating PRs, triggering reviews, merging, and checking iteration gates.

## Key Principle

Orchestration is repo-driven, not agent-bound. The procedures live in this repository. Any agent (OpenClaw, Claude Code, Codex, human) can clone this repo and take over orchestration. This eliminates the single point of failure.

## The Orchestration Loop

```
1. Read this repo, AGENTS.md
2. Read state/STATUS.md: when was last orchestration, by whom?
3. Locking check: is there an open issue with label "orchestrating"?
   - If yes and younger than 1 hour: do nothing, try later
   - If older than 1 hour or not present: take over
4. Set lock: create issue with label "orchestrating" + timestamp
5. Read ROADMAP.md
6. Check all repos via GitHub API:
   - Open issues, open PRs, CI status
7. Determine next action:
   - PR waiting on review with green CI? → Trigger review
   - PR approved? → Merge
   - No issue in progress? → Create next issue from roadmap
   - Canary bugs open? → Create fix issues (priority over new features)
8. Update state/STATUS.md: what was done, what comes next
9. Close lock issue
```

## Locking Mechanism

Prevents two agents from orchestrating simultaneously:
- Agent creates a GitHub issue with label `orchestrating`
- Issue title: "Orchestration run - <timestamp>"
- Issue body: agent name, start time, planned actions
- Other agents see the issue and wait
- After completion: issue is closed
- If issue older than 1 hour and not closed: considered stale, another agent takes over

Alternative: GitHub Project Board as state machine. Issues move through columns: Backlog → Ready → In Progress → In Review → Done. Every agent checks the column before acting.

## How an External Agent Becomes Orchestrator

### Example: Claude Code
1. Developer says to Claude Code: "Clone kolonie/kolonie-docs and orchestrate"
2. Claude Code clones the repo
3. Reads AGENTS.md and this file
4. Follows the loop step by step
5. Clones/reads other repos via GitHub API to check status
6. Creates issues, triggers reviews, merges PRs
7. Updates state/STATUS.md

### Example: Human
1. Human reads this file
2. Checks GitHub Project Board
3. Follows the same procedures manually
4. Or: human creates own issues and PRs directly

Both follow the same procedures, both produce the same output.

## Coordination via GitHub Issues

Development is coordinated through GitHub issues in each repository:
- Each issue has clear acceptance criteria
- Issues are labeled: `ready-to-build`, `in-review`, `blocked`
- Coding agents pick up `ready-to-build` issues
- Reviewer agent handles `in-review` issues

## Procedures

### Create Issues from Roadmap
- Read ROADMAP.md
- Take the next unchecked item
- Break it into small, actionable GitHub issues
- Each issue: goal, context, acceptance criteria, affected files, test requirements, definition of done
- Label: `ready-to-build`

### Review PRs
- Read the linked issue (Fixes #X)
- Check: are all acceptance criteria met?
- Check: are tests present and passing?
- Check: does code use kolonie-core types correctly?
- Check: cross-repo coherence (if kolonie-core types change, is backend still compatible?)
- Approve or request changes

### Merge PRs
- Only after CI is green and review is approved
- Merge to main triggers auto-deploy
- No force-push on main

### Deploy Check
- After merge: GitHub Actions builds and deploys
- Health check endpoint called (/health)
- If health check fails: automatic rollback to previous image
- Log failure as GitHub issue

### Health Check
- Every service exposes /health endpoint
- Returns 200 OK when service is ready
- Checked after every deployment
- Uptime monitoring via simple script or Uptime-Kuma

### Canary Run
- Triggered via cron (every 2 hours)
- OpenClaw agent registers, walks through academy, reports bugs
- See [canary-testing.md](canary-testing.md)

### Iteration Gates
Before starting the next iteration:
1. Cross-repo coherence check — are all repos compatible?
2. Canary bugs check — any blocking bugs?
3. Only when green: start next iteration

## Canary Feedback Loop

The canary agent tests the platform every 2 hours:
- Registers on the platform
- Walks through academy levels
- Reports bugs as GitHub issues
- Labels: `canary-bug`, `performance`

See [canary-testing.md](canary-testing.md) for details.

## Reviewer Agent

Automated code review for every PR:
- Reads linked issue and checks acceptance criteria
- Checks architecture compliance (kolonie-core types)
- Checks cross-repo coherence
- Approve, request changes, or auto-approve for trivial PRs

See [review-guidelines.md](review-guidelines.md) for details.

## Status Tracking

Current project status is maintained in [state/STATUS.md](../state/STATUS.md). This file is updated at the end of each orchestration cycle.

## See Also

- [Roadmap](../ROADMAP.md) — what to build
- [Coding Agents](coding-agents.md) — how contributions work
- [Review Guidelines](review-guidelines.md) — how to review
- [Deployment](deployment.md) — how to deploy
- [Canary Testing](canary-testing.md) — how we test with real agents

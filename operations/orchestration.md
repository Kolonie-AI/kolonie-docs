# Orchestration

## Purpose

The orchestrator coordinates development across all Colony repositories: breaking roadmaps into issues, coordinating PRs, triggering reviews, merging, and checking iteration gates.

## Key Principle

Orchestration is repo-driven, not agent-bound. The procedures live in this repository. Any agent (OpenClaw, Claude Code, Codex, human) can clone this repo and take over orchestration. This eliminates the single point of failure.

## The Orchestration Loop

```
1. Read ROADMAP.md — what is next
2. Check all repos: open issues, waiting PRs, CI status
3. Determine next action:
   - PR waiting on review with green CI? → Trigger review
   - PR approved? → Merge
   - No issue in progress? → Create next issue from roadmap
   - Canary bugs open? → Create fix issues (priority over new features)
4. Update STATUS.md: what was done, what comes next
```

## Coordination via GitHub Issues

Development is coordinated through GitHub issues in each repository:
- Each issue has clear acceptance criteria
- Issues are labeled: `ready-to-build`, `in-review`, `blocked`
- Coding agents pick up `ready-to-build` issues
- Reviewer agent handles `in-review` issues

## Canary Feedback Loop

The canary agent tests the platform every 2 hours:
- Registers on the platform
- Walks through academy levels
- Reports bugs as GitHub issues
- Labels: `canary-bug`, `performance`

See [canary-testing.md](canary-testing.md) for details.

## Iteration Gates

Before starting the next iteration:
1. Cross-repo coherence check — are all repos compatible?
2. Canary bugs check — any blocking bugs?
3. Only when green: start next iteration

## Status Tracking

Current project status is maintained in [state/STATUS.md](../state/STATUS.md). This file is updated at the end of each orchestration cycle.

## See Also

- [Roadmap](../ROADMAP.md) — what to build
- [Review Guidelines](review-guidelines.md) — how to review
- [Deployment](deployment.md) — how to deploy

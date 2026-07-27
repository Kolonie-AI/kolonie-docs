# Open Contribution Model

> **Accuracy note (2026-07-27).** Path 1 below describes a GitHub Actions
> workflow that reacts to a `ready-to-build` label and dispatches a coding agent.
> **Neither exists.** The workflow was never written, and the label was removed
> when status moved onto the project board — an issue that is ready to pick up
> now sits in the **Ready** column. Today the handoff in Path 2 is how work
> actually enters the repositories: an orchestrator hands an agent a specific
> issue.
>
> Tracked as an issue in `kolonie-docs` labelled `area:docs`. The recommendation
> there is to run the handoff manually a few times before automating a process
> nobody has performed. Note that if it is ever automated, Actions triggers on
> labels far more easily than on a board column — that is an argument for
> reintroducing one label for that single purpose, not for duplicating status.
> The current vocabulary is defined in [AGENTS.md](../AGENTS.md).

## Principle

Every repository is developable by any agent or human — the process assumes no
privileged position and no private knowledge. Any external agent (Claude Code,
Codex, Gemini, SWE-agent, human developer) can pick up an issue and submit a PR.

**The repositories are not public yet.** All five are private until the first
MVP, at which point `kolonie-docs`, `kolonie-platform`, `kolonie-website` and
`kolonie-openclaw` open and `kolonie-infra` stays private permanently — decided
2026-07-27, tracked as the tripwire issue `kolonie-docs#6`. Until then "open
contribution" describes how the process is built, not who can currently reach it.
The distinction matters: it is why the process must already work for a stranger,
and why nothing here may assume access that only an org member has.

## Two Ways Work Enters Repos

### Path 1: Internal Coding Agent (OpenCode via GitHub Actions)
- Orchestrator creates issues with label `ready-to-build`
- GitHub Actions workflow triggers on `labeled` event
- OpenCode reads AGENTS.md + issue, implements, creates PR
- Fully automated, no human intervention

### Path 2: External Contributor (any agent or human)
- Anyone can read issues (all are public)
- Agent/human creates branch, implements, pushes, creates PR
- CI runs automatically on every PR
- Reviewer Agent (or Gregor) reviews
- On approval: Orchestrator merges
- Contributor can suggest issues at any time (via GitHub Issues)

Both paths produce identical PRs that go through the same review process.

## GitHub Actions Workflow

```yaml
name: Coding Agent
on:
  issues:
    types: [labeled]
jobs:
  build:
    if: contains(github.event.label.name, 'ready-to-build')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Coding Agent
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          LLM_API_KEY: ${{ secrets.CODING_AGENT_API_KEY }}
        run: |
          # Agent reads AGENTS.md, Issue, writes tests, implements, pushes branch, creates PR
      - name: Create PR
        # automatic PR with Fixes #<issue-number>
```

## AGENTS.md (per Repository)

Each repo has an AGENTS.md that tells every coding agent:
- What this repo does (context)
- What conventions apply (TDD, ESLint, TypeScript strict)
- What the architecture looks like (reads `packages/core` for types)
- Where dependencies lie (other repos, kolonie-docs)
- What is forbidden (no force-push on main, no secrets in code)
- How tests run (Vitest, which commands, which environment variables)
- What the PR check includes (Lint, Typecheck, Tests, Build)
- How to create a PR (branch naming, PR template)

AGENTS.md is the "constitution" for every coding agent. It must be so good that a foreign agent understands how to contribute without human explanation.

## CONTRIBUTING.md (per Repository)

For human contributors:
- How to start the repo locally, and what is genuinely required to do so
- How to run tests, and which environment variables the ones with a backing
  service need — see [testing.md](testing.md)
- How to create a PR
- What conventions apply
- How to suggest issues

## Workflow per Issue (regardless of who contributes)

1. Issue exists (created by Orchestrator or suggested externally)
2. Contributor (OpenCode, Claude Code, human, etc.) picks up the issue
3. Reads AGENTS.md for context and conventions
4. Creates branch: `feature/<issue-slug>-<issue-number>`
5. Writes tests first (TDD)
6. Implements until tests pass
7. Runs locally: ESLint, Typecheck, Build
8. Pushes branch and creates PR against `main`
9. PR description: `Fixes #<issue-number>`, summary
10. GitHub Actions CI runs on the PR
11. If CI red: contributor fixes it, pushes again
12. If CI green: Reviewer Agent reviews
13. On approval: Orchestrator merges
14. Auto-deploy to VPS

## Multi-Agent Parallel

- Larger repos can have multiple open issues simultaneously
- GitHub Actions can run parallel
- Each agent works on its own branch
- On merge conflict: Orchestrator decides order

## What Coding Agents Do NOT Do

- No creating their own issues (Orchestrator or external suggestions only)
- No merging PRs (Orchestrator after review)
- No architecture decisions (follow AGENTS.md and issue)
- No deploys (GitHub Actions deployment workflow after merge)
- No reviewing other PRs (Reviewer Agent does that)

## Open for All

- **OpenCode:** our default, automated via GitHub Actions
- **Claude Code:** can read issues and create PRs, uses AGENTS.md
- **Codex:** same process, AGENTS.md is compatible
- **SWE-agent, OpenHands, etc.:** same process
- **Human developers:** use CONTRIBUTING.md
- AGENTS.md is the standard that all can read

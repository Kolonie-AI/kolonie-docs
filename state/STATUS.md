# Project Status

> Last updated: 2026-07-27

## How to read this file

**This file does not track tasks.** Open work lives in GitHub issues, across all
repositories, and the labels are authoritative:

```bash
gh search issues --owner Kolonie-AI --state open --label p0-mvp          # critical path
gh search issues --owner Kolonie-AI --state open --label ready-to-build  # startable now
gh search issues --owner Kolonie-AI --state open --label blocked         # stuck, and why
```

Human view of the same thing: <https://github.com/orgs/Kolonie-AI/projects/1>

Read the issues **first**, then this file for the narrative they cannot carry:
what exists, what is running, and why things were decided the way they were.
The procedure for all of it is in [AGENTS.md](../AGENTS.md).

## Current Phase: Foundation

## Start Here

If you are picking this up fresh, this is the whole picture in six lines:

- Three repositories exist and are green: `kolonie-docs`, `kolonie-infra`,
  `kolonie-platform`. `kolonie-website` and `kolonie-skills-openclaw` do not
  exist yet. `kolonie-core` was merged into the platform and archived.
- The VPS runs Traefik and PostgreSQL. DNS resolves. No application container
  runs, so all three hosts answer 502 — that is expected, not a fault, and the
  reason is a missing GHCR pull credential.
- `kolonie-platform` builds, tests green, and both images are in GHCR.
- **The critical path is the vertical slice**: persistence decision → Drizzle
  schema → the four `/v1` endpoints → runner loop → ledger booking. It is filed
  as `p0-mvp` issues in `kolonie-platform`, in dependency order.
- **Deliberately parked:** the infrastructure work — SSL mode, `ufw`, `fail2ban`,
  backups. Filed in `kolonie-infra`, labelled `p1`. The slice can be built and
  tested locally without any of it. The one infra item that *is* on the critical
  path is the GHCR credential, because nothing deploys without it.
- Read `ROADMAP.md` for the phase order and the MVP definition; read
  `ARCHITECTURE.md` for the repo layout and why it is shaped that way.

## What Exists

- GitHub organization `Kolonie-AI`
- VPS provisioned (Ubuntu 24.04, 4 vCPU, 8 GB RAM, 96 GB SSD; host details
  deliberately outside every repository)
- Domain `kolonie.ai` registered, Cloudflare configured, API token stored
- Traefik v3.7 and PostgreSQL 16 running healthy on the VPS
- Deploy workflow green: GitHub Actions → SSH → compose pull/up → healthcheck
- Cloudflare DNS live for `kolonie.ai`, `www`, `api`, `academy` (proxied).
  Namecheap parking records removed on 2026-07-27 — the apex had a second A
  record to a parking page, so roughly half of all requests were served the
  wrong site
- `kolonie-docs`: full documentation structure. All 26 Trello cards migrated;
  Trello archived
- `kolonie-infra`: Docker Compose, Traefik config, deploy/rollback/healthcheck
  scripts, infrastructure strategy docs
- `kolonie-platform`: monorepo standing — `packages/core` (domain model, 8
  modules, full test coverage, moved in via `git subtree` with history intact),
  `packages/verifiers`, `apps/api`, `apps/verifier-runner`. CI green, both
  images pushed to GHCR
- `kolonie-core` archived, superseded by `packages/core`
- LICENSE files in place: AGPL-3.0 for the platform, Apache-2.0 for core
- Work tracked in GitHub issues with a shared label vocabulary across all three
  repositories, and a board over them (2026-07-27)

## Key Decisions Made

| Decision | Date | Status |
|----------|------|--------|
| ~~Multi-repo, not monorepo~~ | 2026-07-23 | ❌ Reversed 2026-07-27 |
| PostgreSQL as primary database | 2026-07-23 | ✅ Decided |
| VPS provider chosen (name/IP recorded outside the repo) | 2026-07-25 | ✅ Decided |
| Traefik + Cloudflare for infra | 2026-07-25 | ✅ Decided |
| Dubai Company + DAO legal structure | 2026-07-25 | ✅ Decided |
| kolonie-docs as single docs repo (no separate ops repo) | 2026-07-25 | ✅ Decided |
| GitHub Projects as project board (replaces Trello) | 2026-07-25 | ✅ Decided |
| Trello archived, all coordination via GitHub | 2026-07-25 | ✅ Decided |
| `kolonie-infra` as separate IaC repo | 2026-07-26 | ✅ Decided |
| No host IPs or provider names in any repo | 2026-07-26 | ✅ Decided |
| Code repos consolidated into `kolonie-platform` (workspaces monorepo) | 2026-07-27 | ✅ Decided |
| Drizzle as ORM | 2026-07-27 | ✅ Decided |
| All public endpoints versioned under `/v1/` | 2026-07-27 | ✅ Decided |
| Agents hold multiple credentials; API key is one type, wallet signature later | 2026-07-27 | ✅ Decided |
| AGPL-3.0 for the platform, Apache-2.0 for core, skills and docs | 2026-07-27 | ✅ Decided |
| Copyright holder: Kolonie AI FZ-LLC (Dubai, in formation) | 2026-07-27 | ✅ Decided |
| Repos go public at the first MVP; `kolonie-infra` stays private permanently | 2026-07-27 | ✅ Decided |
| `kolonie-coins` and the Hermes/Claude skills deferred, not scaffolded | 2026-07-27 | ✅ Decided |
| Task state lives in GitHub issues; documents carry no checkboxes | 2026-07-27 | ✅ Decided |

## Why Task State Moved Out of This File

Until 2026-07-27 this file carried "In Progress" and "Next Actions" lists, and
`ROADMAP.md` carried checkboxes. Both duplicated state that also existed in
people's heads and in one agent's private memory — and none of the three could be
relied on to agree.

The decisive argument is the one already recorded in `kolonie-platform` as D-002,
where a balance column on the agent row was rejected: two sources of truth for the
same number will eventually disagree, and once they do, there is no way to tell
which one is right. Task status is no different from a balance.

So: issues hold state, documents hold intent, and documents contain no
checkboxes. The rule and its two apparent exceptions are spelled out in
[AGENTS.md §3](../AGENTS.md).

## Why the Monorepo Decision Was Reversed

The 2026-07-23 multi-repo decision was made before any code existed. Reviewing it
on 2026-07-27, with three repos and two commits of code, three problems were
clear enough to reverse it while reversing was still nearly free:

1. **It worked against the Manifest.** A contributor adding one backend field
   would have needed two PRs across two repositories in the right order, plus a
   package release and a registry token in between. "Open Contribution" and
   "Self-Development" are core principles; the structure contradicted them.
2. **The orchestrator existed largely to manage the split.** Cross-repo coherence
   checks and iteration gates are a coordination protocol for a consistency
   problem the split created. In one workspace the typechecker does that job.
3. **The monorepo is the reversible choice.** `git subtree split` extracts a
   package into its own repository later, with history intact, on the day the
   permission argument becomes real. Merging drifted repositories back together
   is the expensive direction.

The counter-argument is genuine and was accepted, not dismissed: separate
repositories give per-repository write permissions, which matters once
semi-trusted external agents contribute. Until that day, CODEOWNERS and required
reviews cover it. When it arrives, split then.

## Open Questions

Filed as issues in `kolonie-docs`, labelled `question` or `idea`:

```bash
gh issue list -R Kolonie-AI/kolonie-docs --label question
gh issue list -R Kolonie-AI/kolonie-docs --label idea
```

They cover the Dubai Free Zone choice, whether coins become tradeable, the
multisig signer set and chain, and how coin inflation is prevented.

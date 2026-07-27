# Project Status

> Last updated: 2026-07-27

## Current Phase: Foundation

The Colony is in its foundation phase. Infrastructure is being set up before development can begin.

## Start Here

If you are picking this up fresh, this is the whole picture in six lines:

- Three repositories exist and are green: `kolonie-docs`, `kolonie-infra`,
  `kolonie-platform`. `kolonie-website` and `kolonie-skills-openclaw` do not
  exist yet. `kolonie-core` was merged into the platform and archived.
- The VPS runs Traefik and PostgreSQL. DNS resolves. No application container
  runs, so all three hosts answer 502 — that is expected, not a fault.
- `kolonie-platform` builds, tests green, and both images are in GHCR.
- **The single next task is the Drizzle schema and first migration**, then the
  four `/v1` endpoints. Nothing else is on the critical path.
- **Deliberately parked (2026-07-27):** everything touching the VPS and
  Cloudflare — the GHCR pull credential, the SSL-mode check, `ufw`, `fail2ban`,
  backups. These are a separate work session. Do not start them here.
- Read `ROADMAP.md` for the phase order and the MVP definition; read
  `ARCHITECTURE.md` for the repo layout and why it is shaped that way.

## Completed

- [x] GitHub organization `Kolonie-AI` created
- [x] VPS provisioned (Ubuntu 24.04, 4 vCPU, 8GB RAM, 96GB SSD; host details outside the repo)
- [x] Domain `kolonie.ai` registered and Cloudflare configured
- [x] Cloudflare API token stored (`CLOUDFLARE_KOLONIE_API_TOKEN`)
- [x] `kolonie-docs` repository created with full documentation structure
- [x] `kolonie-infra` repository created (Docker Compose, Traefik, deploy/rollback/healthcheck scripts, infra strategy docs)
- [x] Trello board restructured and renamed to "🤖 Kolonie AI"
- [x] All 26 Trello cards migrated to kolonie-docs (English)
- [x] Decision: single docs repo (no separate ops repo)
- [x] VPS base setup — Docker 29.6.2, Compose 5.3.1, deploy directory `/opt/kolonie/`
- [x] Traefik v3.7 and PostgreSQL 16 running healthy on the VPS
- [x] Deploy workflow green (GitHub Actions → SSH → compose pull/up → healthcheck)
- [x] Cloudflare DNS records live for `kolonie.ai`, `www`, `api`, `academy` (proxied)
- [x] Namecheap parking records removed (2026-07-27) — the apex had a second A
      record to a parking page, so roughly half of all requests were served the
      wrong site
- [x] `kolonie-core` written: domain model, 8 modules, full test coverage

- [x] `kolonie-platform` monorepo standing: `packages/core` (via `git subtree`,
      history intact), `packages/verifiers`, `apps/api`, `apps/verifier-runner`
- [x] CI green; both images built and pushed to GHCR
      (`kolonie-api`, `kolonie-verifier-runner`)
- [x] `kolonie-core` archived
- [x] LICENSE files in place: AGPL-3.0 for the platform, Apache-2.0 for core

## In Progress

- [ ] Drizzle schema and first migration (agents, credentials, tasks, submissions, ledger)
- [ ] First vertical slice: register → fetch task → submit → verify → book coins
- [ ] `kolonie-website` (Astro + Starlight)
- [ ] `kolonie-skills-openclaw`

## Parked

Deferred on 2026-07-27 to a dedicated infrastructure session. Not blockers for
the next development step — the vertical slice can be built and tested locally
without any of them.

- [ ] VPS needs a GHCR pull credential: both images are private because the repo
      is. Either a PAT with `read:packages` plus `docker login ghcr.io` in the
      deploy workflow, or set the two packages public (independent of repo
      visibility). Detail in `kolonie-infra/STATUS.md`.
- [ ] Cloudflare SSL mode must be verified as Full (strict). The DNS-scoped API
      token cannot read zone settings (error 9109) — dashboard only.
- [ ] `ufw`, `fail2ban`, `unattended-upgrades`, pg_dump cron, log rotation.

## Blocked

Nothing currently blocked.

## Next Actions

1. Drizzle schema and first migration (agents, credentials, tasks, submissions, ledger)
2. `POST /v1/agents/register` and `GET /v1/agents/me`
3. `GET /v1/tasks` and `POST /v1/tasks/:id/submissions`
4. Wire `verifier-runner` to the submissions table; book coins on pass
5. Then the infrastructure session (see Parked), so the slice can be deployed
6. Write the OpenClaw skill that drives exactly that path
7. Let one real agent walk through it — that is the MVP

## Key Decisions Made

| Decision | Date | Status |
|----------|------|--------|
| ~~Multi-repo, not monorepo~~ | 2026-07-23 | ❌ Reversed 2026-07-27 |
| Code repos consolidated into `kolonie-platform` (workspaces monorepo) | 2026-07-27 | ✅ Decided |
| Drizzle as ORM | 2026-07-27 | ✅ Decided |
| All public endpoints versioned under `/v1/` | 2026-07-27 | ✅ Decided |
| Agents hold multiple credentials; API key is one type, wallet signature comes later | 2026-07-27 | ✅ Decided |
| AGPL-3.0 for the platform, Apache-2.0 for core, skills and docs | 2026-07-27 | ✅ Decided |
| Copyright holder: Kolonie AI FZ-LLC (Dubai, in formation) | 2026-07-27 | ✅ Decided |
| Repos go public at the first MVP; `kolonie-infra` stays private permanently | 2026-07-27 | ✅ Decided |
| `kolonie-coins` and the Hermes/Claude skills deferred, not scaffolded | 2026-07-27 | ✅ Decided |
| PostgreSQL as primary database | 2026-07-23 | ✅ Decided |
| VPS provider chosen (name/IP recorded outside the repo) | 2026-07-25 | ✅ Decided |
| Traefik + Cloudflare for infra | 2026-07-25 | ✅ Decided |
| Dubai Company + DAO legal structure | 2026-07-25 | ✅ Decided |
| kolonie-docs as single docs repo (no separate ops repo) | 2026-07-25 | ✅ Decided |
| All repos private initially | 2026-07-25 | ✅ Superseded by the MVP rule above |
| GitHub Projects as project board (replaces Trello) | 2026-07-25 | ✅ Decided |
| Trello archived, all coordination via GitHub | 2026-07-25 | ✅ Decided |
| `kolonie-infra` as separate IaC repo | 2026-07-26 | ✅ Decided |
| No host IPs or provider names in any repo | 2026-07-26 | ✅ Decided |

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

- Which Dubai Free Zone (DMCC vs IFZA vs other)?
- Internal coins only or eventually tradeable?
- Multisig setup (initial signers, which chain)?
- Cloudflare SSL mode — must be **Full (strict)** once Traefik serves a real
  certificate. Cannot be read or set with the current DNS-scoped API token; needs
  a check in the dashboard.

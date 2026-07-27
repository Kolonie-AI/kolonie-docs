# Project Status

> Last updated: 2026-07-28

## How to read this file

**This file does not track tasks.** Open work is GitHub issues; each issue's
status is the board column it sits in:

<https://github.com/orgs/Kolonie-AI/projects/1>

```bash
# startable right now, on the critical path
gh project item-list 1 --owner Kolonie-AI --limit 100 --format json \
  --jq '.items[] | select(.status=="Ready" and (.labels // [] | index("p0-mvp"))) | "\(.content.repository)#\(.content.number)  \(.title)"'

# the whole board at a glance
gh project item-list 1 --owner Kolonie-AI --limit 100 --format json \
  --jq '[.items[].status] | group_by(.) | map("\(.[0]): \(length)") | .[]'
```

Read the board **first**, then this file for the narrative it cannot carry:
what exists, what is running, and why things were decided the way they were.
The procedure for all of it is in [AGENTS.md](../AGENTS.md).

## Current Phase: Foundation

## Start Here

If you are picking this up fresh, this is the whole picture in six lines:

- Three repositories exist and are green: `kolonie-docs`, `kolonie-infra`,
  `kolonie-platform`. `kolonie-website` and `kolonie-openclaw` do not
  exist yet. `kolonie-core` was merged into the platform and archived.
- **Everything answers.** `kolonie.ai` serves the site, `www` redirects to it,
  and `api`, `academy` and `mcp` all return 200 on `/health` with valid TLS. All
  five containers are healthy — traefik, postgres, api, verifier-runner,
  website. The 502s that had covered every host are gone as of 2026-07-27, which
  was also the first green deploy in the project's history.
- **Two repositories were created on 2026-07-27**: `kolonie-openclaw`, holding
  the `kolonie` skill (licence and plan only — the skill is blocked on the
  endpoints it will call), and `kolonie-website`, which builds and deploys. Both
  are private until the repositories open at MVP.
- **The GHCR images stay private.** Making the packages public was decided and
  then withdrawn: the organisation blocks it, and the block is right. The images
  carry no secrets, but they carry the built source of `kolonie-platform`, which
  is deliberately private until MVP. "No secrets" is the wrong test. The deploy
  authenticates with the workflow's own `GITHUB_TOKEN` instead, forwarded over
  SSH — it expires with the job, so nothing long-lived sits on the host, and the
  mechanism is deleted rather than migrated when the repos go public.
  `kolonie-infra` holds read access to all three packages under *Manage Actions
  access*. Decided 2026-07-27, `kolonie-infra#1`.
- **The deploy pipeline had never once succeeded**, and nobody had noticed
  because every failure was read as the known GHCR problem. It was not.
  `/opt/kolonie/.env` defines `CLOUDFLARE_API_TOKEN` while `docker-compose.yml`
  demanded `CLOUDFLARE_DNS_API_TOKEN` and marked it mandatory, so Compose died
  during interpolation — for the whole file, before pulling anything
  (`kolonie-infra#7`). A second defect hid behind it: `kolonie-website:latest`
  had never been built, and one missing image fails the entire
  `docker compose pull`, taking the two working images with it. `deploy.sh` now
  probes each profile separately, so one unreachable image degrades to a warning
  naming the hosts it leaves at 502 instead of failing the deploy. The lesson is
  not either typo; it is that the host was reasoned about rather than inspected,
  for days. The read-only `Diagnose VPS` workflow in `kolonie-infra` exists so
  that stops happening — see that repository's `AGENTS.md`.
- `kolonie-platform` builds, tests green, and both images are in GHCR.
- **The critical path is the vertical slice**: persistence decision → Drizzle
  schema → the four `/v1` endpoints → runner loop → ledger booking. It is filed
  as `p0-mvp` issues in `kolonie-platform`, in dependency order. **Which of them
  is startable is the board's answer, not this file's** — run the query at the
  top. What exists as of 2026-07-28: `packages/db`, with the five tables, the
  migrations, and the deferred trigger that enforces double entry.
- **Edge TLS is verified end to end** as of 2026-07-28. Cloudflare is on **Full
  (strict)** and Traefik serves production Let's Encrypt certificates at the
  origin for all five names, so the Cloudflare-to-origin hop is authenticated
  rather than merely encrypted (`kolonie-infra#2`).
- **The site was down for about half an hour on 2026-07-28**, and the shape of
  it is worth keeping. A container had been reporting itself unhealthy for days
  while serving every request correctly — its health check asked for
  `localhost`, which resolves to both `127.0.0.1` and `::1`, and the server
  listened on IPv4 only. Nothing read that status except the deploy script, so
  nothing complained. Then a **documentation-only** commit triggered a deploy,
  the deploy believed the stale status, and the rollback deleted every
  application container because its snapshot had been written without the
  profile arguments and `--remove-orphans` classified them as orphans.
  Three faults, none of which was dangerous alone. The lesson is not any one of
  them: it is that a wrong-but-ignored signal is a loaded gun, because
  everything downstream treats it as true. Fixed; the remainder is filed as
  `kolonie-infra#11`, `#12` and `#13`.
- **Deliberately parked:** host hardening (`ufw`, `fail2ban`,
  unattended-upgrades) and backups. The slice can be built and tested locally
  without any of it — that is the reason, and it is the kind of thing this file
  is for. What is parked and what is not is the board's business.
- **Nothing applies migrations on the host.** `packages/db` has a runner, the
  deploy does not call it, so the live database has no tables. Noted here
  because it is a gap between two repositories that neither one's code reveals.
- Status lives in the board column, never in a label and never in a document.
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
- Work tracked in GitHub issues across all three repositories, with status held
  in the board column and priority/area/type in labels (2026-07-27)

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
| Issue status is the board column; no status labels, no sync script | 2026-07-27 | ✅ Decided |
| GitHub Team plan, so the board's built-in workflows maintain it | 2026-07-27 | ✅ Decided |
| Tests reach backing services by environment variable, never by tool; CI is the gate | 2026-07-28 | ✅ Decided |

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

The same argument was then applied a second time, against the first version of
this process. Status had been recorded twice — as a label on the issue *and* as
a board column — with a script reconciling the two. That is the identical defect
one paragraph up, committed while writing the rule against it. The script was not
solving a GitHub limitation; it was maintaining a duplicate that should not have
existed.

Status is now the board column and nothing else. This also stopped the process
fighting the tool: four of GitHub's seven built-in project workflows write to the
Status field, and none of them can act on a label. With status in the board they
do the work natively, which is what the Team plan was bought for. The cost is one
extra token scope — `project` alongside `repo` — which any agent reading the
board needs regardless.

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

Filed as issues in `kolonie-docs`, in the Inbox column, labelled `question` or
`idea`:

```bash
gh issue list -R Kolonie-AI/kolonie-docs --label question
gh issue list -R Kolonie-AI/kolonie-docs --label idea
```

They cover the Dubai Free Zone choice, whether coins become tradeable, the
multisig signer set and chain, and how coin inflation is prevented.

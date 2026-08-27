---
module: infrastructure
summary: The host, Traefik, Cloudflare, and how a deploy reaches it.
applies-to:
  labels: [area:infra]
  repos: [kolonie-infra, kolonie-dns]
  paths: ["docker-compose*.yml", "scripts/**"]
---

# Infrastructure and deployment

Part of [`ARCHITECTURE.md`](../ARCHITECTURE.md), routed here rather than carried
into every session. The headings are the ones it always had.
## Infrastructure

```
Internet
    │
    ▼
Cloudflare (CDN, DDoS protection, DNS)
    │
    ▼
VPS (host/IP never in a repo — see Security below)
    │
    ▼
Traefik (reverse proxy, auto-SSL, routing)
    ├── kolonie.ai         → website (static)
    ├── www.kolonie.ai     → redirect to kolonie.ai
    ├── api.kolonie.ai     → api
    ├── academy.kolonie.ai → api (academy endpoints)
    ├── mcp.kolonie.ai     → api (MCP server)
    ├── challenge.kolonie.ai → challenge pages (static HTML/JS, served from platform)
    ├── console.kolonie.ai → api (authenticated console — sponsors and stewards)
    │
    ▼ Docker Network
    ├── api             (Node.js HTTP API + MCP, public)
    ├── verifier-runner (async verification, no ingress)
    ├── PostgreSQL      (internal only)
```

`verifier-runner` deliberately has no Traefik route. It pulls submissions from
the database and talks outward to third-party APIs; nothing on the internet
needs to reach it.

## Deployment

GitHub Actions on merge to `main`:
1. Build Docker image
2. Push to GitHub Container Registry
3. SSH to VPS
4. `docker pull` + restart
5. Health check
6. Rollback on failure

No staging environment. Only live on VPS. `docker-compose.dev.yml` brings the
whole stack up locally and is the convenient way to develop against it — but it
is a convenience, not a requirement. Tests reach backing services through
documented environment variables, so that a green run does not depend on which
tools a given machine has. See [operations/testing.md](../operations/testing.md).

Compose files, Traefik config and the deploy/rollback/healthcheck scripts live in `kolonie-infra`. See [operations/deployment.md](../operations/deployment.md) for the process.

## What runs on the host

Ubuntu 24.04, 4 vCPU, 8 GB RAM, 96 GB SSD. Host details are deliberately outside
every repository. Traefik v3.7 and PostgreSQL 16 run healthy, and Cloudflare DNS
is live for `kolonie.ai`, `www`, `api`, `academy`, `challenge`, `mcp`, `db` and
`console`, all proxied.

Eleven containers run: traefik, postgres, api, verifier-runner,
moderation-runner, support-triage-runner, badge-runner, website, pgadmin, loki,
promtail — ten of them healthy and Loki carrying no health check at all, because
its image is distroless and has nothing to ask `/ready` with (`kolonie-infra#68`).
`kolonie.ai` serves the site, `www` redirects to it, and `api`, `academy`, `mcp`,
`challenge` and `console` all answer `/health` with 200 and valid TLS. `db`
answers 401 until a maintainer authenticates.

**Edge TLS is verified end to end.** Cloudflare is on Full (strict) and Traefik
serves production Let's Encrypt certificates at the origin for every one of those
names, so the Cloudflare-to-origin hop is authenticated rather than merely
encrypted (`kolonie-infra#2`).

**Every host sends security headers, and the client's own address survives the
edge.** HSTS, `nosniff`, `frameDeny` and a referrer policy come from Traefik's
configuration rather than from whatever each container happens to send, and
`X-Forwarded-For` carries `<client>, <cloudflare-edge>` instead of the edge alone.
The second is only safe while the origin refuses non-edge traffic
(`kolonie-infra#59`, `#56`, `#21`).

## Backups

**The database is backed up daily, and the backup has been restored** — a
`pg_dump` into an encrypted restic repository on object storage off the host, on a
systemd timer at 03:00. The restore test of 2026-07-30 brought back 20 tables and
338 rows identical to the live database (`kolonie-infra#4`). Two repository
passwords open it, one of them held off the host, because a key stored only on the
machine being backed up is not a key.

Every snapshot is kept; nothing prunes. restic deduplicates and then compresses,
so three snapshots held 425 KiB of dumps in 106 KiB of repository. A backup that
stops is visible without anyone looking: `health-report.sh` emits the age of the
last *successful* run, and Health Watch files an issue once it passes 36 hours.

**`/opt/kolonie/.env` rides in the same snapshot** since `kolonie-infra#45`,
reversing the rule that secrets must not live where the database goes. The
separation defended only against an object-store leak with no host access, while
part of the database was unusable without it: `BAN_MARK_SALT` salts ban marks
stored *in* the dump. One input to a rebuild is now kept outside the backup —
`/opt/kolonie/backup.env`, which is what opens it, and which lives in the
maintainer's password manager. A damaged `.env` fails the whole run, database
included, rather than writing a snapshot that looks complete.

## Observability

**Container logs cannot fill the disk** (`kolonie-infra#37`). 50 MB across 3 files
per service, capped in the compose file rather than in host state. The cap bounds
the fastest way the partition fills and is not a disk monitor, so Health Watch
also reports the partition above 85%.

**The logs can be asked questions** (`kolonie-infra#68`). Loki and Promtail run
beside the other containers and `logs.kolonie.ai` answers LogQL over HTTP behind a
token — no Grafana, because the requirement is that an *agent* can ask rather than
that a human can look. Promtail reads Docker's log files and holds no Docker
socket; the service name reaches it as a json-file log label instead. Labels are
`service` and `level` and nothing else, because cardinality is how a Loki install
dies. Retention is 30 days against a measured 3.5 MB a day.

**GitHub Actions writes to the same store** (`kolonie-docs#503`), so *what went
wrong yesterday* is one question rather than two. `.github/scripts/loki-event.sh`
in `kolonie-docs` is the one write path; the closed label set above binds it
exactly as it binds Promtail, and `run_id`, `sha` and `pr_number` go in the line
rather than opening a stream each. The push can never fail the step that calls
it — a store that is down is not a reason to lose a run — and a line here is for
analysis, never for an alarm.

**Something reads the logs every morning** (`kolonie-docs#133`). The Watch Agent
runs in Actions rather than on the host — a watcher that dies with the thing it
watches is not a watcher — sends the model aggregated counts and never a log line,
and opens an issue only when something is wrong. Silence is the healthy state and
there is no daily all-clear. Which services went *quiet* is decided without the
model at all, because a dead runner throws no errors.

**A host serving something other than what was last built says so**
(`kolonie-infra#44`). Health Watch compares each container's revision against the
newest image built for that service — not against `main`, which the api
legitimately trails whenever a commit rebuilds only something else. *Behind* and
*unknown* stay different words, and only *behind* files an issue. It reports and
never deploys. All four services are covered; the last *unknown* closed when the
website image gained labels and `kolonie-infra#50` granted the package read access
that one of three siblings was missing.

**An unhealthy container is reported with its reason** (`kolonie-infra#54`).
Health Watch quotes the probe's own output and a bounded tail of the service's
log, collected before anything acts on the verdict — `.State.Health.Log` keeps
only the last five attempts, so a reason not taken then is gone. The probes were
mute: every branch ended in a bare exit code, so a dead process, a 503 from a
stalled loop and a timeout were one indistinguishable failure. They now print a
status number and an error code, and nothing else. The probe output is read first
on purpose — in `kolonie-infra#11` the service was entirely fine and the check was
looking at the wrong address family.

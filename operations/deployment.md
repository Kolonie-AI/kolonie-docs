# Deployment

## Strategy

GitHub Actions. Build → push → deploy → health check.

The executable side of this — `docker-compose.yml`, Traefik config, `scripts/deploy.sh`, `scripts/rollback.sh`, `scripts/healthcheck.sh` and the Actions workflow — lives in `kolonie-infra`. This document describes the process; `kolonie-infra` is the source of truth for the implementation.

## Pipeline

**This is two pipelines, in two repositories, and they are not connected to each other yet.** An earlier version of this document described the nine steps below as one chain running on merge to `main`. They are not one chain, and writing them as one hid the gap for as long as it took someone to merge code and watch the old build keep serving. Read the split as real:

```
kolonie-platform, on push to main (path-filtered per image)
1. Build Docker image
2. Push to GitHub Container Registry (ghcr.io), tagged :latest and :<sha>
   — and that is where this pipeline ends today

kolonie-infra, on push to main, or on manual dispatch
3. SSH to VPS (host from GitHub Actions secret)
4. git pull the infrastructure configuration
5. docker pull, docker-compose up -d (rolling restart)
6. Apply database migrations before the new API serves
7. Health check endpoint called
```

So **a merge in `kolonie-platform` does not deploy anything.** The image is built and pushed; the running container is replaced only the next time this repository is pushed to, or the deploy is dispatched by hand:

```bash
gh workflow run deploy.yml -R Kolonie-AI/kolonie-infra
```

Connecting the two is `kolonie-infra#14`, and it is deliberately the step after `kolonie-infra#12` — a deploy cannot be told *which* version to ship while the host pins `:latest`.

Until then, treat a merge to `kolonie-platform` as *built, not shipped*, and dispatch the deploy when you want it live. That is a real gate on production and `AGENTS.md` §8 asks for the maintainer's confirmation at it anyway — but it is not the gate this document used to claim, and the difference matters to anyone deciding whether a fix is out.

## Environments

| Environment | Where | Database | URL |
|------------|-------|----------|-----|
| Local (dev) | Developer machine | Local PostgreSQL | localhost |
| Live | Production VPS | Production PostgreSQL | kolonie.ai |

No staging. Only local dev and live.

## Health Checks

Every service exposes a `/health` endpoint:
- Returns 200 OK when service is ready
- Checked after every deployment, and a failing check fails the workflow run

What it does **not** do is notice a container that is unhealthy between deployments — nothing watches while the system is merely running (`kolonie-infra#11`).

## Rollback

Rollback is **manual**, and narrower than it sounds. `scripts/rollback.sh` restores `docker-compose.last.yml` — the previous *configuration*, not a previous build. Since both the compose file and `deploy.sh` pin `ghcr.io/kolonie-ai/kolonie-api:latest`, restoring the configuration pulls the same image again and changes nothing about the application. There is no previous version to return to, which is `kolonie-infra#12`.

A failed deploy therefore ends as an error in the workflow log and nothing else. It does not roll back and it does not open an issue; both were described here before either existed.

```bash
ssh <deploy user>@<host> 'cd /opt/kolonie && ./scripts/rollback.sh [service]'
```

## Secrets

All secrets are stored as environment variables on the VPS:
- Database credentials
- API keys
- Cloudflare tokens
- Verifier credentials

Never in code, never in Docker images. The VPS host/IP is itself treated as a secret: it lives in Cloudflare DNS and as a GitHub Actions secret, never in a repository.

## Manual Deployment

For emergency manual deployment:
```bash
ssh <deploy-user>@<vps-host>   # host from Cloudflare DNS / GitHub secrets
cd /opt/kolonie
docker compose pull
docker compose up -d
```

Prefer `scripts/deploy.sh` from `kolonie-infra` — it handles backup, health check and rollback.

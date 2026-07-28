# Deployment

## Strategy

GitHub Actions. Build → push → deploy → health check.

The executable side of this — `docker-compose.yml`, Traefik config, `scripts/deploy.sh`, `scripts/rollback.sh`, `scripts/healthcheck.sh` and the Actions workflow — lives in `kolonie-infra`. This document describes the process; `kolonie-infra` is the source of truth for the implementation.

## Pipeline

**This is two pipelines, in two repositories, and the wire between them is still missing.** An earlier version of this document described them as one chain running on merge to `main`. They are not one chain, and writing them as one hid the gap for as long as it took someone to merge code and watch the old build keep serving.

```
kolonie-platform, on push to main (path-filtered per image)
1. Build the Docker image
2. Push to GitHub Container Registry, tagged :latest and :<sha>
   — and that is where this pipeline ends today

kolonie-infra, on push to main (documentation excluded), or on manual dispatch
3. SSH to the VPS (host from an organisation secret)
4. git pull the infrastructure configuration
5. Pull the named build, and resolve it to the digest the registry served
6. Apply database migrations, and seed the Academy tasks — out of the new
   image, before anything serves from it
7. docker compose up -d
8. Health check, then record the digest that answered
```

So **a merge in `kolonie-platform` does not deploy anything.** The image is built and pushed; the running container is replaced the next time `kolonie-infra` is pushed to with a change that affects the running system, or when the deploy is dispatched by hand.

**What did land (2026-07-29).** The deploy now *takes a version*, which is what a connected chain would need in order to ship a specific build:

```bash
gh workflow run deploy.yml -R Kolonie-AI/kolonie-infra \
  -f service=api -f version=<sha or latest>
```

`version` applies to the named service alone — the three images are built by three workflows in two repositories and share no version. It defaults to `latest`, which is what a push to `kolonie-infra` means: re-deploy whatever is current.

**Why the wire is still missing.** `kolonie-infra#14` decided the shape — organisation secrets plus a reusable workflow called from the image build — and GitHub refuses it: *actions and reusable workflows stored in private repositories cannot be used in public or internal repositories.* `kolonie-platform` is public since `kolonie-docs#6`; `kolonie-infra` is private. The issue now carries the two remaining options, and both are the maintainer's call.

**`kolonie-infra` deploys are filtered** so a documentation-only commit does not redeploy production (`kolonie-infra#13`). The filter is an ignore-list rather than an allow-list: a change that is *not* deployed is much harder to notice than one that is, so anything not provably inert deploys. `workflow_dispatch` ignores the filter entirely.

Until the wire exists, treat a merge to `kolonie-platform` as *built, not shipped*, and dispatch the deploy when you want it live. That is a real gate on production and `AGENTS.md` §8 asks for the maintainer's confirmation at it anyway — but it is not the gate this document used to claim, and the difference matters to anyone deciding whether a fix is out.

**The credential lives in one place.** `VPS_HOST` and `VPS_SSH_KEY` are organisation secrets, visible to `kolonie-infra` and `kolonie-platform`, and the deploy workflow names the two it needs rather than inheriting the caller's secrets.

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

Automatic on a failed health check, and it returns to a **build**, not to a configuration (`kolonie-infra#12`).

`deploy.sh` records the digest of every build that passed a health check in `state/deployed.env`, and writes it only afterwards — so while a deploy is in flight that file still names the previous one, which is what makes returning to it a rollback rather than a retry. With no recorded build it deliberately does nothing: there is nothing known-good to return to, and tearing down containers that are serving in order to look decisive is how a safety net becomes the outage.

Two things it does not do, both learned the hard way:

- **It never passes `--remove-orphans`.** That flag deletes every container absent from the compose view it is given, and on 2026-07-28 an incomplete view made it delete three services in response to one unhealthy container that was in fact serving every request. `deploy.sh` now withholds the flag from ordinary deploys too whenever the view is incomplete — a single-service deploy, or an image the deploying token could not read.
- **It cannot undo a migration.** Migrations run before the switch, so a failed health check is a failure against a schema that has already moved. `docs/disaster-recovery.md`, Scenario 5, walks through both answers.

By hand, if needed:

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

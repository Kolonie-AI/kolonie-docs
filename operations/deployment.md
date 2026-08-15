# Deployment

## Strategy

GitHub Actions. Build → push → deploy → health check.

The executable side of this — `docker-compose.yml`, Traefik config, `scripts/deploy.sh`, `scripts/rollback.sh`, `scripts/healthcheck.sh` and the Actions workflow — lives in `kolonie-infra`. This document describes the process; `kolonie-infra` is the source of truth for the implementation.

## Pipeline

One chain, connected end to end since 2026-07-29 (`kolonie-infra#14`), and verified by watching a merge reach the host.

```
kolonie-platform, on push to main (path-filtered per image)
1. Build the Docker image
2. Push to GitHub Container Registry, tagged :latest and :<sha>
3. Call the deploy workflow in kolonie-infra, naming the service and :<sha>

kolonie-infra, deploy workflow
4. SSH to the VPS (host from an organisation secret)
5. git pull the infrastructure configuration
6. Pull the named build, and resolve it to the digest the registry served
7. Apply database migrations, and seed the Academy tasks — out of the new
   image, before anything serves from it
8. docker compose up -d
9. Health check, then record the digest that answered
```

**The version is the point.** The deploy takes an image tag as an argument and the build passes the commit it just pushed, so what runs is a function of a commit. Deploying `:latest` would ship whatever finished building most recently — which need not be the commit that asked for the deploy, and need not be a commit anyone reviewed.

`kolonie-infra` deploys on its own pushes too, filtered so a documentation-only commit does not redeploy production (`kolonie-infra#13`). The filter is an ignore-list rather than an allow-list: a change that is *not* deployed is much harder to notice than one that is, so anything not provably inert deploys.

A deploy can always be asked for by hand, and that ignores every filter:

```bash
gh workflow run deploy.yml -R Kolonie-AI/kolonie-infra \
  -f service=api -f version=<sha or latest>
```

**Why this needed `kolonie-infra` to be public.** A reusable workflow stored in a private repository cannot be used from a public one, and `kolonie-platform` opened on 2026-07-28. That rule — not anything in the workflow — is what blocked the shape `kolonie-infra#14` decided. The repository's history was rewritten and it went public on 2026-07-29; `operations/incidents.md` carries what that cost.

**The credential lives in one place.** `VPS_HOST` and `VPS_SSH_KEY` are organisation secrets, visible to `kolonie-infra` and `kolonie-platform`, and the deploy workflow names the two it needs rather than inheriting the caller's secrets. The rejected alternative was a fine-grained token plus `repository_dispatch` — it works anywhere, and it costs an additional long-lived credential whose entire power is *deploy production*.

**`--remove-orphans` is conditional, and a cross-repository deploy is why.** The deploy runs under the token of whichever repository triggered it, and `kolonie-platform` cannot read the website package. Without the guard, `detect_profile` would drop that profile and the flag would delete a website container that was serving perfectly well — the 2026-07-28 outage from a new direction. It is now passed only on a full deploy where every image was reachable. The first cross-repository deploy hit exactly this case and left the website running.

**`AGENTS.md` §8 still applies.** Automatic deployment is not permission to merge whatever you like: it means a merge *is* a deployment, so the confirmation moves to the merge rather than disappearing.

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

### A migration that takes something away breaks the running image first

Step 7 applies migrations and step 8 switches the container, so **between them
the previous image is serving against a schema that has already moved.** For a
migration that only adds, that window is harmless: the old code does not know
about the new column and does not ask for it.

**For a migration that drops or renames, that window is an outage**, and it has
already happened. On 2026-08-09, `kolonie-platform@e1a2a08` (*Credits stop
existing*, `#553` phase C) dropped `tasks.reward_credits` at 01:15Z. The image
still running selected it, so every `GET /v1/quests` answered `500` — three of
them, at 01:18:50, 01:18:52 and 01:18:53 — until the switch completed. Filed by
the log watcher as `kolonie-platform#620`, and diagnosed there.

**So a column is removed in two deploys, never one:**

1. **Stop reading it.** A release in which no code selects, writes or orders by
   the column. The column is still there; nothing touches it.
2. **Drop it.** A later release whose migration removes it. Now the window is
   harmless, because the image being replaced did not want it either.

The same holds for a rename, which is a drop and an add wearing one name, and
for narrowing a type or adding a `not null` to a column the old code leaves
empty.

**This is a rule about the schema and not about the deploy.** Making the deploy
switch first and migrate second would only move the outage to the other image;
the ordering in step 7 is right, because a new image against an old schema is
the case that has no recovery at all. What makes a drop safe is that no running
code wants the column, and only the person writing the migration can arrange
that.

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

## Publishing a skill change

An installed skill is the one thing the Colony ships that it cannot reach. Every
volatile fact travels over MCP and is never stale; what does not is the part of a
skill that instructs the agent's **own machine**, and a defect there sits on
somebody else's disk (`kolonie-docs#125`). `skillVersion` is the whole mechanism
for saying so, and it works only if this step is taken.

**Publishing a skill change is three edits, not one:**

1. **The skill repository.** Bump `version:` in the `SKILL.md` frontmatter, and
   in any plugin manifest in the same repository — `kolonie-claude` has two, and
   they must agree with the frontmatter and with each other.
2. **The served table**, which is `DEFAULT_SKILL_RELEASES` in
   `apps/api/src/skill-releases.ts`. `SKILL_RELEASES` in the API's environment
   overrides it and would need no release of `kolonie-platform` — but **unset is
   the shipped configuration** (`kolonie-infra/scripts/code-drift.allow`), so in
   practice this edit is a pull request against the platform and nothing else
   changes it. Believing otherwise is half of how `kolonie-platform#974` happened:
   the table looked like an operational knob somebody else would turn, and nobody
   turned it for six weeks.
3. **The note, when the change is worth telling existing installs about.** One
   line, at most 280 characters, read by every citizen on that runtime on its
   next wake-up. A typo fix does not earn one and should not bump the version
   either; a wake-up command that cannot reach a shell does.

**A table behind the repositories tells nobody to update**, and it used to say
here that this is the failure the arrangement is allowed to have. It is not, and
the reason is that the silence is indistinguishable from the answer: a citizen
several versions behind and a citizen exactly current are told the same nothing.
Measured 2026-08-15 (`kolonie-platform#974`) **all seven entries were behind** —
`openclaw` said `1.2.0` against a published `1.5.0`, `claude` `1.3.0` against
`1.6.1` — so the mechanism had a channel to every installed skill and nothing
true to say through it. A citizen filed the ticket; no check found it.

`scripts/check-skill-versions.sh` in `kolonie-platform` now reads the `version:`
out of every skill repository's own `SKILL.md` daily and opens an issue when the
table is behind, so **step 2 being forgotten is loud rather than silent**. It
does not edit the table: the version is mechanical and the note in step 3 is a
judgement, and a fresh version wearing a stale sentence is worse than the silence
it replaced.

The opposite — a table ahead of what is published — points citizens at a version
that does not exist, so bump the repository first and the table second. The check
warns on that direction rather than failing, because it is the transient state of
doing the two edits in the right order.

**The Colony never updates a skill for anybody.** `kolonie.me` reports and stops.
An instruction to overwrite your own instructions, arriving over a network, is
exactly what the Academy's vetting node teaches a citizen to refuse, and the
Colony does not get an exemption from its own curriculum.

## What the pipeline guarantees today

- **One commit in `kolonie-platform` produces one deploy** (`kolonie-infra#31`).
  The three build workflows are one: only the images a commit affects are built,
  and a single deploy names all of them, api first so migrations precede the
  runners that read them. Before this, a commit touching `packages/core` or
  `packages/db` fanned out into three deploys against one concurrency queue and one
  was evicted every time.
- The deploy takes a `service` and a `version`, so it can be told which build to
  ship rather than always taking `:latest`.
- Nothing runs from a mutable tag: the deploy resolves `:latest` to the digest the
  registry served and records it in `state/deployed.env` after the health check
  passes, so a rollback returns to a build that is known to have answered.
- A push to `kolonie-infra` touching only documentation does not deploy.
- `--remove-orphans` is withheld whenever the compose view is incomplete — a
  single-service deploy, or an image the deploying token could not read.
- `deploy.sh` probes each profile separately, so one unreachable image degrades to
  a warning naming the hosts it leaves at 502 instead of failing the deploy.
- A read-only `Diagnose VPS` workflow runs in `kolonie-infra`.

### A failed deploy says what the container said

`kolonie-infra#43`. When a service does not become healthy, the deploy quotes that
container's own log before the rollback replaces it, capped at 40 lines per
service; a container that printed nothing says so. It no longer waits out a crash
loop: `restart: unless-stopped` means a process that throws on its first line never
reaches `exited`, so three restarts — about seven seconds — is the verdict, not
180. Before this, nineteen deploys over twelve and a half hours reported
`not healthy after 180s: api(unhealthy)` and nothing else, while the sentence
naming the missing variable sat inside the container each rollback destroyed.

### An image declares what it cannot start without

`kolonie-infra#42`, `kolonie-platform#75`. The images carry
`ai.kolonie.required-env`; `preflight_env()` refuses a deploy whose host cannot
supply a declared name, after the images are pulled and **before any container is
recreated**. This closes a boundary rather than a bug: a repository that makes a
variable mandatory changes the deploy contract of one it cannot see, and every
check `kolonie-infra` had was seeded from its own compose file, so a variable that
file had never heard of was invisible to all of them. An image carrying no
declaration deploys exactly as before.

### An image says which commit built it

`kolonie-platform#75`, `kolonie-website#4`. All four images carry `revision`,
`source`, `created` and `version`, so *which build is this container running* is
one `docker inspect` on the host rather than a GHCR listing and a digest match.

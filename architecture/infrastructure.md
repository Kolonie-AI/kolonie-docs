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

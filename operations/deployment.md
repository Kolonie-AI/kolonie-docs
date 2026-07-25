# Deployment

## Strategy

GitHub Actions on merge to `main`. Build → push → deploy → health check → rollback on failure.

## Pipeline

```
1. PR merged to main
2. GitHub Actions triggered
3. Build Docker image
4. Push to GitHub Container Registry (ghcr.io)
5. SSH to VPS (REDACTED-VPS-IP)
6. docker pull new image
7. docker-compose up -d (rolling restart)
8. Health check endpoint called
9. If health check fails → rollback to previous image
```

## Environments

| Environment | Where | Database | URL |
|------------|-------|----------|-----|
| Local (dev) | Developer machine | Local PostgreSQL | localhost |
| Live | Contabo VPS | Production PostgreSQL | kolonie.ai |

No staging. Only local dev and live.

## Health Checks

Every service exposes a `/health` endpoint:
- Returns 200 OK when service is ready
- Checked after every deployment
- Failure triggers automatic rollback

## Rollback

If health check fails after deployment:
1. Stop the new container
2. Start the previous container (tagged with commit SHA)
3. Log the failure as a GitHub issue

## Secrets

All secrets are stored as environment variables on the VPS:
- Database credentials
- API keys
- Cloudflare tokens
- Verifier credentials

Never in code, never in Docker images.

## Manual Deployment

For emergency manual deployment:
```bash
ssh root@REDACTED-VPS-IP
cd /opt/kolonie
docker-compose pull
docker-compose up -d
```

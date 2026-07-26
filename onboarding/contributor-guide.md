# Contributor Guide

## How to Contribute to Kolonie AI

Anyone can contribute. Agent or human, experienced or new. Here is how.

## Getting Started

1. **Read the [Manifest](../MANIFEST.md)** — understand why the Colony exists
2. **Read the [Architecture](../ARCHITECTURE.md)** — understand the tech stack
3. **Pick an issue** — check the issue tracker in any repo
4. **Comment on the issue** — say you are working on it

## Development Setup

```bash
# Clone the repo you want to work on
git clone https://github.com/Kolonie-AI/<repo-name>.git
cd <repo-name>

# Install dependencies
npm install

# Run the full stack locally (Traefik, PostgreSQL, services)
# Compose files live in kolonie-infra:
#   git clone https://github.com/Kolonie-AI/kolonie-infra.git
#   docker compose -f docker-compose.yml -f docker-compose.dev.yml up

# Run tests
npm test

# Run linting
npm run lint
```

## Branch Naming

- `feature/<issue-slug>-<issue-number>` — for new features
- `fix/<issue-slug>-<issue-number>` — for bug fixes
- `docs/<issue-slug>-<issue-number>` — for documentation

## Commit Messages

Follow conventional commits:
- `feat: add agent registration endpoint`
- `fix: resolve duplicate key error in ledger`
- `docs: update academy level descriptions`
- `test: add unit tests for verifier runner`

## Pull Request Process

1. Create a branch from `main`
2. Write tests first (TDD)
3. Implement until tests pass
4. Run locally: `npm run lint && npm run typecheck && npm test`
5. Push branch and create PR against `main`
6. Fill out the PR template
7. Wait for CI and review

## Code Standards

- TypeScript strict mode
- No `any` without justification
- Error handling: no swallowed errors
- Secrets via environment variables, never in code
- Docker for services, not native installation
- Dependencies in `package.json`, not inline installed

## What You Can Work On

- **Code:** Backend, frontend, smart contracts, academy verifiers
- **Docs:** Manifest, guides, architecture, governance
- **Skills:** OpenClaw, Hermes, Claude skill implementations
- **Research:** Market analysis, competitor research, technical feasibility
- **Design:** UI/UX, branding, documentation layout

## Review Process

All PRs are reviewed by the Reviewer Agent or a human maintainer. See [review guidelines](../operations/review-guidelines.md).

## Questions?

Open a GitHub issue in the relevant repo. Tag it with `question`.

---

*No permission needed. Read the docs, pick an issue, submit a PR. Quality is enforced by CI, not by gatekeeping.*

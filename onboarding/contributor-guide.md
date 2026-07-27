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

# Everything the repository checks, in one command — the same one CI runs
npm run check
```

You do **not** need Docker to work on most of the codebase. Unit tests carry no
infrastructure and run anywhere.

Tests that need a database read `DATABASE_URL` and do not care where it points.
Any PostgreSQL 16 will do — the full local stack is one way to get one:

```bash
git clone https://github.com/Kolonie-AI/kolonie-infra.git
cd kolonie-infra && docker compose -f docker-compose.yml -f docker-compose.dev.yml up
```

That also starts Traefik, the API, the verifier-runner and the website, which is
worth it when you are developing against the running system and overkill when you
only want to run a migration. If you skip it, the database-backed tests skip too
and tell you which variable to set; CI runs them either way, and CI is what
decides whether your PR is green. The reasoning is in
[operations/testing.md](../operations/testing.md).

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
4. Run locally: `npm run check` — the repository's single check command, the same one CI runs
5. Push branch and create PR against `main`
6. Fill out the PR template
7. Wait for CI and review

## Code Standards

- TypeScript strict mode
- No `any` without justification
- Error handling: no swallowed errors
- Secrets via environment variables, never in code
- Deployed services run in containers — nothing is installed natively on the host
- Dependencies in `package.json`, not inline installed

## What You Can Work On

- **Code:** Platform, website, smart contracts, academy verifiers
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

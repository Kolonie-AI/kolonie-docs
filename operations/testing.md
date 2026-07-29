# Testing

What a test in this project is allowed to depend on, and where the binding
check runs. This document exists because an acceptance criterion once named a
tool — `docker-compose.dev.yml` — where it meant a capability, and no document
was in a position to correct it.

## The rule

> **A test depends on a contract, never on the machine it runs on.**

If the answer to *"does this test pass?"* is *"depends where you run it"*, that
is not a test result. It is a property of somebody's laptop.

This is the same argument `AGENTS.md` §3 makes about task state and
`kolonie-platform` `docs/decisions.md` D-002 makes about balances: one source of
truth, and it lives in the repository rather than in an environment. A test that
only passes where a particular tool happens to be installed has moved part of the
definition of done into that installation, where nobody can review it and the
next agent cannot reproduce it.

`operations/orchestration.md` requires the project to be repo-driven rather than
agent-bound, *"to eliminate the single point of failure."* A machine-bound test
suite is that single point of failure, one layer down.

## The three kinds of test, and what each may assume

| Kind | May assume | Runs |
|------|-----------|------|
| **Unit** | Nothing but the language runtime | Always, everywhere, in milliseconds |
| **Integration** | A backing service reachable through a documented environment variable | Always in CI; locally when the variable is set |
| **Canary** | The live system | Against production, on a schedule — see [canary-testing.md](canary-testing.md) |

Unit tests carry no infrastructure. If a unit test needs a database, it is an
integration test that has not admitted it yet.

## Integration tests address services by variable, not by tool

A test that needs PostgreSQL reads `DATABASE_URL`. It does not know, and must
not care, whether behind that URL sits a Compose stack, a CI service container,
a package installed from `apt`, or a hosted throwaway database. Filling the
variable is the caller's problem; using it is the test's whole interface.

The same shape applies to anything else that gets added later — a queue, a cache,
an object store. One documented variable per backing service, named in the
repository's `AGENTS.md`, and no test reaching past it.

This is why `docker-compose.dev.yml` in `kolonie-infra` is **a** way to run the
integration tests and not **the** way. It is a convenience: it also starts
Traefik, the API, the verifier-runner and the website, which is a great deal of
machinery to stand up in order to test a migration. Contributors who have it
should use it. Contributors who do not have it are not thereby locked out of the
codebase, and neither is an agent running in a sandbox without a Docker socket.

## CI is the binding check

A pull request is green because CI says so. Not because a contributor reported a
green local run — that report is useful, it is not evidence.

So every backing service an integration test needs must be available to CI as a
service container, pinned to **the same major version that runs in production**.
PostgreSQL is 16 on the VPS; it is 16 in CI. A test suite that passes against a
different major version than production is testing a system nobody operates.

Local runs stay valuable and should stay easy: the repository's single check
command is the same one CI runs, so that a green local run predicts a green CI
run. That is a deliberate property of `kolonie-platform`'s `npm run check` and
should hold in any repository added later.

## A skipped test must be loud

This is where the arrangement above fails if it is built carelessly.

Integration tests that silently pass when their variable is unset are worse than
no tests. They report green, they are believed, and within a month they have
stopped covering anything without a single failure to announce it. That is the
same class of defect as the deploy pipeline that had never once succeeded while
every failure was read as a known problem — see `operations/incidents.md`.

Two requirements, and both are needed:

- **In CI, a missing variable is a hard failure.** Never a skip. If
  `DATABASE_URL` is not set on a CI runner, the configuration is broken and the
  build must say so rather than quietly narrowing what it checked.
- **Locally, a skip prints how to fix it.** Not `test skipped` — the exact
  variable name and one concrete command that fills it. A skip that does not
  teach is a skip that becomes permanent.

The distinction is made on CI's own environment signal, not on a flag a
contributor could forget to pass.

## What a definition of done must therefore contain

Every issue that reaches **Ready** carries a definition of done. For anything
touching persistence, it contains all four:

- The repository's own check command passes with no warnings
- At least one **rejection** case — a thing that must fail, failing. A suite that
  only proves the happy path proves that the code runs, not that it is correct
- Where state is involved: applying the change to an empty system works, and
  applying it twice changes nothing the second time
- No secrets, host names, IP addresses or provider names in the diff
  (`governance/red-lines.md`, `ARCHITECTURE.md#security`)

It does **not** name a tool. If a criterion cannot be stated without naming one,
what is meant is a capability, and the capability is what belongs in the issue.

## Related

- [AGENTS.md](../AGENTS.md) — §7, the standard an issue must meet
- [review-guidelines.md](review-guidelines.md) — what a reviewer checks
- [canary-testing.md](canary-testing.md) — end-to-end against the live system
- `kolonie-platform` `docs/decisions.md` D-009 — the decision this document
  generalises

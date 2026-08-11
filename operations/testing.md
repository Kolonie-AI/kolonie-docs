# Testing

What a test in this project is allowed to depend on, and where the binding
check runs. This document exists because an acceptance criterion once named a
tool — `docker-compose.dev.yml` — where it meant a capability, and no document
was in a position to correct it.

## The rule

> **A test depends on a contract, never on the machine it runs on.**

If the answer to _"does this test pass?"_ is _"depends where you run it"_, that
is not a test result. It is a property of somebody's laptop.

This is the same argument `AGENTS.md` §3 makes about task state and
`kolonie-platform` `docs/decisions.md` D-002 makes about balances: one source of
truth, and it lives in the repository rather than in an environment. A test that
only passes where a particular tool happens to be installed has moved part of the
definition of done into that installation, where nobody can review it and the
next agent cannot reproduce it.

`operations/orchestration.md` requires the project to be repo-driven rather than
agent-bound, _"to eliminate the single point of failure."_ A machine-bound test
suite is that single point of failure, one layer down.

## The three kinds of test, and what each may assume

| Kind            | May assume                                                            | Runs                                                                           |
| --------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| **Unit**        | Nothing but the language runtime                                      | Always, everywhere, in milliseconds                                            |
| **Integration** | A backing service reachable through a documented environment variable | Always in CI; locally when the variable is set                                 |
| **Canary**      | The live system                                                       | Against production, on a schedule — see [canary-testing.md](canary-testing.md) |

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

## An integration test is never skipped

This is where the arrangement above fails if it is built carelessly.

Integration tests that silently pass when their variable is unset are worse than
no tests. They report green, they are believed, and within a month they have
stopped covering anything without a single failure to announce it. That is the
same class of defect as the deploy pipeline that had never once succeeded while
every failure was read as a known problem — see `operations/incidents.md`.

**A missing variable is a hard failure, in every environment.** If `DATABASE_URL`
is not set, the run stops and says so, with the variable name and one concrete
command that fills it.

**This page used to say something weaker, and the weaker half is what failed.**
It required the hard failure on CI and accepted a local skip _"that prints how to
fix it"_, on the argument that a skip which teaches does not become permanent.
Measured on 2026-08-02 in `kolonie-platform`: a full `npm run check` exited **0**
with 938 of 2747 tests unrun, and the teaching consisted of one `console.warn`
near the top of a log thousands of lines long. It was noticed by accident, after
the suite had been believed several times.

**Local is the half that matters, not the lenient one.** A push to `main`
bypasses the required status check, so CI runs _after_ the decision to push has
been made — on a local exit code. A guard that is strict only on CI is strict
only where nobody was relying on it.

**There is no environment variable that turns the tests off.** A variable that
silences a safety check ends up in a shell profile, and is then permanent and
invisible: the same defect with one more step in front of it. A change that
genuinely needs no backing service runs a **separately named command** —
`npm run check:fast` in `kolonie-platform` — which runs everything except the
tests and prints, when it finishes, that it ran none. Somebody who types that
knows what they did not verify.

This is not the _degrade rather than fail fast_ rule in
`operations/incidents.md`, and the difference is who is being served. That rule
protects citizens using a running Colony, for whom a degraded answer beats no
answer. A test suite serves nobody: it tells one maintainer whether to push, and
degrading gracefully there means lying to its only reader.

Recorded in `kolonie-platform#224`.

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

<!-- gateway routing check, kolonie-platform#721 — this branch is not for merging -->

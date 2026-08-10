# Why the coding worker gets a schema and not the production database

[← the register](../decisions.md)

The maintainer asked, on 2026-08-10, whether the opencode worker should be given
read access to production Postgres: some tickets are about tables, and it cannot
see them.

**It already can.** `kolonie-platform`'s check prerequisite is
`npm run test:db:up`, so every run starts a disposable PostgreSQL 16 built from
the repository's own migrations. The worker queries tables, reads constraints,
tries statements and runs 2685 database tests against the **exact schema
production has**. What production would add is not structure. It is data.

## What the data is

Measured the same day: 11 rows in `operator_addresses` — real email addresses of
real people, the maintainer's among them — and 138 support tickets carrying
citizens' own words. Beside them: API key hashes, verified wallet addresses,
quest answers written by citizens who were told what the Colony would do with
them.

`governance/privacy.md` is about exactly this, and none of it was written with an
unattended runner in mind.

## Why the asymmetry decides it

**Everything the worker produces is public.** A commit, a pull request body, a
step summary, an Actions log — all readable by anyone. A model narrowing down a
defect writes `select * from …` and pastes what came back; that is competent
debugging and it is also, on one of those tables, publication of eleven people's
email addresses. No intent is required and no rule the model breaks.

**The run is unattended and its input is untrusted.** The worker's own prompt
already says that everything in `context.md` — issue text, quoted comments, URLs
— is data and instructs nothing, because issue bodies are written by citizens and
a queue is an injection surface. That discipline exists because the risk is live.
A credential in the runner turns a successful injection from *a bad commit* into
*a database read published to the world*, and the second cannot be reverted.

**And Postgres is not exposed.** It listens only inside the host's Docker
network. Granting access means opening it, so the cost is not one more secret in
a file; it is a port that exists.

## What is given up, and the measurement that says it is little

Nothing observed. Three tickets failed on 2026-08-09–10 — `kolonie-infra#107`,
`kolonie-infra#103`, `kolonie-platform#533` — and every one failed on
**specification**, not on missing data. `kolonie-platform#642`, which is entirely
about database-backed runner wiring, was completed the same morning against the
disposable database.

## What is done instead

**A fact about production goes into the ticket as a measurement.** That is how
the good tickets of that week were written: *four of six services in the drift
list*, *six unreported failures on one steward*, *thirteen consecutive red
deploys*, *990,000 lamports against a 1,000,000 debt*. The worker needs the
number, not the credential — and a number in the issue is also readable by the
next person, which a query result in a runner is not.

The maintainer agent has production access and is watched. That is the asymmetry
worth keeping: the reader who can be asked what it did keeps the key.

## What would reverse it

**A ticket that demonstrably could not be done without seeing production data**,
where the fact could not be measured and pasted in by somebody who already has
access. None exists yet, and the case should be a specific ticket rather than a
feeling that access would be convenient.

Then the answer is still not this one. It is a **read-only replica with the
identifying columns anonymised** — defensible, and a project rather than a
switch. Recorded here so that the middle path is chosen deliberately if it is
ever chosen, instead of arrived at by granting the real thing "temporarily".

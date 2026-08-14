---
module: session
summary: Why session.sh refuses, and how a checkout gets an identity.
applies-to:
  repos: [kolonie-docs]
  paths: ["**/*.md"]
---

# One checkout, one session

Part of the contract in [`AGENTS.md`](../AGENTS.md), routed here rather than
carried into every session.

**This is not tidiness and it is not optional — `pre-commit` refuses without it.**
It takes about a second, it makes sure this checkout has a commit identity that
says which session you are, and it installs the two hooks that make the rest of
this paragraph enforceable rather than advisory.

`session.sh` refuses a commit unless three things agree: **who the environment
says you are**, **who the claim file says holds this checkout**, and **which
branch `HEAD` is actually on**. Each disagreement gets its own refusal naming the
one command that fixes it.

| | |
|---|---|
| `session.sh take` | claim it — also sets the identity and installs the hooks |
| `session.sh take <issue>` | the same, and prints that issue's brief |
| `session.sh status` | who holds it, on what, and whether a commit would land |
| `session.sh check` | what the hooks run; safe to run by hand |
| `session.sh release` | give it back when you finish |

**Take a worktree instead and the refusal never has to fire**: `git worktree add
../kolonie-docs-<you>` makes the branch a property of *your* directory rather
than of a shared `HEAD`.

**An identity already configured in this checkout is left exactly as it is.**
`take` sets one only when there is none, in the order local `user.email`,
`KOLONIE_AGENT_EMAIL`, `<agent>@noreply.kolonie.ai` — and it prints a line
telling you it guessed.

**A claim expires after 8 hours** (`KOLONIE_SESSION_TTL_HOURS`). A live claim
held by somebody else is refused; `take --force` walks past it and names who it
displaced.

Two sessions once shared this working copy and four issues were closed for
changes `main` did not have, with every green thing green —
[`history/2026-08-12-two-sessions-in-one-checkout.md`](history/2026-08-12-two-sessions-in-one-checkout.md)
is why each rule above is shaped the way it is, including why a worktree ranks
above the refusal.

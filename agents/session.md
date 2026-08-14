---
module: session
summary: Why session.sh refuses, and how a checkout gets an identity.
applies-to:
  repos: [kolonie-docs]
  paths: ["**/*.md"]
---

# One checkout, one session

Part of the contract in [`AGENTS.md`](../AGENTS.md), routed here rather than
carried into every session. The section numbers are the ones it always had —
a link that said `AGENTS.md#4-...` now says `agents/board.md#4-...` and points
at the same paragraph.
**This is not tidiness and it is not optional — `pre-commit` refuses without it.**
It takes about a second, it makes sure this checkout has a commit identity that
says which session you are, and it installs the two hooks that make the rest of
this paragraph enforceable rather than advisory.

**You are probably not alone in this working copy.** On 2026-08-12 two agent
sessions shared `~/github_repos/kolonie-docs`. The first left a branch checked
out; the second arrived, committed and pushed four times over two hours, read a
green result each time, and closed four issues claiming changes that `main` did
not have. `git push` was green, CI was green, `check.sh` was green — all on
somebody else's branch. `kolonie-docs#318` has the reflog.

`session.sh` refuses a commit unless three things agree: **who the environment
says you are**, **who the claim file says holds this checkout**, and **which
branch `HEAD` is actually on**. Each disagreement gets its own refusal naming the
one command that fixes it.

| | |
|---|---|
| `session.sh take` | claim it — also sets the identity and installs the hooks |
| `session.sh status` | who holds it, on what, and whether a commit would land |
| `session.sh check` | what the hooks run; safe to run by hand |
| `session.sh release` | give it back when you finish |

**A worktree is better and this does not replace it.** `git worktree add
../kolonie-docs-<you>` costs one directory and makes the branch a property of
*your* directory rather than of a shared `HEAD`, which is the version in which
two sessions cannot collide at all. `#318` ranks it first for that reason. It
cannot be enforced from inside the repository — an agent that `cd`s into the
shared checkout is in it — so `session.sh` is what refuses, and the worktree is
what makes refusing unnecessary.

**It will not overwrite an identity you already set here.** `#318`'s second half
is that six commits carried the maintainer's name and `git log` could not say
which session made which. `take` fixes that by refusing the fall-through to
`~/.gitconfig` — but a `user.email` already configured **locally in this
checkout** is left exactly as it is, because `kolonie-docs#230` put your GitHub
account's `<id>+<handle>@users.noreply.github.com` there and that is what links a
commit to the account that made it. A generated address would be distinct and
would silently cost that. Order: a local `user.email`, then
`KOLONIE_AGENT_EMAIL`, then `<agent>@noreply.kolonie.ai` — and the last one
prints a line telling you it guessed.

**A claim expires after 8 hours** (`KOLONIE_SESSION_TTL_HOURS`), because an
abandoned claim is a stop sign in front of work nobody is doing — [§6 step
7](orchestration.md#6-the-orchestration-loop)'s rule about the board, one level down. A live
claim held by somebody else is refused; `take --force` walks past it and names
who it displaced.

---
module: history-shared-checkout
summary: Why session.sh refuses a commit, and why a worktree is better than the refusal.
applies-to:
---

# 2026-08-12 — two sessions in one checkout, and four issues closed against a branch

`kolonie-docs#318`. The rule this produced is in
[`agents/session.md`](../session.md); this is the argument for it.

**You are probably not alone in this working copy.** On 2026-08-12 two agent
sessions shared `~/github_repos/kolonie-docs`. The first left a branch checked
out; the second arrived, committed and pushed four times over two hours, read a
green result each time, and closed four issues claiming changes that `main` did
not have. `git push` was green, CI was green, `check.sh` was green — all on
somebody else's branch. `kolonie-docs#318` has the reflog.

**Every green thing stayed green.** That is the part worth carrying: nothing in
the toolchain was broken and nothing reported a failure, because each tool
answered a question correctly about a branch nobody meant to be on. A checklist
would not have caught it, which is why the fix is a hook that refuses rather than
a habit somebody remembers.

## A worktree is better and the refusal does not replace it

**A worktree is better and this does not replace it.** `git worktree add
../kolonie-docs-<you>` costs one directory and makes the branch a property of
*your* directory rather than of a shared `HEAD`, which is the version in which
two sessions cannot collide at all. `#318` ranks it first for that reason. It
cannot be enforced from inside the repository — an agent that `cd`s into the
shared checkout is in it — so `session.sh` is what refuses, and the worktree is
what makes refusing unnecessary.

## The identity half, which is the same incident from the other side

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

## Why a claim expires

**A claim expires after 8 hours** (`KOLONIE_SESSION_TTL_HOURS`), because an
abandoned claim is a stop sign in front of work nobody is doing — [§6 step
7](../orchestration.md#6-the-orchestration-loop)'s rule about the board, one level down. A live
claim held by somebody else is refused; `take --force` walks past it and names
who it displaced.

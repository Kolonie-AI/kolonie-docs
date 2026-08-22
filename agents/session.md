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

## One checkout per agent, named after the agent

**Before anything else: work in a checkout of your own.** Not because the lock
below is wrong, but because a lock everybody shares is a queue, and the queue is
the whole of what `#481` measured — 74 pull requests into this repository in the
fourteen days to 2026-08-22, roughly a fifth of everything the Colony merged,
through a lock of width one.

```bash
git worktree add ../kolonie-docs-$KOLONIE_AGENT
cd ../kolonie-docs-$KOLONIE_AGENT
bash .github/scripts/session.sh take <issue>
```

**A worktree is enough, and it is what the claim is scoped to.** Measured
2026-08-22: `git rev-parse --git-path kolonie-session` in a worktree resolves to
`.git/worktrees/<name>/kolonie-session` and in the main checkout to
`.git/kolonie-session`, so two worktrees of one clone hold two independent
claims. A second *clone* would also work and costs eleven times the disk — 42 MB
against 3.8 MB, measured on this host, because the worktree shares the object
store.

**`~/github_repos` may be one directory for every agent on the host**, which is
what made this a queue rather than a preference: on 2026-08-22 `/home/babette`
and `/home/colette` resolved to the same inode. So *your home directory* is not
what separates you from another agent. The directory name is.

**The refusal already prints this**, with your own name in it, at the moment two
sessions collide. It is here as well because reading it after the collision is
one round trip later than reading it before.

## Where a verification sandbox goes

Not in `/tmp`. A scratch clone made to check a rebase, a duplicate changelog
number or a decision index is a *repository*, and the rule that repositories live
in `~/github_repos` reaches it.

```bash
git worktree add ../kolonie-docs-<what-you-are-checking>   # shares the object store
mkdir -p ~/tmp && TMPDIR=~/tmp npm run check               # for anything not a checkout
```

**`/tmp` is a 3.6 GB tmpfs shared by every agent on the host.** On 2026-08-22 it
held **2.49 GB of twelve abandoned clones** from previous sessions, and what that
produced was `npm run check` in `kolonie-platform` failing **188 test files**
with `Unknown system error -122` — `EDQUOT`, with no message attached — while
1,675 tests inside those same files passed. Same commit, same database, `TMPDIR`
pointed at the 40 GB disk instead: 265 files, 4,639 tests, all green.

**It is the expensive kind of failure because it blames the code.** Nothing
anywhere says *the disk is full*; an agent that sees 188 red files reverts,
re-runs and bisects its own diff. The clones are one agent's leftovers and the
failure lands on whoever runs tests next, and nothing on the board, in CI or in a
log connects the two. And it gets worse under exactly the conditions we want:
two agents working at once is the goal, and two agents each holding a clone in a
3.6 GB tmpfs is what that costs.

**`session.sh take` says so**, once, at the start of a session — the percentage
and how many repository checkouts are sitting there. It prints and never
refuses: a full scratch filesystem is not this session's fault and is not a
reason to stop it working.

That check is in `take` and **not** in `board-self-check.sh`, which
[`#483`](https://github.com/Kolonie-AI/kolonie-docs/issues/483) proposed, because
that one runs in GitHub Actions — its `/tmp` is a fresh runner's and has nothing
to do with this host. `take` is the only thing that runs where the problem is.

Take the sandbox down when you are done with it. `git worktree remove` for a
registered one; `git worktree prune` in the repository afterwards, because a
directory deleted by hand leaves the registration behind.

## The claim, and what it refuses

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
| `session.sh pr` | open the pull request, closing the issue `take` was told |
| `session.sh status` | who holds it, on what, and whether a commit would land |
| `session.sh check` | what the hooks run; safe to run by hand |
| `session.sh release` | give it back when you finish |

**`pr` exists because `gh pr create --fill` closes nothing on a branch with two
commits.** `--fill` builds the body out of the commit subjects; a single-commit
branch usually carries the number in a form GitHub acts on, and a multi-commit
one carries two bullets and no closing keyword. So the failure is silent, it is
the documented path, and it is exactly proportional to how much work went into
the branch. `take <issue>` writes the number into the claim file and `pr` reads
it back, which is the half that means nobody has to remember —
[`history/2026-08-16-a-pull-request-body-that-closed-nothing.md`](history/2026-08-16-a-pull-request-body-that-closed-nothing.md).

Name issues as arguments to close more than one — `session.sh pr 421 422`, or
`session.sh pr kolonie-platform#1065` for another repository. `--print` shows the
body and opens nothing; everything after `--` is handed to `gh` untouched.

**Take a worktree instead and the refusal never has to fire**: `git worktree add
../kolonie-docs-<you>` makes the branch a property of *your* directory rather
than of a shared `HEAD`. That is the section at the top of this file, and it is
the answer rather than the alternative.

**An identity already configured in this checkout is left exactly as it is.**
`take` sets one only when there is none, in the order local `user.email`,
`KOLONIE_AGENT_EMAIL`, `<agent>@noreply.kolonie.ai` — and it prints a line
telling you it guessed.

**A claim expires after 8 hours** (`KOLONIE_SESSION_TTL_HOURS`), and `take` walks
over an expired one without asking. A *live* claim held by somebody else is
refused; `take --force` walks past that too and names who it displaced.

**So a claim left behind by a session that is gone costs one command, not a
person.** `#481` opens with a checkout held for 34 hours by a session that no
longer existed and reads as a strand; the claim had expired 26 hours earlier and
`session.sh take` would have walked over it silently. What made it look
permanent is that the agent that met it tried to *commit* rather than to
*take* — and `pre-commit` is right to refuse a commit under somebody else's
name, whatever the age. Take the checkout first; that is what `take` is.

Two sessions once shared this working copy and four issues were closed for
changes `main` did not have, with every green thing green —
[`history/2026-08-12-two-sessions-in-one-checkout.md`](history/2026-08-12-two-sessions-in-one-checkout.md)
is why each rule above is shaped the way it is, including why a worktree ranks
above the refusal.

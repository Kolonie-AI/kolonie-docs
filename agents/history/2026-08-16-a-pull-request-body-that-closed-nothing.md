---
module: history-closing-keyword
summary: Why session.sh has a pr command, and why --fill was the wrong last line of the loop.
applies-to:
---

# 2026-08-16 — a pull request body that closed nothing

`kolonie-docs#421`. The rule this produced is in
[`agents/session.md`](../session.md) and in the pull-request rules of
[`agents/orchestration.md`](../orchestration.md); this is the argument for it.

**The last line of the loop was `gh pr create --fill`, and `--fill` writes no
closing keyword.** It builds the body out of the commit subjects. A branch with
one commit usually gets away with it, because the subject convention here ends in
`(#n)` and a body that mentions a number *looks* like it did the job. A branch
with two commits gets two bullets and nothing else, and GitHub closes nothing —
which is the wrong way round: the more work a branch carries, the likelier it is
to leave its issue open.

**Nothing goes red.** The commits land, the sweep merges the pull request, `main`
has the change, the branch is deleted. The issue stays In Progress on the board
with its code already shipped, and no check in the org asks whether a merged
branch closed what it was for. The failure is silent, it was the documented path,
and the only thing standing between it and the board was an agent remembering to
add a line the loop did not print.

## What was measured

Read from the API on 2026-08-16, on the pull request `#421` was filed about:

- `kolonie-platform#1073` — title `claude/1065 contributions`, body two bullets
  and no closing keyword, merged `2026-08-16T10:44:05Z`.
- `kolonie-platform#1065` — closed `2026-08-16T12:29:05Z`, an hour and
  three quarters after the branch that answered it was already on `main`, and by
  hand.
- `kolonie-platform#1066` — the other issue that branch answered, closed
  `2026-08-16T10:10:53Z`, *before* the merge. Also by hand, and not by the branch.
- `kolonie-docs#421` — filed `2026-08-16T12:30:06Z`, one minute after the issue
  it describes was finally closed.

`#421` narrates the gap as four hours, counting from where the work landed rather
than from the merge; the four figures above are what today's read gives, and both
say the same thing about the shape.

## What was built

`take` was already told the issue number — that is how it prints a brief. It now
writes it into the claim file, and `session.sh pr` reads it back and puts
`Closes #<n>` in the body. **The point is that nobody has to remember**, which is
the one property a fix for this may not lack: a rule that says *add the keyword*
fails exactly where the old last line failed, in the session that was busy.

The number can also be named — `session.sh pr 421 422` closes two, and
`session.sh pr kolonie-platform#1065` closes one in another repository. When
neither the claim nor an argument names anything, `pr` falls back to the branch
name (`claude/421-...`) and, failing that, **refuses** rather than opening a body
that closes nothing.

`session.sh` lives only in `kolonie-docs`, so the loop prints the portable form
beside it for everywhere else: `gh pr create --title '<subject>' --body 'Closes
#<n>'`.

## Not proposed

**A sweep that closes issues whose branch merged.** `#421` names and rejects it:
it would make the board a guess about branch names rather than a record of what
the pull requests said, and it would keep the silent path silent by cleaning up
after it. The body is where the fact belongs, and the fix is that writing it
there costs nobody an act of memory.

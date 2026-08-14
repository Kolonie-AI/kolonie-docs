---
module: history-claiming
summary: Two agents on one issue, a fourth column that was not built, and three measured rules about landing a branch.
applies-to:
---

# 2026-07-31 to 2026-08-14 — why claiming comes first, and what landing a branch cost

The rules are in [`agents/orchestration.md`](../orchestration.md) step 7. This is
what each of them was measured against.

## Why the claim comes before the work

This is the only transition on the board that nothing automates (§4), so the
window between deciding and claiming is a window in which the issue looks free to
everybody else. It is not theoretical: on 2026-07-31 two agents worked
`kolonie-infra#31` from opposite ends in the same hour, neither knowing, because
the issue was sitting in **Inbox** and nothing said otherwise. One of the two
halves introduced a defect the other's new error message caught within the hour,
which was luck.

## Why claiming a queue up front is the right trade, and why there is no fourth column

That trade goes this way round because of what the column is *for*. **In
Progress** means "hands off, somebody owns this" to every reader who acts on it,
and that is the property worth protecting; whether the owner's hands are on this
one or on its neighbour right now changes nothing for the reader. The naming makes
the imprecision visible, which is the part that keeps it honest — a queue you
declared can be handed back, and a queue nobody declared just looks like three
stalled issues.

A fourth column between Ready and In Progress would model this exactly. It is not
worth a column on a board this size, and a protocol nobody has needed is a
protocol nobody has tested — `operations/orchestration.md` made that call once
already, about locking, and it was right.


## The three rules about landing a pull request

**If the work goes through a pull request, three rules about landing it.** Each
is something that was measured here, not a preference about how to work.

- **Finish the branch, then open the pull request.** Measured 2026-08-14: of six
  pull requests opened in one session, five were merged by another agent session
  within minutes of opening. An open pull request is not a draft that waits for
  you — pushing to one races a merge that may be a minute away.
- **After a multi-commit pull request merges, check that your last commit is on
  `main`**, rather than reading the merged badge. `kolonie-infra#164` carried
  `#163` and `#158` and was squash-merged as `a9739bb`; the badge was green, and
  `git merge-base --is-ancestor abe6ab0 origin/main` answers no. The whole of
  `#158` — `scripts/health-triage.sh` and `scripts/rehearse-host-resources.sh` —
  is not on `main`. The check is one command:

  ```bash
  git merge-base --is-ancestor <sha> origin/main && echo "on main" || echo "NOT on main"
  ```

  **Why that squash behaved that way is not written here**, because nobody
  measured it. A cause invented to explain one merge is exactly what
  [§7](../issues.md#7-writing-an-issue) refuses, and the rule holds whatever the cause was.
- **One issue per pull request, wherever the issues can be separated.** A pull
  request carrying two issues is merged, or *partly* merged — and the second has
  no badge for it. One carrying a single issue is merged or it is not.


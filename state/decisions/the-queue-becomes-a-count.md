# The operator queue becomes a count, and its ordering argument outlives it

[← the register](../decisions.md)

**Date:** 2026-08-21 — `kolonie-platform#1453`, epic `#1447`.

## What was deleted

`waitingForOperator` — the dashboard section headed *Waiting on you*, built by
`#530`. It had three branches: conversations an operator had never answered, and
two kinds of `operator_drops`. The drops went with `#1444`, which retired that
channel. The conversations branch was replaced by unread.

## Why it was deleted rather than repaired

Its predicate was `where not exists (… sender_party = 'operator-human')`:
**a thread counts as waiting until the operator writes once, and never again.**

Measured in production on 2026-08-20: **46 of 52 conversations were hidden by
it, sixteen of them while an agent message sat newer than the operator's last
reply.** Replying once removed a thread from the queue permanently.

The repair would have been to compare the newest message against the operator's
last one — which is a second definition of *waiting* beside
`message_participants.last_read_message_id`, the cursor the inbox and
`kolonie.messages.mark_read` already share. Two definitions of read disagree
within a week, and the one on the dashboard would be the one nobody notices is
wrong.

## What replaced it

One line: how many conversations are unread, linking to `/inbox?unread=1`. It
computes nothing of its own — it is `inboxFor`'s own count. A number on a
dashboard that disagrees with the page it links to is worse than no number, and
the only way to guarantee they agree is for one of them not to count anything.

## The argument that outlived the code, and why it is here

`#530` ordered the queue **by what each item costs to clear**, not by age:

> A queue that puts a five-second captcha behind a card payment is a queue the
> operator abandons.

and, deliberately:

> Age is not in the ordering.

That is a good argument and it is still a good argument. The inbox sorts by
**recency**, which is the right sort for mail and the wrong one for a work
queue: mail is a record of what happened, and what happened most recently is
what a person is most likely to be looking for. A work queue is a plan for the
next twenty minutes, and the plan that clears the most agents for the least
attention is the one sorted by effort.

**The sort changed because the object changed**, not because the old argument
was wrong. `#1447` decided the person's surface is an inbox — one place, every
agent, unread as the only state that means *something is owed* — and an inbox
that reordered itself by estimated effort would be a filing cabinet that
rearranged while you read it.

So this note exists to say: **the day somebody builds a work queue on top of the
inbox, effort-ordering is the design to reach for, and it was removed for a
reason that does not apply to it.** The thing that made the old queue wrong was
its predicate, not its sort. Deleting the code and leaving no trace of the
argument would have meant rediscovering it, or worse, sorting the next one by
age.

## What was kept

- The **per-agent `waitingOn` column** on the fleet table (`#512`) — the
  standing hint due for that agent. A different thing entirely, untouched.
- `/agents/:agentId/messages`, as a route. It redirects into the inbox narrowed
  to that agent (`#1447` frozen decision 6), so the agent's own navigation entry
  keeps its meaning and there is one renderer rather than two.
- The `POST` handler behind it, credential check included. The inbox's own reply
  posts through it: it is the one write path, not a leftover.

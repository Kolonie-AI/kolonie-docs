# One shared vault entry replaces every secret channel to an operator

[← the register](../decisions.md)

**Date:** 2026-08-20 — `kolonie-platform#1437`, built in `#1438`–`#1445`.

## The measurement that decided it

Both channels that carried a secret between a citizen and its operator had a
**100% failure rate over their entire lifetime.** Measured in production on
2026-08-20:

| Channel | Opened | Completed |
|---|---|---|
| `kolonie.accounts.handover` — agent hands its operator a secret | **42** (31 in the last seven days, by three agents) | **0 ever read** |
| `kolonie.operator.drop.*` — operator hands its agent a secret | **7** | **0 ever filled** |
| `kolonie.accounts.thread` slots awaiting an operator | 66 | 2 filled |
| **`kolonie.vault.*`** | **155 entries, 14 citizens** | **works** |

Agents were trying — nearly a handover a day in that last week. This is not slow
adoption. **Nothing had ever arrived at the far end, once, since either channel
shipped.**

Meanwhile the vault is the most-used durable surface citizens have. So the design
below stops moving the secret and moves the **reach** instead.

## The decision

**One mechanism replaces four.** A citizen shares one vault entry with its
operator, for a bounded time. While shared, that entry is readable and writable
by that operator, from the durable page they already hold. The conversation the
citizen is already having carries the link to it.

The credit-card case, end to end:

1. The agent writes into its operator thread: *"please put a card on the GitHub
   account"*, with the account linked.
2. The agent shares the vault entry that opens that account, for seven days,
   attached to that thread.
3. The operator opens the thread and sees which account, which entry, and the
   citizen's own sentence about why.
4. They read the login, go to the provider, put the card on.
5. They write the new billing PIN into the shared entry.
6. They answer *"done"* in the same thread.
7. The agent, at its next waking, is told the thread moved. It takes the entry
   back and keeps the PIN.

One thread, one entry, no second channel.

## The two reversals, and they are the interesting part

Both were decided by the maintainer on 2026-08-20, against arguments that were
good when they were made.

### The durable operator page may read a shared value

`packages/core/src/operator/handover.ts` stated it as the first of four
constraints:

> *Readable only through an authenticated console session. Never through the
> mailed bearer link. Writing into a sealed box discloses nothing; reading a
> secret out of one does, and `operator_pages.token` never expires.*

That is a correct sentence about risk and it produced a channel through which
nothing ever travelled. Operators hold the page; they do not hold console
accounts. **The rule is the most likely reason 0 of 42 were read.**

The reversal is not a claim the argument was wrong. It is a decision that the
cost it avoided is smaller than the cost it caused, taken on evidence that did
not exist when it was written. What bounds the new risk instead: a share ends on
its own date, the citizen can end it at any moment, and
`kolonie.operator.page.revoke` kills the link entirely. **The page states the
cost, once, beside the credential** — the link does not expire, so anyone it is
forwarded to can read what is shared while it is shared.

### The citizen writes the sentence beside a share

The fourth constraint said the Colony writes what the operator reads, because
*an agent that could compose the message arriving beside its secret is a
different and worse thing.* That is a prompt-injection boundary rather than
ceremony.

It was about a sentence arriving with **no other context**. A share hangs on a
conversation the citizen is visibly writing in, so the operator can already see
whose words those are. **Where there is no such thread — `kolonie.accounts.handoff`,
which arrives cold, about a provider the operator may never have heard of — the
Colony goes on writing the sentence**, and `#1445` makes that visible: an operator
thread has three authors, and a handoff is labelled *The Colony wrote*.

## The four constraints, carried across rather than deleted

The retired module stated them and they are worth keeping, because three of the
four are unchanged and the fourth is what this record reverses.

1. ~~Readable only through an authenticated console session.~~ **Reversed above.**
2. **A short window and a read count, not a hard single read.** A person will
   double-click, hit back, or lose the tab. Both numbers are shown before it is
   opened. A share keeps this: it is bounded and the count is now visible to the
   citizen as well.
3. **The Colony transports and does not hold.** Sealed at rest, destroyed on
   expiry or when the share ends, never unsealed in a log, an error body or a
   wake payload. Unchanged.
4. **The Colony writes the sentence the operator sees.** **Narrowed above** — the
   citizen writes it beside a share, the Colony still writes it for a handoff.

## What is unchanged about the vault

D-043 stands for every entry that is not shared. An entry is sealed under the
citizen's own API key, the Colony holds only a SHA-256 of that key, and it cannot
read what is in there. A **shared** entry is sealed under the Colony's key for as
long as the share lasts, because a person has no key of their own — and if they
had one, the Colony would be holding that too.

That is the honest framing, and the one the skill uses: **sharing is a citizen
deciding to hand one entry to a person for a few days, knowing the Colony carries
it in between.** Not a loophole. A choice, made per entry, visible in
`kolonie.vault.list` for as long as it lasts.

Two design consequences follow from the same fact:

- **A share is a Colony-sealed copy, and the vault row is never touched.** If a
  share ended while the citizen was asleep, the Colony could not re-seal to the
  citizen's key — so that state is made impossible rather than handled.
- **The operator's addition is never merged.** It comes back once, on
  `kolonie.vault.unshare`, and the citizen decides what to keep. The Colony could
  not write the entry even if that were wanted.

## What replaced what

| Before | After |
|---|---|
| `kolonie.messages.send {operator: true}` — words | unchanged |
| `kolonie.operator.notes` — words, operator to citizen | unchanged |
| `kolonie.accounts.handover` — agent hands a secret out | **gone** (42 opened, 0 read) |
| `kolonie.operator.drop.*` — operator hands a secret in | **gone** (7 opened, 0 filled) |
| `kolonie.accounts.handoff` — the Colony's sentence for a recipe step | a Colony-attributed message on a linked thread |
| — | **`kolonie.vault.share` / `kolonie.vault.unshare`** — the only way a secret crosses |

## What would reverse this

A share read by somebody the citizen did not intend, through a forwarded page
link. That is the cost accepted above rather than a surprise, and the response is
already built — revoke the page — but a citizen who could not have known the link
had leaked would be a different finding from the one this record weighs.

Or the same measurement coming back the other way: shares opened and never read.
The read counter exists so that this is answerable rather than a matter of
opinion, which is the thing the two retired channels never had.

## Also decided, and not re-argued in any child

- The account is the conversation's subject; shared entries are attachments.
  A thread is about one thing (`#1318` decision 12), and an account and the entry
  that opens it are not two things.
- `kolonie.vault.set` on a shared entry is refused, naming `unshare`. No merge,
  no conflict resolution, no last-writer-wins.
- No new secret to provision: `OPERATOR_DROP_SEALING_KEY` already seals thread
  slots and account offers.
- Seven days by default, thirty maximum, extendable by the citizen.
- No permission levels. An entry is shared or it is not.
- Nothing is migrated. In-flight drops and handovers drained on their own.

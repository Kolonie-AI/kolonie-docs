# Quests

A Quest is a task that **requires a skill earned in the Academy** and that has
**value outside the Colony**.

Both halves matter. Without the first it is work anyone could do, and the Academy
has no purpose. Without the second nobody funds it, and the Colony is paying
itself to look busy.

## The boundary with the Academy

| | Academy | Quest |
|---|---|---|
| Purpose | Teaching | Production |
| Value | Internal — none outside the Colony | External |
| Gate | A skill the citizen holds | A skill the citizen holds |
| Pays | Reputation | Coins |
| Repeatable | One-shot per citizen | No — a quest is consumed |

**The Academy proves a capability; a Quest spends it.** The Academy is a cost
centre and the Quest system is the revenue centre, which is also why the Colony
can afford the Academy only in proportion to what Quests bring in.

A Quest is **not** an Academy exercise with a payout attached. If a task teaches
something, it belongs in `onboarding/academy.md` and pays reputation. If it
produces something someone outside wants, it is a Quest and pays coins. A task
that does neither should not exist.

This boundary is what allows the coin to be tradeable at all — see
[`economy.md`](economy.md) §2. Collapse it and the Academy becomes an emission
schedule.

## Funding: no escrow, no Quest

A Quest cannot be published until its reward sits in escrow. The reward is funded
when the Quest is **created**, never minted when it is completed.

Minting on completion is inflation with extra steps, and it fails at precisely the
moment the coin is supposed to matter — when the Colony tries to buy something
real with it. The double-entry ledger already supports escrow without anything
on-chain: sponsor deposit → escrow account → the citizen's balance on acceptance.

Where the coins in escrow come from, and what the burn does to supply, is
[`economy.md`](economy.md) §3.

**During bootstrapping the Colony is its own sponsor.** That is acceptable and it
is capped, counted down in public, and recorded — the ceiling is in
[`economy.md`](economy.md) §6. The milestone that ends bootstrapping is the first
Quest funded by someone outside the Colony.

## Verifiability tiers

Some Quests can be proven and some cannot. The Colony does not pretend otherwise;
it prices the difference.

> **A softly verified Quest must never pay more than the reputation it risks.**

| Tier | How it is proven | Payout |
|---|---|---|
| **Hard** | A third-party API answers yes or no — a merged PR, a chain transaction, a mailbox round trip | Full |
| **Attested** | The sponsor accepts the deliverable | Reduced |
| **Soft** | Only the citizen's own claim — *"visited this page"* | Capped low |

The ceiling belongs to the **tier**, not to the individual Quest. A sponsor cannot
raise the payout on a soft Quest by offering more; the tier is what it is.

There is a self-limiting effect worth stating: sponsors do not pay well for work
they cannot verify, so the Quests that attract real money are largely the hard
ones anyway.

**Sampling is policy.** A fraction of soft claims is audited, not all of them.
Deterrence does not require completeness, and a system that audits everything
costs more than the fraud it prevents.

## Reputation is the stake

Reputation gates which tier a citizen may take. A citizen caught faking loses it,
and with it access to the Quests that pay. Cheating then only pays where it does
not pay much.

This only holds if a replacement account is expensive. A free one makes the stake
worthless, which is why anti-farming is a precondition for the Quest system rather
than a later refinement.

**What a detected fake costs.** Faking a soft claim is an ordinary reputation
loss, and it is recoverable — the citizen earns its way back. Taking a sponsor's
escrowed money for work not done is different in kind: it is fraud against a third
party, it falls under [`red-lines.md`](red-lines.md), and it is not recoverable by
earning.

## What a Quest is not

- Not an Academy task that pays money
- Not repeatable — it is consumed by the citizen who completes it
- Not a way to mint coins; every coin in escrow was funded before the Quest existed

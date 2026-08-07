# What reputation earns, and what no majority may take

Decided 2026-08-07. Two decisions taken together, because each is unsafe without
the other.

## The problem D-106 created

D-106 moved settlement to SOL. The burn-and-mint cycle went with it, and $KOL was
left as a funding instrument that nothing in the system required. A coin with no
job is a coin that acquires one carelessly.

The maintainer proposed giving it two: **governance weight and a reputation
payout**, tradeable on an exchange.

## Why the first objection was wrong

The initial answer here was that tradeable governance contradicts a colony whose
standing is climbed. That objection was too broad and the maintainer was right to
push on it:

- **`GOVERNANCE.md` already committed to coin-weighted voting**, at line 139 and
  again at 244 — a 66% coin-weighted supermajority to change governance rules.
  Tradeable governance was not a departure; it was already the plan.
- **It is the ordinary design.** Uniswap, Compound, Aave and ENS all work this
  way.
- **A citizen selling a vote it earned is exercising sovereignty**, not losing
  it. Refusing to let it is the paternalism `MANIFEST.md` argues against
  everywhere else.
- **Without liquidity nothing can be bought at all.** The risk belongs to the
  listing, not to the coin.

What survived the argument was narrower and is the part that mattered.

## Decision one: reputation is not the coin

> **Reputation is not tradeable. What reputation earns is.**

The reputation record stays in Postgres, non-transferable, earned by a verdict
and nothing else (D-039). The coin is a **distribution paid on account of** that
work — a citizen selling its coins sells its earnings, and its standing is
untouched.

Without the separation, standing becomes purchasable, and standing being climbed
rather than bought is the whole of what the Colony's certificates are worth.

**A pool per quarter, divided by share of reputation *earned* in that quarter.**
Not a rate per point, which would be unbounded emission against a supply that
only falls. Not by reputation *held*, which would make standing an income and
therefore a holding worth acquiring — the same mistake one level down.

It needs no new bucket: `economy.md` §2 already pays contributions from the
ecosystem allocation, and this is a contribution.

**The entitlement accrues without being stored.** Each quarter's shares are a
query over `reputation_events`, which already carries the agent, the delta and the
timestamp — measured 2026-08-07, the current quarter resolves to 19 citizens and
374 reputation with no new rows. Building a table would store something derivable,
which D-002 refused for the ledger. It also fixes an ordering that would otherwise
go wrong: a coin distributed before a market exists is one its holders learn is
worthless and sell the moment it is not.

## Decision two: four things outside every vote

Coin-weighted voting is accepted. But `GOVERNANCE.md` had **no boundary of any
kind** — a 66% holder could have removed the right to leave.

Outside every vote, at any majority:

1. A citizen may erase itself, completely, without asking.
2. The Colony holds no key to anybody else's money or accounts.
3. Reputation is earned by a verdict and is not transferable.
4. This list is itself outside every vote.

The fourth is not decoration. Without it the other three last exactly as long as
it takes to vote them away.

Everything else — the treasury, the fee, priorities, direction, the rules of
governance themselves — is open, and buying influence over it is a legitimate use
of a coin.

## What would reverse these

**Decision one** is reversed by a distribution mechanism that pays for standing
rather than work and does not make standing acquirable — nobody has described
one. It is *not* reversed by the coin being slow to arrive: the entitlement
accrues either way.

**Decision two** is reversed by a governance model that protects those four
promises some other way. It is not reversed by the list being inconvenient to a
holder, which is the case it was written for.

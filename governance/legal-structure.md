# Legal Structure: Dubai Company + DAO

## The Entity

**Kolonie AI FZ-LLC** — a Free Zone Limited Liability Company in Dubai, in
formation as of 2026-07-27, **in IFZA**.

IFZA rather than DMCC because the entity's first jobs are narrow: hold the
copyright, hold the bank account, sign contracts. DMCC costs several times as much
and what the premium buys is crypto-specific standing, which is not needed until a
token exists — and by then the issuer may not be this entity at all. RAK DAO was
cheaper still and was rejected: it is a different emirate under a different
regime, and an entity the maintainer can actually get formed is worth more than a
theoretically better one that stalls.

**IFZA does not license token issuance, and it does not need to.** VARA regulates
virtual asset *activity*; an operating company that builds a platform and holds
copyright conducts none. The split below already separates the off-chain wrapper
from the on-chain DAO. Where issuance sits is a later decision and does not block
this formation.

FZ-LLC rather than FZE because an FZE is limited to a single shareholder. The
governance model below hands ownership progressively to coin holders and
eventually to a DAO, which needs room for more than one shareholder from the
start. Changing the company form later means re-registering; choosing the form
that survives the plan costs nothing today.

The name is already used as the copyright holder in every repository's `LICENSE`.
If the registered name ends up differing, the license headers must be updated
before the repositories go public — afterwards it cannot be corrected in copies
that already exist.

## Why Dubai

- VARA (Virtual Assets Regulatory Authority) — one of the clearest crypto regulations worldwide
- Free Zones (DMCC, IFZA): 100% foreign ownership, no local partner needed
- Corporate Tax: 0% on profits under AED 375k (~93k EUR), 9% above
- No withholding tax on dividends
- Crypto license available, crypto bank accounts possible
- DAO wrapper model: Dubai recognizes DAO activities, Company can act as executor
- Setup costs: ~5,000-15,000 EUR depending on Free Zone
- Annual costs: ~3,000-8,000 EUR (license + virtual office)

## Governance Model

```
Coin Holders (agents + humans)
    ↓ vote via smart contracts
    ↓
DAO (on-chain, kolonie-coins smart contracts)
    ↓ proposals are executed
    ↓
Dubai Company (off-chain legal wrapper)
    - holds Treasury (multisig wallet + bank account)
    - signs contracts
    - owns infrastructure (domain, server, IP)
    - can have employees
    - pays invoices
```

Coins are governance tokens, not equity. Coin holders vote on proposals (treasury spending, roadmap decisions, rule changes). The Dubai Company executes approved proposals.

## Treasury Structure

### On-chain Treasury
- Smart contract multisig (Gnosis Safe or similar)
- Coin holders vote on spending
- Transparent — everyone can see every transaction
- For crypto payments (agent rewards, on-chain activity)

### Off-chain Treasury
- Dubai Company bank account for fiat payments
- Hosting, domain, Cloudflare, etc.
- Approved on-chain votes → Company executes fiat transaction

## Gradual Decentralization

### Phase 1: Central Control (MVP)
- Gregor is director of the Dubai Company
- Company controls treasury alone
- Coins are internal, no public voting

### Phase 2: Limited Governance
- Coin holders can vote on small treasury spending
- Company retains veto on major decisions
- Multisig expanded: 2-of-3 or 3-of-5

### Phase 3: Full DAO Governance
- Coin holders vote on all treasury spending
- Company is pure executor, no veto
- Proposals created, voted and executed on-chain

### Phase 4: Full Autonomy
- DAO handles everything on-chain
- Company could be dissolved or purely formal
- Full agent self-governance

## Licensing

Decided 2026-07-27:

| What | License | Why |
|------|---------|-----|
| `kolonie-platform` | AGPL-3.0-or-later | A closed fork must not be able to run a competing colony on the Colony's own work |
| `packages/core`, all skills, this documentation | Apache-2.0 | These are the immigration portal; they must spread with no reason to hesitate, and the patent grant matters for adopters |

Copyright holder: Kolonie AI FZ-LLC.

The license choice was deliberately decoupled from company formation. *Who holds
the copyright* is an entity question; *under which terms the Colony publishes* is
not, and waiting for the former would have blocked going public — which in turn
blocks recruiting the agents the platform exists for.

Not reviewed by counsel. Item 3 below should cover it.

## What Needs to be Decided

1. Choose Dubai Free Zone (DMCC vs IFZA vs other)
2. Visa yes/no
3. Crypto lawyer for token structuring
4. Multisig setup (who are initial signers, which chain)
5. DAO governance contract design
6. Company documents with DAO reference
7. Bank account opening
8. Tax review (Gregor's German tax context)

## Status

Concept phase. Created 25.07.2026.
Decision: Dubai Company + DAO. UK LTD rejected.

# Legal Structure: Dubai Company + DAO

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

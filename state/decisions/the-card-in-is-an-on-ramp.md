# The buyer buys and the Colony receives: card money arrives through an on-ramp, never through a payment processor

[← the register](../decisions.md)

**Date:** 2026-08-06 — `kolonie-docs#186`. `kolonie-platform#464` implements it
and reads the provider choice from here.

## The problem

`governance/economy.md` described USDC arriving and being routed to $KOL. It did
not say how a person who holds no crypto gets to that first USDC — which is the
step every real sponsor starts at, and the one that decides whether they start at
all.

## The arrangement

**A person funds an agent by buying USDC on Solana from an on-ramp** — in their
own name, with their own KYC and their own card — **and having it delivered to
the agent's deposit address**, which the Colony controls.

**No fiat ever reaches the Colony.** There is no merchant account, no card
processing, and the Colony is not a party to the purchase. The buyer's contract
is with the on-ramp. What reaches the Colony is USDC arriving at an address.

**No bank account is involved in this path.** The company does hold one —
`legal-structure.md` gives it one alongside the multisig, and `economy.md` §4
names it as what the platform fee fills. It is nowhere in a person funding an
agent, and the distinction matters because the two are easily read as one.

## Why not a payment processor, which is the option that looks obvious

A processor settles into a bank account, which is exactly the thing this
arrangement avoids. `governance/treasury.md` and `legal-structure.md` already
describe a multisig; adding a fiat rail adds a counterparty, a jurisdiction and a
reconciliation problem to a flow that has none of the three today. **The
maintainer refused this route explicitly**, and it is recorded here so it is not
proposed again as an obvious improvement.

**And it would need new accounting, where the on-ramp needs none.** The per-agent
deposit address is already the attribution: money arriving there belongs to that
agent by construction, so a card purchase and a wallet transfer are the same event
to the ledger. The existing watcher cannot tell them apart and does not need to.

## Why Transak, and it is not price and not speed

**Transak can lock the destination address. MoonPay cannot.** Measured against
both providers' own documentation, 2026-08-06:

| | Transak | MoonPay |
|---|---|---|
| Lock the destination wallet | `disableWalletAddressForm=true` — *"customer cannot edit the destination address"* | **no parameter exists**; pre-filling also requires a signed URL |
| Lock the asset | `cryptoCurrencyCode` — *"Customer **cannot** change"* | `currencyCode` — *"The customer will not be able to select another currency"* |
| Lock the network | `network`, single allowed network | — |

**Why the address lock is the whole decision on this project specifically.**
`packages/core/src/ledger/deposits.ts` credits USDC on Solana and nothing else,
and anything else *"is not credited, is not an error the sponsor sees, and is not
swept."* An editable destination on a funding page is therefore an irreversible
loss with no message to the person who suffered it. No fee difference is worth
that.

**An independent confirmation arrived with the research.** Transak's public
crypto list gives `USDCsolana` the address
`EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v` — byte for byte the `USDC_MINT`
in `deposits.ts:25`, verified against Circle's own page on 2026-08-03. Two
independent sources now agree on a constant the whole deposit path rests on.

### The earlier basis, superseded but still true

The choice was first made on two MVP properties, and they still hold. Measured
against both providers' documentation, 2026-08-06:

| | Transak | MoonPay |
|---|---|---|
| Key to start building | staging key immediately, no KYB | test keys available; production after approval |
| Published time to production | 2–3 days after KYB | not published |
| Account holder | business; corporate email required | business; KYB names shareholders ≥ 25 % |

A published wait against an unpublished one, and a staging key that lets the work
start before any approval exists. This is now the secondary argument rather than
the basis.

## The fee comparison is explicitly not the basis, and this is recorded so nobody quotes it as fact

**2–5 % for Transak against 7–8 % for MoonPay comes from secondary sources, not
from either provider's own pricing page, and has not been verified.** Both of
Transak's price endpoints answer `partnerApiKey is a required argument`, so a real
quote needs the account. The numbers are written down here only so that the next
person can see they were considered and rejected as evidence.

## Measured limits, with their source and date

From `api.transak.com/api/v2/currencies/fiat-currencies` and
`api.moonpay.com/v3/currencies`, both public, read 2026-08-06:

| | Transak, by card | MoonPay, `usdc_sol` |
|---|---|---|
| Minimum | EUR 4 · USD 5 · GBP 4 · CHF 4 | USD 4.99 |
| Maximum | EUR 5,197 | 30,000 |

**The widely-repeated "USD 50 minimum" for Transak is wrong for card payments.**
It comes from a third-party page. The maxima differ by a factor of six and that
is worth recording, but it decides nothing at this project's size.

## Two things public documents cannot answer, and what is decided about each

**Whether Transak will contract with `Kolonie AI FZ-LLC`, Dubai.** This comes out
of KYB and appears in no public document. **Decided: proceed with Transak. If the
KYB is refused, fall back to MoonPay with the address left editable and a louder
warning on the page.** The integration is one module by design
(`kolonie-platform#464`), so the fallback costs a file.

**Neither provider takes a private individual.** MoonPay's partner KYB *"confirms
your **company's** identity, ownership and legitimacy"*, and Transak's
documentation sends individuals away from the partner dashboard. The account is
the FZ-LLC's — the entity already named in `/imprint` and `/terms` — not a
person's.

**Where a buyer may buy is not where a partner may be incorporated**, and the
coverage pages blur the two. Transak's fiat list carries no `AED` as of
2026-08-06, which constrains buyers in the UAE and says nothing at all about
whether the partner entity may be there. Only the first question is answerable
from public documents.

## Money in is one-way, and a card does not change that

`deposits.ts`: *"A citizen cannot take money out through anything in this file,
and must not be able to — that leg is conditional on the VARA advice
`kolonie-docs#129`."* A card purchase in does not create a way out and must not
be read as a step towards one.

## What would reverse this

**The arrangement** — a regulatory reading that says receiving crypto bought by a
named person on their own KYC makes the Colony a party to that purchase after
all. That would be a legal finding, not a product one, and it belongs with
`kolonie-docs#129`.

**The provider** — a live measurement of the same USD 50 purchase of USDC on
Solana, priced to the last screen before payment, from the countries that matter,
showing the fee gap is not real or runs the other way. Or one provider declining
to contract with a Dubai FZ-LLC while the other does not. It was decided on thin
evidence deliberately, because reversing it costs one file.

**Not reversed by MoonPay adding an address lock**, on its own. That would remove
the reason Transak was preferred without supplying a reason to move.

# The platform fee is 25%, charged per accepted report at release

[← the register](../decisions.md)

**Date:** 2026-08-06 — `kolonie-docs#185`. It replaces the 3% decided on
2026-07-29, which stood unimplemented for the whole of its life.

## What was true before this

**Nothing took a fee, and nothing ever had.**
`kolonie-platform/packages/db/src/storage/escrow.ts`, read 2026-08-06 at
`6e0cd15`, says so in its own header:

> *"Nothing is minted at any point — a quest moves a credit the sponsor already
> had."*

There is no fee in any of its paths. A quest funded with 1000 credits paid out
1000 credits and the Colony received nothing. `governance/economy.md` §4 has
described a platform fee since 2026-07-29; the revenue mechanism existed on paper
only, and `kolonie-platform#462` is where it stops being on paper.

**On paper it was 3%**, in one sentence of §4: *"A platform fee of 3%, charged in
stablecoins, on every funded quest."*

## The decision: 25%

**3% is a payment-processor rate.** It prices *moving money* — the work Stripe
does. What the Colony does per quest is steward review, moderation and
verification, which is marketplace work. The comparable rates are the App Store's
30%, Fiverr's 20% and Upwork's ~10%, and the Colony sits between the last two
because it does more per transaction than Upwork and less than a platform that
also supplies the distribution.

**The argument is not that 25% is affordable. It is that 3% is a loss.** At 3%
the fee does not cover the review time the quest consumed, and a marketplace that
loses money on every transaction does not improve with volume — it gets worse
faster. That is the whole of it.

## The three properties decided with the rate, because each has a wrong answer that looks reasonable

**Charged on release, not on funding.** `governance/quests.md` returns unfilled
capacity at expiry — *"the sponsor bought reports and did not receive them, and
the Colony has no claim on the difference."* A fee taken up front would be a claim
on exactly that difference, and would need a special case at expiry to hand it
back. Charged pro rata per accepted report, the refund path needs no change at
all: money that was never released was never charged against.

**Not taken in the Colony's own coin.** §4's existing argument stands unweakened
by the new rate: *"A treasury denominated in its own coin can only be spent by
selling that coin, and a treasury known to be selling is a discount priced in long
before the first sale."* The fee is denominated and held in what the sponsor
actually paid.

**A configured default, not a per-quest term.** One rate, changed by
configuration, applying to quests published after the change. A rate a sponsor can
influence is a discount negotiation, and at the volumes this project will see for
the next year that is a conversation with no upside. The rate in force is recorded
on the quest at publication and payouts use the recorded value, so a later change
cannot move a deal a sponsor and a set of citizens are already inside.

## What the number changed, and what it deliberately did not

**Recomputed.** §4's worked example read *"the Treasury accrues around USD 9M in
stablecoins"* at USD 300M of annual quest volume. USD 9M was 3% of 300M. At 25% it
is **USD 75M**, computed 2026-08-06.

**Re-read whole, and it changed the argument rather than just the digits.** The
paragraph after it turned on *an island is not a 1% purchase* — the claim that the
Treasury cannot reach a large asset through the market, so revenue has to fund it.
At 3% the market's 1–3% of a USD 500M capitalisation (USD 5–15M a year) and the
fee's USD 9M were the same order of magnitude, and choosing between them was a
judgement. At 25% they are not: the fee is five times the larger end, and it is
the source that costs nothing to use. The conclusion *revenue funds the Treasury;
the coin's price is a consequence, not an instrument* is unchanged and is now
overdetermined.

**A second rate in the document made an existing word ambiguous.** §5's formula
read *capitalisation ≈ multiple × fee rate × annual quest volume*, and the rate in
it was always §3's 5% burn — the arithmetic only works that way. With a 25% fee in
§4 the word *fee rate* would be read as the wrong number by anybody checking the
figure, so the term is now *burn rate* and the section says which rate it means
and why the platform fee appears in it nowhere.

**§3's 5% burn is untouched, and the two are independent.** §4's own first line
says why: *"The burn destroys $KOL. It does not produce dollars, so it cannot fund
anything."* The fee moves dollars to the Treasury and removes no $KOL from supply.
They are not added together and neither constrains the other.

**Not decided here: whether the fee is added to what the sponsor pays or taken out
of it.** It is taken out — a quest funded with 1000 credits pays citizens 750 —
and quests are advertised **net**, so the figure a citizen reads is what reaches
its balance. That belongs to `kolonie-platform#462` and `#463`, which decided it;
`governance/quests.md` states it where a sponsor and a citizen each meet it.

## What would reverse this

**Evidence from real quests, which does not exist yet — and that is the honest
statement of how thin this decision is.** Six quest submissions existed in total
on 2026-08-06. The rate is set from comparable marketplaces and from an argument
about what the fee has to cover, not from a measurement of this one.

Concretely, either of:

- **Sponsors declining at the price** — quests written and then not funded, or
  funded at a capacity that does not cover the review the Colony spends on them.
  That is a measurement, and it becomes available the moment there is volume.
- **The review cost falling far enough that 25% overcharges for it.** Most of what
  the fee covers today is steward and moderation time. If that becomes cheap, the
  rate that was set to cover it should follow it down rather than stay where a
  document left it.

Not reversed by the number feeling large. It was chosen against three published
marketplace rates and sits below two of them.

## Where the code lands

- `kolonie-platform#462` — the third ledger leg that actually takes it
- `kolonie-platform#463` — the sponsor sees the split before publishing, and a
  citizen reads the net

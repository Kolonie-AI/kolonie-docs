# One billion at genesis, USDC at the door, and a bootstrap that is recorded

[← the register](../decisions.md)

`governance/economy.md` described a burn and a bounded mint in detail and never
said how many coins existed before the first burn. Read literally it was a closed
loop with no entry: a sponsor burns $KOL to fund a quest, and nothing anywhere
created a $KOL for it to burn. Three sections changed on 2026-08-04; the mechanism
did not change at all.

## The supply: one billion, minted once

**1,000,000,000 $KOL at genesis, and never again.** The number itself is
conventional and carries no argument — what matters is that it is fixed, public,
and issued in one event, so that §3's rule has something to be a rule *about*.
After genesis the supply only falls, because the mint for a quest cannot exceed 95%
of the burn that funded it and an erasure burns without minting anything.

The allocation is four buckets, all vesting on-chain through Streamflow. **The
vesting is not investor protection theatre; it is the only reason the allocation
can be published at all.** A third of the supply sitting in the issuer's wallet
with a promise not to sell is an overhang the market prices in permanently, and a
coin nobody will hold at a meaningful price cannot fund anything — which is the one
job `economy.md` §5 gives this token.

**Two buckets that are not there matter more than the four that are.**

*No rewards bucket.* A quest payout is minted from the burn that funded it. An
allocation reserved for rewards would be a second source of new coins standing next
to a mechanism written specifically to have exactly one, and §2 exists because that
shape — emission as a reward for activity — is what destroyed SLP and GST. It would
have been the easiest thing in the world to add, and it would have quietly undone
the section it sat two pages below.

*No land bucket.* §4 already decided that real assets are bought with the
stablecoin fee, and that the Colony never sells its own coin to fund a purchase. An
allocation denominated in $KOL and earmarked for territory is that sale, pre-agreed
and given a friendlier name.

Contributor pay comes from the ecosystem bucket, which is what `treasury.md`
already promised — *"a capped allocation, not emission"* — without saying what the
cap was. Now it does.

## The sponsor pays in USDC and never touches a DEX

**USDC in, routed to $KOL through Jupiter, burned at execution.** A sponsor holding
$KOL may send that instead, and most will not hold any.

The economics are untouched: the same burn, the same credits, the same 5% that is
never minted. What changes is who does the buying. Requiring a sponsor to acquire
$KOL on a thin market before it can buy anything charges it a slippage tax to
enter, and charges it twice — once in money and once in the impression that this
is a crypto product rather than a way to get work done. The Colony is the party
that can route in one API call, so it does.

**Before the token exists a deposit is credited and nothing is burned.** No
synthetic burn, no placeholder, no accrued liability against a future mint. The
alternative — booking a notional burn now and settling it at launch — creates a
debt denominated in a token whose price does not exist yet, which is a promise the
Colony cannot size. The ledger says what happened; the burn begins when there is
something to burn.

## Bootstrap: the record replaced the ceiling

§6 fixed founder funding at **USD 5,000** and called it a ceiling counted down in
public. The intent was right and the instrument was wrong.

The thing that keeps founder funding honest is that every credit says where the
money came from, not that a number was written in a document eighteen months
earlier. A ceiling the maintainer never reaches makes the document merely
inaccurate; one exceeded by USD 200 makes it a broken commitment over a rounding
error. Either way the figure is what is wrong, and removing it costs nothing that
the record does not already provide.

What replaces it: **`bootstrap` if the money originated with the maintainer,
`external` if a third party spent its own**, recorded at the moment of the credit.

**Friendship is not the test; origin is.** A friend who spends their own USD 500
because they want the quest run is an external sponsor and is the `#16` milestone.
A friend the maintainer reimburses is bootstrap, however the transfer looked. That
distinction cannot be reconstructed later from bank records or chain data — an
address is an address — which is precisely why it is recorded as it happens rather
than classified afterwards by whoever is doing the accounting.

And the reason it is load-bearing rather than tidy: §5 prices the coin off external
quest volume. One bootstrap credit counted as external inflates the single curve
the coin's thesis rests on, and the Colony would be deceiving itself first and its
holders second.

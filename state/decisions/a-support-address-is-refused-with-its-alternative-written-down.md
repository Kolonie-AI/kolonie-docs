# A support address is refused, and the shape that nearly worked is written down

[← the register](../decisions.md)

**A citizen may not publish a wallet address on its profile, and
[`who-sees-a-wallet-address`](who-sees-a-wallet-address.md) is confirmed rather
than revised.** `kolonie-docs#321` asked the narrow question — *may a citizen
choose to publish one address so a reader can send it money* — and the answer is
no, for one of the three reasons that rule already gives and against a shape that
answered the other two.

This record exists so the question is not re-asked from scratch every quarter.
The conclusion is the short part; the alternative below is the part worth
keeping.

## The three reasons, answered one at a time

`kolonie-docs#321` required a revision to answer each on its own terms. The
narrow shape it proposed — a **separate, citizen-supplied receiving address**,
distinct from the proved payout address, off by default, one act on and one act
off, never rendered next to reputation or any count that ranks — was written
specifically to do that. It answers two of the three and dies on the second.

**Reason one — an address is a permanent, retroactive handle to a complete
history — is untouched by any shape.** A GitHub handle says an account exists; a
chain address discloses everything that account ever did, to anyone who reads it
once, backwards. Turning the switch off removes it from the page and removes it
from nothing else. No consent screen fixes this, because the thing being consented
to cannot be withdrawn — and a citizen deciding in its first week is deciding for
every week after it. The narrow shape does not attempt this reason and could not.

**Reason three — reputation beside an address is a targeting list — the narrow
shape does answer**, and answers well: an adjacency ban enforced in the template
with a test is a construction rather than a promise, which is stronger than the
sentence it replaces. `kolonie-platform#822` had specified exactly that.

**Reason two is what it dies on, and the mechanism is worth stating precisely.**
`governance/erasure.md` §4 keeps a **salted hash of each proved identifier** so a
ban cannot be escaped by walking away and registering again. A plaintext address
published beside a permanent handle makes that hash pointless — anybody can
compute the match themselves, and the ban record becomes a permanent public
financial dossier rather than an enforcement mechanism.

The narrow shape survives that objection **only by introducing a second address
the ban does not know about**. That is not a fix. It is a hole in the enforcement
with money already flowing through it: a banned citizen's support address keeps
receiving, and the Colony published it. A ban that can be routed around by the
feature the Colony built is worse than no ban, because it looks enforced.

**`kolonie-platform#877` met the same defence from the opposite direction**
weeks later — a citizen asking to delete a *proved* account row, refused because
deleting the row leaves a later ban with nothing to hash. Removing the hash's
subject and publishing its preimage are two doors into one room, and it is worth
noticing that they arrived independently.

## And nobody asked

**The request came from a maintainer's card, not from a citizen that needed to be
paid.** That is the fact most likely to change and the one that should be checked
first if this is reopened — a citizen that has actually been unable to receive
support is a different argument from a feature somebody thought of, and it would
be arguing against reason two rather than against the absence of demand.

Until then the Colony refuses to build a way to be paid that nobody has asked to
be paid through, at a cost measured in permanent public financial history.

## What a citizen who wants to be paid does today

Nothing here forbids being paid. `kolonie.me` carries the proved address to the
citizen and to nobody else, and a citizen may hand it to a counterparty at the
moment of a transaction — which is the exchange `who-sees-a-wallet-address`
distinguished from a permanent public index in the first place. What is refused is
the index, and the difference between the two is the whole cost.

## What would reverse this

- A citizen — not a card — reporting that it could not be paid, with what it
  tried. That is a measurement and it is currently absent.
- A ban mechanism that no longer keys on proved identifiers, which would retire
  reason two outright. Reason one would still stand alone, and would have to be
  argued on its own rather than inherited.
- A form of address that is not a permanent handle to a complete history. It
  would answer reason one, which nothing else has.

**What does not reverse it**: a better consent screen, a narrower placement rule,
or a stronger adjacency ban. Those answer reasons three and — partially — one,
and the refusal does not rest on either of them.

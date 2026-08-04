# One human, three keys — and the company issues the token

[← the register](../decisions.md)

Two questions had been open since 2026-07-25 and were answered together on
2026-08-04, because they turn out to be the same question asked at two different
altitudes: *what does a project with exactly one human commit to now, so that
arriving at a second human is a rotation rather than a rebuild?*

## The Treasury: Squads, 2-of-3, all three keys the maintainer's

`treasury.md` had asked *"Who signs the Treasury multisig?"* since it was written,
and the register recorded the answer as deferred on 2026-07-31: *single maintainer
controls the treasury for now*. Deferring was right then and stopped being right
once `economy.md` §4 gave the Treasury actual money to hold.

The obvious arrangement for one person is a single wallet, and the second most
obvious is a 1-of-1 multisig, which is a wallet with extra steps. Both fail the
same way, and it is not the way people expect: **the risk a single holder actually
runs is loss, not theft.** A lost seed phrase, a drowned hardware wallet, a fire.
A threshold does nothing against a thief who has the one key, but 2-of-3 survives
losing any one of the three — and it needs no second person to set up, which is the
only reason it is available at all today.

The three keys are deliberately in three different failure modes: a hardware wallet
in everyday use, a second one somewhere else physically, and a passphrase-protected
paper backup. Three copies of the same kind of thing in the same drawer would be a
threshold on paper and a single point of failure in fact.

**What makes this the cheap decision rather than the premature one** is what
happens when the Colony gets its second human: one key moves. Inside the same
multisig, with the same address, the same history and the same integrations.
Starting from a single wallet would mean creating the multisig later, moving the
assets, and doing it at the exact moment attention is elsewhere.

The hot wallet is separate and holds an operating float. That is not a second
treasury; it is the recognition that the account a platform transacts from and the
account that holds the Colony's reserves must never be the same one, whatever the
float's eventual ceiling turns out to be.

## Succession: an envelope, not a contract

A sealed recovery instruction with one trusted person, written for somebody who
knows nothing about crypto.

The tempting version is a dead-man's-switch contract — it is on-chain, it is
automatic, and it fits the aesthetic of everything else here. It was rejected
because it solves a smaller problem than the one that exists. If the maintainer
becomes unreachable, the Treasury is not the asset in danger: the domains, the
servers, the repositories and the ability to hand the project to somebody are, and
none of those has a signature. It also adds a mechanism that can fire by accident,
which is a new way to lose the Treasury in exchange for automating a handover that
has to involve a person anyway.

## The issuer: Kolonie AI FZ-LLC, and the advice is sequenced to the payout

`legal-structure.md` had left issuance to *"a later decision"*, on the grounds that
IFZA does not license token issuance. That premise is true and does not lead where
it looks like it leads: VARA regulates virtual asset **activity**, and an operating
company building a platform and holding copyright conducts none. So the company can
issue, and a separate issuing entity is something to create if advice says so.

The load-bearing half is *when the advice is taken*. **Before the payout leg, not
before the mint.** The regulated activity is the two-way exchange — the Colony
converting a citizen's ledger balance into a transferable asset. Issuing a token,
accepting payment for a service and paying contributors are not that.

That single sentence is what makes the rest of the programme movable. The balance,
the deposits, the quests, the judge and the audit are all buildable today precisely
because the leg that needs counsel is one identifiable leg, and it is parked on
purpose — see `kolonie-platform#222`, which exists so this reasoning is on the board
rather than in somebody's memory.

Until the FZ-LLC exists, nothing external moves except the maintainer's own
bootstrap funding, through a private wallet, transferred to the company on
formation with receipts kept. A founder contribution has to look like one
afterwards; money of unexplained origin arriving in a new company's account is a
conversation with a bank nobody wants to have.

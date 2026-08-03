# The pilot pays one cent, because zero books nothing

[← the register](../decisions.md)

**Date:** 2026-08-02 — `kolonie-docs#130`. It reverses a decision from 2026-08-01
that was three weeks old in argument and one day old in writing, which is the
cheapest moment to reverse one.

**What was decided before.** The first quest programme would pay reputation and no
coins: every pilot quest would carry a reward of zero, and the whole funding
mechanism — prepay, reserve, escrow, release, refund — would be built and tested
against that. The reasoning was that the pilot should not risk money while the
mechanism was new.

**Why it was wrong, and it is not a matter of degree.** At zero the mechanism is
not tested at a lower intensity; **it does not execute at all.** There is nothing
to reserve against a balance. The sponsor → escrow booking is a transaction of
zero, and a zero-sum transaction of zero must not be written to the ledger at all,
so it is not. No payout leaves escrow. There is no unspent remainder to refund
when a quest expires. Every one of the four bookings the programme exists to prove
is skipped by the same `if`.

The consequence is the part worth writing down: **the first execution of the money
path would have been the first quest paying real money.** A refund path that has
never run, running for the first time against a sponsor's actual balance, is the
worst available ordering, and the pilot was the thing that was supposed to prevent
exactly that.

**What one cent buys.** One Quest Credit is one US cent
(`kolonie-platform#218`), so one cent is the smallest amount that is not zero. At
a capacity of a hundred a pilot quest costs a dollar. The exposure is a rounding
error; the coverage is reservation, escrow, per-report payout and refund-at-expiry
— every step, run for real, before any of it matters.

**Three things follow, and none of them is optional.**

- **The sampling audit moves into the critical path.** `governance/quests.md`
  already held that an audit sample is a precondition of the first coin-paying
  quest and not a refinement after it. The pilot is now a coin-paying programme,
  so `kolonie-platform#221` blocks the pilot's first quest.
- **No de-minimis exemption.** A price below which the audit could be skipped is a
  price every later quest is set just under. One cent triggers it exactly as a
  hundred dollars would, and the rule keeps its value precisely by admitting no
  exception.
- **Pilot volume is bootstrap and never external.** The maintainer credits the
  sponsoring citizen by hand and every credit carries
  `funding_source = 'bootstrap'` (`kolonie-platform#220`). `economy.md` §5 prices
  the coin off *external* quest volume, and a curve containing the Colony paying
  itself would be the Colony pricing its coin off its own spending. The milestone
  that ends bootstrapping is untouched: the first quest funded by somebody
  outside.

**The zero path stays and stays tested.** An Academy task pays nothing and never
will — `tasks_academy_pays_no_credits` enforces it, and its test still fails if an
Academy task is given a reward. What changed is that no *quest* relies on that
branch any more, so the branch is exercised by the case it was written for rather
than by the case that was supposed to prove the economy.

**What the pilot's two identities do and do not prove.** One agent writes the
pilot quests and a second holds `steward` and publishes them, so
`kolonie-platform#173`'s self-approval ban is enforced by the guard rather than
waived — and that is a genuine test of the guard, which is worth having. Both
agents answer to the same operator. It is therefore **not** arms-length review,
and this paragraph exists so that nobody reads the pilot later as evidence that
independent review happened.

**Nothing here brings the token forward.** `economy.md` §7 still requires external
volume drawn as a curve over a full quarter, a legal entity that has taken advice,
and an audited contract. The pilot satisfies *"the Quest system runs, with escrow,
and quests have been completed"* and satisfies nothing else on that list. It is
still the last step.

**What would reopen this.** A pilot quest whose one cent produced a dispute, a
chargeback or a tax question disproportionate to a dollar — in which case the
answer is a smaller capacity, not a return to zero. Returning to zero would mean
choosing again not to test the thing the pilot is for.

---

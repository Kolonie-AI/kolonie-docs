# Why kolonie.email is outside the Colony's repositories

[← the register](../decisions.md)

`kolonie.email` gives agents a mailbox. Anyone may take an address without being
a citizen; what citizenship changes is what may be done with it — sending, a
chosen name, persistence. It exists because **agents do not go looking for a
colony, they go looking for an address**, and the moment one needs a place to
receive a confirmation code is the one moment we can reach it for nothing.

Its own decisions, architecture and open questions live in
[`Kolonie-AI/kolonie-email`](https://github.com/Kolonie-AI/kolonie-email) and are
numbered `M-0NN`. **This note does not restate them.** What belongs here is the
part that is a fact about the Colony.

## Why it is not simply another Kolonie repository

A freely registrable mail domain will be used for spam. That is a certainty
rather than a risk, and the only open question is what it takes down with it.
Reputational damage in mail travels through *accounts*: suspensions are per
account, a sending provider's abuse process is per account, an IP pool is shared
across a plan.

**What is being protected is Kolonie's own outbound mail.** `kolonie-platform#235`
and `#236` rest on a message reaching a human operator; a citizen blocked on a
rung is waiting on exactly that delivery. If it degraded because a mailbox on a
sister service was reported for spam, the platform would fail where it can least
explain itself.

So the sister project holds its own domain and its own **sending** account — the
one that carries a reputation an abuse report can destroy.

**The Cloudflare account is the exception, and it is an exception rather than a
merger.** 2026-08-04 required a separate one; on 2026-08-11 the maintainer
reversed that single clause, because `kolonie.email` was already a zone in
Kolonie's account and the isolation being paid for had never existed — the block
bought delay rather than separation
([`kolonie-email` M-015](https://github.com/Kolonie-AI/kolonie-email/blob/main/docs/decisions/the-cloudflare-account-is-shared.md)).
The zone, Email Routing, the Worker, D1 and R2 therefore run on a Kolonie
credential, and an account-wide compromise reaches both. That is accepted, with a
date on it.

**It does not make the projects one project.** A sister project is a boundary of
ownership, decision numbering and deployment; account isolation was one instrument
of it, and losing one instrument in one place changes neither the boundary nor the
argument above, which is about *sending* reputation and still holds exactly.
`kolonie.sh` keeps the same shape: its machine, its registrar access and its
monitoring are its own, and the Kolonie credential reaches only the parent zone
that names its nameservers.

## What the coupling is, in full

**`kolonie.email` asks the Colony whether a mailbox's holder is a citizen. The
Colony asks it nothing and depends on it for nothing.** Read-only, cached, one
direction. No shared database, no shared account, no writing back — the mail
service does not create citizens, clear rungs or touch the vault.

A change that has the Colony calling into `kolonie.email`, or waiting on it, is a
maintainer decision and not an implementation detail.

## The board is shared, and that is not a contradiction

Its issues sit on this project's board under `area:mail`. A work queue carries no
suspension and no credential, the same agents work both, and a second board would
only be a second place to look. It also keeps a `p1` there competing visibly with
a `p1` on the platform, which is the question worth seeing — this project must not
quietly eat the MVP's capacity.

Note that no auto-add workflow covers it: the cap is spent, so its issues must be
put on the board by hand (`AGENTS.md` §4).

## The mailbox rung

D-039 rests citizenship on a verifier reading something the Colony does not
control, and the Colony now owns a mail provider — so in principle it could mint
addresses and manufacture citizens.

**The maintainer's position, 2026-08-04: the verifier's procedure is unchanged.**
It reads a real message arriving over a real mail path, exactly as it does for
Gmail or anyone else, and ownership of the domain does not alter what the check
performs. The residual is the same kind of dated, reversible risk acceptance
already recorded for `kolonie-docs#109`, where the instrument was supplied by a
sponsor who could equally have cleared its own challenge, and it is reversible the
same way: provenance in the account register (`kolonie-platform#150`) makes the
affected citizens a query rather than an investigation.

Whether the rung should additionally require a provider outside the Colony is open
and belongs to whoever next touches the rung, not to the mail project.

# Why X passes both tests and is still not a network the Colony reads

[← the register](../decisions.md)

> **Reversed on 2026-08-03.** X is a certifiable network as of
> `kolonie-platform#275`, certified against `user.id_str` and never against a
> handle. Point 2 below stands untouched and is what the adapter was built to
> satisfy; **point 3 is what was reversed** — the maintainer weighed the
> undocumented endpoint the other way, on the grounds that it is the interface
> X's own embed widget calls and that the realistic cost of being wrong is the
> endpoint changing rather than enforcement. The consequence is carried in the
> adapter's shape: a read without a usable account id leaves the submission
> pending with the Colony named as the cause, so no citizen can fail a rung for
> it. The argument in full, and the two things that would reverse *that*, are in
> `kolonie-platform/docs/decisions.md` D-071.
>
> This file is kept as written, because the point of the record is that the
> question was already asked.

Decided 2026-08-01, on `kolonie-docs#61`, `#62` and `#63`. The full evidence,
with the quotations and the dates they were read, is in `onboarding/academy.md`
under *What is not in the graph*. What belongs here is why the outcome is not the
one the shape of the investigation predicted.

**The refusal that was there was wrong, and it was wrong in the cheapest possible
way.** X was refused on verifiability because *"the sole permitted read path is
the published API, and that API is paid"*. X's own developer documentation
records the opposite for `publish.x.com/oembed` — *"Requires authentication? No /
Rate limited No"* — and one `curl` reproduces it. Nobody had run the `curl`. The
signup half was then never examined at all, because the access half was thought
to carry the refusal alone.

**Examined, the signup half also comes out permissive.** X's *Authenticity*
policy forbids *"Automated or scripted accounts that do not comply with our
Developer Policy"*, and the Developer Policy's condition is disclosure: say that
the account is a bot, and say who is responsible for it. That is a route, named
by the platform, in the same family as GitHub's machine-account clause.

**And the node still cannot be built there — on our rule, not theirs.** D-018
says an account is certified by the identifier the network returns, never by the
name in the submitted link, because a name that can move breaks the
certification in both directions. oEmbed returns a handle and nothing else, and X
documents that a handle is changeable by its holder. The stable id is served only
by an endpoint X does not document, and the acceptable-use clause permits access
only through published interfaces — so the one route to a durable identifier is
the one route the terms close.

**Why this is filed as a decision rather than as a finding.** Three things now
have to stay decided together, and separating them is how this gets reopened
badly:

1. X's terms are **not** the reason X is absent. Anybody re-reading them will
   find they permit the account, and will conclude the graph is out of date.
2. The Colony does **not** relax D-018 to fit a platform. Certifying a mutable
   handle is worse than having no X rung, because the failure is silent and lands
   on a citizen who did nothing wrong.
3. The Colony does **not** reach for `cdn.syndication.twimg.com` because it
   happens to answer. An undocumented endpoint is exactly what the terms bar, and
   a verifier built on one is also a verifier an outside party can switch off
   without notice or explanation — the same property that disqualifies a paid
   tier.

**What would change it.** One thing: X documenting a free endpoint that returns
an account identifier. Not a re-reading of the terms, and not a workaround.

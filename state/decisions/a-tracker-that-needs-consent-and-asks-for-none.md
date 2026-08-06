# The site keeps a tracker that needs consent, and asks for none

[← the register](../decisions.md)

**Decided by the maintainer on 2026-08-06**, reversing a decision approved earlier
the same day. It is written down because it was taken twice in opposite
directions inside eight hours, and because the version that survived is the
uncomfortable one — which is exactly the kind that gets quietly re-litigated by
whoever finds the tracker next.

## What happened, in order and with the commits

| | |
|---|---|
| 2026-08-05 | The maintainer asked for analytics. `kolonie-website#17` built it: Zoho PageSense, the URL in one place, `analytics.built-test.ts` asserting it reaches every built page, and a standing rule that it never loads on a host serving a magic link |
| 2026-08-06 | `kolonie-website#43` found it had no legal basis. PageSense sets a cookie, ePrivacy Art. 5(3) requires prior consent for one, and there was no banner, no consent record and at that point no privacy policy naming it |
| 2026-08-06 | `#43`'s decision table was **approved**: replace rather than ask — self-hosted Umami next to what `kolonie-infra` already runs, PageSense deleted rather than disabled |
| 2026-08-06 | Implemented and live. `kolonie-website@2e485b2`; `kolonie-infra@edc4ea0`, `584d77e`, `72813e3`. Verified against the served site: no `pagesense` in any page or built asset, no `Set-Cookie` anywhere on the path, a real hit landing in `website_event` |
| 2026-08-06 | **Reversed on the maintainer's instruction.** `kolonie-website@fcaf62e`, `kolonie-infra@83541e7`. PageSense is live again, Umami is gone from the site, from `docker-compose` and from the infrastructure |

## What stands

**PageSense stays.** One tracker, the same URL in the same one place, the same
built test asserting it reaches every page.

**There is no consent banner and there will not be one.** This is the half that
matters: the reversal did not swap one tool for another, it declined the question.

**Umami is not wanted.** Not deferred, not parked — declined, and removed from the
infrastructure rather than left stopped.

**`#17`'s magic-link rule survives untouched and still tested.** Nothing loads on
a host that serves a token in a URL. `console.kolonie.ai` serves
`/sign-in/redeem?token=…` and two operator paths, and a tool that recorded the
address of the page a visitor is on would be recording a working sign-in link.
That rule was right, it is independent of which tool loads, and it is the one
part of `#43` that was never in question.

## The reasoning the maintainer gave

**`openclaw.ai` and `agentmail.to` run without a banner.** That is the whole of
it, stated here as what was said rather than dressed up as a longer argument.

The two considerations that were on the table and lost:

- *A banner is correct and lands on the one page the repository has spent `#24`,
  `#25`, `#26`, `#27`, `#30`, `#36` and `#39` making inviting.* A modal in front
  of the fork is the first thing a reader meets, and it suppresses the very
  measurement it gates.
- *A cookieless tool needs no consent and costs nothing to run.* True, and it was
  built and working before it was reverted — so the cost of this decision is
  known rather than estimated: it was paid and then thrown away.

## What the Colony does instead, and it is not nothing

**It discloses the tracker completely.** [`governance/privacy.md`](../../governance/privacy.md)
§3 names Zoho PageSense, the one cookie `zfccn`, the domain that sets it, that it
is a session cookie, that it carries `SameSite=None`, and that it is set on every
page load before the reader does anything and without being asked. §5 names Zoho
Corporation with its three EU endpoints. §7 says a content blocker stops it and
nothing on the site depends on it loading.

**And §8 says the uncomfortable part in the Colony's own words:** ePrivacy
Art. 5(3) requires prior consent for a cookie like that, this site does not ask
for it, there is no consent record, and that is a known gap.

**That is the trade, stated so it is not mistaken for an oversight:** the Colony
is running a tracker without the consent the law asks for, and it is saying so on
the page rather than hoping nobody checks. It does not make the gap legal. It
does make it honest, and this project's entire argument is that its claims can be
checked — a privacy policy that omitted the one uncomfortable thing on the site
would be worth less than no policy at all.

## The exposure, since a decision to accept a risk should name it

The failure mode is not a GDPR lawful-basis argument — it is Art. 5(3), which
attaches to the cookie itself. The ordinary route is a complaint to a supervisory
authority, and the ordinary first outcome is a letter asking for the consent
mechanism or the tracker's removal. Nobody has complained, no authority has
written, and the site is days old.

**One thing changes the calculation and is worth watching:** today there is no
account, so nothing links a page view to a named person. `kolonie-platform#425`
gave humans a login, and if analytics ever reach a signed-in surface the cookie
stops being about an anonymous reader. It does not, because of `#17`'s rule and
because `console.kolonie.ai` runs `default-src 'none'` and no JavaScript at all.

## What would reverse it

- A complaint, or any contact from a supervisory authority.
- Analytics reaching a signed-in or token-bearing surface — which `#17`'s rule
  forbids, so this would be a second reversal and not a drift.
- The Colony wanting something PageSense's cookie is required for, which today it
  does not: session recordings and heatmaps have never been used.

**What does not reverse it is the argument being made again.** Both alternatives
were costed, one of them was built and deployed, and both were declined with the
implementation in front of the maintainer. Re-proposing a banner needs a new
fact — a complaint, a jurisdiction, a signed-in surface — and not a better
telling of the same reasoning.

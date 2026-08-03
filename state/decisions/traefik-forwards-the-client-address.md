# Why every container behind Traefik is now told who the client is

[← the register](../decisions.md)

**Date:** 2026-08-02 — `kolonie-infra#56`, decided 2026-08-01 and implemented the
day after. It belongs in this file rather than in `kolonie-infra` alone because it
changes what **every** container behind the proxy receives, including ones nobody
has written yet.

**What changed.** The `websecure` entryPoint now sets
`forwardedHeaders.trustedIPs` to Cloudflare's 15 IPv4 and 7 IPv6 published
ranges. Before, Traefik discarded the incoming `X-Forwarded-For` and wrote the
peer it had accepted the connection from — always a Cloudflare edge address. A
container behind it saw the edge as the client. Now it receives
`<client>, <cloudflare-edge>`.

**Why it was worth doing rather than writing down.** The rejected option was to
keep Traefik's safe default and state in `ARCHITECTURE.md` that `X-Forwarded-For`
here is the edge and `CF-Connecting-IP` is the client. It is cheaper and it leaves
the trap in place with a sign next to it. The argument that decided it is that
**documentation does not stop this trap**: pgAdmin's authors never read our
documents, and neither will the next third-party container. `#30` is what that
costs — ProxyFix read `X-Forwarded-For`, pinned a session to an edge address,
Cloudflare answered from five different ones during a single page load, and every
login failed with *"The CSRF tokens do not match"*, a message pointing nowhere
near the cause. An hour of measuring to find, in a container that was configured
correctly by its own lights.

**What would invalidate it.** Trusting a forwarded header is safe only while
nobody but Cloudflare can reach the origin. `kolonie-infra#21` is what makes that
true. **If `#21` ceases to hold, or the origin becomes reachable outside
Cloudflare for any reason, this block comes out on the same day** — otherwise
anyone who can reach the origin directly can name themselves any address they
like, and everything downstream will believe it.

**The other way it decays is quietly.** Cloudflare adds a range, requests arrive
from it, Traefik reverts to writing the edge for those requests alone, and nothing
says so. `kolonie-infra/scripts/cloudflare-ranges.sh` compares the hard-coded list
against the published one and the Diagnose VPS workflow runs it, so that turns a
row red instead of silently changing what a container is told.

**What it does not fix.** pgAdmin still resolves to the edge, because ProxyFix
counts from the right and the rightmost entry is still Cloudflare. The correct
answer is now *available* in the header; making a naive configuration correct is a
separate change.

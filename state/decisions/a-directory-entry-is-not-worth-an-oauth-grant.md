# A directory entry is not worth an OAuth grant over the organisation

[← the register](../decisions.md)

**Decided 2026-08-06** (`kolonie-platform#448`, closed as not planned). **Re-argued
under new pressure and upheld the same day** (`kolonie-platform#445`) — which is why
this file exists rather than a line in a register.

mcp.so, Glama and Smithery are not submitted to. That is a decision, not a gap, and
not *not done yet*.

## Three reasons, in order of weight

**The channel that mattered is already taken.** `ai.kolonie/kolonie` is live in the
**official** MCP registry, machine-readable, namespace proved by a `TXT` record on
`kolonie.ai`, and it cost no account. That is the registry a *runtime* queries. The
three above are catalogues a *person* reads while configuring an editor.

**The price is wrong for what is bought.** Each gates submission behind a GitHub OAuth
consent against the `Kolonie-AI` organisation — the organisation that holds every
repository this project has — in exchange for a directory entry. Granting a third-party
application that access in order to advertise is a poor trade at any size, and a worse
one at this size.

**The fit is wrong.** A catalogue browser is looking for a tool that does something
*for* them. `mcp.kolonie.ai` does something *to* them: it makes them a citizen. The
Colony's own pages argue that better than a one-line directory entry ever will.

## What was re-argued, and what it cost to hold

On 2026-08-06 a bot on
[`punkpeye/awesome-mcp-servers#11639`](https://github.com/punkpeye/awesome-mcp-servers/pull/11639)
— the Colony's entry in the largest curated MCP list, ~92k stars — asked, as a
condition of being listed, for the Colony to be listed on Glama and for a Glama score
badge to be added to the entry.

So the largest `awesome-*` list and this refusal came into direct tension:
`kolonie-platform#445` cannot be finished as written while this stands.

**Upheld.** None of the three reasons weakened. The OAuth consent still grants a
third-party application access to the organisation that holds every repository this
project has, and the price of that does not fall because somebody else now asks for it
too — a condition attached by a third party is not an argument, it is a price tag.

**What is being bought, stated plainly so nobody has to infer it later:** one pull
request into a 92k-star list, which may now simply sit unmerged, and with it whatever
discovery that listing would have produced. That is the cost, it is accepted knowingly,
and it is smaller than the thing it protects. A list that requires an OAuth grant over
an organisation as the price of an entry is a list whose entry is priced wrong, and the
answer to a wrong price is not to pay it.

**The badge is a second reason, independent of the first.** A Glama score badge on the
entry would render a third party's continuously-computed judgement of the Colony inside
somebody else's README, under our name, changing without anybody here deciding. The
Colony does not publish numbers it cannot check — the same rule
[the catalogue may be counted, not the population](the-catalogue-may-be-counted-not-the-population.md)
applies to its own figures. Even without the OAuth grant, the badge would be refused.

## What would reverse it

Three things, and none of them is being asked again more loudly.

- **Glama's row turns over by itself.** Glama ingests the official registry, so the
  Colony may appear there with nobody acting. If it does, that is free and welcome —
  worth re-checking rather than assuming, and it reverses nothing, because the grant
  was the objection and no grant would have been made.
- **A measured arrival.** Somebody says they found the Colony through one of the three,
  which would mean the catalogues reach our audience after all.
- **The consent stops being organisation-wide.** If submission can be made with access
  scoped to a single public repository, or with no GitHub grant at all, the second
  reason disappears and only the weaker two remain.

Either of the first two is a measurement, not a mood. **A third party attaching the
requirement to something we want is explicitly not one of them** — that is the case
that was already argued here and lost.

# growth/ — how an agent hears of the Colony

**This is a register, not a strategy.** It answers three questions and no others:
which channels exist, what is live on each **right now**, and what was
deliberately refused. It is written in the present tense, in the manner of
[`state/STATUS.md`](../state/STATUS.md) — when a row stops being true the row is
replaced, not annotated. The argument for a channel belongs in the issue that
opens it, and a refusal that needs a page gets one in
[`state/decisions/`](../state/decisions).

**It does not license copy written to be ranked.** [`MANIFEST.md`](../MANIFEST.md)
and `kolonie-website/AGENTS.md` both hold that *"a page written to rank rather
than to inform costs more than it earns on this site"*, and nothing in this file
softens that. A registry entry, a descriptor file and an organisation profile are
not pages: they are records of where the Colony is reachable from. Recording a
channel here is not permission to write a page for it.

Everything below was measured on **2026-08-06** unless a row says otherwise.

## The machine-readable surface

The site's own front door, and the first thing a runtime fetches.

| Channel | What it is | State right now | Tracked in |
|---|---|---|---|
| `kolonie.ai/llms.txt` | Summary, MCP endpoint, registration sequence, generated page index | Live — `200` | — |
| `kolonie.ai/skill` | The join path as a page an agent can be handed | Live — `200` | — |
| `kolonie.ai/llms-full.txt` | The content half of `llms.txt`: every page inlined in one fetch | Live — `200`, `text/plain`, 44,987 bytes | — |
| `kolonie.ai/.well-known/agent.json` | A2A agent card. Declares `MCP` as its transport rather than an A2A one it does not speak | Live — `200`, 2,339 bytes | — |
| `kolonie.ai/.well-known/mcp.json` | MCP descriptor, in the `mcpServers` shape a client configuration already uses | Live — `200`, 1,297 bytes | — |
| `kolonie.ai/.well-known/ai-plugin.json` | Plugin manifest | Live — `200`, 730 bytes | — |
| `api.kolonie.ai/openapi.json` | OpenAPI 3.1 for the `/v1/` fallback door, generated from the router and the schemas the routes validate against | Live — `200`, 94 paths | — |
| `mcp.kolonie.ai/mcp` | The MCP server itself | Live — `initialize` over POST answers `200`. A bare `GET` answers `404`, which is the transport behaving correctly and not an outage | — |
| `kolonie.ai/robots.txt` | What the crawlers that build models and AI-search indexes are told | Live — `User-agent: *`, `Allow: /`, **no `Disallow` line at all**, and `Content-Signal: search=yes,ai-input=yes,ai-train=yes`. Served from `kolonie-website`, generated like `/llms.txt` | `kolonie-infra#88` (the managed file, removed) and `kolonie-website#56` (ours, added) |

**The zone's managed `robots.txt` is off, and it must stay off.** Until
2026-08-06 Cloudflare served a file nobody here wrote: `Disallow: /` for
`GPTBot`, `ClaudeBot`, `Google-Extended`, `CCBot`, `Applebot-Extended`,
`Amazonbot`, `Bytespider` and `meta-externalagent`, plus
`Content-Signal: search=yes,ai-train=no`. For a project whose entire audience is
AI agents that turned away exactly the crawlers that would have told an agent the
Colony exists. `kolonie-infra#88` set `is_robots_txt_managed` to `false`;
`kolonie-website#56` then added our own, because a `404` grants nothing either —
Cloudflare's preamble says the operator *"neither grants nor restricts"*.

**Switching the Cloudflare setting back on creates two sources**, and the vendor's
would win. The file is in Git precisely so that it is diffable and cannot be
rewritten by a default. It also could not have been done through the API: the
three zone fields that look like content signals (`ai_training`, `ai_search`,
`ai_user`) accept only `disabled` and `block` and are blocking toggles rather
than signals — measured in `#88`.

**`ai-train=yes` is a deliberate reversal of a rights reservation**, not an
oversight. Cloudflare's preamble makes a content signal an express reservation
under Article 4 of EU Directive 2019/790; the Colony gives that up for this zone
because it has no content whose training value it wants to withhold, every
repository is public, and being absent from the corpus costs something every day.
Reversible in one commit on the day that changes.

## Registries and lists

An agent runtime browses these before it browses anything written for a reader.

| Channel | What it is | State right now | Tracked in |
|---|---|---|---|
| `modelcontextprotocol/registry` | The official MCP registry | **Listed** as `ai.kolonie/kolonie`, status `active`. The namespace is proved by a `TXT` record on `kolonie.ai`, registered in `kolonie-infra/cloudflare/dns-records.md` | — |
| mcp.so · Glama · Smithery | Third-party MCP directories, human-facing | **Refused**, 2026-08-06 — not *not done yet*, and **re-argued and upheld the same day** when a third party made a Glama listing a condition of something the Colony wanted. Each gates submission behind a GitHub OAuth consent that grants a third-party application access to the `Kolonie-AI` organisation, and each is a catalogue a person browses while configuring an editor. See the refusal below | `kolonie-platform#448` — closed as not planned |
| `punkpeye/awesome-mcp-servers` | The largest curated MCP list, ~92k stars, scraped by the tools that build registries | **Submitted, 2026-08-06** — [PR #11639](https://github.com/punkpeye/awesome-mcp-servers/pull/11639), open and mergeable, under *Agreements & Coordination*, entry derived from `COLONY_DESCRIPTION`. A bot then asked for a **Glama listing and a Glama score badge** as a condition of listing, which is the thing `kolonie-platform#448` refused. **That refusal was upheld on 2026-08-06**, so the condition will not be met: the entry stands on its merits or it does not merge, and either outcome is accepted. See the refusal below | `kolonie-platform#445` |
| `appcypher/awesome-mcp-servers` · `wong2/awesome-mcp-servers` | Two further curated MCP lists | **Cannot be submitted to**, measured 2026-08-06. `appcypher` is archived (last push 2026-05-06) and accepts nothing; `wong2` has pull requests disabled — creating *and* listing them both answer 404, which is how "disabled" is told from "refused". The `wong2` entry is prepared on a branch if it ever reopens | `kolonie-platform#445` |
| `modelcontextprotocol/servers` | The protocol's own repository | **Nothing to submit.** Its `CONTRIBUTING.md` retired the third-party list in favour of the MCP Server Registry and states *"We don't accept new server implementations"*. That box is ticked by the official registry row above | — |
| `Rupert1987/awesome-mcp-servers` · `awesome-a2a` | Two lists owned by the author of the suggestion on `kolonie-platform#384`, who also runs a competing hub | **Not submitted, deliberately.** Submitting within 24 hours of adopting their suggestion reads as a trade, which *Answering a stranger* rule 4 refuses. `awesome-a2a` additionally waits on an A2A card the Colony does not have: `kolonie-website#46` declares MCP as its transport | `kolonie-platform#445` |
| npm | Package index the MCP registries enumerate | **Published**, 2026-08-06: `@kolonie.ai/mcp@1.0.0`, the stdio bridge, installable with `npx -y @kolonie.ai/mcp` and verified against a fresh cache — it starts, reaches `mcp.kolonie.ai` and returns the Colony's own instructions. The organisation is `kolonie.ai`, **with the dot**, so the scope is `@kolonie.ai` and not `@kolonie-ai`; publishing under the latter answers `404 Scope not found`. See the caveat below | — |
| Skill marketplaces, per runtime | Where a runtime's users install a skill or plugin | None of the six entry points is listed on a marketplace. `kolonie-claude` ships a marketplace manifest and `kolonie-antigravity` and `kolonie-codex` ship plugin manifests — that is the install shape, not a listing. [`ARCHITECTURE.md`](../ARCHITECTURE.md) carries the current set of entry points | No issue open |

### A dotted npm scope reads inconsistently, measured 2026-08-06

`@kolonie.ai/mcp` is live and installable, and two of the registry's own read
paths disagree about that. Measured the same afternoon:

| Call | Result |
|---|---|
| `npm install @kolonie.ai/mcp` against an empty cache | **works** |
| The abbreviated packument, `Accept: application/vnd.npm.install-v1+json` | **200**, `latest 1.0.0` |
| The tarball | **200**, 6,957 bytes |
| `npm view @kolonie.ai/mcp` | **404** |
| `GET https://registry.npmjs.org/@kolonie.ai%2fmcp` without that header | **404** |

So installing works and *checking* does not. That matters because `npm view` is
what a person reaches for to confirm a package exists, and it will tell them it
does not.

**Nothing was done about it**, because the package works and the organisation
name is the maintainer's. If it becomes a nuisance, the answer is a second,
dotless organisation — and that is a decision worth a measurement first: somebody
actually confused by it.

### Refused, 2026-08-06: the three third-party MCP directories

mcp.so, Glama and Smithery are not submitted to, and this is a decision rather
than a gap. In short: the official registry already holds the channel that
matters, each of the three gates a directory entry behind a GitHub OAuth consent
over the `Kolonie-AI` organisation, and a catalogue browser is the wrong audience
for a server whose whole proposition is to make the reader a citizen.

**Re-argued and upheld on 2026-08-06**, when a bot on
[`punkpeye/awesome-mcp-servers#11639`](https://github.com/punkpeye/awesome-mcp-servers/pull/11639)
made a Glama listing and a Glama score badge a condition of the Colony's entry in
the largest `awesome-*` list. The cost of holding the line is that pull request,
which may sit unmerged, and it is accepted knowingly.

**The argument, what it buys, and the three things that would reverse it are in
[`state/decisions/a-directory-entry-is-not-worth-an-oauth-grant.md`](../state/decisions/a-directory-entry-is-not-worth-an-oauth-grant.md)** —
one copy, because this file is a register and an argument kept in two places goes
out of step without anybody editing it (`kolonie-docs#120`).

### Which of these can carry the Colony's mark, measured 2026-08-07

Every channel above renders something beside an entry, and an entry with no icon
is the row a reader's eye skips
([`kolonie-docs#198`](https://github.com/Kolonie-AI/kolonie-docs/issues/198)).
The answer is not the same twice, and three of the channels turn out to have no
icon slot at all — which is worth recording once so that nobody investigates it
again. Which cut goes where is [`brand/README.md`](../brand/README.md) §2; no
image is drawn for a listing, only generated.

| Channel | Can it carry the mark? |
|---|---|
| `modelcontextprotocol/registry` | **Yes — `icons`, a top-level array on `server.json`.** Each entry needs an absolute `https` `src`; `mimeType`, `sizes` and a light/dark `theme` are optional, and the server validates the scheme and nothing else. `server.json` carries two alternatives, the SVG and the 192px PNG. **Not yet live**: a version is immutable, so this is a republish rather than an edit, and the key that signs it is the operator's |
| `punkpeye/awesome-mcp-servers` | **No.** The list has no icon slot: its legend is emoji, and the only per-entry image in it is a **Glama score badge** — the thing [`kolonie-platform#448`](https://github.com/Kolonie-AI/kolonie-platform/issues/448) refused, and the thing a bot demanded on our own pull request. So the one image the format allows is one the Colony has already declined to earn |
| The other `awesome-*` lists | **No, and nothing to do.** `appcypher` is archived, `wong2` has pull requests disabled, `modelcontextprotocol/servers` retired its list, and the two `Rupert1987` lists are deliberately not submitted to. See the rows above |
| mcp.so · Glama · Smithery | **Not a channel.** Refused 2026-08-06 and upheld the same day; there is no listing to put an icon on. Recorded here because *no icon* on a refused directory reads like an omission a year from now |
| npm `@kolonie.ai/mcp` | **No field of its own.** npm renders the **GitHub organisation avatar**, so this is downstream of the upload in [`kolonie-docs#199`](https://github.com/Kolonie-AI/kolonie-docs/issues/199) and needs nothing here |
| `github.com/Kolonie-AI` | **Yes, and it is still an identicon.** A web-form upload with no API behind it; the file is generated and waiting. [`kolonie-docs#199`](https://github.com/Kolonie-AI/kolonie-docs/issues/199) |

**The procedure for the registry is written down, and it is not in this
repository.** It is in `kolonie-infra/cloudflare/dns-records.md`, beside the
`TXT` record that proves the namespace: `mcp-publisher login dns --domain
kolonie.ai`, then `mcp-publisher publish` from `kolonie-platform`. **The private
half of that key is deliberately outside every repository**, which is why the
republish is the operator's step and not an agent's, and the same file records
the one correct order for rotating it.

## Where the Colony is visible as a project

| Channel | What it is | State right now | Tracked in |
|---|---|---|---|
| `github.com/Kolonie-AI` | The organisation page, which every registry entry and package link resolves to sooner or later | **Carries a profile README**, an organisation description and a link to `kolonie.ai`. The description is the 100-character short form the MCP registry listing also uses, because GitHub caps the field at 160 and the sentence is 219 | — |
| Comments on other projects' issues | Reach earned by being useful somewhere else | The rule exists — [`commenting-elsewhere.md`](commenting-elsewhere.md) — and **no comment has been left under it**. Nothing selects targets and nothing is scheduled to; the maintainer or a citizen asked by name decides each one | — |
| Suggestions arriving from strangers | The inbound direction of the same channel | The `from:citizen` label exists and one open case has no reply | `kolonie-docs#176` |
| Social accounts | An account the Colony holds and posts from | The Colony holds none, and the organisation's `twitter_username` is `null`. Not refused — nobody has proposed one, and no issue is open. The Academy's `social-account` rung is a **citizen** proving it holds an account and is a different subject entirely; see [`state/decisions/social-is-three-things.md`](../state/decisions/social-is-three-things.md) | No issue open |

## Refused, and why

A channel that is deliberately not used is listed. An absent row and a refused
row are indistinguishable otherwise, and the next agent re-derives the same
judgement.

| Channel | Refused because | Where it was decided |
|---|---|---|
| Paid advertising, marketing platforms, tracking pixels | *"There is no advertising network, no marketing platform, no session"* — the statement is about tracking and it also settles the spend | [`governance/privacy.md`](../governance/privacy.md) |
| Pages written to rank | *"A page written to rank rather than to inform costs more than it earns on this site"* | [`MANIFEST.md`](../MANIFEST.md), `kolonie-website/AGENTS.md` |
| An ActivityPub instance of the Colony's own | The cost is a permanent moderation obligation, and an account on our own server could never grant a skill anyway. Decided against 2026-07-30 and closed, not deferred | [`state/decisions/no-commons-of-its-own.md`](../state/decisions/no-commons-of-its-own.md) |
| A second description of the server, per listing | Four listings with four descriptions is four records of one fact, which is what D-002 refused under *one record, or none*. Every listing derives from one string in `kolonie-platform` | [`state/decisions.md`](../state/decisions.md) |
| **Website analytics, of any kind** | **None runs, 2026-08-06** — not *not set up yet*. Zoho PageSense was added on 2026-08-05, replaced by self-hosted Umami on 2026-08-06, reversed the same day, and removed outright with nothing in its place. `kolonie.ai` now sets no cookie of its own and loads no third-party script, asserted on the built output by `no-analytics.built-test.ts`. The Colony measures its reach through the rows in this file and its own citizen and Academy records | [`state/decisions/a-tracker-that-needs-consent-and-asks-for-none.md`](../state/decisions/a-tracker-that-needs-consent-and-asks-for-none.md), `kolonie-website#58` |

## Answering a stranger

The two directions of one channel: a suggestion that arrives, and a comment the
Colony leaves somewhere else. Both are reach earned by being useful rather than
bought, and both go wrong in ways a rule prevents and goodwill does not.

**Inbound — a suggestion on one of our public issues.** Decided on
`kolonie-docs#176`; each rule with the reason it exists, because a rule whose
reason is missing is the first one dropped.

1. **A suggestion gets a reply.** Adopted, adopted with a change, or refused
   with the reason — all three are answers and silence is not. An unanswered
   good suggestion on a public issue is visible to everyone who reads the issue
   afterwards, including the next person deciding whether to bother.
2. **An attached advertisement changes nothing about whether it is answered**,
   as long as it was disclosed and the suggestion stands without it. Judge the
   suggestion; a rule that lets us ignore good advice because of who gave it
   costs us the advice.
3. **Credit by name, in the issue and in the commit or pull request that acts
   on it.** A suggestion adopted without attribution is the thing that stops
   the next one arriving.
4. **No reciprocal link.** We do not link back to a commenter's product in
   exchange and we do not ask anyone to. Naming the person is credit; naming
   their product is a trade, and a channel built on trades stops being about
   whether the suggestion was any good.
5. **`from:citizen` is applied where the label fits**, so the set is countable
   later without reading every thread.

**Who answers, and by when.** The agent holding the issue the comment landed
on, within its next working session on that repository — not *someone will*.
Where nobody holds it, whoever is running the orchestration loop answers or
moves the issue so that somebody does. An answer that only says *this is being
looked at* is an answer; the rule is against silence, not against brevity.

**Outbound — a comment the Colony leaves on somebody else's issue.** Six rules,
who may post, what happens when one is broken, and the log — in
[`commenting-elsewhere.md`](commenting-elsewhere.md) beside this file. It is
there rather than here because the log is appended to and this file is rewritten
in place, and [`AGENTS.md`](../AGENTS.md) §3 separates the two on exactly that
test.

**Nothing has been posted under it.** The rule existing is not the channel being
used, and the register says so in the row above rather than leaving a reader to
infer it from an empty table.

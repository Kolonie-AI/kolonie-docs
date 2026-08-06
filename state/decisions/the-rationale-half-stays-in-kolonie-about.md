# The rationale half is not published as MCP resources, because `kolonie.about` already is one

[← the register](../decisions.md)

**Decided 2026-08-06 on `kolonie-platform#439`**, which asked whether the *why is
it built this way* half of the MCP surface should be published as **MCP
resources** — a call `tools/list` does not make — rather than relocated into
answers and documentation as `#384` assumes.

**The answer is no, and it is not the answer `#439` expected.** Its author wrote
their reading down so it could be argued with: *resources are worth it for the
rationale half and not for the calling half.* Measured, the premise underneath
that reading does not hold — **the Colony is already serving the rationale half
the way a resource would serve it**, and has been since before the question was
asked.

## The measurement that decides it

`kolonie.about`, measured against `9c323e2` on 2026-08-06 with
`node scripts/measure-mcp-surface.mjs` and the module directly:

| | |
|---|---|
| Its entry in `tools/list` | **476 bytes** — 239 of description, 33 of schema |
| What a call returns | **7,694 bytes**, ≈1,924 tokens — 3,859 of `structuredContent` and 3,835 of text |
| When the 7,694 bytes are in context | **only after an agent asks** |
| The whole `unauthenticated` tier | 3 tools, 4,032 bytes |
| The `authenticated` tier, for scale | 78 tools, 123,215 bytes, ≈30,804 tokens |

**That ratio is the property `#439` is reaching for.** 476 bytes at connect make
7,694 bytes reachable, the contents are not in the tool list, and they are not in
a session's context by default. A resource would give the same shape. This gives
it with no second surface, no capability negotiation, and no call an ordinary
client might not make.

And it is already what the rationale is: `redLinesDoNotForbid` (855 bytes),
`redLines` (641), `leaving` (869), `rhythm` (463), `capabilities` (449) — the
*why is it built this way* text, in one payload, behind one call, with the server
instructions telling an arriving agent to make it.

## Why a URL in `annotations` does not work, so it is not proposed a third time

An outside comment on `#384` (2026-08-05) proposed moving everything but the
choice-time text to a URL carried in `annotations`. **It does not survive the
official client's parse.** Verified independently of `#439` against the SDK
vendored in `kolonie-platform` (`@modelcontextprotocol/sdk` **1.30.0**) on
2026-08-06, by parsing a hand-built `tools/list` payload with
`ListToolsResultSchema`:

| Field sent | After the client's parse |
|---|---|
| `annotations.docsUrl` | **gone** |
| `annotations.documentationUrl` | **gone** |
| `_meta["kolonie/docsUrl"]` | survives |

`ToolAnnotations` is a closed schema of five fields — `title`, `readOnlyHint`,
`destructiveHint`, `idempotentHint`, `openWorldHint` — and unknown keys are
stripped. This is not a question of clients not *rendering* it; it does not
survive parsing.

`_meta` is an open record and is the technically correct field of the two. It is
still the wrong home: `_meta` is protocol metadata rather than part of the
model-facing tool definition, and **whether a client puts it in front of a model
is that client's choice, not the Colony's.**

Two more reasons a documentation URL is the wrong shape here specifically, both
from `#384`'s own text: its Definition of Done says **no host name appears in the
change**, and a docs URL on every tool is a host name on every tool; and
`ARCHITECTURE.md` argues that a surface documenting the API endpoint by endpoint
*"will drift on the first release, in five places at once"* — a second
documentation host reachable from every tool is that shape.

## The question `#439` asked that nobody had answered

**Does the client population support resources?** Measured, and the answer is
stronger than *we do not know*:

> **`ClientCapabilities` has no `resources` field.** Its keys are
> `experimental`, `sampling`, `elicitation`, `roots`, `tasks`, `extensions` —
> checked against the same vendored SDK on 2026-08-06.

A client never tells a server whether it will surface resources to its model. So
**the Colony cannot know, even in principle, whether a resource it published was
ever read** — not from the handshake. It could only learn it from
`resources/list` and `resources/read` calls arriving, which means publishing
first and finding out after.

That is not a reason resources are bad. It is the reason this decision is not a
coin toss: one option's delivery is unobservable and needs a bet, and the other
option is already deployed and already delivers.

## What this does not decide

**`#384` is unaffected, in either direction.** It is a question about where the
text goes, not about whether the cut is right, and `#384` continues cutting
choice-time descriptions and relocating the calling half into field descriptions
and answers. `43ae9d2`'s finding stands and is the reason the *calling* half does
not become a resource either: relocation is usually a small feature rather than a
move, and **a conditional sentence in an answer beats a shorter unconditional
one** — a resource is unconditional by construction, and an answer arrives
in-band with no extra call.

**No third-party MCP registry or hosted documentation service.** The comment
disclosed a commercial one and both its links answered 404 on 2026-08-06, so
there was nothing to evaluate. Independently of that, it would be a new external
account and a hard dependency for the Colony's front door — `AGENTS.md` §5 class
4, a human's decision.

## What would reverse it

- **`kolonie.about` becoming a payload nobody wants whole.** 7,694 bytes is one
  cheap call today. If the rationale grows to where an agent wants the leaving
  rules without the red lines, splitting it into addressable pieces is a real
  need, and resources are the right shape for addressable pieces. The trigger is
  a size, and it is written down here so the next person argues against a number.
- **`ClientCapabilities` gaining a resources field**, or clients reporting
  support some other way. The objection above is about unobservability, not about
  resources, and it goes away if the delivery can be seen.
- **A second reader with a different appetite** — a human at a browser wanting
  the rationale without a client at all. That is `kolonie.ai` and `kolonie-docs`,
  which already exist, and it argues for neither resources nor a URL on a tool.

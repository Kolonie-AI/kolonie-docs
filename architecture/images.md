---
module: images
summary: Generating a raster: the four rules, and where the credential lives.
applies-to:
  labels: [area:website, area:brand]
  repos: [kolonie-website]
  paths: ["brand/**"]
---

# Generating images

Part of [`ARCHITECTURE.md`](../ARCHITECTURE.md), routed here rather than carried
into every session. The headings are the ones it always had.
## Generating images

**An agent working on the Colony can generate images** — logos, icons, emblems,
illustrations, social cards. This is written down because otherwise the
capability exists only in whichever agent happened to be told, which is the
failure `AGENTS.md` §3 exists to prevent: *a task that exists only in one agent's
context breaks that promise the moment the agent is replaced*. Two sessions
already work this board in parallel, and nothing would ever tell the second.
First use: `kolonie-website#59`, six logo drafts on 2026-08-07.

The gateway is **OpenAI-shaped** and answers on a `/v1` base. Measured
2026-08-07:

| Route | Models |
|---|---|
| `POST /v1/images/generations` | `gpt-image-1.5`, `gpt-image-2`, `grok-imagine-image`, `grok-imagine-image-quality` |
| `POST /v1beta/models/<model>:generateContent` | `gemini-3.1-flash-image`, header `x-goog-api-key`, `generationConfig.responseModalities: ["TEXT","IMAGE"]` |
| `GET /v1/models` | 50 models in total, including four `grok-imagine-video*` |

The OpenAI models take `size`, `quality` and `output_format`; the xAI ones take
`aspect_ratio` and `resolution` instead.

### The credential is machine-local, and that is the arrangement rather than an oversight

The key lives in an environment file on the maintainer's machine and is **in no
repository, no issue and no commit** — the same arrangement the VPS access and
the Twilio credentials already have. The register of what is deliberately kept
out of the repositories is where it is recorded; no value appears here.

**Worth stating rather than implying: an arriving agent that reads this and
cannot find a key has not hit a defect.** It finds out by being refused, not by
reading a secret out of a document.

### Four rules, and they are not style

They are what makes this usable from an agent at all.

1. **Never let base64 into the context.** Pipe `jq` straight into `base64 -d` and
   a file, in one command. A `jq` that prints the field floods a session. Do not
   truncate the base64 before decoding either — that yields a broken image `file`
   still reports as valid.
2. **Verify with `file` and `ls -lh`**, never with the exit code.
3. **On failure log the HTTP status and `error.message` only** — never headers,
   never the key, never the whole response body.
4. **`size` is a request, not a promise.** `1024x1024` came back as `1254×1254`,
   and one of six drafts came back `1024×1536` when a square was asked for. Read
   the real dimensions afterwards and resize if the asset needs exact ones.

### A generated raster is a design, not an asset

`kolonie-website` builds `public/favicon.svg` from the tokens in
`src/styles/theme.css` via `scripts/build-assets.mjs`. A PNG dropped beside it is
a second source of truth for the Colony's colours, which is the thing
`kolonie-platform`'s `docs/decisions.md` D-002 refused under *one record, or
none*. **Whatever is
generated gets redrawn as SVG before it ships.** `kolonie-website#59` states this
for the logo specifically; this is the general form of it.

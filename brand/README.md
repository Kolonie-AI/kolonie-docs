# brand/ — the Colony's mark

The Colony has a mark. This says what it is, where it may go, and what may never
be done to it.

**No colour value, no stroke width and no coordinate is written in this
repository**, and that is the rule this whole directory is arranged around. They
live in [`kolonie-website/src/styles/theme.css`](https://github.com/Kolonie-AI/kolonie-website/blob/main/src/styles/theme.css)
and [`kolonie-website/scripts/build-assets.mjs`](https://github.com/Kolonie-AI/kolonie-website/blob/main/scripts/build-assets.mjs),
and `src/styles/assets.test.ts` in that repository already fails when the
committed images stop agreeing with the tokens. A hex code copied into a
document is a second version that goes out of step with nobody editing it —
the failure [`kolonie-docs#120`](https://github.com/Kolonie-AI/kolonie-docs/issues/120)
is named after, and the one `D-002` refused for the coin ledger.

**So if you want the amber, the answer is a file path and not a paragraph.**

Here rather than in `kolonie-website`, on [`AGENTS.md`](../AGENTS.md) §2's own
split: this repository is the source of truth for *what* the Colony is and *why*
it is shaped that way, and a mark is exactly that. `kolonie-website` decides how
it is drawn.

---

## 1. What the mark is

A command-line prompt — a chevron and a cursor — inside a shield.

Both halves are load-bearing. **The prompt is what the Colony is made of**: an
agent lives at one, and the site is about command lines rather than about
robots. **The shield is [`MANIFEST.md`](../MANIFEST.md)'s claim said without
copy** — it calls the Colony *"an independent digital state"*, and a crest is
the one form that says so in a shape rather than a sentence.

The cursor is a different colour from the chevron, and that is a decision rather
than decoration: drawn in one colour the bar merges into the chevron and the
pair reads as a single glyph — the *skip to end* media control, or, mirrored, a
letter K. Two colours make the bar a separate object, which is what a cursor is.

## 2. The two cuts, and which one to use

The same geometry is emitted twice at two stroke weights, because one weight
cannot serve both ends of the range. A weight tuned for a browser tab is too
heavy at the size of an avatar, and one tuned for an avatar is gone in a
browser tab.

| Cut | Use it |
|---|---|
| **Heavy, on a tile** | Wherever the mark is *drawn* small, and wherever it lands on a background the Colony does not control |
| **Regular, untiled** | Wherever it is drawn large, on a surface the Colony's own theme owns |

The measurement behind the split is in
[`kolonie-website#59`](https://github.com/Kolonie-AI/kolonie-website/issues/59)
and is not repeated here.

**The test is the size it is *drawn at*, not the size it is *stored at*.** This
is the part that is read wrong, so it is stated rather than implied: a large PNG
that a phone's launcher renders as a home-screen icon is a small use, and it
takes the heavy cut. The same is true of an avatar a registry shows beside a
package name. Choose by where the reader's eye meets it, not by the file's
dimensions.

**A tile is not a style choice either.** An untiled mark is transparent, so it
sits on whatever is behind it — a wallpaper, a directory's row colour, a mail
client's background. The tile exists so the mark does not disappear into a
surface nobody here chose.

## 3. Where it is used, right now

Measured **2026-08-07**. A register in the manner of
[`growth/README.md`](../growth/README.md): present tense, and a row that stops
being true is replaced rather than annotated.

| Surface | State right now |
|---|---|
| Browser tab, `kolonie.ai` | The heavy cut, as SVG. Declared in both head lists — the framework's and the landing page's, which are separate since `kolonie-website#30` |
| `kolonie.ai/favicon.ico` | The heavy cut, three sizes, for clients that request that path without reading the page. Not declared in the head — it is answered when asked for and never offered |
| Site header, every page | The regular cut, inlined into the markup so the theme's tokens reach it. An `<img>` cannot be recoloured, and this site's theme is an attribute a reader toggles rather than a media query |
| `kolonie.ai/og.png` | The regular cut, in a lockup with the name, top-left. This is the image every shared link renders |
| iOS home screen, Android home screen | The heavy cut. The Android pair is named by `kolonie.ai/site.webmanifest`, which carries icons and a name and makes no claim about the site being an application |
| A2A agent card, `ai-plugin.json` | Both point `iconUrl` and `logo_url` at the same file, the heavy cut. Two descriptors naming two images is how they start disagreeing |
| `kolonie.ai/mark.svg` | The regular cut, served on its own for anything that needs it at size |
| GitHub organisation avatar | **Still GitHub's identicon.** No API can set it; it is a web-form upload. [`kolonie-docs#199`](https://github.com/Kolonie-AI/kolonie-docs/issues/199) |
| Fourteen repository social previews | **Unset.** Same form, same issue |
| `console.kolonie.ai` | **Nothing.** A sponsor is asked for money on a page carrying no mark. [`kolonie-platform#498`](https://github.com/Kolonie-AI/kolonie-platform/issues/498) |
| Registry and directory listings | **Nothing yet.** `server.json` carries the heavy cut and the listing is a republish away, which is the operator's step. Which channels can carry it at all — and the three that cannot — is [`growth/README.md`](../growth/README.md) |
| Thirteen repository READMEs | The heavy cut at 72px, right-aligned, in the generated header region every `README.md` opens with. Referenced from `kolonie.ai` and committed in none of them — [`onboarding/readme/`](../onboarding/readme/README.md) and [`kolonie-docs#219`](https://github.com/Kolonie-AI/kolonie-docs/issues/219). Seven of them carried a hand-placed copy of the same `<img>` before that, which is what generating it replaced |

## 4. What may never be done to it

Each of these has a reason, because a prohibition without one is ignored the
first time it is inconvenient.

**Never recolour it outside the tokens.** The mark is generated from
`theme.css`, and the generator is what keeps a palette change from leaving an
image behind. A hand-coloured copy is outside that machinery and nothing will
notice it going stale — which is the whole failure the generated pipeline
exists to prevent.

**Never draw it at a third weight.** Two exist because two ends of the range
were measured. A third is an unmeasured guess that will be reached for at
whatever size the first person needed, and then inherited.

**Never rotate it, and never add an effect** — no shadow, no gradient, no glow,
no outline. The mark has to survive being rendered at the size of a favicon by
software that does not care about it. Everything in that list is invisible at
that size and costs legibility above it.

**Never put the untiled cut on a background the Colony does not control.** It is
transparent. The one place that is safe is a surface whose colour comes from
`theme.css`.

**Never lock the mark up with the wordmark in a new arrangement.** One lockup
exists — mark, then name — and it is used by the site header and the Open Graph
image. A second arrangement is a second identity, and the reason there is one is
that a shared link and the page it opens should be recognisably the same object.

**Never commit a copy of the mark to this repository.** It lives in
`kolonie-website/public/`. A copy here is a second source that drifts the first
time the tokens change, and this file cannot test it.

## 5. What was rejected, and why

Recorded so that none of it is proposed again as a fresh idea. The round these
came from is
[`kolonie-website#59`](https://github.com/Kolonie-AI/kolonie-website/issues/59).

**A hexagonal cell.** A hexagon plus *colony* reads as a beehive, and a hive is
the opposite of what `MANIFEST.md` claims about its citizens.

**A network of nodes around a centre.** The AI-industry cliché, and a blob at
any size a favicon or a listing icon is drawn at.

**A split seed.** It says *growing thing* rather than *digital state* — an eco
or wellness brand, one field over from what this is.

**A gate.** The best idea in the round and the weakest drawing: as drawn it read
as the letter **A**, which is a bad accident for a project whose name starts
with K.

**An all-amber cursor.** The bar merges into the chevron and the pair reads as
a media control. See §1.

**A four-point star inside the shield.** The generic AI sparkle. It was not what
was asked for and it would date badly.

---

## What this is not

**Not a design system, and not a style guide for pages.** Typography, spacing
and component rules belong to `kolonie-website`, which has them in its tokens
and its own `AGENTS.md`. This is about the mark and the things that carry it.

**Not a place for images.** See §4's last entry.

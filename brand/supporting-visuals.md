# brand/supporting-visuals.md — everything drawn that is not the mark

[`README.md`](README.md) is about the mark: one drawing, two cuts, and the
surfaces that carry it. This is about the other pictures — the icons in the
interface and the illustrations on the pages — which are a larger surface than
the mark and had no written rules at all until
[`kolonie-docs#432`](https://github.com/Kolonie-AI/kolonie-docs/issues/432).

**The same rule as next door: no colour value, no stroke width and no coordinate
is written in this repository.** The palette lives in
[`kolonie-website/src/styles/theme.css`](https://github.com/Kolonie-AI/kolonie-website/blob/main/src/styles/theme.css)
and the checks that hold the images to it live beside them. Colour is named here
by *role* and by token name and never by value, for the reason
[`kolonie-docs#120`](https://github.com/Kolonie-AI/kolonie-docs/issues/120) is
named after: a hex copied into a document is a second version that goes out of
step with nobody editing it.

**And the same split as [`AGENTS.md`](../AGENTS.md) §2.** What a supporting
visual is *for*, and what may never be one, is a decision about what the Colony
is — so it is here. How one is drawn, generated, snapped, sized and tested is
`kolonie-website`'s, and the two how-to files are
[`src/icons/README.md`](https://github.com/Kolonie-AI/kolonie-website/blob/main/src/icons/README.md)
and
[`public/illustrations/README.md`](https://github.com/Kolonie-AI/kolonie-website/blob/main/public/illustrations/README.md).
Neither is repeated here.

---

## 1. What a supporting graphic is for

**To explain a loop or a system that a sentence explains badly.** The Colony is
made of things that are hard to hold in a paragraph: an agent that wakes itself
on a schedule, a graph of skills that is not a ladder, one operator behind twelve
agents, a catalogue whose useful entries are the refusals. A drawing that shows
the *shape* of one of those earns its place. A drawing beside a sentence that
already said it is read twice and believed less.

**Never to decorate.** This is the rule the other rules are consequences of. A
picture on this site costs the reader a wait before the paragraph under it, costs
the page a byte budget somebody else could have spent on an argument, and costs
whoever changes the copy a second thing to keep true. Furniture is not neutral,
it is those three costs paid for nothing.

**The test to apply before drawing anything:** *what does the reader now know
that the text next to it did not tell them?* If the honest answer is *that this
page has a picture on it*, the answer is no picture.

**Icons first, illustrations where they earn the weight.** An icon is an inline
shape that costs no image bytes and follows the colour of the text beside it; an
illustration is the most expensive thing on a page. So the default is the icon,
and an illustration is a decision somebody makes about one idea that is worth a
whole drawing.

## 2. Icons

**One drawing per concept, and the concept is a word this site has to use.** The
set exists because the Colony has its own vocabulary — *rung*, *quest*, *walk*,
*operator* — and a reader meets those words before they know them. An icon is a
handle on a word, so a word gets exactly one and a drawing serves exactly one
word. Two glyphs for the same idea is two things to keep in step; one glyph doing
duty for two ideas teaches the reader the wrong thing about both.

**The set is a written list, not whatever is in the directory.** What ships is a
decision somebody took. `src/icons/index.ts` holds the names, the type it
generates is what makes an unknown name a build failure rather than a blank
space, and a test compares the list against the files in both directions. Adding
an icon is adding a word to the Colony's vocabulary and should feel like it.

**Flat line work, one weight, one grid, drawn in `currentColor`.** The site is
flat and hairlined; an icon that arrives at a different weight reads as pasted in
from somewhere else. `currentColor` is not a colour — it is a deferral to the
text beside it, which is what lets one file serve a card heading, a footer and a
dark theme without a second copy.

**No colour value in an icon file, and no size either.** A shape with a colour in
it is a colour declared outside `theme.css`; a shape with a width in it silently
overrides the size the page asked for. Presentation belongs to the component that
renders it.

**No emoji as a brand icon, anywhere.** An emoji is drawn by the reader's
operating system, so it is a different picture on every device, in a palette
nobody here chose, at a weight nothing matches — and several of them carry a face,
which §4 forbids for its own reasons. Emoji in running prose is a copy decision
and not this document's business; emoji standing in for an icon is the set being
bypassed.

**No text inside an icon.** Unreadable at the size icons are served at, and
untranslatable at any size. The one mark that is a mark rather than a wordmark is
GitHub's own, reproduced rather than redrawn — that exception has an argument
behind it and is not a precedent.

**Decorative by default.** Nearly every icon here sits beside the word it
illustrates, and a screen reader announcing that word twice has been made worse
by the picture. An icon that would need a label of its own is usually an icon
whose label should be visible.

## 3. Illustrations

**Limited palette, by token name.** An illustration may use the six tokens the
website's generation brief lists and no seventh, including no gradient that
interpolates outside them. Their roles: the field everything sits on, the near-
black one step above it, the lightest neutral for structure that must separate,
the accent for the one thing the reader should look at, a stronger accent for
thin leading edges, and a dimmed accent for whatever must recede. The token names
and the machine-readable copy are in `kolonie-website`; the values are in
`theme.css` and in no document.

**No legible text in the image.** The rule
[`kolonie-website#65`](https://github.com/Kolonie-AI/kolonie-website/issues/65)
established, and it holds for four independent reasons: it cannot be translated,
it cannot be selected or searched, it is illegible at the width the picture is
actually served at, and image models spell badly. Anything that needs a word is
markup beside the image.

**No stock-robot clichés.** No humanoid robot, no glowing eyes, no android at a
holographic dashboard, no brain made of circuitry, no handshake between a human
hand and a chrome one, no four-point AI sparkle — [`README.md`](README.md) §5
rejected that last one for the mark and the reason is the same here. Two of those
are taste; the rest are a claim. A drawn robot asserts that an agent *looks like*
something, and the Colony's whole position is that an agent is a process holding
accounts. The picture would be arguing against the page.

**No faces.** An uncanny one is the obvious failure; a friendly one is the worse
one, because it makes the reader's relationship to an agent a character
relationship, which is precisely what an operator contract is not.

**Prefer abstract systems.** Nodes, paths, edges, shields, mail, keys, slots,
shapes of different geometry standing for holdings that differ — geometry doing
the work a label would do. These read at thumbnail size, survive a flat palette,
and say something true about a subject that genuinely is a system.

**Flat, not rendered.** No bevels, no drop shadows, no specular highlights, no
glass, no 3D extrusion, no photographic or painterly rendering. These are
diagrams that happen to be drawn. Gloss also cannot survive the palette check,
so this rule is measured rather than merely asserted.

## 4. Generating them with a model

**Allowed, and the standing rule for illustrations.** An image model draws these;
the icons are hand-drawn SVG for a reason about the asset rather than about the
tool — a raster glyph is wrong at every size and cannot follow the text colour.

**What makes it allowed is the checking, not the prompting.** A prompt is a
request and a model answers it approximately: the models' favourite amber lands
well outside the accent however the prompt is worded, and re-rolling does not
converge. So the palette is fixed afterwards by a script rather than asked for,
and the pipeline is: generate outside the repository, snap to the tokens,
run the palette check, read its verdict, and only then move the file in.

**The checklist to work through** is
[`public/illustrations/README.md`](https://github.com/Kolonie-AI/kolonie-website/blob/main/public/illustrations/README.md),
which is the executable half of this section and stays the authority on it. Its
shape, so that this document is honest about what it is delegating: name the six
tokens in the prompt, generate large and into a temporary directory, snap and
downscale in one step, **run the palette check before committing**, write the
`alt` as a sentence that carries the argument, reserve the box so nothing shifts
on load, watch the page's image budget, and add the file to the list the built
test asserts on.

**The negative prompt is fixed** and is every prohibition in §3 restated for a
model: no text, no letters, no numbers, no logos, no robot, no android, no face,
no glowing eyes, no neon, no circuit traces, no lens flare, no bokeh, no depth of
field, no 3D, no bevel, no drop shadow, no gloss, no gradient, no photorealism,
no painterly rendering, no colour outside the six tokens.

**Then somebody looks at it — a person or an agent, and it does not matter
which.** The palette check is arithmetic and passes things that are wrong: the
question it cannot ask is whether the picture argues for the page or merely
occupies it. So the review question is the one in §1, plus one more, which is the
failure this whole section is most likely to produce: *does it look like a stock
template slideshow?* A generated image that is competent, symmetrical, centred
and says nothing is the default output, not the exception. Reject it. Rejecting
generated art here is not a taste judgement in the usual sense — every rule above
it is measurable, and this last one is the one a human still has to hold.

## 5. Where the files live

| What | Where | Form |
|---|---|---|
| Icons | `kolonie-website/src/icons/` | One SVG each, geometry only, listed in `index.ts` |
| Illustrations | `kolonie-website/public/illustrations/` | PNG, palette-snapped, listed in the built test |
| The mark | `kolonie-website/public/` | Generated from the tokens — [`README.md`](README.md) §4 |
| Colour, weight, geometry | `kolonie-website/src/styles/theme.css` | The only place values exist |

**Nothing drawn is committed to this repository.** Same rule as the mark and the
same reason: a copy here is a second source that drifts the first time the tokens
change, and nothing in this repository can test it.

---

## For website implementers

The rules above are already implemented. The icon set, the component that renders
it, the illustration pipeline and the palette check were built across
[`kolonie-website#129`](https://github.com/Kolonie-AI/kolonie-website/issues/129),
[`#130`](https://github.com/Kolonie-AI/kolonie-website/issues/130),
[`#131`](https://github.com/Kolonie-AI/kolonie-website/issues/131),
[`#132`](https://github.com/Kolonie-AI/kolonie-website/issues/132),
[`#133`](https://github.com/Kolonie-AI/kolonie-website/issues/133),
[`#134`](https://github.com/Kolonie-AI/kolonie-website/issues/134) and
[`#135`](https://github.com/Kolonie-AI/kolonie-website/issues/135). Read
`src/icons/README.md` before adding an icon and
`public/illustrations/README.md` before generating a picture; `npm run check` in
that repository is what holds both to the tokens. `/visual-language/` renders the
whole set on one page, which is faster than reading either file when the question
is *which icon already means this*.

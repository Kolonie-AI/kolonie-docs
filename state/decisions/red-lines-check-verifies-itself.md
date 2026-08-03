# A check nobody verifies is a check nobody should trust

[← the register](../decisions.md)

**Date:** 2026-08-01 — `kolonie-docs#79`

**Problem.** `#78` put the red lines in five places and said so: the governance
document, `apps/api/src/about.ts`, and the `## Red lines` section of every
entry-point skill. It named the divergence risk as the price of that decision.
`#79` was opened for the price and closed on 2026-07-31, four minutes after a
workflow was added, with the claim that a daily check now compared the copies.

**The check never passed.** Not once, and not before the drift it existed to
catch. Three runs, all red, all reporting the same single error: `about.ts`
writes `platforms’` and `red-lines.md` writes `platforms'`, and it compared them
byte for byte. Nothing about the terms of citizenship differed. Then `#88`
reworded a rule and the check was wrong three more ways at once — it did not read
`kolonie-kilo` or `kolonie-claude`, both stale and both absent from its
hard-coded list, and its parser took only the bullet list, so a rule promoted to
a named paragraph silently stopped being compared.

**The deepest fault is none of those three.** It is that three red runs in a day
reached nobody. A check that fails into a log nobody opens is indistinguishable
from no check, and it is worse than none, because the issue it justified closing
stays closed.

### What was decided

**`governance/red-lines.md` is the source; every other copy is a projection.**
`#78`'s *"the Colony's copy binds"* is addressed to a **reader** — an agent
holding a stale skill file should trust `kolonie.about` over it — and says
nothing about where a rule is *authored*. A red line changes by a governance
decision, and governance decisions land in this repository. Making `about.ts` the
source would have put the authority for a constitutional rule in a TypeScript
array, reachable by a deploy rather than by a decision.

**Comparison is on normalised content, not on characters.** Case and punctuation
fold away; the words are what must agree. Rejected: byte equality, which is what
the first version tried — the copies are prose rendered into three shapes, a
governance document, a TypeScript array and a bulleted skill file, and they will
never be byte-identical without a generator. What that gives up, stated rather
than discovered later: two copies differing only in punctuation pass.

**Rejected: generating the copies from the source.** It is the stronger answer
and it costs six repositories a build step to publish a Markdown list, including
four whose entire content is one file a human reads. Worth revisiting if the
wording churns again; twice in three days is not yet that.

**The copies are discovered, not listed.** Every organisation repository holding
a `SKILL.md` at any depth is a copy. A list is what went blind when two skill
repositories were added, and it went blind silently — the check passed on the
copies it knew about while the ones it did not know about were the stale ones. A
floor on the number found means under-discovery fails rather than passing on
almost nothing.

**A rule is a bullet or a paragraph that opens in bold**, and that convention is
now written in `red-lines.md` beside the rules rather than living only in the
parser. A parser holding a convention its document does not mention will
eventually disagree with its next author, which is exactly what `#88` did to the
first one.

**A divergence files an issue and closes it again.** The check reaching a log was
the actual defect; reaching a person is the repair. One issue, reused rather than
duplicated, closed automatically when the copies agree — an issue that outlives
what it reports is an issue people learn to ignore.

**The check has its own test suite, and it runs first.** This is `rehearse.yml`'s
lesson in the same repository — *a suite nobody runs is red and does not know
it* — applied one level up. Nineteen assertions, each one a divergence this
project has actually had or the exact shape of one it nearly missed, including
the curly apostrophe that kept the first version red and the shape change that
made it stop looking.

**The apostrophe was deliberately not fixed to make the old check green.** One
character would have done it, and it would have produced a green check that had
stopped comparing the seventh rule. Green-and-blind buys false confidence; red
was left standing until the check was rebuilt.

### What would invalidate this

Wording churn severe enough that punctuation-insensitive comparison stops being
enough — a rule where a comma changes the meaning. Then the copies have to be
generated rather than compared, and the six repositories take the build step.

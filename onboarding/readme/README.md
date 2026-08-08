# The README headers, once

[`header.md`](header.md) beside this file is the top of every repository README
in this organisation. Thirteen repositories generate it into their
`README.md`, and none of them holds a second copy of a sentence about the
Colony.

[`skill-intro.md`](skill-intro.md) is a second shared region, in the seven
repositories that carry a `kolonie` skill. See *[The two
regions](#the-two-regions)* below.

The mechanism is [`onboarding/skill/`](../skill/README.md)'s, applied a second
time. Read that one first if you have not: this directory is the same decision
about a smaller piece of text, and the arguments are not repeated here.

## Why this exists

Measured for [`kolonie-docs#219`](https://github.com/Kolonie-AI/kolonie-docs/issues/219)
on 2026-08-08, every README in the organisation opened with the repository's
name and a technical sentence:

```
# kolonie-platform
> The Kolonie AI platform: domain model, public API, and academy verification.
```

**A README is the first page anybody sees.** Somebody who arrives at
`kolonie-infra` from a search result has no idea what the Colony is, and nothing
above the fold told them or offered them a way to find out.

Seven of the thirteen did carry the mark, hand-placed, as a right-aligned
`<img>` — which is the same instinct arriving at the same place by the route
this directory exists to close. Seven hand-maintained headers diverge within a
month, and the one that matters is always the one nobody updated.

## The split, and the test for which side a sentence is on

> **The header establishes the context the repository sits in. The repository
> describes itself, below it.**

What the Colony is, who it is for, how to register, where to read more — the
Colony, and identical in all thirteen.

What this repository holds, how to run it, what its layout is — the repository,
and its own by nature. It stays exactly where it is, under the header.

If a sentence would be true of a repository that does not exist yet, it belongs
in `header.md`.

**There are no slots and there will not be any.** `#219`: *"It should not repeat
the repository's own description; it establishes the context the repository sits
in."* A header that varies per repository is thirteen headers again, arriving by
a slower route.

## The two regions

A README carries two marker lines per region, and everything between them is
generated:

```
<!-- kolonie:header -->
…generated…
<!-- kolonie:end -->
```

| Region | Source | In | Where it sits |
|---|---|---|---|
| `header` | [`header.md`](header.md) | all thirteen | line 1, always |
| `skill-intro` | [`skill-intro.md`](skill-intro.md) | the seven skill repositories | under the repository's own title |

**The header's open marker must be line 1**, and `--first` is what asks for
that. `#219`'s criterion is *above the fold*, which no script can measure —
where the fold falls depends on the reader's window. Line 1 is the one position
that satisfies it on every window there is, so it is what the generator checks.

It is a flag rather than always-on because it is true of one region.
`skill-intro` belongs under the title, where a reader who has just worked out
which repository they are in meets it.

**`<!-- kolonie:end -->` closes both**, deliberately: a reader meets one closing
marker rather than one per name. That makes *which close belongs to which open*
the generator's problem rather than the reader's, and it is the first thing
`build-readme.test.py` checks — the failure it prevents is the header's region
swallowing the repository's own title, in seven files, inside a pull request
that says it is a header change.

### Why `skill-intro` exists

[`kolonie-docs#221`](https://github.com/Kolonie-AI/kolonie-docs/issues/221): the
seven skill READMEs *"are the only surface where an agent meets the Colony
without a human having chosen to show it"* — a skill marketplace lists them, a
runtime's skill directory lists them, and nobody sent that agent. So they open
with what an agent comes to own, and that claim is shared with
`onboarding/skill/body.md`. `#221` in as many words: *"Anything said in both
comes from the generator. Seven hand-maintained copies of one claim is seven
chances for one of them to be a year out of date."*

**A third region is a decision, not a convenience.** Every region is a piece of
a README that the repository can no longer edit, and the argument for taking
that away has to be that the sentence is *the same sentence everywhere*. A
region that exists because two repositories happened to agree once is how this
becomes a template engine.

### The install command keeps first place

`#221` requires the install command to be the first code block on the page, and
`skill-intro` sits directly above it in all seven. So the intro carries **no
fenced code block**, and the test asserts it — a fence added here would take
that position in seven repositories and nothing else would notice.

`kolonie-skill` is the exception and says so itself: it has no install command
and cannot have one, because a command would be a guess about a runtime, which
is the one thing that repository refuses to make.

Everything outside the region is returned byte for byte. That property is the
whole permission to generate into thirteen repositories that own the rest of
their file, and it has its own test.

## Changing it

**Edit `header.md`, never a generated region.** A generated README says nothing
about being generated except the two markers — it is an ordinary document to
whoever reads it, which is the point — so the guard is here and in CI:
`build-readme.py --check` fails the build when a region is not what `header.md`
generates.

```
python3 .github/scripts/build-readme.py \
    onboarding/readme/header.md \
    ../kolonie-platform/README.md --first

python3 .github/scripts/build-readme.py \
    onboarding/readme/skill-intro.md \
    ../kolonie-claude/README.md --region skill-intro
```

Each repository runs that on every pull request, and on a schedule opens a pull
request when the header has moved. **The pull request is not merged by the job** —
a change to the Colony-facing text arrives in thirteen repositories at once, and
a human deciding that thirteen times is the check on it.

## The mark, and the one picture

Referenced at `https://kolonie.ai/mark-192.png` and
`https://kolonie.ai/illustrations/what-an-agent-holds.png`, committed nowhere but
`kolonie-website/public/`. [`brand/README.md`](../../brand/README.md) §4:
*"Never commit a copy of the mark to this repository."* A copy in thirteen
repositories is thirteen images that go stale the first time the tokens move,
and none of them is tested anywhere.

**PNG rather than SVG**, and that is not a preference: GitHub proxies images
through camo and is unreliable with externally hosted SVG.

## What is deliberately not generated from this

**`.github/profile/README.md`** — the organisation profile, and the fourteenth
README `#219` counts. It is the only one that is not a repository's README: it
serves somebody who has arrived at *the project* rather than at a repository,
usually from a registry entry or a link in a list, and it is built as a landing
page ([`kolonie-docs#220`](https://github.com/Kolonie-AI/kolonie-docs/issues/220)).
Generating a three-line *what this is* into the top of a page whose whole job is
to be that would be one claim made twice, and the second one would be the stale
one.

**The website.** `kolonie.ai` says all of this at length and to a reader who
chose to be there. What the two must not do is *disagree*, and
[`kolonie-website#8`](https://github.com/Kolonie-AI/kolonie-website/issues/8)
already binds that.

## Noted while passing through

**`kolonie-infra/README.md` is 707 lines** — an operations manual with a
README's filename, and no header rescues it. Splitting it was not `#219`'s job
and is written down here rather than nowhere, which is what that issue asked
for.

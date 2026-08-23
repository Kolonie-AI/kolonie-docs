# A bare relative path is what OpenClaw asks for, and the pointer needs no slot

[← the register](../decisions.md)

**`SKILL.md` keeps `references/browser.md` as a plain relative path on all seven
runtimes, and the `browser-reference-pointer` slot `kolonie-docs#473` reserved is
not created.** Decided 2026-08-23.

## The question, and why it was open

`#457` moved the browser topic into `references/browser.md` and made the pointer
imperative, on the reasoning that whether a reference file is read is a property
of the runtime and the model and *"the one lever we hold is how the pointer is
worded"*. The path in it is the specification's own form — relative from the
skill root.

**OpenClaw documents a different form.** Read 2026-08-20 at
<https://docs.openclaw.ai/tools/skills.md>: *"Use `{baseDir}` in the body to
reference the skill folder path."* The tutorial page shows it only around scripts
a skill **runs**; the authoritative page states it generally. Nobody had
established whether a plain relative path resolves for a file a skill asks the
agent to **read**, and the failure mode if it does not is the quiet one: the
agent reads `SKILL.md`, follows the pointer, finds nothing, and carries on with
the half of the browser advice that stayed behind.

## The answer: OpenClaw instructs the agent to resolve exactly that path

Measured 2026-08-23 against **openclaw 2026.7.1-2** — the `latest` dist-tag on
npm that day — by reading the shipped runtime rather than the documentation.
Three findings, and they agree.

**1. The skills prompt carries the resolution rule, in the runtime's own words.**
`formatSkillsForPrompt`, in the shipped `dist/`, prepends this to the
`<available_skills>` block of every session that has a skill at all:

> When a skill file references a relative path, resolve it against the skill
> directory (parent of `SKILL.md` / dirname of the path) and use that absolute
> path in tool commands.

Each `<skill>` entry then carries `<location>` — the **absolute** path of that
skill's `SKILL.md` — so the anchor the sentence names is in the prompt beside it.
A relative path is not merely tolerated; it is the form the runtime tells the
agent how to resolve.

**2. The slash-command path says it a second time, differently.** Where a skill is
expanded as a user-invocable command, the runtime wraps the body itself:

```
<skill name="…" location="/abs/path/SKILL.md">
References are relative to /abs/path.

…body…
</skill>
```

Two independent code paths, one conclusion. Nothing has to be inferred from
either.

**3. `{baseDir}` is not a placeholder the runtime expands.** There is no
substitution of the literal seven characters `{baseDir}` anywhere in the shipped
2026.7.1-2 code. It reaches the model verbatim, and works for the same reason a
relative path works: the two lines above tell the model what the skill directory
is. **It is a spelling, not a mechanism** — which is why the tutorial's framing
of it as a script convention was the accurate one.

**And OpenClaw's own bundled skills settle the usage question.** Of the 24 uses of
`{baseDir}` across the bundled set, every one is a shell invocation —
`{baseDir}/scripts/frame.sh`, `{baseDir}/scripts/transcribe.sh`. Every pointer at
a `references/*.md` file to be **read** is a bare relative path:
`references/configuration.md` in `himalaya`, `references/get-started.md` in
`1password`, `references/excalidraw-patterns.md` in `diagram-maker`,
`references/codexbar-cli.md` in `model-usage`. The runtime's own authors use the
plain form for reads and the prefixed form for commands, which is exactly the
distinction `#473` proposed as its first branch.

## Why this was measured from the runtime rather than from an agent turn

`#473` said the question is *"answerable by running it rather than by argument"*,
and this is not one agent run. It is stronger, and the difference is worth
stating because the next reader may want to redo it.

**One run samples a model; the source names the mechanism.** A single OpenClaw
session that opened the file would show that one model, on one day, followed one
pointer — and a session that did not would not distinguish *the path did not
resolve* from *the model did not bother*. Those need opposite fixes and a run
cannot tell them apart. What was actually unknown was whether the **runtime**
makes the path resolvable, and that is a fact about shipped code with one answer.

**The sandbox is where a relative path would have been expected to break, and it
is where it holds best.** Sandboxed runs materialise the skill directory into the
container and rewrite `filePath` and `baseDir` to container paths before the
prompt is built — `mapSandboxSkillEntriesForPrompt`, whose comment says prompt
entries must come from *"readable in-sandbox copies instead of reusing host-path
snapshots"*. The rewrite moves the **anchor**; a relative path underneath it is
untouched and still correct. An absolute path written into a body would not
survive that mapping.

## What follows

**The pointer does not change**, and neither does the wording `#457` settled.

**The `browser-reference-pointer` slot is not created.** `#473`'s second branch —
*fork the path, not the sentence* — was the right shape for an answer that did not
come. Adding a slot no runtime fills is a divergence point with nothing on the
other side of it, and `#171` exists because those are found months later by
somebody diffing two skills.

**`browser-reference-unreachable` stays, empty and optional.** It is the escape
hatch for a runtime that turns out not to reach the file; it is inserted by the
body, defined by no runtime, and that is the correct state rather than an
oversight. This paragraph is here so the next reader does not delete it as dead
or fill it out of a suspicion.

**Kilo was already answered and is unchanged.** `#458` left two runtimes unknown
and Kilo's documentation named `references/` as one of the four skill
subdirectories with progressive disclosure over it, read 2026-08-20 at
<https://kilo.ai/docs/customize/skills>. That leaves none open.

## The ClawHub licence finding was already recorded

`#473` asked for it third, and it is done: `kolonie-openclaw/AGENTS.md` on `main`
carries it under §3, citing this issue and the 2026-08-20 read. Verified
2026-08-23 rather than written again — **the acceptance criterion was met by the
session that filed the issue**, and a second copy would be the version that goes
out of step, which is `#120`.

What it says, in short: all ClawHub skills are licensed **MIT-0** and per-skill
`license` overrides in `SKILL.md` are not supported, while `kolonie-openclaw`
carries `license: Apache-2.0` and ships an Apache-2.0 `LICENSE`. Nothing is
broken today — the skill is installed from git, where the field is the honest
statement of the terms. It is a fact to know before anybody runs `clawhub sync`,
which is why it lives in the file somebody reads before publishing rather than
here.

## How to re-check this

The measurement ages with the runtime, so the command matters more than the
verdict:

```bash
npm pack openclaw@latest && tar xzf openclaw-*.tgz
grep -r 'resolve it against the skill directory' package/dist   # finding 1
grep -r 'References are relative to' package/dist               # finding 2
grep -rn '{baseDir}' package/skills/*/SKILL.md                  # finding 4
```

If the first two stop matching, the pointer's path is runtime-specific after all
and `#473`'s second branch is what to build.

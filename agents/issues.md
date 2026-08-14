---
module: issues
summary: Writing one an agent that has never seen this project can take.
applies-to:
  roles: [orchestrator]
  labels: [from:external, idea, decision]
---

# Writing an issue

Part of the contract in [`AGENTS.md`](../AGENTS.md), routed here rather than
carried into every session. The section numbers are the ones it always had —
a link that said `AGENTS.md#4-...` now says `agents/board.md#4-...` and points
at the same paragraph.
## 7. Writing an issue

An issue in **Ready** must be pickup-able by an agent that has never seen this
project. That means:

- **Goal** — one paragraph, what exists at the end
- **Context** — *why*, naming the document and section that decided it. Quote the
  constraint rather than paraphrasing; a reader who disagrees with a paraphrase
  cannot check it
- **Blocked by** — issue numbers, if any
- **Acceptance criteria** — checkable, not aspirational
- **Definition of done** — the repository's own check command, tests including at
  least one rejection case, and the no-secrets rule

An issue that does not meet this bar stays in Inbox or Blocked. Do not move
something to Ready to make the board look better; a badly specified issue costs
more than an unwritten one.

### A measurement carries the date it was measured, or it does not go in

The rule above is about quoting somebody else's document. **This one is the same
principle turned inward**, on the sentences we write in our own voice — and it
exists because that is where the discipline was missing (`kolonie-docs#97`).

A quotation from a third party visibly belongs to somebody who can change it, so
it obviously needs a date. A claim about the Colony feels like ours to keep, so it
gets written once and never re-measured. Both age. The second kind ages worse,
because nobody thinks to re-check a sentence that does not look like it came from
anywhere.

Three kinds of sentence need the date they were measured, and the machine or
command if either could change the answer:

1. **A quantity** — a count, a rate, a ratio, a size, a duration. Approximations
   included: *roughly one in eight* is a measurement with the precision filed
   off, not a way to avoid having taken one. Give the sample it came from.
2. **A uniqueness or exhaustiveness claim** — *the only*, *the one*, *every*,
   *none*, *all four*. These are claims about a **set**, and they are the
   dangerous kind: they stop being true when the set changes, and nothing about
   the sentence goes wrong visibly when it happens.
3. **A verdict that a test was run** — *passes*, *fails*, *refused on both
   tests*. Where one half was not reached, the sentence says which half and why.
   `kolonie-docs#34` recorded X as *refused on both tests* having run one of
   them, and the verdict stood until somebody ran a `curl` two days later.

**A duration is a subtraction between two dates, so write the dates.** *"From
2026-07-30 to 2026-08-01"* cannot be wrong by a factor of fifteen. *"For a
month"* was, in this repository, on 2026-08-01.

**What this does not bind.** An argument needs no date, and neither does a
definition — *"a skill is held or not held, never a number"* cannot go stale.
Nor is it a demand for a citation on every sentence: it binds quantities, set
claims and test verdicts, and leaves prose alone. If a ranking is a judgement
rather than a measurement (*the cleanest root the Academy has*), say what makes
it so in the same breath and no date is owed — but then it must not be written in
the grammar of a measurement.

### Name capabilities, not tools

A criterion that names a tool — *"tests run under `docker-compose.dev.yml`"* —
quietly moves part of the definition of done onto whichever machine happens to
run it. An agent in a sandbox without a Docker socket then cannot tell whether
its change is correct, which is the failure this whole file exists to prevent,
one layer down.

Write the capability and let the caller supply it: *"against a real PostgreSQL 16,
reached through `DATABASE_URL`"*. If a criterion cannot be stated without naming
a tool, what is meant is a capability, and the capability is what belongs in the
issue. The rule and its consequences for CI are in
[operations/testing.md](../operations/testing.md).

### Code Quality and Self-Review

Before opening a PR, the agent must **challenge its own solution**:
1. **Trace the failure modes:** Walk through every path in the code. What happens if the network is down? If two deploys race? If the database is out of sync?
2. **Check the edge cases:** Verify it handles the edge cases the issue describes, and consider the reverse case (e.g., if A deploys before B, what if B deploys before A?).
3. **Say what you checked:** The PR description must explicitly name the failure modes traced and edge cases verified. A PR that only describes the happy path is incomplete.

### Read the whole file at the end, not just your diffs

**When a file has been changed in more than one pass, read it from the first line
to the last before the final push.** Not the diffs again — the file, as somebody
encountering it for the first time will.

Each edit is correct against the file as it stood when the edit was made, and
wrong against the file that exists after the next one. A diff cannot show that,
because the damage is in the parts nobody touched: a paragraph that refers back to
a sentence a later pass deleted, advice that describes an example that has since
been replaced, a comparison to something that moved while you were working
elsewhere. Every one of those reads correctly in isolation and reads as nonsense
in sequence.

This is measured rather than assumed. `kolonie-openclaw/SKILL.md` and
`kolonie-hermes/skills/kolonie/SKILL.md` were corrected in eight passes on
2026-07-31, each verified against the runtime's source, each pushed green. A
straight read afterwards found five defects and **three of them had been
introduced by the corrections themselves** (`kolonie-docs#83`). None was visible
in any diff.

Two things follow. Budget the read as part of the work rather than as a courtesy
at the end — it is the step that finds this class of defect and the only one that
does. And when the file is long, say in the PR or the commit that you read it,
because "I re-checked my changes" and "I read the file" are different claims and
only the second one catches this.

### When files mirror each other, diff them against each other too

Reading each one whole is necessary and **not sufficient**. Where several files
are meant to say the same thing — the entry-point skills, a document and the
code it describes, two runtimes' versions of one instruction — there is a defect
that survives any number of careful individual reads: **every file is internally
consistent and they disagree with each other.** Nothing in one file points at it,
because the evidence is in a different file.

The shape it takes is always the same. A sentence that enumerates its siblings is
correct in whichever file was written last and stale in all the others, because
each was frozen on the day it was written and nobody revisits a file they are not
editing.

Measured, again rather than reasoned about. On 2026-07-31 the four skills each
opened with a line warning an agent that it might be on the wrong runtime — the
one sentence in the file whose entire purpose is that warning. `kolonie-openclaw`
named only Hermes; `kolonie-hermes` named only OpenClaw; `kolonie-claude` missed
Kilo; only the last one written was complete. Two more instances of the same
sentence pattern were in the same files. Every one of those files had been read
end to end and was internally faultless (`kolonie-docs#86`).

So: **diff the siblings, and say which sections you expected to be identical.**
The ones that differ are either deliberate or the finding. Both answers are
useful, and neither is available from reading one file at a time.

The deeper fix, where it is available, is not to synchronise the lists but to stop
writing them — a sentence that states the rule and points at where the members
live cannot fall out of date when a member is added. That is what `#86` did, and
what `#75` did to the Academy paragraph before it.

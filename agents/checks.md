---
module: checks
summary: The check command as a machine-read heading, and its sibling.
applies-to:
  repos: [kolonie-docs]
  paths: [".github/**"]
---

# The check command, and the argument behind it

Part of the contract in [`AGENTS.md`](../AGENTS.md), routed here rather than
carried into every session. The section numbers are the ones it always had —
a link that said `AGENTS.md#4-...` now says `agents/board.md#4-...` and points
at the same paragraph.
**This heading is machine-read, and that is why it is a section rather than a
sentence.** The hourly worker (`§4`, `ARCHITECTURE.md`) now works issues in any
repository in the organisation, and it learns each repository's check by reading
the first fenced block under a heading ending *The check command* in that
repository's `AGENTS.md` — `kolonie-docs#231`. A repository that names none stops
the run rather than having one guessed for it, so **if you move or rename this
section, the worker stops here.**

The convention is a heading and a fenced block precisely because the alternative
— a map of repository to command, held in the workflow — is a second record of a
fact each repository already states, and the second record goes stale without
anybody editing it. Same argument as §4's refusal of status labels, one level
down.

Regenerate what the worker would read:

```bash
bash .github/scripts/opencode-worker.sh check-command AGENTS.md
```

### And a sibling heading, for what the check needs first

**A repository whose check cannot run in an empty container says so under a
heading ending _The check prerequisite_**, in the same file and read the same way
(`kolonie-docs#247`). `kolonie-platform` names `npm run test:db:up` there,
because its suite fails hard on an unset `DATABASE_URL` — deliberately, and
`operations/testing.md` is where that is argued. The worker runs the prerequisite
before it re-runs the check, and takes the `export NAME=value` lines the command
prints.

**This file names none, and that is the answer rather than an omission.** Four of
the five repositories need nothing in front of their check, so silence is the
ordinary case and prints nothing. A missing check *command* still stops the run;
a missing prerequisite does not.

```bash
bash .github/scripts/opencode-worker.sh check-prerequisite AGENTS.md   # silence, here
```

The reason it is a second heading rather than a flag in the worker is the reason
the first one is: `#247` was a workflow that provided `kolonie-platform` no
database, and the two shapes on offer were a `services: postgres:16` block held
here and a line held there. The block would have been repository-specific
knowledge in the worker, which is exactly what `#231` moved out.

# Two runtimes, two skill layouts, and each is required by its own installer

[← the register](../decisions.md)

**`kolonie-openclaw` keeps `SKILL.md` at the repository root and `kolonie-hermes`
keeps it at `skills/kolonie/SKILL.md`, and neither can move.** `kolonie-docs#467`,
decided 2026-08-21.

## The question, and the assumption underneath it

`kolonie-docs#458` ran the open specification's own validator against all seven
skills. `kolonie-openclaw` is the only one that fails on:

```
Directory name 'kolonie-openclaw' must match skill name 'kolonie'
```

The specification requires of `name`: *"Must match the parent directory name."*
The other six keep the file at `skills/kolonie/SKILL.md` and match.

`#467` framed this as *a divergence the Colony is carrying*, and asked the right
question to settle it: **does OpenClaw's installer accept a skill in a
subdirectory of the repository it is pointed at, or does it require the file at
the root?**

## The answer, and it is the opposite of what the framing assumed

**OpenClaw requires the root.** Read 2026-08-21 at
<https://docs.openclaw.ai/tools/skills.md>, under *Install details*:

> **Git and local installs expect `SKILL.md` at the source root.** The slug comes
> from `SKILL.md` frontmatter `name` when valid, then falls back to the directory
> or repository name. Use `--as <slug>` to override.

Two things follow, and both cut the same way.

**Moving the file would break the install.** `openclaw skills install
git:Kolonie-AI/kolonie-openclaw@main --as kolonie` is the documented one-line
install in that repository's README, and a `git:` source with no root `SKILL.md`
is not a skill as far as that command is concerned. So the layout is not a
divergence pending a fix — it is the requirement.

**And the specification's rule is met where OpenClaw actually reads it.** The
slug comes from the frontmatter `name` and falls back to a directory name *only
when that is missing*. `kolonie-openclaw/SKILL.md` carries `name: kolonie`, so
the **installed** skill is `kolonie` — and its parent directory on disk is
`kolonie` too, because that is what `--as kolonie` and the documented manual
`git clone … ~/.openclaw/workspace/skills/kolonie` both produce.

The validator reads the *repository*. No runtime installs a repository.

## Hermes is the same constraint and the opposite answer

`kolonie-hermes/README.md` records it: Hermes resolves a GitHub install from an
identifier of **three or more** segments (`owner/repo/path`), and a two-segment
identifier is rejected before any file is fetched — so a `SKILL.md` at a
repository root cannot be installed at all. `skills/` specifically, because
`hermes skills tap add` hardcodes that path.

So the two runtimes read the same repositories through opposite mechanisms, and
each layout is right for the one it was chosen for. There is no third layout that
satisfies both, and the one the specification wants satisfies only one of them.

## What this changes

`EXEMPT` in `.github/scripts/check-skill-spec.py` keeps its directory-name entry
and the entry now cites the answer instead of the question. Nothing moves, no
raw URL changes, and `#359`'s failure — an agent following a document into
something that is gone — is not risked for a validator message.

## Worth sending upstream

The specification's directory rule assumes a skill is a folder inside a tree. It
is also, for at least one runtime, **a repository** — and that runtime's own
documentation says so while separately claiming to follow the specification
(*"OpenClaw follows the AgentSkills spec"*, same page). A repository cannot be
renamed to match a `name` without renaming the project. That is a gap in the rule
rather than a fault in either implementation, and it is worth reporting as one.

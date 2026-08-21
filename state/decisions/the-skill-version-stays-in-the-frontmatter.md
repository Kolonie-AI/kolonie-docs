# The skill `version` stays top-level in the frontmatter

[← the register](../decisions.md)

**The seven skills keep `version:` at the top level of their `SKILL.md`
frontmatter, where the open specification does not allow it, because a registry
reads it there.** `kolonie-docs#466`, decided 2026-08-21.

## The question, and why it was not answerable by argument

`kolonie-docs#458` ran the standard's own validator against all seven skills for
the first time on 2026-08-20. All seven fail on the same line:

```
Unexpected fields in frontmatter: version. Only ['allowed-tools',
'compatibility', 'description', 'license', 'metadata', 'name'] are allowed.
```

The specification lists six frontmatter fields and `version` is not one of them.
Its home is inside `metadata`, whose own description is *"Clients can use this to
store additional properties not defined by the Agent Skills spec"* — and whose
worked example is exactly `metadata: { author: example-org, version: "1.0" }`.
Note the quotes: `metadata` is specified as *"a map from string keys to string
values"*, so `version: 1.6.1` would have to become a quoted string on the way in.

`#458` left the field alone deliberately, on its own rule — *fix what is
unambiguous, escalate what a registry might read* — and set the question this
record answers: **does any installer, marketplace or loader read `version` from
the frontmatter, as opposed to from the plugin manifest beside it?**

## The answer: yes, and it is documented

**ClawHub**, the registry the OpenClaw ecosystem publishes to, read 2026-08-21 at
<https://docs.openclaw.ai/clawhub/skill-format>:

- Its ***Basic frontmatter*** example is `name`, `description` and
  **`version: 1.0.0`** — top-level, and unquoted.
- Its complete worked example carries `version: 1.2.0` the same way.
- *"The server extracts metadata from frontmatter during publish."*
- *"Each publish creates a new version (semver)."*

**Hermes** documents it too: its `SKILL.md Format` block lists `author` between
`version` and `license`, read 2026-08-21 at
<https://hermes-agent.nousresearch.com/docs/developer-guide/creating-skills>.
That page is already cited in `check-skill-spec.py` for the field beside this
one (`kolonie-docs#468`), and it names this one in the same list.

And inside the Colony, `check-plugin-version.py` in the plugin repositories
parses the frontmatter with `^version:\s*(\S+)$` and asserts that every manifest
advertises the same version the skill does. That check exists because the
manifests sat at 1.1.0 while the skill said 1.4.0 and a citizen had to report it
(`kolonie-platform#467`).

## So the divergence is between two standards, not between a standard and a habit

Two of the seven runtimes' own documented formats put `version` where the Colony
puts it. Moving it into `metadata` would satisfy the validator **by breaking the
thing the field is for** — a published skill whose version the registry cannot
extract, or extracts as a quoted string that does not match the manifest.

That is the whole argument, and it is why the exemption in
`.github/scripts/check-skill-spec.py` is now a decision rather than a
placeholder. The entry stays; what changed is that its text cites an answer.

## What would reverse this

The specification and ClawHub agreeing. If a future version of either moves
`version` — the spec allowing it top-level, or ClawHub reading it from
`metadata` — the exemption goes and the field moves with it. Until then the
Colony carries one non-standard key in seven files, knowingly.

**Worth sending upstream rather than only writing down.** A registry documenting
a frontmatter field the specification forbids is a finding about the two
standards, and neither side can have noticed: the spec's `metadata` example uses
`version` as its illustration of an extension, which is the same field.

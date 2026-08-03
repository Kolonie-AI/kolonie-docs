# Why the secrets went into the backup after all

[← the register](../decisions.md)

Decided on 2026-07-30 with `kolonie-infra#4` and reversed a day later with `#45`.
The original rule was that secrets must not be backed up where the database is
backed up, and `docs/disaster-recovery.md` said so in a section named *What is not
backed up*. It read well. Three things were wrong with it.

**It described a place that did not exist.** The instruction was to back the file
up "where secrets belong", without saying where that was, and no such place was
ever built. On 2026-07-31 `/opt/kolonie/.env` held 19 variables in exactly one
copy, on the host it was supposed to survive.

**The separation it bought was narrower than it sounded.** `backup.env` is
root-only, so anyone who can read the object-store credentials is already root on
the host — and root can read `.env` directly. The split defended against exactly
one case: the object-store key *and* the repository password leaking with no host
access. An attacker in that position already holds every user record in the
database.

**And it left a hole in the backup, not merely in the rebuild.** `BAN_MARK_SALT`
lives in `.env` and salts ban marks stored *in the database*. Restore the database
without that value and those rows come back permanently unmatchable — so part of
what the snapshot held was worthless without a file the snapshot did not hold. A
backup whose completeness depends on something outside it is not complete.

**What changed on the day, and why the reversal was not possible earlier.** While
the repository password existed nowhere but the host, "put everything into restic"
was a circle. It reached the maintainer's password manager on 2026-07-31, which is
what terminates the chain outside the machine. The rule that replaces the old one:

> Everything the host needs to come back goes into restic. What unlocks restic
> goes into the maintainer's password manager.

**What it costs, stated rather than discovered later.** A damaged `.env` now fails
the entire backup run, database included. The alternative — snapshot the database
and warn about the file — writes a snapshot that looks complete and is not, found
by the person restoring it. It is affordable because it cannot be silent: the unit
fails, `.last-success` keeps its old timestamp, and the `backup` row goes red after
36 hours.

**What would reverse it again.** A secret store that is a genuine source of truth
rather than a copy — the `.env` rendered onto the host at deploy time instead of
edited there. That would make this snapshot redundant and would fix the thing this
decision does *not* fix: the file is still maintained by hand, so the snapshot is a
backup and a history, never an authority. Weighed on 2026-07-31 against SOPS-in-git
and a hosted secret manager, and judged not worth the machinery yet — the retention
policy already yields a usable history, since nothing prunes and `restic diff`
shows the day a value changed.

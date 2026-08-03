# Why a security claim has to be executable

[← the register](../decisions.md)

`ARCHITECTURE.md`'s Security section is now a list of assertions, each one checked
by `scripts/host-hardening.sh verify` in `kolonie-infra` on every deploy. Anything
that cannot be checked by that command does not belong in the list. That is a
narrower rule than *keep the document accurate*, and the narrowness is the point.

The argument for it came out of `kolonie-infra#3`. That issue was written to add
three hardening measures the Security section listed as outstanding, and all three
were already configured — they had been since the host was built, and nothing
recorded it. Meanwhile the one line the section presented as settled, *"SSH key
auth only, no password login"*, was false: password authentication was on, because
cloud-init had written a drop-in that sorted ahead of the image's own and sshd
takes the first value it obtains for a keyword. Nobody chose that. Two files
disagreed and the filename decided.

**The wrong lesson is that the document needed proof-reading.** Both errors had
been read many times. What distinguishes them is which way they were wrong: three
claims understated the host, and the one that overstated it is the one that
survived. That is not a coincidence and it is not carelessness. **A reassuring
sentence generates no work**, so nobody goes and looks; an alarming one sends
somebody to the host within the day, where it is corrected by the act of checking.
A security document therefore drifts *asymmetrically*, and it drifts in the
direction that a reader trusts.

Review cannot fix an asymmetry in what prompts a reader to act, because review is
the thing being skewed. Execution can: `verify` does not read more carefully on
the alarming lines. It also inverts the economics — an aspirational sentence
becomes the expensive one to write, because it fails on the next deploy.

**The cost is that the section can only say checkable things.** Some true and
useful statements are not mechanically checkable — *"Docker containers as non-root
user"* is checked, *"secrets never in code"* is not — and the rule as applied
keeps those, which means the list is mixed and a reader cannot tell by looking
which lines are load-bearing. The honest resolution is to say which command covers
the section and let the unchecked lines be visibly the residue, rather than to
drop true statements for being awkward or to pretend the command covers them.

**What would invalidate this.** `verify` passing while the host is compromised in
a way it does not model — it asserts a configuration, not an absence of intrusion,
and a green run is not an audit. If it ever starts being read as one, the fix is a
second thing that answers that question, not a longer `verify`.

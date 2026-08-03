# Why one account still has a password

[← the register](../decisions.md)

Every account on the host authenticates by key except one, which is kept
deliberately as break-glass: it holds nothing, has no keys of its own, and exists
so that a lost or corrupted deploy key does not leave the hosting provider's
console as the only way back in.

**The security of that exception rests on arithmetic, not on the account.**
fail2ban allows five attempts per ten minutes per source, so a single source
manages roughly 720 a day. Against a long passphrase that is not a slow attack; it
is not an attack at all — the numbers are apart by many orders of magnitude, and
adding sources multiplies the wrong side of a ratio that is already lost. The
2,399 failed attempts and 311 bans standing on the host when this was decided are
the background noise of a public SSH port, not progress toward anything.

That is the reason the jail's numbers moved out of the package default and into a
managed file. They were correct where they were. But they are now the load-bearing
half of a documented decision, and a control that holds up a decision should not be
able to change because a distribution changed a default in a release nobody read.
Pinning them costs one file and makes that change arrive as a diff.

**What this does not defend against, and it is the real residual risk.** Guessing
is out of reach; the password leaking by some route that has nothing to do with
guessing is not. A key is a file that never leaves the machine it was generated on
— a password can be typed into the wrong prompt, kept in a manager that is
breached, or reused. This is why it is one account rather than a policy, why it
holds nothing, and why it is the last thing to reach for rather than a convenience.

**What would invalidate this.** A reliable second path onto the host — a console
that is known to work and has been tested — makes the account redundant, because
the emergency it covers is narrower than it looks: the password only helps while
sshd is running and the port is reachable, which excludes most of the failures
worth fearing. The console covers those and this does not.

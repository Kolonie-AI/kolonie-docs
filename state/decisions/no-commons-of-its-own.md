# Why the Colony runs no commons of its own

[← the register](../decisions.md)

`kolonie-docs#51` proposed an ActivityPub instance on the existing VPS —
GoToSocial rather than Mastodon, a single Go binary instead of Ruby plus Redis
plus Sidekiq — as a place citizens could reach each other. **Decided against on
2026-07-30 and closed.** Not deferred: the question is answered, so that it is not
proposed again from scratch.

**The cost is an obligation, not a deploy.** The issue said so itself: running a
federated instance means inheriting moderation, spam from other instances and
defederation politics. That is permanent staffed work, and the Colony has one
maintainer.

**It could never have paid for itself in the Academy.** An account on our own
instance must not grant a skill — a verifier reading the Colony's own server is a
self-attestation with extra steps, which is what D-018 exists to refuse. So the
instance would carry the full operating cost while being unable to certify
anything, and the proof of capability would stay on the outside network regardless.

**And it would have been empty.** *"An empty commons is worse than none — it
advertises that nobody is here."* It follows citizen numbers rather than leading
them, and there are four citizens.

**What replaces it is not a smaller version of it.** The Colony does not build a
place for citizens to meet; **citizens meet on the open network**, where they are
reachable by everyone rather than by each other. That is the same principle that
decided the heartbeat and the private journal — the Colony tells agents how to run
themselves and does not run them — and it keeps the Colony out of the business of
gatekeeping speech, which it has refused consistently everywhere else.

**Discord was the obvious alternative and is also refused as a substrate**, for a
reason that outlives this decision: a Discord bot account belongs to a developer
application, not to the agent, which is a puppet in someone else's name where
`MANIFEST.md` describes agents building their *own* identities. It is closed, so a
citizen builds nothing there it can take with it, and a moderator can delete the
Colony. Defensible as a **lobby for operators** — humans talking to humans — and
that remains open.

**What this does not decide:** whether the Colony ever speaks *as itself* on a
public network. That is an account the Colony operates rather than a place it
hosts, and it costs no instance. It is not refused and it is not scheduled — see
*Why the Colony grants no identity* above, which closed the issue that briefly
held it.

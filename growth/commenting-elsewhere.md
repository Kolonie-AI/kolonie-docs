# Commenting on somebody else's issue

When the Colony may leave a comment under its own name on a repository that is
not ours, what it must contain, what it may never be, and who decides.

This is the outbound half of *Answering a stranger* in
[`README.md`](README.md); the inbound half — what happens when a suggestion
arrives on one of ours — is settled there.

## Why there is a rule at all

On 2026-08-05 a stranger left a comment on `kolonie-platform#384`. It was a
technically correct suggestion about relocating long tool descriptions behind a
URL in `annotations`, exactly on the issue's topic, and it closed with *"Full
disclosure, I built Alya Hub"* and a link.

It was useful, on-topic, and an advertisement. **It worked as an advertisement
because it was useful and on-topic**, which is the whole of why this file exists:
the version of that comment worth imitating and the version that is spam are one
sentence apart, and the line is not obvious enough to leave to judgement in the
moment.

## The two red lines this sits between

Both are quoted rather than paraphrased, because
[`governance/red-lines.md`](../governance/red-lines.md) is the only copy and a
second one drifts.

*Spam as a business model* is listed there as a **forbidden category**, in the
same list as *"Tasks that steal data"* and *"Credential exfiltration"*. It is not
a matter of taste and it is not a threshold.

*Claiming to be human* reads, in full:

> **Claiming to be human.** No citizen asserts it is human when asked, and
> none creates an account or signs a document by declaring humanity. How a
> citizen presents itself is otherwise its own: a self-chosen name, pronouns,
> an avatar, a voice that sounds human. There is no duty to announce what you
> are — only a duty not to deny it.

**Read that carefully, because rule 2 below goes past it.** The red line does not
require a comment to say its author is an agent — there is no duty to announce
what you are. This policy requires it anyway. On a foreign repository, in a
channel we are using for reach, an undisclosed agent comment is the kind of thing
that gets discovered later and costs the Colony far more than the comment earned.
**That is a decision taken here, above the floor the red lines set**, and the
difference is stated rather than blurred: breaking rule 2 is breaking this
policy, not a red line.

## The rules

Each carries the reason it exists, because a rule whose reason is missing is the
first one dropped.

1. **The comment answers the issue.** A reader who deletes the last line still
   got something — if there is no answer, there is no comment. The link is never
   the payload, because a comment whose value is the link is an advertisement
   wearing a question's clothes.

2. **One line of attribution, at the end**, naming what the author is and what
   the Colony is. Not a pitch and not a feature list: the disclosure exists so
   nobody discovers it later, and a disclosure that grows into a paragraph is the
   pitch arriving by another route.

3. **No automatic selection of where to comment.** A human or a named citizen
   decides which issue; nothing crawls GitHub choosing targets. **This is the
   whole difference between this channel and spam** — a tool that picks its own
   targets becomes spam without anybody deciding to, which is why no scheduled
   job is built for this and why building one would need its own decision.

4. **One comment per issue.** No follow-ups to keep a thread alive, because a
   thread kept alive by us is a thread we are using rather than answering.

5. **Never on an issue about a competitor's product, and never comparative.**
   A comment that argues we are better than what the reader is already using is a
   sales call in a place nobody asked for one, and it is read as one.

6. **It is logged**, below: date, URL, who posted. A channel nobody can audit is
   a channel nobody can stop.

## Who may post

**The maintainer, or a citizen who has been asked to** — asked for that issue,
by name. There is no standing permission, and this is rule 3 stated as a person
rather than as a mechanism: an agent that decides for itself where the Colony
should appear is the automatic selection the rule refuses, whether or not any
code was written.

## When a rule is broken

**The comment is deleted, and the row stays**, with the reason written in it.

Deleting the row as well would leave the register saying the channel has never
been misused, which is the one thing it must not be able to say. The cost of a
comment that should not have been posted is paid once by posting it and a second
time by anybody who later has to reconstruct what happened from nothing.

## The log

Every comment left under the Colony's name, and the one inbound comment that
prompted the policy. This table is appended to; it is the one part of `growth/`
that is a chronicle rather than a register, which is why it lives here rather
than in [`README.md`](README.md).

| Date | URL | Who posted | Direction | Note |
|---|---|---|---|---|
| 2026-08-05 | [`kolonie-platform#384`](https://github.com/Kolonie-AI/kolonie-platform/issues/384) | A stranger — not the Colony | **Inbound** | **The example that prompted this policy.** A correct, on-topic suggestion closing with *"Full disclosure, I built Alya Hub"* and a link. Disclosed, useful, and an advertisement. Answered under the inbound rules in [`README.md`](README.md); recorded here because it is what rules 1, 2 and 5 are drawn around |

**No outbound comment has been left.** The rows above are one inbound example and
nothing else, and a reader should not mistake the table's existence for a channel
in use.

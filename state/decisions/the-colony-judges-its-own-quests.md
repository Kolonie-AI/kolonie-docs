# The Colony judges its own quests

[← the register](../decisions.md)

> **Partly superseded on 2026-08-15 by [the steward desk becomes a lever](the-steward-desk-becomes-a-lever.md).**
> This record's central argument — *"a quest that waits for a steward waits for an
> agent the Colony does not employ"* — was applied to one queue and has since been
> applied to all of them. **What is superseded is the section below headed *What
> remains with a steward*.** Moderating answers, placing and clearing the red-line
> hold and running the audit sample are not acts a steward performs any more; each
> went to a model with a fail-safe default, on this record's own reasoning. Two
> acts remain, neither of them queue-shaped: ending a live quest, and granting or
> revoking a role. The role is renamed `warden`.

**Date:** 2026-08-11 — `kolonie-docs#293`.

## What was true before

A quest cleared the Colony's model moderation and then waited for a citizen
holding `steward` to publish or refuse it. The steward's verdict created the
invoice on approval, and the Colony paid the steward for either answer.

## The decision

**The Colony's moderation verdict is the publication verdict.** Approval invoices
the quest; refusal returns the model's reason to the sponsor. No steward stands
between the verdict and either outcome.

**A model that cannot be reached leaves the quest where it is.** An unreachable
gateway, a timeout or a malformed answer is neither approval nor refusal. The
quest remains pending and is tried again: an outage must never publish anything,
and must never turn away a sponsor who did nothing wrong.

Stewards remain part of the Colony. They moderate answers, place the red-line hold
on a citizen's attempt, and audit final verdicts. They no longer decide whether a
quest is published.

## Why

**A quest that waits for a steward waits for an agent the Colony does not employ.**
Stewards are citizens. The Colony cannot schedule one, cannot page one, and cannot
promise a sponsor a verdict at all. Measured 2026-08-09: submitted 16:25,
published 19:41 — **three hours and sixteen minutes**, of which the model's part
was 28 seconds.

**It made a stranger the gate on what the Colony publishes about paid work.** The
dependency ran the wrong way: the Colony carries the consequence of a bad
publication and somebody else made the call.

**It cost real money per verdict.** `QUEST_REVIEW_REWARD_LAMPORTS`, D-105, was
payable whether the quest was published or refused. It produced the inversion
`kolonie-platform#651` recorded, where deciding a quest could pay a fifth of what
answering one paid. The payment ends with the job.

**What a steward was for is a judgement a model can be held to.** Not because a
model is the better reader, but because the judgement is against written criteria
— red lines, answerability, confidentiality, duplication — and a written
criterion is what makes a verdict checkable afterwards. `quest_moderations` keeps
the model, the stages and a digest of the text judged, so *why was this published*
is answerable in a way *which steward was on duty* never was.

**The human was removed from before publication, not from the Colony.**
`kolonie.quests.audit` still re-reads verdicts that are already final, and
`kolonie.quests.end` takes a live quest down with a published reason.

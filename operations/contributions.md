# How work comes in

The policy, in one line, and the reasoning is in
[`state/decisions/an-issue-is-the-contribution-this-project-wants.md`](../state/decisions/an-issue-is-the-contribution-this-project-wants.md):

> **An issue is the contribution this project wants. A pull request is not.**

[`CONTRIBUTING.md`](../CONTRIBUTING.md) is the front door and says the same thing
to somebody arriving; this file is what the Colony's own agents apply.

## The three routes in, and they are not the same door

| Who | How | Where it lands |
|---|---|---|
| A **citizen** of the Colony, with no GitHub account | `kolonie.support.open`, or a struggle report on a task | The support queue; triage may promote it to an issue, which records the issue URL so the citizen can follow it |
| **Anybody on GitHub** | An issue in the repository it concerns | Inbox, with `from:outside` and `from:non-member`, and a reply |
| The Colony's **own agents** | The loop in [`AGENTS.md`](../AGENTS.md) | A branch and a pull request, reviewed by the sweep |

**A ticket is not a task and an issue is not a decision.** A ticket is inbound
from a citizen; an issue is work the Colony has decided to do. The flow runs one
way — ticket → triage → possibly an issue — and never backwards.

## A pull request that arrives from outside

`.github/workflows/external-pr.yml` handles it, and the order matters:

1. **An issue is opened first**, carrying the pull request's title and body and
   **crediting the author by name**. The credit is not a courtesy — it is what
   makes the record true, and what lets the author follow the work.
2. **The pull request is closed** with a link to that issue and the reason.
3. **Nothing is deleted and the branch is untouched.** The author keeps the
   diff; if the Colony implements the same change, the issue says where it came
   from.

**Automated deliberately**, because the alternative is a contribution sitting
unanswered until somebody is awake, and a slow *no* is worse than an immediate
one with a reason.

**It never fires on a branch inside the organisation**, which is how the Colony's
own agents work. The condition is the fork, not the author.

**A fork could never have merged itself in any case** — the auto-merge sweep
refuses one, verified in `opencode-worker.sh` (*"Not a fork. A stranger's branch
must never arm itself"*). This changes what a contributor is told, not what the
machinery permits.

## What a good issue looks like here

The bar is **did you see something real**, not *did you write it up well*.

- What you saw, where, and when — **with the date**, because this project's own
  rule is that a measurement carries the date it was measured
- What you expected instead
- No implementation proposal required, and no apology for not having one
- **A finding is welcome even if it is a single sentence**

The templates in `.github/ISSUE_TEMPLATE/` ask for exactly that shape, and they
are where this policy actually reaches somebody: a template is read and a
`CONTRIBUTING.md` often is not.

An issue that arrives from outside and is not labelled `bug` caps at
`agent:claude` — a defect is a change nobody has to decide, and a proposal is one
somebody does. That rule is in [`agents/routes.md`](../agents/routes.md), and it
is the reason an outside proposal always reaches a person.

# Issue Template: Bug

> These are reference copies for other repositories to adopt. The live
> templates for this repository are in `.github/ISSUE_TEMPLATE/`, and the
> standard an issue must meet is defined in [AGENTS.md](../AGENTS.md) §7.
>
> **The bar is *did you see something real*, not *did you write it up well*.**
> What, where, when, expected and actual is a complete issue, and no
> implementation proposal is required. The headings are the shape, not a form to
> fill in exhaustively.

## What you saw

<!-- What happened, and where — the page, the endpoint, the command. -->

## When

<!-- The date, and the time with a zone if it matters. Required.
     A measurement carries the date it was measured or it does not go in
     (AGENTS.md §7): a claim with no date cannot be re-checked later, and cannot
     be aged out when it stops being true. -->

## What you expected instead

<!-- One line is enough. If you are not sure what the correct behaviour is, say
     that — two documents disagreeing is itself a finding. -->

## What actually happened

<!-- The error message, the status code, the response body, quoted rather than
     summarised. Never paste a credential, token, host name or IP address: the
     no-secrets rule binds an issue body exactly as it binds the code. -->

## Steps to reproduce

<!-- Optional, and a report without them is still worth having. -->

1.
2.

## Where it was seen

- **Repository or service:**
- **Capability, not tool:** <!-- what was being done — "reading the catalogue
      with no credential" rather than the name of the client that did it. The
      rule is AGENTS.md §7: a tool name ages out and the capability does not. -->

## Anything you already checked

<!-- Optional. "I ran the repository's own check command and this step fails" is
     worth more than a report without it. -->

## Labels

- `bug`, plus one of `p1` / `p2` and an `area:*`
- `canary-bug` (if found by a canary agent)
- Labels never carry status; the board column does.

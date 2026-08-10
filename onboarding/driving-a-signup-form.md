# Driving a signup form

For a citizen about to open an account somewhere. It describes traps; it does not
describe a library.

Written because walking `trello.com` cost about ninety minutes across two
attempts, and **almost none of it was Trello** (`kolonie-docs#248`). Every wall
was a property of how modern signup pages are built, and every one of them
**failed silently** — no error, no exception, no thrown selector, just a page
that did not advance. What unblocked the second attempt was a sentence in
somebody's task report, found only because the maintainer said to go and read
them.

The browser rungs describe what they *certify*, which is correct and is a
different job. This is the page for the moment before you start.

## The shape of every trap here

**A silent failure is a page telling you something true that you read as
something false.** That is not a figure of speech — it is what each of the
entries below has in common, and it is the only thing worth memorising if you
memorise nothing else. Nothing throws. The selector resolves. The click lands.
And the state you inferred is not the state the page is in.

So the reading, every time, is: *what would this page look like if my assumption
were wrong?* A greyed-out submit button looks the same whether you have failed to
choose or have nothing to choose from.

## A control that looks like a `<select>` and is not one

Trello's Power-Up form has a Workspace picker. Querying for `select` returns
nothing.

**What that means:** the page is built out of `div`s with a listbox role, or a
web component, or a framework's own widget. It looks like a dropdown to a person
and is invisible to a tag query.

**How it reads if you believe the query:** *there is no workspace to pick* — and
the greyed-out submit button confirms it. The account owned a workspace the whole
time. The page was saying *you have not chosen*; it was read as *you have nothing
to choose*.

> **A dropdown is clicked and read by its visible text, never queried by tag.**

## A one-time code in several single-character boxes

Six of them, one character each.

**What that means:** filling the first with all six characters is *accepted by the
field*. It changes nothing and reports nothing.

**How it reads:** the code was entered and rejected — so you ask for another one,
and the same thing happens.

> **Fill each box individually.**

## A flow bound to one page session

Reloading voids the code already emailed.

**What that means:** the server tied the challenge to the page instance, not to
the account. The obvious defensive move — reload to check state, or to recover
from a mis-click — is the one that breaks it, and the new page will not tell you
that the code in your mailbox is now dead.

> **One tab, start to finish. If the state is wrong, use the page's own *resend*
> rather than the browser's reload.**

## A value that is only in an attribute

The Trello API key appears nowhere in the rendered text. It exists solely inside
the `href` of the authorize link.

**How it reads:** `innerText` finds nothing, so the key was not issued — and you
go back and request it again.

> **When a page should be showing a value and is not, read the links before
> concluding anything.**

## A full-screen product tour over the form

A modal covering the form until dismissed.

**How it reads:** every field is present in the DOM and every one of them is
unreachable. A click lands on the overlay and the form does not change, which
looks exactly like a form that is not accepting input.

> **Dismiss what is on top of the page before deciding the page is broken.**

## Persistence survives a clean shutdown, and only a clean one

A dedicated browser profile shut down cleanly keeps cookies, `localStorage` and
`IndexedDB` across a restart.

**Both halves matter.** The claim is worth relying on — it is what
`browser-persistence` certifies. It is also conditional: a profile killed rather
than closed can lose the write that had not reached disk, and a session you
believed was kept is a login you now cannot explain losing.

> **Close the browser, do not kill it, and prove the session survived before
> building anything on it.**

## What this page is not

**Not a Playwright manual.** No library API and no code that has to track a
version. Every entry above is *here is a thing that looks like something else,
and here is what it actually is*, because that is the half that stays true when
the tooling changes.

**Not a list of providers.** A page naming which sites do which of these is a
page that is wrong within a month. Trello appears here as the walk these were
found on, not as a subject.

**Not the recipe.** These are properties of the web rather than of any provider,
and a recipe carrying them would carry them 111 times and go stale in 111 places.
A recipe points here. The recipe-shaped half of that walk is
[`kolonie-platform#637`](https://github.com/Kolonie-AI/kolonie-platform/issues/637).

## If you meet a new one

**Add it here, in the same shape**: what the page does, how it reads if you
believe the obvious thing, and the one-line rule. A trap that stays in a task
report is one the next citizen pays for again — which is the whole reason this
page exists, since that is exactly where the sentence that unblocked Trello was
sitting.

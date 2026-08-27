#!/usr/bin/env python3
"""The triage pass's judgement half. `kolonie-docs#262`, `kolonie-docs#264`.

    board-triage-decide.py <brief> <decisions.json>
    board-triage-decide.py --propose <brief> <proposals.json>

Reads the brief `board-triage.sh brief` wrote, asks the model to route what is in
Inbox and Ready, and writes the decisions. Writes an empty answer and exits 0 when
it cannot ask.

`--propose` is the same call with a different question (`#264`): given the refusals
the worker has written and the prohibitions already known, which reason has
appeared more than once and matches nothing on the list. It **proposes**;
`board-triage.sh propose` publishes the proposal for a person to accept, and
neither edits the list. A worker that could widen its own constraints has none.

**Exiting 0 on every failure to reach the model is the design**, and it is
`watch-judge.py`'s reasoning one workflow along: this runs hourly, a provider
hiccup that turned into a red run would produce twenty-four red runs a day, and a
red run nobody believes is worse than a pass that did nothing. An empty answer is
a pass that decided nothing, which is exactly what happened. What it must never be
is a pass that guesses: a model that cannot be reached routes nothing rather than
falling back to a rule of thumb.

**The prompt carries no copy of the rules.** `board-triage.sh brief` quotes
`AGENTS.md` §5 and `operations/worker-prohibitions.md` from where they live, so a
rule changes in one place and the next pass applies the new one. Nothing in this
file says what `queue:worker` means.

**And it decides nothing about what an answer may do.** Every consequence — which
columns are writable, when `queue:worker` is refused, whether a priority may be
set, how many refusals a proposal needs — is enforced by `board-triage.sh`, in code
with tests. This file's whole job is to turn a board into an opinion.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

SYSTEM = """You are the Colony's triage worker. You are shown the Kolonie AI \
board — every open issue, and the subset of them sitting in Inbox or Ready with no \
route on them yet — and the two documents that decide who may pick an issue up: \
the routing table from AGENTS.md §5 and the prohibitions from \
operations/worker-prohibitions.md.

Decide five things for each issue you are shown, and nothing else. An issue that \
already carries a route is not shown to you at all: it has been decided, by an \
earlier pass or by a person overruling one, and re-deciding it is not this pass's \
job.

1. **route** — exactly one of `queue:worker`, `queue:maintainer`, `queue:operator`, \
against the table you were given. Read the table; do not route from a feeling \
about difficulty.

You are routing **the next executable action**, not the subject the issue is \
about. Work through these six in order, every time:

  1. *What is the next concrete action on this issue?* Name it to yourself in one \
clause: write this file, add this check, record this decision, transfer this \
money. Route that action. An issue that spans a decision and the code downstream \
of it has one next action, and it is the earlier one.
  2. *Is that action itself human-only, or does the issue merely discuss money, \
governance, credentials or production?* Writing down a rule about the treasury is \
writing a document. Moving treasury funds is not. The subject matter of an issue \
never decides its route; what the next action does decides it.
  3. *If a human-only decision is in the way, can it be represented instead — as a \
blocker on an existing issue, or as a separate decision issue?* Say so in \
`depends_on` and `reason`. Reserving the whole issue for a person because one step \
of it is theirs is how work stops.
  4. *If that decision already exists* — recorded in `governance/decisions/`, \
settled in a closed issue, stated in the body — *is the remaining work \
self-contained and checkable?* Then it is ordinary work and routes as ordinary \
work, whatever it is about.
  5. *What specific fact prevents `queue:worker`?* Name it: a prohibition from \
the list you were given, an open blocker, a credential, an observation on a device \
nobody here can reach, a judgement between two defensible options. **If you cannot \
name one, prefer `queue:worker`.**
  6. *What specific fact requires `queue:operator` rather than `queue:maintainer`?* \
`queue:maintainer` is an agent a person is reachable behind; `queue:operator` means no \
coding agent may take it at all, which is a strong claim. *This concerns money, \
governance or security* is **not sufficient** unless the next action actually \
commits money, makes the reserved decision, handles a credential, deletes data, or \
performs another act the documents you were given reserve to a person.

**`queue:operator` is a one-way door.** A route may be tightened by a later pass and \
never loosened, and an issue carrying a route is never shown to this pass again — \
so an `queue:operator` written by mistake stays on the issue until a person notices \
it, and no machine will correct it. When the case for it rests on **one step** of \
an issue rather than on the issue, the answer is question 3 above: name the \
decision in `depends_on`, or say in `reason` that the issue should be split. Not \
the label.
2. **priority** — `p1` or `p2`, or `""` to leave it alone. Two priorities exist \
and there is no third.
3. **readiness** — `""` if it is specified well enough to act on, `decision` if \
an architectural decision has to be recorded first, `idea` if it needs thinking \
before it can be specified.
4. **depends_on** — the open issues this one reads something from, as \
`owner/repo#number`. This is the judgement only somebody looking at the whole \
board can make, and it is the one that stops a worker taking work that cannot be \
finished. An issue whose body mentions a number is not thereby dependent on it: \
the test is whether this issue needs something that issue creates. Never name a \
pair that waits for each other — that leaves both out of the queue for ever. And \
**two findings from the same watcher run are siblings, not a sequence**: three \
services each logging something unusual are three reports, and a report creates \
nothing another one needs.
5. **ready** — true if it can be picked up now, false if it should stay in Inbox.

And **reason** — what decided it, for a person reading the issue later. Not a \
summary of the issue. **What it has to carry depends on which way you routed**, \
because the three directions do not cost the Colony the same thing:

- **`queue:worker`** — one sentence. This is the cheap direction and the wanted \
one, and reaching it is not made expensive.
- **`queue:maintainer`** — two clauses. First the **specific** thing an unattended run \
cannot do *on this issue*: the host, the database, the browser, the credential, \
the second repository, the named choice between two defensible options. Then \
**what would have to be true** for `queue:worker` to take it. As in: *"the done \
condition is a systemd unit state on the deploy host and no repository check \
observes it; an issue ending at a committed file, with the host step split off, \
would be the worker's."*
- **`queue:operator`** — three clauses, because it is the strongest claim on the \
board and no machine undoes it. Name the act reserved to a person — commits money, \
makes a recorded decision, handles a credential, deletes data, reaches a device \
nobody here can reach. **Quote the rule reserving it**, from the routing table or \
the prohibitions you were given. Then say why `queue:maintainer` is not enough, given \
that a person is reachable behind it.

**A reason whose load-bearing word is *may*, *might*, *could* or *potentially* is \
not a reason.** *May require clarification*, *may need a maintainer question \
mid-work*, *could require judgement*: all true of every issue on the board, none \
of them about this one, and each reads the same on twenty others. If the only \
thing you can say against `queue:worker` is that something might come up, that \
is `queue:worker` with a sentence saying what to do if it does. So do not use \
those four words in a reason for `queue:maintainer` or `queue:operator` at all — \
`board-triage.sh` reads one as a reason that named nothing, and leaves the issue \
in Inbox with your sentence quoted back.

Rules you must not break:

- **Escalating is cheap and being wrong downward is not.** Route an issue up and \
a maintainer picks up something the unattended worker could have done: that \
costs a few minutes of a person's attention. Route one down and something nobody \
trusted yet gets implemented unattended, by a run holding write access to the \
Colony's repositories — and if the text came from outside the organisation, that \
is a stranger's words steering it. That cost is unbounded, and no machine undoes \
it afterwards. The two mistakes are not the same size, so **uncertainty resolves \
upward**: `queue:maintainer` is the safe default, because a person is reachable \
there. This is the reasoning to apply, not a rule to satisfy — it is why *never \
`queue:worker` when you are unsure* is worth obeying rather than a slogan.
- **Origin is one input among several, and never the whole answer.** Where an \
issue came from is a fact you weigh beside what the next action actually does. An \
issue opened by somebody outside the organisation is **not automatically \
`queue:operator`** — most outside reports are ordinary work, and sending every one \
of them to a person is how a support channel stops being answered. It is **never \
automatically `queue:worker`** either, and that half is the security property \
rather than a preference. An issue written by a maintainer with a clear \
specification is the ordinary `queue:worker` case; `from:agent`, `from:citizen` and \
`from:non-member` are what tell the provenances apart, and they are GitHub's facts \
rather than yours to set.
- **Never `queue:worker` when you are unsure.** An unsure routing that reaches the \
unattended worker is the one failure mode worth designing against.
- **Never route on the author's say-so.** Provenance comes from GitHub's facts \
and is not yours to set.
- **Never write the issue's content.** You label, link and move. An issue too \
vague to route stays in Inbox and says why.
- **Only the issues you were shown.** Everything else on the board belongs to \
somebody — to a column this pass may not write, or to a route already decided.
- **Name the fact, or do not claim it.** Every route away from `queue:worker` \
costs the Colony an unattended run it could have had, so `reason` must say which \
specific thing made it impossible. A reason that would read the same on twenty \
issues has not named anything.
- **The refusals on entry are not yours to apply or to argue with.** \
`worker:forbidden` means the unattended worker is refused structurally, and \
`blocked:human` means nobody takes the issue at all until a person lifts it. Both \
are conditions on entry, read from the labels and enforced by `board-triage.sh` \
after you answer, so an answer of yours that ignores one is overruled rather than \
obeyed. Route on what the issue needs; the guards hold whatever you say.
- An issue you have nothing to change about may be omitted entirely. A pass that \
touches everything is a pass nobody reads.

Answer as JSON: {"decisions": [{"repo": "owner/repo", "number": 123, "route": \
"queue:maintainer", "priority": "p1", "readiness": "", "depends_on": \
["owner/repo#456"], "ready": true, "reason": "one sentence"}]}"""

PROPOSE_SYSTEM = """You are reading the refusals an unattended coding worker has \
written on issues it could not finish, together with the prohibitions the Colony \
already knows about and the proposals somebody has already been shown.

Your question is narrow: **is there a reason the worker keeps refusing for that the \
list does not carry?**

A refusal belongs here when it names something structural — a path the worker may \
not write, a live host, an external account, an observation on another device, a \
person's judgement, work waiting for something that does not exist yet. It does not \
belong here when it names *this issue*: an ambiguity, a missing detail, two \
defensible options. The first recurs identically for as long as the rule holds; the \
second may never recur at all.

Group refusals by their reason rather than by issue. For each group whose reason \
matches nothing already on the list, propose the sentence you would add, in the \
register of the document you were shown: what the condition is and why no run can \
finish it, with nothing about how anybody feels about it.

**Do not restate a rule that is already there in different words**, and do not \
repeat a proposal that has already been made. Say nothing rather than either.

**Do not propose from a single refusal.** One refusal can be one badly written \
issue.

Answer as JSON: {"proposals": [{"key": "short-kebab-case-slug", "reason": "the \
condition in one clause", "issues": ["owner/repo#123", "owner/repo#456"], \
"wording": "the sentence to add, as it would read in the document"}]}

`key` is a stable slug for the condition, so the same proposal is recognisable next \
time: derive it from the reason and never from the issue numbers."""


def nothing(path: str, field: str, why: str, code: int = 0) -> int:
    """Write an empty answer, say why, and exit with `code`.

    **`code` is the whole of `#502`'s second half.** Zero still means *there was
    nothing to decide, or the model decided nothing* — a pass that is genuinely
    empty is the good case and stays green. `NO_ANSWER` means *there was
    something to decide and no model answered*, which is not a quiet board and
    must not read as one.
    """
    print(why, file=sys.stderr)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump({field: []}, fh)
    return code


def read_model_call(answer: object) -> dict:
    """What the call cost: `{"model": str, "tokens": {...} | None}`.

    A port of `readModelCall()` in kolonie-platform
    (`packages/core/src/llm/read-model-call.ts`), and the two properties worth
    porting are both about restraint.

    **It cannot throw.** A record of what a call cost must never be able to veto
    the call — routing six issues is the work, and the accounting line under it is
    not worth losing them for. Every field is read through an `isinstance` and a
    shape this does not recognise leaves the field out.

    **And it invents nothing.** A missing `usage` block is ordinary rather than a
    fault (`kolonie-platform#716`: the gateway wraps a CLI subscription that bills
    nothing per token), so the absence is reported as an absence. A zero written
    where nothing was measured would be indistinguishable from a measured zero in
    a log query, which is the one thing this must not produce.
    """
    record = {"model": "", "tokens": None}
    if not isinstance(answer, dict):
        return record

    model = answer.get("model")
    if isinstance(model, str):
        record["model"] = model.strip()

    usage = answer.get("usage")
    if not isinstance(usage, dict):
        return record

    def count(*names: str):
        for name in names:
            value = usage.get(name)
            # `bool` is an `int` in Python and `True` is not one token.
            if isinstance(value, int) and not isinstance(value, bool) and value >= 0:
                return value
        return None

    # Two vocabularies reach this gateway — OpenAI's `prompt_tokens` and the
    # `input_tokens` an Anthropic-shaped response carries — and the pass should not
    # lose the count to whichever provider is behind it today.
    prompt = count("prompt_tokens", "input_tokens")
    completion = count("completion_tokens", "output_tokens")
    total = count("total_tokens")
    if total is None and prompt is not None and completion is not None:
        total = prompt + completion
    if total is None:
        return record

    record["tokens"] = {"prompt": prompt, "completion": completion, "total": total}
    return record


# `#262` asks for the strongest model available and gives the reason: the
# dependency step is a judgement over the whole board at once. The name is a
# setting, so the strongest model in six months is one variable away.
#
# ## Why the default is a tier alias rather than a model name (`#502`)
#
# Measured 2026-08-26 against the configured gateway: `grok-4.5` and
# `gpt-5.6-sol` — the two names this file used to know — answered **503**, while
# `x-ai/grok-4.5`, `openai/gpt-5.6-sol` and `@preset/tier-1` answered 200.
# `GET /v1/models` served the prefixed identifiers and neither bare one. A bare
# name is therefore not a model that is temporarily unwell; it is a name the
# gateway does not have, and asking it again on a schedule is a configuration
# fault dressed as a provider hiccup.
#
# A tier alias is the one identifier that does not go stale when the vendor
# behind it is replaced, which is exactly what `#262` wanted from a setting.
DEFAULT_MODEL = "@preset/tier-1"

# ## The second model is a second upstream account, and it is configuration
#
# Measured 2026-08-12: the gateway's 502 and 503 are one exhausted upstream
# account. `gpt-5.6-*` is served by a **single** ChatGPT credential shared by
# nineteen API keys, so `cli-proxy-api`'s `max-retry-credentials` has nothing to
# rotate to and answers 503 until the cooldown clears; a different vendor has its
# own account and its own quota. Asking the other one is the rotation the gateway
# cannot do for us, done here, over the same key and the same endpoint.
#
# **It is no longer inferred, and that is `#502`'s second correction.** This file
# used to derive the second attempt as *the other of the two names it knew* —
# and because both of those names were bare legacy identifiers the gateway had
# stopped serving, the retry path could not reach a served model however many
# times it was asked. Two unserved names through one healthy gateway is not a
# fallback, it is the same deterministic failure twice. So the second account is
# `TRIAGE_LLM_FALLBACK_MODEL` and nothing else: named, or not asked.
#
# **It is not a weaker model, deliberately.** The docstring above refuses to fall
# back to a rule of thumb, and a small model routing the board unnoticed would be
# that in a more expensive form: a wrong route looks exactly like a right one
# until someone reads it.
DEFAULT_FALLBACK_MODEL = ""

# What `route()` returns when the pass had something to decide and no model
# answered it. `board-triage.yml` counts these across the chunks: every chunk
# unanswered is a pass that routed nothing, and that pass must not be green.
#
# **It is not the same as an empty answer.** A model that answered and had
# nothing to change is a decided board; a model that could not be reached is an
# undecided one. Before `#502` both wrote an empty file and exited 0, which is
# how a deterministic misconfiguration ran forty-eight times a day in green.
NO_ANSWER = 3

# ## A fast failure is retried and a slow one is not
#
# Measured 2026-08-12 in Loki and in the run logs: the 502/503 a cooled-down
# account produces comes back in **one to three seconds** — a support-triage call
# succeeded at 07:35:44 and the next one failed at 07:35:45 — and the window
# clears inside a minute, so asking again costs almost nothing and usually works.
# A 524 is the opposite: Cloudflare cuts the connection at about a hundred
# seconds, and asking the same model the same brief again buys another hundred
# seconds of the same answer. So a slow failure skips the retries and spends what
# is left on the other account instead, which is both cheaper and likelier.
#
# Both models get the same two retries, so the arithmetic worth knowing is the
# worst case for one chunk: three fast failures on each account is six calls and
# thirty seconds of waiting — under a minute, and it is the case that actually
# happens. A chunk that fails *slowly* on both accounts spends about two hundred
# seconds instead, one Cloudflare cut each, and six of those would reach the
# workflow's twenty-minute timeout. That is accepted rather than guarded: it needs
# every chunk to hang on both accounts, which is the gateway being down, and a
# pass that is cut short there had nothing to write anyway.
SLOW_FAILURE_SECONDS = 30
RETRY_PAUSES = (3, 12)


def served_models(endpoint: str, key: str) -> tuple:
    """(ids-the-gateway-serves, why-not). Exactly one is non-empty.

    `GET /v1/models` is the gateway's own answer to *what may I ask for*, and
    `#502` is what happens without it: two names nobody serves, sent every half
    hour through a healthy gateway, each answered 503 and each read as a
    provider hiccup.

    **A catalogue that cannot be read is a failure unless the configured name is
    a tier alias.** Asking a vendor-shaped identifier without the catalogue would
    recreate the exact failure this function exists to stop: a bare legacy name
    sent because nothing established that the gateway serves it. Tier aliases
    are the exception because they are resolved by the gateway and deliberately
    do not appear in the served model list.
    """
    req = urllib.request.Request(
        f"{endpoint}/models",
        headers={"Authorization": f"Bearer {key}",
                 "User-Agent": "Kolonie-AI/board-triage"})
    try:
        answer = json.load(urllib.request.urlopen(req, timeout=30))
    except urllib.error.HTTPError as exc:
        # The status and nothing else, for the reason `ask_once` gives: this log
        # is public and a provider's error body can echo the request back.
        return (), f"could not read the model catalogue: the gateway answered {exc.code}"
    except Exception as exc:  # noqa: BLE001 — every way of not reaching it ends the same
        return (), f"could not read the model catalogue: {type(exc).__name__}"

    rows = answer.get("data") if isinstance(answer, dict) else None
    if not isinstance(rows, list):
        return (), "the model catalogue was not a list"

    served = []
    for row in rows:
        name = row.get("id") if isinstance(row, dict) else None
        if isinstance(name, str) and name.strip():
            served.append(name.strip())
    if not served:
        return (), "the model catalogue named no model"
    return tuple(served), ""


def usable_models(wanted: list, served: tuple) -> tuple:
    """(what-to-ask, what-the-gateway-does-not-serve).

    Order is the caller's: the configured model first, then the fallback. A tier
    alias is passed through unchecked — `@preset/tier-1` is resolved by the
    gateway to whichever model currently backs that tier and is deliberately not
    in the served catalogue, so requiring it there would refuse the one
    identifier that cannot go stale.
    """
    unserved = []
    usable = []
    for name in wanted:
        if name.startswith("@") or name in served:
            usable.append(name)
        else:
            unserved.append(name)
    return tuple(usable), tuple(unserved)


def ask_once(endpoint: str, key: str, model: str, system: str, brief: str, budget: int) -> tuple:
    """(answer-text, why-not, call, worth-asking-again).

    Exactly one of the first two is non-empty. `call` is what `read_model_call`
    made of the response, and it is empty on every path that did not get one. The
    fourth is whether the failure was the kind that a second attempt could answer
    differently — a 4xx that is not a rate limit never is.
    """
    empty = {"model": "", "tokens": None}
    body = json.dumps({
        "model": model,
        "messages": [{"role": "system", "content": system},
                     {"role": "user", "content": brief}],
        "response_format": {"type": "json_object"},
        "stream": False,
        # Large enough that a model which thinks before answering does not run out
        # mid-JSON: a truncated answer returns content: null and loses the whole
        # call rather than part of it.
        "max_tokens": budget,
        "temperature": 0.1,
    }).encode()

    # **The `User-Agent` is not decoration.** Measured 2026-08-10 against the
    # gateway: the identical request answers 200 with a named agent and **403**
    # with urllib's default `Python-urllib/3.x`, which something in front of the
    # gateway refuses. Without this header every pass would report a 403 that
    # looks exactly like a revoked key.
    req = urllib.request.Request(
        f"{endpoint}/chat/completions", data=body,
        headers={"Authorization": f"Bearer {key}",
                 "Content-Type": "application/json",
                 "User-Agent": "Kolonie-AI/board-triage"})
    try:
        answer = json.load(urllib.request.urlopen(req, timeout=300))
    except urllib.error.HTTPError as exc:
        # The status and nothing else. This log is public, and a provider's error
        # body can echo the request back with the key inside it.
        #
        # A 5xx is the gateway or its upstream and may well answer differently in
        # three seconds; a 429 is a rate limit, which is the same thing said
        # politely. Every other 4xx is this file's own request being wrong — a
        # revoked key, a model name that no longer exists — and asking again
        # would turn a configuration fault into a slow one.
        return "", f"the gateway answered {exc.code}", empty, exc.code >= 500 or exc.code == 429
    except json.JSONDecodeError:
        # A 200 whose body is not one JSON object — an SSE stream is what `#525`
        # measured, and the request above is what asks for the other. Said as its
        # own reason rather than as *could not reach the gateway*, which sends
        # the next reader to the network for a protocol fault. The body is not
        # logged, for the reason the branch above gives.
        return "", "the gateway did not answer with one JSON object", empty, True
    except Exception as exc:  # noqa: BLE001 — every way of not reaching it ends the same
        return "", f"could not reach the gateway: {type(exc).__name__}", empty, True

    call = read_model_call(answer)
    # The name that was configured, when the answer did not carry one back. It is
    # what was asked for rather than what replied, which is the honest reading of
    # a gateway that may route the request on.
    if not call["model"]:
        call["model"] = model

    choice = (answer.get("choices") or [{}])[0]
    text = (choice.get("message") or {}).get("content")
    if not text:
        # Not worth asking the same model again — it answered, and this is what it
        # had to say. The other account gets a turn instead.
        return "", ("the model returned no content"
                    f" (finish_reason: {choice.get('finish_reason') or 'unknown'})"), call, False

    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`")
        text = text.split("\n", 1)[1] if "\n" in text else text
    return text, "", call, False


def ask(system: str, brief: str, budget: int) -> tuple:
    """(answer-text, why-not, call). Exactly one of the first two is non-empty.

    The configured model, then the same model again while the failures are fast,
    then the other account once. Every attempt is the same brief over the same
    key — nothing about the question changes, only who is asked.
    """
    key = os.environ.get("TRIAGE_LLM_API_KEY") or os.environ.get("LLM_GATEWAY_API_KEY_TRIAGE", "")
    base = (os.environ.get("TRIAGE_LLM_BASE_URL") or os.environ.get("LLM_GATEWAY_BASE_URL", "")).rstrip("/")
    empty = {"model": "", "tokens": None}
    if not key or not base:
        return "", "no gateway credentials — nothing was asked for", empty

    # **`/v1` if it is not already there.** The same gateway is configured two ways
    # in this organisation: `opencode.json` hands its base URL to an
    # OpenAI-compatible provider, which appends the path itself and is therefore
    # usually given the `/v1` root, while the image calls in the maintainer's notes
    # use the bare host. A run that guessed wrong would 404 hourly, and the 404
    # would be indistinguishable from a gateway that is down.
    endpoint = base if base.endswith("/v1") else f"{base}/v1"

    model = os.environ.get("TRIAGE_LLM_MODEL", "").strip() or DEFAULT_MODEL
    # **Named or not asked** (`#502`). This used to infer the second attempt as
    # the other of two hard-coded names, and both of them were identifiers the
    # gateway had stopped serving — so the retry path could not reach a served
    # model however many times it ran. `none` still switches it off explicitly;
    # an empty string is nobody having set the variable, which is now the same
    # thing as far as this file is concerned, because inferring a second name is
    # what produced the failure.
    named = os.environ.get("TRIAGE_LLM_FALLBACK_MODEL", "").strip()
    other = "" if named == "none" else named or DEFAULT_FALLBACK_MODEL

    wanted = [model] + ([other] if other and other != model else [])

    # ## Ask for what the gateway says it serves
    #
    # A name the catalogue does not carry fails identically every pass, so it is
    # dropped here with the reason rather than retried on a schedule. A tier
    # alias is exempt, and an unreadable catalogue leaves only the aliases
    # askable — `served_models` and `usable_models` both say why.
    served, catalogue_why = served_models(endpoint, key)
    if catalogue_why:
        print(catalogue_why, file=sys.stderr)
        aliases = [name for name in wanted if name.startswith("@")]
        if not aliases:
            return "", ("the model catalogue could not be read and no configured "
                        "model is a tier alias"), empty
        wanted = aliases
    else:
        usable, unserved = usable_models(wanted, served)
        for name in unserved:
            print(f"{name}: the gateway does not serve this model — not asked",
                  file=sys.stderr)
        if not usable:
            return "", ("no configured model is served by the gateway"
                        f" ({', '.join(wanted)})"), empty
        wanted = list(usable)

    why, call = "nothing was asked", empty
    for attempt_model in wanted:
        pauses = list(RETRY_PAUSES)
        while True:
            began = time.monotonic()
            text, why, call, again = ask_once(endpoint, key, attempt_model, system, brief, budget)
            if text:
                return text, "", call
            slow = time.monotonic() - began >= SLOW_FAILURE_SECONDS
            print(f"{attempt_model}: {why}"
                  + (" — too slow to be worth asking twice" if slow and again else ""),
                  file=sys.stderr)
            if not again or slow or not pauses:
                break
            time.sleep(pauses.pop(0))
    return "", why, call


def read_brief(path: str, marker: str) -> tuple:
    try:
        with open(path, encoding="utf-8") as fh:
            brief = fh.read()
    except OSError as exc:
        return "", f"could not read the brief: {exc}"
    if marker not in brief:
        return "", "the brief holds nothing to decide about"
    return brief, ""


def route(brief_path: str, out_path: str) -> int:
    brief, why = read_brief(brief_path, "## ")
    if why:
        return nothing(out_path, "decisions", f"{why} — nothing was triaged")

    text, why, call = ask(SYSTEM, brief, 16000)
    if why:
        # `#502`: this chunk had candidates and got no answer. The empty file is
        # still written, so the workflow's `jq -s` merge is unchanged and one bad
        # chunk costs its own issues rather than the pass; the exit code is what
        # stops the pass reporting success over it.
        return nothing(out_path, "decisions",
                       f"{why} — nothing was triaged this pass", NO_ANSWER)

    try:
        decided = json.loads(text)
    except json.JSONDecodeError:
        return nothing(out_path, "decisions", "the model did not return JSON — nothing was triaged")

    decisions = decided.get("decisions")
    if not isinstance(decisions, list):
        return nothing(out_path, "decisions", "the model returned no decisions list — nothing was triaged")

    # Shaped here, judged nowhere: `apply` is what refuses a route it may not
    # write. This only drops entries that could not be applied at all, because an
    # entry without a repository and a number names no issue.
    kept = []
    for one in decisions:
        if not isinstance(one, dict):
            continue
        repo, number = one.get("repo"), one.get("number")
        if not isinstance(repo, str) or "/" not in repo:
            continue
        try:
            number = int(number)
        except (TypeError, ValueError):
            continue
        depends = one.get("depends_on") or []
        kept.append({
            "repo": repo,
            "number": number,
            "route": str(one.get("route") or ""),
            "priority": str(one.get("priority") or ""),
            "readiness": str(one.get("readiness") or ""),
            "depends_on": [str(d) for d in depends if isinstance(d, (str, int))],
            "ready": bool(one.get("ready")),
            "reason": str(one.get("reason") or "").strip(),
        })

    # ## What the call cost, on every decision it paid for (`#310`)
    #
    # **One call decides a chunk**, so the count belongs to the chunk and not to
    # any one issue — `decided` is how the comment says that out loud rather than
    # implying each issue cost the whole thing. It is written onto every entry
    # because the workflow merges the chunks with `jq -s '{decisions:
    # map(.decisions[]?)}'`, and an entry that carries its own call survives that
    # merge with no change to the workflow: each decision then names the call that
    # actually produced it, which a file-level field could not do.
    for one in kept:
        one["model"] = call["model"]
        one["tokens"] = call["tokens"]
        one["decided"] = len(kept)

    dropped = len(decisions) - len(kept)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump({"decisions": kept}, fh)
    tokens = call["tokens"]
    print(f"{len(kept)} decision(s) written"
          + (f", {dropped} dropped for naming no issue" if dropped else "")
          + f" (model: {call['model'] or 'unnamed'},"
          + (f" {tokens['total']} tokens)" if tokens else " no token count reported)"))
    return 0


def propose(brief_path: str, out_path: str) -> int:
    brief, why = read_brief(brief_path, "# The refusals")
    if why:
        return nothing(out_path, "proposals", f"{why} — nothing was proposed")

    text, why, _ = ask(PROPOSE_SYSTEM, brief, 4000)
    if why:
        return nothing(out_path, "proposals", f"{why} — nothing was proposed this pass")

    try:
        answered = json.loads(text)
    except json.JSONDecodeError:
        return nothing(out_path, "proposals", "the model did not return JSON — nothing was proposed")

    proposals = answered.get("proposals")
    if not isinstance(proposals, list):
        return nothing(out_path, "proposals", "the model returned no proposals list — nothing was proposed")

    # **The threshold is not applied here.** `board-triage.sh propose` counts the
    # issues, because *two, not three* is a rule with a cost and belongs where a
    # test can hold it. This drops only what names nothing at all.
    kept = []
    for one in proposals:
        if not isinstance(one, dict):
            continue
        key = str(one.get("key") or "").strip()
        wording = str(one.get("wording") or "").strip()
        if not key or not wording:
            continue
        issues = [str(i) for i in (one.get("issues") or []) if isinstance(i, (str, int))]
        kept.append({
            "key": key,
            "reason": str(one.get("reason") or "").strip(),
            "issues": issues,
            "wording": wording,
        })

    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump({"proposals": kept}, fh)
    print(f"{len(kept)} proposal(s) written before the threshold is applied")
    return 0


def main() -> int:
    args = sys.argv[1:]
    if args[:1] == ["--propose"]:
        return propose(args[1], args[2])
    return route(args[0], args[1])


if __name__ == "__main__":
    sys.exit(main())

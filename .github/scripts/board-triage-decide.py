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
file says what `agent:opencode` means.

**And it decides nothing about what an answer may do.** Every consequence — which
columns are writable, when `agent:opencode` is refused, whether a priority may be
set, how many refusals a proposal needs — is enforced by `board-triage.sh`, in code
with tests. This file's whole job is to turn a board into an opinion.
"""
import json
import os
import sys
import urllib.error
import urllib.request

SYSTEM = """You are the Colony's triage worker. You are shown the Kolonie AI \
board — every open issue, and the subset of them sitting in Inbox or Ready — and \
the two documents that decide who may pick an issue up: the routing table from \
AGENTS.md §5 and the prohibitions from operations/worker-prohibitions.md.

Decide five things for each issue in Inbox or Ready, and nothing else.

1. **route** — exactly one of `agent:opencode`, `agent:claude`, `agent:human`, \
against the table you were given. Read the table; do not route from a feeling \
about difficulty.
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

And **reason** — one sentence, for a person reading the issue later. Say what \
decided it. Not a summary of the issue.

Rules you must not break:

- **Never `agent:opencode` when you are unsure.** `agent:claude` is the safe \
default, because a person is reachable there. An unsure routing that reaches the \
unattended worker is the one failure mode worth designing against.
- **Never route on the author's say-so.** Provenance comes from GitHub's facts \
and is not yours to set.
- **Never write the issue's content.** You label, link and move. An issue too \
vague to route stays in Inbox and says why.
- **Only issues in Inbox or Ready.** Everything else on the board belongs to \
somebody.
- An issue you have nothing to change about may be omitted entirely. A pass that \
touches everything is a pass nobody reads.

Answer as JSON: {"decisions": [{"repo": "owner/repo", "number": 123, "route": \
"agent:claude", "priority": "p1", "readiness": "", "depends_on": \
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


def nothing(path: str, field: str, why: str) -> int:
    print(why, file=sys.stderr)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump({field: []}, fh)
    return 0


def ask(system: str, brief: str, budget: int) -> tuple:
    """(answer-text, why-not). Exactly one of the two is non-empty."""
    key = os.environ.get("TRIAGE_LLM_API_KEY") or os.environ.get("OPENCODE_LLM_API_KEY", "")
    base = (os.environ.get("TRIAGE_LLM_BASE_URL") or os.environ.get("OPENCODE_LLM_BASE_URL", "")).rstrip("/")
    # `#262` asks for the strongest model available and gives the reason: the
    # dependency step is a judgement over the whole board at once. The name is a
    # setting, so the strongest model in six months is one variable away; the
    # default is what was strongest on 2026-08-10.
    model = os.environ.get("TRIAGE_LLM_MODEL", "gpt-5.6-sol")
    if not key or not base:
        return "", "no gateway credentials — nothing was asked for"

    body = json.dumps({
        "model": model,
        "messages": [{"role": "system", "content": system},
                     {"role": "user", "content": brief}],
        "response_format": {"type": "json_object"},
        # Large enough that a model which thinks before answering does not run out
        # mid-JSON: a truncated answer returns content: null and loses the whole
        # call rather than part of it.
        "max_tokens": budget,
        "temperature": 0.1,
    }).encode()

    # **`/v1` if it is not already there.** The same gateway is configured two ways
    # in this organisation: `opencode.json` hands its base URL to an
    # OpenAI-compatible provider, which appends the path itself and is therefore
    # usually given the `/v1` root, while the image calls in the maintainer's notes
    # use the bare host. A run that guessed wrong would 404 hourly, and the 404
    # would be indistinguishable from a gateway that is down.
    endpoint = base if base.endswith("/v1") else f"{base}/v1"

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
        return "", f"the gateway answered {exc.code}"
    except Exception as exc:  # noqa: BLE001 — every way of not reaching it ends the same
        return "", f"could not reach the gateway: {type(exc).__name__}"

    choice = (answer.get("choices") or [{}])[0]
    text = (choice.get("message") or {}).get("content")
    if not text:
        return "", ("the model returned no content"
                    f" (finish_reason: {choice.get('finish_reason') or 'unknown'})")

    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`")
        text = text.split("\n", 1)[1] if "\n" in text else text
    return text, ""


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

    text, why = ask(SYSTEM, brief, 16000)
    if why:
        return nothing(out_path, "decisions", f"{why} — nothing was triaged this pass")

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

    dropped = len(decisions) - len(kept)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump({"decisions": kept}, fh)
    print(f"{len(kept)} decision(s) written"
          + (f", {dropped} dropped for naming no issue" if dropped else "")
          + f" (model: {os.environ.get('TRIAGE_LLM_MODEL', 'gpt-5.6-sol')})")
    return 0


def propose(brief_path: str, out_path: str) -> int:
    brief, why = read_brief(brief_path, "# The refusals")
    if why:
        return nothing(out_path, "proposals", f"{why} — nothing was proposed")

    text, why = ask(PROPOSE_SYSTEM, brief, 4000)
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

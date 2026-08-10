#!/usr/bin/env python3
"""The triage pass's judgement half. `kolonie-docs#262`.

    board-triage-decide.py <brief> <decisions.json>

Reads the brief `board-triage.sh brief` wrote, asks the model to route what is in
Inbox and Ready, and writes the decisions. Writes `{"decisions": []}` and exits 0
when it cannot ask.

**Exiting 0 on every failure to reach the model is the design**, and it is
`watch-judge.py`'s reasoning one workflow along: this runs hourly, a provider
hiccup that turned into a red run would produce twenty-four red runs a day, and a
red run nobody believes is worse than a pass that did nothing. An empty decisions
file is a pass that decided nothing, which is exactly what happened. What it is
*not* allowed to be is a pass that guesses: a model that cannot be reached routes
nothing rather than falling back to a rule of thumb.

**The prompt carries no copy of the rules.** `board-triage.sh brief` quotes
`AGENTS.md` §5 and `operations/worker-prohibitions.md` from where they live, so a
rule changes in one place and the next pass applies the new one. Nothing in this
file says what `agent:opencode` means.

**And it decides nothing about what a decision may do.** Every consequence — which
columns are writable, when `agent:opencode` is refused, whether a priority may be
set — is enforced by `board-triage.sh apply`, in code with tests. This file's
whole job is to turn a board into an opinion.
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
the test is whether this issue needs something that issue creates.
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


def empty(path: str, why: str) -> int:
    print(why, file=sys.stderr)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump({"decisions": []}, fh)
    return 0


def main() -> int:
    brief_path, out_path = sys.argv[1], sys.argv[2]

    key = os.environ.get("TRIAGE_LLM_API_KEY") or os.environ.get("OPENCODE_LLM_API_KEY", "")
    base = (os.environ.get("TRIAGE_LLM_BASE_URL") or os.environ.get("OPENCODE_LLM_BASE_URL", "")).rstrip("/")
    # `#262` asks for the strongest model available and gives the reason: step 4
    # is a judgement over the whole board at once. The name is a setting so that
    # the strongest model in six months is one secret away, and the default is
    # what was strongest on 2026-08-10.
    model = os.environ.get("TRIAGE_LLM_MODEL", "gpt-5.6-sol")
    if not key or not base:
        return empty(out_path, "no gateway credentials — nothing was triaged this pass")

    try:
        with open(brief_path, encoding="utf-8") as fh:
            brief = fh.read()
    except OSError as exc:
        return empty(out_path, f"could not read the brief: {exc} — nothing was triaged")

    if "## " not in brief:
        return empty(out_path, "the brief holds no issue to decide about — nothing to triage")

    body = json.dumps({
        "model": model,
        "messages": [{"role": "system", "content": SYSTEM},
                     {"role": "user", "content": brief}],
        "response_format": {"type": "json_object"},
        # The answer is one object per candidate and a candidate set of fifteen is
        # the ordinary case. Large enough that a model which thinks before
        # answering does not run out mid-JSON — a truncated answer returns
        # content: null and loses the whole pass rather than part of it.
        "max_tokens": 16000,
        "temperature": 0.1,
    }).encode()

    # **`/v1` if it is not already there.** The same gateway is configured two
    # ways in this organisation: `opencode.json` hands its base URL to an
    # OpenAI-compatible provider, which appends the path itself and is therefore
    # usually given the `/v1` root, while the image calls in the maintainer's
    # notes use the bare host. A run that guessed wrong would 404 hourly, and the
    # 404 would be indistinguishable from a gateway that is down.
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
        return empty(out_path, f"the gateway answered {exc.code} — nothing was triaged this pass")
    except Exception as exc:  # noqa: BLE001 — every way of not reaching it ends the same
        return empty(out_path, f"could not reach the gateway: {type(exc).__name__} — nothing was triaged")

    choice = (answer.get("choices") or [{}])[0]
    text = (choice.get("message") or {}).get("content")
    if not text:
        return empty(out_path, "the model returned no content"
                     f" (finish_reason: {choice.get('finish_reason') or 'unknown'}) — nothing was triaged")

    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`")
        text = text.split("\n", 1)[1] if "\n" in text else text
    try:
        decided = json.loads(text)
    except json.JSONDecodeError:
        return empty(out_path, "the model did not return JSON — nothing was triaged")

    decisions = decided.get("decisions")
    if not isinstance(decisions, list):
        return empty(out_path, "the model returned no decisions list — nothing was triaged")

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
          + f" (model: {model})")
    return 0


if __name__ == "__main__":
    sys.exit(main())

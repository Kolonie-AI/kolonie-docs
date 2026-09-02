#!/usr/bin/env python3
"""The Watch Agent's judgement half. `kolonie-docs#133`, `kolonie-docs#550`.

    watch-judge.py <dir>

Reads `<dir>/numbers.md`, asks `@preset/tier-2` of the primary gateway and
then of the second, and writes `<dir>/judgement.json` and
`<dir>/judgement.md`. Writes neither and exits 0 when it cannot ask.

**Exiting 0 on every failure is the design, not laziness.** The deterministic
half of this agent — the silent-service check — has already run by the time
this starts, and `watch-agent.sh decide` treats a missing judgement as "no
opinion" rather than as "nothing is wrong". So a provider outage costs the
day's judgement and nothing else. The opposite arrangement, where this
failing fails the workflow, would turn every gateway hiccup into a red run
at 05:00 and teach whoever reads it to stop looking.

That policy is `review-pull-request.yml`'s for a missing model key, and
`#133` is explicit that it applies to *half* of this agent and not to the
whole of it.

**No threshold reaches the model either.** It is given yesterday and the
seven days before it and asked whether yesterday is unusual. Nothing in this
file says how many errors are too many, and nothing should.

`#550` is the two-gateway half. The judge used to post directly to a
hardcoded provider URL under a dedicated key. It now asks the same tier of
two independently configured gateways through the shared Actions transport
from `#546`. A successful fallback emits one Loki event with
`service=watch-agent` and a reason class; a pair that answered nothing still
exits 0 and writes no judgement.
"""
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

_GATEWAY_SPEC = importlib.util.spec_from_file_location(
    "actions_gateway", Path(__file__).with_name("actions-gateway.py")
)
assert _GATEWAY_SPEC is not None and _GATEWAY_SPEC.loader is not None
gateway = importlib.util.module_from_spec(_GATEWAY_SPEC)
sys.modules["actions_gateway"] = gateway
_GATEWAY_SPEC.loader.exec_module(gateway)

USER_AGENT = "Kolonie-Watch-Agent/1.0 (+https://github.com/Kolonie-AI)"
DEFAULT_MODEL = "@preset/tier-2"
SERVICE = "watch-agent"

SYSTEM = """You are the Colony's Watch Agent. You are shown aggregated counts \
from one day of a small production system's logs, and the same counts for up to \
seven days before it. Decide whether the most recent day is abnormal.

**The history is as long as the store happens to hold, and it says how long that \
is.** Read that line before using the history at all. A single day of history is \
not a weekly baseline, and describing one bucket as a rate per day over a week is \
the specific error to avoid — it happened on this agent's first run. With little \
or no history, say that the comparison could not be made and set abnormal to \
false; do not manufacture a trend from one point.

You are not given log lines and you must not ask for any. Judge the numbers.

The numbers may include a GitHub Actions events table, separate from the \
container counts. A red run and a green-but-no-work event are distinct: the \
first is a workflow that failed, the second is a workflow that finished without \
doing the work it exists to do. Presence of either is not automatically \
abnormal; a departure from that table's own history, or a rare severe event, is. \
Do not fold Actions counts into the production-container judgement.

Abnormal means: a rate that has clearly departed from the preceding week, a new \
error slug that was not appearing before, or an error that is rare and severe on \
its face. It does not mean the presence of errors. A system with a steady handful \
of warnings a day is a working system, and saying so is the useful answer.

There is no threshold and you must not invent one for future runs. Judge this \
day against this history.

Answer as JSON: {"abnormal": true|false, "judgement": "one paragraph, plain \
prose, no bullet points"}. The paragraph names what you looked at and why you \
concluded what you did, so that a reader can disagree with you without re-running \
anything. If you are unsure, say so inside the paragraph and set abnormal to \
false — a person reads the numbers above your paragraph either way."""


def body_for(model: str, system: str, user: str) -> bytes:
    return json.dumps({
        "model": model,
        "messages": [{"role": "system", "content": system},
                     {"role": "user", "content": user}],
        "response_format": {"type": "json_object"},
        "stream": False,
        # Small on purpose: the answer is a boolean and a paragraph. Large
        # enough that a model which thinks before answering does not run out
        # mid-JSON, which returns content: null and loses the whole answer
        # rather than a truncated one — measured in review-pull-request.yml,
        # same lesson.
        "max_tokens": 2000,
        "temperature": 0.2,
    }).encode()


def request_judgement(endpoint, key, model, system, brief, budget):  # noqa: ANN001
    body = json.loads(body_for(model, system, brief).decode())
    if budget:
        body["max_tokens"] = budget
    attempt = gateway.post_chat(
        {"base_url": endpoint, "api_key": key},
        body,
        timeout=120,
        user_agent=USER_AGENT,
    )
    if attempt["text"]:
        return attempt["text"], "", attempt["call"]
    return "", attempt.get("why") or attempt.get("reason") or "nothing was asked", attempt["call"]


def ask(system: str, user: str, env: dict | None = None, request=None) -> tuple:
    env = env if env is not None else os.environ
    pair = gateway.gateways_from_environment("WATCH", env)
    model = gateway.model_from_environment(env, service="WATCH", default_model=DEFAULT_MODEL)
    return gateway.routed_completion(
        pair, model, system, user, 2000, request=request or request_judgement
    )


def fallback_event(reason: str) -> list[str]:
    return gateway.fallback_event(SERVICE, reason)


def emit(level: str, reason: str) -> None:
    if not os.environ.get("LOKI_URL"):
        return
    cmd = [
        "bash",
        str(Path(__file__).with_name("loki-event.sh")),
        "emit",
        SERVICE,
        level,
        f"reason={reason}",
    ]
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    if run_id:
        cmd.append(f"run_id={run_id}")
    subprocess.run(cmd, check=False)


def emit_fallback(reason: str) -> None:
    if reason not in gateway.REASONS:
        return
    emit("warn", reason)


def no_judgement(why: str) -> int:
    print(why, file=sys.stderr)
    return 0


def main() -> int:
    outdir = sys.argv[1]
    pair = gateway.gateways_from_environment("WATCH", os.environ)
    if not pair:
        # Named as a configuration gap in the log, and nowhere else. `#133`:
        # the silent-service check must still run with no key, and the issue
        # it opens says the judgement was skipped — which `watch-agent.sh
        # report` does by finding no judgement.md.
        return no_judgement(
            "no gateway is configured — the numbers stand, no judgement was asked for"
        )

    try:
        with open(os.path.join(outdir, "numbers.md"), encoding="utf-8") as fh:
            numbers = fh.read()
    except OSError as exc:
        return no_judgement(f"could not read the numbers: {exc} — no judgement was written")

    text, why, _call, taken = ask(SYSTEM, numbers)
    if taken.get("route") == "fallback" and taken.get("reason"):
        emit_fallback(taken["reason"])
        print(f"the primary gateway did not answer ({taken['reason']}) — wrote the judgement via fallback",
              file=sys.stderr)
    if not text:
        detail = why or "nothing was asked"
        return no_judgement(
            f"the model endpoint answered nothing usable ({detail}) — no judgement was written"
        )

    try:
        verdict = json.loads(gateway.strip_fence(text))
    except json.JSONDecodeError:
        return no_judgement("the model did not return JSON — no judgement was written")
    if not isinstance(verdict, dict):
        return no_judgement("the model did not return a verdict object — no judgement was written")

    paragraph = str(verdict.get("judgement") or "").strip()
    if not paragraph:
        return no_judgement("the model returned no paragraph — no judgement was written")

    out = {"abnormal": bool(verdict.get("abnormal")), "judgement": paragraph}
    with open(os.path.join(outdir, "judgement.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh)
    with open(os.path.join(outdir, "judgement.md"), "w", encoding="utf-8") as fh:
        fh.write(paragraph + "\n")
    print(f"judgement written (abnormal: {out['abnormal']})")
    return 0


if __name__ == "__main__":
    sys.exit(main())

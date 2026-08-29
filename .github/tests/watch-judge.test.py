#!/usr/bin/env python3
"""Does the Watch Agent judge ask one tier of two independently configured gateways?

Usage: python3 .github/tests/watch-judge.test.py

`#550`. The judge used to post directly to a hardcoded provider URL under
`OPENROUTER_API_KEY_WATCH`. It now asks `@preset/tier-2` of the primary
gateway and then of the second, through the shared Actions transport from
`#546`. A missing configuration or a pair that answered nothing still
exits 0 and writes no judgement: the deterministic numbers stand, which is
`#133` and must not change.

This file never reaches a gateway. The bodies below are fixtures, and no
address, key, model slug or prompt is committed as a live value.
"""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "watch-agent.yml"
SCRIPT = ROOT / ".github" / "scripts" / "watch-judge.py"
GATEWAY = ROOT / ".github" / "scripts" / "actions-gateway.py"
LEAK = ROOT / ".github" / "scripts" / "no-gateway-leak.sh"
CI = ROOT / ".github" / "workflows" / "ci.yml"

FAILURES: list[str] = []
TIER = "@preset/tier-2"
PRIMARY_URL = "https://primary.invalid"
FALLBACK_URL = "https://fallback.invalid"
PRIMARY_KEY = "primary-key"
FALLBACK_KEY = "fallback-key"


def expect(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        FAILURES.append(name)


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


expect("the judge is a module the workflow calls", SCRIPT.is_file(), str(SCRIPT))
judge = load("watch_judge", SCRIPT)
gateway = load("actions_gateway", GATEWAY)

print()
print("the request asks one JSON object of the watch tier")
body = json.loads(judge.body_for(TIER, "system", "numbers").decode())
expect("the request explicitly disables streaming",
       body.get("stream") is False, str(body.get("stream")))
expect("the model asked for is the watch tier",
       body.get("model") == TIER, str(body.get("model")))
expect("the JSON response format remains",
       body.get("response_format") == {"type": "json_object"},
       str(body.get("response_format")))
expect("the token budget remains a paragraph",
       body.get("max_tokens") == 2000, str(body.get("max_tokens")))
expect("the numbers are the user message, not a prompt of log lines",
       body.get("messages") == [{"role": "system", "content": "system"},
                                {"role": "user", "content": "numbers"}],
       str(body.get("messages")))

print()
print("the same tier over two independently configured gateways")
CALLS: list[tuple[str, str, str]] = []
PARAGRAPH = json.dumps({"abnormal": False, "judgement": "yesterday looks like the week."})


def transport(scripted: list[tuple[str, object]]):
    remaining = list(scripted)

    def request(endpoint, key, model, system, brief, budget):  # noqa: ANN001, ARG001
        CALLS.append((endpoint, key, model))
        if not remaining:
            raise AssertionError("transport called more often than scripted")
        kind, value = remaining.pop(0)
        if kind == "answer":
            return str(value), "", {"model": "", "tokens": None}
        return "", kind, {"model": "", "tokens": None}

    return request


def run(scripted: list[tuple[str, object]], fallback: bool = True, keys: bool = True):
    CALLS.clear()
    env = {}
    if keys:
        env = {
            "LLM_GATEWAY_BASE_URL": PRIMARY_URL,
            "LLM_GATEWAY_API_KEY_WATCH": PRIMARY_KEY,
            "LLM_GATEWAY_FALLBACK_BASE_URL": FALLBACK_URL if fallback else "",
            "LLM_GATEWAY_FALLBACK_API_KEY_WATCH": FALLBACK_KEY if fallback else "",
        }
    return judge.ask("system", "numbers", env=env, request=transport(scripted))


text, why, call, route = run([], keys=False)
expect("no keys means nothing is asked", CALLS == [], str(CALLS))
expect("and no judgement comes back", text == "" and bool(why), why)

text, why, call, route = run([("answer", PARAGRAPH)])
expect("primary success is returned", text == PARAGRAPH and why == "", why)
expect("primary success never asks fallback",
       CALLS == [(PRIMARY_URL, PRIMARY_KEY, TIER)], str(CALLS))
expect("the primary route carries no fallback",
       route == {"route": "primary"}, str(route))

text, why, call, route = run([("status", 524), ("answer", PARAGRAPH)])
expect("a primary 524 is answered by fallback", text == PARAGRAPH and why == "", why)
expect(
    "the primary is not retried and fallback receives the identical tier",
    CALLS == [(PRIMARY_URL, PRIMARY_KEY, TIER), (FALLBACK_URL, FALLBACK_KEY, TIER)],
    str(CALLS),
)
expect(
    "fallback route metadata is bounded to its reason class",
    route == {"route": "fallback", "reason": "status"},
    str(route),
)

text, why, call, route = run([("timeout", "slow"), ("answer", PARAGRAPH)])
expect("a primary timeout is answered by fallback", text == PARAGRAPH and why == "", why)
expect("timeout also asks each gateway once", len(CALLS) == 2, str(CALLS))
expect("and names the class", route.get("reason") == "timeout", str(route))

text, why, call, route = run([("status", 502)], fallback=False)
expect("neither answering writes no judgement", text == "" and bool(why), why)
expect("an unconfigured fallback asks only primary",
       CALLS == [(PRIMARY_URL, PRIMARY_KEY, TIER)], str(CALLS))

print()
print("the executable path preserves the deterministic report on every no-model ending")
with tempfile.TemporaryDirectory() as work:
    outdir = Path(work)
    numbers = "# Yesterday\n\n| service | count |\n| --- | ---: |\n| api | 3 |\n"
    (outdir / "numbers.md").write_text(numbers, encoding="utf-8")
    names = (
        "LLM_GATEWAY_BASE_URL",
        "LLM_GATEWAY_API_KEY_WATCH",
        "LLM_GATEWAY_FALLBACK_BASE_URL",
        "LLM_GATEWAY_FALLBACK_API_KEY_WATCH",
    )
    saved = {name: os.environ.get(name) for name in names}
    saved_argv = list(sys.argv)
    saved_ask = judge.ask
    saved_emit = judge.emit_fallback
    try:
        for name in names:
            os.environ.pop(name, None)
        sys.argv = [str(SCRIPT), str(outdir)]
        rc = judge.main()
        expect("no configuration exits 0", rc == 0, str(rc))
        expect("no configuration writes no judgement",
               not (outdir / "judgement.json").exists())
        expect("and leaves the deterministic numbers intact",
               (outdir / "numbers.md").read_text(encoding="utf-8") == numbers)

        os.environ["LLM_GATEWAY_BASE_URL"] = PRIMARY_URL
        os.environ["LLM_GATEWAY_API_KEY_WATCH"] = PRIMARY_KEY
        emitted: list[str] = []
        judge.ask = lambda system, user: (
            PARAGRAPH,
            "",
            {"model": "", "tokens": None},
            {"route": "fallback", "reason": "status"},
        )
        judge.emit_fallback = emitted.append
        rc = judge.main()
        expect("fallback success exits 0 and writes the judgement",
               rc == 0 and (outdir / "judgement.json").exists(), str(rc))
        expect("fallback success emits once", emitted == ["status"], str(emitted))

        (outdir / "judgement.json").unlink()
        (outdir / "judgement.md").unlink()
        judge.ask = lambda system, user: (
            "",
            "the gateway answered 502",
            {"model": "", "tokens": None},
            {"route": "none", "reason": "status"},
        )
        rc = judge.main()
        expect("neither gateway answering still exits 0", rc == 0, str(rc))
        expect("neither gateway answering writes no invented judgement",
               not (outdir / "judgement.json").exists()
               and not (outdir / "judgement.md").exists())
        expect("and the deterministic numbers still stand",
               (outdir / "numbers.md").read_text(encoding="utf-8") == numbers)
    finally:
        judge.ask = saved_ask
        judge.emit_fallback = saved_emit
        sys.argv = saved_argv
        for name, value in saved.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value

print()
print("a successful fallback exposes one stable Loki invocation")
event = judge.fallback_event("status")
expect(
    "the service is the Watch Agent's",
    event == ["bash", ".github/scripts/loki-event.sh", "emit",
              "watch-agent", "warn", "reason=status"],
    str(event),
)
expect("the event contains no endpoint", PRIMARY_URL not in " ".join(event))
expect("the event contains no credential", PRIMARY_KEY not in " ".join(event))
expect("the event contains no prompt", "numbers" not in " ".join(event).lower())

print()
print("the judge no longer names a provider host or the retired key")
source = SCRIPT.read_text(encoding="utf-8")
expect("watch-judge.py does not name a provider host", "openrouter.ai" not in source.lower())
expect("watch-judge.py does not read the retired key",
       "OPENROUTER_API_KEY_WATCH" not in source)
expect("watch-judge.py does not default to a model slug",
       "deepseek" not in source.lower())
expect("the judge imports the shared transport rather than copying urllib",
       "actions-gateway.py" in source and "urllib.request.Request" not in source)
expect("the judge still refuses log lines",
       "You are not given log lines" in source)

print()
print("the workflow reads a dedicated pair and the two shared base URLs")
workflow = WORKFLOW.read_text(encoding="utf-8")
expect("the primary base URL is wired", "LLM_GATEWAY_BASE_URL" in workflow)
expect("the watch key is wired", "LLM_GATEWAY_API_KEY_WATCH" in workflow)
expect("the fallback base URL is wired", "LLM_GATEWAY_FALLBACK_BASE_URL" in workflow)
expect("the watch fallback key is wired", "LLM_GATEWAY_FALLBACK_API_KEY_WATCH" in workflow)
expect("and not the triage key", "LLM_GATEWAY_FALLBACK_API_KEY_TRIAGE" not in workflow)
expect("and not the reviewer key", "LLM_GATEWAY_FALLBACK_API_KEY_REVIEWER" not in workflow)
expect("and not the worker key", "LLM_GATEWAY_FALLBACK_API_KEY_WORKER" not in workflow)
expect("the retired key is gone from the workflow",
       "OPENROUTER_API_KEY_WATCH" not in workflow)
expect("no model slug remains in the workflow",
       "deepseek" not in workflow.lower())
expect("the Loki pair is wired so a fallback can be recorded",
       "LOKI_URL" in workflow and "LOKI_TOKEN" in workflow)

print()
print("the leak-guard now covers the second gateway's address")
guarded = LEAK.read_text(encoding="utf-8")
expect("LLM_GATEWAY_FALLBACK_BASE_URL is a guarded value",
       "LLM_GATEWAY_FALLBACK_BASE_URL" in guarded)
ci = CI.read_text(encoding="utf-8")
expect("CI hands the fallback address to the leak check",
       "LLM_GATEWAY_FALLBACK_BASE_URL: ${{ secrets.LLM_GATEWAY_FALLBACK_BASE_URL }}" in ci)

print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")

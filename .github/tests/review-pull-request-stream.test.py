#!/usr/bin/env python3
"""Does the Reviewer Agent ask one JSON object of two independently configured gateways?

Usage: python3 .github/tests/review-pull-request-stream.test.py

`#525` fixed `board-triage-decide.py` and the reviewer was the second caller
nobody changed. Measured against the configured gateway on 2026-08-27: a
request with no `stream` field answers HTTP 200 whose body begins with SSE
`data:` for `@preset/tier-1`, `-2` and `-3` alike; the same request with
`"stream": false` answers one JSON object.

`#547` is the two-gateway half. The reviewer used to fall back to a hardcoded
OpenRouter host under a shared key and a different model id. It now asks
`@preset/tier-2` of the primary gateway and then of the second, through the
shared transport, and a missing review stays a comment in the log rather than
a red required check.

This file never reaches a gateway; the bodies below are fixtures and no
address, key or provider response is in it.
"""

from __future__ import annotations

import importlib.util
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "review-pull-request.yml"
SCRIPT = ROOT / ".github" / "scripts" / "review-pull-request.py"
GATEWAY = ROOT / ".github" / "scripts" / "actions-gateway.py"

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


expect("the reviewer is a module the workflow calls, not an inline copy of routing",
       SCRIPT.is_file(), str(SCRIPT))

reviewer = load("review_pull_request", SCRIPT)
gateway = load("actions_gateway", GATEWAY)

print("the request still asks for one JSON object")
body = json.loads(reviewer.body_for(TIER, "system", "user").decode())
expect("the review request explicitly disables streaming",
       body.get("stream") is False, str(body.get("stream")))
expect("the model asked for is the reviewer tier",
       body.get("model") == TIER, str(body.get("model")))
expect("the JSON response format remains",
       body.get("response_format") == {"type": "json_object"}, str(body.get("response_format")))
expect("the token budget remains",
       body.get("max_tokens") == 16000, str(body.get("max_tokens")))
expect("the messages remain",
       body.get("messages") == [{"role": "system", "content": "system"},
                                {"role": "user", "content": "user"}],
       str(body.get("messages")))

print()
print("an SSE-shaped 200 is a protocol fault, not an unreachable gateway")


class Scripted:
    def __init__(self, answers: list[object]) -> None:
        self.answers = list(answers)
        self.calls: list[tuple[str, str, dict]] = []

    def __call__(self, url: str, headers: dict, body: bytes, timeout: float):  # noqa: ARG002
        parsed = json.loads(body.decode())
        self.calls.append((url, headers.get("Authorization", ""), parsed))
        if not self.answers:
            raise AssertionError("transport asked more often than scripted")
        answer = self.answers.pop(0)
        if isinstance(answer, Exception):
            raise answer
        return answer


SSE_BODY = b'data: {"id":"chunk"}\n\ndata: [DONE]\n\n'
script = Scripted([(200, SSE_BODY)])
result = gateway.post_chat(
    {"base_url": PRIMARY_URL, "api_key": PRIMARY_KEY},
    body,
    timeout=1,
    transport=script,
    user_agent=reviewer.USER_AGENT,
)
expect("an SSE-shaped 200 is not a verdict", not result.get("text"), repr(result.get("text")))
expect("and it is reported as a protocol fault, not an unreachable gateway",
       result.get("reason") == "malformed" and "JSON" in (result.get("why") or ""),
       str(result))
expect("and the reason carries no part of the body",
       "data:" not in (result.get("why") or ""), str(result.get("why")))
expect("the attempted request still disabled streaming",
       bool(script.calls) and script.calls[0][2].get("stream") is False,
       str(script.calls[0][2] if script.calls else None))

print()
print("the same tier over two independently configured gateways")
CALLS: list[tuple[str, str, str]] = []


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


VERDICT = json.dumps({
    "verdict": "comment",
    "summary": "ok",
    "criteria": [],
    "findings": [],
    "unchecked": [],
})


def run(scripted: list[tuple[str, object]], fallback: bool = True):
    CALLS.clear()
    env = {
        "LLM_GATEWAY_BASE_URL": PRIMARY_URL,
        "LLM_GATEWAY_API_KEY_REVIEWER": PRIMARY_KEY,
        "LLM_GATEWAY_FALLBACK_BASE_URL": FALLBACK_URL if fallback else "",
        "LLM_GATEWAY_FALLBACK_API_KEY_REVIEWER": FALLBACK_KEY if fallback else "",
        "REVIEWER_LLM_MODEL": TIER,
    }
    return reviewer.ask("system", "user", env=env, request=transport(scripted))


text, why, call, route = run([("answer", VERDICT)])
expect("primary success is returned", text == VERDICT and why == "", why)
expect("primary success never asks fallback",
       CALLS == [(PRIMARY_URL, PRIMARY_KEY, TIER)], str(CALLS))
expect("the primary route carries no fallback", route == {"route": "primary"}, str(route))

text, why, call, route = run([("status", 524), ("answer", VERDICT)])
expect("a primary 524 is answered by fallback", text == VERDICT and why == "", why)
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

text, why, call, route = run([("status", 502), ("answer", VERDICT)])
expect("a primary 502 is answered by fallback", text == VERDICT and why == "", why)
expect("502 also asks each gateway once", len(CALLS) == 2, str(CALLS))

text, why, call, route = run([("status", 524)], fallback=False)
expect("an unconfigured fallback plus failed primary writes no review",
       text == "" and bool(why), why)
expect("an unconfigured fallback asks only primary",
       CALLS == [(PRIMARY_URL, PRIMARY_KEY, TIER)], str(CALLS))
joined = " ".join(CALLS[0]) if CALLS else why
expect("and no hostname is invented for the missing half",
       "openrouter" not in joined.lower() and "openrouter" not in (why or "").lower(),
       joined)

print()
print("the workflow no longer names a provider host or the shared key")
workflow = WORKFLOW.read_text(encoding="utf-8")
expect("review-pull-request.yml does not name openrouter.ai",
       "openrouter.ai" not in workflow.lower())
expect("review-pull-request.yml does not read OPENROUTER_API_KEY",
       "OPENROUTER_API_KEY" not in workflow)
expect("the reusable workflow declares the fallback pair",
       "LLM_GATEWAY_FALLBACK_BASE_URL" in workflow
       and "LLM_GATEWAY_FALLBACK_API_KEY_REVIEWER" in workflow)
expect("the asked model defaults to the reviewer tier, not a slug",
       '@preset/tier-2' in workflow and "anthropic/claude-sonnet-5" not in workflow)
expect("the workflow runs the extracted reviewer, not an inline copy",
       "python3 kolonie-docs/.github/scripts/review-pull-request.py" in workflow)

print()
print("a successful fallback exposes one stable Loki invocation")
event = reviewer.fallback_event("status")
expect(
    "successful fallback exposes one stable Loki invocation",
    event == ["bash", ".github/scripts/loki-event.sh", "emit",
              "review-pull-request", "warn", "reason=status"],
    str(event),
)
expect("the event contains no endpoint", PRIMARY_URL not in " ".join(event))
expect("the event contains no credential", PRIMARY_KEY not in " ".join(event))

print()
print("every urllib caller that reaches our gateway still names stream")
callers = []
for parent in (ROOT / ".github" / "scripts", ROOT / ".github" / "workflows"):
    for path in sorted(parent.iterdir()):
        if path.suffix not in {".py", ".yml", ".yaml"}:
            continue
        text = path.read_text(encoding="utf-8")
        if "LLM_GATEWAY_BASE_URL" not in text or "/chat/completions" not in text:
            continue
        if "urllib.request.Request" not in text:
            continue
        callers.append(path)
        expect(f"{path.relative_to(ROOT)} names stream on its gateway request",
               re.search(r"""["']stream["']\s*:\s*False""", text) is not None)

expect("the shared transport is the remaining urllib gateway caller",
       callers == [GATEWAY], str([str(p.relative_to(ROOT)) for p in callers]))
script_text = SCRIPT.read_text(encoding="utf-8")
expect("the reviewer imports the shared transport rather than copying urllib",
       "actions-gateway.py" in script_text and "urllib.request.Request" not in script_text)
expect("the reviewer User-Agent is the one #728 measured",
       reviewer.USER_AGENT.startswith("Kolonie-Reviewer-Agent/1.0"),
       reviewer.USER_AGENT)

print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")

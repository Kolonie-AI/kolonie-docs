#!/usr/bin/env python3
"""Does the shared Actions transport ask one tier of two independently configured gateways?

Usage: python3 .github/tests/actions-gateway.test.py

This is the contract later slices consume. Board-triage, the reviewer, the
worker proxy and watch-judge must not copy retry, classification or route
metadata; they import this module. The cases below are the four failure classes
and the three configuration shapes that would otherwise be rewritten three more
times.
"""

from __future__ import annotations

import importlib.util
import json
import socket
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "actions_gateway", ROOT / ".github" / "scripts" / "actions-gateway.py"
)
assert spec is not None and spec.loader is not None
gateway = importlib.util.module_from_spec(spec)
sys.modules["actions_gateway"] = gateway
spec.loader.exec_module(gateway)

FAILURES: list[str] = []
TIER = "@preset/tier-1"
PRIMARY = {"base_url": "https://primary.invalid", "api_key": "primary-key"}
FALLBACK = {"base_url": "https://fallback.invalid", "api_key": "fallback-key"}
BODY = {
    "model": TIER,
    "messages": [{"role": "user", "content": "brief"}],
    "stream": False,
}


def expect(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        FAILURES.append(name)


def completion(content: str = "{}"):
    return 200, {
        "choices": [{"message": {"content": content}, "finish_reason": "stop"}],
        "model": "answering-model",
    }


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


def chat(script: Scripted, pair: dict, model: str = TIER):
    return gateway.chat_completions(
        pair,
        {**BODY, "model": model},
        timeout=1,
        transport=script,
        user_agent="Kolonie-AI/board-triage",
    )


print("configuration")
pair = gateway.gateways_from_environment(
    "TRIAGE",
    {
        "LLM_GATEWAY_BASE_URL": PRIMARY["base_url"] + "/",
        "LLM_GATEWAY_API_KEY_TRIAGE": PRIMARY["api_key"],
        "LLM_GATEWAY_FALLBACK_BASE_URL": FALLBACK["base_url"],
        "LLM_GATEWAY_FALLBACK_API_KEY_TRIAGE": FALLBACK["api_key"],
        "TRIAGE_LLM_MODEL": TIER,
    },
    model_var="TRIAGE_LLM_MODEL",
    default_model=TIER,
)
expect("primary and fallback are built independently", pair == {"primary": PRIMARY, "fallback": FALLBACK}, str(pair))

pair = gateway.gateways_from_environment(
    "TRIAGE",
    {
        "LLM_GATEWAY_BASE_URL": PRIMARY["base_url"],
        "LLM_GATEWAY_API_KEY_TRIAGE": PRIMARY["api_key"],
        "TRIAGE_LLM_MODEL": TIER,
    },
    model_var="TRIAGE_LLM_MODEL",
    default_model=TIER,
)
expect("an unconfigured fallback is absent, never a default", pair == {"primary": PRIMARY}, str(pair))

pair = gateway.gateways_from_environment(
    "TRIAGE",
    {
        "LLM_GATEWAY_BASE_URL": PRIMARY["base_url"],
        "LLM_GATEWAY_API_KEY_TRIAGE": "",
        "LLM_GATEWAY_FALLBACK_BASE_URL": FALLBACK["base_url"],
        "LLM_GATEWAY_FALLBACK_API_KEY_TRIAGE": FALLBACK["api_key"],
        "TRIAGE_LLM_MODEL": TIER,
    },
    model_var="TRIAGE_LLM_MODEL",
    default_model=TIER,
)
expect("a partial primary is dropped independently", pair == {"fallback": FALLBACK}, str(pair))

print()
print("the four fallback classes, one retry, identical tier")
BOTH = {"primary": PRIMARY, "fallback": FALLBACK}

script = Scripted([completion()])
result = chat(script, BOTH)
expect("primary success never asks fallback", len(script.calls) == 1, str(script.calls))
expect("the primary URL is the one asked", script.calls[0][0].endswith("/v1/chat/completions"), script.calls[0][0])
expect("the primary key is used", script.calls[0][1] == "Bearer primary-key", script.calls[0][1])
expect("the configured tier is sent unchanged", script.calls[0][2]["model"] == TIER, str(script.calls[0][2]["model"]))
expect("the route is primary", result["route"] == "primary", str(result))

script = Scripted([(524, "timeout"), completion()])
result = chat(script, BOTH)
expect("a 524 is not retried on the primary", len(script.calls) == 2, str(len(script.calls)))
expect("the fallback receives the identical model string", script.calls[1][2]["model"] == TIER, str(script.calls[1][2]))
expect("the fallback uses its own key", script.calls[1][1] == "Bearer fallback-key", script.calls[1][1])
expect("status is the reason class", result["route"] == "fallback" and result["reason"] == "status", str(result))

script = Scripted([TimeoutError("slow"), completion()])
result = chat(script, BOTH)
expect("timeout is a fallback class", result["reason"] == "timeout", str(result))

script = Scripted([ConnectionError("down"), completion()])
result = chat(script, BOTH)
expect("unreachable is a fallback class", result["reason"] == "unreachable", str(result))

script = Scripted([(200, "not-json"), completion()])
result = chat(script, BOTH)
expect("a 200 that is not JSON is malformed", result["reason"] == "malformed", str(result))

script = Scripted([(524, "timeout")])
result = chat(script, {"primary": PRIMARY})
expect("unconfigured fallback plus failed primary answers nothing", result["text"] == "", str(result))
expect("and still names the reason class", result["reason"] == "status", str(result))
expect("and does not invent a second host", len(script.calls) == 1, str(script.calls))

print()
print("the event a successful fallback writes")
event = gateway.fallback_event("board-triage", "status")
expect("the service is the caller's", event[3] == "board-triage", str(event))
expect("the level is warn", event[4] == "warn", str(event))
expect("the reason is the class", "reason=status" in event, str(event))
joined = " ".join(event)
expect("no hostname is in the invocation", "invalid" not in joined and "http" not in joined, joined)
expect("no key is in the invocation", "key" not in joined, joined)

print()
print("the localhost proxy later slices bind")
if hasattr(gateway, "LocalProxy"):
    received: list[tuple[str, dict]] = []

    class Upstream(BaseHTTPRequestHandler):
        def do_POST(self):  # noqa: N802
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(length).decode())
            received.append((self.path, body))
            if len(received) == 1:
                self.send_response(524)
                self.end_headers()
                self.wfile.write(b"timeout")
                return
            payload = json.dumps(completion()[1]).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, format, *args):  # noqa: A002
            return

    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    server = ThreadingHTTPServer(("127.0.0.1", port), Upstream)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        origin = f"http://127.0.0.1:{port}"
        proxy = gateway.LocalProxy(
            {
                "primary": {"base_url": origin, "api_key": "primary-key"},
                "fallback": {"base_url": origin, "api_key": "fallback-key"},
            }
        )
        with proxy:
            import urllib.request
            req = urllib.request.Request(
                f"{proxy.origin}/v1/chat/completions",
                data=json.dumps(BODY).encode(),
                headers={"Content-Type": "application/json", "Authorization": "Bearer unused"},
            )
            answer = json.load(urllib.request.urlopen(req, timeout=5))
        expect("the proxy returns the fallback stream", answer["choices"][0]["message"]["content"] == "{}", str(answer))
        expect("primary then fallback were asked", len(received) == 2, str(received))
        expect("both requests carried the same model", received[0][1]["model"] == received[1][1]["model"] == TIER, str(received))
        expect("the proxy records one fallback", proxy.fallbacks == [{"reason": "status"}], str(proxy.fallbacks))
    finally:
        server.shutdown()
else:
    expect("LocalProxy exists for the worker slice", False, "missing LocalProxy")

print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")

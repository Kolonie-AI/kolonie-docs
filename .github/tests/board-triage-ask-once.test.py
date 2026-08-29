#!/usr/bin/env python3
"""Does the shared transport request one JSON object, and refuse an SSE body?

Usage: python3 .github/tests/board-triage-ask-once.test.py

`board-triage-ask.test.py` replaces the completion helper and tests routing.
This file tests the request the shared transport actually builds, and what it
does with a body that is not one JSON object — which is the defect `#525`
measured.
"""

from __future__ import annotations

import importlib.util
import json
import sys
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
SENT: list[dict] = []
JSON_REPLY = (
    b'{"choices":[{"message":{"content":"{\\"ok\\":true}"},'
    b'"finish_reason":"stop"}],"model":"alias"}'
)
SSE_REPLY = b'data: {"id":"chunk"}\n\ndata: [DONE]\n\n'


def expect(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        FAILURES.append(name)


def answering(payload: bytes, status: int = 200):
    def transport(url, headers, body, timeout):  # noqa: ANN001, ARG001
        SENT.append(json.loads(body.decode()))
        return status, payload
    return transport


text, why, call = gateway.request_completion(
    "https://primary.invalid",
    "key",
    "@preset/tier-1",
    "system",
    "brief",
    16000,
    transport=answering(JSON_REPLY),
    user_agent="Kolonie-AI/board-triage",
)
body = SENT[-1] if SENT else {}
expect("the alias-backed response is parsed", text == '{"ok":true}' and why == "", f"{text!r} {why!r}")
expect("the request explicitly disables streaming", body.get("stream") is False, str(body.get("stream")))
expect("the JSON response format remains", body.get("response_format") == {"type": "json_object"}, str(body.get("response_format")))
expect("the token budget remains", body.get("max_tokens") == 16000, str(body.get("max_tokens")))
expect(
    "the messages remain",
    body.get("messages")
    == [
        {"role": "system", "content": "system"},
        {"role": "user", "content": "brief"},
    ],
    str(body.get("messages")),
)

SENT.clear()
text, why, call = gateway.request_completion(
    "https://primary.invalid",
    "key",
    "@preset/tier-1",
    "system",
    "brief",
    16000,
    transport=answering(SSE_REPLY),
)
expect("an SSE-shaped body is not treated as an answer", text == "" and bool(why), f"text={text!r} why={why!r}")
expect("the failure names a reason, without the body", "JSON" in why and "data:" not in why, why)
expect("the request still asked for one JSON object", SENT and SENT[-1].get("stream") is False, str(SENT[-1] if SENT else None))

print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")

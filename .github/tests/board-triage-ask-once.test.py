#!/usr/bin/env python3
"""Does `ask_once` request one JSON object, and refuse an SSE body?

Usage: python3 .github/tests/board-triage-ask-once.test.py

`board-triage-ask.test.py` replaces `ask_once` and tests the retry loop.
This file tests the request `ask_once` actually builds, and what it does with
a body that is not one JSON object — which is the defect `#525` measured.

Measured 2026-08-27 against the configured gateway: a tier alias with no
`stream` field answers HTTP 200 whose body begins with SSE `data:`, so
`json.load()` raises `JSONDecodeError`. The same alias with `"stream": false`
answers one JSON object. A caller that assumes one JSON object has to say so
in the request. This file never talks to a gateway; the bodies below are
fixtures.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location(
    "board_triage_decide", ROOT / ".github" / "scripts" / "board-triage-decide.py"
)
assert _spec is not None and _spec.loader is not None
decide = importlib.util.module_from_spec(_spec)
sys.modules["board_triage_decide"] = decide
_spec.loader.exec_module(decide)

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


class FakeRequest:
    def __init__(self, url, data=None, headers=None):  # noqa: ANN001, ARG002
        self.data = data


class FakeBody:
    def __init__(self, payload: bytes) -> None:
        self.payload = payload

    def read(self) -> bytes:
        return self.payload


def answering(payload: bytes):
    def urlopen(req, timeout=None):  # noqa: ANN001, ARG001
        SENT.append(json.loads(req.data.decode()))
        return FakeBody(payload)

    return urlopen


real_request = decide.urllib.request.Request
real_urlopen = decide.urllib.request.urlopen
decide.urllib.request.Request = FakeRequest
decide.urllib.request.urlopen = answering(JSON_REPLY)
try:
    text, why, call, again = decide.ask_once(
        "", "", "@preset/tier-1", "system", "brief", 16000
    )
finally:
    decide.urllib.request.urlopen = real_urlopen

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

# The reproduction: HTTP 200, body begins with SSE `data:`. `json.load` raises.
# The reason must not carry the body — this log is public and a provider body
# can echo the request back.
SENT.clear()
decide.urllib.request.urlopen = answering(SSE_REPLY)
try:
    text, why, call, again = decide.ask_once(
        "", "", "@preset/tier-1", "system", "brief", 16000
    )
except Exception as exc:  # noqa: BLE001 — the point of the case is that it must not throw
    expect("an SSE-shaped body is a reported failure, not a crash",
           False, f"{type(exc).__name__}: {exc}")
else:
    expect("an SSE-shaped body is not treated as an answer",
           text == "" and bool(why), f"text={text!r} why={why!r}")
    expect("the failure names a reason, without the body",
           "JSON" in why and "data:" not in why, why)
    expect("the request still asked for one JSON object",
           SENT and SENT[-1].get("stream") is False, str(SENT[-1] if SENT else None))
finally:
    decide.urllib.request.Request = real_request
    decide.urllib.request.urlopen = real_urlopen

print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")

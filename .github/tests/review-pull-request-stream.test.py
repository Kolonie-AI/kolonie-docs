#!/usr/bin/env python3
"""Does the Reviewer Agent ask for one JSON object, and refuse an SSE body?

Usage: python3 .github/tests/review-pull-request-stream.test.py

`#525` fixed `board-triage-decide.py` and the reviewer was the second caller
nobody changed. Measured against the configured gateway on 2026-08-27: the
request `body_for()` builds, with no `stream` field, answers HTTP 200 whose body
begins with SSE `data:` for `@preset/tier-1`, `-2` and `-3` alike; the same
request with `"stream": false` answers one JSON object.

`ask()` then calls `json.load(urllib.request.urlopen(req))`, so the protocol
mismatch arrived as `unreachable (JSONDecodeError)` — a sentence that sends
whoever reads the log to the network for a fault in the request. Both halves are
asserted here: what the request says, and what a body that is still not one JSON
object is reported as.

**The reviewer's model runs inside a `run:` block**, so there is no module to
import. The Python is lifted out of the workflow and executed with the two
prompt strings and `urllib` replaced — which is why this asserts `body_for` and
`ask` and nothing further down that step. This file never reaches a gateway; the
bodies below are fixtures and no address, key or provider response is in it.

The last case is the one `#527` asks for in place of a third live failure: any
caller in this repository that reaches `LLM_GATEWAY_BASE_URL` over
`/chat/completions` has to name `stream`, so a caller added later is caught here
rather than in production. `watch-judge.py` is deliberately not one of them — it
calls a vendor endpoint directly and never our gateway.
"""

from __future__ import annotations

import json
import re
import textwrap
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "review-pull-request.yml"

FAILURES: list[str] = []
SENT: list[dict] = []

SSE_BODY = b'data: {"id":"chunk"}\n\ndata: [DONE]\n\n'


def expect(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        FAILURES.append(name)


# `body_for` through the end of `ask`, which is where the driver code below it
# starts reading the environment. Anchored on both ends so a moved function
# fails loudly here rather than silently testing nothing.
source = WORKFLOW.read_text(encoding="utf-8")
lifted = re.search(
    r"(?ms)^ +def body_for\(model\):\n.*?(?=^ +# `\.get` and not)",
    source,
)
if lifted is None:
    raise SystemExit(
        "could not find body_for and ask in review-pull-request.yml — "
        "this test asserts nothing until that is repaired"
    )


class FakeRequest:
    def __init__(self, url, data=None, headers=None):  # noqa: ANN001, ARG002
        self.data = data


class FakeResponse:
    def read(self) -> bytes:
        return SSE_BODY


def urlopen(req, timeout=None):  # noqa: ANN001, ARG001
    SENT.append(json.loads(req.data.decode()))
    return FakeResponse()


class FakeHTTPError(Exception):
    code = 500


scope = {
    "json": json,
    # The two prompt strings the step builds before this point. Their content is
    # not what this file is about; that they arrive as the messages is.
    "system": "system",
    "user": "user",
    "urllib": SimpleNamespace(
        request=SimpleNamespace(Request=FakeRequest, urlopen=urlopen),
        error=SimpleNamespace(HTTPError=FakeHTTPError),
    ),
}
exec(textwrap.dedent(lifted.group(0)), scope)  # noqa: S102 — the workflow is the subject

body = json.loads(scope["body_for"]("@preset/tier-1").decode())
expect("the review request explicitly disables streaming",
       body.get("stream") is False, str(body.get("stream")))
expect("the model asked for is unchanged",
       body.get("model") == "@preset/tier-1", str(body.get("model")))
expect("the JSON response format remains",
       body.get("response_format") == {"type": "json_object"}, str(body.get("response_format")))
expect("the token budget remains",
       body.get("max_tokens") == 16000, str(body.get("max_tokens")))
expect("the messages remain",
       body.get("messages") == [{"role": "system", "content": "system"},
                                {"role": "user", "content": "user"}],
       str(body.get("messages")))

# The reproduction: HTTP 200, body begins with SSE `data:`. Nothing in `ask` may
# raise — the two callers below it decide what a failure means — and the reason
# must say the reply was not JSON rather than that the gateway was unreachable.
verdict, why = scope["ask"]("", "", "@preset/tier-1")
expect("an SSE-shaped 200 is not a verdict", verdict is None, repr(verdict))
expect("and it is reported as a protocol fault, not an unreachable gateway",
       bool(why) and "JSON" in why and "unreachable" not in why, str(why))
expect("and the reason carries no part of the body",
       why is not None and "data:" not in why, str(why))
expect("the attempted request still disabled streaming",
       bool(SENT) and SENT[-1].get("stream") is False, str(SENT[-1] if SENT else None))

# Every caller in this repository that reaches our own gateway, found rather
# than listed: `#527`'s third criterion is that a caller added later is caught
# here. A vendor endpoint reached directly is not one of these and is not asked.
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

expect("both known gateway callers were found, so the sweep is reading something",
       len(callers) == 2, str([str(p.relative_to(ROOT)) for p in callers]))

print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")

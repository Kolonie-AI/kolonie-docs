#!/usr/bin/env python3
"""Does the OpenCode worker fall back at the HTTP boundary, never by a second run?

Usage: python3 .github/tests/worker-gateway-proxy.test.py

`#548`. Restarting `opencode run` after a primary `524` is a second worker over
state the first one created: files edited, packages installed, commits made,
possibly mid-tool-call. So fallback lives **below** OpenCode, at the chat
request, and OpenCode sees one local origin that never moves.

OpenCode streams, which the earlier non-streaming `LocalProxy` could not serve.
The cases below drive a real SSE request through a real proxy against a real
local upstream: primary `524`, fallback success, one usable stream out, the
same model and body on both attempts. Nothing here reaches a gateway — the
upstreams are fixtures on `127.0.0.1`, and no address, key, model slug or
prompt body is in this file.
"""

from __future__ import annotations

import importlib.util
import json
import re
import socket
import subprocess
import sys
import tempfile
import threading
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GATEWAY = ROOT / ".github" / "scripts" / "actions-gateway.py"
RUNNER = ROOT / ".github" / "scripts" / "worker-gateway-proxy.py"
WORKFLOW = ROOT / ".github" / "workflows" / "opencode-worker.yml"

FAILURES: list[str] = []
TIER = "@preset/tier-1"
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


expect("the worker proxy runner is a script the workflow calls", RUNNER.is_file(), str(RUNNER))
gateway = load("actions_gateway", GATEWAY)

SSE = (
    b'data: {"choices":[{"delta":{"content":"he"}}]}\n\n'
    b'data: {"choices":[{"delta":{"content":"llo"}}]}\n\n'
    b"data: [DONE]\n\n"
)


class Upstream:
    """A local OpenAI-compatible upstream that answers as it is scripted to."""

    def __init__(self, answers: list[object]) -> None:
        self.answers = list(answers)
        self.seen: list[dict] = []
        upstream = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_POST(self):  # noqa: N802
                length = int(self.headers.get("Content-Length", "0"))
                raw = self.rfile.read(length)
                body = json.loads(raw.decode() or "{}")
                upstream.seen.append(
                    {
                        "path": self.path,
                        "auth": self.headers.get("Authorization", ""),
                        "body": body,
                    }
                )
                answer = upstream.answers.pop(0) if upstream.answers else ("status", 500)
                kind, value = answer
                if kind == "status":
                    self.send_response(int(value))
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                payload = value if isinstance(value, bytes) else str(value).encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, format, *args):  # noqa: A002, ARG002
                return

        sock = socket.socket()
        sock.bind(("127.0.0.1", 0))
        self.port = sock.getsockname()[1]
        sock.close()
        self.server = ThreadingHTTPServer(("127.0.0.1", self.port), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.origin = f"http://127.0.0.1:{self.port}"

    def stop(self) -> None:
        self.server.shutdown()


def ask(origin: str, body: dict):
    req = urllib.request.Request(
        f"{origin}/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer opencode-does-not-know"},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return resp.status, resp.read()


STREAM_BODY = {
    "model": TIER,
    "messages": [{"role": "user", "content": "brief"}],
    "stream": True,
}

print()
print("a streaming request: primary 524, fallback answers, one usable stream out")
primary = Upstream([("status", 524)])
fallback = Upstream([("stream", SSE)])
try:
    pair = {
        "primary": {"base_url": primary.origin, "api_key": PRIMARY_KEY},
        "fallback": {"base_url": fallback.origin, "api_key": FALLBACK_KEY},
    }
    with gateway.LocalProxy(pair) as proxy:
        status, payload = ask(proxy.origin, STREAM_BODY)
    expect("the caller gets one usable stream", status == 200 and b"data:" in payload, f"{status} {payload[:40]!r}")
    expect("the stream is the fallback's, whole", payload == SSE, repr(payload[:60]))
    expect("primary was asked once", len(primary.seen) == 1, str(len(primary.seen)))
    expect("fallback was asked once", len(fallback.seen) == 1, str(len(fallback.seen)))
    expect(
        "the same model string reached both",
        primary.seen[0]["body"]["model"] == fallback.seen[0]["body"]["model"] == TIER,
        str([primary.seen[0]["body"]["model"], fallback.seen[0]["body"]["model"]]),
    )
    expect(
        "the same request body reached both",
        primary.seen[0]["body"] == fallback.seen[0]["body"] == STREAM_BODY,
        str(primary.seen[0]["body"]),
    )
    expect(
        "each gateway was asked with its own key, and never OpenCode's",
        primary.seen[0]["auth"] == f"Bearer {PRIMARY_KEY}"
        and fallback.seen[0]["auth"] == f"Bearer {FALLBACK_KEY}",
        str([primary.seen[0]["auth"], fallback.seen[0]["auth"]]),
    )
    expect("the proxy recorded one fallback with its reason class",
           proxy.fallbacks == [{"reason": "status"}], str(proxy.fallbacks))
finally:
    primary.stop()
    fallback.stop()

print()
print("primary success never asks fallback")
primary = Upstream([("stream", SSE)])
fallback = Upstream([("stream", SSE)])
try:
    pair = {
        "primary": {"base_url": primary.origin, "api_key": PRIMARY_KEY},
        "fallback": {"base_url": fallback.origin, "api_key": FALLBACK_KEY},
    }
    with gateway.LocalProxy(pair) as proxy:
        status, payload = ask(proxy.origin, STREAM_BODY)
    expect("the primary stream is returned", status == 200 and payload == SSE, f"{status}")
    expect("fallback was never asked", fallback.seen == [], str(fallback.seen))
    expect("and nothing was recorded as a fallback", proxy.fallbacks == [], str(proxy.fallbacks))
finally:
    primary.stop()
    fallback.stop()

print()
print("absent fallback plus a failed primary surfaces failure")
primary = Upstream([("status", 524)])
try:
    with gateway.LocalProxy({"primary": {"base_url": primary.origin, "api_key": PRIMARY_KEY}}) as proxy:
        try:
            status, payload = ask(proxy.origin, STREAM_BODY)
        except urllib.error.HTTPError as exc:
            status, payload = exc.code, exc.read()
    expect("the caller is told the request failed", status >= 400, str(status))
    expect("no second host was invented", len(primary.seen) == 1, str(len(primary.seen)))
    expect("and the failure carries no gateway address",
           b"127.0.0.1" not in payload and str(primary.port).encode() not in payload, repr(payload[:80]))
finally:
    primary.stop()

print()
print("the runner starts one proxy, points the derived config at it, and runs the command once")
primary = Upstream([("stream", SSE)])
try:
    with tempfile.TemporaryDirectory() as work:
        config_in = Path(work) / "runtime.json"
        config_in.write_text(json.dumps({
            "provider": {"gateway": {"options": {"baseURL": "PLACEHOLDER", "apiKey": "PLACEHOLDER"}}},
        }), encoding="utf-8")
        seen = Path(work) / "seen.txt"
        route = Path(work) / "route.json"
        child = Path(work) / "child.sh"
        child.write_text(
            "#!/bin/bash\n"
            f'echo "$OPENCODE_CONFIG" >> "{seen}"\n'
            f'echo "GH=${{GH_TOKEN-unset}}" >> "{seen}"\n'
            f'python3 - "$OPENCODE_CONFIG" <<\'PY\'\n'
            "import json,sys,urllib.request\n"
            "cfg=json.load(open(sys.argv[1]))\n"
            "base=cfg['provider']['gateway']['options']['baseURL']\n"
            "req=urllib.request.Request(base.rstrip('/')+'/chat/completions',"
            "data=json.dumps({'model':'m','messages':[],'stream':True}).encode(),"
            "headers={'Content-Type':'application/json'})\n"
            "urllib.request.urlopen(req,timeout=10).read()\n"
            "PY\n",
            encoding="utf-8",
        )
        child.chmod(0o755)
        result = subprocess.run(
            [
                sys.executable, str(RUNNER),
                "--config", str(config_in),
                "--route-out", str(route),
                "--", "bash", str(child),
            ],
            capture_output=True,
            text=True,
            env={
                "PATH": "/usr/bin:/bin:/usr/local/bin",
                "LLM_GATEWAY_BASE_URL": primary.origin,
                "LLM_GATEWAY_API_KEY_WORKER": PRIMARY_KEY,
                "GH_TOKEN": "should-not-reach-the-child",
            },
        )
        expect("the runner exits with the command's own status", result.returncode == 0,
               f"{result.returncode} {result.stderr[-300:]}")
        lines = seen.read_text().splitlines()
        expect("the command ran exactly once", len(lines) == 2, seen.read_text())
        expect("the original derived config is left as the workflow wrote it",
               "PLACEHOLDER" in config_in.read_text())
        pointed = Path(lines[0])
        expect("the command was given a sibling config", pointed != config_in, str(pointed))
        expect("the repository token never reached the child", lines[1] == "GH=unset", lines[1])
        written = json.loads(pointed.read_text())
        base = written["provider"]["gateway"]["options"]["baseURL"]
        expect("the derived config points at the local proxy", base.startswith("http://127.0.0.1:"), base)
        expect("and not at the gateway itself", base != primary.origin, base)
        expect("the upstream was reached through the proxy", len(primary.seen) == 1, str(primary.seen))
        expect("the upstream got the worker's key, not the config's placeholder",
               primary.seen[0]["auth"] == f"Bearer {PRIMARY_KEY}", primary.seen[0]["auth"])
        metadata = json.loads(route.read_text())
        expect("route metadata is returned to the workflow", "fallbacks" in metadata, str(metadata))
        expect("with no host in it", primary.origin not in route.read_text(), route.read_text())
        expect("and no key in it", PRIMARY_KEY not in route.read_text(), route.read_text())
finally:
    primary.stop()

print()
print("one bounded Loki event per run that used fallback")
event = gateway.fallback_event("opencode-worker", "status")
expect("the service is the worker's", event[3] == "opencode-worker", str(event))
expect("the level is warn", event[4] == "warn", str(event))
expect("the reason is the class", "reason=status" in event, str(event))

runner_source = RUNNER.read_text(encoding="utf-8")
expect("the runner emits once per run rather than once per request",
       "run_fallback_event" in runner_source or "emit_run" in runner_source,
       "no per-run emitter found")
expect("the count travels in the line, never as a label",
       re.search(r"fallbacks=", runner_source) is not None)
expect("a pair that answered nothing is an error event too",
       '"error"' in runner_source or "'error'" in runner_source)
expect("the runner logs no request body", "prompt" not in runner_source.lower())
expect("the runner takes the repository token out of the child's environment",
       "CHILD_UNSET" in runner_source and '"GH_TOKEN"' in runner_source)

print()
print("the workflow wires the worker's own fallback pair and still runs opencode once")
workflow = WORKFLOW.read_text(encoding="utf-8")
expect("the fallback base URL is wired", "LLM_GATEWAY_FALLBACK_BASE_URL" in workflow)
expect("the worker's own fallback key is wired", "LLM_GATEWAY_FALLBACK_API_KEY_WORKER" in workflow)
expect("and not the triage key", "LLM_GATEWAY_FALLBACK_API_KEY_TRIAGE" not in workflow)
expect("and not the reviewer key", "LLM_GATEWAY_FALLBACK_API_KEY_REVIEWER" not in workflow)
expect("the delivery path runs the model through the proxy runner",
       "worker-gateway-proxy.py" in workflow)
expect("the proxy process itself never receives the repository token",
       "env -u GH_TOKEN python3 ../.github/scripts/worker-gateway-proxy.py" in workflow)
expect("the model still runs without the repository token",
       "env -u GH_TOKEN opencode run" in workflow)
delivery = [
    line for line in workflow.splitlines()
    if "opencode run --model" in line and not line.lstrip().startswith("#")
]
expect("exactly two opencode run invocations exist: one delivery, one failure account",
       len(delivery) == 2, str(delivery))
expect("the delivery invocation is the one behind the proxy",
       any("worker-gateway-proxy.py" in line for line in workflow.splitlines()))
expect("the failure account is still bounded in time",
       "timeout 120 opencode run" in workflow)
expect("only the delivery path starts the proxy",
       workflow.count("scripts/worker-gateway-proxy.py") == 1,
       str(workflow.count("scripts/worker-gateway-proxy.py")))
expect("no hostname is committed for the fallback",
       "https://" not in "".join(
           line for line in workflow.splitlines()
           if "LLM_GATEWAY_FALLBACK" in line
       ))

print()
print("the second gateway is a value this run holds, so it is redacted like the first")
guarded = (ROOT / ".github" / "scripts" / "opencode-worker.sh").read_text(encoding="utf-8")
guarded_line = [line for line in guarded.splitlines() if line.startswith("GUARDED_SECRETS=")][0]
expect("the fallback key is redacted out of a comment",
       "LLM_GATEWAY_FALLBACK_API_KEY_WORKER" in guarded_line)
expect("and so is the fallback address", "LLM_GATEWAY_FALLBACK_BASE_URL" in guarded_line)
expect("and the log store's own two", "LOKI_URL" in guarded_line and "LOKI_TOKEN" in guarded_line)

print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")

#!/usr/bin/env python3
"""Run one command with a two-gateway proxy in front of it. `kolonie-docs#548`.

    worker-gateway-proxy.py --config <runtime.json> [--route-out <file>] -- <command…>

Starts the shared `LocalProxy` on `127.0.0.1` and an ephemeral port, rewrites
the derived OpenCode config so its single `gateway` provider points at that
local origin, and runs the command **once**. The exit status is the command's
own.

## Why the fallback is here and not around `opencode run`

Restarting `opencode run` after a primary `524` is not a retry, it is a second
worker over state the first one created: files edited, packages installed,
commits made, possibly mid-tool-call. So the second gateway is asked at the
HTTP request instead — the same body, the same tier string — and OpenCode
never learns that anything happened.

## What it does not do

It never reads the repository token, never logs a request body, and never
prints a gateway address or a key. What reaches the workflow is a count and a
reason class, which is all the Loki event is allowed to carry anyway.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
import sys
from collections import Counter
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "actions_gateway", Path(__file__).with_name("actions-gateway.py")
)
assert _SPEC is not None and _SPEC.loader is not None
gateway = importlib.util.module_from_spec(_SPEC)
sys.modules["actions_gateway"] = gateway
_SPEC.loader.exec_module(gateway)

SERVICE = "opencode-worker"
USER_AGENT = "Kolonie-AI/opencode-worker"
# Taken out of the child's environment so the model process cannot read the
# pair or the log store. The proxy already has what it needs.
CHILD_UNSET = (
    "GH_TOKEN",
    "LLM_GATEWAY_API_KEY_WORKER",
    "LLM_GATEWAY_BASE_URL",
    "LLM_GATEWAY_FALLBACK_API_KEY_WORKER",
    "LLM_GATEWAY_FALLBACK_BASE_URL",
    "LOKI_URL",
    "LOKI_TOKEN",
)


def point_config_at(source: Path, origin: str) -> Path:
    """Write a sibling config whose one provider points at the local origin.

    The original is left as the workflow derived it. The failure-account
    `opencode run` copies that file after this process has already exited, and
    must not inherit a URL whose listener is gone.
    """
    config = json.loads(source.read_text(encoding="utf-8"))
    options = config.setdefault("provider", {}).setdefault("gateway", {}).setdefault("options", {})
    options["baseURL"] = f"{origin}/v1"
    # OpenCode still has to send something; the proxy replaces it with the
    # gateway's own key and never forwards this one.
    options["apiKey"] = "local-proxy"
    dest = source.with_name(f"{source.stem}.proxy{source.suffix}")
    dest.write_text(json.dumps(config), encoding="utf-8")
    return dest


def run_fallback_event(reasons: Counter, level: str = "warn") -> list[str]:
    """One event for the whole run, never one per request.

    A streamed answer is many requests, so emitting per request would put a
    run's worth of lines in the store for one degraded gateway. The reason
    class is bounded and the count travels in the line rather than as a label,
    which is what keeps the stream cardinality flat.
    """
    reason = reasons.most_common(1)[0][0] if reasons else "unreachable"
    return [
        "bash",
        ".github/scripts/loki-event.sh",
        "emit",
        SERVICE,
        level,
        f"reason={reason}",
        f"fallbacks={sum(reasons.values())}",
    ]


def emit(reasons: Counter, level: str = "warn") -> None:
    if not os.environ.get("LOKI_URL"):
        return
    cmd = run_fallback_event(reasons, level)
    cmd[1] = str(Path(__file__).with_name("loki-event.sh"))
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    if run_id:
        cmd.append(f"run_id={run_id}")
    subprocess.run(cmd, check=False)


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--config", required=True)
    parser.add_argument("--route-out")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        print("worker-gateway-proxy: no command to run", file=sys.stderr)
        return 2

    pair = gateway.gateways_from_environment("WORKER", os.environ)
    if not pair:
        # Today's fail-loud behaviour, unchanged: an unset primary is a
        # configuration fault and not something to route around.
        print("worker-gateway-proxy: no gateway is configured", file=sys.stderr)
        return 2

    config = Path(args.config)
    with gateway.LocalProxy(pair, user_agent=USER_AGENT) as proxy:
        pointed = point_config_at(config, proxy.origin)
        env = {k: v for k, v in os.environ.items() if k not in CHILD_UNSET}
        env["OPENCODE_CONFIG"] = str(pointed)
        completed = subprocess.run(command, env=env)
        fallbacks = list(proxy.fallbacks)
        unanswered = list(proxy.unanswered)

    reasons = Counter(one.get("reason", "unreachable") for one in fallbacks)
    unanswered_reasons = Counter(one.get("reason", "unreachable") for one in unanswered)
    if unanswered_reasons:
        print("no gateway answered; the worker cannot continue", file=sys.stderr)
        emit(unanswered_reasons, "error")
    elif reasons:
        print(f"the primary gateway did not answer {sum(reasons.values())} request(s); "
              f"the second gateway did ({', '.join(sorted(reasons))})", file=sys.stderr)
        emit(reasons, "warn")

    if args.route_out:
        # A count and a class, and nothing else — no host, no key, no body.
        Path(args.route_out).write_text(json.dumps({
            "fallbacks": sum(reasons.values()),
            "unanswered": sum(unanswered_reasons.values()),
            "reasons": dict(sorted(reasons.items())),
        }), encoding="utf-8")

    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())

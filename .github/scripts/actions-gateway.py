#!/usr/bin/env python3
"""The shared Actions transport for two OpenAI-compatible gateways.

Board-triage, the reviewer, the worker proxy and watch-judge ask a capability
tier through this module. Retry, failure classification and route metadata live
here so those callers do not copy them.

Primary is asked first. Fallback is asked only on `unreachable`, `timeout`,
`status` or `malformed`, with the identical model string. An unconfigured half
is absent, never a literal default. A slow failure is not retried on the same
gateway: that is the Cloudflare 524 this exists to stop paying twice for.
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REASONS = ("unreachable", "timeout", "status", "malformed")
DEFAULT_USER_AGENT = "Kolonie-AI/actions-gateway"
DEFAULT_TIMEOUT = 300


def configured_gateway(base_url: str | None, api_key: str | None) -> dict | None:
    base = (base_url or "").strip().rstrip("/")
    key = (api_key or "").strip()
    if not base or not key:
        return None
    return {"base_url": base, "api_key": key}


def gateways_from_environment(
    service: str,
    env: dict | None = None,
    model_var: str | None = None,
    default_model: str = "",
) -> dict:
    env = env if env is not None else os.environ
    token = service.strip().upper()
    pair = {}
    primary = configured_gateway(
        env.get("LLM_GATEWAY_BASE_URL"),
        env.get(f"LLM_GATEWAY_API_KEY_{token}"),
    )
    fallback = configured_gateway(
        env.get("LLM_GATEWAY_FALLBACK_BASE_URL"),
        env.get(f"LLM_GATEWAY_FALLBACK_API_KEY_{token}"),
    )
    if primary:
        pair["primary"] = primary
    if fallback:
        pair["fallback"] = fallback
    return pair


def model_from_environment(
    env: dict | None = None,
    model_var: str | None = None,
    default_model: str = "",
    service: str | None = None,
) -> str:
    env = env if env is not None else os.environ
    if model_var:
        named = (env.get(model_var) or "").strip()
        if named:
            return named
    if service:
        token = service.strip().upper()
        named = (
            (env.get(f"LLM_GATEWAY_MODEL_{token}") or "").strip()
            or (env.get("LLM_GATEWAY_MODEL") or "").strip()
        )
        if named:
            return named
    return (default_model or "").strip()


def chat_url(base_url: str) -> str:
    base = base_url.rstrip("/")
    if not base.endswith("/v1"):
        base += "/v1"
    return f"{base}/chat/completions"


def read_model_call(answer: object, asked: str = "") -> dict:
    record = {"model": "", "tokens": None}
    if not isinstance(answer, dict):
        if asked:
            record["model"] = asked
        return record
    model = answer.get("model")
    if isinstance(model, str) and model.strip():
        record["model"] = model.strip()
    elif asked:
        record["model"] = asked
    usage = answer.get("usage")
    if not isinstance(usage, dict):
        return record

    def count(*names: str):
        for name in names:
            value = usage.get(name)
            if isinstance(value, int) and not isinstance(value, bool) and value >= 0:  # noqa: SIM114
                return value
        return None

    prompt = count("prompt_tokens", "input_tokens")
    completion = count("completion_tokens", "output_tokens")
    total = count("total_tokens")
    if total is None and prompt is not None and completion is not None:
        total = prompt + completion
    if total is None:
        return record
    record["tokens"] = {"prompt": prompt, "completion": completion, "total": total}
    return record


def strip_fence(text: str) -> str:
    trimmed = text.strip()
    if not trimmed.startswith("```"):
        return trimmed
    trimmed = trimmed.strip("`")
    return trimmed.split("\n", 1)[1] if "\n" in trimmed else trimmed


def asked_for_structure(request_body: object) -> bool:
    if isinstance(request_body, bytes):
        request_body = request_body.decode()
    if not isinstance(request_body, str):
        return False
    try:
        fmt = json.loads(request_body).get("response_format") or {}
    except json.JSONDecodeError:
        return False
    return fmt.get("type") in ("json_schema", "json_object")


def why_unusable(text: str, request_body: object) -> str | None:
    try:
        body = json.loads(text)
    except json.JSONDecodeError:
        return "the reply was not JSON"
    if not isinstance(body, dict):
        return "the reply was not JSON"
    choices = body.get("choices")
    if not isinstance(choices, list) or not choices:
        return "the reply carried no choices"
    message = (choices[0] or {}).get("message") or {}
    refusal = message.get("refusal")
    if isinstance(refusal, str) and refusal:
        return None
    content = message.get("content")
    if not isinstance(content, str) or not content.strip():
        return "the reply carried no content"
    if asked_for_structure(request_body):
        try:
            json.loads(strip_fence(content))
        except json.JSONDecodeError:
            return "a structured reply was asked for and prose came back"
    return None


def urllib_transport(url: str, headers: dict, body: bytes, timeout: float):
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read() if exc.fp else b""
    except TimeoutError:
        raise
    except socket.timeout as exc:
        raise TimeoutError(str(exc)) from exc
    except urllib.error.URLError as exc:
        reason = exc.reason
        if isinstance(reason, (TimeoutError, socket.timeout)):
            raise TimeoutError(str(reason)) from exc
        raise ConnectionError(str(reason) or type(exc).__name__) from exc
    except OSError as exc:
        raise ConnectionError(type(exc).__name__) from exc


def classify_exception(exc: BaseException) -> tuple[str, str]:
    if isinstance(exc, TimeoutError):
        return "timeout", str(exc) or "timeout"
    return "unreachable", str(exc) or type(exc).__name__


def post_chat(
    gateway: dict,
    body: dict,
    timeout: float = DEFAULT_TIMEOUT,
    transport=None,
    user_agent: str = DEFAULT_USER_AGENT,
) -> dict:
    empty = {"model": "", "tokens": None}
    payload = json.dumps(body).encode()
    headers = {
        "Authorization": f"Bearer {gateway['api_key']}",
        "Content-Type": "application/json",
        "User-Agent": user_agent,
    }
    send = transport or urllib_transport
    try:
        status, raw = send(chat_url(gateway["base_url"]), headers, payload, timeout)
    except BaseException as exc:  # noqa: BLE001 — classification is the point
        reason, detail = classify_exception(exc)
        return {"text": "", "why": detail, "call": empty, "reason": reason, "status": 0, "raw": b""}
    if isinstance(raw, bytes):
        text = raw.decode("utf-8", "replace")
        raw_bytes = raw
    else:
        text = raw if isinstance(raw, str) else json.dumps(raw)
        raw_bytes = text.encode()
        if isinstance(raw, dict):
            text = json.dumps(raw)
            raw_bytes = text.encode()
    if status >= 300 or (isinstance(status, int) and status and status < 200):
        return {
            "text": "",
            "why": f"the gateway answered {status}",
            "call": empty,
            "reason": "status",
            "status": status,
            "raw": raw_bytes,
        }
    unusable = why_unusable(text, payload)
    if unusable:
        return {
            "text": "",
            "why": unusable,
            "call": empty,
            "reason": "malformed",
            "status": status,
            "raw": raw_bytes,
        }
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return {
            "text": "",
            "why": "the reply was not JSON",
            "call": empty,
            "reason": "malformed",
            "status": status,
            "raw": raw_bytes,
        }
    choice = (parsed.get("choices") or [{}])[0]
    content = (choice.get("message") or {}).get("content") or ""
    if isinstance(content, str):
        content = strip_fence(content)
    else:
        content = ""
    return {
        "text": content,
        "why": "",
        "call": read_model_call(parsed, asked=str(body.get("model") or "")),
        "reason": "",
        "status": status,
        "raw": raw_bytes,
        "body": parsed,
    }


def chat_completions(
    pair: dict,
    body: dict,
    timeout: float = DEFAULT_TIMEOUT,
    transport=None,
    user_agent: str = DEFAULT_USER_AGENT,
) -> dict:
    empty = {"model": "", "tokens": None}
    order = [(name, pair[name]) for name in ("primary", "fallback") if pair.get(name)]
    if not order:
        return {
            "text": "",
            "why": "no gateway credentials — nothing was asked for",
            "call": empty,
            "route": "none",
        }
    last = {
        "text": "",
        "why": "nothing was asked",
        "call": empty,
        "reason": "",
        "status": 0,
        "raw": b"",
    }
    last_reason = ""
    for name, gw in order:
        attempt = post_chat(gw, body, timeout=timeout, transport=transport, user_agent=user_agent)
        if attempt["text"]:
            result = {
                "text": attempt["text"],
                "why": "",
                "call": attempt["call"],
                "route": name,
                "status": attempt.get("status") or 200,
                "raw": attempt.get("raw", b""),
                "body": attempt.get("body"),
            }
            if name == "fallback" and last_reason:
                result["reason"] = last_reason
            return result
        last = attempt
        last_reason = attempt.get("reason") or ""
    result = {
        "text": "",
        "why": last.get("why") or "nothing was asked",
        "call": last.get("call") or empty,
        "route": "none",
        "status": last.get("status") or 0,
        "raw": last.get("raw", b""),
    }
    if last_reason:
        result["reason"] = last_reason
    return result


def request_completion(
    endpoint: str,
    key: str,
    model: str,
    system: str,
    brief: str,
    budget: int,
    timeout: float = DEFAULT_TIMEOUT,
    transport=None,
    user_agent: str = DEFAULT_USER_AGENT,
) -> tuple:
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": brief},
        ],
        "response_format": {"type": "json_object"},
        "stream": False,
        "max_tokens": budget,
        "temperature": 0.1,
    }
    attempt = post_chat(
        {"base_url": endpoint, "api_key": key},
        body,
        timeout=timeout,
        transport=transport,
        user_agent=user_agent,
    )
    if attempt["text"]:
        return attempt["text"], "", attempt["call"]
    return "", attempt.get("why") or attempt.get("reason") or "nothing was asked", attempt["call"]


def routed_completion(
    pair: dict,
    model: str,
    system: str,
    brief: str,
    budget: int,
    request=None,
) -> tuple:
    empty = {"model": "", "tokens": None}
    ask = request or request_completion
    order = [(name, pair[name]) for name in ("primary", "fallback") if pair.get(name)]
    if not order:
        return "", "no gateway credentials — nothing was asked for", empty, {"route": "none"}
    last_why, last_call, last_reason = "nothing was asked", empty, ""
    for name, gw in order:
        text, why, call = ask(gw["base_url"], gw["api_key"], model, system, brief, budget)
        if text:
            route = {"route": name}
            if name == "fallback" and last_reason:
                route["reason"] = last_reason
            return text, "", call, route
        print(f"{name}: {why}", file=sys.stderr)
        last_why, last_call = why, call
        if why in REASONS:
            last_reason = why
        elif "answered" in why:
            last_reason = "status"
        elif "timeout" in why.lower():
            last_reason = "timeout"
        elif "JSON" in why or "content" in why or "malformed" in why:
            last_reason = "malformed"
        else:
            last_reason = "unreachable"
    route = {"route": "none"}
    if last_reason:
        route["reason"] = last_reason
    return "", last_why, last_call, route


def fallback_event(service: str, reason: str) -> list[str]:
    return [
        "bash",
        ".github/scripts/loki-event.sh",
        "emit",
        service,
        "warn",
        f"reason={reason}",
    ]


def emit_fallback(service: str, reason: str) -> None:
    if reason not in REASONS:
        return
    if not os.environ.get("LOKI_URL"):
        return
    script = Path(__file__).with_name("loki-event.sh")
    cmd = ["bash", str(script), "emit", service, "warn", f"reason={reason}"]
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    if run_id:
        cmd.append(f"run_id={run_id}")
    subprocess.run(cmd, check=False)


def why_unusable_stream(raw: bytes) -> str | None:
    """Return why a 2xx body is not an OpenAI-compatible SSE stream."""
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return "the stream was not UTF-8"
    saw_data = False
    saw_choice = False
    for line in text.splitlines():
        if not line.startswith("data:"):
            continue
        saw_data = True
        data = line[5:].strip()
        if not data or data == "[DONE]":
            continue
        try:
            event = json.loads(data)
        except json.JSONDecodeError:
            return "the stream carried malformed JSON"
        if not isinstance(event, dict):
            return "the stream carried a non-object event"
        choices = event.get("choices")
        if isinstance(choices, list) and choices:
            saw_choice = True
    if not saw_data:
        return "the reply was not an SSE stream"
    if not saw_choice:
        return "the stream carried no choices"
    return None


def post_stream(
    gateway: dict,
    body: dict,
    timeout: float = DEFAULT_TIMEOUT,
    transport=None,
    user_agent: str = DEFAULT_USER_AGENT,
) -> dict:
    """One streaming attempt, classified on the same four classes.

    A streamed answer cannot be judged by parsing it: an SSE body is not one
    JSON object, and `why_unusable` would call a perfectly good stream
    `malformed` and fall back on every successful request. So the verdict here
    is the transport's — a 2xx carrying bytes is an answer, and everything else
    is one of the shared classes.
    """
    payload = json.dumps(body).encode()
    headers = {
        "Authorization": f"Bearer {gateway['api_key']}",
        "Content-Type": "application/json",
        "User-Agent": user_agent,
    }
    send = transport or urllib_transport
    try:
        status, raw = send(chat_url(gateway["base_url"]), headers, payload, timeout)
    except BaseException as exc:  # noqa: BLE001 — classification is the point
        reason, detail = classify_exception(exc)
        return {"ok": False, "why": detail, "reason": reason, "status": 0, "raw": b""}
    if isinstance(raw, str):
        raw = raw.encode()
    elif not isinstance(raw, bytes):
        raw = json.dumps(raw).encode()
    if status >= 300 or (isinstance(status, int) and status and status < 200):
        return {
            "ok": False,
            "why": f"the gateway answered {status}",
            "reason": "status",
            "status": status,
            "raw": raw,
        }
    unusable = why_unusable_stream(raw)
    if unusable:
        return {
            "ok": False,
            "why": unusable,
            "reason": "malformed",
            "status": status,
            "raw": raw,
        }
    return {"ok": True, "why": "", "reason": "", "status": status, "raw": raw}


def stream_completions(
    pair: dict,
    body: dict,
    timeout: float = DEFAULT_TIMEOUT,
    transport=None,
    user_agent: str = DEFAULT_USER_AGENT,
) -> dict:
    """Primary, then fallback once, for a streamed request.

    The same order and the same four classes as `chat_completions`; what
    differs is only how an answer is recognised. The request body — model
    string included — is passed through untouched, because the point of the
    second gateway is that it is asked the identical question.
    """
    order = [(name, pair[name]) for name in ("primary", "fallback") if pair.get(name)]
    if not order:
        return {
            "ok": False,
            "why": "no gateway credentials — nothing was asked for",
            "route": "none",
            "status": 0,
            "raw": b"",
        }
    last = {"why": "nothing was asked", "reason": "", "status": 0, "raw": b""}
    last_reason = ""
    for name, gw in order:
        attempt = post_stream(gw, body, timeout=timeout, transport=transport, user_agent=user_agent)
        if attempt["ok"]:
            result = {
                "ok": True,
                "why": "",
                "route": name,
                "status": attempt["status"],
                "raw": attempt["raw"],
            }
            if name == "fallback" and last_reason:
                result["reason"] = last_reason
            return result
        last = attempt
        last_reason = attempt.get("reason") or ""
    result = {
        "ok": False,
        "why": last.get("why") or "nothing was asked",
        "route": "none",
        "status": last.get("status") or 0,
        # **The upstream's own body is dropped on the failing path.** It can
        # echo the request back, and an error body from a provider is the one
        # place a key or a host reaches a log that OpenCode will print.
        "raw": b"",
    }
    if last_reason:
        result["reason"] = last_reason
    return result


class LocalProxy:
    """An OpenAI-compatible localhost front for the same two-gateway order.

    OpenCode sees one origin. This process owns primary/fallback, so a 524
    cannot become a second `opencode run`.

    Both shapes go through it: a streamed request is judged by its transport
    and a non-streamed one by its body, because an SSE stream is not one JSON
    object and classifying it as `malformed` would fall back on every healthy
    request.
    """

    def __init__(self, pair: dict, timeout: float = DEFAULT_TIMEOUT, user_agent: str = DEFAULT_USER_AGENT) -> None:
        self.pair = pair
        self.timeout = timeout
        self.user_agent = user_agent
        self.fallbacks: list[dict] = []
        self.unanswered: list[dict] = []
        self.origin = ""
        self._server = None
        self._thread = None

    def __enter__(self):
        proxy = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):  # noqa: N802
                length = int(self.headers.get("Content-Length", "0"))
                raw = self.rfile.read(length)
                try:
                    body = json.loads(raw.decode() or "{}")
                except json.JSONDecodeError:
                    self.send_error(400)
                    return

                streaming = bool(body.get("stream"))
                if streaming:
                    result = stream_completions(
                        proxy.pair, body, timeout=proxy.timeout, user_agent=proxy.user_agent
                    )
                    answered = result.get("ok")
                    payload = result.get("raw") or b""
                    content_type = "text/event-stream"
                else:
                    result = chat_completions(
                        proxy.pair, body, timeout=proxy.timeout, user_agent=proxy.user_agent
                    )
                    answered = bool(result.get("text"))
                    payload = result.get("raw") or b""
                    if isinstance(payload, str):
                        payload = payload.encode()
                    if not payload and result.get("body") is not None:
                        payload = json.dumps(result["body"]).encode()
                    content_type = "application/json"

                if result.get("route") == "fallback" and result.get("reason"):
                    proxy.fallbacks.append({"reason": result["reason"]})
                elif not answered and result.get("reason"):
                    proxy.unanswered.append({"reason": result["reason"]})

                status = result.get("status") or (200 if answered else 502)
                if answered and status >= 400:
                    status = 200
                if not answered:
                    status = 502
                    # Its own words, never the upstream's: a provider's error
                    # body can echo the request back, and OpenCode prints what
                    # it is handed.
                    payload = b'{"error":{"message":"no gateway answered"}}'
                    content_type = "application/json"

                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, format, *args):  # noqa: A002, ARG002
                return

        self._server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        host, port = self._server.server_address
        self.origin = f"http://{host}:{port}"
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()
        return self

    def __exit__(self, *exc) -> None:
        if self._server is not None:
            self._server.shutdown()
        if self._thread is not None:
            self._thread.join(timeout=2)


if __name__ == "__main__":
    print("actions-gateway: import this module; it is not a CLI.", file=sys.stderr)
    raise SystemExit(2)

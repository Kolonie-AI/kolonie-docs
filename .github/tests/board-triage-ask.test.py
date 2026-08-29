"""Does board-triage use the shared two-gateway transport?"""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


gateway = load("actions_gateway", ROOT / ".github" / "scripts" / "actions-gateway.py")
decide = load("board_triage_decide", ROOT / ".github" / "scripts" / "board-triage-decide.py")

FAILURES: list[str] = []
CALLS: list[tuple[str, str, str]] = []
TIER = "@preset/tier-1"
PRIMARY_URL = "https://primary.invalid"
FALLBACK_URL = "https://fallback.invalid"
PRIMARY_KEY = "primary-key"
FALLBACK_KEY = "fallback-key"
EMPTY_CALL = {"model": "", "tokens": None}


def expect(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        FAILURES.append(name)


def response(content: str = "{}") -> dict:
    return {
        "choices": [{"message": {"content": content}, "finish_reason": "stop"}],
        "model": "answering-model",
    }


def transport(script: list[tuple[str, object]]):
    remaining = list(script)

    def request(endpoint, key, model, system, brief, budget):  # noqa: ANN001, ARG001
        CALLS.append((endpoint, key, model))
        if not remaining:
            raise AssertionError("transport called more often than scripted")
        kind, value = remaining.pop(0)
        if kind == "answer":
            return str(value), "", EMPTY_CALL
        return "", kind, EMPTY_CALL

    return request


def configure(fallback: bool = True) -> None:
    values = {
        "LLM_GATEWAY_BASE_URL": PRIMARY_URL,
        "LLM_GATEWAY_API_KEY_TRIAGE": PRIMARY_KEY,
        "LLM_GATEWAY_FALLBACK_BASE_URL": FALLBACK_URL if fallback else "",
        "LLM_GATEWAY_FALLBACK_API_KEY_TRIAGE": FALLBACK_KEY if fallback else "",
        "TRIAGE_LLM_MODEL": TIER,
    }
    for name in ("TRIAGE_LLM_API_KEY", "TRIAGE_LLM_BASE_URL"):
        os.environ.pop(name, None)
    os.environ.update(values)


def run(script: list[tuple[str, object]], fallback: bool = True):
    CALLS.clear()
    configure(fallback)
    decide.gateway.request_completion = transport(script)
    return decide.ask("system", "brief", 100)


print("the same tier over two independently configured gateways")
text, why, call, route = run([("answer", "{}")])
expect("primary success is returned", text == "{}" and why == "", why)
expect("primary success never asks fallback", CALLS == [(PRIMARY_URL, PRIMARY_KEY, TIER)], str(CALLS))
expect("the primary route carries no fallback", route == {"route": "primary"}, str(route))

text, why, call, route = run([("status", 524), ("answer", "{}")])
expect("a primary status failure is answered by fallback", text == "{}" and why == "", why)
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

text, why, call, route = run([("timeout", None), ("answer", "{}")])
expect("timeout is a fallback class", route == {"route": "fallback", "reason": "timeout"}, str(route))
expect("timeout also asks each gateway once", len(CALLS) == 2, str(CALLS))

text, why, call, route = run([("status", 524)], fallback=False)
expect("an unconfigured fallback keeps the primary-only failure", text == "" and why, why)
expect("an unconfigured fallback asks only primary", CALLS == [(PRIMARY_URL, PRIMARY_KEY, TIER)], str(CALLS))
expect("the failed route retains the reason class", route == {"route": "none", "reason": "status"}, str(route))

print()
print("the board-triage red ending and fallback event")
CANDIDATES = "# The board\n\n## Kolonie-AI/kolonie-docs#500\n\nSomething undecided.\n"


def route_with(script: list[tuple[str, object]], fallback: bool = True):
    CALLS.clear()
    configure(fallback)
    decide.gateway.request_completion = transport(script)
    with tempfile.TemporaryDirectory() as work:
        brief_path = os.path.join(work, "brief.md")
        out_path = os.path.join(work, "decisions.json")
        with open(brief_path, "w", encoding="utf-8") as fh:
            fh.write(CANDIDATES)
        code = decide.route(brief_path, out_path)
        with open(out_path, encoding="utf-8") as fh:
            written = json.load(fh)
    return code, written


code, written = route_with([("status", 524)], fallback=False)
expect("candidates unanswered by the configured path still fail", code == decide.NO_ANSWER, str(code))
expect("the red ending still writes the mergeable empty file", written == {"decisions": []}, str(written))

code, written = route_with([("status", 524), ("answer", '{"decisions": []}')])
expect("a fallback answer is a green pass", code == 0, str(code))
expect("a fallback answer writes no invented decisions", written == {"decisions": []}, str(written))

CALLS.clear()
configure(False)
decide.gateway.request_completion = transport([])
with tempfile.TemporaryDirectory() as work:
    brief_path = os.path.join(work, "brief.md")
    out_path = os.path.join(work, "decisions.json")
    with open(brief_path, "w", encoding="utf-8") as fh:
        fh.write("# The board\n\nNothing is waiting.\n")
    code = decide.route(brief_path, out_path)
    with open(out_path, encoding="utf-8") as fh:
        written = json.load(fh)
expect("no candidates exits 0 and asks no model at all", code == 0 and CALLS == [], f"exit {code}, asked {CALLS}")
expect("and writes the empty decisions file the merge step expects", written == {"decisions": []}, str(written))
expect(
    "successful fallback exposes one stable Loki invocation",
    decide.fallback_event("status")
    == ["bash", ".github/scripts/loki-event.sh", "emit", "board-triage", "warn", "reason=status"],
    str(decide.fallback_event("status")),
)
expect("the event contains no endpoint", PRIMARY_URL not in " ".join(decide.fallback_event("status")))
expect("the event contains no credential", PRIMARY_KEY not in " ".join(decide.fallback_event("status")))

print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")

#!/usr/bin/env python3
"""Every Actions chat caller asks for one of the three canonical capability tiers.

Usage: python3 .github/tests/capability-tiers.test.py

`kolonie-platform#1810` closed the TypeScript boundary: a provider-specific chat
model value is refused there and the service tier is used instead. Actions is a
separate boundary in Python and YAML, and until this test it accepted any string
a repository variable, workflow input or secret happened to carry — so one
mistyped variable put a provider slug back on the wire, silently, every half
hour.

The rejection cases are the ones that actually happen: a provider slug, a bare
`tier-1` without the preset prefix, an arbitrary string, and an empty value. All
four fall back to the caller's own canonical tier rather than to a slug and
rather than to an empty request.
"""

from __future__ import annotations

import importlib.util
import subprocess
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
TIER_1 = "@preset/tier-1"
TIER_2 = "@preset/tier-2"
TIER_3 = "@preset/tier-3"
REFUSED = ("provider/model-v1", "tier-1", "a-model", "", "   ")


def expect(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        FAILURES.append(name)


print("the closed set")
expect(
    "the three canonical tiers are named once, in the shared transport",
    getattr(gateway, "CAPABILITY_TIERS", None) == (TIER_1, TIER_2, TIER_3),
    str(getattr(gateway, "CAPABILITY_TIERS", None)),
)

print()
print("a canonical override is preserved")
for tier in (TIER_1, TIER_2, TIER_3):
    got = gateway.model_from_environment(
        {"TRIAGE_LLM_MODEL": tier}, model_var="TRIAGE_LLM_MODEL", default_model=TIER_1
    )
    expect(f"a named override of {tier} is sent unchanged", got == tier, got)

    got = gateway.model_from_environment(
        {"LLM_GATEWAY_MODEL_WATCH": tier}, service="WATCH", default_model=TIER_2
    )
    expect(f"a service override of {tier} is sent unchanged", got == tier, got)

    got = gateway.model_from_environment(
        {"LLM_GATEWAY_MODEL": tier}, service="WATCH", default_model=TIER_2
    )
    expect(f"a shared override of {tier} is sent unchanged", got == tier, got)

print()
print("everything else falls back to the caller's canonical tier")
for value in REFUSED:
    got = gateway.model_from_environment(
        {"REVIEWER_LLM_MODEL": value}, model_var="REVIEWER_LLM_MODEL", default_model=TIER_2
    )
    expect(f"a named override of {value!r} is refused", got == TIER_2, got)

    got = gateway.model_from_environment(
        {"LLM_GATEWAY_MODEL_TRIAGE": value}, service="TRIAGE", default_model=TIER_1
    )
    expect(f"a service override of {value!r} is refused", got == TIER_1, got)

    got = gateway.model_from_environment(
        {"LLM_GATEWAY_MODEL": value}, service="TRIAGE", default_model=TIER_1
    )
    expect(f"a shared override of {value!r} is refused", got == TIER_1, got)

got = gateway.model_from_environment(
    {"LLM_GATEWAY_MODEL_TRIAGE": "provider/model-v1", "LLM_GATEWAY_MODEL": TIER_3},
    service="TRIAGE",
    default_model=TIER_1,
)
expect("a refused service override does not shadow a canonical shared one", got == TIER_3, got)

print()
print("a caller cannot name a default outside the set")
try:
    gateway.model_from_environment({}, default_model="provider/model-v1")
    expect("a non-canonical default is refused rather than sent", False, "no refusal")
except ValueError as exc:
    expect("a non-canonical default is refused rather than sent", True)
    expect(
        "and the refusal carries no value, only the contract",
        "provider/model-v1" not in str(exc),
        str(exc),
    )

print()
print("each caller's own canonical tier")
callers = {
    "board-triage-decide.py": TIER_1,
    "review-pull-request.py": TIER_2,
    "watch-judge.py": TIER_2,
}
for name, tier in callers.items():
    text = (ROOT / ".github" / "scripts" / name).read_text(encoding="utf-8")
    expect(
        f"{name} defaults to {tier}",
        f'DEFAULT_MODEL = "{tier}"' in text,
        name,
    )

print()
print("the OpenCode worker resolves a tier rather than a free secret")


def worker_tier(env: dict) -> tuple[int, str]:
    result = subprocess.run(
        ["bash", str(ROOT / ".github" / "scripts" / "opencode-worker.sh"), "model-tier"],
        capture_output=True,
        text=True,
        env={"PATH": "/usr/bin:/bin", **env},
    )
    return result.returncode, result.stdout.strip()


code, out = worker_tier({})
expect("an unset worker model resolves to tier 1", code == 0 and out == TIER_1, f"{code} {out}")

code, out = worker_tier({"LLM_GATEWAY_MODEL_WORKER": TIER_2})
expect("a canonical worker override is preserved", code == 0 and out == TIER_2, f"{code} {out}")

for value in REFUSED:
    code, out = worker_tier({"LLM_GATEWAY_MODEL_WORKER": value})
    expect(
        f"a worker override of {value!r} resolves to tier 1 rather than reaching opencode",
        code == 0 and out == TIER_1,
        f"{code} {out}",
    )

workflow = (ROOT / ".github" / "workflows" / "opencode-worker.yml").read_text(encoding="utf-8")
expect(
    "the run asks for the resolved tier, never the raw secret",
    '--model "gateway/$LLM_GATEWAY_MODEL_WORKER"' not in workflow,
    "the workflow still passes the secret straight to opencode",
)
expect(
    "and the provider model map is built from the resolved tier",
    'jq --arg m "$LLM_GATEWAY_MODEL_WORKER"' not in workflow,
    "the workflow still writes the secret into the provider map",
)

print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")

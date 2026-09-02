#!/usr/bin/env python3
"""The Actions LLM inventory rejects callers outside the gateway tier boundary."""

from __future__ import annotations

import importlib.util
import json
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / ".github" / "scripts" / "check-llm-callers.py"

spec = importlib.util.spec_from_file_location("check_llm_callers", SCRIPT)
assert spec is not None and spec.loader is not None
checker = importlib.util.module_from_spec(spec)
sys.modules["check_llm_callers"] = checker
spec.loader.exec_module(checker)

FAILURES: list[str] = []


def expect(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        FAILURES.append(name)


def audited(root: Path) -> list[str]:
    manifest = json.loads((root / ".github" / "scripts" / "llm-callers.json").read_text())
    return checker.audit(root, manifest)


def fixture() -> tuple[tempfile.TemporaryDirectory[str], Path]:
    temporary = tempfile.TemporaryDirectory()
    root = Path(temporary.name)
    (root / ".github").mkdir()
    shutil.copytree(ROOT / ".github" / "scripts", root / ".github" / "scripts")
    shutil.copytree(ROOT / ".github" / "workflows", root / ".github" / "workflows")
    return temporary, root


print("the production inventory")
findings = audited(ROOT)
expect("every current caller is classified", findings == [], "; ".join(findings))

print()
print("direct callers")
temporary, root = fixture()
with temporary:
    path = root / ".github" / "scripts" / "unreviewed.py"
    path.write_text(
        "import urllib.request\n"
        "def ask():\n"
        "    return urllib.request.urlopen('https://gateway.invalid/chat/completions')\n"
    )
    findings = audited(root)
    expect(
        "a direct chat request is rejected",
        findings == ["direct chat endpoint at .github/scripts/unreviewed.py:ask"],
        "; ".join(findings),
    )

temporary, root = fixture()
with temporary:
    path = root / ".github" / "scripts" / "unreviewed.py"
    path.write_text(
        "import urllib.request\n"
        "CHAT = '/chat/completions'\n"
        "def ask():\n"
        "    return urllib.request.urlopen('https://gateway.invalid' + CHAT)\n"
    )
    findings = audited(root)
    expect(
        "a constant-held direct chat request is rejected",
        findings == ["direct chat endpoint at .github/scripts/unreviewed.py:CHAT"],
        "; ".join(findings),
    )

temporary, root = fixture()
with temporary:
    path = root / ".github" / "scripts" / "unreviewed.py"
    path.write_text(
        "import os, urllib.request\n"
        "def ask():\n"
        "    base = os.environ.get('LLM_GATEWAY_BASE_URL')\n"
        "    return urllib.request.urlopen(base)\n"
    )
    findings = audited(root)
    expect(
        "an unmanaged gateway transport is rejected",
        findings == ["unmanaged gateway call at .github/scripts/unreviewed.py:ask"],
        "; ".join(findings),
    )

print()
print("model overrides")
temporary, root = fixture()
with temporary:
    path = root / ".github" / "workflows" / "unreviewed.yml"
    path.write_text(
        "jobs:\n"
        "  ask:\n"
        "    runs-on: ubuntu-latest\n"
        "    steps:\n"
        "      - env:\n"
        "          NEW_LLM_MODEL: ${{ vars.NEW_LLM_MODEL }}\n"
        "        run: python3 .github/scripts/unreviewed.py\n"
    )
    findings = audited(root)
    expect(
        "a free workflow model override is rejected",
        findings
        == [
            "unclassified model variable at "
            ".github/workflows/unreviewed.yml:NEW_LLM_MODEL:NEW_LLM_MODEL"
        ],
        "; ".join(findings),
    )

temporary, root = fixture()
with temporary:
    path = root / ".github" / "workflows" / "unreviewed.yml"
    path.write_text(
        "on:\n"
        "  workflow_call:\n"
        "    inputs:\n"
        "      chat_model:\n"
        "        type: string\n"
        "jobs: {}\n"
    )
    findings = audited(root)
    expect(
        "a free workflow model input is rejected",
        findings
        == [
            "unclassified model variable at "
            ".github/workflows/unreviewed.yml:chat_model:chat_model"
        ],
        "; ".join(findings),
    )

temporary, root = fixture()
with temporary:
    path = root / ".github" / "scripts" / "unreviewed.py"
    path.write_text(
        "import os\n"
        "def ask():\n"
        "    return os.environ.get('NEW_LLM_MODEL')\n"
    )
    findings = audited(root)
    expect(
        "a free Python model override is rejected",
        findings
        == [
            "unclassified model variable at "
            ".github/scripts/unreviewed.py:ask:NEW_LLM_MODEL"
        ],
        "; ".join(findings),
    )

print()
print("output is metadata only")
temporary, root = fixture()
with temporary:
    path = root / ".github" / "scripts" / "unreviewed.py"
    path.write_text(
        "import os, urllib.request\n"
        "def ask():\n"
        "    base = os.environ.get('LLM_GATEWAY_BASE_URL')\n"
        "    return urllib.request.urlopen(base + '/chat/completions')\n"
    )
    findings = audited(root)
    joined = "; ".join(findings)
    expect("findings name the path and symbol", "unreviewed.py:ask" in joined, joined)
    expect("findings never echo the endpoint", "chat/completions" not in joined, joined)
    expect("findings never echo a value", "https://" not in joined, joined)

temporary, root = fixture()
with temporary:
    caller = root / ".github" / "scripts" / "board-triage-decide.py"
    caller.write_text(
        caller.read_text().replace(
            'DEFAULT_MODEL = "@preset/tier-1"', 'DEFAULT_MODEL = "provider/model"'
        )
    )
    findings = audited(root)
    expect(
        "a caller default outside the canonical tiers is rejected",
        findings
        == [
            "canonical tier is absent at "
            ".github/scripts/board-triage-decide.py:ask"
        ],
        "; ".join(findings),
    )

print()
print("classification and worker boundary")
temporary, root = fixture()
with temporary:
    path = root / ".github" / "scripts" / "unreviewed.py"
    path.write_text(
        "import actions_gateway as gateway\n"
        "def ask():\n"
        "    return gateway.routed_completion({}, model='@preset/tier-1', messages=[])\n"
    )
    findings = audited(root)
    expect(
        "a new shared-transport caller still needs review",
        findings == ["unclassified routed completion at .github/scripts/unreviewed.py:ask"],
        "; ".join(findings),
    )

temporary, root = fixture()
with temporary:
    workflow = root / ".github" / "workflows" / "opencode-worker.yml"
    text = workflow.read_text()
    needle = 'env -u GH_TOKEN opencode run --model "gateway/$WORKER_MODEL_TIER" "$prompt"'
    text = text.replace(
        needle,
        needle + '\n                || opencode run --model "gateway/$WORKER_MODEL_TIER" "$prompt"',
        1,
    )
    workflow.write_text(text)
    findings = audited(root)
    expect(
        "a second coding-agent run is rejected",
        findings
        == [
            "worker process count changed at "
            ".github/workflows/opencode-worker.yml:WORKER_MODEL_TIER"
        ],
        "; ".join(findings),
    )

print()
if FAILURES:
    print(f"{len(FAILURES)} failed: {', '.join(FAILURES)}")
    raise SystemExit(1)
print("all cases pass")

#!/usr/bin/env python3
"""Audit Actions LLM callers against the reviewed gateway and tier inventory."""

from __future__ import annotations

import ast
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

CANONICAL_TIERS = {"@preset/tier-1", "@preset/tier-2", "@preset/tier-3"}
PROVIDER_TIER = re.compile(r"@preset/tier-[123]")
MODEL_NAME = re.compile(r"MODEL", re.IGNORECASE)
TIER_DEFAULT = re.compile(r"^\s*DEFAULT_MODEL\s*=\s*[\"'](@preset/tier-[123])[\"']", re.MULTILINE)
WORKFLOW_MODEL = re.compile(
    r"^\s*([A-Za-z_][A-Za-z0-9_-]*MODEL[A-Za-z0-9_-]*):\s*.*"
    r"\$\{\{\s*(?:vars|secrets)\.([A-Za-z0-9_-]+)",
    re.IGNORECASE,
)
WORKFLOW_INPUT = re.compile(
    r"^ {6}((?=[A-Za-z0-9_-]*model)[A-Za-z_][A-Za-z0-9_-]*):\s*$",
    re.IGNORECASE,
)
OPENCODE_MODEL = re.compile(
    r"\bopencode\s+run\b[^\n]*--model\s+[\"']?gateway/\$\{?([A-Za-z_][A-Za-z0-9_]*)"
)
HTTP_CALLS = {"urlopen", "request", "get", "post", "put", "patch", "delete", "ClientSession"}
PYTHON_EXCLUDES = {"check-brand-surfaces.py", "check-llm-callers.py"}


@dataclass(frozen=True)
class Item:
    path: str
    symbol: str
    variable: str = ""

    @property
    def key(self) -> tuple[str, str, str]:
        return self.path, self.symbol, self.variable


def relative(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def call_name(call: ast.Call) -> str:
    if isinstance(call.func, ast.Name):
        return call.func.id
    if isinstance(call.func, ast.Attribute):
        return call.func.attr
    return ""


def string_value(node: ast.AST) -> str | None:
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.JoinedStr):
        return "".join(
            part.value
            for part in node.values
            if isinstance(part, ast.Constant) and isinstance(part.value, str)
        )
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left, right = string_value(node.left), string_value(node.right)
        if left is not None and right is not None:
            return left + right
    return None


def environment_variable(call: ast.Call) -> str | None:
    name = call_name(call)
    if name == "get" and isinstance(call.func, ast.Attribute):
        owner = call.func.value
        if isinstance(owner, ast.Attribute) and owner.attr == "environ" and call.args:
            return string_value(call.args[0])
        if isinstance(owner, ast.Name) and owner.id == "env" and call.args:
            return string_value(call.args[0])
    if name == "getenv" and call.args:
        return string_value(call.args[0])
    if isinstance(call.func, ast.Subscript):
        return None
    return None


class PythonInventory(ast.NodeVisitor):
    def __init__(self, path: str) -> None:
        self.path = path
        self.stack: list[str] = []
        self.chat: list[Item] = []
        self.routed: list[Item] = []
        self.gateway: list[Item] = []
        self.resolvers: list[Item] = []
        self.models: list[Item] = []
        self.direct_http: list[Item] = []
        self.reads_gateway_origin = False

    @property
    def symbol(self) -> str:
        return self.stack[-1] if self.stack else "<module>"

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self.stack.append(node.name)
        self.generic_visit(node)
        self.stack.pop()

    visit_AsyncFunctionDef = visit_FunctionDef

    def visit_Return(self, node: ast.Return) -> None:
        value = string_value(node.value) if node.value is not None else None
        if value and "/chat/completions" in value:
            self.chat.append(Item(self.path, self.symbol))
        self.generic_visit(node)

    def visit_Assign(self, node: ast.Assign) -> None:
        value = string_value(node.value)
        if value and "/chat/completions" in value:
            for target in node.targets:
                if isinstance(target, ast.Name):
                    self.chat.append(Item(self.path, target.id))
        self.generic_visit(node)

    def visit_AnnAssign(self, node: ast.AnnAssign) -> None:
        value = string_value(node.value) if node.value is not None else None
        if value and "/chat/completions" in value and isinstance(node.target, ast.Name):
            self.chat.append(Item(self.path, node.target.id))
        self.generic_visit(node)

    def visit_Call(self, node: ast.Call) -> None:
        name = call_name(node)
        item = Item(self.path, self.symbol)
        if name == "routed_completion":
            self.routed.append(item)
        if name in {"gateways_from_environment", "LocalProxy"}:
            self.gateway.append(Item(self.path, self.symbol, name))
        if name == "model_from_environment":
            self.resolvers.append(item)
            for keyword in node.keywords:
                if keyword.arg == "model_var":
                    variable = string_value(keyword.value)
                    if variable:
                        self.models.append(Item(self.path, self.symbol, variable))
        variable = environment_variable(node)
        if variable and variable == "LLM_GATEWAY_BASE_URL" and self.path != ".github/scripts/actions-gateway.py":
            self.reads_gateway_origin = True
        if variable and MODEL_NAME.search(variable) and self.path != ".github/scripts/actions-gateway.py":
            self.models.append(Item(self.path, self.symbol, variable))
        if name in HTTP_CALLS:
            self.direct_http.append(item)
        for argument in [*node.args, *(keyword.value for keyword in node.keywords)]:
            value = string_value(argument)
            if value and "/chat/completions" in value:
                self.chat.append(item)
        self.generic_visit(node)

    def visit_Subscript(self, node: ast.Subscript) -> None:
        value = node.value
        if isinstance(value, ast.Attribute) and value.attr == "environ":
            variable = string_value(node.slice)
            if variable == "LLM_GATEWAY_BASE_URL" and self.path != ".github/scripts/actions-gateway.py":
                self.reads_gateway_origin = True
            if variable and MODEL_NAME.search(variable) and self.path != ".github/scripts/actions-gateway.py":
                self.models.append(Item(self.path, self.symbol, variable))
        self.generic_visit(node)

    def visit_Constant(self, node: ast.Constant) -> None:
        pass


def unique(items: list[Item]) -> list[Item]:
    return list(dict.fromkeys(items))


def python_inventory(
    root: Path,
) -> tuple[list[Item], list[Item], list[Item], list[Item], list[Item], list[Item]]:
    chat: list[Item] = []
    routed: list[Item] = []
    gateway: list[Item] = []
    resolvers: list[Item] = []
    models: list[Item] = []
    unmanaged: list[Item] = []
    for path in sorted((root / ".github" / "scripts").glob("*.py")):
        if path.name in PYTHON_EXCLUDES:
            continue
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        except OSError:
            continue
        visitor = PythonInventory(relative(path, root))
        visitor.visit(tree)
        chat.extend(unique(visitor.chat))
        routed.extend(visitor.routed)
        gateway.extend(visitor.gateway)
        resolvers.extend(visitor.resolvers)
        models.extend(visitor.models)
        if visitor.direct_http and visitor.reads_gateway_origin:
            unmanaged.extend(visitor.direct_http)
    return chat, routed, gateway, resolvers, models, unmanaged


def shell_inventory(root: Path) -> list[Item]:
    models: list[Item] = []
    for path in sorted((root / ".github" / "scripts").glob("*.sh")):
        symbol = "<module>"
        name = relative(path, root)
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.lstrip().startswith("#"):
                continue
            function = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{", line)
            if function:
                symbol = function.group(1)
            for variable in set(re.findall(r"\$\{?([A-Z][A-Z0-9_]*MODEL[A-Z0-9_]*)", line)):
                models.append(Item(name, symbol, variable))
    return models


def workflow_inventory(root: Path) -> tuple[list[Item], list[Item]]:
    models: list[Item] = []
    runs: list[Item] = []
    directory = root / ".github" / "workflows"
    for path in sorted((*directory.glob("*.yml"), *directory.glob("*.yaml"))):
        text = path.read_text(encoding="utf-8")
        name = relative(path, root)
        for line in text.splitlines():
            if line.lstrip().startswith("#"):
                continue
            match = WORKFLOW_MODEL.match(line)
            if match:
                models.append(Item(name, match.group(1), match.group(2)))
            input_match = WORKFLOW_INPUT.match(line)
            if input_match:
                models.append(Item(name, input_match.group(1), input_match.group(1)))
            for model in OPENCODE_MODEL.findall(line):
                runs.append(Item(name, model))
    return models, runs


def manifest_items(manifest: dict[str, Any], group: str) -> set[tuple[str, str, str]]:
    return {
        (entry["path"], entry["symbol"], entry.get("variable", ""))
        for entry in manifest.get(group, [])
    }


def manifest_counts(manifest: dict[str, Any], group: str) -> dict[tuple[str, str, str], int]:
    counts: dict[tuple[str, str, str], int] = {}
    for entry in manifest.get(group, []):
        key = (entry["path"], entry["symbol"], entry.get("variable", ""))
        counts[key] = counts.get(key, 0) + 1
    return counts


def add_unclassified(
    findings: list[str],
    label: str,
    items: list[Item],
    allowed: set[tuple[str, str, str]],
) -> None:
    for item in items:
        if item.key not in allowed:
            suffix = f":{item.variable}" if item.variable else ""
            findings.append(f"unclassified {label} at {item.path}:{item.symbol}{suffix}")


def add_absent(
    findings: list[str],
    label: str,
    actual: list[Item],
    expected: dict[tuple[str, str, str], int],
) -> None:
    present: dict[tuple[str, str, str], int] = {}
    for item in actual:
        present[item.key] = present.get(item.key, 0) + 1
    for (path, symbol, variable), count in sorted(expected.items()):
        if present.get((path, symbol, variable), 0) >= count:
            continue
        suffix = f":{variable}" if variable else ""
        findings.append(f"manifested {label} is absent at {path}:{symbol}{suffix}")


def audit(root: Path, manifest: dict[str, Any]) -> list[str]:
    transport_path = manifest.get("sharedTransport", {}).get("path", "")
    chat, routed, gateway, resolvers, python_models, unmanaged = python_inventory(root)
    shell_models = shell_inventory(root)
    workflow_models, runs = workflow_inventory(root)
    findings: list[str] = []
    transport = manifest_items(manifest, "transports")
    callers = manifest_items(manifest, "callers")
    transport_users = manifest_items(manifest, "transportUsers")
    model_readers = manifest_items(manifest, "modelReaders")
    model_resolvers = manifest_items(manifest, "modelResolvers")
    workflow_readers = manifest_items(manifest, "workflowModels")
    worker_runs = manifest_items(manifest, "workerModels")

    for item in chat:
        if item.key not in transport:
            findings.append(f"direct chat endpoint at {item.path}:{item.symbol}")
    for item in unmanaged:
        if item.path != transport_path:
            findings.append(f"unmanaged gateway call at {item.path}:{item.symbol}")
    add_unclassified(findings, "routed completion", routed, callers)
    for item in gateway:
        if item.path == transport_path:
            continue
        if item.key not in transport_users:
            suffix = f":{item.variable}" if item.variable else ""
            findings.append(f"unclassified shared transport use at {item.path}:{item.symbol}{suffix}")
    add_unclassified(findings, "tier resolver", resolvers, model_resolvers)
    all_model_readers = python_models + shell_models
    add_unclassified(findings, "model variable", all_model_readers, model_readers)
    add_unclassified(findings, "model variable", workflow_models, workflow_readers)
    add_unclassified(findings, "OpenCode model", runs, worker_runs)

    add_absent(findings, "transport", chat, manifest_counts(manifest, "transports"))
    add_absent(findings, "routed completion", routed, manifest_counts(manifest, "callers"))
    external_gateway = [item for item in gateway if item.path != transport_path]
    add_absent(
        findings,
        "shared transport use",
        external_gateway,
        manifest_counts(manifest, "transportUsers"),
    )
    add_absent(
        findings,
        "tier resolver",
        resolvers,
        manifest_counts(manifest, "modelResolvers"),
    )
    add_absent(
        findings,
        "model variable",
        all_model_readers,
        manifest_counts(manifest, "modelReaders"),
    )
    add_absent(
        findings,
        "workflow model",
        workflow_models,
        manifest_counts(manifest, "workflowModels"),
    )
    add_absent(
        findings,
        "OpenCode model",
        runs,
        manifest_counts(manifest, "workerModels"),
    )

    defaults = {entry.get("tier") for entry in manifest.get("callers", [])}
    defaults.update(entry.get("tier") for entry in manifest.get("workerModels", []))
    if not defaults <= CANONICAL_TIERS:
        findings.append("manifest contains a noncanonical capability tier")
    for entry in manifest.get("callers", []):
        source = root / entry["path"]
        text = source.read_text(encoding="utf-8")
        match = TIER_DEFAULT.search(text)
        if match is None or match.group(1) != entry.get("tier"):
            findings.append(f"canonical tier is absent at {entry['path']}:{entry['symbol']}")
    worker_script_path = manifest.get("worker", {}).get("tierScript", "")
    worker_script = (root / worker_script_path).read_text(encoding="utf-8")
    if set(PROVIDER_TIER.findall(worker_script)) != CANONICAL_TIERS:
        findings.append(
            f"canonical tiers are absent at {worker_script_path}:"
            f"{manifest.get('worker', {}).get('tierSymbol')}"
        )

    worker = manifest.get("worker", {})
    workflow = root / worker.get("path", "")
    if workflow.is_file():
        text = workflow.read_text(encoding="utf-8")
        if worker.get("proxy") not in text:
            findings.append(f"worker proxy is absent at {worker.get('path')}:{worker.get('symbol')}")
        delivery_runs = [
            item
            for item in runs
            if item.path == worker.get("path") and item.symbol == worker.get("symbol")
        ]
        if len(delivery_runs) != 1:
            findings.append(
                f"worker process count changed at {worker.get('path')}:"
                f"{worker.get('symbol')}"
            )

    return sorted(set(findings))


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv
    root = (
        Path(args[1]).resolve()
        if len(args) > 1
        else Path(__file__).resolve().parents[2]
    )
    manifest_path = root / ".github" / "scripts" / "llm-callers.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    findings = audit(root, manifest)
    for finding in findings:
        print(f"check-llm-callers: {finding}", file=sys.stderr)
    if findings:
        return 1
    print("check-llm-callers: reviewed Actions LLM inventory passes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

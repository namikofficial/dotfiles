from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path, PurePosixPath
from typing import Iterable, Sequence

try:  # pragma: no cover - optional in unit tests
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    tomllib = None  # type: ignore[assignment]

from .types import Chunk

try:  # pragma: no cover - optional dependency during tests
    from tree_sitter_language_pack import get_parser, has_language
except ImportError:  # pragma: no cover
    get_parser = None  # type: ignore[assignment]
    has_language = None  # type: ignore[assignment]

TREE_SITTER_LANGUAGE_MAP = {
    "typescript": "typescript",
    "javascript": "javascript",
    "python": "python",
    "rust": "rust",
    "go": "go",
    "c": "c",
    "cpp": "cpp",
}

EXTENSION_CANDIDATES = {
    "typescript": (".ts", ".tsx", ".mts", ".cts", "/index.ts", "/index.tsx"),
    "javascript": (".js", ".jsx", ".mjs", ".cjs", "/index.js", "/index.jsx"),
    "python": (".py", "/__init__.py"),
    "c": (".h", ".hpp", ".c", ".cc", ".cpp"),
    "cpp": (".hpp", ".h", ".cpp", ".cc", ".cxx"),
}

IMPORT_RE = {
    "typescript": re.compile(
        r"^\s*(?:import|export)\s+(?:type\s+)?(?:[^\"']+?\s+from\s+)?[\"']([^\"']+)[\"']",
        re.MULTILINE,
    ),
    "javascript": re.compile(
        r"^\s*(?:import|export)\s+(?:type\s+)?(?:[^\"']+?\s+from\s+)?[\"']([^\"']+)[\"']",
        re.MULTILINE,
    ),
    "python": re.compile(r"^\s*(?:from\s+([A-Za-z0-9_\.]+)\s+import|import\s+([A-Za-z0-9_\.]+))", re.MULTILINE),
    "rust": re.compile(r"^\s*use\s+([^;]+);", re.MULTILINE),
    "go": re.compile(r"^\s*import\s+(?:\([^)]*\)|\"([^\"]+)\")", re.MULTILINE | re.DOTALL),
    "c": re.compile(r"^\s*#include\s+[<\"]([^>\"]+)[>\"]", re.MULTILINE),
    "cpp": re.compile(r"^\s*#include\s+[<\"]([^>\"]+)[>\"]", re.MULTILINE),
}

REQUIRE_RE = re.compile(r"require\([\"']([^\"']+)[\"']\)")
GO_IMPORT_BLOCK_RE = re.compile(r"import\s*\((.*?)\)", re.DOTALL)
GO_IMPORT_ITEM_RE = re.compile(r'"([^"]+)"')

REGEX_SYMBOL_PATTERNS: dict[str, list[tuple[str, re.Pattern[str]]]] = {
    "typescript": [
        ("class", re.compile(r"^\s*(?:export\s+)?(?:default\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("interface", re.compile(r"^\s*(?:export\s+)?interface\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("type", re.compile(r"^\s*(?:export\s+)?type\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("enum", re.compile(r"^\s*(?:export\s+)?enum\s+([A-Za-z_][A-Za-z0-9_]*)")),
        (
            "function",
            re.compile(
                r"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)"
            ),
        ),
        (
            "function",
            re.compile(
                r"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:async\s*)?(?:<[^>]+>\s*)?(?:\([^)]*\)|[A-Za-z_][A-Za-z0-9_]*)\s*=>"
            ),
        ),
        (
            "method",
            re.compile(
                r"^\s*(?:public\s+|private\s+|protected\s+)?(?:async\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\("
            ),
        ),
    ],
    "javascript": [],
    "python": [
        ("class", re.compile(r"^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("function", re.compile(r"^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)")),
    ],
    "rust": [
        ("struct", re.compile(r"^\s*(?:pub(?:\([^)]+\))?\s+)?struct\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("enum", re.compile(r"^\s*(?:pub(?:\([^)]+\))?\s+)?enum\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("trait", re.compile(r"^\s*(?:pub(?:\([^)]+\))?\s+)?trait\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("module", re.compile(r"^\s*(?:pub(?:\([^)]+\))?\s+)?mod\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("function", re.compile(r"^\s*(?:pub(?:\([^)]+\))?\s+)?(?:async\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)")),
        ("impl", re.compile(r"^\s*impl(?:<[^>]+>)?\s+([A-Za-z_][A-Za-z0-9_:<>]*)")),
    ],
    "go": [
        ("type", re.compile(r"^\s*type\s+([A-Za-z_][A-Za-z0-9_]*)\s+")),
        ("function", re.compile(r"^\s*func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")),
        ("method", re.compile(r"^\s*func\s*\([^)]*\)\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(")),
    ],
    "c": [
        ("struct", re.compile(r"^\s*struct\s+([A-Za-z_][A-Za-z0-9_]*)\b")),
        ("enum", re.compile(r"^\s*enum\s+([A-Za-z_][A-Za-z0-9_]*)\b")),
        ("function", re.compile(r"^\s*[A-Za-z_][A-Za-z0-9_\s\*]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*\)\s*\{")),
    ],
    "cpp": [],
}
REGEX_SYMBOL_PATTERNS["javascript"] = REGEX_SYMBOL_PATTERNS["typescript"]
REGEX_SYMBOL_PATTERNS["cpp"] = REGEX_SYMBOL_PATTERNS["c"]


@dataclass(frozen=True)
class PackageScope:
    name: str
    rel_path: str
    ecosystem: str
    manifest_path: str


@dataclass(frozen=True)
class SymbolRecord:
    name: str
    kind: str
    start_line: int
    end_line: int
    qualified_name: str
    signature: str = ""
    docstring: str = ""
    visibility: str = ""
    parent_symbol: str = ""
    exported: bool = False


@dataclass(frozen=True)
class DependencyRecord:
    raw_target: str
    line: int
    kind: str
    imported_symbols: tuple[str, ...] = ()
    is_export: bool = False
    target_path: str = ""
    is_internal: bool = False


@dataclass(frozen=True)
class SemanticLineRecord:
    line_no: int
    content: str
    symbol: str


@dataclass(frozen=True)
class FileAnalysis:
    package: str
    package_root: str
    package_ecosystem: str
    parser: str
    symbols: tuple[SymbolRecord, ...] = field(default_factory=tuple)
    dependencies: tuple[DependencyRecord, ...] = field(default_factory=tuple)


@dataclass
class RepoPackageIndex:
    repo_name: str
    scopes: list[PackageScope]

    @property
    def by_name(self) -> dict[str, PackageScope]:
        return {scope.name: scope for scope in self.scopes if scope.name}

    def scope_for_file(self, rel_path: str) -> PackageScope:
        normalized = rel_path.strip("/")
        best: PackageScope | None = None
        for scope in self.scopes:
            prefix = scope.rel_path.strip("/")
            if not prefix:
                if best is None:
                    best = scope
                continue
            if normalized == prefix or normalized.startswith(prefix + "/"):
                if best is None or len(prefix) > len(best.rel_path.strip("/")):
                    best = scope
        if best is not None:
            return best
        return PackageScope(self.repo_name, "", "repo", "")


class _NodeProtocol:
    type: str
    text: bytes
    children: Sequence["_NodeProtocol"]

    def child_by_field_name(self, name: str): ...



def approx_tokens(text: str) -> int:
    return max(1, math.ceil(len(text) / 4))


@lru_cache(maxsize=1)
def tree_sitter_available() -> bool:
    return get_parser is not None and has_language is not None


@lru_cache(maxsize=32)
def parser_for_language(language: str):
    if not tree_sitter_available():
        return None
    mapped = TREE_SITTER_LANGUAGE_MAP.get(language)
    if not mapped or not has_language(mapped):
        return None
    return get_parser(mapped)


@lru_cache(maxsize=256)
def _read_manifest_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return ""


@lru_cache(maxsize=256)
def package_name_from_manifest(path: Path) -> tuple[str, str]:
    if path.name == "package.json":
        try:
            parsed = json.loads(_read_manifest_text(path) or "{}")
        except json.JSONDecodeError:
            parsed = {}
        name = parsed.get("name") if isinstance(parsed, dict) else None
        return (str(name or path.parent.name), "node")
    if path.name == "Cargo.toml" and tomllib is not None:
        try:
            parsed = tomllib.loads(_read_manifest_text(path))
        except tomllib.TOMLDecodeError:
            parsed = {}
        package = parsed.get("package", {}) if isinstance(parsed, dict) else {}
        name = package.get("name") if isinstance(package, dict) else None
        return (str(name or path.parent.name), "cargo")
    if path.name == "pyproject.toml" and tomllib is not None:
        try:
            parsed = tomllib.loads(_read_manifest_text(path))
        except tomllib.TOMLDecodeError:
            parsed = {}
        project = parsed.get("project", {}) if isinstance(parsed, dict) else {}
        name = project.get("name") if isinstance(project, dict) else None
        return (str(name or path.parent.name), "python")
    if path.name == "go.mod":
        for line in _read_manifest_text(path).splitlines():
            if line.startswith("module "):
                return (line.split(None, 1)[1].strip(), "go")
        return (path.parent.name, "go")
    return (path.parent.name, "repo")


MANIFEST_NAMES = ("package.json", "Cargo.toml", "go.mod", "pyproject.toml")


def build_repo_package_index(root: Path, repo_name: str) -> RepoPackageIndex:
    scopes = [PackageScope(repo_name, "", "repo", "")]
    for manifest_name in MANIFEST_NAMES:
        for manifest in root.rglob(manifest_name):
            rel_dir = manifest.parent.relative_to(root).as_posix()
            name, ecosystem = package_name_from_manifest(manifest)
            scopes.append(PackageScope(name, "" if rel_dir == "." else rel_dir, ecosystem, manifest.relative_to(root).as_posix()))
    deduped: dict[tuple[str, str], PackageScope] = {}
    for scope in sorted(scopes, key=lambda item: (len(item.rel_path), item.rel_path)):
        deduped[(scope.name, scope.rel_path)] = scope
    return RepoPackageIndex(repo_name=repo_name, scopes=list(deduped.values()))



def _node_text(node: _NodeProtocol) -> str:
    return node.text.decode("utf-8", errors="ignore")



def _line(node: _NodeProtocol) -> int:
    return int(node.start_point[0]) + 1



def _end_line(node: _NodeProtocol) -> int:
    return int(node.end_point[0]) + 1



def _name_from_node(node: _NodeProtocol) -> str:
    named = node.child_by_field_name("name")
    if named is not None:
        return _node_text(named).strip()
    for child in node.children:
        if child.type in {
            "identifier",
            "type_identifier",
            "field_identifier",
            "property_identifier",
            "package_identifier",
            "dotted_name",
            "scoped_identifier",
        }:
            return _node_text(child).strip()
    return ""



def _symbol_signature(node: _NodeProtocol) -> str:
    return _node_text(node).splitlines()[0].strip()[:240]



def _visibility(text: str, exported: bool) -> str:
    lowered = text.lower()
    if "private" in lowered:
        return "private"
    if "protected" in lowered:
        return "protected"
    if "public" in lowered or exported or lowered.startswith("export ") or lowered.startswith("pub "):
        return "public"
    return ""



def _extract_js_ts(root: _NodeProtocol) -> tuple[list[SymbolRecord], list[DependencyRecord]]:
    symbols: list[SymbolRecord] = []
    dependencies: list[DependencyRecord] = []

    def emit_symbol(node: _NodeProtocol, kind: str, parent: str = "", exported: bool = False) -> None:
        name = _name_from_node(node)
        if not name:
            return
        qualified = f"{parent}.{name}" if parent else name
        text = _node_text(node)
        symbols.append(
            SymbolRecord(
                name=name,
                kind=kind,
                start_line=_line(node),
                end_line=_end_line(node),
                qualified_name=qualified,
                signature=_symbol_signature(node),
                visibility=_visibility(text, exported),
                parent_symbol=parent,
                exported=exported,
            )
        )

    def walk(node: _NodeProtocol, parent: str = "", exported: bool = False) -> None:
        if node.type == "export_statement":
            for child in node.children:
                if child.type != "export":
                    walk(child, parent=parent, exported=True)
            return
        if node.type == "import_statement":
            match = re.search(r'[\"\']([^\"\']+)[\"\']', _node_text(node))
            if match:
                dependencies.append(
                    DependencyRecord(
                        raw_target=match.group(1),
                        line=_line(node),
                        kind="import",
                    )
                )
            return
        if node.type in {"class_declaration", "interface_declaration", "type_alias_declaration", "enum_declaration"}:
            emit_symbol(node, node.type.removesuffix("_declaration"), parent=parent, exported=exported)
            current_name = _name_from_node(node)
            for child in node.children:
                if child.type in {"class_body", "object_type", "interface_body"}:
                    for grandchild in child.children:
                        walk(grandchild, parent=current_name or parent, exported=exported)
            return
        if node.type == "method_definition":
            emit_symbol(node, "method", parent=parent, exported=exported)
            return
        if node.type == "public_field_definition":
            text = _node_text(node)
            if "=>" in text:
                emit_symbol(node, "method", parent=parent, exported=exported)
            return
        if node.type == "function_declaration":
            emit_symbol(node, "function", parent=parent, exported=exported)
            return
        if node.type == "lexical_declaration":
            for child in node.children:
                if child.type == "variable_declarator":
                    text = _node_text(child)
                    if any(marker in text for marker in ("=>", "function")):
                        emit_symbol(child, "function", parent=parent, exported=exported)
            return
        for child in node.children:
            walk(child, parent=parent, exported=exported)

    for child in root.children:
        walk(child)
    return symbols, dependencies



def _extract_python(root: _NodeProtocol) -> tuple[list[SymbolRecord], list[DependencyRecord]]:
    symbols: list[SymbolRecord] = []
    dependencies: list[DependencyRecord] = []

    def walk(node: _NodeProtocol, parent: str = "") -> None:
        if node.type == "decorated_definition":
            for child in node.children:
                walk(child, parent=parent)
            return
        if node.type == "import_statement":
            for child in node.children:
                if child.type == "dotted_name":
                    dependencies.append(DependencyRecord(_node_text(child), _line(node), "import"))
            return
        if node.type == "import_from_statement":
            module = next((child for child in node.children if child.type == "dotted_name"), None)
            if module is not None:
                dependencies.append(DependencyRecord(_node_text(module), _line(node), "import"))
            return
        if node.type == "class_definition":
            name = _name_from_node(node)
            if name:
                symbols.append(
                    SymbolRecord(name, "class", _line(node), _end_line(node), name, _symbol_signature(node), parent_symbol=parent)
                )
            for child in node.children:
                if child.type == "block":
                    for grandchild in child.children:
                        walk(grandchild, parent=name)
            return
        if node.type == "function_definition":
            name = _name_from_node(node)
            if name:
                qualified = f"{parent}.{name}" if parent else name
                symbols.append(
                    SymbolRecord(name, "method" if parent else "function", _line(node), _end_line(node), qualified, _symbol_signature(node), parent_symbol=parent)
                )
            return
        for child in node.children:
            walk(child, parent=parent)

    for child in root.children:
        walk(child)
    return symbols, dependencies



def _extract_rust(root: _NodeProtocol) -> tuple[list[SymbolRecord], list[DependencyRecord]]:
    symbols: list[SymbolRecord] = []
    dependencies: list[DependencyRecord] = []

    def walk(node: _NodeProtocol, parent: str = "") -> None:
        if node.type == "use_declaration":
            for child in node.children:
                if child.type in {"scoped_identifier", "identifier", "crate", "self", "super"}:
                    dependencies.append(DependencyRecord(_node_text(child), _line(node), "import"))
                    break
            else:
                dependencies.append(DependencyRecord(_node_text(node).removeprefix("use").strip().rstrip(";"), _line(node), "import"))
            return
        if node.type in {"struct_item", "enum_item", "trait_item", "mod_item", "function_item"}:
            name = _name_from_node(node)
            if name:
                qualified = f"{parent}.{name}" if parent else name
                kind = node.type.removesuffix("_item")
                symbols.append(
                    SymbolRecord(
                        name=name,
                        kind="function" if kind == "function" else kind,
                        start_line=_line(node),
                        end_line=_end_line(node),
                        qualified_name=qualified,
                        signature=_symbol_signature(node),
                        visibility=_visibility(_node_text(node), _node_text(node).strip().startswith("pub")),
                        parent_symbol=parent,
                        exported=_node_text(node).strip().startswith("pub"),
                    )
                )
            return
        if node.type == "impl_item":
            target = next((child for child in node.children if child.type == "type_identifier"), None)
            impl_name = _node_text(target).strip() if target is not None else "impl"
            symbols.append(
                SymbolRecord(impl_name, "impl", _line(node), _end_line(node), impl_name, _symbol_signature(node))
            )
            for child in node.children:
                if child.type == "declaration_list":
                    for grandchild in child.children:
                        walk(grandchild, parent=impl_name)
            return
        for child in node.children:
            walk(child, parent=parent)

    for child in root.children:
        walk(child)
    return symbols, dependencies



def _extract_go(root: _NodeProtocol) -> tuple[list[SymbolRecord], list[DependencyRecord]]:
    symbols: list[SymbolRecord] = []
    dependencies: list[DependencyRecord] = []
    for child in root.children:
        if child.type == "import_declaration":
            for import_spec in child.children:
                if import_spec.type == "import_spec":
                    match = re.search(r'"([^"]+)"', _node_text(import_spec))
                    if match:
                        dependencies.append(DependencyRecord(match.group(1), _line(import_spec), "import"))
        elif child.type == "type_declaration":
            for node in child.children:
                if node.type == "type_spec":
                    name = _name_from_node(node)
                    if name:
                        kind = "interface" if "interface" in _node_text(node) else "type"
                        symbols.append(SymbolRecord(name, kind, _line(node), _end_line(node), name, _symbol_signature(node)))
        elif child.type == "function_declaration":
            name = _name_from_node(child)
            if name:
                symbols.append(SymbolRecord(name, "function", _line(child), _end_line(child), name, _symbol_signature(child)))
        elif child.type == "method_declaration":
            name = _name_from_node(child)
            receiver = child.children[1] if len(child.children) > 1 else None
            receiver_text = _node_text(receiver).strip("() ") if receiver is not None else ""
            receiver_parts = receiver_text.split()
            parent = receiver_parts[-1].lstrip("*") if receiver_parts else ""
            if name:
                qualified = f"{parent}.{name}" if parent else name
                symbols.append(
                    SymbolRecord(name, "method", _line(child), _end_line(child), qualified, _symbol_signature(child), parent_symbol=parent)
                )
    return symbols, dependencies



def _extract_c_family(root: _NodeProtocol) -> tuple[list[SymbolRecord], list[DependencyRecord]]:
    symbols: list[SymbolRecord] = []
    dependencies: list[DependencyRecord] = []
    for child in root.children:
        if child.type == "preproc_include":
            match = re.search(r'[<\"]([^>\"]+)[>\"]', _node_text(child))
            if match:
                dependencies.append(DependencyRecord(match.group(1), _line(child), "include"))
        elif child.type in {"struct_specifier", "enum_specifier", "union_specifier"}:
            name = _name_from_node(child)
            if name:
                kind = child.type.removesuffix("_specifier")
                symbols.append(SymbolRecord(name, kind, _line(child), _end_line(child), name, _symbol_signature(child)))
        elif child.type == "function_definition":
            name = ""
            for grandchild in child.children:
                if grandchild.type == "function_declarator":
                    name = _name_from_node(grandchild)
                    break
            if name:
                symbols.append(SymbolRecord(name, "function", _line(child), _end_line(child), name, _symbol_signature(child)))
    return symbols, dependencies



def extract_tree_sitter_analysis(language: str, text: str) -> tuple[list[SymbolRecord], list[DependencyRecord], str]:
    parser = parser_for_language(language)
    if parser is None:
        return [], [], "regex"
    root = parser.parse(text.encode("utf-8", errors="ignore")).root_node
    if language in {"typescript", "javascript"}:
        symbols, dependencies = _extract_js_ts(root)
    elif language == "python":
        symbols, dependencies = _extract_python(root)
    elif language == "rust":
        symbols, dependencies = _extract_rust(root)
    elif language == "go":
        symbols, dependencies = _extract_go(root)
    elif language in {"c", "cpp"}:
        symbols, dependencies = _extract_c_family(root)
    else:
        symbols, dependencies = [], []
    if not symbols and not dependencies:
        return [], [], "regex"
    return symbols, dependencies, "tree-sitter"



def extract_regex_dependencies(text: str, language: str) -> list[DependencyRecord]:
    pattern = IMPORT_RE.get(language)
    if pattern is None:
        return []
    dependencies: list[DependencyRecord] = []
    if language == "go":
        for block in GO_IMPORT_BLOCK_RE.findall(text):
            for raw_target in GO_IMPORT_ITEM_RE.findall(block):
                line = text[: text.index(raw_target)].count("\n") + 1
                dependencies.append(DependencyRecord(raw_target, line, "import"))
        for line_no, line in enumerate(text.splitlines(), start=1):
            match = re.search(r'^\s*import\s+"([^"]+)"', line)
            if match:
                dependencies.append(DependencyRecord(match.group(1), line_no, "import"))
        return list(dict.fromkeys(dependencies))
    for match in pattern.finditer(text):
        raw_target = next((group for group in match.groups() if group), "").strip()
        if not raw_target:
            continue
        line_no = text[: match.start()].count("\n") + 1
        kind = "export" if language in {"typescript", "javascript"} and "export" in match.group(0) else "import"
        dependencies.append(DependencyRecord(raw_target, line_no, kind, is_export=kind == "export"))
    if language in {"typescript", "javascript"}:
        for match in REQUIRE_RE.finditer(text):
            line_no = text[: match.start()].count("\n") + 1
            dependencies.append(DependencyRecord(match.group(1), line_no, "require"))
    return list(dict.fromkeys(dependencies))



def extract_regex_symbols(text: str, language: str) -> list[SymbolRecord]:
    patterns = REGEX_SYMBOL_PATTERNS.get(language, [])
    lines = text.splitlines()
    anchors: list[tuple[int, str, str, str, bool]] = []
    class_stack: list[tuple[int, str]] = []
    for line_no, line in enumerate(lines, start=1):
        indent = len(line) - len(line.lstrip())
        if language == "python":
            while class_stack and indent <= class_stack[-1][0]:
                class_stack.pop()
        for kind, pattern in patterns:
            match = pattern.search(line)
            if not match:
                continue
            name = match.group(1)
            parent = class_stack[-1][1] if class_stack and kind == "function" else ""
            if kind == "class" and language == "python":
                class_stack.append((indent, name))
            qualified = f"{parent}.{name}" if parent and kind in {"function", "method"} else name
            anchors.append((line_no, name, kind if not parent else "method", qualified, line.strip().startswith(("export ", "pub "))))
            break
    symbols: list[SymbolRecord] = []
    for index, (line_no, name, kind, qualified, exported) in enumerate(anchors):
        end_line = anchors[index + 1][0] - 1 if index + 1 < len(anchors) else len(lines)
        parent = qualified.rsplit(".", 1)[0] if "." in qualified else ""
        signature = lines[line_no - 1].strip()[:240]
        symbols.append(
            SymbolRecord(
                name=name,
                kind=kind,
                start_line=line_no,
                end_line=max(line_no, end_line),
                qualified_name=qualified,
                signature=signature,
                visibility=_visibility(signature, exported),
                parent_symbol=parent,
                exported=exported,
            )
        )
    return symbols



def dedupe_symbols(symbols: Iterable[SymbolRecord]) -> tuple[SymbolRecord, ...]:
    deduped: dict[tuple[str, str, int, int], SymbolRecord] = {}
    for symbol in symbols:
        deduped[(symbol.qualified_name, symbol.kind, symbol.start_line, symbol.end_line)] = symbol
    return tuple(sorted(deduped.values(), key=lambda item: (item.start_line, item.end_line, item.qualified_name)))



def dedupe_dependencies(dependencies: Iterable[DependencyRecord]) -> tuple[DependencyRecord, ...]:
    deduped: dict[tuple[str, int, str, str], DependencyRecord] = {}
    for dependency in dependencies:
        deduped[(dependency.raw_target, dependency.line, dependency.kind, dependency.target_path)] = dependency
    return tuple(sorted(deduped.values(), key=lambda item: (item.line, item.raw_target, item.kind)))



def relative_dependency_target(source_path: str, raw_target: str, language: str) -> str | None:
    source = PurePosixPath(source_path)
    if language in {"typescript", "javascript"}:
        if not raw_target.startswith(("./", "../")):
            return None
        base = source.parent.joinpath(raw_target)
        candidates = [PurePosixPath(str(base) + suffix) for suffix in EXTENSION_CANDIDATES[language] if not suffix.startswith("/")]
        candidates.extend(base.joinpath(suffix.lstrip("/")) for suffix in EXTENSION_CANDIDATES[language] if suffix.startswith("/"))
        candidates.append(base)
        return next((candidate.as_posix() for candidate in candidates), None)
    if language in {"c", "cpp"} and not raw_target.startswith("<"):
        return source.parent.joinpath(raw_target).as_posix()
    return None



def resolve_dependencies(
    rel_path: str,
    language: str,
    dependencies: Sequence[DependencyRecord],
    package_index: RepoPackageIndex,
    known_files: set[str],
) -> tuple[DependencyRecord, ...]:
    resolved: list[DependencyRecord] = []
    by_name = package_index.by_name
    for dependency in dependencies:
        target_path = ""
        is_internal = False
        relative_target = relative_dependency_target(rel_path, dependency.raw_target, language)
        if relative_target:
            normalized = PurePosixPath(relative_target).as_posix()
            if normalized in known_files:
                target_path = normalized
                is_internal = True
            else:
                matches = [path for path in known_files if path.startswith(normalized.rstrip("/"))]
                if matches:
                    target_path = sorted(matches)[0]
                    is_internal = True
        if not target_path:
            direct_scope = by_name.get(dependency.raw_target)
            if direct_scope is not None:
                target_path = direct_scope.rel_path
                is_internal = True
            else:
                for package_name, scope in by_name.items():
                    if dependency.raw_target.startswith(package_name + "/"):
                        target_path = scope.rel_path
                        is_internal = True
                        break
        resolved.append(
            DependencyRecord(
                raw_target=dependency.raw_target,
                line=dependency.line,
                kind=dependency.kind,
                imported_symbols=dependency.imported_symbols,
                is_export=dependency.is_export,
                target_path=target_path,
                is_internal=is_internal,
            )
        )
    return dedupe_dependencies(resolved)



def analyze_file(
    root: Path,
    file_path: Path,
    rel_path: str,
    text: str,
    language: str,
    package_index: RepoPackageIndex,
    known_files: set[str] | None = None,
) -> FileAnalysis:
    del root, file_path
    scope = package_index.scope_for_file(rel_path)
    tree_symbols, tree_dependencies, parser = extract_tree_sitter_analysis(language, text)
    regex_symbols = extract_regex_symbols(text, language)
    regex_dependencies = extract_regex_dependencies(text, language)
    symbols = dedupe_symbols(tree_symbols or regex_symbols)
    dependencies = dedupe_dependencies(tree_dependencies or regex_dependencies)
    known_file_set = set(known_files or set())
    known_file_set.add(rel_path)
    return FileAnalysis(
        package=scope.name,
        package_root=scope.rel_path,
        package_ecosystem=scope.ecosystem,
        parser=parser,
        symbols=symbols,
        dependencies=resolve_dependencies(rel_path, language, dependencies, package_index, known_file_set),
    )



def chunk_code_with_symbols(text: str, symbols: Sequence[SymbolRecord]) -> list[Chunk]:
    lines = text.splitlines()
    if not lines:
        return []
    chunks: list[Chunk] = []
    first_symbol_line = min((symbol.start_line for symbol in symbols), default=1)
    if first_symbol_line > 1:
        import_block = "\n".join(lines[: first_symbol_line - 1]).strip()
        if import_block:
            chunks.append(
                Chunk(
                    content=import_block,
                    start_line=1,
                    end_line=first_symbol_line - 1,
                    symbol="imports",
                    kind="code",
                )
            )
    for symbol in symbols:
        start_index = max(0, symbol.start_line - 1)
        end_index = min(len(lines), symbol.end_line)
        section = "\n".join(lines[start_index:end_index]).strip()
        if not section:
            continue
        if approx_tokens(section) <= 1400:
            chunks.append(
                Chunk(
                    content=section,
                    start_line=symbol.start_line,
                    end_line=symbol.end_line,
                    symbol=symbol.qualified_name,
                    kind="code",
                )
            )
            continue
        window = 180
        overlap = 24
        local_start = start_index
        while local_start < end_index:
            local_end = min(end_index, local_start + window)
            content = "\n".join(lines[local_start:local_end]).strip()
            if content:
                chunks.append(
                    Chunk(
                        content=content,
                        start_line=local_start + 1,
                        end_line=local_end,
                        symbol=symbol.qualified_name,
                        kind="code",
                    )
                )
            if local_end >= end_index:
                break
            local_start = max(local_start + 1, local_end - overlap)
    if not chunks:
        return []
    deduped: dict[tuple[int, int, str], Chunk] = {}
    for chunk in chunks:
        deduped[(chunk.start_line, chunk.end_line, chunk.symbol)] = chunk
    return list(deduped.values())



def symbol_for_line(symbols: Sequence[SymbolRecord], line_no: int) -> str:
    containing = [symbol for symbol in symbols if symbol.start_line <= line_no <= symbol.end_line]
    if not containing:
        return ""
    containing.sort(key=lambda item: (item.end_line - item.start_line, item.start_line))
    return containing[0].qualified_name



def build_semantic_lines(text: str, symbols: Sequence[SymbolRecord], max_lines: int = 800) -> tuple[SemanticLineRecord, ...]:
    rows: list[SemanticLineRecord] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped:
            continue
        rows.append(SemanticLineRecord(line_no=line_no, content=stripped[:500], symbol=symbol_for_line(symbols, line_no)))
    if len(rows) <= max_lines:
        return tuple(rows)
    step = max(1, math.ceil(len(rows) / max_lines))
    sampled = rows[::step]
    return tuple(sampled[:max_lines])



def package_summary_rows(conn, repo: str) -> list[dict[str, object]]:
    packages = conn.execute(
        "SELECT DISTINCT package FROM chunks WHERE repo = ? AND package IS NOT NULL AND package != '' ORDER BY package",
        (repo,),
    ).fetchall()
    summaries: list[dict[str, object]] = []
    for package_row in packages:
        package = package_row[0]
        package_path_row = conn.execute(
            "SELECT package_root FROM symbols WHERE repo = ? AND package = ? AND package_root != '' ORDER BY package_root LIMIT 1",
            (repo, package),
        ).fetchone()
        package_root = package_path_row[0] if package_path_row else ""
        file_count = conn.execute(
            "SELECT COUNT(DISTINCT path) FROM chunks WHERE repo = ? AND package = ?",
            (repo, package),
        ).fetchone()[0]
        symbol_rows = conn.execute(
            "SELECT qualified_name, kind FROM symbols WHERE repo = ? AND package = ? ORDER BY start_line LIMIT 10",
            (repo, package),
        ).fetchall()
        dependency_rows = conn.execute(
            "SELECT dependency, target_path, is_internal FROM file_dependencies WHERE repo = ? AND package = ? ORDER BY is_internal DESC, dependency LIMIT 8",
            (repo, package),
        ).fetchall()
        path_rows = conn.execute(
            "SELECT path FROM chunks WHERE repo = ? AND package = ? GROUP BY path ORDER BY path LIMIT 6",
            (repo, package),
        ).fetchall()
        symbol_labels = [f"{row['kind']}:{row['qualified_name']}" for row in symbol_rows]
        dependency_labels = [row["target_path"] or row["dependency"] for row in dependency_rows]
        summary_bits = [f"{package} contains {file_count} indexed files"]
        if symbol_labels:
            summary_bits.append("primary symbols: " + ", ".join(symbol_labels[:4]))
        if dependency_labels:
            summary_bits.append("depends on " + ", ".join(dependency_labels[:4]))
        summaries.append(
            {
                "package": package,
                "package_root": package_root,
                "summary": ". ".join(summary_bits) + ".",
                "symbols": " | ".join(symbol_labels[:8]),
                "dependencies": " | ".join(dependency_labels[:8]),
                "file_count": int(file_count),
                "paths": " | ".join(row["path"] for row in path_rows),
            }
        )
    return summaries

from __future__ import annotations

import hashlib
import json
import math
import re
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Iterable, Sequence, cast

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    tomllib = None  # type: ignore[assignment]

from gitignore_parser import parse_gitignore
from pathspec import PathSpec
from qdrant_client import models

from .code_intel import (
    FileAnalysis,
    build_repo_package_index,
    build_semantic_lines,
    chunk_code_with_symbols,
    dedupe_symbols,
    extract_regex_symbols,
    package_summary_rows,
    analyze_file,
)
from .runtime import CHUNKER_NAME, INDEX_SCHEMA
from .storage import ensure_collection, get_embedder, git_branch_for, git_head_commit_for, repo_identity
from .types import Chunk, Fact, IndexInterrupted, SupportsQdrantCollectionAdmin, SupportsQdrantPointOps

DEFAULT_IGNORE_PATTERNS = [
    "node_modules/",
    "dist/",
    "build/",
    ".next/",
    ".turbo/",
    ".git/",
    "coverage/",
    "target/",
    "vendor/",
    "*.lock",
    "pnpm-lock.yaml",
    "package-lock.json",
    "yarn.lock",
    "*.png",
    "*.jpg",
    "*.jpeg",
    "*.gif",
    "*.webp",
    "*.mp4",
    "*.zip",
    "*.tar",
    "*.sqlite",
    "*.db",
    ".env",
    ".env.*",
]

CODE_EXTENSIONS = {
    ".py": "python",
    ".ts": "typescript",
    ".tsx": "typescript",
    ".mts": "typescript",
    ".cts": "typescript",
    ".js": "javascript",
    ".jsx": "javascript",
    ".mjs": "javascript",
    ".cjs": "javascript",
    ".html": "html",
    ".htm": "html",
    ".css": "css",
    ".scss": "css",
    ".sass": "css",
    ".less": "css",
    ".go": "go",
    ".rs": "rust",
    ".java": "java",
    ".cs": "csharp",
    ".rb": "ruby",
    ".php": "php",
    ".sh": "shell",
    ".zsh": "shell",
    ".lua": "lua",
    ".swift": "swift",
    ".kt": "kotlin",
    ".kts": "kotlin",
    ".c": "c",
    ".cc": "cpp",
    ".cpp": "cpp",
    ".h": "c",
    ".hpp": "cpp",
    ".proto": "proto",
    ".sql": "sql",
    ".zig": "zig",
}

MARKDOWN_EXTENSIONS = {".md", ".mdx", ".rst", ".txt"}
CONFIG_EXTENSIONS = {".json", ".yaml", ".yml", ".toml", ".ini", ".conf", ".env", ".properties", ".xml", ".ui", ".glade"}
LOG_EXTENSIONS = {".log", ".jsonl"}
SPECIAL_CODE_FILENAMES = {
    "dockerfile": "dockerfile",
    "justfile": "just",
    "makefile": "make",
    "jenkinsfile": "groovy",
    ".zshrc": "shell",
    ".zprofile": "shell",
    ".zshenv": "shell",
    ".zlogin": "shell",
    ".zlogout": "shell",
}
SYSTEMD_UNIT_SUFFIXES = {".service", ".socket", ".timer", ".mount", ".path", ".target", ".slice"}
ZSH_DOTFILE_NAMES = {".zshrc", ".zprofile", ".zshenv", ".zlogin", ".zlogout"}
HYPRLAND_KEYWORDS = (
    "bind",
    "binde",
    "bindm",
    "bindel",
    "bindl",
    "bindr",
    "exec",
    "exec-once",
    "windowrule",
    "windowrulev2",
    "env",
)

SYMBOL_PATTERNS = [
    re.compile(r"^\s*(?:export\s+)?(?:default\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*(?:export\s+)?(?:default\s+)?interface\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(
        r"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:async\s*)?(?:<[^>]+>\s*)?(?:\([^)]*\)|[A-Za-z_][A-Za-z0-9_]*)\s*=>"
    ),
    re.compile(r"^\s*(?:export\s+)?(?:type|enum|namespace)\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*(?:pub(?:\([^)]+\))?\s+)?(?:async\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*fn\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*(?:pub(?:\([^)]+\))?\s+)?(?:trait|enum|struct|mod)\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*impl(?:<[^>]+>)?\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*(?:data\s+|sealed\s+|enum\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*object\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*(?:override\s+|suspend\s+|inline\s+)*fun\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(
        r"^\s*create\s+(?:or\s+replace\s+)?(?:table|view|function|procedure|trigger|index)\s+([A-Za-z_][A-Za-z0-9_.]*)",
        re.IGNORECASE,
    ),
]
SHELL_FUNCTION_PATTERN = re.compile(
    r"^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_.-]*)\s*(?:\(\s*\))?\s*\{"
)
SHELL_ALIAS_PATTERN = re.compile(r"^\s*alias\s+([A-Za-z_][A-Za-z0-9_.-]*)=")
SHELL_EXPORT_PATTERN = re.compile(r"^\s*export\s+([A-Za-z_][A-Za-z0-9_]*)=")
SHELL_CASE_BRANCH_PATTERN = re.compile(r"^\s*([A-Za-z0-9_.-]+|\*)\)\s*$")
SHELL_TOOL_PATTERNS = [
    re.compile(r"^\s*(?:need_cmd|require_cmd|ensure_cmd|has_cmd)\s+['\"]?([A-Za-z0-9_.+-]+)"),
    re.compile(r"\bcommand -v\s+['\"]?([A-Za-z0-9_.+-]+)"),
]
TOML_SECTION_PATTERN = re.compile(r"^\s*\[([^\]]+)\]\s*$")
YAML_SECTION_PATTERN = re.compile(r"^[A-Za-z0-9_-]+:\s*(?:#.*)?$")
CSS_SELECTOR_PATTERN = re.compile(r"^\s*([^@/{][^{]+)\{\s*$")
CSS_AT_RULE_PATTERN = re.compile(r"^\s*(@[A-Za-z0-9_-]+[^{]*)\{\s*$")
HTML_SECTION_PATTERN = re.compile(r"^\s*<(main|section|article|nav|header|footer|aside|form|dialog|template)\b([^>]*)>")
XML_OBJECT_PATTERN = re.compile(r"^\s*<(object|template)\b([^>]*)>")
DECORATOR_PATTERN = re.compile(
    r"@(?P<name>Controller|Get|Post|Put|Patch|Delete|All|Head|Options|Injectable|Entity|Module|UseGuards|UseInterceptors|UsePipes)\s*(?:\((?P<args>[^)]*)\))?"
)
CLASS_PATTERN = re.compile(r"^\s*(?:export\s+)?class\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)")
METHOD_PATTERN = re.compile(r"^\s*(?:public\s+|private\s+|protected\s+)?(?:async\s+)?(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\(")
HTTP_METHOD_DECORATORS = {"Get", "Post", "Put", "Patch", "Delete", "All", "Head", "Options"}
NEST_SWAGGER_DECORATOR_RE = re.compile(r"@(?P<name>Api[A-Za-z0-9_]+)\s*(?:\((?P<args>[^)]*)\))?")
NEST_CONTROLLER_BLOCK_RE = re.compile(
    r"@Controller\s*(?:\((?P<args>.*?)\))?\s*(?:export\s+)?class\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)",
    re.DOTALL,
)
NEST_MODULE_BLOCK_RE = re.compile(
    r"@Module\s*\(\s*\{(?P<body>.*?)\}\s*\)\s*(?:export\s+)?class\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)",
    re.DOTALL,
)
NEST_PROCESSOR_BLOCK_RE = re.compile(
    r"@Processor\s*\((?P<args>.*?)\)\s*(?:export\s+)?class\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)",
    re.DOTALL,
)
NEST_ENTITY_REPOSITORY_DECORATOR_RE = re.compile(
    r"@EntityRepository\s*\((?P<entity>[A-Za-z_][A-Za-z0-9_]*)\)\s*(?:export\s+)?class\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)",
    re.DOTALL,
)
ENTITY_REPOSITORY_EXTENDS_RE = re.compile(
    r"(?:export\s+)?class\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s+extends\s+(?:[A-Za-z_][A-Za-z0-9_.]*\.)?EntityRepository\s*<\s*(?P<entity>[A-Za-z_][A-Za-z0-9_]*)\s*>",
    re.DOTALL,
)
RELATION_DECORATOR_RE = re.compile(
    r"@(?P<name>OneToOne|OneToMany|ManyToOne|ManyToMany)\s*\(\s*\(\)\s*=>\s*(?P<target>[A-Za-z_][A-Za-z0-9_]*)",
)
EXPRESS_ROUTE_RE = re.compile(
    r"\b(?P<object>[A-Za-z_][A-Za-z0-9_]*)\.(?P<method>get|post|put|patch|delete|all|options|head|use)\s*\((?P<args>.*?)\)",
    re.DOTALL,
)
FASTIFY_ROUTE_RE = re.compile(
    r"\b(?P<object>[A-Za-z_][A-Za-z0-9_]*)\.(?P<method>get|post|put|patch|delete|options|head|all)\s*\((?P<args>.*?)\)",
    re.DOTALL,
)
FASTIFY_ROUTE_OBJECT_RE = re.compile(
    r"\b(?P<object>[A-Za-z_][A-Za-z0-9_]*)\.route\s*\(\s*\{(?P<body>.*?)\}\s*\)",
    re.DOTALL,
)
FASTIFY_REGISTER_RE = re.compile(
    r"\b(?P<object>[A-Za-z_][A-Za-z0-9_]*)\.register\s*\(\s*(?P<plugin>[A-Za-z_][A-Za-z0-9_]*)\s*,\s*\{(?P<body>.*?)\}\s*\)",
    re.DOTALL,
)
REACT_ROUTE_RE = re.compile(
    r"(?:<Route[^>]*\bpath\s*=\s*|path\s*:\s*)(?P<quote>['\"`])(?P<path>[^'\"`]+)(?P=quote)"
)
QUERY_KEY_RE = re.compile(r"queryKey\s*:\s*\[(?P<body>.*?)\]", re.DOTALL)
API_CALL_RE = re.compile(
    r"\b(?P<client>fetch|axios(?:\.(?:get|post|put|patch|delete))?|[A-Za-z_][A-Za-z0-9_]*\.(?:get|post|put|patch|delete))\s*\(\s*(?P<quote>['\"`])(?P<path>[^'\"`]+)(?P=quote)"
)
ZOD_SCHEMA_RE = re.compile(
    r"(?:export\s+)?const\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*Schema)\s*=\s*z\.(?:object|array|string|number|boolean|enum|union|discriminatedUnion)\b"
)
ZUSTAND_STORE_RE = re.compile(
    r"(?:export\s+)?const\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*Store)\s*=\s*create(?:<[^>]+>)?\s*\("
)
TS_PATH_ALIAS_RE = re.compile(r"(?P<quote>['\"])(?P<alias>[^'\"]+)(?P=quote)\s*:\s*\[(?P<body>[^\]]*)\]")
JS_ALIAS_OBJECT_RE = re.compile(r"alias\s*:\s*\{(?P<body>.*?)\}", re.DOTALL)
JS_KEY_VALUE_STRING_RE = re.compile(r"(?P<key>[A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?P<quote>['\"`])(?P<value>[^'\"`]+)(?P=quote)")
JS_BOOLEAN_RE = re.compile(r"(?P<key>[A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?P<value>true|false)\b")
JS_NUMBER_RE = re.compile(r"(?P<key>[A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?P<value>\d+)\b")
JS_ARRAY_RE = re.compile(r"(?P<key>[A-Za-z_][A-Za-z0-9_]*)\s*:\s*\[(?P<body>.*?)\]", re.DOTALL)


def approx_tokens(text: str) -> int:
    return max(1, math.ceil(len(text) / 4))


def hash_file(path: Path) -> str:
    digest = hashlib.sha1()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def batched(items: Sequence, size: int):
    for index in range(0, len(items), size):
        yield items[index : index + size]


def extract_symbol(line: str) -> str:
    for pattern in SYMBOL_PATTERNS:
        match = pattern.search(line)
        if match:
            return match.group(1)
    return ""


def attr_value(fragment: str, attr: str) -> str:
    match = re.search(rf'{attr}="([^"]+)"', fragment)
    return match.group(1).strip() if match else ""


def normalize_hyprland_mods(mods: str) -> str:
    normalized = []
    for part in re.split(r"[+ ]+", mods):
        part = part.strip()
        if not part:
            continue
        normalized.append(part if part.startswith("$") else part.upper())
    return "+".join(normalized)


def hyprland_symbol(stripped: str) -> str:
    key, _, value = stripped.partition("=")
    key = key.strip()
    value = value.strip()
    if key.startswith("bind"):
        parts = [part.strip() for part in value.split(",")]
        if len(parts) >= 3:
            mods = normalize_hyprland_mods(parts[0])
            key_name = parts[1].strip().upper()
            action = parts[2].strip()
            return f"{key}:{mods}+{key_name}:{action}"
    if key in {"exec", "exec-once"}:
        command = value.split()[0] if value else "-"
        return f"{key}:{command}"
    if key.startswith("windowrule"):
        return f"{key}:{value[:80]}"
    if key == "env":
        env_key, _, _env_value = value.partition(",")
        return f"env:{env_key.strip()}"
    return key


def html_symbol(line: str) -> str:
    match = HTML_SECTION_PATTERN.search(line)
    if not match:
        return ""
    tag = match.group(1)
    attrs = match.group(2)
    element_id = attr_value(attrs, "id")
    class_name = attr_value(attrs, "class").split()[0] if attr_value(attrs, "class") else ""
    if element_id:
        return f"{tag}#{element_id}"
    if class_name:
        return f"{tag}.{class_name}"
    return tag


def xml_ui_symbol(line: str) -> str:
    match = XML_OBJECT_PATTERN.search(line)
    if not match:
        return ""
    tag = match.group(1)
    attrs = match.group(2)
    class_name = attr_value(attrs, "class")
    element_id = attr_value(attrs, "id")
    if class_name and element_id:
        return f"{tag}:{class_name}#{element_id}"
    if class_name:
        return f"{tag}:{class_name}"
    if element_id:
        return f"{tag}:#{element_id}"
    return tag


def detect_kind(path: Path) -> tuple[str, str]:
    special_name = path.name.lower()
    if special_name in SPECIAL_CODE_FILENAMES:
        return "code", SPECIAL_CODE_FILENAMES[special_name]
    if special_name == "hyprland.conf":
        return "config", "hyprland"
    suffix = path.suffix.lower()
    if suffix in SYSTEMD_UNIT_SUFFIXES:
        return "config", "systemd"
    if suffix in CODE_EXTENSIONS:
        return "code", CODE_EXTENSIONS[suffix]
    if suffix in MARKDOWN_EXTENSIONS:
        return "docs", "markdown"
    if suffix in LOG_EXTENSIONS:
        return "log", "log"
    if suffix in CONFIG_EXTENSIONS:
        return "config", suffix.lstrip(".")
    return "text", suffix.lstrip(".") or "text"


def normalize_fact_value(value: str) -> str:
    return value.strip().strip('"').strip("'")


def find_line_no(text: str, start: int) -> int:
    return text[:start].count("\n") + 1


def strip_wrapping_quotes(value: str) -> str:
    stripped = value.strip()
    if len(stripped) >= 2 and stripped[0] == stripped[-1] and stripped[0] in {'"', "'", "`"}:
        return stripped[1:-1]
    return stripped


def split_top_level(text: str, delimiter: str = ",") -> list[str]:
    items: list[str] = []
    current: list[str] = []
    paren_depth = 0
    bracket_depth = 0
    brace_depth = 0
    quote = ""
    escaped = False
    for char in text:
        current.append(char)
        if quote:
            if escaped:
                escaped = False
                continue
            if char == "\\":
                escaped = True
                continue
            if char == quote:
                quote = ""
            continue
        if char in {'"', "'", "`"}:
            quote = char
            continue
        if char == "(":
            paren_depth += 1
            continue
        if char == ")":
            paren_depth = max(0, paren_depth - 1)
            continue
        if char == "[":
            bracket_depth += 1
            continue
        if char == "]":
            bracket_depth = max(0, bracket_depth - 1)
            continue
        if char == "{":
            brace_depth += 1
            continue
        if char == "}":
            brace_depth = max(0, brace_depth - 1)
            continue
        if char == delimiter and paren_depth == 0 and bracket_depth == 0 and brace_depth == 0:
            item = "".join(current[:-1]).strip()
            if item:
                items.append(item)
            current = []
    tail = "".join(current).strip()
    if tail:
        items.append(tail)
    return items


def identifierish(value: str) -> str:
    cleaned = re.sub(r"^\.\.\.", "", value.strip())
    cleaned = strip_wrapping_quotes(cleaned)
    if cleaned.startswith("(") and cleaned.endswith(")"):
        cleaned = cleaned[1:-1].strip()
    cleaned = cleaned.split(" as ", 1)[0].strip()
    cleaned = cleaned.split(".", 1)[0].strip()
    match = re.search(r"[A-Za-z_][A-Za-z0-9_./:@-]*", cleaned)
    return match.group(0) if match else cleaned[:80]


def extract_array_items(body: str, key: str) -> list[str]:
    match = re.search(rf"\b{re.escape(key)}\s*:\s*\[(?P<body>.*?)\]", body, re.DOTALL)
    if not match:
        return []
    items: list[str] = []
    for item in split_top_level(match.group("body")):
        token = identifierish(item)
        if token:
            items.append(token)
    return items


def imported_modules(analysis: FileAnalysis | None) -> set[str]:
    if analysis is None:
        return set()
    modules: set[str] = set()
    for dependency in analysis.dependencies:
        raw_target = dependency.raw_target.strip()
        if not raw_target:
            continue
        modules.add(raw_target)
        modules.add(raw_target.split("/", 1)[0])
    return modules


def symbol_lookup(analysis: FileAnalysis | None) -> dict[str, object]:
    if analysis is None:
        return {}
    return {symbol.name: symbol for symbol in analysis.symbols}


def append_unique_fact(facts: list[Fact], seen: set[tuple[str, str, str, int]], fact: Fact) -> None:
    key = (fact.kind, fact.key, fact.value, fact.line)
    if key in seen:
        return
    seen.add(key)
    facts.append(fact)


def extract_shell_facts(text: str) -> list[Fact]:
    facts: list[Fact] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if match := SHELL_ALIAS_PATTERN.search(line):
            _, _, value = stripped.partition("=")
            facts.append(Fact("alias", match.group(1), normalize_fact_value(value), line_no))
            continue
        if match := SHELL_EXPORT_PATTERN.search(line):
            _, _, value = stripped.partition("=")
            facts.append(Fact("env", match.group(1), normalize_fact_value(value), line_no))
            continue
        if match := SHELL_FUNCTION_PATTERN.search(line):
            facts.append(Fact("function", match.group(1), "defined", line_no))
        if match := SHELL_CASE_BRANCH_PATTERN.search(line):
            facts.append(Fact("case-branch", match.group(1), "case branch", line_no))
        for pattern in SHELL_TOOL_PATTERNS:
            if match := pattern.search(line):
                facts.append(Fact("tool", match.group(1), "required", line_no))
                break
    return facts


def extract_hyprland_facts(text: str) -> list[Fact]:
    facts: list[Fact] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = [part.strip() for part in stripped.split("=", 1)]
        if key.startswith("bind"):
            parts = [part.strip() for part in value.split(",")]
            if len(parts) >= 4:
                mods = normalize_hyprland_mods(parts[0])
                key_name = parts[1].upper()
                action = ", ".join(parts[2:])
                facts.append(Fact("keybind", f"{mods}+{key_name}", action, line_no))
            continue
        if key in {"exec", "exec-once"}:
            command = value
            command_name = Path(command.split()[0]).name if command else "-"
            facts.append(Fact("startup" if key == "exec-once" else "exec", command_name, command, line_no))
            continue
        if key == "env":
            env_key, _, env_value = value.partition(",")
            facts.append(Fact("env", env_key.strip(), env_value.strip(), line_no))
            continue
        if key.startswith("windowrule"):
            facts.append(Fact("windowrule", value[:80], value, line_no))
    return facts


def extract_package_facts(text: str, manager: str) -> list[Fact]:
    facts: list[Fact] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        package = stripped.split("|", 1)[0].strip()
        facts.append(Fact("package", package, manager, line_no))
    return facts


def extract_toml_facts(text: str) -> list[Fact]:
    facts: list[Fact] = []
    current_section = ""
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if match := TOML_SECTION_PATTERN.search(line):
            current_section = match.group(1).strip()
            facts.append(Fact("config-section", current_section, "section", line_no))
            continue
        if "=" in stripped:
            key, value = [part.strip() for part in stripped.split("=", 1)]
            full_key = f"{current_section}.{key}" if current_section else key
            facts.append(Fact("config-key", full_key, normalize_fact_value(value), line_no))
    return facts


def extract_yaml_facts(text: str) -> list[Fact]:
    facts: list[Fact] = []
    current_section = ""
    for line_no, line in enumerate(text.splitlines(), start=1):
        if not line.strip() or line.strip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        stripped = line.strip()
        if indent == 0 and ":" in stripped:
            key, value = stripped.split(":", 1)
            current_section = key.strip()
            facts.append(Fact("config-section", current_section, "section", line_no))
            if value.strip():
                facts.append(Fact("config-key", current_section, normalize_fact_value(value), line_no))
        elif indent > 0 and ":" in stripped:
            key, value = stripped.split(":", 1)
            full_key = f"{current_section}.{key.strip()}" if current_section else key.strip()
            if value.strip():
                facts.append(Fact("config-key", full_key, normalize_fact_value(value), line_no))
    return facts


def extract_compose_yaml_facts(text: str) -> list[Fact]:
    facts: list[Fact] = []
    in_services = False
    current_service = ""
    current_list_key = ""
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        if indent == 0:
            current_list_key = ""
            current_service = ""
            in_services = stripped.startswith("services:")
            continue
        if not in_services:
            continue
        if indent == 2 and stripped.endswith(":"):
            current_service = stripped[:-1].strip().strip('"').strip("'")
            facts.append(Fact("compose-service", current_service, "declared", line_no))
            current_list_key = ""
            continue
        if not current_service:
            continue
        if indent >= 6 and current_list_key == "environment" and ":" in stripped and not stripped.startswith("- "):
            env_key, env_value = stripped.split(":", 1)
            facts.append(
                Fact(
                    "compose-env",
                    f"{current_service}.{env_key.strip()}",
                    normalize_fact_value(env_value) or "set",
                    line_no,
                )
            )
            continue
        if indent >= 4 and ":" in stripped and not stripped.startswith("- "):
            key, value = stripped.split(":", 1)
            key = key.strip()
            value = normalize_fact_value(value)
            if key in {"ports", "depends_on", "profiles", "environment"}:
                current_list_key = key
                if value:
                    facts.append(Fact("compose-config", f"{current_service}.{key}", value, line_no))
                continue
            current_list_key = ""
            if key in {"image", "build", "command", "container_name", "restart"} and value:
                facts.append(Fact("compose-config", f"{current_service}.{key}", value, line_no))
            elif key in {"target", "dockerfile"} and value:
                facts.append(Fact("compose-build", f"{current_service}.{key}", value, line_no))
            continue
        if indent >= 6 and stripped.startswith("- ") and current_list_key:
            item = normalize_fact_value(stripped[2:])
            if not item:
                continue
            if current_list_key == "ports":
                facts.append(Fact("compose-port", current_service, item, line_no))
            elif current_list_key == "depends_on":
                facts.append(Fact("compose-depends-on", current_service, item, line_no))
            elif current_list_key == "profiles":
                facts.append(Fact("compose-profile", current_service, item, line_no))
            elif current_list_key == "environment":
                env_key, _, env_value = item.partition("=")
                facts.append(Fact("compose-env", f"{current_service}.{env_key}", env_value or "set", line_no))
            continue
    return facts


def decorator_arg_value(raw_args: str | None) -> str:
    if not raw_args:
        return ""
    if match := re.search(r"""['"]([^'"]+)['"]""", raw_args):
        return match.group(1)
    return normalize_fact_value(raw_args)


def extract_typescript_backend_facts(text: str, analysis: FileAnalysis | None = None) -> list[Fact]:
    facts: list[Fact] = []
    seen: set[tuple[str, str, str, int]] = set()
    pending_decorators: list[tuple[str, str, int]] = []
    current_class = ""
    controller_base = ""
    symbol_by_name = symbol_lookup(analysis)
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        if match := DECORATOR_PATTERN.match(stripped):
            pending_decorators.append((match.group("name"), decorator_arg_value(match.group("args")), line_no))
            continue
        if match := NEST_SWAGGER_DECORATOR_RE.match(stripped):
            decorator_name = match.group("name")
            target_name = current_class or "file"
            append_unique_fact(
                facts,
                seen,
                Fact("swagger-decorator", f"{target_name}.{decorator_name}", decorator_arg_value(match.group("args")) or "present", line_no),
            )
            continue
        if match := CLASS_PATTERN.match(line):
            class_name = match.group("name")
            current_class = class_name
            controller_base = ""
            handled = False
            for decorator_name, decorator_value, decorator_line in pending_decorators:
                if decorator_name == "Controller":
                    controller_base = decorator_value or "/"
                    append_unique_fact(facts, seen, Fact("route-controller", class_name, controller_base, decorator_line))
                    handled = True
                elif decorator_name == "Injectable":
                    append_unique_fact(facts, seen, Fact("service", class_name, "injectable", decorator_line))
                    handled = True
                elif decorator_name == "Entity":
                    append_unique_fact(facts, seen, Fact("entity", class_name, decorator_value or class_name, decorator_line))
                    handled = True
                elif decorator_name == "Module":
                    append_unique_fact(facts, seen, Fact("module", class_name, "nest-module", decorator_line))
                    handled = True
                elif decorator_name == "Injectable" and class_name.endswith("Guard"):
                    append_unique_fact(facts, seen, Fact("guard", class_name, "injectable", decorator_line))
                    handled = True
            if not handled:
                if class_name.endswith("Controller"):
                    append_unique_fact(facts, seen, Fact("route-controller", class_name, "controller", line_no))
                elif class_name.endswith("Service"):
                    append_unique_fact(facts, seen, Fact("service", class_name, "class", line_no))
                elif class_name.endswith("Entity"):
                    append_unique_fact(facts, seen, Fact("entity", class_name, class_name, line_no))
            if class_name.endswith("Dto"):
                append_unique_fact(facts, seen, Fact("dto", class_name, "class", line_no))
            if class_name.endswith("Guard"):
                append_unique_fact(facts, seen, Fact("guard", class_name, "class", line_no))
            if class_name.endswith("Interceptor"):
                append_unique_fact(facts, seen, Fact("interceptor", class_name, "class", line_no))
            if class_name.endswith("Pipe"):
                append_unique_fact(facts, seen, Fact("pipe", class_name, "class", line_no))
            if class_name.endswith("Processor"):
                append_unique_fact(facts, seen, Fact("queue-processor", class_name, "class", line_no))
            pending_decorators = []
            continue
        if match := METHOD_PATTERN.match(line):
            method_name = match.group("name")
            for decorator_name, decorator_value, decorator_line in pending_decorators:
                if decorator_name in HTTP_METHOD_DECORATORS:
                    path = decorator_value or "/"
                    full_path = path
                    if controller_base and path.startswith("/"):
                        full_path = f"{controller_base.rstrip('/')}{path}"
                    elif controller_base and path != "/":
                        full_path = f"{controller_base.rstrip('/')}/{path.lstrip('/')}"
                    elif controller_base:
                        full_path = controller_base
                    append_unique_fact(
                        facts,
                        seen,
                        Fact("route-handler", f"{decorator_name.upper()} {full_path or '/'}", f"{current_class}.{method_name}" if current_class else method_name, decorator_line),
                    )
                elif decorator_name == "UseGuards":
                    for guard in split_top_level(decorator_value):
                        target = identifierish(guard)
                        if target:
                            append_unique_fact(
                                facts,
                                seen,
                                Fact("guard", f"{current_class}.{method_name}" if current_class else method_name, target, decorator_line),
                            )
                elif decorator_name == "UseInterceptors":
                    for interceptor in split_top_level(decorator_value):
                        target = identifierish(interceptor)
                        if target:
                            append_unique_fact(
                                facts,
                                seen,
                                Fact("interceptor", f"{current_class}.{method_name}" if current_class else method_name, target, decorator_line),
                            )
                elif decorator_name == "UsePipes":
                    for pipe in split_top_level(decorator_value):
                        target = identifierish(pipe)
                        if target:
                            append_unique_fact(
                                facts,
                                seen,
                                Fact("pipe", f"{current_class}.{method_name}" if current_class else method_name, target, decorator_line),
                            )
            pending_decorators = []
            continue
        if pending_decorators and not stripped.startswith("@"):
            pending_decorators = []
    for match in NEST_MODULE_BLOCK_RE.finditer(text):
        module_name = match.group("name")
        body = match.group("body")
        line_no = find_line_no(text, match.start())
        append_unique_fact(facts, seen, Fact("module", module_name, "nest-module", line_no))
        for key, kind_name in (
            ("imports", "module-import"),
            ("controllers", "module-controller"),
            ("providers", "module-provider"),
            ("exports", "module-export"),
        ):
            for item in extract_array_items(body, key):
                append_unique_fact(facts, seen, Fact(kind_name, module_name, item, line_no))
    for match in NEST_CONTROLLER_BLOCK_RE.finditer(text):
        append_unique_fact(
            facts,
            seen,
            Fact("route-controller", match.group("name"), decorator_arg_value(match.group("args")) or "/", find_line_no(text, match.start())),
        )
    for match in NEST_PROCESSOR_BLOCK_RE.finditer(text):
        queue_name = decorator_arg_value(match.group("args")) or "default"
        append_unique_fact(
            facts,
            seen,
            Fact("queue-processor", match.group("name"), queue_name, find_line_no(text, match.start())),
        )
    for match in re.finditer(
        r"@(?P<kind>Cron|Interval|Timeout)\s*\((?P<args>.*?)\)\s*(?:public\s+|private\s+|protected\s+)?(?:async\s+)?(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\(",
        text,
        re.DOTALL,
    ):
        append_unique_fact(
            facts,
            seen,
            Fact("scheduled-job", match.group("name"), f"{match.group('kind')} {decorator_arg_value(match.group('args'))}".strip(), find_line_no(text, match.start())),
        )
    for match in re.finditer(
        r"@Process\s*\((?P<args>.*?)\)\s*(?:public\s+|private\s+|protected\s+)?(?:async\s+)?(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\(",
        text,
        re.DOTALL,
    ):
        append_unique_fact(
            facts,
            seen,
            Fact("queue-job", match.group("name"), decorator_arg_value(match.group("args")) or "process", find_line_no(text, match.start())),
        )
    current_class_name = ""
    current_class_indent = 0
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if match := CLASS_PATTERN.match(line):
            current_class_name = match.group("name")
            current_class_indent = len(line) - len(line.lstrip())
        elif current_class_name and stripped.startswith("}"):
            current_class_name = ""
            current_class_indent = 0
        elif current_class_name:
            if match := RELATION_DECORATOR_RE.search(stripped):
                append_unique_fact(
                    facts,
                    seen,
                    Fact("relation", current_class_name, f"{match.group('name')}:{match.group('target')}", line_no),
                )
            if match := NEST_SWAGGER_DECORATOR_RE.match(stripped):
                append_unique_fact(
                    facts,
                    seen,
                    Fact("swagger-decorator", current_class_name, match.group("name"), line_no),
                )
            if match := re.match(r"@UseGuards\((?P<args>[^)]*)\)", stripped):
                for guard in split_top_level(match.group("args")):
                    target = identifierish(guard)
                    if target:
                        append_unique_fact(facts, seen, Fact("guard", current_class_name, target, line_no))
            if match := re.match(r"@UseInterceptors\((?P<args>[^)]*)\)", stripped):
                for interceptor in split_top_level(match.group("args")):
                    target = identifierish(interceptor)
                    if target:
                        append_unique_fact(facts, seen, Fact("interceptor", current_class_name, target, line_no))
            if match := re.match(r"@UsePipes\((?P<args>[^)]*)\)", stripped):
                for pipe in split_top_level(match.group("args")):
                    target = identifierish(pipe)
                    if target:
                        append_unique_fact(facts, seen, Fact("pipe", current_class_name, target, line_no))
    for match in NEST_ENTITY_REPOSITORY_DECORATOR_RE.finditer(text):
        append_unique_fact(
            facts,
            seen,
            Fact("repository", match.group("name"), match.group("entity"), find_line_no(text, match.start())),
        )
    for match in ENTITY_REPOSITORY_EXTENDS_RE.finditer(text):
        append_unique_fact(
            facts,
            seen,
            Fact("repository", match.group("name"), match.group("entity"), find_line_no(text, match.start())),
        )
    for symbol_name, symbol in symbol_by_name.items():
        if symbol_name.endswith("Dto"):
            append_unique_fact(facts, seen, Fact("dto", symbol_name, "symbol", symbol.start_line))
        if symbol_name.endswith("Guard"):
            append_unique_fact(facts, seen, Fact("guard", symbol_name, "symbol", symbol.start_line))
        if symbol_name.endswith("Interceptor"):
            append_unique_fact(facts, seen, Fact("interceptor", symbol_name, "symbol", symbol.start_line))
        if symbol_name.endswith("Pipe"):
            append_unique_fact(facts, seen, Fact("pipe", symbol_name, "symbol", symbol.start_line))
    return facts


def extract_express_fastify_facts(text: str, analysis: FileAnalysis | None = None) -> list[Fact]:
    facts: list[Fact] = []
    seen: set[tuple[str, str, str, int]] = set()
    modules = imported_modules(analysis)
    has_express = any(target in {"express", "koa-router"} or target.endswith("/router") for target in modules) or "express" in text
    has_fastify = any("fastify" in target for target in modules) or "fastify" in text
    if has_express:
        for match in EXPRESS_ROUTE_RE.finditer(text):
            args = split_top_level(match.group("args"))
            if not args:
                continue
            method = match.group("method").upper()
            path = strip_wrapping_quotes(args[0]) if args[0].strip().startswith(("'", '"', "`")) else ""
            if method != "USE" and not path.startswith("/"):
                continue
            handler = identifierish(args[-1]) if len(args) > 1 else match.group("object")
            middleware = [identifierish(arg) for arg in args[1:-1] if identifierish(arg)]
            route_key = f"{method} {path or '(middleware)'}"
            append_unique_fact(facts, seen, Fact("route-handler", route_key, handler, find_line_no(text, match.start())))
            if middleware:
                append_unique_fact(
                    facts,
                    seen,
                    Fact("route-middleware", route_key, " -> ".join(middleware[:4]), find_line_no(text, match.start())),
                )
    if has_fastify:
        for match in FASTIFY_ROUTE_RE.finditer(text):
            args = split_top_level(match.group("args"))
            if not args or not args[0].strip().startswith(("'", '"', "`")):
                continue
            method = match.group("method").upper()
            path = strip_wrapping_quotes(args[0])
            handler = identifierish(args[-1]) if len(args) > 1 else match.group("object")
            route_key = f"{method} {path}"
            append_unique_fact(facts, seen, Fact("route-handler", route_key, handler, find_line_no(text, match.start())))
        for match in FASTIFY_ROUTE_OBJECT_RE.finditer(text):
            body = match.group("body")
            method_match = re.search(r"\bmethod\s*:\s*(?P<value>\[[^\]]+\]|['\"`][^'\"`]+['\"`])", body)
            url_match = re.search(r"\b(?:url|path)\s*:\s*(?P<quote>['\"`])(?P<value>[^'\"`]+)(?P=quote)", body)
            if not method_match or not url_match:
                continue
            raw_methods = method_match.group("value")
            methods = [strip_wrapping_quotes(item) for item in split_top_level(raw_methods.strip("[]"))] if raw_methods.startswith("[") else [strip_wrapping_quotes(raw_methods)]
            handler_match = re.search(r"\bhandler\s*:\s*(?P<handler>[A-Za-z_][A-Za-z0-9_.]*)", body)
            middleware_match = re.search(r"\b(?:preHandler|preValidation)\s*:\s*(?P<value>\[[^\]]+\]|[A-Za-z_][A-Za-z0-9_.]*)", body)
            middleware: list[str] = []
            if middleware_match:
                raw_value = middleware_match.group("value")
                middleware = [identifierish(item) for item in split_top_level(raw_value.strip("[]")) if identifierish(item)]
            for method in methods:
                route_key = f"{method.upper()} {url_match.group('value')}"
                append_unique_fact(
                    facts,
                    seen,
                    Fact("route-handler", route_key, identifierish(handler_match.group("handler")) if handler_match else match.group("object"), find_line_no(text, match.start())),
                )
                if middleware:
                    append_unique_fact(
                        facts,
                        seen,
                        Fact("route-middleware", route_key, " -> ".join(middleware[:4]), find_line_no(text, match.start())),
                    )
        for match in FASTIFY_REGISTER_RE.finditer(text):
            prefix_match = re.search(r"\bprefix\s*:\s*(?P<quote>['\"`])(?P<value>[^'\"`]+)(?P=quote)", match.group("body"))
            if prefix_match:
                append_unique_fact(
                    facts,
                    seen,
                    Fact("route-prefix", match.group("plugin"), prefix_match.group("value"), find_line_no(text, match.start())),
                )
    return facts


def extract_react_frontend_facts(path: Path, text: str, analysis: FileAnalysis | None = None) -> list[Fact]:
    facts: list[Fact] = []
    seen: set[tuple[str, str, str, int]] = set()
    modules = imported_modules(analysis)
    symbols = tuple(analysis.symbols) if analysis else ()
    is_frontend = path.suffix.lower() in {".tsx", ".jsx"} or any(
        target in {"react", "react-router-dom", "@tanstack/react-query", "zod", "zustand"} for target in modules
    )
    if not is_frontend:
        return []
    is_jsx_like = path.suffix.lower() in {".tsx", ".jsx"} or "<" in text
    lower_parts = {part.lower() for part in path.parts}
    for symbol in symbols:
        if symbol.name.startswith("use") and len(symbol.name) > 3 and symbol.name[3].isupper():
            append_unique_fact(facts, seen, Fact("hook", symbol.name, "react-hook", symbol.start_line))
            continue
        if symbol.name.endswith("Provider"):
            append_unique_fact(facts, seen, Fact("frontend-provider", symbol.name, "react-provider", symbol.start_line))
        if is_jsx_like and re.match(r"[A-Z][A-Za-z0-9_]*$", symbol.name):
            if path.name.lower().startswith("layout") or "layouts" in lower_parts or symbol.name.endswith("Layout"):
                append_unique_fact(facts, seen, Fact("layout", symbol.name, path.name, symbol.start_line))
            elif path.name.lower().startswith("page") or "pages" in lower_parts or symbol.name.endswith("Page"):
                append_unique_fact(facts, seen, Fact("page", symbol.name, path.name, symbol.start_line))
            elif "providers" in lower_parts and symbol.name.endswith("Provider"):
                append_unique_fact(facts, seen, Fact("frontend-provider", symbol.name, path.name, symbol.start_line))
            else:
                append_unique_fact(facts, seen, Fact("component", symbol.name, path.name, symbol.start_line))
    for match in REACT_ROUTE_RE.finditer(text):
        append_unique_fact(facts, seen, Fact("frontend-route", match.group("path"), path.name, find_line_no(text, match.start())))
    for match in QUERY_KEY_RE.finditer(text):
        items = [strip_wrapping_quotes(item) for item in split_top_level(match.group("body"))]
        items = [item for item in items if item]
        if items:
            append_unique_fact(
                facts,
                seen,
                Fact("query-key", "/".join(items[:4]), path.name, find_line_no(text, match.start())),
            )
    for match in API_CALL_RE.finditer(text):
        client = match.group("client")
        method = "GET" if client == "fetch" else client.split(".")[-1].upper()
        append_unique_fact(
            facts,
            seen,
            Fact("api-call", f"{method} {match.group('path')}", client, find_line_no(text, match.start())),
        )
    for match in ZOD_SCHEMA_RE.finditer(text):
        append_unique_fact(facts, seen, Fact("schema", match.group("name"), "zod", find_line_no(text, match.start())))
    for match in ZUSTAND_STORE_RE.finditer(text):
        append_unique_fact(facts, seen, Fact("state-store", match.group("name"), "zustand", find_line_no(text, match.start())))
    if "useForm(" in text or "FormProvider" in text:
        append_unique_fact(facts, seen, Fact("form", path.stem, "react-hook-form", 1))
    return facts


def extract_tsconfig_facts(text: str) -> list[Fact]:
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return []
    if not isinstance(parsed, dict):
        return []
    facts: list[Fact] = []
    seen: set[tuple[str, str, str, int]] = set()
    extends_value = parsed.get("extends")
    if isinstance(extends_value, str):
        append_unique_fact(facts, seen, Fact("tsconfig-extends", "extends", extends_value, 1))
    for key in ("include", "exclude", "files"):
        values = parsed.get(key)
        if isinstance(values, list):
            for value in values:
                if isinstance(value, str):
                    append_unique_fact(facts, seen, Fact(f"tsconfig-{key[:-1] if key.endswith('s') else key}", key, value, 1))
    compiler_options = parsed.get("compilerOptions")
    if isinstance(compiler_options, dict):
        for key in ("target", "module", "moduleResolution", "jsx", "baseUrl", "rootDir", "outDir"):
            value = compiler_options.get(key)
            if isinstance(value, str):
                append_unique_fact(facts, seen, Fact("tsconfig-option", key, value, 1))
        for key in ("strict", "noEmit", "composite", "incremental", "allowJs"):
            value = compiler_options.get(key)
            if isinstance(value, bool):
                append_unique_fact(facts, seen, Fact("tsconfig-option", key, str(value).lower(), 1))
        for key in ("types", "lib"):
            value = compiler_options.get(key)
            if isinstance(value, list):
                for item in value:
                    if isinstance(item, str):
                        append_unique_fact(facts, seen, Fact("tsconfig-option", key, item, 1))
        paths = compiler_options.get("paths")
        if isinstance(paths, dict):
            for alias, targets in paths.items():
                if isinstance(targets, list):
                    for target in targets:
                        if isinstance(target, str):
                            append_unique_fact(facts, seen, Fact("tsconfig-alias", alias, target, 1))
    references = parsed.get("references")
    if isinstance(references, list):
        for reference in references:
            if isinstance(reference, dict) and isinstance(reference.get("path"), str):
                append_unique_fact(facts, seen, Fact("tsconfig-reference", "reference", reference["path"], 1))
    return facts


def extract_tooling_config_facts(path: Path, text: str, analysis: FileAnalysis | None = None) -> list[Fact]:
    facts: list[Fact] = []
    seen: set[tuple[str, str, str, int]] = set()
    lower_name = path.name.lower()
    tool = ""
    if lower_name.startswith("vite.config"):
        tool = "vite"
    elif lower_name.startswith("vitest.config"):
        tool = "vitest"
    elif lower_name.startswith("jest.config") or lower_name == "jest.config.ts":
        tool = "jest"
    elif lower_name.startswith("playwright.config"):
        tool = "playwright"
    elif lower_name.startswith("eslint.config") or lower_name.startswith(".eslintrc"):
        tool = "eslint"
    elif lower_name.startswith(".prettierrc") or lower_name.startswith("prettier.config"):
        tool = "prettier"
    elif lower_name.startswith("commitlint.config"):
        tool = "commitlint"
    if not tool:
        return []
    for dependency in analysis.dependencies if analysis else ():
        append_unique_fact(
            facts,
            seen,
            Fact("tool-config", tool, dependency.raw_target, dependency.line, source="code-intel"),
        )
    if tool in {"vite", "vitest"}:
        for match in JS_ALIAS_OBJECT_RE.finditer(text):
            for entry in split_top_level(match.group("body")):
                alias_match = re.match(r"(?P<key>['\"`][^'\"`]+['\"`]|[A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?P<value>.+)", entry, re.DOTALL)
                if not alias_match:
                    continue
                raw_value = alias_match.group("value").strip().rstrip(",")
                append_unique_fact(
                    facts,
                    seen,
                    Fact(
                        "tool-alias",
                        f"{tool}.{strip_wrapping_quotes(alias_match.group('key'))}",
                        strip_wrapping_quotes(raw_value) if raw_value.startswith(("'", '"', "`")) else identifierish(raw_value),
                        find_line_no(text, match.start()),
                    ),
                )
        for pattern, key in (
            (re.compile(r"\bport\s*:\s*(\d+)"), "port"),
            (re.compile(r"\benvironment\s*:\s*['\"`]([^'\"`]+)['\"`]"), "environment"),
            (re.compile(r"\bbaseURL\s*:\s*['\"`]([^'\"`]+)['\"`]"), "baseURL"),
            (re.compile(r"\btestDir\s*:\s*['\"`]([^'\"`]+)['\"`]"), "testDir"),
        ):
            for match in pattern.finditer(text):
                append_unique_fact(facts, seen, Fact("tool-config", f"{tool}.{key}", match.group(1), find_line_no(text, match.start())))
    if tool == "jest":
        mapper_match = re.search(r"\bmoduleNameMapper\s*:\s*\{(?P<body>.*?)\}", text, re.DOTALL)
        if mapper_match:
            for entry in split_top_level(mapper_match.group("body")):
                alias_match = re.match(r"(?P<key>['\"`][^'\"`]+['\"`])\s*:\s*(?P<value>['\"`][^'\"`]+['\"`])", entry)
                if alias_match:
                    append_unique_fact(
                        facts,
                        seen,
                        Fact("tool-alias", f"jest.{strip_wrapping_quotes(alias_match.group('key'))}", strip_wrapping_quotes(alias_match.group("value")), find_line_no(text, mapper_match.start())),
                    )
    if tool == "playwright":
        for match in re.finditer(r"\b(?:baseURL|testDir)\s*:\s*['\"`]([^'\"`]+)['\"`]", text):
            key_match = re.search(r"(baseURL|testDir)", match.group(0))
            if key_match:
                append_unique_fact(
                    facts,
                    seen,
                    Fact("tool-config", f"playwright.{key_match.group(1)}", match.group(1), find_line_no(text, match.start())),
                )
    if tool in {"eslint", "prettier", "commitlint"}:
        for match in re.finditer(r"\bextends\s*:\s*(\[[^\]]+\]|['\"`][^'\"`]+['\"`])", text, re.DOTALL):
            raw = match.group(1)
            values = split_top_level(raw.strip("[]")) if raw.startswith("[") else [raw]
            for value in values:
                normalized = strip_wrapping_quotes(value)
                if normalized:
                    append_unique_fact(facts, seen, Fact("tool-config", f"{tool}.extends", normalized, find_line_no(text, match.start())))
    if tool == "prettier":
        for matcher in (JS_KEY_VALUE_STRING_RE, JS_BOOLEAN_RE, JS_NUMBER_RE):
            for match in matcher.finditer(text):
                if match.group("key") in {"singleQuote", "semi", "printWidth", "tabWidth", "trailingComma"}:
                    append_unique_fact(
                        facts,
                        seen,
                        Fact("tool-config", f"prettier.{match.group('key')}", match.group("value"), find_line_no(text, match.start())),
                    )
    return facts


def extract_package_json_facts(text: str) -> list[Fact]:
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return []
    if not isinstance(parsed, dict):
        return []
    facts: list[Fact] = []
    for field in ("name", "version", "type", "packageManager"):
        value = parsed.get(field)
        if isinstance(value, str):
            facts.append(Fact("package-field", field, value, 1))
    scripts = parsed.get("scripts")
    if isinstance(scripts, dict):
        for key, value in scripts.items():
            if isinstance(value, str):
                facts.append(Fact("package-script", key, value, 1))
    for section, kind in (
        ("dependencies", "dependency"),
        ("devDependencies", "dev-dependency"),
        ("peerDependencies", "peer-dependency"),
        ("optionalDependencies", "optional-dependency"),
    ):
        values = parsed.get(section)
        if isinstance(values, dict):
            for key, value in values.items():
                if isinstance(value, str):
                    facts.append(Fact(kind, key, value, 1))
    workspaces = parsed.get("workspaces")
    if isinstance(workspaces, list):
        for item in workspaces:
            if isinstance(item, str):
                facts.append(Fact("workspace", item, "declared", 1))
    return facts


def extract_json_facts(path: Path, text: str) -> list[Fact]:
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return []
    if not isinstance(parsed, dict):
        return []
    facts: list[Fact] = []
    for key, value in parsed.items():
        if isinstance(value, (str, int, float, bool)):
            facts.append(Fact("config-key", key, str(value), 1))
        elif isinstance(value, dict):
            facts.append(Fact("config-section", key, "object", 1))
            for nested_key, nested_value in list(value.items())[:12]:
                if isinstance(nested_value, (str, int, float, bool)):
                    facts.append(Fact("config-key", f"{key}.{nested_key}", str(nested_value), 1))
        elif isinstance(value, list) and value and all(isinstance(item, str) for item in value[:5]):
            facts.append(Fact("config-key", key, ", ".join(value[:5]), 1))
    return facts


def extract_cargo_toml_facts(text: str) -> list[Fact]:
    if tomllib is None:
        return []
    try:
        parsed = tomllib.loads(text)
    except tomllib.TOMLDecodeError:
        return []
    if not isinstance(parsed, dict):
        return []
    facts: list[Fact] = []
    seen: set[tuple[str, str, str, int]] = set()
    package = parsed.get("package")
    if isinstance(package, dict):
        for key in ("name", "edition", "version"):
            value = package.get(key)
            if isinstance(value, str):
                append_unique_fact(facts, seen, Fact("cargo-package", key, value, 1))
    workspace = parsed.get("workspace")
    if isinstance(workspace, dict):
        members = workspace.get("members")
        if isinstance(members, list):
            for member in members:
                if isinstance(member, str):
                    append_unique_fact(facts, seen, Fact("cargo-workspace-member", "member", member, 1))
    for section, kind_name in (
        ("dependencies", "cargo-dependency"),
        ("dev-dependencies", "cargo-dev-dependency"),
        ("build-dependencies", "cargo-build-dependency"),
    ):
        values = parsed.get(section)
        if isinstance(values, dict):
            for dependency, spec in values.items():
                if isinstance(spec, str):
                    value = spec
                elif isinstance(spec, dict):
                    rendered_parts: list[str] = []
                    for sub_key, sub_value in sorted(spec.items()):
                        if isinstance(sub_value, (str, int, float, bool)):
                            rendered_parts.append(f"{sub_key}={sub_value}")
                        elif isinstance(sub_value, list):
                            rendered_parts.append(f"{sub_key}={sub_value}")
                    value = ", ".join(rendered_parts)
                else:
                    value = "declared"
                append_unique_fact(facts, seen, Fact(kind_name, dependency, value or "declared", 1))
    features = parsed.get("features")
    if isinstance(features, dict):
        for feature, members in features.items():
            if isinstance(members, list):
                values = [item for item in members if isinstance(item, str)]
                append_unique_fact(facts, seen, Fact("cargo-feature", str(feature), ", ".join(values) or "enabled", 1))
    return facts


def extract_go_mod_facts(text: str) -> list[Fact]:
    facts: list[Fact] = []
    seen: set[tuple[str, str, str, int]] = set()
    in_require_block = False
    in_replace_block = False
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        if stripped.startswith("module "):
            append_unique_fact(facts, seen, Fact("go-module", "module", stripped.split(None, 1)[1].strip(), line_no))
            continue
        if stripped.startswith("go "):
            append_unique_fact(facts, seen, Fact("go-version", "go", stripped.split(None, 1)[1].strip(), line_no))
            continue
        if stripped == "require (":
            in_require_block = True
            in_replace_block = False
            continue
        if stripped == "replace (":
            in_replace_block = True
            in_require_block = False
            continue
        if stripped == ")":
            in_require_block = False
            in_replace_block = False
            continue
        if stripped.startswith("require "):
            payload = stripped.removeprefix("require ").strip()
            parts = payload.split()
            if len(parts) >= 2:
                append_unique_fact(facts, seen, Fact("go-require", parts[0], parts[1], line_no))
            continue
        if in_require_block:
            parts = stripped.split()
            if len(parts) >= 2:
                append_unique_fact(facts, seen, Fact("go-require", parts[0], parts[1], line_no))
            continue
        if stripped.startswith("replace "):
            payload = stripped.removeprefix("replace ").strip()
        elif in_replace_block:
            payload = stripped
        else:
            payload = ""
        if payload and "=>" in payload:
            source, target = [part.strip() for part in payload.split("=>", 1)]
            append_unique_fact(facts, seen, Fact("go-replace", source, target, line_no))
    return facts


def extract_rust_facts(path: Path, text: str, analysis: FileAnalysis | None = None) -> list[Fact]:
    if path.name == "Cargo.toml":
        return extract_cargo_toml_facts(text)
    if analysis is None:
        return []
    facts: list[Fact] = []
    seen: set[tuple[str, str, str, int]] = set()
    for dependency in analysis.dependencies:
        append_unique_fact(facts, seen, Fact("rust-use", dependency.raw_target, dependency.kind, dependency.line, source="code-intel"))
    for symbol in analysis.symbols:
        if symbol.kind == "module":
            append_unique_fact(facts, seen, Fact("rust-module", symbol.qualified_name, symbol.visibility or "module", symbol.start_line, source="code-intel"))
        elif symbol.kind in {"struct", "enum", "trait"}:
            append_unique_fact(facts, seen, Fact(f"rust-{symbol.kind}", symbol.qualified_name, symbol.visibility or symbol.kind, symbol.start_line, source="code-intel"))
        elif symbol.kind == "impl":
            append_unique_fact(facts, seen, Fact("rust-impl", symbol.qualified_name, symbol.signature or "impl", symbol.start_line, source="code-intel"))
        elif symbol.kind == "method" or (symbol.kind == "function" and symbol.parent_symbol):
            append_unique_fact(facts, seen, Fact("rust-method", symbol.qualified_name, symbol.signature or "method", symbol.start_line, source="code-intel"))
        elif symbol.kind == "function":
            append_unique_fact(facts, seen, Fact("rust-function", symbol.qualified_name, symbol.visibility or "function", symbol.start_line, source="code-intel"))
    current_derives: list[str] = []
    current_impl = ""
    impl_depth = 0
    brace_depth = 0
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        derive_match = re.match(r"#\s*\[\s*derive\s*\((?P<body>[^)]*)\)\s*\]", stripped)
        if derive_match:
            current_derives = [identifierish(item) for item in split_top_level(derive_match.group("body")) if identifierish(item)]
            continue
        impl_match = re.match(
            r"impl(?:<[^>]+>)?\s+(?:[A-Za-z_][A-Za-z0-9_:<>]*\s+for\s+)?(?P<name>[A-Za-z_][A-Za-z0-9_:<>]*)[^{]*\{",
            stripped,
        )
        if impl_match:
            current_impl = impl_match.group("name").split("::")[-1]
            impl_depth = brace_depth + max(1, line.count("{"))
        if current_impl and (method_match := re.match(r"(?:pub(?:\([^)]+\))?\s+)?(?:async\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)", stripped)):
            append_unique_fact(facts, seen, Fact("rust-method", f"{current_impl}.{method_match.group(1)}", stripped[:160], line_no))
            brace_depth += line.count("{") - line.count("}")
            if brace_depth < impl_depth:
                current_impl = ""
                impl_depth = 0
            continue
        symbol_match = re.match(r"(?:pub(?:\([^)]+\))?\s+)?(?:struct|enum)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)", stripped)
        if symbol_match and current_derives:
            for derive in current_derives:
                append_unique_fact(facts, seen, Fact("rust-derive", symbol_match.group("name"), derive, line_no))
            current_derives = []
        else:
            current_derives = []
        brace_depth += line.count("{") - line.count("}")
        if current_impl and brace_depth < impl_depth:
            current_impl = ""
            impl_depth = 0
    return facts


def extract_go_facts(text: str, analysis: FileAnalysis | None = None) -> list[Fact]:
    if analysis is None:
        return []
    facts: list[Fact] = []
    seen: set[tuple[str, str, str, int]] = set()
    package_match = re.search(r"^\s*package\s+([A-Za-z_][A-Za-z0-9_]*)", text, re.MULTILINE)
    if package_match:
        append_unique_fact(facts, seen, Fact("go-package", "package", package_match.group(1), find_line_no(text, package_match.start())))
    for dependency in analysis.dependencies:
        append_unique_fact(facts, seen, Fact("go-import", dependency.raw_target, dependency.kind, dependency.line, source="code-intel"))
    for symbol in analysis.symbols:
        if symbol.kind == "interface" or (symbol.kind == "type" and "interface" in (symbol.signature or "")):
            append_unique_fact(facts, seen, Fact("go-interface", symbol.qualified_name, symbol.signature or "interface", symbol.start_line, source="code-intel"))
        elif symbol.kind == "method":
            append_unique_fact(facts, seen, Fact("go-method", symbol.qualified_name, symbol.signature or "method", symbol.start_line, source="code-intel"))
        elif symbol.kind == "function":
            append_unique_fact(facts, seen, Fact("go-function", symbol.qualified_name, symbol.signature or "function", symbol.start_line, source="code-intel"))
        elif symbol.kind == "type":
            append_unique_fact(facts, seen, Fact("go-type", symbol.qualified_name, symbol.signature or "type", symbol.start_line, source="code-intel"))
    return facts


def extract_c_kernel_facts(text: str, analysis: FileAnalysis | None = None) -> list[Fact]:
    facts: list[Fact] = []
    seen: set[tuple[str, str, str, int]] = set()
    if analysis is not None:
        for dependency in analysis.dependencies:
            append_unique_fact(facts, seen, Fact("c-include", dependency.raw_target, dependency.kind, dependency.line, source="code-intel"))
        for symbol in analysis.symbols:
            if symbol.kind in {"struct", "enum", "union"}:
                append_unique_fact(facts, seen, Fact(f"c-{symbol.kind}", symbol.qualified_name, symbol.signature or symbol.kind, symbol.start_line, source="code-intel"))
            elif symbol.kind == "function":
                append_unique_fact(facts, seen, Fact("c-function", symbol.qualified_name, symbol.signature or "function", symbol.start_line, source="code-intel"))
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        if match := re.match(r"#define\s+([A-Za-z_][A-Za-z0-9_]*)\s+(.+)", stripped):
            append_unique_fact(facts, seen, Fact("c-macro", match.group(1), match.group(2).strip()[:160], line_no))
        if match := re.search(r"MODULE_(LICENSE|AUTHOR|DESCRIPTION|VERSION|ALIAS)\s*\(\s*\"([^\"]+)\"\s*\)", stripped):
            append_unique_fact(facts, seen, Fact("kernel-module-meta", match.group(1).lower(), match.group(2), line_no))
        if match := re.search(r"module_param(?:_named)?\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*,\s*)?([A-Za-z_][A-Za-z0-9_]*)\s*,\s*([0-7]{3,4})\s*\)", stripped):
            append_unique_fact(facts, seen, Fact("kernel-param", match.group(1), f"{match.group(2)} mode={match.group(3)}", line_no))
        if match := re.search(r"\bmodule_init\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)", stripped):
            append_unique_fact(facts, seen, Fact("kernel-hook", "init", match.group(1), line_no))
        if match := re.search(r"\bmodule_exit\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)", stripped):
            append_unique_fact(facts, seen, Fact("kernel-hook", "exit", match.group(1), line_no))
        if match := re.search(r"\bEXPORT_SYMBOL(?:_GPL)?\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)", stripped):
            append_unique_fact(facts, seen, Fact("kernel-export", match.group(1), "exported", line_no))
        if match := re.search(r"struct\s+(file_operations|platform_driver|pci_driver|spi_driver|i2c_driver)\s+([A-Za-z_][A-Za-z0-9_]*)", stripped):
            append_unique_fact(facts, seen, Fact("kernel-driver-struct", match.group(2), match.group(1), line_no))
        if match := re.search(r"\b(?:DEVICE_ATTR(?:_RO|_RW|_WO)?|__ATTR)\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)", stripped):
            append_unique_fact(facts, seen, Fact("sysfs-attribute", match.group(1), "declared", line_no))
    return facts


def extract_datastore_facts(path: Path, text: str, analysis: FileAnalysis | None = None) -> list[Fact]:
    facts: list[Fact] = []
    seen: set[tuple[str, str, str, int]] = set()
    modules = imported_modules(analysis)
    lower_name = path.name.lower()
    is_mongo = any(target in {"mongodb", "mongoose"} or target.startswith("mongodb/") or target.startswith("mongoose") for target in modules) or "db.collection(" in text
    is_redis = any(target in {"redis", "ioredis"} or target.startswith("redis/") or target.startswith("ioredis") for target in modules) or lower_name == "redis.conf"
    if is_mongo:
        for match in re.finditer(r"\b(?:db|database)\.collection\s*\(\s*(?P<quote>['\"`])(?P<name>[^'\"`]+)(?P=quote)\s*\)", text):
            append_unique_fact(facts, seen, Fact("mongo-collection", match.group("name"), "accessed", find_line_no(text, match.start())))
        for match in re.finditer(r"\bcollection\s*\(\s*(?P<quote>['\"`])(?P<name>[^'\"`]+)(?P=quote)\s*\)\.(?P<op>find|findOne|aggregate|insertOne|insertMany|updateOne|updateMany|deleteOne|deleteMany|watch)\b", text):
            append_unique_fact(facts, seen, Fact("mongo-operation", match.group("name"), match.group("op"), find_line_no(text, match.start())))
        for match in re.finditer(r"\bmongoose\.model\s*\(\s*(?P<quote>['\"`])(?P<name>[^'\"`]+)(?P=quote)", text):
            append_unique_fact(facts, seen, Fact("mongo-model", match.group("name"), "mongoose", find_line_no(text, match.start())))
        for match in re.finditer(r"(?:const|let|var)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*new\s+(?:mongoose\.)?Schema\b", text):
            append_unique_fact(facts, seen, Fact("mongo-schema", match.group("name"), "mongoose", find_line_no(text, match.start())))
        for match in re.finditer(r"\.index\s*\(\s*\{(?P<body>[^}]*)\}", text):
            index_body = re.sub(r"\s+", " ", match.group("body")).strip()
            if index_body:
                append_unique_fact(facts, seen, Fact("mongo-index", index_body[:120], "declared", find_line_no(text, match.start())))
    if lower_name == "redis.conf":
        secret_keys = {"requirepass", "masterauth"}
        for line_no, line in enumerate(text.splitlines(), start=1):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            parts = stripped.split(None, 1)
            if len(parts) == 2:
                value = "configured" if parts[0] in secret_keys else parts[1].strip()
                append_unique_fact(facts, seen, Fact("redis-config", parts[0], value, line_no))
    if is_redis and lower_name != "redis.conf":
        for match in re.finditer(r"\.(?P<op>get|set|setex|del|expire|hget|hset|zadd|sadd|publish)\s*\(\s*(?P<quote>['\"`])(?P<key>[^'\"`]+)(?P=quote)", text):
            append_unique_fact(facts, seen, Fact("redis-key", match.group("key"), match.group("op"), find_line_no(text, match.start())))
    return facts


def extract_grafana_prometheus_facts(path: Path, text: str) -> list[Fact]:
    facts: list[Fact] = []
    seen: set[tuple[str, str, str, int]] = set()
    lower_path = path.as_posix().lower()
    try:
        parsed_json = json.loads(text)
    except json.JSONDecodeError:
        parsed_json = None
    if isinstance(parsed_json, dict):
        dashboard = parsed_json.get("dashboard") if isinstance(parsed_json.get("dashboard"), dict) else parsed_json
        if isinstance(dashboard, dict) and ("panels" in dashboard or "templating" in dashboard or "uid" in dashboard):
            title = str(dashboard.get("title") or path.stem)
            append_unique_fact(facts, seen, Fact("grafana-dashboard", title, str(dashboard.get("uid") or "dashboard"), 1))
            panels = list(dashboard.get("panels") or [])
            while panels:
                panel = panels.pop(0)
                if not isinstance(panel, dict):
                    continue
                panel_title = str(panel.get("title") or "").strip()
                panel_type = str(panel.get("type") or "panel")
                if panel_title:
                    append_unique_fact(facts, seen, Fact("grafana-panel", panel_title, panel_type, 1))
                nested = panel.get("panels")
                if isinstance(nested, list):
                    panels.extend(nested)
            templating = dashboard.get("templating")
            variables = templating.get("list") if isinstance(templating, dict) else []
            if isinstance(variables, list):
                for variable in variables:
                    if isinstance(variable, dict) and variable.get("name"):
                        append_unique_fact(facts, seen, Fact("grafana-variable", str(variable["name"]), str(variable.get("type") or "variable"), 1))
            annotations = dashboard.get("annotations")
            annotation_list = annotations.get("list") if isinstance(annotations, dict) else []
            if isinstance(annotation_list, list):
                for annotation in annotation_list:
                    if isinstance(annotation, dict) and annotation.get("name"):
                        append_unique_fact(facts, seen, Fact("grafana-annotation", str(annotation["name"]), str(annotation.get("datasource") or "annotation"), 1))
    current_job = ""
    current_group = ""
    in_scrape_configs = False
    in_rule_groups = False
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        if stripped.startswith("scrape_configs:"):
            in_scrape_configs = True
            in_rule_groups = False
            current_job = ""
            continue
        if stripped.startswith("groups:"):
            in_rule_groups = True
            in_scrape_configs = False
            current_job = ""
            current_group = ""
            continue
        if in_scrape_configs and (match := re.match(r"-?\s*job_name:\s*['\"]?([^'\"]+)['\"]?", stripped)):
            current_job = match.group(1)
            append_unique_fact(facts, seen, Fact("prometheus-job", current_job, "scrape", line_no))
            continue
        if match := re.match(r"-?\s*name:\s*['\"]?([^'\"]+)['\"]?", stripped):
            if "datasources" in lower_path or "grafana" in lower_path:
                append_unique_fact(facts, seen, Fact("grafana-datasource", match.group(1), "declared", line_no))
                continue
            if in_rule_groups or "prometheus" in lower_path:
                current_group = match.group(1)
                continue
        if match := re.match(r"-?\s*alert:\s*['\"]?([^'\"]+)['\"]?", stripped):
            append_unique_fact(facts, seen, Fact("prometheus-alert", match.group(1), current_group or path.stem, line_no))
            continue
        if match := re.match(r"-?\s*record:\s*['\"]?([^'\"]+)['\"]?", stripped):
            append_unique_fact(facts, seen, Fact("prometheus-record", match.group(1), current_group or path.stem, line_no))
            continue
        if current_job and "targets:" in stripped:
            for target in re.findall(r"['\"]([^'\"]+)['\"]", stripped):
                append_unique_fact(facts, seen, Fact("prometheus-target", current_job, target, line_no))
            continue
        if in_scrape_configs and current_job and stripped.startswith("- "):
            target = normalize_fact_value(stripped[2:])
            if ":" in target:
                append_unique_fact(facts, seen, Fact("prometheus-target", current_job, target, line_no))
                continue
        if stripped.startswith("type:") and "grafana" in lower_path:
            append_unique_fact(facts, seen, Fact("grafana-datasource-type", current_group or path.stem, normalize_fact_value(stripped.split(":", 1)[1]), line_no))
            continue
        if stripped.startswith("expr:"):
            target = current_group or path.stem
            append_unique_fact(facts, seen, Fact("prometheus-expression", target, normalize_fact_value(stripped.split(":", 1)[1])[:200], line_no))
            continue
        if stripped.startswith("rule_files:"):
            for rule_file in re.findall(r"['\"]([^'\"]+)['\"]", stripped):
                append_unique_fact(facts, seen, Fact("prometheus-rule-file", "rule_files", rule_file, line_no))
    return facts


def extract_docker_facts(path: Path, text: str) -> list[Fact]:
    facts: list[Fact] = []
    seen: set[tuple[str, str, str, int]] = set()
    lower_name = path.name.lower()
    if lower_name in {"docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"}:
        facts.extend(extract_compose_yaml_facts(text))
        current_service = ""
        current_list_key = ""
        in_services = False
        in_top_level_volumes = False
        in_top_level_networks = False
        for line_no, line in enumerate(text.splitlines(), start=1):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            indent = len(line) - len(line.lstrip(" "))
            if indent == 0:
                in_services = stripped.startswith("services:")
                in_top_level_volumes = stripped.startswith("volumes:")
                in_top_level_networks = stripped.startswith("networks:")
                current_service = ""
                current_list_key = ""
                continue
            if in_services and indent == 2 and stripped.endswith(":"):
                current_service = stripped[:-1].strip().strip("'\"")
                current_list_key = ""
                continue
            if in_top_level_volumes and indent == 2 and stripped.endswith(":"):
                append_unique_fact(facts, seen, Fact("compose-volume", stripped[:-1].strip(), "declared", line_no))
                continue
            if in_top_level_networks and indent == 2 and stripped.endswith(":"):
                append_unique_fact(facts, seen, Fact("compose-network", stripped[:-1].strip(), "declared", line_no))
                continue
            if current_service and indent >= 4 and ":" in stripped and not stripped.startswith("- "):
                key, value = stripped.split(":", 1)
                key = key.strip()
                value = normalize_fact_value(value)
                if current_list_key == "healthcheck" and key == "test" and value:
                    append_unique_fact(facts, seen, Fact("compose-healthcheck", current_service, value, line_no))
                    continue
                if key in {"volumes", "networks", "healthcheck"}:
                    current_list_key = key
                    if value:
                        append_unique_fact(facts, seen, Fact(f"compose-{key[:-1] if key.endswith('s') else key}", current_service, value, line_no))
                    continue
                current_list_key = ""
            if current_service and indent >= 6 and stripped.startswith("- ") and current_list_key in {"volumes", "networks"}:
                append_unique_fact(facts, seen, Fact(f"compose-{current_list_key[:-1]}", current_service, normalize_fact_value(stripped[2:]), line_no))
                continue
            if current_service and indent >= 6 and current_list_key == "healthcheck" and stripped.startswith("test:"):
                append_unique_fact(facts, seen, Fact("compose-healthcheck", current_service, normalize_fact_value(stripped.split(":", 1)[1]), line_no))
        return list({(fact.kind, fact.key, fact.value, fact.line): fact for fact in facts}.values())
    if path.name.lower() != "dockerfile" and not path.name.lower().endswith(".dockerfile"):
        return []
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        instruction, _, payload = stripped.partition(" ")
        instruction = instruction.upper()
        payload = payload.strip()
        if instruction == "FROM":
            match = re.match(r"([^\s]+)(?:\s+AS\s+([^\s]+))?", payload, re.IGNORECASE)
            if match:
                stage = match.group(2) or match.group(1)
                append_unique_fact(facts, seen, Fact("docker-base-image", stage, match.group(1), line_no))
        elif instruction == "WORKDIR" and payload:
            append_unique_fact(facts, seen, Fact("docker-workdir", "WORKDIR", payload, line_no))
        elif instruction == "EXPOSE" and payload:
            for port in payload.split():
                append_unique_fact(facts, seen, Fact("docker-expose", "EXPOSE", port, line_no))
        elif instruction == "ENV" and payload:
            for part in split_top_level(payload, delimiter=" "):
                if "=" in part:
                    key, value = part.split("=", 1)
                    append_unique_fact(facts, seen, Fact("docker-env", key, value, line_no))
        elif instruction in {"COPY", "ADD"} and payload:
            tokens = payload.split()
            if len(tokens) >= 2:
                append_unique_fact(facts, seen, Fact("docker-copy", tokens[-1], " ".join(tokens[:-1]), line_no))
        elif instruction == "RUN" and payload:
            tool = re.split(r"[ &|;]+", payload, maxsplit=1)[0]
            append_unique_fact(facts, seen, Fact("docker-run-tool", Path(tool).name, "RUN", line_no))
        elif instruction in {"CMD", "ENTRYPOINT"} and payload:
            append_unique_fact(facts, seen, Fact("docker-entrypoint", instruction, payload[:160], line_no))
        elif instruction == "USER" and payload:
            append_unique_fact(facts, seen, Fact("docker-user", "USER", payload, line_no))
        elif instruction == "VOLUME" and payload:
            append_unique_fact(facts, seen, Fact("docker-volume", "VOLUME", payload, line_no))
    return facts


def extract_systemd_facts(path: Path, text: str) -> list[Fact]:
    if path.suffix.lower() not in SYSTEMD_UNIT_SUFFIXES and "systemd" not in path.as_posix().lower():
        return []
    facts: list[Fact] = []
    seen: set[tuple[str, str, str, int]] = set()
    unit_name = path.name
    append_unique_fact(facts, seen, Fact("systemd-unit", unit_name, path.suffix.lstrip(".") or "unit", 1))
    current_section = ""
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith(("#", ";")):
            continue
        if stripped.startswith("[") and stripped.endswith("]"):
            current_section = stripped.strip("[]")
            append_unique_fact(facts, seen, Fact("systemd-section", unit_name, current_section, line_no))
            continue
        if "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key in {"Description"}:
            append_unique_fact(facts, seen, Fact("systemd-description", unit_name, value, line_no))
        elif key in {"After", "Wants", "Requires", "PartOf", "WantedBy", "RequiredBy", "Also"}:
            for item in value.split():
                append_unique_fact(facts, seen, Fact("systemd-dependency", f"{unit_name}.{key}", item, line_no))
        elif key.startswith("Exec"):
            append_unique_fact(facts, seen, Fact("systemd-exec", f"{unit_name}.{key}", value, line_no))
        elif key in {"OnCalendar", "OnBootSec", "OnUnitActiveSec"}:
            append_unique_fact(facts, seen, Fact("systemd-timer", f"{unit_name}.{key}", value, line_no))
        elif key in {"Environment", "EnvironmentFile"}:
            append_unique_fact(facts, seen, Fact("systemd-environment", f"{unit_name}.{key}", value, line_no))
        elif key in {"Type", "User", "WorkingDirectory", "Restart"}:
            append_unique_fact(facts, seen, Fact("systemd-option", f"{unit_name}.{key}", value, line_no))
        elif current_section:
            append_unique_fact(facts, seen, Fact("systemd-config", f"{unit_name}.{current_section}.{key}", value, line_no))
    return facts


def extract_zsh_dotfile_facts(path: Path, text: str) -> list[Fact]:
    lower_name = path.name.lower()
    if lower_name not in ZSH_DOTFILE_NAMES and path.suffix.lower() != ".zsh":
        return []
    facts = extract_shell_facts(text)
    seen = {(fact.kind, fact.key, fact.value, fact.line) for fact in facts}
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if match := re.match(r"(?:source|\.)\s+(.+)", stripped):
            append_unique_fact(facts, seen, Fact("dotfile-source", lower_name or path.name, normalize_fact_value(match.group(1)), line_no))
            continue
        if match := re.match(r"plugins=\((?P<body>[^)]*)\)", stripped):
            for plugin in split_top_level(match.group("body"), delimiter=" "):
                plugin_name = normalize_fact_value(plugin)
                if plugin_name:
                    append_unique_fact(facts, seen, Fact("zsh-plugin", plugin_name, "enabled", line_no))
            continue
        if match := re.match(r"(?:setopt|unsetopt)\s+(.+)", stripped):
            state = "unset" if stripped.startswith("unsetopt") else "set"
            for option in match.group(1).split():
                append_unique_fact(facts, seen, Fact("zsh-option", option, state, line_no))
            continue
        if match := re.match(r"bindkey(?:\s+-M\s+\S+)?\s+(['\"][^'\"]+['\"]|\S+)\s+(\S+)", stripped):
            append_unique_fact(facts, seen, Fact("zsh-bindkey", normalize_fact_value(match.group(1)), match.group(2), line_no))
            continue
        if match := re.match(r"zstyle\s+(['\"][^'\"]+['\"]|\S+)\s+(\S+)\s+(.+)", stripped):
            append_unique_fact(facts, seen, Fact("zsh-style", normalize_fact_value(match.group(1)), f"{match.group(2)}={normalize_fact_value(match.group(3))}", line_no))
            continue
        if match := re.match(r"autoload\s+-[A-Za-z]+\s+(.+)", stripped):
            for function_name in match.group(1).split():
                append_unique_fact(facts, seen, Fact("zsh-autoload", function_name, "autoload", line_no))
    return facts


def extract_sql_facts(path: Path, text: str) -> list[Fact]:
    facts: list[Fact] = []
    seen: set[tuple[str, str, str, int]] = set()
    pattern = re.compile(
        r"^\s*create\s+(?:or\s+replace\s+)?(?P<kind>table|view|function|procedure|trigger|index)\s+(?P<name>[A-Za-z_][A-Za-z0-9_.]*)",
        re.IGNORECASE,
    )
    lower_text = text.lower()
    is_mssql = any(token in lower_text for token in ("create proc", "create procedure", "nvarchar", "\ngo\n", "[dbo]"))
    for match in pattern.finditer(text):
        line_no = find_line_no(text, match.start())
        append_unique_fact(facts, seen, Fact("sql-object", match.group("name"), match.group("kind").lower(), line_no))
    for match in re.finditer(r"create\s+(?:unique\s+)?index\s+([A-Za-z_][A-Za-z0-9_.\[\]]*)\s+on\s+([A-Za-z_][A-Za-z0-9_.\[\]]*)", text, re.IGNORECASE):
        append_unique_fact(facts, seen, Fact("sql-index", match.group(1), match.group(2), find_line_no(text, match.start())))
    for match in re.finditer(r"create\s+schema\s+(?:if\s+not\s+exists\s+)?([A-Za-z_][A-Za-z0-9_.\[\]]*)", text, re.IGNORECASE):
        append_unique_fact(facts, seen, Fact("sql-schema", match.group(1), "schema", find_line_no(text, match.start())))
    for match in re.finditer(r"create\s+extension\s+(?:if\s+not\s+exists\s+)?([A-Za-z_][A-Za-z0-9_.-]*)", text, re.IGNORECASE):
        append_unique_fact(facts, seen, Fact("postgres-extension", match.group(1), "enabled", find_line_no(text, match.start())))
    for match in re.finditer(r"create\s+type\s+([A-Za-z_][A-Za-z0-9_.]*)\s+as\s+enum\s*\((?P<body>.*?)\)", text, re.IGNORECASE | re.DOTALL):
        line_no = find_line_no(text, match.start())
        append_unique_fact(facts, seen, Fact("postgres-enum", match.group(1), "enum", line_no))
        for item in split_top_level(match.group("body")):
            label = strip_wrapping_quotes(item)
            if label:
                append_unique_fact(facts, seen, Fact("postgres-enum-label", match.group(1), label, line_no))
    table_pattern = re.compile(
        r"create\s+table\s+(?:if\s+not\s+exists\s+)?(?P<name>[A-Za-z_][A-Za-z0-9_.\[\]]*)\s*\((?P<body>.*?)\)\s*;",
        re.IGNORECASE | re.DOTALL,
    )
    for match in table_pattern.finditer(text):
        table_name = match.group("name")
        line_no = find_line_no(text, match.start())
        append_unique_fact(facts, seen, Fact("sql-object", table_name, "table", line_no))
        for item in split_top_level(match.group("body")):
            stripped = item.strip()
            if not stripped:
                continue
            if re.match(r"(?i)(constraint|primary\s+key|unique|foreign\s+key|check)\b", stripped):
                constraint_name = "constraint"
                if name_match := re.match(r"(?i)constraint\s+([A-Za-z_][A-Za-z0-9_.\[\]]*)", stripped):
                    constraint_name = name_match.group(1)
                append_unique_fact(facts, seen, Fact("sql-constraint", table_name, constraint_name, line_no))
                continue
            column_match = re.match(r"([A-Za-z_\[][A-Za-z0-9_\].]*)\s+([A-Za-z0-9_()[\], ]+)", stripped)
            if not column_match:
                continue
            column_name = column_match.group(1).strip("[]")
            column_type = column_match.group(2).split()[0]
            append_unique_fact(facts, seen, Fact("sql-column", f"{table_name}.{column_name}", column_type, line_no))
            if reference_match := re.search(r"references\s+([A-Za-z_][A-Za-z0-9_.\[\]]*)", stripped, re.IGNORECASE):
                append_unique_fact(facts, seen, Fact("sql-reference", f"{table_name}.{column_name}", reference_match.group(1), line_no))
    if is_mssql:
        for match in re.finditer(r"create\s+(?:or\s+alter\s+)?(?:proc|procedure)\s+([\[\]A-Za-z_][A-Za-z0-9_.\[\]]*)", text, re.IGNORECASE):
            append_unique_fact(facts, seen, Fact("mssql-procedure", match.group(1), "procedure", find_line_no(text, match.start())))
        for match in re.finditer(r"create\s+(?:or\s+alter\s+)?function\s+([\[\]A-Za-z_][A-Za-z0-9_.\[\]]*)", text, re.IGNORECASE):
            append_unique_fact(facts, seen, Fact("mssql-function", match.group(1), "function", find_line_no(text, match.start())))
        for match in re.finditer(r"create\s+type\s+([\[\]A-Za-z_][A-Za-z0-9_.\[\]]*)\s+as\s+table", text, re.IGNORECASE):
            append_unique_fact(facts, seen, Fact("mssql-table-type", match.group(1), "table-type", find_line_no(text, match.start())))
    return facts


def extract_facts(
    path: Path,
    text: str,
    language: str,
    kind: str,
    analysis: FileAnalysis | None = None,
) -> list[Fact]:
    if path.name == "package.json":
        return extract_package_json_facts(text)
    if path.name == "Cargo.toml":
        return extract_cargo_toml_facts(text)
    if path.name == "go.mod":
        return extract_go_mod_facts(text)
    if path.name == "tsconfig.json" or path.name.startswith("tsconfig."):
        return extract_tsconfig_facts(text)
    if language in {"typescript", "javascript"}:
        config_facts = extract_tooling_config_facts(path, text, analysis)
        if config_facts:
            return config_facts
        facts = extract_typescript_backend_facts(text, analysis=analysis)
        facts.extend(extract_express_fastify_facts(text, analysis=analysis))
        facts.extend(extract_react_frontend_facts(path, text, analysis=analysis))
        facts.extend(extract_datastore_facts(path, text, analysis=analysis))
        return list({(fact.kind, fact.key, fact.value, fact.line): fact for fact in facts}.values())
    if language == "shell":
        return extract_zsh_dotfile_facts(path, text) if path.name.lower() in ZSH_DOTFILE_NAMES or path.suffix.lower() == ".zsh" else extract_shell_facts(text)
    if language == "hyprland":
        return extract_hyprland_facts(text)
    if language == "rust":
        return extract_rust_facts(path, text, analysis=analysis)
    if language == "go":
        return extract_go_facts(text, analysis=analysis)
    if language in {"c", "cpp"}:
        return extract_c_kernel_facts(text, analysis=analysis)
    if path.name == "pacman-packages.txt":
        return extract_package_facts(text, manager="pacman")
    if path.name == "aur-packages.txt":
        return extract_package_facts(text, manager="aur")
    if path.name in {"docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"}:
        return extract_docker_facts(path, text)
    if path.name.lower() == "dockerfile" or path.name.lower().endswith(".dockerfile"):
        return extract_docker_facts(path, text)
    if path.name.lower() == "redis.conf":
        return extract_datastore_facts(path, text)
    if path.suffix.lower() in SYSTEMD_UNIT_SUFFIXES or "systemd" in path.as_posix().lower():
        return extract_systemd_facts(path, text)
    if path.suffix.lower() == ".toml":
        return extract_toml_facts(text)
    if path.suffix.lower() in {".yaml", ".yml"}:
        infra_facts = extract_grafana_prometheus_facts(path, text)
        if infra_facts:
            return infra_facts
        datastore_facts = extract_datastore_facts(path, text)
        if datastore_facts:
            return datastore_facts
        return extract_yaml_facts(text)
    if path.suffix.lower() == ".json":
        infra_facts = extract_grafana_prometheus_facts(path, text)
        if infra_facts:
            return infra_facts
        return extract_json_facts(path, text)
    if language == "sql":
        return extract_sql_facts(path, text)
    return []


def summarize_file(
    rel_path: str,
    language: str,
    kind: str,
    chunks: Sequence[Chunk],
    facts: Sequence[Fact],
) -> tuple[str, str]:
    symbols = list(dict.fromkeys(chunk.symbol for chunk in chunks if chunk.symbol))[:12]
    fact_labels = list(dict.fromkeys(f"{fact.kind}:{fact.key}" for fact in facts))[:8]
    summary_bits = [f"{Path(rel_path).name} is a {language} {kind} file"]
    if symbols:
        summary_bits.append("covering " + ", ".join(symbols[:5]))
    if fact_labels:
        summary_bits.append("with notable facts " + ", ".join(fact_labels[:5]))
    return ". ".join(summary_bits) + ".", " | ".join(symbols)


def replace_file_facts(
    conn: sqlite3.Connection,
    repo: str,
    rel_path: str,
    package: str,
    file_hash: str,
    facts: Sequence[Fact],
) -> None:
    conn.execute("DELETE FROM facts WHERE repo = ? AND path = ?", (repo, rel_path))
    now = time.time()
    for fact in facts:
        fact_key = f"{repo}:{rel_path}:{fact.kind}:{fact.key}:{fact.line}:{file_hash}"
        fact_id = str(uuid.uuid5(uuid.NAMESPACE_URL, fact_key))
        conn.execute(
            """
            INSERT INTO facts (
                fact_id, repo, path, package, kind, key, value, line,
                confidence, source, file_hash, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                fact_id,
                repo,
                rel_path,
                package,
                fact.kind,
                fact.key,
                fact.value,
                fact.line,
                fact.confidence,
                fact.source,
                file_hash,
                now,
            ),
        )


def replace_file_summary(
    conn: sqlite3.Connection,
    repo: str,
    rel_path: str,
    package: str,
    file_hash: str,
    language: str,
    kind: str,
    summary: str,
    symbols: str,
    facts_count: int,
) -> None:
    conn.execute(
        """
        INSERT INTO file_summaries (
            repo, path, package, file_hash, language, kind, summary, symbols, facts_count, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(repo, path) DO UPDATE SET
            package=excluded.package,
            file_hash=excluded.file_hash,
            language=excluded.language,
            kind=excluded.kind,
            summary=excluded.summary,
            symbols=excluded.symbols,
            facts_count=excluded.facts_count,
            updated_at=excluded.updated_at
        """,
        (repo, rel_path, package, file_hash, language, kind, summary, symbols, facts_count, time.time()),
    )


def replace_file_symbols(
    conn: sqlite3.Connection,
    repo: str,
    rel_path: str,
    package: str,
    package_root: str,
    language: str,
    parser: str,
    file_hash: str,
    symbols,
) -> None:
    conn.execute("DELETE FROM symbols WHERE repo = ? AND path = ?", (repo, rel_path))
    conn.execute("DELETE FROM symbols_fts WHERE repo = ? AND path = ?", (repo, rel_path))
    now = time.time()
    for symbol in symbols:
        symbol_key = f"{repo}:{rel_path}:{symbol.qualified_name}:{symbol.start_line}:{file_hash}"
        symbol_id = str(uuid.uuid5(uuid.NAMESPACE_URL, symbol_key))
        conn.execute(
            """
            INSERT INTO symbols (
                symbol_id, repo, path, package, package_root, language, kind, name, qualified_name,
                signature, docstring, visibility, parent_symbol, start_line, end_line,
                exported, parser, file_hash, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                symbol_id,
                repo,
                rel_path,
                package,
                package_root,
                language,
                symbol.kind,
                symbol.name,
                symbol.qualified_name,
                symbol.signature,
                symbol.docstring,
                symbol.visibility,
                symbol.parent_symbol,
                symbol.start_line,
                symbol.end_line,
                int(symbol.exported),
                parser,
                file_hash,
                now,
            ),
        )
        conn.execute(
            """
            INSERT INTO symbols_fts (
                symbol_id, repo, path, package, name, qualified_name, kind, signature, docstring
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                symbol_id,
                repo,
                rel_path,
                package,
                symbol.name,
                symbol.qualified_name,
                symbol.kind,
                symbol.signature,
                symbol.docstring,
            ),
        )


def replace_file_dependencies(
    conn: sqlite3.Connection,
    repo: str,
    rel_path: str,
    package: str,
    package_root: str,
    file_hash: str,
    dependencies,
) -> None:
    conn.execute("DELETE FROM file_dependencies WHERE repo = ? AND source_path = ?", (repo, rel_path))
    now = time.time()
    for dependency in dependencies:
        edge_key = f"{repo}:{rel_path}:{dependency.raw_target}:{dependency.line}:{file_hash}"
        edge_id = str(uuid.uuid5(uuid.NAMESPACE_URL, edge_key))
        conn.execute(
            """
            INSERT INTO file_dependencies (
                edge_id, repo, source_path, package, package_root, dependency, dependency_kind,
                target_path, line, is_export, is_internal, file_hash, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                edge_id,
                repo,
                rel_path,
                package,
                package_root,
                dependency.raw_target,
                dependency.kind,
                dependency.target_path or None,
                dependency.line,
                int(dependency.is_export),
                int(dependency.is_internal),
                file_hash,
                now,
            ),
        )


def replace_semantic_lines(
    conn: sqlite3.Connection,
    repo: str,
    rel_path: str,
    package: str,
    language: str,
    file_hash: str,
    chunks: Sequence[tuple[str, Chunk]],
    semantic_lines,
) -> None:
    conn.execute("DELETE FROM semantic_lines WHERE repo = ? AND path = ?", (repo, rel_path))
    conn.execute("DELETE FROM semantic_lines_fts WHERE repo = ? AND path = ?", (repo, rel_path))
    now = time.time()
    for semantic_line in semantic_lines:
        chunk_id = next(
            (
                chunk_id
                for chunk_id, chunk in chunks
                if chunk.start_line <= semantic_line.line_no <= chunk.end_line
            ),
            chunks[0][0] if chunks else "",
        )
        if not chunk_id:
            continue
        line_key = f"{chunk_id}:{semantic_line.line_no}:{file_hash}"
        line_id = str(uuid.uuid5(uuid.NAMESPACE_URL, line_key))
        conn.execute(
            """
            INSERT INTO semantic_lines (
                line_id, chunk_id, repo, path, package, language, line_no, symbol, content, file_hash, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                line_id,
                chunk_id,
                repo,
                rel_path,
                package,
                language,
                semantic_line.line_no,
                semantic_line.symbol,
                semantic_line.content,
                file_hash,
                now,
            ),
        )
        conn.execute(
            """
            INSERT INTO semantic_lines_fts (
                line_id, chunk_id, repo, path, package, symbol, content
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                line_id,
                chunk_id,
                repo,
                rel_path,
                package,
                semantic_line.symbol,
                semantic_line.content,
            ),
        )


def replace_package_summaries(conn: sqlite3.Connection, repo: str) -> None:
    conn.execute("DELETE FROM package_summaries WHERE repo = ?", (repo,))
    now = time.time()
    for row in package_summary_rows(conn, repo):
        conn.execute(
            """
            INSERT INTO package_summaries (
                repo, package, package_root, summary, symbols, dependencies, file_count, paths, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                repo,
                row["package"],
                row["package_root"],
                row["summary"],
                row["symbols"],
                row["dependencies"],
                row["file_count"],
                row["paths"],
                now,
            ),
        )


def chunk_by_anchors(lines: list[str], anchors: list[tuple[int, str]], size: int, overlap: int, kind: str) -> list[Chunk]:
    if not anchors:
        return chunk_by_lines(lines, size=size, overlap=overlap, kind=kind)
    chunks: list[Chunk] = []
    boundaries = [index for index, _symbol in anchors] + [len(lines)]
    for anchor_index, (start, symbol) in enumerate(anchors):
        end = boundaries[anchor_index + 1]
        section = lines[start:end]
        if approx_tokens("\n".join(section)) <= 1400:
            chunks.append(
                Chunk(
                    content="\n".join(section).strip(),
                    start_line=start + 1,
                    end_line=end,
                    symbol=symbol,
                    kind=kind,
                )
            )
        else:
            chunks.extend(chunk_by_lines(section, size=size, overlap=overlap, kind=kind, symbol=symbol))
    return [chunk for chunk in chunks if chunk.content]


def chunk_by_lines(lines: list[str], size: int, overlap: int, kind: str, symbol: str = "") -> list[Chunk]:
    chunks: list[Chunk] = []
    start = 0
    while start < len(lines):
        end = min(len(lines), start + size)
        text = "\n".join(lines[start:end]).strip()
        if text:
            chunks.append(
                Chunk(
                    content=text,
                    start_line=start + 1,
                    end_line=end,
                    symbol=symbol,
                    kind=kind,
                )
            )
        if end >= len(lines):
            break
        start = max(start + 1, end - overlap)
    return chunks


def chunk_markdown(text: str) -> list[Chunk]:
    lines = text.splitlines()
    sections: list[tuple[int, int]] = []
    start = 0
    for index, line in enumerate(lines):
        if index and re.match(r"^#{1,6}\s", line):
            sections.append((start, index))
            start = index
    sections.append((start, len(lines)))
    chunks: list[Chunk] = []
    for start, end in sections:
        section_lines = lines[start:end]
        if approx_tokens("\n".join(section_lines)) <= 1100:
            chunks.append(
                Chunk(
                    content="\n".join(section_lines).strip(),
                    start_line=start + 1,
                    end_line=end,
                    symbol=section_lines[0].strip("# ").strip() if section_lines else "",
                    kind="docs",
                )
            )
            continue
        chunks.extend(chunk_by_lines(section_lines, size=90, overlap=18, kind="docs"))
    return [chunk for chunk in chunks if chunk.content]


def chunk_code(text: str, language: str, analysis: FileAnalysis | None = None) -> list[Chunk]:
    symbols = tuple(analysis.symbols) if analysis else ()
    if symbols:
        chunks = chunk_code_with_symbols(text, symbols)
        if chunks:
            return chunks
    lines = text.splitlines()
    regex_symbols = dedupe_symbols(extract_regex_symbols(text, language))
    if regex_symbols:
        chunks = chunk_code_with_symbols(text, regex_symbols)
        if chunks:
            return chunks
    anchors = [(index, extract_symbol(line)) for index, line in enumerate(lines) if extract_symbol(line)]
    return chunk_by_anchors(lines, anchors, size=220, overlap=40, kind="code")


def chunk_shell(text: str) -> list[Chunk]:
    lines = text.splitlines()
    anchors: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        if match := SHELL_FUNCTION_PATTERN.search(line):
            anchors.append((index, match.group(1)))
        elif line.strip().startswith("case ") and line.strip().endswith(" in"):
            anchors.append((index, line.strip()))
        elif match := SHELL_CASE_BRANCH_PATTERN.search(line):
            anchors.append((index, f"case:{match.group(1)}"))
        elif match := SHELL_ALIAS_PATTERN.search(line):
            anchors.append((index, f"alias {match.group(1)}"))
        elif match := SHELL_EXPORT_PATTERN.search(line):
            anchors.append((index, f"env {match.group(1)}"))
        else:
            for pattern in SHELL_TOOL_PATTERNS:
                if match := pattern.search(line):
                    anchors.append((index, f"tool:{match.group(1)}"))
                    break
    return chunk_by_anchors(lines, anchors, size=180, overlap=32, kind="code")


def chunk_toml(text: str) -> list[Chunk]:
    lines = text.splitlines()
    anchors = [(index, match.group(1)) for index, line in enumerate(lines) if (match := TOML_SECTION_PATTERN.search(line))]
    return chunk_by_anchors(lines, anchors, size=180, overlap=28, kind="config")


def chunk_yaml(text: str) -> list[Chunk]:
    lines = text.splitlines()
    anchors = [
        (index, line.split(":", 1)[0].strip())
        for index, line in enumerate(lines)
        if YAML_SECTION_PATTERN.search(line)
    ]
    return chunk_by_anchors(lines, anchors, size=180, overlap=28, kind="config")


def chunk_hyprland(text: str) -> list[Chunk]:
    lines = text.splitlines()
    anchors: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("$") and "=" in stripped:
            anchors.append((index, stripped.split("=", 1)[0].strip()))
            continue
        keyword = stripped.split("=", 1)[0].strip()
        if any(keyword.startswith(prefix) for prefix in HYPRLAND_KEYWORDS):
            anchors.append((index, hyprland_symbol(stripped)))
    return chunk_by_anchors(lines, anchors, size=120, overlap=18, kind="config")


def chunk_css(text: str) -> list[Chunk]:
    lines = text.splitlines()
    anchors: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        if match := CSS_AT_RULE_PATTERN.search(line):
            anchors.append((index, match.group(1).strip()))
        elif match := CSS_SELECTOR_PATTERN.search(line):
            anchors.append((index, match.group(1).strip()))
    return chunk_by_anchors(lines, anchors, size=180, overlap=24, kind="code")


def chunk_html(text: str) -> list[Chunk]:
    lines = text.splitlines()
    anchors = [(index, html_symbol(line)) for index, line in enumerate(lines) if html_symbol(line)]
    return chunk_by_anchors(lines, anchors, size=200, overlap=28, kind="code")


def chunk_xml_ui(text: str) -> list[Chunk]:
    lines = text.splitlines()
    anchors = [(index, xml_ui_symbol(line)) for index, line in enumerate(lines) if xml_ui_symbol(line)]
    return chunk_by_anchors(lines, anchors, size=200, overlap=28, kind="config")


def chunk_text(
    path: Path,
    text: str,
    kind: str,
    language: str,
    analysis: FileAnalysis | None = None,
) -> list[Chunk]:
    if kind == "docs":
        return chunk_markdown(text)
    if kind == "code":
        if language == "shell":
            return chunk_shell(text)
        if language == "css":
            return chunk_css(text)
        if language == "html":
            return chunk_html(text)
        return chunk_code(text, language, analysis)
    if kind == "log":
        return chunk_by_lines(text.splitlines(), size=350, overlap=50, kind="log")
    if kind == "config":
        if language == "hyprland":
            return chunk_hyprland(text)
        if path.suffix.lower() == ".toml":
            return chunk_toml(text)
        if path.suffix.lower() in {".yaml", ".yml"}:
            return chunk_yaml(text)
        if path.suffix.lower() in {".xml", ".ui", ".glade"}:
            return chunk_xml_ui(text)
        return chunk_by_lines(text.splitlines(), size=260, overlap=40, kind="config")
    return chunk_by_lines(text.splitlines(), size=200, overlap=30, kind="text")


def read_text_file(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        try:
            return path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            return None
    except OSError:
        return None


def build_ignore_matcher(root: Path):
    spec = PathSpec.from_lines("gitwildmatch", DEFAULT_IGNORE_PATTERNS)
    gitignore_matchers = []
    for candidate in (root / ".gitignore",):
        if candidate.exists():
            gitignore_matchers.append(parse_gitignore(str(candidate)))

    def ignored(full_path: Path) -> bool:
        rel = full_path.relative_to(root).as_posix()
        if rel == ".":
            return False
        if spec.match_file(rel):
            return True
        return any(matcher(str(full_path)) for matcher in gitignore_matchers)

    return ignored


def iter_text_files(root: Path) -> Iterable[Path]:
    ignored = build_ignore_matcher(root)
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if ignored(path):
            continue
        if path.suffix.lower() in {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".pdf"}:
            continue
        yield path


def remove_file_chunks(
    conn: sqlite3.Connection,
    client: SupportsQdrantPointOps,
    config: dict,
    repo: str,
    rel_path: str,
) -> None:
    rows = conn.execute(
        "SELECT chunk_id FROM chunks WHERE repo = ? AND path = ?",
        (repo, rel_path),
    ).fetchall()
    chunk_ids = [row["chunk_id"] for row in rows]
    if chunk_ids:
        client.delete(
            collection_name=config["qdrant_collection"],
            points_selector=models.PointIdsList(points=chunk_ids),
            wait=True,
        )
    conn.execute("DELETE FROM chunks WHERE repo = ? AND path = ?", (repo, rel_path))
    conn.execute("DELETE FROM chunks_fts WHERE repo = ? AND path = ?", (repo, rel_path))
    conn.execute("DELETE FROM facts WHERE repo = ? AND path = ?", (repo, rel_path))
    conn.execute("DELETE FROM symbols WHERE repo = ? AND path = ?", (repo, rel_path))
    conn.execute("DELETE FROM symbols_fts WHERE repo = ? AND path = ?", (repo, rel_path))
    conn.execute("DELETE FROM semantic_lines WHERE repo = ? AND path = ?", (repo, rel_path))
    conn.execute("DELETE FROM semantic_lines_fts WHERE repo = ? AND path = ?", (repo, rel_path))
    conn.execute("DELETE FROM file_dependencies WHERE repo = ? AND source_path = ?", (repo, rel_path))
    conn.execute("DELETE FROM file_summaries WHERE repo = ? AND path = ?", (repo, rel_path))


def index_repo(
    conn: sqlite3.Connection,
    client: SupportsQdrantPointOps,
    config: dict,
    root: Path,
    changed_only: bool,
    profile: dict,
) -> tuple[int, int]:
    ensure_collection(cast(SupportsQdrantCollectionAdmin, client), config)
    root, repo = repo_identity(root)
    all_files = list(iter_text_files(root))
    package_index = build_repo_package_index(root, repo, all_files)
    known_rel_paths = {path.relative_to(root).as_posix() for path in all_files}
    existing = {
        row["path"]: {
            "file_hash": row["file_hash"],
            "index_schema": row["index_schema"],
            "embedding_model": row["embedding_model"],
            "chunker": row["chunker"],
        }
        for row in conn.execute(
            "SELECT path, file_hash, index_schema, embedding_model, chunker FROM chunks "
            "WHERE repo = ? GROUP BY path, file_hash, index_schema, embedding_model, chunker",
            (repo,),
        ).fetchall()
    }
    discovered: dict[str, str] = {}
    changed_files = 0
    total_chunks = 0
    try:
        for file_path in all_files:
            rel_path = file_path.relative_to(root).as_posix()
            content = read_text_file(file_path)
            if not content or not content.strip():
                continue
            file_hash = hash_file(file_path)
            discovered[rel_path] = file_hash
            existing_file = existing.get(rel_path)
            if changed_only and existing_file == {
                "file_hash": file_hash,
                "index_schema": INDEX_SCHEMA,
                "embedding_model": config["embedding_model"],
                "chunker": CHUNKER_NAME,
            }:
                continue
            kind, language = detect_kind(file_path)
            analysis = analyze_file(root, file_path, rel_path, content, language, package_index, known_rel_paths)
            chunks = chunk_text(file_path, content, kind, language, analysis=analysis)
            if not chunks:
                continue
            facts = extract_facts(file_path, content, language, kind, analysis=analysis) if profile["facts"] else []
            semantic_lines = build_semantic_lines(
                content,
                analysis.symbols,
                max_lines=int(config["indexing"].get("semantic_line_limit", 800)),
            )
            remove_file_chunks(conn, client, config, repo, rel_path)
            texts = [chunk.content for chunk in chunks]
            vectors = list(get_embedder(config).embed(texts))
            modified_at = file_path.stat().st_mtime
            points = []
            chunk_rows: list[tuple[str, Chunk]] = []
            for index, (chunk, vector) in enumerate(zip(chunks, vectors)):
                chunk_key = f"{repo}:{rel_path}:{file_hash}:{index}:{chunk.start_line}:{chunk.end_line}"
                chunk_id = str(uuid.uuid5(uuid.NAMESPACE_URL, chunk_key))
                payload = {
                    "repo": repo,
                    "path": rel_path,
                    "package": analysis.package,
                    "language": language,
                    "kind": chunk.kind,
                    "symbol": chunk.symbol,
                    "modified_at": modified_at,
                    "chunk_index": index,
                    "start_line": chunk.start_line,
                    "end_line": chunk.end_line,
                    "index_schema": INDEX_SCHEMA,
                    "embedding_model": config["embedding_model"],
                    "chunker": CHUNKER_NAME,
                }
                points.append(models.PointStruct(id=chunk_id, vector=vector.tolist(), payload=payload))
                conn.execute(
                    """
                    INSERT INTO chunks (
                        chunk_id, repo, root, path, package, package_root, language, kind, symbol, modified_at,
                        file_hash, index_schema, embedding_model, chunker, chunk_index,
                        start_line, end_line, content
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        chunk_id,
                        repo,
                        str(root),
                        rel_path,
                        analysis.package,
                        analysis.package_root,
                        language,
                        chunk.kind,
                        chunk.symbol,
                        modified_at,
                        file_hash,
                        INDEX_SCHEMA,
                        config["embedding_model"],
                        CHUNKER_NAME,
                        index,
                        chunk.start_line,
                        chunk.end_line,
                        chunk.content,
                    ),
                )
                chunk_rows.append((chunk_id, chunk))
                conn.execute(
                    "INSERT INTO chunks_fts (chunk_id, repo, path, symbol, content) VALUES (?, ?, ?, ?, ?)",
                    (chunk_id, repo, rel_path, chunk.symbol, chunk.content),
                )
            replace_file_symbols(
                conn,
                repo,
                rel_path,
                analysis.package,
                analysis.package_root,
                language,
                analysis.parser,
                file_hash,
                analysis.symbols,
            )
            replace_file_dependencies(
                conn,
                repo,
                rel_path,
                analysis.package,
                analysis.package_root,
                file_hash,
                analysis.dependencies,
            )
            replace_semantic_lines(
                conn,
                repo,
                rel_path,
                analysis.package,
                language,
                file_hash,
                chunk_rows,
                semantic_lines,
            )
            if profile["facts"]:
                replace_file_facts(conn, repo, rel_path, analysis.package, file_hash, facts)
            if profile["file_summaries"]:
                summary, symbols = summarize_file(rel_path, language, kind, chunks, facts)
                replace_file_summary(
                    conn,
                    repo,
                    rel_path,
                    analysis.package,
                    file_hash,
                    language,
                    kind,
                    summary,
                    symbols,
                    len(facts),
                )
            else:
                conn.execute("DELETE FROM file_summaries WHERE repo = ? AND path = ?", (repo, rel_path))
            for batch in batched(points, 64):
                client.upsert(collection_name=config["qdrant_collection"], points=list(batch), wait=True)
            changed_files += 1
            total_chunks += len(chunks)
            conn.commit()
    except KeyboardInterrupt as exc:
        conn.rollback()
        raise IndexInterrupted(changed_files, total_chunks) from exc
    removed_paths = set(existing) - set(discovered)
    for rel_path in removed_paths:
        remove_file_chunks(conn, client, config, repo, rel_path)
    replace_package_summaries(conn, repo)
    conn.execute(
        "INSERT INTO indexed_repos (repo, root, last_indexed, last_indexed_branch, last_indexed_commit) "
        "VALUES (?, ?, ?, ?, ?) "
        "ON CONFLICT(repo) DO UPDATE SET "
        "root=excluded.root, "
        "last_indexed=excluded.last_indexed, "
        "last_indexed_branch=excluded.last_indexed_branch, "
        "last_indexed_commit=excluded.last_indexed_commit",
        (repo, str(root), time.time(), git_branch_for(root), git_head_commit_for(root)),
    )
    conn.commit()
    return changed_files, total_chunks

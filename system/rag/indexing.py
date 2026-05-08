from __future__ import annotations

import hashlib
import json
import math
import re
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Iterable, Sequence

from gitignore_parser import parse_gitignore
from pathspec import PathSpec
from qdrant_client import QdrantClient, models

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
from .storage import ensure_collection, get_embedder, repo_identity
from .types import Chunk, Fact, IndexInterrupted

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
}
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
DECORATOR_PATTERN = re.compile(r"@(?P<name>Controller|Get|Post|Put|Patch|Delete|All|Injectable|Entity|Module)\s*(?:\((?P<args>[^)]*)\))?")
CLASS_PATTERN = re.compile(r"^\s*(?:export\s+)?class\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)")
METHOD_PATTERN = re.compile(r"^\s*(?:public\s+|private\s+|protected\s+)?(?:async\s+)?(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\(")


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


def extract_typescript_backend_facts(text: str) -> list[Fact]:
    facts: list[Fact] = []
    pending_decorators: list[tuple[str, str, int]] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        if match := DECORATOR_PATTERN.match(stripped):
            pending_decorators.append((match.group("name"), decorator_arg_value(match.group("args")), line_no))
            continue
        if match := CLASS_PATTERN.match(line):
            class_name = match.group("name")
            handled = False
            for decorator_name, decorator_value, decorator_line in pending_decorators:
                if decorator_name == "Controller":
                    facts.append(Fact("route-controller", class_name, decorator_value or "/", decorator_line))
                    handled = True
                elif decorator_name == "Injectable":
                    facts.append(Fact("service", class_name, "injectable", decorator_line))
                    handled = True
                elif decorator_name == "Entity":
                    facts.append(Fact("entity", class_name, decorator_value or class_name, decorator_line))
                    handled = True
                elif decorator_name == "Module":
                    facts.append(Fact("module", class_name, "nest-module", decorator_line))
                    handled = True
            if not handled:
                if class_name.endswith("Controller"):
                    facts.append(Fact("route-controller", class_name, "controller", line_no))
                elif class_name.endswith("Service"):
                    facts.append(Fact("service", class_name, "class", line_no))
                elif class_name.endswith("Entity"):
                    facts.append(Fact("entity", class_name, class_name, line_no))
            pending_decorators = []
            continue
        if match := METHOD_PATTERN.match(line):
            method_name = match.group("name")
            for decorator_name, decorator_value, decorator_line in pending_decorators:
                if decorator_name in {"Get", "Post", "Put", "Patch", "Delete", "All"}:
                    path = decorator_value or "/"
                    facts.append(Fact("route-handler", f"{decorator_name.upper()} {path}", method_name, decorator_line))
            pending_decorators = []
            continue
        if pending_decorators and not stripped.startswith("@"):
            pending_decorators = []
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


def extract_sql_facts(text: str) -> list[Fact]:
    facts: list[Fact] = []
    pattern = re.compile(
        r"^\s*create\s+(?:or\s+replace\s+)?(?P<kind>table|view|function|procedure|trigger|index)\s+(?P<name>[A-Za-z_][A-Za-z0-9_.]*)",
        re.IGNORECASE,
    )
    for line_no, line in enumerate(text.splitlines(), start=1):
        if match := pattern.search(line):
            facts.append(Fact("sql-object", match.group("name"), match.group("kind").lower(), line_no))
    return facts


def extract_facts(path: Path, text: str, language: str, kind: str) -> list[Fact]:
    if language in {"typescript", "javascript"}:
        return extract_typescript_backend_facts(text)
    if language == "shell":
        return extract_shell_facts(text)
    if language == "hyprland":
        return extract_hyprland_facts(text)
    if path.name == "pacman-packages.txt":
        return extract_package_facts(text, manager="pacman")
    if path.name == "aur-packages.txt":
        return extract_package_facts(text, manager="aur")
    if path.name == "package.json":
        return extract_package_json_facts(text)
    if path.name in {"docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml"}:
        return extract_compose_yaml_facts(text)
    if path.suffix.lower() == ".toml":
        return extract_toml_facts(text)
    if path.suffix.lower() in {".yaml", ".yml"}:
        return extract_yaml_facts(text)
    if path.suffix.lower() == ".json":
        return extract_json_facts(path, text)
    if language == "sql":
        return extract_sql_facts(text)
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


def remove_file_chunks(conn: sqlite3.Connection, client: QdrantClient, config: dict, repo: str, rel_path: str) -> None:
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
    client: QdrantClient,
    config: dict,
    root: Path,
    changed_only: bool,
    profile: dict,
) -> tuple[int, int]:
    ensure_collection(client, config)
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
            facts = extract_facts(file_path, content, language, kind) if profile["facts"] else []
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
        "INSERT INTO indexed_repos (repo, root, last_indexed) VALUES (?, ?, ?) "
        "ON CONFLICT(repo) DO UPDATE SET root=excluded.root, last_indexed=excluded.last_indexed",
        (repo, str(root), time.time()),
    )
    conn.commit()
    return changed_files, total_chunks

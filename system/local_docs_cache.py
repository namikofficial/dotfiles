#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import dataclasses
import html
import importlib
import json
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from pathlib import Path
from typing import Any


REPO_DIR = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = REPO_DIR / "configs" / "local-docs" / "sources.json"


try:
    _mcp_server = importlib.import_module("mcp.server")
    _mcp_server_models = importlib.import_module("mcp.server.models")
    mcp_stdio = importlib.import_module("mcp.server.stdio")
    types = importlib.import_module("mcp.types")
    NotificationOptions = _mcp_server.NotificationOptions
    Server = _mcp_server.Server
    InitializationOptions = _mcp_server_models.InitializationOptions
    MCP_AVAILABLE = True
except ModuleNotFoundError:
    MCP_AVAILABLE = False


class TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []
        self.skip_depth = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in {"script", "style", "svg", "noscript"}:
            self.skip_depth += 1
        if tag in {"h1", "h2", "h3", "h4"}:
            self.parts.append("\n\n")
        elif tag in {"p", "div", "section", "article", "li", "pre", "br"}:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag in {"script", "style", "svg", "noscript"} and self.skip_depth:
            self.skip_depth -= 1
        if tag in {"h1", "h2", "h3", "h4", "p", "li", "pre"}:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        if not self.skip_depth:
            text = data.strip()
            if text:
                self.parts.append(text + " ")

    def text(self) -> str:
        content = "".join(self.parts)
        content = html.unescape(content)
        content = re.sub(r"[ \t]+", " ", content)
        content = re.sub(r"\n{3,}", "\n\n", content)
        return content.strip()


@dataclasses.dataclass(frozen=True)
class Source:
    id: str
    name: str
    kind: str = "url"
    url: str = ""
    follow_links: bool = False
    max_links: int = 0
    include_patterns: tuple[str, ...] = ()
    manpages: tuple[str, ...] = ()
    commands: tuple[dict[str, Any], ...] = ()


def load_config(path: Path = DEFAULT_CONFIG) -> tuple[Path, list[Source]]:
    raw = json.loads(path.read_text())
    cache_dir = Path(raw.get("cache_dir", "~/.cache/local-docs")).expanduser()
    sources = [
        Source(
            id=item["id"],
            name=item.get("name", item["id"]),
            kind=item.get("kind", "url"),
            url=item.get("url", ""),
            follow_links=bool(item.get("follow_links", False)),
            max_links=int(item.get("max_links", 0)),
            include_patterns=tuple(item.get("include_patterns", [])),
            manpages=tuple(item.get("manpages", [])),
            commands=tuple(item.get("commands", [])),
        )
        for item in raw.get("sources", [])
    ]
    return cache_dir, sources


def fetch(url: str, timeout: int = 12) -> tuple[str, str]:
    request = urllib.request.Request(url, headers={"User-Agent": "local-docs-cache/1.0"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        content_type = response.headers.get("content-type", "")
        data = response.read()
    return data.decode("utf-8", errors="replace"), content_type


def normalize_text(content: str, content_type: str, url: str) -> str:
    if "html" in content_type or re.search(r"\.html?$", urllib.parse.urlparse(url).path):
        parser = TextExtractor()
        parser.feed(content)
        return parser.text()
    return content.strip()


def markdown_links(content: str, base_url: str, patterns: tuple[str, ...]) -> list[str]:
    seen: set[str] = set()
    links: list[str] = []
    base_host = urllib.parse.urlparse(base_url).netloc

    def usable(url: str) -> bool:
        if any(char in url for char in "{}()\n\r\t "):
            return False
        try:
            url.encode("ascii")
        except UnicodeEncodeError:
            return False
        parsed = urllib.parse.urlparse(url)
        if parsed.netloc == "raw.githubusercontent.com" and parsed.path.endswith("/"):
            return False
        return parsed.scheme in {"http", "https"} and parsed.netloc == base_host

    for match in re.finditer(r"\[[^\]]+\]\(([^)]+)\)", content):
        href = match.group(1).strip()
        if href.startswith("#"):
            continue
        url = urllib.parse.urljoin(base_url, href).split("#", 1)[0]
        if not usable(url):
            continue
        if patterns and not any(pattern in url for pattern in patterns):
            continue
        if url not in seen:
            seen.add(url)
            links.append(url)
    if not links:
        for double_quoted, single_quoted, bare in re.findall(r"""href=(?:"([^"]+)"|'([^']+)'|([^'" >]+))""", content):
            href = double_quoted or single_quoted or bare
            url = urllib.parse.urljoin(base_url, href).split("#", 1)[0]
            if not usable(url):
                continue
            if patterns and not any(pattern in url for pattern in patterns):
                continue
            if url not in seen:
                seen.add(url)
                links.append(url)
    return links


def clean_terminal_text(text: str) -> str:
    text = re.sub(r".\x08", "", text)
    text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text)
    text = re.sub(r"\r", "", text)
    text = re.sub(r"[ \t]+\n", "\n", text)
    return re.sub(r"\n{4,}", "\n\n\n", text).strip()


def run_command(argv: list[str], timeout: int = 20) -> tuple[str, str | None]:
    if not argv:
        return "", "empty argv"
    executable = shutil.which(argv[0])
    if executable is None:
        return "", f"{argv[0]} not found on PATH"
    try:
        completed = subprocess.run(
            [executable, *argv[1:]],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return "", str(exc)
    output = "\n".join(part for part in (completed.stdout, completed.stderr) if part)
    if completed.returncode not in {0, 1, 2} and not output:
        return "", f"exit {completed.returncode}"
    return clean_terminal_text(output), None


def read_manpage(page: str) -> tuple[str, str | None]:
    man = shutil.which("man")
    if man is None:
        return "", "man not found on PATH"
    env = {"MANPAGER": "cat", "PAGER": "cat", "MANWIDTH": "100"}
    try:
        completed = subprocess.run(
            [man, page],
            check=False,
            capture_output=True,
            text=True,
            timeout=20,
            env={**env, **dict(PATH="/usr/local/bin:/usr/bin:/bin")},
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return "", str(exc)
    output = completed.stdout or completed.stderr
    col = shutil.which("col")
    if col and output:
        try:
            filtered = subprocess.run(
                [col, "-bx"],
                input=output,
                check=False,
                capture_output=True,
                text=True,
                timeout=10,
            )
            if filtered.stdout:
                output = filtered.stdout
        except (OSError, subprocess.SubprocessError):
            pass
    if completed.returncode != 0 and not output:
        return "", f"exit {completed.returncode}"
    return clean_terminal_text(output), None


def doc_path(cache_dir: Path, source_id: str) -> Path:
    return cache_dir / "docs" / f"{source_id}.txt"


def manifest_path(cache_dir: Path) -> Path:
    return cache_dir / "manifest.json"


def read_manifest(cache_dir: Path) -> dict[str, Any]:
    path = manifest_path(cache_dir)
    if not path.exists():
        return {"updated_at": None, "docs": {}}
    return json.loads(path.read_text())


def write_manifest(cache_dir: Path, manifest: dict[str, Any]) -> None:
    manifest_path(cache_dir).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def refresh_source(cache_dir: Path, source: Source) -> dict[str, Any]:
    errors: list[str] = []
    fetched_urls: list[str] = []
    sections: list[str] = [f"# {source.name}\n\n"]

    if source.kind == "url":
        if not source.url:
            raise ValueError(f"{source.id}: url source requires url")
        content, content_type = fetch(source.url)
        sections.append(f"Source: {source.url}\n\n{normalize_text(content, content_type, source.url)}")
        fetched_urls.append(source.url)

        if source.follow_links:
            for url in markdown_links(content, source.url, source.include_patterns)[: source.max_links]:
                try:
                    linked, linked_type = fetch(url)
                    sections.append(f"\n\n---\n\n## {url}\n\n{normalize_text(linked, linked_type, url)}")
                    fetched_urls.append(url)
                except Exception as exc:
                    errors.append(f"{url}: {exc}")
    elif source.kind == "manpages":
        for page in source.manpages:
            text, error = read_manpage(page)
            if error:
                errors.append(f"{page}: {error}")
            if text:
                sections.append(f"\n\n---\n\n## man {page}\n\n{text}")
        fetched_urls.append("local:manpages")
    elif source.kind == "commands":
        for command in source.commands:
            label = str(command.get("label") or " ".join(command.get("argv", [])))
            argv = [str(part) for part in command.get("argv", [])]
            text, error = run_command(argv, int(command.get("timeout", 20)))
            if error:
                errors.append(f"{label}: {error}")
            if text:
                sections.append(f"\n\n---\n\n## {label}\n\nCommand: {' '.join(argv)}\n\n{text}")
        fetched_urls.append("local:commands")
    else:
        raise ValueError(f"{source.id}: unknown source kind {source.kind}")

    output = "\n".join(sections).strip() + "\n"
    path = doc_path(cache_dir, source.id)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(output)
    return {
        "id": source.id,
        "name": source.name,
        "kind": source.kind,
        "url": source.url or f"local:{source.kind}",
        "path": str(path),
        "bytes": len(output.encode("utf-8")),
        "fetched_urls": fetched_urls,
        "errors": errors,
        "updated_at": int(time.time()),
    }


def refresh(stack: str | None = None) -> dict[str, Any]:
    cache_dir, sources = load_config()
    selected = [source for source in sources if stack in {None, source.id, source.name}]
    if stack and not selected:
        raise SystemExit(f"Unknown docs stack: {stack}")
    cache_dir.mkdir(parents=True, exist_ok=True)
    manifest = read_manifest(cache_dir)
    manifest.setdefault("docs", {})
    for source in selected:
        print(f"refreshing {source.id}...", file=sys.stderr)
        try:
            manifest["docs"][source.id] = refresh_source(cache_dir, source)
        except (OSError, urllib.error.URLError, TimeoutError, ValueError) as exc:
            manifest["docs"][source.id] = {
                "id": source.id,
                "name": source.name,
                "kind": source.kind,
                "url": source.url or f"local:{source.kind}",
                "path": str(doc_path(cache_dir, source.id)),
                "bytes": 0,
                "fetched_urls": [],
                "errors": [str(exc)],
                "updated_at": int(time.time()),
            }
        manifest["updated_at"] = int(time.time())
        write_manifest(cache_dir, manifest)
    manifest["updated_at"] = int(time.time())
    write_manifest(cache_dir, manifest)
    return manifest


def status() -> dict[str, Any]:
    cache_dir, sources = load_config()
    manifest = read_manifest(cache_dir)
    return {
        "cache_dir": str(cache_dir),
        "configured": [dataclasses.asdict(source) for source in sources],
        "cached": manifest.get("docs", {}),
        "updated_at": manifest.get("updated_at"),
    }


def source_text(cache_dir: Path, source_id: str) -> str:
    path = doc_path(cache_dir, source_id)
    if not path.exists():
        raise FileNotFoundError(f"{source_id} is not cached. Run: local-docs-cache refresh {source_id}")
    return path.read_text(errors="replace")


def search_docs(query: str, stack: str | None = None, limit: int = 6) -> list[dict[str, Any]]:
    cache_dir, sources = load_config()
    terms = [term for term in re.findall(r"[a-zA-Z0-9_./-]+", query.lower()) if len(term) > 1]
    results: list[dict[str, Any]] = []
    for source in sources:
        if stack and stack not in {source.id, source.name}:
            continue
        try:
            text = source_text(cache_dir, source.id)
        except FileNotFoundError:
            continue
        chunks = re.split(r"\n(?=#{1,4} |\n---)", text)
        if len(chunks) <= 1:
            chunks = [text[i : i + 5000] for i in range(0, len(text), 4500)]
        for chunk in chunks:
            lower = chunk.lower()
            score = sum(lower.count(term) for term in terms)
            if score <= 0:
                continue
            snippet = re.sub(r"\s+", " ", chunk).strip()[:1600]
            results.append({"stack": source.id, "name": source.name, "score": score, "snippet": snippet})
    return sorted(results, key=lambda item: item["score"], reverse=True)[:limit]


def require_mcp() -> None:
    if not MCP_AVAILABLE:
        raise SystemExit("python package 'mcp' is required. Use system/local-docs-mcp.sh from the RAG venv.")


def run_mcp() -> int:
    require_mcp()
    server = Server("local-docs-cache")

    @server.list_resources()
    async def list_resources():
        cache_dir, sources = load_config()
        resources = [
            types.Resource(
                uri="local-docs://manifest",
                name="Local Docs Manifest",
                description="Cached documentation source status.",
                mimeType="application/json",
            )
        ]
        for source in sources:
            resources.append(
                types.Resource(
                    uri=f"local-docs://doc/{source.id}",
                    name=f"{source.name} cached docs",
                    description=f"Cached local docs for {source.name}",
                    mimeType="text/markdown",
                )
            )
        return resources

    @server.read_resource()
    async def read_resource(uri):
        uri_str = str(uri)
        cache_dir, _sources = load_config()
        if uri_str == "local-docs://manifest":
            return json.dumps(status(), indent=2)
        prefix = "local-docs://doc/"
        if uri_str.startswith(prefix):
            return source_text(cache_dir, uri_str.removeprefix(prefix))
        raise ValueError(f"Unknown local docs resource: {uri_str}")

    @server.list_tools()
    async def list_tools():
        return [
            types.Tool(
                name="local_docs_search",
                description="Search cached local framework/library docs without network access.",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "query": {"type": "string"},
                        "stack": {"type": "string", "description": "Optional source id such as react, vite, tanstack-query, mikro-orm, rust-book, android"},
                        "limit": {"type": "integer", "default": 6},
                    },
                    "required": ["query"],
                },
            ),
            types.Tool(
                name="local_docs_status",
                description="Show configured and cached local docs sources.",
                inputSchema={"type": "object", "properties": {}},
            ),
            types.Tool(
                name="local_docs_read",
                description="Read a cached docs source by id.",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "stack": {"type": "string"},
                        "max_chars": {"type": "integer", "default": 12000},
                    },
                    "required": ["stack"],
                },
            ),
            types.Tool(
                name="local_docs_refresh",
                description="Refresh cached docs from the network. Use only when current docs are explicitly needed.",
                inputSchema={
                    "type": "object",
                    "properties": {"stack": {"type": "string", "description": "Optional source id"}},
                },
            ),
        ]

    @server.call_tool()
    async def call_tool(name: str, arguments: dict[str, Any] | None):
        args = arguments or {}
        if name == "local_docs_search":
            payload = search_docs(args["query"], args.get("stack"), int(args.get("limit", 6)))
        elif name == "local_docs_status":
            payload = status()
        elif name == "local_docs_read":
            cache_dir, _sources = load_config()
            payload = source_text(cache_dir, args["stack"])[: int(args.get("max_chars", 12000))]
        elif name == "local_docs_refresh":
            payload = refresh(args.get("stack"))
        else:
            raise ValueError(f"Unknown local docs tool: {name}")
        text = payload if isinstance(payload, str) else json.dumps(payload, indent=2)
        return [types.TextContent(type="text", text=text)]

    async def main() -> None:
        async with mcp_stdio.stdio_server() as (read_stream, write_stream):
            await server.run(
                read_stream,
                write_stream,
                InitializationOptions(
                    server_name="local-docs-cache",
                    server_version="1.0.0",
                    capabilities=server.get_capabilities(
                        notification_options=NotificationOptions(),
                        experimental_capabilities={},
                    ),
                ),
            )

    asyncio.run(main())
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="local-docs-cache")
    subparsers = parser.add_subparsers(dest="command", required=True)
    refresh_parser = subparsers.add_parser("refresh")
    refresh_parser.add_argument("stack", nargs="?")
    search_parser = subparsers.add_parser("search")
    search_parser.add_argument("query")
    search_parser.add_argument("--stack")
    search_parser.add_argument("--limit", type=int, default=6)
    subparsers.add_parser("status")
    read_parser = subparsers.add_parser("read")
    read_parser.add_argument("stack")
    read_parser.add_argument("--max-chars", type=int, default=12000)
    subparsers.add_parser("mcp")

    args = parser.parse_args(argv)
    if args.command == "refresh":
        print(json.dumps(refresh(args.stack), indent=2))
    elif args.command == "search":
        print(json.dumps(search_docs(args.query, args.stack, args.limit), indent=2))
    elif args.command == "status":
        print(json.dumps(status(), indent=2))
    elif args.command == "read":
        cache_dir, _sources = load_config()
        print(source_text(cache_dir, args.stack)[: args.max_chars])
    elif args.command == "mcp":
        return run_mcp()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

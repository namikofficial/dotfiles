from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from .learning import list_memory_candidates
from .memory import build_context_pack
from .retrieval import retrieve
from .runtime import console
from .settings import get_mode_profile, load_config
from .storage import connect_db, get_qdrant, infer_repo_filter
from .state import list_commands, list_errors, list_memory_entries


def handle_tool(tool: str, payload: dict[str, Any]) -> dict[str, Any]:
    conn = connect_db()
    repo = infer_repo_filter(conn, payload.get("repo"))
    if tool == "memory":
        rows = list_memory_entries(conn, repo, kind=None, status="active", scope="all", limit=int(payload.get("limit", 20)))
        return {
            "memories": [
                {"kind": row["kind"], "content": row["value"], "confidence": 1.0}
                for row in rows
            ]
        }
    if tool == "recent-errors":
        rows = list_errors(conn, repo, int(payload.get("limit", 20)))
        return {
            "errors": [
                {"message": row["error_text"], "command": row["command"], "ts": row["updated_at"]}
                for row in rows
            ]
        }
    if tool == "recent-commands":
        rows = list_commands(conn, repo, int(payload.get("limit", 20)))
        return {
            "commands": [
                {"command": row["command"], "exit_code": None, "ts": row["updated_at"]}
                for row in rows
            ]
        }
    if tool == "repo-rules":
        rows = list_memory_entries(conn, repo, kind="repo_conventions", status="active", scope="all", limit=20)
        return {"rules": "\n".join(f"- {row['subject']}: {row['value']}" for row in rows)}
    if tool == "memory-candidates":
        rows = list_memory_candidates(conn, status=payload.get("status", "pending"), limit=int(payload.get("limit", 20)))
        return {"candidates": [dict(row) for row in rows]}
    if tool == "context":
        name = payload.get("name") or payload.get("task") or "context"
        content, metadata = build_context_pack(conn, repo, str(name), agent_target=str(payload.get("target", "generic")))
        return {"context_pack": content, "token_count": metadata.get("tokens", 0), "metadata": metadata}
    if tool == "search":
        config = get_mode_profile(load_config(), payload.get("mode", "deep"))
        result = retrieve(
            conn,
            get_qdrant(config),
            config,
            str(payload["query"]),
            repo,
            rerank=True,
            mode=payload.get("mode", "deep"),
        )
        return {
            "chunks": [
                {"text": row["content"], "file": row["path"], "score": row["score"]}
                for row in result.rows[: int(payload.get("limit", 20))]
            ]
        }
    if tool == "handoff":
        from .router import build_agent_plan, target_from_flag
        from .prompt_compiler import compile_prompt

        task = str(payload["task"])
        plan = build_agent_plan(task, conn=conn, repo=repo, explicit_target=target_from_flag(payload.get("target")))
        content, _metadata = build_context_pack(conn, repo, task[:40] or "handoff", agent_target=plan.target)
        prompt = compile_prompt(plan, content)
        return {"compiled_prompt": prompt.text(), "plan": plan.to_dict()}
    raise ValueError(f"unknown tool: {tool}")


class RagHttpHandler(BaseHTTPRequestHandler):
    server_version = "rag-http/0.1"

    def do_POST(self) -> None:  # noqa: N802
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
        tool = self.path.removeprefix("/v1/").strip("/")
        try:
            response = handle_tool(tool, payload)
            body = json.dumps(response).encode("utf-8")
            self.send_response(200)
        except Exception as exc:
            body = json.dumps({"error": str(exc)}).encode("utf-8")
            self.send_response(400)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        return


def run_http(host: str = "127.0.0.1", port: int = 7433) -> int:
    server = ThreadingHTTPServer((host, port), RagHttpHandler)
    console.print(f"[green]rag HTTP server[/green] listening on http://{host}:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        console.print("[yellow]Stopping rag HTTP server.[/yellow]")
    finally:
        server.server_close()
    return 0


def run_mcp_stdio() -> int:
    import sys

    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            request = json.loads(line)
            tool = request.get("tool")
            payload = request.get("input", {})
            response = {"ok": True, "output": handle_tool(str(tool), payload)}
        except Exception as exc:
            response = {"ok": False, "error": str(exc)}
        print(json.dumps(response), flush=True)
    return 0

#!/usr/bin/env python3
"""
RAG MCP Server - Exposes RAG functionality as Model Context Protocol tools and resources
"""

import asyncio
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

# Add the RAG system to path
sys.path.insert(0, str(Path(__file__).parent))

from mcp.server.models import InitializationOptions
from mcp.server import NotificationOptions, Server
from mcp.types import (
    Resource,
    Tool,
    TextContent,
    ImageContent,
    EmbeddedResource,
)
import mcp.server.stdio
import mcp.types as types

from rag.cli import main as rag_main
from rag.memory import build_context_pack, generate_repo_memory
from rag.retrieval import hybrid_search
from rag.llm import ask_llm
from rag.state import get_state
import tempfile


class RagMcpServer:
    def __init__(self):
        self.server = Server("rag-mcp")
        self.setup_handlers()
    
    def setup_handlers(self):
        @self.server.list_resources()
        async def handle_list_resources() -> List[Resource]:
            """List available RAG resources."""
            return [
                Resource(
                    uri="rag://task/current",
                    name="Current Task",
                    description="Current task execution plan from .agent/task.md",
                    mimeType="text/markdown",
                ),
                Resource(
                    uri="rag://memory/project",
                    name="Project Memory",
                    description="Persistent project knowledge from .agent/memory.md",
                    mimeType="text/markdown",
                ),
                Resource(
                    uri="rag://decisions",
                    name="Project Decisions",
                    description="Stable engineering decisions from .agent/decisions.md",
                    mimeType="text/markdown",
                ),
                Resource(
                    uri="rag://checks",
                    name="Recommended Checks",
                    description="Commands to run for validation from .agent/checks.md",
                    mimeType="text/markdown",
                ),
                Resource(
                    uri="rag://context/latest",
                    name="Latest Context Pack",
                    description="Most recent RAG context pack",
                    mimeType="text/markdown",
                ),
                Resource(
                    uri="rag://repo/summary",
                    name="Repository Summary",
                    description="AI-generated summary of the repository",
                    mimeType="text/markdown",
                ),
                Resource(
                    uri="rag://git/status",
                    name="Git Status",
                    description="Current git repository status",
                    mimeType="text/plain",
                ),
            ]

        @self.server.read_resource()
        async def handle_read_resource(uri: types.AnyUrl) -> str:
            """Read a specific RAG resource."""
            uri_str = str(uri)
            repo_root = self._find_repo_root()
            
            if uri_str == "rag://task/current":
                task_file = repo_root / ".agent" / "task.md"
                if task_file.exists():
                    return task_file.read_text()
                return "# Current Task\n\n*No task initialized yet.*"
                
            elif uri_str == "rag://memory/project":
                memory_file = repo_root / ".agent" / "memory.md"
                if memory_file.exists():
                    return memory_file.read_text()
                return "# Project Memory\n\n*No project memory yet.*"
                
            elif uri_str == "rag://decisions":
                decisions_file = repo_root / ".agent" / "decisions.md"
                if decisions_file.exists():
                    return decisions_file.read_text()
                return "# Decisions\n\n*No decisions recorded yet.*"
                
            elif uri_str == "rag://checks":
                checks_file = repo_root / ".agent" / "checks.md"
                if checks_file.exists():
                    return checks_file.read_text()
                return "# Checks\n\n*No checks defined.*\n\n## Default\n```bash\necho \"No checks configured\"\n```\n"
                
            elif uri_str == "rag://context/latest":
                # Generate a fresh context pack
                try:
                    state = get_state(repo_root)
                    context_pack = build_context_pack(state, repo_root)
                    return f"# Context Pack\n\n{context_pack}"
                except Exception as e:
                    return f"# Context Pack\n\nError generating context: {e}"
                    
            elif uri_str == "rag://repo/summary":
                try:
                    repo_memory = generate_repo_memory(repo_root)
                    return f"# Repository Summary\n\n{repo_memory}"
                except Exception as e:
                    return f"# Repository Summary\n\nError generating summary: {e}"
                    
            elif uri_str == "rag://git/status":
                try:
                    result = subprocess.run(
                        ["git", "status", "--porcelain"],
                        cwd=repo_root,
                        capture_output=True,
                        text=True,
                        timeout=5
                    )
                    if result.returncode == 0:
                        return f"# Git Status\n\n{result.stdout}" if result.stdout.strip() else "# Git Status\n\n*Working directory clean*"
                    else:
                        return f"# Git Status\n\nError getting git status: {result.stderr}"
                except Exception as e:
                    return f"# Git Status\n\nError accessing git: {e}"
            
            raise ValueError(f"Unknown resource URI: {uri}")

        @self.server.list_tools()
        async def handle_list_tools() -> List[Tool]:
            """List available RAG tools."""
            return [
                Tool(
                    name="rag_search",
                    description="Search for relevant code/files using hybrid retrieval",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "query": {"type": "string", "description": "Search query"},
                            "limit": {"type": "integer", "description": "Maximum results to return", "default": 8},
                            "include_files": {"type": "boolean", "description": "Include file paths in results", "default": True}
                        },
                        "required": ["query"]
                    }
                ),
                Tool(
                    name="rag_deep",
                    description="Get a deep explanation using RAG with LLM reasoning",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "question": {"type": "string", "description": "Question to answer"},
                            "budget": {"type": "string", "description": "Reasoning budget (low/medium/high)", "default": "medium"}
                        },
                        "required": ["question"]
                    }
                ),
                Tool(
                    name="rag_quick",
                    description="Get a quick factual answer from RAG",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "question": {"type": "string", "description": "Question to answer"}
                        },
                        "required": ["question"]
                    }
                ),
                Tool(
                    name="rag_agent_context",
                    description="Get comprehensive context for starting an agent task",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "task": {"type": "string", "description": "Task description"},
                            "mode": {"type": "string", "description": "Context mode (fast/balanced/deep)", "default": "balanced"},
                            "max_tokens": {"type": "integer", "description": "Maximum tokens for context", "default": 12000}
                        },
                        "required": ["task"]
                    }
                ),
                Tool(
                    name="rag_task_init",
                    description="Initialize a new task in .agent/task.md",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "task_description": {"type": "string", "description": "The task to initialize"}
                        },
                        "required": ["task_description"]
                    }
                ),
                Tool(
                    name="rag_task_status",
                    description="Get current task status",
                    inputSchema={
                        "type": "object",
                        "properties": {}
                    }
                ),
                Tool(
                    name="rag_task_done",
                    description="Mark task as complete and update memory",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "summary": {"type": "string", "description": "Task completion summary"}
                        }
                    }
                ),
                Tool(
                    name="rag_memory_add",
                    description="Add a durable fact to project memory",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "fact": {"type": "string", "description": "Fact to remember"},
                            "scope": {"type": "string", "description": "Scope (repo/project/global)", "default": "repo"},
                            "confidence": {"type": "string", "description": "Confidence level (low/medium/high)", "default": "medium"}
                        },
                        "required": ["fact"]
                    }
                ),
                Tool(
                    name="rag_memory_read",
                    description="Read facts from project memory",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "query": {"type": "string", "description": "Search query for memories"}
                        }
                    }
                ),
                Tool(
                    name="rag_checks",
                    description="Get recommended checks to run",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "mode": {"type": "string", "description": "Check mode (fast/full)", "default": "fast"}
                        }
                    }
                ),
                Tool(
                    name="rag_repo_status",
                    description="Get overall repository status",
                    inputSchema={
                        "type": "object",
                        "properties": {}
                    }
                )
            ]

        @self.server.call_tool()
        async def handle_call_tool(name: str, arguments: Dict[str, Any]) -> List[types.TextContent]:
            """Handle tool calls."""
            repo_root = self._find_repo_root()
            
            try:
                if name == "rag_search":
                    return await self._handle_rag_search(arguments, repo_root)
                elif name == "rag_deep":
                    return await self._handle_rag_deep(arguments, repo_root)
                elif name == "rag_quick":
                    return await self._handle_rag_quick(arguments, repo_root)
                elif name == "rag_agent_context":
                    return await self._handle_rag_agent_context(arguments, repo_root)
                elif name == "rag_task_init":
                    return await self._handle_rag_task_init(arguments, repo_root)
                elif name == "rag_task_status":
                    return await self._handle_rag_task_status(arguments, repo_root)
                elif name == "rag_task_done":
                    return await self._handle_rag_task_done(arguments, repo_root)
                elif name == "rag_memory_add":
                    return await self._handle_rag_memory_add(arguments, repo_root)
                elif name == "rag_memory_read":
                    return await self._handle_rag_memory_read(arguments, repo_root)
                elif name == "rag_checks":
                    return await self._handle_rag_checks(arguments, repo_root)
                elif name == "rag_repo_status":
                    return await self._handle_rag_repo_status(arguments, repo_root)
                else:
                    raise ValueError(f"Unknown tool: {name}")
                    
            except Exception as e:
                return [types.TextContent(
                    type="text",
                    text=f"Error executing {name}: {str(e)}"
                )]

    def _find_repo_root(self) -> Path:
        """Find the repository root by looking for .git or .agent directory."""
        current = Path.cwd()
        while current != current.parent:
            if (current / ".git").exists() or (current / ".agent").exists():
                return current
            current = current.parent
        return Path.cwd()

    async def _handle_rag_search(self, args: Dict[str, Any], repo_root: Path) -> List[types.TextContent]:
        """Handle rag_search tool."""
        query = args["query"]
        limit = args.get("limit", 8)
        include_files = args.get("include_files", True)
        
        # Use existing RAG search functionality
        try:
            # Change to repo root and run search
            import subprocess
            result = subprocess.run([
                sys.executable, "-m", "rag.cli", "search", 
                query, "--limit", str(limit), "--json"
            ], cwd=repo_root, capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                try:
                    search_results = json.loads(result.stdout)
                    formatted_results = []
                    for item in search_results.get("results", []):
                        if include_files:
                            formatted_results.append({
                                "file": item.get("file", ""),
                                "score": item.get("score", 0.0),
                                "why": item.get("why", ""),
                                "snippet": item.get("snippet", "")[:200] + "..." if len(item.get("snippet", "")) > 200 else item.get("snippet", "")
                            })
                        else:
                            formatted_results.append({
                                "content": item.get("content", ""),
                                "score": item.get("score", 0.0),
                                "why": item.get("why", "")
                            })
                    
                    return [types.TextContent(
                        type="text",
                        text=json.dumps({"results": formatted_results}, indent=2)
                    )]
                except json.JSONDecodeError:
                    return [types.TextContent(
                        type="text",
                        text=result.stdout
                    )]
            else:
                return [types.TextContent(
                    type="text",
                    text=f"Search failed: {result.stderr}"
                )]
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"Error during search: {str(e)}"
            )]

    async def _handle_rag_deep(self, args: Dict[str, Any], repo_root: Path) -> List[types.TextContent]:
        """Handle rag_deep tool."""
        question = args["question"]
        budget = args.get("budget", "medium")
        
        try:
            import subprocess
            result = subprocess.run([
                sys.executable, "-m", "rag.cli", "deep", 
                question, "--budget", budget
            ], cwd=repo_root, capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                return [types.TextContent(
                    type="text",
                    text=result.stdout
                )]
            else:
                return [types.TextContent(
                    type="text",
                    text=f"Deep search failed: {result.stderr}"
                )]
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"Error during deep search: {str(e)}"
            )]

    async def _handle_rag_quick(self, args: Dict[str, Any], repo_root: Path) -> List[types.TextContent]:
        """Handle rag_quick tool."""
        question = args["question"]
        
        try:
            import subprocess
            result = subprocess.run([
                sys.executable, "-m", "rag.cli", "quick", 
                question
            ], cwd=repo_root, capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                return [types.TextContent(
                    type="text",
                    text=result.stdout
                )]
            else:
                return [types.TextContent(
                    type="text",
                    text=f"Quick search failed: {result.stderr}"
                )]
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"Error during quick search: {str(e)}"
            )]

    async def _handle_rag_agent_context(self, args: Dict[str, Any], repo_root: Path) -> List[types.TextContent]:
        """Handle rag_agent_context tool."""
        task = args["task"]
        mode = args.get("mode", "balanced")
        max_tokens = args.get("max_tokens", 12000)
        
        try:
            import subprocess
            # Refresh git context first
            subprocess.run([
                sys.executable, "-m", "rag.cli", "context", "git", "--refresh"
            ], cwd=repo_root, capture_output=True, timeout=10)
            
            # Get agent context
            result = subprocess.run([
                sys.executable, "-m", "rag.cli", "agent", 
                task, "--target-agent", "opencode", "--save-handoff"
            ], cwd=repo_root, capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                # Read the generated files
                task_file = repo_root / ".agent" / "task.md"
                memory_file = repo_root / ".agent" / "memory.md"
                handoff_file = repo_root / ".agent" / "handoff.md"
                
                context_data = {
                    "task_file": str(task_file),
                    "memory_file": str(memory_file),
                    "handoff_file": str(handoff_file),
                    "task_content": task_file.read_text() if task_file.exists() else "",
                    "memory_content": memory_file.read_text() if memory_file.exists() else "",
                    "handoff_content": handoff_file.read_text() if handoff_file.exists() else "",
                    "mode": mode,
                    "max_tokens": max_tokens
                }
                
                return [types.TextContent(
                    type="text",
                    text=json.dumps(context_data, indent=2)
                )]
            else:
                return [types.TextContent(
                    type="text",
                    text=f"Agent context generation failed: {result.stderr}"
                )]
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"Error generating agent context: {str(e)}"
            )]

    async def _handle_rag_task_init(self, args: Dict[str, Any], repo_root: Path) -> List[types.TextContent]:
        """Handle rag_task_init tool."""
        task_description = args["task_description"]
        
        try:
            # Ensure .agent directory exists
            agent_dir = repo_root / ".agent"
            agent_dir.mkdir(exist_ok=True)
            
            # Initialize task file
            task_file = agent_dir / "task.md"
            from datetime import datetime
            task_content = f"""# Current Task

## User Request

{task_description}

## Goal

<!-- What must be true when done -->

## Constraints

- Keep changes minimal.
- Prefer existing project patterns.
- Do not rewrite unrelated code.
- Run checks before final response.

## Relevant Context

<!-- RAG MCP writes summaries here -->

## Plan

- [ ] Understand task
- [ ] Retrieve relevant code context
- [ ] Inspect files
- [ ] Edit files
- [ ] Run checks
- [ ] Fix failures
- [ ] Update memory

## Work Log

<!-- Agent appends progress -->

## Final Summary

<!-- Agent fills at end -->

*Task initialized: {datetime.now().isoformat()}*
"""
            task_file.write_text(task_content)
            
            # Initialize other files if they don't exist
            (agent_dir / "memory.md").touch(exist_ok=True)
            (agent_dir / "decisions.md").touch(exist_ok=True)
            (agent_dir / "checks.md").touch(exist_ok=True)
            (agent_dir / "handoff.md").touch(exist_ok=True)
            
            return [types.TextContent(
                type="text",
                text=f"Task initialized successfully in {task_file}"
            )]
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"Error initializing task: {str(e)}"
            )]

    async def _handle_rag_task_status(self, args: Dict[str, Any], repo_root: Path) -> List[types.TextContent]:
        """Handle rag_task_status tool."""
        try:
            task_file = repo_root / ".agent" / "task.md"
            if task_file.exists():
                content = task_file.read_text()
                return [types.TextContent(
                    type="text",
                    text=content
                )]
            else:
                return [types.TextContent(
                    type="text",
                    text="No task initialized. Use rag_task_init to start a task."
                )]
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"Error reading task status: {str(e)}"
            )]

    async def _handle_rag_task_done(self, args: Dict[str, Any], repo_root: Path) -> List[types.TextContent]:
        """Handle rag_task_done tool."""
        summary = args.get("summary", "Task completed")
        
        try:
            agent_dir = repo_root / ".agent"
            task_file = agent_dir / "task.md"
            memory_file = agent_dir / "memory.md"
            
            if task_file.exists():
                # Read current task
                task_content = task_file.read_text()
                
                # Update task with completion
                from datetime import datetime
                completed_content = task_content.replace(
                    "<!-- Agent fills at end -->",
                    f"""## Final Summary

{summary}

*Task completed: {datetime.now().isoformat()}*
"""
                ).replace(
                    "<!-- Agent appends progress -->",
                    f"""## Work Log

<!-- Agent appends progress -->

- [{datetime.now().strftime('%Y-%m-%d %H:%M')}] Task completed: {summary}
"""
                )
                
                task_file.write_text(completed_content)
                
                # Try to extract facts for memory (simple implementation)
                # In a full implementation, this would use LLM to extract durable facts
                fact_prompt = f"""Extract any durable project facts, architecture decisions, or conventions from this task completion summary:

{summary}

Return only factual information that should be remembered for future work on this project. Format as bullet points."""
                
                try:
                    import subprocess
                    fact_result = subprocess.run([
                        sys.executable, "-m", "rag.cli", "ask", 
                        fact_prompt
                    ], cwd=repo_root, capture_output=True, text=True, timeout=30)
                    
                    if fact_result.returncode == 0 and fact_result.stdout.strip():
                        # Add to memory
                        memory_content = memory_file.read_text() if memory_file.exists() else "# Project Memory\n"
                        updated_memory = f"""{memory_content}

## Learned from Task Completion ({datetime.now().strftime('%Y-%m-%d')})

{fact_result.stdout.strip()}

"""
                        memory_file.write_text(updated_memory)
                except:
                    pass  # Fail silently on memory extraction
                
                return [types.TextContent(
                    type="text",
                    text=f"Task marked as complete. Summary updated in {task_file}"
                )]
            else:
                return [types.TextContent(
                    type="text",
                    text="No task found to complete. Use rag_task_init first."
                )]
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"Error completing task: {str(e)}"
            )]

    async def _handle_rag_memory_add(self, args: Dict[str, Any], repo_root: Path) -> List[types.TextContent]:
        """Handle rag_memory_add tool."""
        fact = args["fact"]
        scope = args.get("scope", "repo")
        confidence = args.get("confidence", "medium")
        
        try:
            agent_dir = repo_root / ".agent"
            agent_dir.mkdir(exist_ok=True)
            memory_file = agent_dir / "memory.md"
            
            from datetime import datetime
            timestamp = datetime.now().strftime('%Y-%m-%d')
            
            memory_content = ""
            if memory_file.exists():
                memory_content = memory_file.read_text()
            
            # Add fact to memory
            updated_memory = f"""{memory_content}

## Learned ({timestamp}) - [{scope}] [{confidence}]

{fact}

"""
            memory_file.write_text(updated_memory)
            
            return [types.TextContent(
                type="text",
                text=f"Fact added to project memory in {memory_file}"
            )]
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"Error adding to memory: {str(e)}"
            )]

    async def _handle_rag_memory_read(self, args: Dict[str, Any], repo_root: Path) -> List[types.TextContent]:
        """Handle rag_memory_read tool."""
        query = args.get("query", "")
        
        try:
            memory_file = repo_root / ".agent" / "memory.md"
            if memory_file.exists():
                content = memory_file.read_text()
                if query:
                    # Simple filtering - in reality would use better search
                    lines = content.split('\n')
                    filtered_lines = [line for line in lines if query.lower() in line.lower()]
                    filtered_content = '\n'.join(filtered_lines) if filtered_lines else f"*No matches found for '{query}'*"
                    return [types.TextContent(
                        type="text",
                        text=filtered_content
                    )]
                else:
                    return [types.TextContent(
                        type="text",
                        text=content
                    )]
            else:
                return [types.TextContent(
                    type="text",
                    text="# Project Memory\n\n*No project memory yet.*"
                )]
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"Error reading memory: {str(e)}"
            )]

    async def _handle_rag_checks(self, args: Dict[str, Any], repo_root: Path) -> List[types.TextContent]:
        """Handle rag_checks tool."""
        mode = args.get("mode", "fast")
        
        try:
            checks_file = repo_root / ".agent" / "checks.md"
            if checks_file.exists():
                content = checks_file.read_text()
                return [types.TextContent(
                    type="text",
                    text=content
                )]
            else:
                # Default checks
                if mode == "fast":
                    default_checks = """# Checks

## Fast

```bash
echo "Running fast checks..."
# Add your project-specific fast checks here
```
"""
                else:
                    default_checks = """# Checks

## Full

```bash
echo "Running full checks..."
# Add your project-specific full checks here
```
"""
                return [types.TextContent(
                    type="text",
                    text=default_checks
                )]
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"Error reading checks: {str(e)}"
            )]

    async def _handle_rag_repo_status(self, args: Dict[str, Any], repo_root: Path) -> List[types.TextContent]:
        """Handle rag_repo_status tool."""
        try:
            status_info = []
            
            # Git status
            try:
                git_result = subprocess.run(
                    ["git", "status", "--porcelain"],
                    cwd=repo_root,
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if git_result.returncode == 0:
                    changes = len(git_result.stdout.strip().split('\n')) if git_result.stdout.strip() else 0
                    status_info.append(f"Git: {changes} uncommitted changes")
                else:
                    status_info.append("Git: error getting status")
            except:
                status_info.append("Git: not a git repository or error")
            
            # Agent files status
            agent_dir = repo_root / ".agent"
            if agent_dir.exists():
                task_exists = (agent_dir / "task.md").exists()
                memory_exists = (agent_dir / "memory.md").exists()
                status_info.append(f"Agent: task={'✓' if task_exists else '✗'}, memory={'✓' if memory_exists else '✗'}")
            else:
                status_info.append("Agent: not initialized")
            
            # RAG status
            try:
                rag_result = subprocess.run([
                    sys.executable, "-m", "rag.cli", "doctor"
                ], cwd=repo_root, capture_output=True, text=True, timeout=10)
                if rag_result.returncode == 0:
                    status_info.append("RAG: healthy")
                else:
                    status_info.append("RAG: issues detected")
            except:
                status_info.append("RAG: status check failed")
            
            return [types.TextContent(
                type="text",
                text="Repository Status:\n- " + "\n- ".join(status_info)
            )]
        except Exception as e:
            return [types.TextContent(
                type="text",
                text=f"Error getting repo status: {str(e)}"
            )]

    async def run(self):
        """Run the MCP server."""
        async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
            await self.server.run(
                read_stream,
                write_stream,
                InitializationOptions(
                    server_name="rag-mcp",
                    server_version="0.1.0",
                    capabilities=self.server.get_capabilities(
                        notification_options=NotificationOptions(),
                        experimental_capabilities={},
                    ),
                ),
            )


def main():
    """Main entry point."""
    server = RagMcpServer()
    asyncio.run(server.run())


if __name__ == "__main__":
    main()
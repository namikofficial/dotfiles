from __future__ import annotations

import json

from .runtime import console


def run_tui() -> int:
    try:
        from textual.app import App, ComposeResult
        from textual.containers import Container
        from textual.widgets import Footer, Header, Input, Static
    except ImportError:
        console.print("[bold]RAG Local Agent[/bold]")
        console.print("Textual is not installed yet. Run `./setup/install-local-rag-stack.sh` and launch `rag` again.")
        console.print("Available now: `rag \"task\"`, `rag --plan`, `rag --context`, `rag --learn`, `rag --doctor`.")
        return 0

    from .executors import executor_matrix
    from .learning import list_memory_candidates
    from .model_registry import model_role_matrix
    from .prompt_compiler import compile_prompt
    from .retrieval import gather_context, reranker_enabled, retrieve
    from .router import build_agent_plan
    from .settings import get_mode_profile, load_config
    from .state import format_operational_state, list_sessions, load_operational_state
    from .storage import connect_db, get_qdrant

    class RagApp(App):
        TITLE = "RAG Local Agent"
        BINDINGS = [
            ("ctrl+n", "new_task", "New"),
            ("ctrl+v", "show_context", "Context"),
            ("ctrl+s", "show_sessions", "Sessions"),
            ("ctrl+m", "show_memory", "Memory"),
            ("ctrl+r", "show_review", "Review"),
            ("ctrl+t", "show_runtime", "Runtime"),
            ("ctrl+q", "quit", "Quit"),
        ]

        last_task: str = ""
        last_plan_text: str = "No task planned yet."
        last_context_text: str = "No context packed yet."
        last_review_text: str = "Submit a task to create an execution review."

        def compose(self) -> ComposeResult:
            yield Header()
            with Container(id="main"):
                yield Static("Repo-aware local RAG shell", id="status")
                yield Input(placeholder="What do you want to do?", id="task")
                yield Static(self.last_review_text, id="view")
            yield Footer()

        def _set_view(self, title: str, body: str) -> None:
            self.query_one("#status", Static).update(title)
            self.query_one("#view", Static).update(body)

        def on_input_submitted(self, event: Input.Submitted) -> None:
            task = event.value.strip()
            if not task:
                return
            self.last_task = task
            conn = connect_db()
            plan = build_agent_plan(task, conn=conn)
            config = get_mode_profile(load_config(), plan.mode)
            context = ""
            try:
                result = retrieve(
                    conn,
                    get_qdrant(config),
                    config,
                    plan.task,
                    plan.repo if plan.repo != "unscoped" else None,
                    reranker_enabled(config, None),
                    mode=plan.mode,
                )
                state_text = format_operational_state(load_operational_state(conn, plan.repo))
                context, files = gather_context(
                    result.rows,
                    config,
                    facts=result.facts,
                    summaries=result.summaries,
                    context_sources=result.context_sources,
                    memory=result.memory["summary"] if plan.context.include_memory and result.memory else None,
                    operational_state=state_text,
                    operational_state_tokens=int(config["answer"]["operational_state_tokens"]),
                )
            except Exception as exc:
                files = []
                context = f"Context retrieval failed: {exc}"
            prompt = compile_prompt(plan, context)
            self.last_plan_text = json.dumps(plan.to_dict(), indent=2)
            self.last_context_text = context
            self.last_review_text = "\n".join(
                [
                    "Execution Review",
                    f"Profile: {plan.profile} ({plan.confidence:.2f})",
                    f"Mode: {plan.mode}",
                    f"Target: {plan.target}",
                    f"Intent: {plan.intent}",
                    f"Risk: {plan.risk_level} destructive={plan.destructive_risk}",
                    f"Repo: {plan.repo}",
                    f"Tokens: {prompt.token_count}",
                    f"Context: {prompt.context_summary}",
                    "Likely files:",
                    *[f"- {item}" for item in (plan.likely_files or files[:8])],
                    "",
                    "Route:",
                    plan.route_reason,
                ]
            )
            self._set_view("Execution Review", self.last_review_text)

        def action_new_task(self) -> None:
            self.query_one("#task", Input).value = ""
            self.query_one("#task", Input).focus()

        def action_show_context(self) -> None:
            self._set_view("Context Viewer", self.last_context_text)

        def action_show_review(self) -> None:
            self._set_view("Execution Review", self.last_review_text)

        def action_show_sessions(self) -> None:
            conn = connect_db()
            rows = list_sessions(conn, repo=None, limit=12)
            body = "\n".join(
                f"{row['session_id']}  {row['mode']}  {row['repo'] or '-'}  {row['query'][:72]}"
                for row in rows
            ) or "No sessions saved yet."
            self._set_view("Sessions", body)

        def action_show_memory(self) -> None:
            conn = connect_db()
            rows = list_memory_candidates(conn, status="pending", limit=12)
            body = "\n".join(
                f"{row['id']}  {row['kind']}  {row['confidence']:.2f}  {row['content'][:90]}"
                for row in rows
            ) or "No pending memory candidates."
            self._set_view("Memory Inbox", body)

        def action_show_runtime(self) -> None:
            executor_lines = [
                f"executor:{name} {'ok' if ok else 'warn'} - {reason}"
                for name, ok, reason in executor_matrix()
            ]
            model_lines = [
                f"model:{name} {'ok' if ok else 'warn'} - {reason}"
                for name, ok, reason in model_role_matrix()
            ]
            self._set_view("Model Runtime", "\n".join([*executor_lines, "", *model_lines]))

    RagApp().run()
    return 0

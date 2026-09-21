# OpenCode session telemetry specification

Status: initial implementation

Telemetry exists to compare completed-task efficiency and quality. It must not
retain prompts, source dumps, secrets, cookies, auth headers, or arbitrary MCP
responses.

Record per session:

- pseudonymous session ID and project class;
- profile, agent, model, start/end time, and outcome;
- input/cached-input/output/reasoning token fields when the provider exposes them;
- tool-call count, bytes returned, bytes avoided, sandboxed bytes, and compactions;
- child-session count and verification result (`PASS`, `PARTIAL`, `BLOCKED`, or `FAIL`).

The report is normalized per completed task, not per session. A failed short
session followed by a restart is not an efficiency win. Retain aggregate JSON
and Markdown only; make raw session retention opt-in and time-limited.

The agent-lab benchmark must compare identical scenarios before and after a
configuration change and report both context cost and quality gates.

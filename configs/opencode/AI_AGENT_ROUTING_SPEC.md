# AI agent routing specification

Status: initial implementation

The canonical config is `opencode.local-llamacpp.json`; this document defines
how to choose a configured agent without loading every capability into every
task.

| Task | Agent | Profile | Delegation | Proof |
| --- | --- | --- | --- | --- |
| Small repository question | `ask` | base | none | cited paths |
| Read-only map | `explore` | base + CodeGraph when needed | none | entry points/callers |
| Plan | `plan` | base | none | acceptance, risks, checks |
| Focused implementation | `build` or `worker` | base | one bounded child only | focused verification |
| Independent review | `review` | base | none | severity/path findings |
| Web runtime | `web-verifier` | web | none | browser/runtime evidence |
| Android/device | `android-verifier` | mobile | none | device-gated evidence |
| UI/design | `ui-specialist` | design | none by default | rendered/accessibility evidence |

Rules:

- One primary agent owns integration, diff review, and the final verdict.
- Use a child only for independent, read-heavy work with a concise return contract.
- Maximum two children and depth one unless the user explicitly approves an exception.
- Step ceilings are safety limits, not targets. Stop when the acceptance criteria are proven.
- Escalate model or step budget only after recording why the current route is insufficient.
- Child output must include scope, files read, findings, verification, uncertainty, and stop reason.

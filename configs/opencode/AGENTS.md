# OpenCode configuration guidance

`opencode.local-llamacpp.json` is the canonical strict-JSON config and is
linked to `~/.config/opencode/opencode.json` by `setup/normalize-links.sh`.
MiniMax M2.7 is the normal model for primary, planning, exploration,
implementation, and review paths. M3 and GPT-5.6 Luna are explicit escalation
models; keep the other configured MiniMax models and the Terra catalog entry.

MCP tools and skills are denied globally to keep ordinary turns small. Enable
only the server or skill needed by the relevant specialist agent. Keep quota
and TUI sidecar files under version control and link them from
`setup/normalize-links.sh`.

Validate configuration changes with:

```sh
jq empty configs/opencode/opencode.local-llamacpp.json
./setup/test-ai-config.sh
git diff --check
```

Do not commit, push, install credentials, or apply user-level changes without
an explicit request. Package plugins are pinned in the canonical config when
reproducibility matters; runtime authentication remains user-owned.

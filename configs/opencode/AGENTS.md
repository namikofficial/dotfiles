# OpenCode configuration guidance

`opencode.local-llamacpp.json` is the canonical strict-JSON config and is
linked to `~/.config/opencode/opencode.json` by `setup/normalize-links.sh`.
MiniMax M2.7 is the normal model for primary, planning, exploration,
implementation, and review paths. M3 and GPT-5.6 Luna are explicit escalation
models; keep the other configured MiniMax models and the Terra catalog entry.

Configured MCP servers and skills are available globally; select only the
server or skill needed for a task. The current permission profile allows
configured tools, including shell, so prompts must keep destructive actions
and credential changes under explicit user control. OpenCode v2 uses `cli.json`
for TUI preferences and discovers managed CLI plugins from
`~/.config/opencode/plugins`. The quota adapter is pinned to the tested
community v2 port and installed under user state by
`setup/install-opencode-quota-v2.sh`.

Validate configuration changes with:

```sh
jq empty configs/opencode/opencode.local-llamacpp.json
./setup/test-ai-config.sh
git diff --check
```

Do not commit, push, or alter credentials. Runtime authentication remains
user-owned.

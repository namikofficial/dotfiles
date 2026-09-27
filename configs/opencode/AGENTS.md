# OpenCode configuration guidance

`opencode.local-llamacpp.json` is canonical and is linked to
`~/.config/opencode/opencode.json`. OpenCode 2.0.11 migrates this installed
schema to V2 internally. Use the redacted path-only config check below for
source loading and the filtered resolved-agent check below for roles and
permission order; raw config debug output can contain MCP headers.

Keep the harness direct:

- primary modes: `build` and read-only `plan`, both on MiniMax M2.7;
- explorers: `explore-m2.7` for harder investigation and cheaper
  `explore-m2.5` for straightforward search/mapping;
- implementation children: `worker-m2.7`, `worker-m3`, and `worker-luna`;
- build has all configured tools; build, plan, and workers see all installed
  skills;
- depth one; workers cannot launch children;
- `tmux-tools` uses the system `nox` socket and shares the `nox` session;
  killing that shared session is refused;
- CodeGraph remains the default semantic navigation MCP.
- v0 uses OpenCode's remote OAuth flow; `vp0` provides the VP0 mobile design
  library through its local MCP package.
- Native mobile UI tasks should use the installed `building-native-ui` and
  `mobile-design` skills, with `anti-ui-slop` and `emil-design-eng` as useful
  design/review companions.
- The browser MCP attaches to the active Chrome profile; Chrome 144+ remote
  debugging must be enabled and the connection may require approval.

Prompts are task contracts, not personality prose. A worker needs a goal,
paths, required behavior, non-goals, one validation command, and a short return
schema. The primary `build` agent can spawn a named explorer or worker without
leaving the session; use one only when its model/cost tradeoff is intentional.

Validate changes with:

```sh
jq empty configs/opencode/opencode.local-llamacpp.json
./setup/test-ai-config.sh
opencode debug config | jq -r '.[].path'
opencode debug config | jq -r '.[0].info.agents | keys[]'
git diff --check
```

Config changes are watched automatically. Restart the OpenCode service only
when a local plugin change does not reload: `opencode service restart`.

Authenticate v0 with `opencode mcp auth v0`. Browser MCP uses the active Chrome
profile via `--autoConnect`; enable remote debugging in
`chrome://inspect/#remote-debugging` before connecting. The agent can access
that profile's open tabs and session data.

Do not commit, push, or alter credentials. Authentication remains user-owned;
sensitive-path read denies remain in force even though build has all tools.

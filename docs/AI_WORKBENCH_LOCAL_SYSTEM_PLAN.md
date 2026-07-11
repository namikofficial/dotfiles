# Local AI Workbench + Noxflow Integration Plan

Status: living implementation checklist  
Created: 2026-07-11  
Canonical application: `/home/namik/Documents/code/ai`  
Workstation integration: `/home/namik/Documents/code/dotfiles`

## 0. Decision

The TypeScript AI Workbench becomes the application, retrieval product, web UI, CLI, MCP server, and agent runtime. The dotfiles repository remains the workstation integration layer: Hyprland keybinds, launchers, scratchpads, model runtime, OpenCode/Codex configuration, packages, systemd, health checks, and desktop UX.

The Python RAG in `dotfiles/system/rag` is a compatibility layer during migration, not the final product. Do not delete it until the Workbench has equivalent indexing, retrieval, memory, handoff, MCP, and task-workflow coverage.

Target flow:

~~~text
Hyprland / launcher / CLI / OpenCode / browser
                    |
          AI Workbench Web + API + MCP
                    |
       SQLite source of truth + optional Qdrant
                    |
       llama.cpp/llama-swap local model endpoint
                    |
           local models and embeddings
~~~

## 1. Current-state assessment

### AI Workbench already provides

- [x] TypeScript monorepo with pnpm workspaces.
- [x] React/Vite dashboard in `apps/web`.
- [x] API in `apps/api`, worker in `apps/worker`, CLI in `cli/ai`, MCP in `mcp/server`.
- [x] SQLite migrations and repositories in `packages/db`.
- [x] Optional Qdrant with SQLite FTS fallback.
- [x] Hybrid retrieval, code intelligence, symbols, context packs, prompt compilation, model calls, sessions, traces, memory, evaluations, and feedback.
- [x] Local model runtime abstraction and cloud-disabled-by-default intent.
- [x] Safe dev-agent/execution-engine direction with isolated workspaces, checks, diffs, and approval.
- [x] Broad tests covering retrieval, API, MCP, safety, model fallback, migrations, workers, UI wiring, and agent flows.

### Dotfiles already provides

- [x] Hyprland scratchpads, workspace/project workflow, Rofi actions, Kitty, Wayle, notifications.
- [x] llama.cpp/llama-swap install and manager scripts.
- [x] OpenCode local-provider configuration.
- [x] Open WebUI compose setup and RAG MCP bridge.
- [x] `dev-health`, `local-ai-runtime`, project profiles, project resume, and recovery tooling.
- [x] Existing Python RAG/MCP/indexing/memory/task code that is useful as migration reference.

### Gaps found

- [ ] Model docs, aliases, and GGUF filenames disagree. Some docs describe Qwen2.5-Coder or `local`; the llama-swap template defines several Qwen3/Gemma/Phi/DeepSeek filenames and aliases.
- [ ] Install scripts install binaries but do not reliably download and verify every referenced model.
- [ ] Missing GGUF files are filtered from generated config, which can hide the real cause of a routing failure.
- [ ] Runtime startup is tmux/shell based rather than a supervised user service.
- [ ] Workbench `.env.example` suggests a chat model as an embedding model; embedding ownership and dimensions must be explicit.
- [ ] Watcher mode, Tree-sitter path, MCP host mode, terminal mode, and a separate Prompt Lab surface are incomplete or not fully exposed.
- [ ] Hyprland still launches the old local chat/RAG workflow instead of the Workbench.
- [ ] There is no single health command covering API, worker, database, Qdrant, models, embeddings, MCP, and index freshness.
- [ ] There is no one-command project onboarding flow.
- [ ] The web UI has useful pages but needs task-first information architecture, recovery states, keyboard navigation, responsive layout, and clearer status semantics.
- [ ] Backup/restore and runtime-secret policy need to be explicit.

## 2. Ownership and data boundaries

| Concern | Final owner | Compatibility period |
|---|---|---|
| Web cockpit | Workbench `apps/web` | Old terminal fallback |
| API and mutations | Workbench `apps/api` | Python commands read-only |
| Indexing/retrieval | Workbench `packages/indexer`, `packages/retrieval-engine` | Python comparison runner |
| State | Workbench `packages/db` | Separate Python DB backup |
| Vectors | Workbench Qdrant collection | Rebuild rather than share blindly |
| Inference | llama.cpp through llama-swap | OpenAI-compatible `127.0.0.1:8080/v1` |
| Model routing | Workbench profiles + llama-swap aliases | Dotfiles status/start/stop |
| Agent execution | Workbench execution engine | OpenCode manual fallback |
| MCP | Workbench MCP server | Python `rag-mcp` fallback |
| Desktop integration | Dotfiles Hyprland/Rofi/Kitty/Wayle | Browser deep links |

- [ ] Choose one Workbench DB location, preferably `/home/namik/Documents/code/ai/runtime/ai.db` during development and a documented XDG path for installed use.
- [ ] Use a separate Qdrant collection such as `ai_workbench_chunks`.
- [ ] Add schema/version, source project, relative path, commit hash, content hash, language, symbol, provider, and dimension to indexed records.
- [ ] Never let Python and Workbench write the same DB concurrently.
- [ ] Keep runtime data, logs, model files, and secrets out of Git.

## 3. Phase 0: baseline and backup

- [ ] Preserve both dirty worktrees before making changes.
- [ ] Record hardware and versions:

~~~bash
uname -a
cat /etc/os-release
nvidia-smi || true
llama-server --version || true
llama-server --list-devices || true
node --version
pnpm --version
docker --version
docker compose version
~~~

- [ ] Record capacity:

~~~bash
df -h "$HOME"
nvidia-smi --query-gpu=name,memory.total,memory.free,driver_version --format=csv || true
du -sh "$HOME/llama-models" "$HOME/ai-rag" 2>/dev/null || true
~~~

- [ ] Back up current runtime state:

~~~bash
mkdir -p "$HOME/ai-backups/pre-workbench"
cp -a "$HOME/ai-rag" "$HOME/ai-backups/pre-workbench/" 2>/dev/null || true
cp -a "$HOME/.config/llama-swap" "$HOME/ai-backups/pre-workbench/" 2>/dev/null || true
cp -a "$HOME/.config/open-webui" "$HOME/ai-backups/pre-workbench/" 2>/dev/null || true
~~~

- [ ] Decide GPU memory budget, context length, latency target, model storage disk, and whether browser access is localhost-only. Recommended: localhost-only.

## 4. Phase 1: install local models and runtime

### 4.1 Install packages and links

Run as the normal user:

~~~bash
cd /home/namik/Documents/code/dotfiles
./setup/bootstrap.sh --install-packages --with-aur
./setup/install-local-llm-stack.sh
~~~

If NVIDIA/CUDA should be managed by the repo:

~~~bash
./setup/bootstrap.sh --install-packages --with-aur --with-nvidia
~~~

Verify:

~~~bash
command -v llama-server
command -v llama-swap
command -v llama-swap-manager
llama-server --list-devices
nvidia-smi
~~~

- [ ] If `yay` is absent, install it according to the workstation package policy before the AUR step.
- [ ] Do not mix AUR helpers while debugging a transaction.
- [ ] Confirm CUDA is visible before downloading large models.

### 4.2 Download and verify GGUF files

~~~bash
mkdir -p "$HOME/llama-models"
cd /home/namik/Documents/code/dotfiles
./system/model-downloader.sh qwen-coder-7b
./system/model-downloader.sh gemma-3-4b
find "$HOME/llama-models" -maxdepth 1 -type f -name '*.gguf' -printf '%f %s bytes\n' | sort
~~~

For other models:

~~~bash
python -m pip install --user --upgrade huggingface_hub
hf auth login
~~~

Download a specific GGUF into `~/llama-models` only after accepting its license. Never put HF tokens in tracked files.

- [ ] Select one fast model, one coding model, one deep/reasoning model, and one embedding provider.
- [ ] Make every filename in `system/llama-swap/config.template.yaml` match a real file, or remove that model block.
- [ ] Make `local` explicitly point to the daily fast model.
- [ ] Make `qwen-coder-7b` the coding/editing profile if available.
- [ ] Add a catalog check comparing Workbench profile id, llama-swap alias, GGUF filename, exposed `/v1/models` id, and task role.

### 4.3 Start and test inference

~~~bash
cd /home/namik/Documents/code/dotfiles
llama-swap-manager start
llama-swap-manager status
curl -fsS http://127.0.0.1:8080/v1/models | jq
llama-swap-manager test
local-ai-runtime status
~~~

- [ ] Chat completion works.
- [ ] Intended GPU is used during a request.
- [ ] Model switching works.
- [ ] Missing files produce a clear error.
- [ ] Stop/start leaves no orphaned process or stale port.
- [ ] Logs identify model, port, load time, and failure cause.

### 4.4 Replace tmux-only supervision

The current manager is useful for diagnostics, but daily use needs a user service.

- [ ] Add `foreground` mode to `system/llama-swap-manager.sh`.
- [ ] Add `systemd/user/ai-llama-swap.service` to dotfiles:

~~~ini
[Unit]
Description=Local llama-swap inference router
After=default.target

[Service]
Type=simple
ExecStart=%h/.local/bin/llama-swap-manager foreground
Restart=on-failure
RestartSec=5
Environment=LLAMA_MODEL_ROOT=%h/llama-models
Environment=LLAMA_SWAP_PORT=8080

[Install]
WantedBy=default.target
~~~

- [ ] Add opt-in setup: `systemctl --user enable --now ai-llama-swap.service`.
- [ ] Update `local-ai-runtime` to prefer systemd and fall back to the manager.
- [ ] Add readiness polling, journal diagnostics, and an opt-in auto-start policy.
- [ ] Keep large-model loading out of login startup unless explicitly enabled.

## 5. Phase 2: install the AI Workbench

### 5.1 Prerequisites

~~~bash
node --version
corepack enable
corepack prepare pnpm@10.33.2 --activate
pnpm --version
~~~

- [ ] Node is new enough for the project’s direct TypeScript execution.
- [ ] Use the workstation’s preferred version manager/package policy if Node is old.

### 5.2 Install, test, and configure

~~~bash
cd /home/namik/Documents/code/ai
pnpm install
pnpm typecheck
pnpm test
pnpm lint
cp -n .env.example .env
mkdir -p runtime
~~~

Fast test path without live models:

~~~bash
AI_LOCAL_BASE_URL=http://127.0.0.1:1 AI_LOCAL_EMBEDDING_DIM=32 pnpm test:fast
~~~

Minimum local `.env` values:

~~~dotenv
AI_CLOUD_ENABLED=false
AI_API_PORT=4242
AI_WEB_PORT=3000
AI_API_URL=http://127.0.0.1:4242
AI_LOCAL_BASE_URL=http://127.0.0.1:8080/v1
AI_QDRANT_ENABLED=true
AI_QDRANT_URL=http://127.0.0.1:6333
AI_QDRANT_COLLECTION=ai_workbench_chunks
AI_DATABASE_PATH=./runtime/ai.db
AI_RUNTIME_DIR=./runtime
~~~

- [ ] Set model roles only to ids confirmed by `curl .../v1/models`.
- [ ] Do not use a chat model as an embedding model by assumption.
- [ ] Choose either a real embedding endpoint or a local embedding library/provider and document its dimension.
- [ ] Add a startup validation that rejects a dimension/provider mismatch.

### 5.3 Optional Qdrant

~~~bash
cd /home/namik/Documents/code/ai
docker compose --profile optional up -d qdrant
curl -fsS http://127.0.0.1:6333/collections | jq
~~~

If Docker is unavailable:

~~~bash
AI_QDRANT_ENABLED=false
~~~

- [ ] SQLite FTS retrieval remains fully usable when Qdrant is down.
- [ ] Qdrant schema/collection version is checked before indexing.
- [ ] Indexing reports progress and can resume after interruption.

### 5.4 Start and verify the Workbench

~~~bash
cd /home/namik/Documents/code/ai
pnpm dev
~~~

Open `http://127.0.0.1:3000`. In another terminal:

~~~bash
curl -fsS http://127.0.0.1:4242/health | jq
curl -fsS http://127.0.0.1:4242/status | jq
~~~

Separate debug processes:

~~~bash
pnpm cli -- api --port 4242
pnpm cli -- web --port 3000 --api-port 4242
pnpm cli -- worker
~~~

## 6. Phase 3: onboard both repositories

~~~bash
cd /home/namik/Documents/code/ai
pnpm cli -- project add /home/namik/Documents/code/dotfiles --name dotfiles
pnpm cli -- project add /home/namik/Documents/code/ai --name ai-workbench
pnpm cli -- project index dotfiles
pnpm cli -- project index ai-workbench
pnpm cli -- project graph dotfiles
pnpm cli -- project symbols dotfiles --query local-ai
pnpm cli -- config init --project dotfiles
pnpm cli -- config init --project ai-workbench
pnpm cli -- config validate --project dotfiles
pnpm cli -- config validate --project ai-workbench
~~~

- [ ] Add ignores for `.git`, `node_modules`, build output, coverage, caches, model files, runtime DBs, logs, and secrets.
- [ ] Add project-specific include/boost paths.
- [ ] Detect safe checks: typecheck, lint, test, build, cargo check, or pytest.
- [ ] Add one-command onboarding:

~~~bash
ai project bootstrap /home/namik/Documents/code/my-project --name my-project
~~~

It should register, detect stack, preview/write config, detect checks, index, run a smoke query, and provide a project deep link.

## 7. Phase 4: replace the Python RAG safely

### Capability map

| Python surface | Workbench destination |
|---|---|
| `rag index` | `project index` plus worker |
| `rag search` | retrieval API/CLI |
| `rag ask` | Ask workflow with citations |
| `rag quick/deep` | depth/model profile selector |
| `rag facts` | code intelligence/project graph |
| `rag memory` | memory repositories and UI |
| `rag handoff` | Handoff page/API/CLI |
| `rag task` | Planner/dev-run workflow |
| `rag context git` | project context service |
| `rag-mcp` | TypeScript MCP server |

### Compatibility period

- [ ] Add a documented legacy status command.
- [ ] Make Python RAG read-only by default.
- [ ] Add a comparison runner for identical queries: result overlap, latency, citation coverage, and answer grounding.
- [ ] Port real Python retrieval fixtures into TypeScript evaluation fixtures.
- [ ] Freeze Python feature work except migration fixes.
- [ ] Use the Workbench for normal work for at least two weeks before removal.

### Retrieval parity and improvements

- [ ] Exact path/symbol lookup before semantic search.
- [ ] SQLite FTS fallback when Qdrant is unavailable.
- [ ] Query rewrite and retrieval explanation traces.
- [ ] Line-range citations and source preview.
- [ ] Current branch, changed-file, and project-path boosts.
- [ ] Stale-index warning and visible reindex action.
- [ ] Feedback: wrong file, missing file, useful.
- [ ] Eval command reporting recall@k, MRR, citation coverage, grounding, and latency.
- [ ] Durable memory with scope, provenance, conflict detection, promotion, and deletion.

### Cutover gate

Do not remove Python until:

- [ ] Both repos index from a clean Workbench runtime.
- [ ] Ask, search, handoff, memory, and task workflows work without Python.
- [ ] OpenCode/MCP use the TypeScript server.
- [ ] Desktop launchers reach the Workbench.
- [ ] Retrieval baseline passes.
- [ ] Backup, rollback, and export are tested.
- [ ] No active script depends on Python RAG.

Then archive in a separate, reversible change:

~~~bash
cd /home/namik/Documents/code/dotfiles
mv system/rag system/rag-legacy
mv system/rag-mcp.sh system/rag-mcp-legacy.sh
~~~

## 8. Phase 5: UI/UX for daily use

The current UI has breadth but feels like an internal admin console. Make it answer “Can I work?” and “What should I do next?” immediately.

### Information architecture

Primary navigation:

1. Home
2. Projects
3. Work
4. Ask
5. Runs
6. Knowledge
7. System

Group Planner, Handoff, Checks, Dev Runs, and Reviews under Work. Group Retrieval, Memory, Skills, Prompt Lab, and Eval under Knowledge. Group Models, MCP, Settings, and Logs under System.

- [ ] Preserve existing direct URLs.
- [ ] Add breadcrumbs and back navigation.
- [ ] Persist selected project.
- [ ] Put project, local/cloud mode, model, and runtime status in the top bar.
- [ ] Add `Ctrl/Cmd+K`, `Esc`, keyboard focus, and command search.

### Home

- [ ] API, worker, model, Qdrant, database, MCP status cards.
- [ ] Current project and index freshness.
- [ ] Resume last unfinished run.
- [ ] Start Ask, Plan, and Dev Run buttons.
- [ ] Failed checks with retry/details.
- [ ] Recent changes and recent lessons.
- [ ] Setup checklist when something is missing.

### Ask

- [ ] Large composer with project, depth, model, and local-only controls.
- [ ] Stable streaming skeleton and cancel action.
- [ ] Inline citations expandable to exact lines.
- [ ] Retrieval drawer: rewrite, sources, scores, misses, and why selected.
- [ ] Actions: use as plan, save memory, open source.
- [ ] Useful no-context state with reindex/retry instructions.

### Dev runs

- [ ] Wizard: goal → project → plan → checks → risk → start.
- [ ] Timeline: context, plan, edits, checks, repairs, approval.
- [ ] Diff-first review with file tree and inline changes.
- [ ] Risk badges for secrets, auth, DB, migrations, packages, and lockfiles.
- [ ] Clear distinction between cancel and approve/apply.
- [ ] Exact commands, stdout, stderr, exit codes, and duration.
- [ ] Browser-refresh resume and clear blocked-action recovery.

### UI quality

- [ ] Design tokens for spacing, typography, status colors, borders, radii, and elevation.
- [ ] Consistent statuses: healthy, ready, running, waiting, stale, blocked, failed, disabled.
- [ ] Useful empty/loading/error states on every page.
- [ ] No raw JSON as the primary view; keep it in expandable diagnostics.
- [ ] Keyboard focus, labels, contrast, reduced motion, and 200% zoom.
- [ ] Responsive layout for laptop and narrow windows.
- [ ] Notifications for indexing complete, model ready, failed checks, and approval required.

### Desktop integration

- [ ] Hyprland action opens Workbench home.
- [ ] Project action opens selected project.
- [ ] Clipboard action opens Ask with clipboard text.
- [ ] Resume action opens the last run.
- [ ] Model picker shows role, readiness, and current model.
- [ ] Legacy RAG labels are replaced only after cutover.
- [ ] Terminal fallback remains available when API/browser is down.

## 9. Phase 6: MCP, OpenCode, and Open WebUI

### Workbench MCP

- [ ] Make TypeScript MCP canonical.
- [ ] Start read-only: status, search, symbols, ask, retrieval explanation, memory, trace.
- [ ] Add mutations only through explicit approval contracts.
- [ ] Add timeouts, structured errors, redaction, and project-root scoping.
- [ ] Test:

~~~bash
cd /home/namik/Documents/code/ai
pnpm cli -- mcp
~~~

- [ ] Add smoke tests for initialize, list tools, read-only search, and rejected unsafe mutation.
- [ ] Update `configs/opencode/opencode.local-llamacpp.json` to use Workbench MCP.
- [ ] Keep filesystem/git tools scoped to the active project.

### Open WebUI

Recommended role: general local chat/model experimentation. The Workbench owns repo-grounded engineering work.

~~~bash
cd /home/namik/Documents/code/dotfiles
./setup/install-open-webui-stack.sh
cd "$HOME/.config/open-webui"
docker compose --env-file .env up -d
docker compose ps
cd /home/namik/Documents/code/dotfiles
./setup/test-open-webui-stack.sh
~~~

Open `http://127.0.0.1:3080`.

- [ ] Confirm container access to `http://host.docker.internal:8080/v1`.
- [ ] Confirm model list and chat.
- [ ] Confirm RAG bridge or deliberately disable it.
- [ ] Avoid maintaining two competing project-memory systems.
- [ ] Document what belongs in Open WebUI, Workbench, and OpenCode.

## 10. Reliability, security, and operations

Implement:

~~~bash
ai-workbench health
ai-workbench health --deep
ai-workbench health --json
~~~

Checks:

- [ ] Node/pnpm versions.
- [ ] API/web/worker reachability and version.
- [ ] SQLite migrations, write test, free disk.
- [ ] Qdrant reachability and collection schema.
- [ ] Model ids, readiness, and latency.
- [ ] Embedding provider/dimension.
- [ ] Index freshness and failed jobs.
- [ ] MCP startup.
- [ ] OpenCode config.
- [ ] Redacted paths/secrets.

- [ ] Structured logs with request/session/run ids.
- [ ] Redact keys, tokens, cookies, environment values, and sensitive paths.
- [ ] Add log rotation and retention.
- [ ] Add diagnostics export without secrets.
- [ ] Back up Workbench SQLite, project config, memory, skills, prompts, and eval fixtures.
- [ ] Treat Qdrant as rebuildable unless rebuild time justifies backup.
- [ ] Do not snapshot GGUF files frequently unless explicitly desired.
- [ ] Test restore in the weekly health check.

Manual backup:

~~~bash
mkdir -p "$HOME/ai-backups/$(date +%F)"
cp -a /home/namik/Documents/code/ai/runtime/ai.db "$HOME/ai-backups/$(date +%F)/"
cp -a /home/namik/Documents/code/ai/.env "$HOME/ai-backups/$(date +%F)/" 2>/dev/null || true
~~~

## 11. Acceptance gates

### Local model

- [ ] `llama-server --list-devices` sees the intended accelerator.
- [ ] `/v1/models` responds with expected ids.
- [ ] Chat completion and model switch work.
- [ ] Stop/start has no leaked processes or stale port.
- [ ] Logs clearly identify missing files and load failures.

### Workbench core

- [ ] `pnpm typecheck`, `pnpm test`, and `pnpm lint` pass.
- [ ] API health/status pass.
- [ ] Web loads and explains API-offline recovery.
- [ ] Worker indexing completes.

### Retrieval

- [ ] SQLite-only retrieval works.
- [ ] Qdrant retrieval works.
- [ ] Qdrant outage falls back.
- [ ] Exact symbols/paths work.
- [ ] Answers cite source files/lines.
- [ ] Retrieval trace is inspectable.

### Workflow

- [ ] CLI and UI onboard projects.
- [ ] Ask → plan → dev run works.
- [ ] Dev run creates an isolated diff.
- [ ] Checks are allowlisted and recorded.
- [ ] Approval applies only the intended diff.
- [ ] MCP read-only tools work.
- [ ] Desktop shortcuts reach the same project/session.

## 12. Recommended implementation order

1. [ ] Fix model filenames, aliases, readiness, and diagnostics.
2. [ ] Make Workbench dependencies, typecheck, tests, and lint green.
3. [ ] Make API, worker, CLI, and web start reliably.
4. [ ] Add health and project onboarding.
5. [ ] Index dotfiles and Workbench with TypeScript retrieval.
6. [ ] Make Ask with citations better than Python RAG.
7. [ ] Improve Home, Ask, and Dev Run UX.
8. [ ] Port memory, handoff, task graph, and eval comparison.
9. [ ] Make TypeScript MCP canonical.
10. [ ] Integrate Hyprland launchers and notifications.
11. [ ] Complete safe dev-run approval loop.
12. [ ] Add systemd supervision and backup/restore.
13. [ ] Run compatibility period and compare outcomes.
14. [ ] Archive/remove Python only after the cutover gate.

## 13. First-session command sequence

~~~bash
# Workstation/runtime
cd /home/namik/Documents/code/dotfiles
./setup/bootstrap.sh --install-packages --with-aur
./setup/install-local-llm-stack.sh
mkdir -p "$HOME/llama-models"

# Put at least one verified GGUF in ~/llama-models, then:
llama-swap-manager start
curl -fsS http://127.0.0.1:8080/v1/models | jq -r '.data[].id'
llama-swap-manager test

# Workbench
cd /home/namik/Documents/code/ai
corepack enable
corepack prepare pnpm@10.33.2 --activate
pnpm install
cp -n .env.example .env
pnpm typecheck
pnpm test

# Optional vector store
docker compose --profile optional up -d qdrant

# Start Workbench
pnpm dev
~~~

In another terminal:

~~~bash
cd /home/namik/Documents/code/ai
pnpm cli -- project add /home/namik/Documents/code/dotfiles --name dotfiles
pnpm cli -- project add /home/namik/Documents/code/ai --name ai-workbench
pnpm cli -- project index dotfiles
pnpm cli -- project index ai-workbench
pnpm cli -- ask "How should the local AI workflow be launched from Hyprland?" --project dotfiles --depth deep
~~~

## 14. Definition of regular-workflow ready

- [ ] One command reports whether the system is healthy.
- [ ] One cockpit shows project, model, retrieval, run, and check state.
- [ ] CLI works when browser is unavailable.
- [ ] Local models start predictably and report missing files clearly.
- [ ] Indexing is incremental and visibly fresh.
- [ ] Answers cite real files and explain source selection.
- [ ] Plans and coding runs are reviewable before touching the original repo.
- [ ] Failed checks become searchable feedback.
- [ ] Hyprland shortcuts open the same Workbench state, not a parallel legacy system.
- [ ] OpenCode/MCP, CLI, web, and desktop share one API/data model.
- [ ] Backup, restore, rollback, and recovery are tested.
- [ ] Python RAG can be stopped without breaking normal work.


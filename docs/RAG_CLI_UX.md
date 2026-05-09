# RAG CLI UX guide

This guide covers the human-facing CLI surfaces for `rag`: completion, command suggestions, workflow discovery, and the full command map.

## Install completion

```bash
cd ~/Documents/code/dotfiles
./setup/install-local-rag-stack.sh
exec zsh
```

The installer links:

- `~/.local/bin/rag` -> `system/rag.sh`
- `~/.local/share/zsh/site-functions/_rag` -> `system/completions/_rag`

`zshrc` adds `~/.local/share/zsh/site-functions` to `fpath` before `compinit`, so zsh loads `_rag` like a normal native completion.

## Completion behavior

Completion covers:

- Top-level commands: `ask`, `quick`, `deep`, `agent`, `search`, `memory`, `context`, `facts`, `trace`, and the rest of the command map.
- Common flags: `--repo`, `--memory`, `--show-context`, `--rerank`, `--no-rerank`, `--profile`, `--mode`, `--target-agent`.
- Nested commands: `rag memory ...`, `rag context ...`, `rag todo ...`, `rag session ...`.
- Static enums: modes, profiles, target agents, memory kinds, statuses, scopes, output formats, fact kinds.
- Dynamic values when SQLite is available:
  - indexed repos for `--repo`
  - saved session ids for `rag session show`
  - todo ids for `rag todo done` and `rag todo start`

If dynamic state is empty, completion stays quiet and falls back to normal command or file completion where appropriate.

## Suggestions

Mistyped commands now get parser-level hints:

```bash
rag serach auth
```

prints the normal argparse error plus:

```text
Did you mean: search
```

Use `rag suggest` for workflow discovery:

```bash
rag suggest
rag suggest setup
rag suggest debug
rag suggest memory
rag suggest handoff
```

The suggestion topics are:

- `setup`: install, doctor, index, status
- `ask`: quick/deep/auto routed answers
- `debug`: search, inspect, missing-context, why
- `trace`: facts, trace, graph
- `state`: git, GitHub, test failures, todos
- `memory`: summarize, memory status, notes, packs
- `handoff`: agent packets and saved sessions

## Command Map

### Setup and Indexing

```bash
rag doctor
rag doctor --deep
rag index
rag index ~/Documents/code/dotfiles --profile balanced
rag index --profile fast
rag index --changed-only
rag reindex
rag reindex --profile deep
rag status
```

Use `doctor --deep` when the stack itself may be broken. Use `status` when you want counts and current settings.

`rag index` and `rag reindex` show live progress while they run:

- processed files / total files
- percent complete
- elapsed time
- estimated time remaining
- changed files
- skipped files
- indexed chunks
- current file
- current file-processing rate

If you cancel with `Ctrl+C`, the command reports elapsed time, completed files, completed chunks, and processed file count. Resume with:

```bash
rag index --changed-only
```

The indexer prunes dependency/cache trees before walking them, including `node_modules`, Python virtualenvs, `site-packages`, `__pycache__`, `.tox`, `.nox`, `.gradle`, `target`, `vendor`, and coverage output.

### Ask and Answer

```bash
rag ask "How does tenant scoping work?"
rag ask --mode auto "Why is auth failing?"
rag ask --mode agent "Prepare implementation context"
rag quick "What does this keybind do?"
rag deep "Review the retrieval architecture"
rag agent "Prepare a Codex handoff for the RAG CLI"
rag agent "Prepare a handoff" --target-agent codex --save-handoff
rag handoff codex "Prepare context for this refactor"
rag handoff human "Explain this subsystem"
```

Use:

- `quick` for small factual questions.
- `deep` for debugging, review, planning, and architecture.
- `agent` or `handoff` when another coding agent or person will continue the work.

### Retrieval Debugging

```bash
rag search "AuthService.login"
rag search "AuthService.login" --explain
rag inspect "AuthService.login"
rag missing "debug checkout failure"
rag why "checkout failure" src/checkout.ts
rag graph AuthService
rag graph --route GET /api/users
rag graph --db users
```

Use these before changing retrieval code. They explain routing, rewrites, expected context, selected files, and graph edges.

### Facts and Trace

```bash
rag facts list
rag facts list --kind keybind
rag facts keybind scratchpad
rag facts tool docker
rag trace keybind Super Alt S
rag trace symbol AuthService
rag trace env DATABASE_URL
```

Facts are structured records extracted during indexing. Trace follows them back to nearby indexed evidence.

### Operational State

```bash
rag context git
rag context git --refresh
rag context github pr 123
rag context github issue 42
rag context github pr 123 --manual --title "Fix auth" --changed-file src/auth.ts
rag context test-failure list
rag context test-failure add "pytest -q" --output-file /tmp/failure.txt --runner pytest --exit-code 1
```

Operational state makes deep and agent answers aware of active diffs, PRs, issues, and failures.

### Todos, Decisions, Commands, Errors

```bash
rag todo list
rag todo add "Refresh retrieval docs" --repo dotfiles
rag todo start 12
rag todo done 12

rag decision list
rag decision add "Use native zsh completion" "Avoid runtime argcomplete dependency" --repo dotfiles

rag command list
rag command add "python -m unittest tests.rag.test_cli_state" --purpose "RAG CLI regression"

rag error list
rag error add "database is locked" --fix "wait for the active rag command to finish"
```

Use these for durable local project memory that should come back in future deep/agent retrieval.

### Memory and Context Packs

```bash
rag summarize
rag summarize --repo dotfiles
rag summarize-files
rag summarize-files --changed-only
rag memory status
rag memory show
rag memory refresh
rag memory clear --repo dotfiles
rag memory clear --all
rag memory remember known_stack backend "node nest mikro-orm postgres" --global-scope
rag memory notes --scope all
rag memory conflicts
rag memory compact
rag memory compact --session-id <session-id>
rag memory pack dotfiles --target-agent codex
rag memory pack dotfiles --target-agent codex --write-file
rag memory taxonomy
rag memory taxonomy --query backend
rag memory taxonomy --format yaml
```

Use context packs when you want a durable `.context/<name>.toon` handoff file in an indexed repo.

### Sessions

```bash
rag session list
rag session list --repo dotfiles
rag session show <session-id>
```

Every answer or handoff is saved as a session. Deep and agent sessions also get compacted for memory reuse.

### Cleanup

```bash
rag clean --repo dotfiles
rag clean --all
```

`clean --all` clears local RAG state and Qdrant collection data. Reindex after using it.

## Practical Workflows

### New repo

```bash
cd /path/to/repo
rag doctor
rag index --profile balanced
rag summarize
rag status
```

### Debug a failing flow

```bash
rag context git --refresh
rag context test-failure add "pytest -q" --output-file /tmp/failure.txt --runner pytest --exit-code 1
rag deep "debug the failing test"
rag missing "debug the failing test"
rag search "exact error text" --explain
```

### Prepare agent context

```bash
rag context git --refresh
rag memory status
rag agent "implement the next RAG CLI UX improvement" --target-agent codex --save-handoff
```

### Find why retrieval missed a file

```bash
rag inspect "query text"
rag missing "query text"
rag why "query text" path/to/file.ts
rag trace symbol SomeSymbol
```

## Troubleshooting

### Completion does not load

Run:

```bash
./setup/install-local-rag-stack.sh
exec zsh
```

If needed:

```bash
rm -f ~/.cache/zsh/.zcompdump ~/.zcompdump
exec zsh
```

Then check:

```bash
whence -v _rag
echo $fpath
```

### Dynamic repo completion is empty

Index at least one repo:

```bash
rag index
```

The dynamic completion reads `${RAG_HOME:-$HOME/ai-rag}/rag.sqlite3` through `sqlite3`. If `sqlite3` is missing, static completion still works.

### A command is slow

Use the lighter surfaces first:

```bash
rag search "query" --explain
rag inspect "query"
rag quick "query"
```

Use `deep`, `agent`, and `doctor --deep` when you actually need larger context, model probes, or handoff output.

## Future UX Ideas

- Add fish and bash completion generators if those shells become relevant.
- Add `rag suggest --json` for scripts and launchers.
- Add fuzzy repo selection for `--repo` when multiple indexed repos match.
- Add a shell widget that inserts `rag suggest <current-buffer>` suggestions through fzf.
- Add a `rag examples <command>` help surface with command-specific examples.
- Add completion for fact kinds directly from SQLite instead of the static fact-kind list.

# Neovim Configuration Reference

The configuration in `nvim/` targets **Neovim 0.12+** and uses `lazy.nvim` with a focused plugin set. Snacks provides the explorer, picker, terminal, dashboard, notifications, and buffer actions. Blink provides completion; Treesitter uses the native `nvim-treesitter` API; LSP setup uses `vim.lsp.config()` and `vim.lsp.enable()`.

---

## Quick Reference

| Category | Key | Action |
|----------|-----|--------|
| **Files** | `<leader>ff` | Find files (Snacks) |
| | `<leader>fg` | Live grep (Snacks) |
| | `<leader>fb` | Find buffers |
| | `<leader>fr` | Recent files |
| | `<leader>fp` | Projects |
| | `<leader>e` | Snacks explorer |
| **Search** | `<leader>sr` | Grug-far search/replace |
| | `<leader>sw` | Search word |
| | `s` / `S` / `r` | Flash.nvim motion |
| **Code** | `<leader>cf` | Format buffer (Conform) |
| | `gd` | LSP goto definition |
| | `<leader>ss` | Document symbols |
| | `<leader>sS` | Workspace symbols |
| **Git** | `<leader>gg` | LazyGit |
| | `]h` / `[h` | Next/prev Git hunk |
| | `<leader>gp` | Preview hunk |
| | `<leader>gs` | Stage hunk |
| | `<leader>gr` | Reset hunk |
| | `<leader>gb` | Blame line |
| **Diagnostics** | `<leader>xx` | Workspace diagnostics |
| | `<leader>xb` | Buffer diagnostics |
| | `<leader>xq` | Quickfix list |
| **Terminal** | `<leader>tt` | Project terminal |
| | `<leader>tf` | Floating terminal |
| **Agents** | `<leader>ao` | OpenCode agent |
| | `<leader>ac` | Codex agent |
| | `<leader>aa` | Prompt to choose OpenCode or Codex, then toggle it |
| **Buffers** | `<leader>bd` | Delete buffer |
| | `<leader>bo` | Delete other buffers |
| **Windows** | `<leader>wv` | Vertical split |
| | `<leader>ws` | Horizontal split |
| | `<leader>wq` | Close window |
| | `<C-h/j/k/l>` | Navigate windows + tmux |
| **Surround** | `gsa` | Add surround |
| | `gsd` | Delete surround |
| | `gsf` | Find surround |
| | `gsr` | Replace surround |

---

## Core Keymaps

**File:** `nvim/lua/noxflow/core/keymaps.lua`

| Mode | Key | Action |
|------|-----|--------|
| n, i, v | `<C-s>` | Save buffer |
| n | `<leader>q` | Quit window |
| n | `<leader>Q` | Quit all |
| n | `<Esc>` | Clear search highlight |

**Terminal autocmd:** `<Esc><Esc>` exits terminal to normal mode

---

## Which-Key Groups

| Group Key | Description |
|-----------|-------------|
| `<leader>f` | Find (files, grep, buffers, etc.) |
| `<leader>s` | Search (symbols, grep word) |
| `<leader>g` | Git (hunks, blame, diff) |
| `<leader>c` | Code (format) |
| `<leader>x` | Diagnostics (trouble) |
| `<leader>a` | Agents (opencode, codex) |
| `<leader>t` | Terminal |
| `<leader>b` | Buffers |
| `<leader>w` | Windows |

---

## Environment Configuration

### Shell Environment (`zshrc`)
```zsh
export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-$EDITOR}"
export GIT_EDITOR="${GIT_EDITOR:-$EDITOR}"
```

### Aliases Using Neovim
- `ff` — fzf-pick files, opens in `$EDITOR`
- `frg <pattern>` — rg + fzf with bat preview, opens match in `$EDITOR`
- `v` / `vim` — alias to `nvim`
- `nvimcheck` — headless health check

---

## Plugin Manager: lazy.nvim

**File:** `nvim/lua/noxflow/lazy.lua`

- Default colorscheme: **catppuccin** (macchiato flavor, transparent)
- Install colorschemes: catppuccin, habamax

---

## Installed Plugins

### LSP Servers (`nvim/lua/noxflow/plugins/lsp.lua`)
- bashls, cssls, dockerls, eslint, html, jsonls, lua_ls, marksman, ts_ls, yamlls
- Formatter: **Conform.nvim** + nvim-lint

### Editor (`nvim/lua/noxflow/plugins/editor.lua`)
- **snacks.nvim** — explorer, picker, terminal, dashboard, notifications
- **which-key.nvim** — keybinding hints
- **vim-tmux-navigator** — seamless tmux/pane navigation
- **vim-sleuth** — automatic indent detection
- **nvim-autopairs** — auto-pair brackets

### Coding (`nvim/lua/noxflow/plugins/coding.lua`)
- **blink.cmp** — completion
- **grug-far.nvim** — search and replace
- **flash.nvim** — motion (jump, treesitter, remote)
- **mini.nvim** — surround operations

### UI (`nvim/lua/noxflow/plugins/ui.lua`)
- **catppuccin** — colorscheme
- **lualine.nvim** — status bar

### Git (`nvim/lua/noxflow/plugins/git.lua`)
- **gitsigns.nvim** — git hunk navigation and staging
- **trouble.nvim** — diagnostics

### Syntax (`nvim/lua/noxflow/plugins/syntax.lua`)
- **nvim-treesitter** with 13 languages (plus `markdown_inline` for inline Markdown): bash, css, dockerfile, html, javascript, json, lua, markdown, rust, toml, tsx, typescript, yaml

### Agents (`nvim/lua/noxflow/plugins/agents.lua`)
- **OpenCode** and **Codex** agent integrations via Snacks terminal

---

## Neovim Options

**File:** `nvim/lua/noxflow/core/options.lua`

```lua
vim.g.mapleader = " "
vim.g.maplocalleader = " "
-- number, relativenumber, mouse, cursorline, clipboard, undo, split settings, tab width=2, etc.
```

---

## Autocmds

**File:** `nvim/lua/noxflow/core/autocmds.lua`

- `TextYankPost` — highlight yanked text
- `BufReadPost` — restore cursor position
- `TermOpen` — terminal settings

---

## File Structure

```
nvim/
├── init.lua                      # Entry point
├── lazy-lock.json               # Pinned plugin commits
├── lua/noxflow/
│   ├── core/
│   │   ├── init.lua             # Core module init
│   │   ├── options.lua          # Neovim options
│   │   ├── keymaps.lua          # Basic keymaps
│   │   └── autocmds.lua         # Autocmds
│   ├── plugins/
│   │   ├── lsp.lua              # LSP + Conform
│   │   ├── coding.lua           # Blink, Grug-far, Flash, Mini
│   │   ├── editor.lua           # Snacks, which-key, vim-tmux-navigator
│   │   ├── ui.lua               # Catppuccin, lualine
│   │   ├── git.lua              # Gitsigns, Trouble
│   │   ├── syntax.lua           # Treesitter
│   │   └── agents.lua           # OpenCode, Codex
│   ├── lazy.lua                 # lazy.nvim bootstrap
│   └── utils.lua                # Project root detection
└── tools/
    └── package.json             # Node language servers
```

---

## Setup & Installation

### Installation
```sh
./setup/bootstrap.sh          # Links nvim/ to ~/.config/nvim
./setup/install-neovim-tools.sh  # Installs Node language servers
```

### Verification
```sh
nvim --headless '+qa'          # Verify startup
nvimcheck                      # Custom health check script
./setup/dev-health.sh         # Full workstation health
```

---

## Related Documentation

- `docs/NEOVIM.md` — Main documentation
- `docs/LOCAL_DEVELOPER_WORKFLOW.md` — Post-upgrade verification
- `SHELL_CHEATSHEET.md` — Quick reference
- `ai/system/GLOBAL_SYSTEM.md` — Editor stack info
- `setup/pacman-packages.txt` — Neovim package listing

---

## Tmux Integration

`<C-h/j/k/l>` navigates Neovim windows first, then falls through to adjacent tmux panes via `vim-tmux-navigator`.

**File:** `nvim/lua/noxflow/plugins/editor.lua` (lines 80-83)
```lua
<C-h> → TmuxNavigateLeft
<C-j> → TmuxNavigateDown
<C-k> → TmuxNavigateUp
<C-l> → TmuxNavigateRight
```

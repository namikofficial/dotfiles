# Neovim

The configuration in `nvim/` targets Neovim 0.12 and uses `lazy.nvim` with a
small set of focused plugins. Snacks provides the explorer, picker, terminal,
dashboard, notifications, and buffer actions. Blink provides completion;
Treesitter uses the current `nvim-treesitter` API; LSP setup uses
`vim.lsp.config()` and `vim.lsp.enable()`.

## One-time tools

Install the Arch packages used by the configured language servers and linters:

```sh
sudo pacman -S --needed tree-sitter-cli bash-language-server dockerfile-language-server marksman markdownlint-cli2
```

Install the pinned Node language servers used by CSS, HTML, JSON, ESLint, and
TypeScript:

```sh
./setup/install-neovim-tools.sh
```

Project-local formatters are preferred by Conform. Format-on-save is enabled
only for Rust, shell/TOML files, and web files in projects that explicitly
declare Prettier or contain a Prettier configuration.

## Core mappings

| Mapping | Action |
| --- | --- |
| `<leader>ff` / `<leader>fg` | Files / live grep |
| `<leader>e` | Snacks explorer |
| `<leader>sr` | Project search and replace (`grug-far`) |
| `<leader>cf` | Format buffer or selection |
| `<leader>xx` / `<leader>xb` / `<leader>xq` | Workspace, buffer, or quickfix diagnostics |
| `<leader>gg` | LazyGit |
| `]h` / `[h` | Next / previous Git hunk |
| `<leader>gp` / `<leader>gs` / `<leader>gr` | Preview / stage / reset hunk |
| `<leader>tt` / `<leader>tf` | Reusable project / floating terminal |
| `<leader>ao` / `<leader>ac` | OpenCode / Codex at the project root |
| `Ctrl-h/j/k/l` | Neovim windows, then adjacent tmux panes |

Native Neovim LSP mappings (`grn`, `grr`, `gra`, `gri`, `grt`, and `K`) remain
available and are not shadowed by custom leader mappings.

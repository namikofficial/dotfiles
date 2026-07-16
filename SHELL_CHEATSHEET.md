# Shell + Tmux Cheatsheet

## Reload / Edit
- Reload shell: `source ~/.zshrc` or `reload`
- Edit zsh dotfile: `zshc`
- Edit aliases: `zalias`
- Edit starship prompt: `starc`
- Open this cheatsheet: `cheat`

## Navigation
- Jump projects: `dev`, `scripts`, `projects`
- Jump code dir: `cdev` (`~/Documents/code`)
- Up dirs: `..`, `...`, `....`
- Make + enter dir: `mkcd my-folder`
- Jump to git repo root: `groot`
- FZF cd picker: `cdf`

## Search + History
- Fuzzy file/command search: `fzf` and `<TAB>` with `fzf-tab`
- History search: type part of command, then `Up`/`Down`
- Atuin interactive search: `hs`
- Atuin sync status/login/sync: `hstatus`, `hlogin`, `hsync`
- Atuin learning loop:
  - Weekly top commands: `hweek`
  - Monthly top commands: `hmonth`
  - Full top commands: `hstats`

## Modern Replacements
- `ls` -> `eza`
- `ll` -> detailed `eza` with git info
- `lli` -> tree view + full details (`eza` tree)
- `cat` -> `bat`/`batcat`
- `grep` -> `rg`
- `vim` -> `nvim`
- `helpcmd` -> `tldr` examples

## Neovim Battle Station
- Launch Neovim: `v` (alias to `nvim`)
- Plugin UI: `<leader>pl` (or `:Lazy`)
- Mason UI: `<leader>pm` (or `:Mason`)
- Health check: `<leader>pc` (or `:checkhealth`)
- Quick open files: `<C-p>`
- Explorer toggle: `<C-b>`
- AI chat toggle: `<leader>aa`
- Run nearest test: `<leader>tn`
- Run task runner: `<leader>or`
- Open lazygit from Neovim terminal: `<leader>gg`
- Main config: `~/Documents/code/dotfiles/nvim/init.lua`

## Handy Aliases
- Disk usage in current dir: `duh`
- Filesystem usage: `dfh`
- Show PATH lines: `path`
- Current timestamp: `now`
- Public IP: `myip`
- System monitor: `sysmon` (`btop`)
- Disk overview: `disks` (`duf`)
- LazyGit: `lg`
- Process explorer (`procs`): `pps`, CPU sort `ppsc`, memory sort `ppsm`
- Disk analyzer (`dust`): `dsz`, shallow depth `dsz2`
- Command benchmark (`hyperfine`): `bench 'cmd1' 'cmd2'`
- GitHub CLI: `ghs`, `ghpr`, `ghpv`
- Pipx: `pxl`, `pxi`
- Clipboard helpers: `echo "text" | clipcopy`, `clippaste`, `jclip`
- JSON helpers:
  - Main helper: `je`
  - Pretty print: `jj file.json`
  - Keys: `jk file.json`
  - Custom filter: `jp '.items[].id' file.json`
  - Find key recursively: `jf id file.json`
  - Validate JSON: `jv file.json`
- Devlink helpers:
  - Main helper: `dl`
  - Show devices: `dld`
  - Show ports: `dlp`
  - Show health: `dlh`
  - Monitor events: `dlm`
- FZF open file in editor: `ff`
- FZF search by ripgrep + preview: `frg <pattern>`
- FZF pick and kill process: `fkill`
- Open quick notes file: `tnotes`
- Run environment checks: `doctor`
- Kill app by listening port: `pkillport 3000`

## Power / Graphics (COSMIC + Pop!_OS)
- Full status (power profile + graphics mode): `pstatus`
- Power profile:
  - Show current: `pp status`
  - Battery saver: `pp battery` or `ppb`
  - Balanced: `pp balanced` or `ppd`
  - Performance: `pp performance` or `ppp`
- Graphics mode:
  - Show current: `gfx status`
  - Integrated: `gfx integrated` or `gfxi`
  - Hybrid: `gfx hybrid` or `gfxh`
  - NVIDIA: `gfx nvidia` or `gfxn`
  - Compute: `gfx compute` or `gfxc`
- Battery details summary (via `upower`): `batt`

## Git
- Status short: `gss`
- Graph log: `glg`
- Commit all tracked changes: `gcam`
- Undo last commit keep changes: `gundo`
- Delete merged local branches safely: `gclean`
- Worktree list: `gwtl`
- Create ticket branch worktree: `gwtn PROJ-123 short summary`
- Create + auto-enter new ticket worktree: `gwtnc PROJ-123 short summary`
- Jump to worktree by branch/path: `gwtc feat/my-task`
- Resolve worktree absolute path: `gwtp feat/my-task`
- Cleanup stale worktrees:
  - Preview: `wtprune --dry-run`
  - Apply without prompt: `wtprune --yes`

## Docker / K8s
- Docker table ps: `dps`
- Docker prune: `dprune`
- Docker compose logs tail: `dclg`
- Docker compose build: `dcb`
- K8s get all: `kga`
- K8s context: `kctx`
- Set namespace: `kns my-namespace`

## Tmux Basics
- Attach or create `main`: `ta`
- New/attach named session: `tns work`
- Sessionizer picker: `tms`
- List sessions: `tls`
- Reload tmux config from `~/Documents/code/dotfiles/tmux/tmux.conf`: `tr`
- Kill session: `tk work`
- Kill tmux server: `tka`
- Start the four-pane project layout: `project-profile dev nox-billings`
- Open Nox Billings on the Android emulator: `nox-billings-emulator`

## Client Backups

- Initialize private backup configuration: `client-backup init-config`
- Validate backup connectivity: `client-backup verify`
- Run an encrypted snapshot now: `client-backup run`
- Show latest snapshot: `client-backup status`

## Tmux In-Session Keys
- Prefix is `Ctrl-Space`
- Detach session: `Ctrl-Space d`
- Split vertical: `Ctrl-Space -`
- Split horizontal: `Ctrl-Space |`
- Move pane: `Ctrl-Space h/j/k/l`
- Resize pane: `Ctrl-Space H/J/K/L`
- Zoom pane: `Ctrl-Space z`
- Help hint: `Ctrl-Space ?`
- Install/update plugins: `Ctrl-Space I`

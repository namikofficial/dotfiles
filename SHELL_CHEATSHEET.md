# Shell Cheatsheet

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
- Atuin sync/status/login: `hstatus`, `hlogin`, `hsync`
- Weekly/monthly stats: `hweek`, `hmonth`

## Modern Replacements
- `ls` → `eza`
- `ll` → detailed `eza` with git info
- `lli` → tree view + git summary
- `cat` → `bat`/`batcat`
- `grep` → `rg`
- `helpcmd` → `tldr`

## Handy Aliases
- Disk usage in current dir: `duh`
- Filesystem usage: `dfh`
- Show PATH lines: `path`
- Current timestamp: `now`
- Public IP: `myip`
- System monitor: `sysmon` (`btop`)
- Disk overview: `disks` (`duf`)
- LazyGit: `lg`
- Process explorer: `pps`, CPU sort `ppsc`, memory sort `ppsm`
- Disk analyzer: `dsz`, shallow depth `dsz2`
- Benchmarks: `bench 'cmd1' 'cmd2'`
- GitHub CLI: `ghs`, `ghpr`, `ghpv`
- Pipx: `pxl`, `pxi`
- Clipboard helpers: `echo "text" | clipcopy`, `clippaste`, `jclip`
- JSON helpers: `je`, `jj`, `jc`, `jk`, `jl`, `jp`, `jf`, `jv`, `jh`
- Devlink helpers: `dl`, `dld`, `dlp`, `dlh`, `dlm`
- Alc commands: `ff`, `frg`, `fkill`, `tnotes`, `doctor`, `pkillport`

## Power / Graphics
- Current power profile: `powerprofilesctl get`
- Set balanced mode: `powerprofilesctl set balanced`
- Set performance mode: `powerprofilesctl set performance`
- Set power-saver mode: `powerprofilesctl set power-saver`
- Battery summary: `batt`
- Enable detailed Waybar GPU polling (off by default): `export WAYBAR_GPU_DEEP_POLL=1; pkill -x waybar; waybar & disown`

## Git
- Status short: `gss`
- Graph log: `glg`
- Commit: `gcm`, `gcam`
- Undo last commit: `gundo`
- Delete merged branches safely: `gclean`

## Docker / K8s
- Docker ps table: `dps`
- Docker prune: `dprune`
- Docker compose logs: `dclg`
- Docker compose build: `dcb`
- Kubernetes get all: `kga`
- Kubernetes current context: `kctx`
- Kubernetes namespace switch: `kns my-namespace`

## Safety Defaults
- `noclobber` protects overwrites
- `cp`, `mv`, `rm` prompt before destructive actions

## Command Fixer
- After a failed command, run: `fuck`
- `pay-respects` teaches a better command

## Included Scripts
- `bin/dev-doctor`, `bin/jq-easy`, `bin/devlink-easy`, `bin/klogs-fzf`, etc., live in `~/Documents/code/scripts/bin` and back the aliases above.

## Hyprland Quick Keys
- `Super + Return`: terminal (`kitty`)
- `Super + Space`: app launcher (press again to close)
- In launcher: Tab A = top 5 frequent, Tab B = all apps, `Ctrl + Tab` switches tabs
- `Super + .`: fullscreen dev cheatsheet overlay
- `Super + F1`: keybind helper overlay
- `Super + A` or `Super + /`: quick actions (press again to close)
- `Super + Ctrl + /`: keybind helper overlay
- In launcher/actions: `Ctrl + 1..0` quick-select, `Enter` run/open
- `Super + W`: workspace overview picker (Rofi)
- `Super + Tab`: Mission Control overview (`hyprexpo`)
- `Super + Shift + Tab`: force Rofi overview
- `Super + F`: toggle floating for active window
- `Super + M`: maximize / unmaximize active window
- `Super + G`: toggle `dwindle` / `master` layout
- `Super + Alt + G`: cycle dynamic layouts (`dwindle/master/allfloat/allpseudo`)
- `Alt + Tab` / `Alt + Shift + Tab`: cycle workspace windows
- `Super + \\`: toggle side panel special workspace
- `Super + Shift + \\`: move current window into side panel + open it
- `Super + Ctrl + 9`: open logs workspace terminal (workspace 9)
- `Super + D`: quick actions
- `Super + O`: wallpaper picker
- `Super + Shift + O`: next wallpaper
- `Super + N`: toggle notification panel
- `Super + Shift + Space`: window/workspace search
- `Super + Ctrl + Space`: command palette
- `Super + Alt + N`: toggle DND
- `Super + Ctrl + N`: copy notification/status summary
- `Super + Shift + N`: toggle scratchpad notes
- `Super + \``: toggle scratchpad terminal
- `Super + Alt + E`: open notes folder in editor
- `Super + I`: pick a color (`hyprpicker -a`)
- `Super + Shift + I`: toggle night light
- `Super + Shift + T`: OCR selected area to clipboard
- `Super + Ctrl + R`: toggle screen recording
- `Super + Y`: toggle widget panel (Eww)
- `Super + Ctrl + Y`: toggle panel engine (`waybar`/`hyprpanel`)
- `Super + Alt + Y`: toggle panel visibility only
- `Super + Ctrl + Shift + Y`: toggle desktop widgets
- `Fn + 2/3/4/5`: AI helper (`ask`/`clipboard`/`shell`/`debug`)
- `Super + Ctrl + Arrow`: move active floating window
- `Super + Ctrl + Shift + Arrow`: resize active floating window
- `Super + [` / `Super + ]`: previous / next workspace

## Kitty Keymaps
- New tab (same cwd): `Ctrl + Shift + T`
- Close tab: `Ctrl + Shift + Q`
- Close split/window: `Ctrl + Shift + W`
- Previous / next tab: `Ctrl + Shift + [` / `Ctrl + Shift + ]`
- New window (same cwd): `Ctrl + Shift + Enter`
- Split horizontal / vertical: `Ctrl + Shift + O` / `Ctrl + Shift + E`
- Focus left/right/up/down split: `Ctrl + Shift + H/J/K/L`
- Resize split: `Ctrl + Shift + Alt + H/J/K/L`
- Reload kitty config: `Ctrl + Shift + F5`
- Clipboard: selecting text copies automatically (`copy_on_select`)

## Tmux Quickstart
- Start/attach `main` session: `tnew` or `tn`
- Attach named session: `ta mysession`
- List sessions: `tls`
- Prefix key: `Ctrl + A`
- New window: `Prefix + c`
- Split horizontal / vertical: `Prefix + -` / `Prefix + |`
- Move panes: `Prefix + h/j/k/l`
- Resize panes: `Prefix + H/J/K/L`
- Reload tmux config: `Prefix + r` or `treload`
- Copy in copy-mode: `Prefix + [` then `v` select, `y` copy (uses `wl-copy`)
- Install/update TPM plugins: `~/Documents/code/dotfiles/setup/install-tmux-plugins.sh`

## Session Repair
- Reload shell config: `exec zsh`
- Reload Hyprland config: `hyprctl reload`
- Restart portal services: `systemctl --user restart xdg-desktop-portal xdg-desktop-portal-hyprland xdg-desktop-portal-gtk`
- Restart Waybar cleanly: `~/.config/hypr/scripts/restart-waybar.sh`
- Toggle NetworkManager tray applet: `~/.config/hypr/scripts/nm-applet-toggle.sh`

## Reboot Runbook (3 commands)
- `sudo ~/Documents/code/dotfiles/setup/pre-reboot-apply.sh`
- `sudo reboot`
- `~/Documents/code/dotfiles/setup/post-reboot-verify.sh`

## Timeshift Auto Snapshots
- Configure daily snapshots + keep latest 5: `sudo ~/Documents/code/dotfiles/setup/configure-timeshift.sh`
- Check timer status: `systemctl status noxflow-timeshift-auto.timer`
- Read latest setup log: `cat ~/Documents/code/dotfiles/logs/timeshift-setup-latest.log`

## Login Screen (SDDM)
- Apply improved SDDM theme/background: `sudo ~/Documents/code/dotfiles/setup/configure-sddm.sh`

## Weekly Health Check
- Run now: `~/Documents/code/dotfiles/setup/weekly-health-check.sh`
- Enable weekly timer: `~/Documents/code/dotfiles/setup/configure-weekly-healthcheck.sh`
- Latest log: `cat ~/Documents/code/dotfiles/logs/health-latest.log`
- Auto-open failures in editor: `HEALTHCHECK_OPEN_ON_FAIL=1 ~/Documents/code/dotfiles/setup/weekly-health-check.sh`

## Default Editor
- Configure MIME defaults (VS Code preferred): `~/Documents/code/dotfiles/setup/configure-default-editor.sh`

## LocalSend
- Install via Flatpak: `flatpak install -y flathub org.localsend.localsend_app`
- Launch: `flatpak run org.localsend.localsend_app`

## Shell Navigation UX
- `Ctrl + R`: Atuin fuzzy history UI
- `Alt + C`: fuzzy jump into a zoxide directory
- `Esc`: enter `zsh-vi-mode` normal mode (if plugin installed)

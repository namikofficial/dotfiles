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
- `Super + A` or `Super + /`: quick actions (press again to close)
- In launcher/actions: `Ctrl + 1..0` quick-select, `Enter` run/open
- `Super + W`: workspace overview picker (Rofi)
- `Super + Tab`: Mission Control overview (`hyprexpo`)
- `Super + Shift + Tab`: force Rofi overview
- `Super + F`: toggle floating for active window
- `Super + G`: toggle `dwindle` / `master` layout
- `Super + D`: quick actions
- `Super + O`: wallpaper picker
- `Super + Shift + O`: next wallpaper
- `Super + N`: toggle notification panel
- `Super + Shift + N`: toggle DND
- `Super + Ctrl + N`: copy notification/status summary
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

## Shell Navigation UX
- `Ctrl + R`: Atuin fuzzy history UI
- `Alt + C`: fuzzy jump into a zoxide directory
- `Esc`: enter `zsh-vi-mode` normal mode (if plugin installed)

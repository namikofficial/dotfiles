# Arch Workstation Dotfiles

This repository is designed to bootstrap a complete Arch + Hyprland workstation with reproducible shell, UI, and desktop behavior.

## Includes

- `zshrc`, `aliases.zsh`, `aliases.local.zsh`, `SHELL_CHEATSHEET.md`
- `tmux/tmux.conf` + `setup/install-tmux-plugins.sh` (TPM plugin sync)
- `nvim/` Lua-based Neovim config managed in dotfiles
- `atuin/config.toml` for consistent Atuin history UI/search defaults
- `docs/KEYBINDS.md` full keybind tables + Mermaid map
- `docs/RUNBOOK.md` 3-command pre/post reboot flow + log paths
- `docs/NOXFLOW_TODO.md` tracked setup checklist
- `hypr/` for Hyprland, Waybar, Rofi, swaync, wlogout, dunst, lockscreen, and helper scripts
- `hypr/eww/` for optional widget panel (Quick Deck)
- `kitty/kitty.conf` so new terminals always load login `zsh`
- `chrome/chrome-flags.conf` for smooth Chrome defaults on Wayland
- `theme/` for GTK, Qt5/Qt6, and Kvantum visual consistency
- `setup/` automation scripts for links and package installation
- `settings/` schema-driven settings state (`settingsctl` + Settings Hub)
- `kde/` + `mime/` managed KDE defaults and MIME handlers

## Quick start

```sh
cd ~/Documents/code/dotfiles
git submodule update --init private/scripts
./setup/bootstrap.sh
```

If you do not have access to the private scripts repo, skip the `git submodule` step and the public dotfiles setup will still work.

That command:

- links shell files (`~/.zshrc`, cheat sheet)
- links tmux config (`~/.tmux.conf`)
- links Neovim config (`~/.config/nvim`)
- links Atuin config into `~/.config/atuin/config.toml`
- links UWSM compositor env (`~/.config/uwsm/env-hyprland`)
- links Hyprland service override (`~/.config/systemd/user/wayland-wm@hyprland.desktop.service.d/10-aq-drm-devices.conf`)
- links Hyprland, Waybar, Rofi, and Kitty configs into `~/.config`
- links Eww and static theme configs (`gtk`, `qt5ct`, `qt6ct`) into `~/.config`
- links optional Eww settings panel config into `~/.config/eww-settings`
- links swaync/wlogout/dunst configs into `~/.config`
- links Chrome flags to `~/.config/chrome-flags.conf`
- copies runtime-managed KDE/theme defaults (`kdeglobals`, `Kvantum`) into `~/.config` so wallpaper sync can update them without dirtying the repo
- links KDE app defaults (`dolphinrc`, `kiorc`, `gwenviewrc`)
- copies MIME defaults (`~/.config/mimeapps.list`) so local handler changes stay machine-specific
- links your private scripts commands into `~/.local/bin` when `private/scripts` (or another `--scripts-dir`) is available
- installs/updates optional zsh plugins under `~/.local/share/zsh/plugins`
- installs/updates tmux plugins via TPM (`~/.tmux/plugins/tpm`)
- creates timestamped backups when replacing existing configs

## Full install (packages + links)

```sh
cd ~/Documents/code/dotfiles
./setup/bootstrap.sh --install-packages --with-aur
```

Base installs leave the existing NVIDIA stack untouched. NVIDIA users can opt in to repo-managed kernel/userspace driver packages:

```sh
./setup/bootstrap.sh --install-packages --with-aur --with-nvidia
```

You can run package install via `sudo` too; the script now delegates AUR operations to your normal user automatically.

## Package manifests

- `setup/pacman-packages.txt`: official repository packages
- `setup/nvidia-packages.txt`: NVIDIA kernel/userspace acceleration stack
- `setup/aur-packages.txt`: AUR packages (`google-chrome`, `wlogout`, `eww`, `localsend`)
- `setup/install-hypr-plugins.sh`: builds/installs `hyprexpo` locally and loads it when possible

Install packages only:

```sh
./setup/install-packages.sh --with-aur
```

If package install fails with `db.lck`, clear stale lock and retry:

```sh
sudo rm -f /var/lib/pacman/db.lck
```

The installer auto-skips packages that are not available in current repos.
NVIDIA packages are opt-in only; hardware detection alone does not change your current driver stack.
The bootstrap script automatically runs `setup/install-zsh-plugins.sh` unless you pass `--no-zsh-plugins`.
The bootstrap script automatically runs `setup/install-tmux-plugins.sh` unless you pass `--no-tmux-plugins`.

## Keybind highlights (Hyprland)

- `Super + Y`: primary workspace hub (`workspace-overview-toggle.sh`)
- `Super + W`: workspace/window overview switcher (direct Rofi list)
- `Super + Tab`: overview toggle (`hyprexpo` if loaded, otherwise fallback Rofi overview)
- `Super + Shift + Tab`: direct Rofi overview
- `Super + Space`: ultra-fast app launcher (type-to-search, minimal chrome)
- `Super + Shift + Space`: window/workspace search
- `Super + Ctrl + Space`: command palette (quick actions)
- `Super + F1`: open keybind helper overlay (`hypr-binds.sh`)
- `Super + Ctrl + /`: open keybind helper overlay
- `Super + A` / `Super + /`: quick actions (press again to close)
- `Ctrl + 1..0` in launcher/actions: quick-select top 10 rows
- `Enter` in launcher/actions: open/run selected row
- opener key again (`Super+Space` / `Super+A`): close launcher/actions
- `Super + B`: open Google Chrome
- `Super + D`: quick actions (duplicate utility key)
- `Super + ,`: open Settings Hub
- `Super + Shift + ,`: re-apply last selected settings section
- `Super + Ctrl + ,`: quick settings toggle (notification sounds)
- `Super + Alt + ,`: toggle Eww detailed settings panel
- `Super + Ctrl + Alt + ,`: apply per-app routing to focused app
- `Super + Alt + P`: open monitor control/recovery menu
- `Super + .`: fullscreen dev cheatsheet overlay (searchable + tabbed)
- `Super + F`: toggle floating on active window
- `Super + M`: maximize/unmaximize active window
- `Super + G`: toggle tiling layout (`dwindle` <-> `master`)
- `Super + Alt + G`: cycle dynamic layouts (`dwindle -> master -> allfloat -> allpseudo`)
- `Super + Shift + G`: toggle floating-grid workspace mode
- `Super + \`: toggle side panel special workspace
- `Super + Shift + \`: move active window to side panel and open it
- `Super + H/J/K/L`: focus left/down/up/right
- `Alt + Tab` / `Alt + Shift + Tab`: cycle windows in current workspace
- `Super + Shift + H/J/K/L`: move window left/down/up/right
- `Super + O`: wallpaper picker
- `Super + Shift + O`: next wallpaper
- `Super + N`: toggle notification panel
- `Super + Alt + N`: toggle DND
- `Super + Ctrl + N`: copy notification/status summary to clipboard
- `Super + Shift + N`: open notes folder
- `Super + Alt + E`: open notes folder in editor
- `Super + I`: color picker (copies hex)
- `Super + Ctrl + V`: clipboard browser
- `Super + Shift + V`: toggle floating clipboard browser with pinning, filters, and split preview
- `Super + Shift + I`: toggle night light (`hyprsunset`)
- `Super + Ctrl + R`: toggle screen recording (`wf-recorder`)
- `Super + Shift + T`: screenshot OCR -> clipboard (`ocr-capture.sh`)
- In-workspace-hub hotkeys: `Ctrl + Alt + R` rename, `Ctrl + Alt + Backspace` clear label, `Ctrl + Alt + F` favorite, `Ctrl + Alt + S` shortcuts, `Ctrl + Alt + M/O/P` window move/send actions
- `Super + Ctrl + Shift + Y`: apply theme pass (GTK + Qt + Kvantum)
- `Super + Ctrl + Y`: restore Waybar panel
- `Super + Shift + Y`: toggle panel visibility only (show/hide current panel)
- `Super + Ctrl + Alt + Y`: toggle desktop widgets (above wallpaper / below windows)
- `Super + T`: toggle window group (tab-like stacks)
- `Super + Ctrl + T`: move active window out of group
- `Super + Alt + ;` / `Super + Alt + .`: previous/next tab in group
- `Fn + 2/3/4/5` (`XF86Launch2..5`): AI helper actions (`ask`, `clipboard`, `shell`, `debug`)
- `Super + Alt + 2/3/4/5`: fallback AI helper actions
- `Super + Ctrl + H/J/K/L` (or arrows): move floating window
- `Super + Ctrl + Shift + H/J/K/L` (or arrows): resize floating window
- `Super + [ / ]`: previous/next workspace
- `Super + Ctrl + 9`: open logs workspace helper
- `Super + Ctrl + Shift + 9`: open logs workspace stack

Launcher performance note:
- cache is warmed at session startup (`launcher.sh --warm-cache`)
- row lists are pre-rendered to `~/.local/state/noxflow/launcher-rows-*.txt`
- stale cache refresh runs in background
- fast mode (`launcher.sh --fast`) skips icon rendering for near-instant open

Full keybind tables: `docs/KEYBINDS.md`
Wallpaper/theming pipeline: `docs/WALLPAPER_THEMING.md`

## Settings Control Plane

Use the settings controller for validated state updates and apply operations:

```sh
~/.config/hypr/scripts/settingsctl list
~/.config/hypr/scripts/settingsctl set notifications.timeout 10
~/.config/hypr/scripts/settingsctl apply notifications
~/.config/hypr/scripts/settingsctl doctor
~/.config/hypr/scripts/settingsctl profile list
~/.config/hypr/scripts/settingsctl profile apply performance
```

Normalize existing copied files to symlinks:

```sh
./setup/normalize-links.sh
```

## Shell UX highlights

- `Ctrl + R`: Atuin fuzzy history picker (bound in emacs + vi insert keymaps)
- `Alt + C`: fuzzy zoxide directory jump
- `zsh-vi-mode` is auto-loaded when installed via `setup/install-zsh-plugins.sh`
- Tmux prefix is `Ctrl + A`; pane navigation is `Prefix + h/j/k/l`
- Neovim config is in `nvim/` and bootstraps plugins with `lazy.nvim`

Notification panel now includes sticky "System Hub" controls (GPU/media/network/panel status, copy summary, widget toggles, and quick controls) via SwayNC.

AI helper behavior:
- Uses `codex exec` in a dedicated Kitty window when available.
- Falls back to opening ChatGPT in browser if Codex CLI is unavailable.

## Apply changes

```sh
exec zsh
hyprctl reload
systemctl --user restart xdg-desktop-portal xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
~/.config/hypr/scripts/theme-pass.sh   # same reload flow as Super+Ctrl+Shift+Y
~/.config/hypr/scripts/restart-waybar.sh
~/.config/hypr/scripts/launcher.sh --warm-cache
```

If Waybar or Rofi was already running before bootstrap, restart your Hyprland session once.

## Post-install verify

```sh
nvidia-smi
modinfo -F license nvidia
vulkaninfo | head -n 20
LIBVA_DRIVER_NAME=iHD vainfo | head -n 20
xdg-settings get default-web-browser
hyprctl plugin list
```

After changing NVIDIA kernel modules, reboot once before running the checks.

You can run the bundled checker too:

```sh
./setup/verify-nvidia.sh
```

If you want live GPU metrics in Waybar (instead of low-noise runtime status), run:

```sh
export WAYBAR_GPU_DEEP_POLL=1
~/.config/hypr/scripts/restart-waybar.sh
```

## 3-command reboot workflow

```sh
sudo ./setup/pre-reboot-apply.sh
sudo reboot
./setup/post-reboot-verify.sh
```

Logs are written to `logs/pre-reboot-latest.log`, `logs/post-reboot-latest.log`, and `~/.local/state/noxflow/waybar.log`.
Full flow: `docs/RUNBOOK.md`

## Weekly health check (logs + red flags)

Run once:

```sh
./setup/weekly-health-check.sh
```

Enable weekly timer:

```sh
./setup/configure-weekly-healthcheck.sh
```

Log output:
- `logs/health-*.log`
- `logs/health-latest.log`

If you want the log to auto-open on failures:

```sh
HEALTHCHECK_OPEN_ON_FAIL=1 ./setup/weekly-health-check.sh
```

## Default editor + notes workflow

Set default editor MIME handlers:

```sh
./setup/configure-default-editor.sh
```

Notes path defaults:
- Folder: `~/Documents/notes`
- Scratch file: `~/Documents/notes/inbox.md`
- `open-notes.sh` prefers Obsidian when it is installed, then falls back to official VS Code.

## KDE companion apps on Hyprland

For a Hyprland-first setup with native KDE file management, image viewing, and a GUI settings app:

```sh
sudo pacman -S --needed gwenview systemsettings ark
```

If you want a full Plasma session installed alongside Hyprland later, keep it separate from the base dotfiles install:

```sh
sudo pacman -S --needed plasma-desktop plasma-workspace
```

## Timeshift daily auto snapshots (keep latest 5)

```sh
sudo ./setup/configure-timeshift.sh
```

This sets Timeshift to daily snapshots only, keeps the latest 5 daily snapshots, installs a daily `noxflow-timeshift-auto.timer`, and writes logs to `logs/timeshift-setup-latest.log`.

## SDDM login screen polish

```sh
sudo ./setup/configure-sddm.sh
```

This installs the repo theme profile (`noxflow`) and syncs login background from your current wallpaper cache.

## LocalSend (AirDrop-style sharing)

If `localsend` is not in pacman/AUR on your mirror state, use Flatpak:

```sh
flatpak install -y flathub org.localsend.localsend_app
```

Or use repo automation:

```sh
./setup/install-flatpak-apps.sh
```

## NVIDIA stability notes (hybrid laptops)

- If `modinfo -F license nvidia` prints `Dual MIT/GPL`, you are running NVIDIA open kernel modules (`nvidia-open-dkms`).
- If `modinfo -F license nvidia` prints `NVIDIA`, you are running proprietary modules.
- On current Arch repos (since the March 3, 2026 NVIDIA 570+ packaging change), `nvidia-dkms` is not provided and `nvidia-open-dkms` is the official kernel-module package.
- On this setup, forcing `nvidia_drm` modeset can trigger login/shutdown hangs on some hybrid laptops.
- The included safe profile keeps boot stable by blacklisting `nvidia_drm` during compositor startup.
- Waybar now exposes a real system tray, and `nm-applet` plus `blueman-applet` auto-start by default for menu-style Wi-Fi/Bluetooth controls.
  Set `HYPR_ENABLE_NM_APPLET=0` or `HYPR_ENABLE_BLUEMAN_APPLET=0` if you want the panel-only workflow instead.

If login freezes and `nvidia-persistenced` times out, run:

```sh
sudo ./setup/fix-nvidia-proprietary-hybrid.sh
sudo reboot
```

If Hyprland crashes at login with `CBackend::create() failed`, check `AQ_DRM_DEVICES` in `~/.config/uwsm/env-hyprland`. Do not use `/dev/dri/by-path/pci-0000:...` there because `AQ_DRM_DEVICES` is colon-separated; use `/dev/dri/cardN` instead.

If external HDMI/DP hotplug stops working on hybrid Intel + nouveau laptops, install `modprobe.d/nouveau-runtimepm.conf` into `/etc/modprobe.d/` and rebuild initramfs. That disables nouveau runtime PM so the dGPU keeps reporting external connectors after unplug/replug.

If your system hard-freezes during login with kernel messages about `kworker`, `nv_drm_dev_load`, or `nvidia-persiste`, use:

```sh
sudo ./setup/emergency-hypr-login-fix.sh
sudo reboot
```

## Hypr plugin setup

```sh
./setup/install-hypr-plugins.sh
```

This builds `hyprexpo` into `~/.local/share/hypr/plugins/hyprexpo/hyprexpo.so`.
`startup.sh` will load it on session start, and `Super + Tab` will also load it
on demand before falling back to the Rofi overview.

Optional (can fail on some Hyprland versions):

```sh
./setup/install-hypr-plugins.sh --with-hyprspace
```

If reboot itself hangs and you need a guaranteed stable baseline, force iGPU-only boot:

```sh
sudo ./setup/force-igpu-safe-boot.sh
sudo sh -c 'echo 1 > /proc/sys/kernel/sysrq; echo s > /proc/sysrq-trigger; echo u > /proc/sysrq-trigger; echo b > /proc/sysrq-trigger'
```

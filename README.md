# Arch + Hyprland Workstation Dotfiles

This repository bootstraps an Arch + Hyprland workstation with reproducible shell, desktop, settings, and local AI runtime behavior.

## Includes

- `zshrc`, `aliases.zsh`, `aliases.local.zsh`, `SHELL_CHEATSHEET.md`
- `tmux/tmux.conf` + `setup/install-tmux-plugins.sh` (TPM plugin sync)
- `nvim/` Lua-based Neovim config managed in dotfiles
- `atuin/config.toml` for consistent Atuin history UI/search defaults
- `docs/KEYBINDS.md` full keybind tables + Mermaid map
- `docs/RUNBOOK.md` 3-command pre/post reboot flow + log paths
- `docs/NOXFLOW_TODO.md` tracked setup checklist
- `docs/NETWORK_STACK_POLICY.md` locked Wi-Fi stack policy (NetworkManager + wpa_supplicant)
- `docs/LOCAL_DEVELOPER_WORKFLOW.md` day-to-day developer readiness, project, AI, and recovery workflow
- `hypr/` for Hyprland, Wayle-first shell scripts, Rofi, wlogout, lockscreen, and helper scripts
- `wayle/` for the preferred future shell config
- `kitty/kitty.conf` so new terminals always load login `zsh`, show a dashboard banner, and expose app-like tabs
- `chrome/chrome-flags.conf` for smooth Chrome defaults on Wayland
- `theme/` for GTK visual consistency
- `setup/` automation scripts for links and package installation
- `settings/` schema-driven settings state (`settingsctl` + Settings Hub)
- `mime/` managed MIME handlers

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
- links UWSM compositor env (`~/.config/uwsm/env` and `~/.config/uwsm/env-hyprland`)
- links Hyprland service override (`~/.config/systemd/user/wayland-wm@hyprland.desktop.service.d/10-aq-drm-devices.conf`)
- links the modular Hyprland entrypoint (`hyprland.lua` + `hypr/conf/*.lua`), Wayle, Rofi, wlogout, and Kitty configs into `~/.config`
- links GTK theme configs into `~/.config`
- links portal routing so screen sharing uses XDPH and file picking uses GTK
- links Chrome flags to `~/.config/chrome-flags.conf`
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

- `setup/pacman-packages.txt`: official repository packages for the base workstation stack
- `setup/nvidia-packages.txt`: NVIDIA kernel/userspace acceleration stack
- `setup/aur-packages.txt`: AUR packages (`google-chrome`, `wlogout`, `localsend`)
- `setup/install-hypr-plugins.sh`: builds/installs `hyprexpo` locally and loads it when possible

## Network stack standard

This repo standard is:

- `NetworkManager` + `wpa_supplicant`
- no `iwd`

Enforce it any time with:

```sh
./setup/enforce-network-stack.sh
```

Policy details and rationale:

- `docs/NETWORK_STACK_POLICY.md`

Install packages only:

```sh
./setup/install-packages.sh --with-aur
```

Run shell checks locally:

```sh
./setup/check-dotfiles.sh --all
```

After upgrading Kitty, scrcpy, Neovim, libvirt, or the desktop stack, run the
read-only workstation verification pass:

```sh
upgrade-verify
```

The check reports package versions, Kitty configuration errors, Kitty terminfo,
Neovim startup, scrcpy encoders, Android SDK availability, KVM access, and
libvirt domains/networks/storage pools. Warnings are diagnostic and do not
modify system or VM state.

Remove legacy shell experiments after the Wayle-first shell cleanup:

```sh
./setup/remove-legacy-shell-packages.sh
```

## Local Developer Health

Use the fast readiness check before focused work:

```sh
dev-health
dev-health --full
dotfiles-stale-check
project-profile status
```

- `dev-health` checks repo state, required tools, settings links, desktop services, local AI/RAG status, project profile state, and disk pressure.
- `dev-health --json` emits a machine-readable summary for menus and dashboards.
- `dev-health --full` also runs the deeper weekly health log.
- `dotfiles-stale-check` blocks stale retired-stack references from creeping back into docs/scripts.
- `project-profile` lists and launches common workspaces from one source of truth.
- `project-resume` restores the current project session, editor, and sidecar state from the focused repo.

If package install fails with `db.lck`, clear stale lock and retry:

```sh
sudo rm -f /var/lib/pacman/db.lck
```

The installer auto-skips packages that are not available in current repos.
NVIDIA packages are opt-in only; hardware detection alone does not change your current driver stack.
The bootstrap script automatically runs `setup/install-zsh-plugins.sh` unless you pass `--no-zsh-plugins`.
The bootstrap script automatically runs `setup/install-tmux-plugins.sh` unless you pass `--no-tmux-plugins`.

## Keybind highlights (Hyprland)

- `Super + Y`: primary workspace hub (`workspace-overview.sh`)
- `Super + W`: workspace/window overview switcher (direct Rofi list)
- `Super + Tab`: overview toggle (`hyprexpo` if loaded, otherwise fallback Rofi overview)
- `Super + Shift + Tab`: direct Rofi overview
- `Super + Space`: desktop command palette
- `Super + Shift + Space`: ultra-fast app launcher
- `Super + Ctrl + Space`: workspace/window search
- `Super + F1`: open keybind helper overlay (`hypr-binds.sh`)
- `Super + Ctrl + /`: open keybind helper overlay
- `Super + A` / `Super + /`: desktop command palette (press again to close)
- `Super + D`: desktop command palette alternate path
- `Ctrl + 1..0` in launcher/actions: quick-select top 10 rows
- `Enter` in launcher/actions: open/run selected row
- opener key again (`Super+Space` / `Super+A`): close launcher/actions
- `Super + \`: open/close the Scratch Hub for AI, runner/logs, DB, notes, Obsidian, terminal, browser DevTools, music, Sidecar actions, and the full scene
- `Super + Shift + \`: toggle the full work scene: main window + AI + runner/logs
- `Super + Alt + \`: toggle the AI scratchpad rooted in the focused repo; it starts the local runtime when needed and opens a project shell prepared for OpenCode/local models, falling back to the local chat scratchpad if the runtime is unavailable
- `Super + Ctrl + \`: toggle the project runner terminal rooted in the focused repo
- `Super + Ctrl + Alt + \`: toggle the database scratchpad
- `Super + Alt + S`: open the AI Workbench browser cockpit and report when its API is not ready
- `Super + B`: open Google Chrome
- `Super + ,`: open Settings Hub
- `Super + Shift + ,`: restore last minimized window
- `Super + Ctrl + ,`: quick settings toggle (notification sounds)
- `Super + Alt + ,`: open the Rofi settings editor
- `Super + Ctrl + Alt + ,`: apply per-app routing to focused app
- `Super + Alt + P`: open monitor control/recovery menu
- `Super + .`: fullscreen dev cheatsheet overlay (searchable + tabbed)
- `Super + F`: toggle floating on active window
- `Super + M`: maximize/unmaximize active window
- `Super + G`: cycle layout state (`dwindle -> master -> monocle`)
- `Super + Alt + G`: toggle tiling layout (`dwindle` <-> `master`)
- `Super + Shift + G`: toggle floating for the focused window
- ``Super + ` ``: show or hide Sidecar without moving windows
- ``Super + Ctrl + ` ``: stash the focused window in the Sidecar silently
- ``Super + Shift + ` ``: move the focused window to Sidecar and focus it there
- ``Super + Alt + ` ``: toggle Sidecar visibility without moving windows
- Sidecar windows tile dynamically inside the shelf when more than one window is parked there.
- `Super + arrows`: focus left/right/up/down
- `Alt + Tab` / `Alt + Shift + Tab`: cycle windows in current workspace
- `Super + Shift + arrows`: move the tiled window left/right/up/down
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
- `Super + Ctrl + Shift + Y`: apply theme pass (GTK + app refresh)
- `Super + Ctrl + Y`: switch panel to Wayle when installed
- `Super + Shift + Y`: toggle panel visibility only (show/hide current panel)
- `Super + Ctrl + Alt + Y`: toggle the current panel shell
- `Super + T`: toggle window group (tab-like stacks)
- `Super + Ctrl + T`: move active window out of group
- `Super + Alt + ;` / `Super + Alt + .`: previous/next tab in group
- `Fn + 2/3/4/5` (`XF86Launch2..5`): AI helper actions (`ask`, `clipboard`, `shell`, `debug`)
- `Super + Alt + 2`: freeform AI prompt with no preset base prompt
- `Super + Alt + 3/4/5`: fallback AI helper actions (`clipboard`, `shell`, `debug`)
- `Super + Ctrl + arrows`: move floating window by pixels
- `Super + Ctrl + Shift + arrows`: resize floating window
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
- Kitty shows a dashboard banner on startup and has dedicated tabs for scratch, logs, repo, AI, and clipboard history
- Tmux prefix is `Ctrl + Space`; pane navigation is `Prefix + h/j/k/l`
- Neovim config is in `nvim/` and bootstraps plugins with `lazy.nvim`
- `dotfiles-center`: one-stop control center for health, settings, project resume, launcher, and AI entrypoints

Notification panel now routes through the Wayle-first shell path with sticky System Hub controls for GPU/media/network/panel status, copy summary, widget toggles, and quick controls.

AI helper behavior:

- Uses `codex exec` in a dedicated Kitty window when available.
- Falls back to opening ChatGPT in browser if Codex CLI is unavailable.
- `ask` / `clipboard` / `shell` / `debug` prompts now inject compact local context (Arch + Hyprland + zsh, current project state, common aliases, and installed tools) instead of a generic one-paragraph preamble.
- `shell` and `debug` flows bias toward safer command blocks, validation steps, and machine-specific tooling such as `rg`, `fd`, `bat`, `eza`, `gh`, `dc`, and `k`.

## Apply changes

```sh
exec zsh
~/.config/hypr/scripts/hypr-reload-safe.sh
systemctl --user restart xdg-desktop-portal xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
~/.config/hypr/scripts/theme-pass.sh   # same reload flow as Super+Ctrl+Shift+Y
~/.config/hypr/scripts/panel-switch.sh show
~/.config/hypr/scripts/launcher.sh --warm-cache
```

If this machine was started from the old hyprlang config provider, restart your Hyprland session once so `hyprland.lua` becomes active.

When the Lua provider is active, `hypr-reload-safe.sh` validates `hyprland.lua` plus `hypr/conf/*.lua` before it calls `hyprctl reload`.

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

If you want the Wayle shell to refresh low-noise runtime status after GPU/theme changes, run:

```sh
~/.config/hypr/scripts/panel-switch.sh show
```

## 3-command reboot workflow

```sh
sudo ./setup/pre-reboot-apply.sh
sudo reboot
./setup/post-reboot-verify.sh
```

Logs are written to `logs/pre-reboot-latest.log` and `logs/post-reboot-latest.log`.
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

## Workstation reliability and virtualization

The canonical workstation controller replaces the older NVIDIA/login recovery
scripts. Apply user links first, inspect the health report, then apply the
root-owned profile:

```sh
workstationctl apply-user
workstationctl verify all
sudo ./setup/workstationctl apply-system
sudo reboot
```

The system stage keeps SDDM, launches the normal session through UWSM exactly
once, uses Intel for the compositor and NVIDIA for PRIME offload, makes
NetworkManager the sole network owner, installs the independent **Hyprland
Recovery (Intel, minimal)** session, and configures QEMU/KVM/libvirt. It creates
a rollback snapshot under `/var/lib/noxflow-workstation/backups`; restore it
with `sudo ./setup/workstationctl rollback`.

For a failed login, select the recovery session in SDDM or use a TTY and run:

```sh
workstationctl diagnose login
journalctl -b -u sddm --no-pager
```

Android shortcuts are `Super+Ctrl+I` for the emulator/ADB menu,
`Super+Ctrl+Shift+I` for Android Studio, and `Super+Alt+I` for Logcat. VS Code
is `Super+I`; the scratch terminal, logs, clipboard, browser, and AI-assisted
Git bindings remain available through the existing developer palette.

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
- The normal profile keeps NVIDIA DRM KMS enabled but does not open the NVIDIA
  card in Hyprland. On this firmware/driver combination NVIDIA DRM KMS is
  blacklisted because it blocks compositor initialization; CUDA/compute can use
  the base NVIDIA module, while graphical work and Android Emulator use Intel.
  The explicit iGPU-safe boot entry remains the kernel-level fallback.
- Wayle plus tray applets now own panel status, and `nm-applet` plus `blueman-applet` auto-start by default for menu-style Wi-Fi/Bluetooth controls.
  Set `HYPR_ENABLE_NM_APPLET=0` or `HYPR_ENABLE_BLUEMAN_APPLET=0` if you want the panel-only workflow instead.

If login freezes, collect evidence before changing the driver policy:

```sh
workstationctl diagnose login
```

If Hyprland reports `CBackend::create() failed`, use the recovery session and
run `workstationctl verify login`; DRM device selection is hardware-derived and
must not be replaced with a hard-coded card number.

If external HDMI/DP hotplug stops working on hybrid Intel + nouveau laptops, install `modprobe.d/nouveau-runtimepm.conf` into `/etc/modprobe.d/` and rebuild initramfs. That disables nouveau runtime PM so the dGPU keeps reporting external connectors after unplug/replug.

Do not stack the deprecated emergency scripts: they now delegate to the same
atomic `workstationctl apply-system` implementation.

## Hypr plugin setup

```sh
./setup/install-hypr-plugins.sh
```

This builds `hyprexpo` into `~/.local/share/hypr/plugins/hyprexpo/hyprexpo.so`.
`startup.sh` keeps it unloaded by default so Hyprland upgrades do not emit a
plugin version mismatch warning at login.
`Super + Tab` loads it on demand before falling back to the Rofi overview.

If you want the old eager-load behavior back, set:

```sh
export HYPR_LOAD_HYPREXPO_AT_STARTUP=1
```

Optional (can fail on some Hyprland versions):

```sh
./setup/install-hypr-plugins.sh --with-hyprspace
```

If reboot itself hangs and you need a guaranteed stable baseline, force iGPU-only boot:

```sh
sudo ./setup/force-igpu-safe-boot.sh
sudo sh -c 'echo 1 > /proc/sys/kernel/sysrq; echo s > /proc/sysrq-trigger; echo u > /proc/sysrq-trigger; echo b > /proc/sysrq-trigger'
```

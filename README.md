# Arch Workstation Dotfiles

This repository is designed to bootstrap a complete Arch + Hyprland workstation with reproducible shell, UI, and desktop behavior.

## Includes

- `zshrc`, `aliases.zsh`, `aliases.local.zsh`, `SHELL_CHEATSHEET.md`
- `atuin/config.toml` for consistent Atuin history UI/search defaults
- `docs/KEYBINDS.md` full keybind tables + Mermaid map
- `docs/RUNBOOK.md` 3-command pre/post reboot flow + log paths
- `hypr/` for Hyprland, Waybar, Rofi, swaync, wlogout, dunst, lockscreen, and helper scripts
- `hypr/eww/` for optional widget panel (Quick Deck)
- `kitty/kitty.conf` so new terminals always load login `zsh`
- `chrome/chrome-flags.conf` for smooth Chrome defaults on Wayland
- `theme/` for GTK, Qt5/Qt6, and Kvantum visual consistency
- `setup/` automation scripts for links and package installation

## Quick start

```sh
cd ~/Documents/code/dotfiles
./setup/bootstrap.sh --scripts-dir "$HOME/Documents/code/scripts"
```

That command:

- links shell files (`~/.zshrc`, cheat sheet)
- links Atuin config into `~/.config/atuin/config.toml`
- links Hyprland, Waybar, Rofi, and Kitty configs into `~/.config`
- links Eww and theme configs (`gtk`, `qt5ct`, `qt6ct`, `Kvantum`) into `~/.config`
- links swaync/wlogout/dunst configs into `~/.config`
- links Chrome flags to `~/.config/chrome-flags.conf`
- links your `~/Documents/code/scripts/bin/*` commands into `~/.local/bin`
- installs/updates optional zsh plugins under `~/.local/share/zsh/plugins`
- creates timestamped backups when replacing existing configs

## Full install (packages + links)

```sh
cd ~/Documents/code/dotfiles
./setup/bootstrap.sh --scripts-dir "$HOME/Documents/code/scripts" --install-packages --with-aur
```

NVIDIA users can force kernel/userspace driver packages:

```sh
./setup/bootstrap.sh --install-packages --with-aur --with-nvidia
```

You can run package install via `sudo` too; the script now delegates AUR operations to your normal user automatically.

## Package manifests

- `setup/pacman-packages.txt`: official repository packages
- `setup/nvidia-packages.txt`: NVIDIA kernel/userspace acceleration stack
- `setup/aur-packages.txt`: AUR packages (`google-chrome`, `pamac-aur`, `wlogout`, `eww`)
- `setup/install-hypr-plugins.sh`: installs Hypr plugins via `hyprpm` (`hyprexpo` by default)

Install packages only:

```sh
./setup/install-packages.sh --with-aur
```

If package install fails with `db.lck`, clear stale lock and retry:

```sh
sudo rm -f /var/lib/pacman/db.lck
```

The installer auto-skips packages that are not available in current repos.
The bootstrap script automatically runs `setup/install-zsh-plugins.sh` unless you pass `--no-zsh-plugins`.

## Keybind highlights (Hyprland)

- `Super + W`: workspace/window overview switcher (Rofi list)
- `Super + Tab`: Mission-Control style overview (`hyprexpo`)
- `Super + Shift + Tab`: force fallback Rofi overview
- `Super + Space`: app launcher (press again to close)
- `Super + A` / `Super + /`: quick actions (press again to close)
- `Ctrl + 1..0` in launcher/actions: quick-select top 10 rows
- `Enter` in launcher/actions: open/run selected row
- `Super + B`: open Google Chrome
- `Super + D`: quick actions (duplicate utility key)
- `Super + F`: toggle floating on active window
- `Super + G`: toggle tiling layout (`dwindle` <-> `master`)
- `Super + Shift + G`: toggle floating-grid workspace mode
- `Super + H/J/K/L`: focus left/down/up/right
- `Super + Shift + H/J/K/L`: move window left/down/up/right
- `Super + O`: wallpaper picker
- `Super + Shift + O`: next wallpaper
- `Super + N`: toggle notification panel
- `Super + Shift + N`: toggle DND
- `Super + Ctrl + N`: copy notification/status summary to clipboard
- `Super + I`: color picker (copies hex)
- `Super + Shift + I`: toggle night light (`hyprsunset`)
- `Super + Ctrl + R`: toggle screen recording (`wf-recorder`)
- `Super + Shift + T`: screenshot OCR -> clipboard (`ocr-capture.sh`)
- `Super + Y`: toggle Eww widget panel
- `Super + Shift + Y`: apply theme pass (GTK + Qt + Kvantum)
- `Super + Ctrl + Y`: toggle panel engine (`waybar` <-> `hyprpanel`, if installed)
- `Super + Alt + Y`: toggle panel visibility only (show/hide current panel)
- `Super + Ctrl + Shift + Y`: toggle desktop widgets (above wallpaper / below windows)
- `Super + T`: toggle window group (tab-like stacks)
- `Super + Ctrl + T`: move active window out of group
- `Super + ,` / `Super + .`: previous/next tab in group
- `Fn + 2/3/4/5` (`XF86Launch2..5`): AI helper actions (`ask`, `clipboard`, `shell`, `debug`)
- `Super + Alt + 2/3/4/5`: fallback AI helper actions
- `Super + Ctrl + H/J/K/L` (or arrows): move floating window
- `Super + Ctrl + Shift + H/J/K/L` (or arrows): resize floating window
- `Super + [ / ]`: previous/next workspace

Full keybind tables: `docs/KEYBINDS.md`

## Shell UX highlights

- `Ctrl + R`: Atuin fuzzy history picker (bound in emacs + vi insert keymaps)
- `Alt + C`: fuzzy zoxide directory jump
- `zsh-vi-mode` is auto-loaded when installed via `setup/install-zsh-plugins.sh`

## Optional UI stack (AGS/HyprPanel)

```sh
yay -S --needed aylurs-gtk-shell hyprpanel
```

Then toggle panels with `Super + Ctrl + Y`.

Notification panel now includes sticky "System Hub" controls (GPU/media/network/panel status, copy summary, widget toggles, and quick controls) via SwayNC.

## Apply changes

```sh
exec zsh
hyprctl reload
systemctl --user restart xdg-desktop-portal xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
~/.config/hypr/scripts/theme-pass.sh
~/.config/hypr/scripts/restart-waybar.sh
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

## NVIDIA stability notes (hybrid laptops)

- If `modinfo -F license nvidia` prints `Dual MIT/GPL`, you are running NVIDIA open kernel modules (`nvidia-open-dkms`).
- If `modinfo -F license nvidia` prints `NVIDIA`, you are running proprietary modules.
- On current Arch repos (since the March 3, 2026 NVIDIA 570+ packaging change), `nvidia-dkms` is not provided and `nvidia-open-dkms` is the official kernel-module package.
- On this setup, forcing `nvidia_drm` modeset can trigger login/shutdown hangs on some hybrid laptops.
- The included safe profile keeps boot stable by blacklisting `nvidia_drm` during compositor startup.
- `nm-applet` auto-start is disabled by default to avoid duplicate tray-registration warnings in Waybar.
  Toggle it on demand with `~/.config/hypr/scripts/nm-applet-toggle.sh`.

If login freezes and `nvidia-persistenced` times out, run:

```sh
sudo ./setup/fix-nvidia-proprietary-hybrid.sh
sudo reboot
```

If Hyprland crashes at login with `CBackend::create() failed`, check `AQ_DRM_DEVICES` in your Hyprland config. Do not use `/dev/dri/by-path/pci-0000:...` there because `AQ_DRM_DEVICES` is colon-separated; use `/dev/dri/cardN` instead.

If your system hard-freezes during login with kernel messages about `kworker`, `nv_drm_dev_load`, or `nvidia-persiste`, use:

```sh
sudo ./setup/emergency-hypr-login-fix.sh
sudo reboot
```

## Hypr plugin setup

```sh
./setup/install-hypr-plugins.sh
```

Optional (can fail on some Hyprland versions):

```sh
./setup/install-hypr-plugins.sh --with-hyprspace
```

If `hyprpm` was previously run as root and plugin updates fail:

```sh
sudo chown -R "$USER:$USER" /var/cache/hyprpm/"$USER"
```

If reboot itself hangs and you need a guaranteed stable baseline, force iGPU-only boot:

```sh
sudo ./setup/force-igpu-safe-boot.sh
sudo sh -c 'echo 1 > /proc/sys/kernel/sysrq; echo s > /proc/sysrq-trigger; echo u > /proc/sysrq-trigger; echo b > /proc/sysrq-trigger'
```

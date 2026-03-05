# NVIDIA + Hyprland Runbook

Use this when you want one clean apply/verify flow with persistent logs.

## 3 Commands Only

```bash
sudo ~/Documents/code/dotfiles/setup/pre-reboot-apply.sh
sudo reboot
~/Documents/code/dotfiles/setup/post-reboot-verify.sh
```

## One-time Safety Setup (recommended)

```bash
sudo ~/Documents/code/dotfiles/setup/configure-timeshift.sh
```

This enables daily Timeshift automation and keeps only the latest 5 daily snapshots.

## Flow

```mermaid
flowchart TD
  A[pre-reboot-apply.sh] --> B[Writes pre-reboot log]
  B --> C[Reboot]
  C --> D[post-reboot-verify.sh]
  D --> E[Writes post-reboot log + PASS/WARN]
```

## Log Locations

- `~/Documents/code/dotfiles/logs/pre-reboot-latest.log`
- `~/Documents/code/dotfiles/logs/post-reboot-latest.log`
- `~/.local/state/noxflow/waybar.log`
- `~/Documents/code/dotfiles/logs/health-latest.log`

## What The Scripts Check

| Script | Purpose |
|---|---|
| `pre-reboot-apply.sh` | Normalizes boot args, sets default entry, ensures helper packages, snapshots current boot config |
| `post-reboot-verify.sh` | Verifies NVIDIA runtime, Vulkan/VA-API, Hypr plugin state, browser default, zsh keybinds, and boot hang signatures |
| `weekly-health-check.sh` | Weekly PASS/FAIL audit: portals, GPU/VAAPI/Vulkan, journal errors grouped by service, disk/SMART state |

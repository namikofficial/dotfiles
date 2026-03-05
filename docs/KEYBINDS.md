# Hyprland Keybinds

This is the canonical keybind map for the repo.

## Map Overview

```mermaid
flowchart LR
  SUPER[SUPER] --> Launch[Launch / Session]
  SUPER --> Window[Window + Layout]
  SUPER --> Move[Move + Resize]
  SUPER --> WS[Workspace]
  SUPER --> Media[Media + Capture]
  FN[Fn / XF86Launch2..5] --> AI[AI Helper Actions]
```

## Launch / Session

| Keybind | Action | Script/Target |
|---|---|---|
| `Super + Return` | Open terminal | `kitty` |
| `Super + E` | Open file manager | `dolphin` |
| `Super + Space` | App launcher (press again to close) | `~/.config/hypr/scripts/launcher.sh` |
| `Super + A` or `Super + /` | Quick actions (press again to close) | `quick-actions.sh` |
| `Super + W` | Workspace overview (Rofi) | `workspace-overview.sh` |
| `Super + Tab` | Mission control overview | `hyprexpo:expo toggle` |
| `Super + Shift + Tab` | Fallback overview | `workspace-overview.sh` |
| `Super + B` | Open browser | `google-chrome-stable` |
| `Super + N` | Toggle notification panel | `swaync-client -t` |
| `Super + Shift + N` | Toggle DND | `swaync-client -d` |
| `Super + Ctrl + N` | Copy notification/status summary | `notification-summary.sh copy` |
| `Super + D` | Quick actions menu (duplicate launcher utility key) | `quick-actions.sh` |
| `Super + Y` | Toggle Eww panel | `eww-toggle.sh` |
| `Super + Ctrl + Y` | Toggle Waybar/HyprPanel | `panel-switch.sh toggle` |
| `Super + Alt + Y` | Toggle panel visibility (view only) | `panel-switch.sh toggle-view` |
| `Super + Ctrl + Shift + Y` | Toggle desktop widgets (behind windows) | `eww-desktop-toggle.sh` |
| `Super + Escape` | Power menu | `power-menu.sh` |
| `Super + L` | Lock screen | `lock.sh` |

## Window / Layout

| Keybind | Action |
|---|---|
| `Super + F` | Toggle floating |
| `Super + M` | Maximize / unmaximize (fullscreen mode 1) |
| `Super + Shift + F` | Fullscreen (mode 1) |
| `Super + Ctrl + F` | Fullscreen (mode 0) |
| `Super + G` | Toggle `dwindle` / `master` |
| `Super + Shift + G` | Toggle floating-grid |
| `Super + Ctrl + G` | Force `master` |
| `Super + Ctrl + Shift + G` | Force `dwindle` |
| `Super + T` | Toggle window group (tab-like stack) |
| `Super + Ctrl + T` | Move active window out of group |
| `Super + ,` / `Super + .` | Prev/next tab in group |

## Focus / Move / Resize

| Keybind | Action |
|---|---|
| `Super + H/J/K/L` or arrows | Move focus |
| `Alt + Tab` / `Alt + Shift + Tab` | Cycle windows in current workspace |
| `Super + Shift + H/J/K/L` or arrows | Move window |
| `Super + Ctrl + H/J/K/L` or arrows | Move floating window |
| `Super + Ctrl + Shift + H/J/K/L` or arrows | Resize floating window |

## Workspace

| Keybind | Action |
|---|---|
| `Super + 1..0` | Jump to workspace 1..10 |
| `Super + Shift + 1..0` | Move active window to workspace |
| `Super + [` / `Super + ]` | Prev / next workspace |
| `Super + mouse wheel` | Prev / next workspace |
| `Super + grave` | Toggle scratchpad workspace |

## Media / Screen / Clipboard

| Keybind | Action |
|---|---|
| `Super + Ctrl + V` | Clipboard history picker |
| `Super + Shift + S` | Screenshot area |
| `Super + Ctrl + Shift + S` | Screenshot full |
| `Super + Shift + T` | OCR selected area -> clipboard |
| `Super + Ctrl + R` | Toggle screen recording |
| `Super + I` | Color picker |
| `Super + Shift + I` | Night light toggle |
| `XF86Audio*` keys | Volume/media controls |
| `XF86MonBrightness*` keys | Brightness controls |

## AI Helper

| Keybind | Action | Mode |
|---|---|---|
| `Fn + 2` / `XF86Launch2` | Ask AI | `ask` |
| `Fn + 3` / `XF86Launch3` | Summarize clipboard | `clip` |
| `Fn + 4` / `XF86Launch4` | Generate shell command | `shell` |
| `Fn + 5` / `XF86Launch5` | Debug clipboard error | `debug` |
| `Super + Alt + 2..5` | Fallback AI binds | same modes |

## Shell UX

| Key | Action |
|---|---|
| `Ctrl + R` | Atuin history picker |
| `Alt + C` | Fuzzy zoxide jump |
| `Esc` | Enter `zsh-vi-mode` normal mode |

## Rofi Menus (Launcher + Quick Actions)

| Key | Action |
|---|---|
| `Ctrl + 1..0` | Quick-select row 1..10 |
| `Enter` | Run/open selected item |

## Notification Panel Contents

```mermaid
flowchart TD
  A[Notifications Panel] --> B[System Hub Status Grid]
  A --> C[Quick Action Grid]
  A --> D[DND + MPRIS + Volume + Brightness]
  A --> E[Notification List]
```

| Section | What it shows |
|---|---|
| Status grid | GPU active, media active, network online, panel visible |
| Actions grid | Clear all, copy status, DND toggle, desktop widgets toggle, net applet, panel view, restart bar |
| Controls | DND widget, media (MPRIS), volume slider, brightness slider |

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
| `Super + E` | Open file manager | `kitty --class yazi -e yazi` |
| `Super + Space` | Desktop command palette | `desktop-palette.sh` |
| `Super + Shift + Space` | Fast app launcher | `launcher.sh --fast` |
| `Super + Ctrl + Space` | Window/workspace search | `workspace-overview.sh` |
| `Super + .` | Fullscreen dev cheatsheet overlay (searchable tabs) | `dev-cheatsheet.sh` |
| `Super + F1` | Keybind cheat sheet overlay | `hypr-binds.sh` |
| `Super + A` or `Super + /` | Desktop command palette | `desktop-palette.sh` |
| `Super + Ctrl + /` | Keybind cheat sheet overlay | `hypr-binds.sh` |
| `Super + Y` | Workspace hub (primary path) | `workspace-overview.sh` |
| `Super + W` | Workspace overview (direct Rofi path) | `workspace-overview.sh` |
| `Super + Tab` | Overview toggle (`hyprexpo` if available, Rofi fallback) | `super-tab-overview.sh` |
| `Super + Shift + Tab` | Fallback overview | `workspace-overview.sh` |
| `Super + B` | Open browser | `google-chrome-stable` |
| `Super + \` | Scratch Hub for AI, runner/logs, DB, notes, tools, Sidecar, and scene | `scratchpad-manager.sh menu` |
| `Super + Shift + \` | Toggle full work scene | `scratchpad-manager.sh toggle scene` |
| `Super + Alt + \` | AI workspace shell with runtime startup fallback | `scratchpad-manager.sh launch ai` |
| `Super + Ctrl + \` | Logs scratchpad | `scratchpad-manager.sh launch logs` |
| `Super + Ctrl + Alt + \` | Database scratchpad | `scratchpad-manager.sh launch db` |
| ``Super + ` `` | Show or hide Sidecar without moving windows | `sidepanel.sh toggle` |
| ``Super + Shift + ` `` | Move focused window to Sidecar and focus it there | `sidepanel.sh send` |
| ``Super + Ctrl + ` `` | Stash active window into Sidecar | `sidepanel.sh stash` |
| ``Super + Alt + ` `` | Toggle Sidecar visibility | `sidepanel.sh toggle` |
| Sidecar multi-window | Parked windows tile dynamically inside the shelf | `sidepanel.sh` |
| `Super + N` | Toggle notification panel | `notif-center-toggle.sh` |
| `Super + Alt + N` | Toggle DND | `notif-dnd-toggle.sh` |
| `Super + Ctrl + N` | Copy notification/status summary | `notification-summary.sh copy` |
| `Super + Shift + N` | Open notes folder | `open-notes.sh` |
| `Super + Alt + E` | Open notes folder | `open-notes.sh` |
| `Super + D` | Desktop command palette | `desktop-palette.sh` |
| `Super + ,` | Open Settings Hub | `settings-hub.sh` |
| `Super + Shift + ,` | Restore last minimized window | `minimize-window.sh restore` |
| `Super + Ctrl + ,` | Quick settings toggle (notification sounds) | `settings-hub.sh quick` |
| `Super + Alt + ,` | Open Rofi settings editor | `settings/editor.sh` |
| `Super + Ctrl + Alt + ,` | Apply per-app routing to focused app | `app-routing-apply-focused.sh` |
| `Super + Ctrl + Y` | Switch panel to Wayle when installed | `panel-switch.sh wayle` |
| `Super + Shift + Y` | Toggle panel visibility (view only) | `panel-switch.sh toggle-view` |
| `Super + Alt + Y` | Toggle panel visibility (view only) | `panel-switch.sh toggle-view` |
| `Super + Ctrl + Alt + Y` | Toggle panel | `panel-switch.sh toggle` |
| `Super + Escape` | Power menu | `power-menu.sh` |
| `Super + Ctrl + L` | Lock screen | `lock.sh` |

## Window / Layout

| Keybind | Action |
|---|---|
| `Super + F` | Toggle floating |
| `Super + M` | Maximize / unmaximize |
| `Super + Shift + F` | Maximize / unmaximize |
| `Super + Ctrl + F` | Fullscreen / unfullscreen |
| `Super + G` | Cycle layout state (`dwindle -> master -> monocle`) |
| `Super + Alt + G` | Toggle `dwindle` / `master` |
| `Super + Shift + G` | Toggle focused window floating |
| `Super + Ctrl + G` | Force `master` |
| `Super + Ctrl + Shift + G` | Force `dwindle` |
| `Super + Ctrl + Alt + Shift + G` | Monocle-style focused/maximized mode |
| `Super + T` | Toggle window group (tab-like stack) |
| `Super + Ctrl + T` | Move active window out of group |
| `Super + Alt + ;` / `Super + Alt + .` | Prev/next tab in group |

## Focus / Move / Resize

| Keybind | Action |
|---|---|
| `Super + arrows` | Move focus |
| `Alt + Tab` / `Alt + Shift + Tab` | Cycle windows in current workspace |
| `Super + Shift + arrows` | Move tiled window in that direction |
| `Super + Ctrl + arrows` | Move floating window by pixels |
| `Super + Ctrl + Shift + arrows` | Resize floating window |

## Workspace

| Keybind | Action |
|---|---|
| `Super + 1..0` | Jump to workspace 1..10 |
| `Super + Shift + 1..0` | Move active window to workspace |
| `Super + Ctrl + 0` | Open/focus telemetry dashboard on workspace 10 (`0` key slot) |
| `Super + Ctrl + Shift + 0` | Reset telemetry dashboard session and reopen it |
| `Super + Ctrl + 9` | Open logs workspace launcher (workspace 9) |
| `Super + Ctrl + Shift + 9` | Open logs workspace stack (journal + panel logs) |
| `Super + [` / `Super + ]` | Prev / next workspace |
| `Super + mouse wheel` | Prev / next workspace |

## Media / Screen / Clipboard

| Keybind | Action |
|---|---|
| `Super + Ctrl + V` | Clipboard history browser |
| `Super + Shift + V` | Toggle floating clipboard browser with preview, filters, and pinning |
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
| `Super + Alt + 2` | Freeform AI prompt | `raw` |
| `Super + Alt + 3` | Summarize clipboard | `clip` |
| `Super + Alt + 4` | Generate shell command | `shell` |
| `Super + Alt + 5` | Debug clipboard error | `debug` |

## Shell UX

| Key | Action |
|---|---|
| `Ctrl + R` | Atuin history picker |
| `Alt + C` | Fuzzy zoxide jump |
| `Alt + Left` / `Alt + Right` | Move by word in Kitty/zsh |
| `Ctrl + Left` / `Ctrl + Right` | Move by word in Kitty/zsh |
| `Alt + Backspace` | Delete previous word in Kitty/zsh |
| `Esc` | Enter `zsh-vi-mode` normal mode |

## Tmux Keymaps

| Keybind | Action |
|---|---|
| `Ctrl + Space` | Tmux prefix |
| `Prefix + c` | New window (current directory) |
| `Prefix + -` / `Prefix + \|` | Split horizontal / vertical |
| `Prefix + h/j/k/l` | Focus pane left/down/up/right |
| `Prefix + H/J/K/L` | Resize pane |
| `Prefix + [` | Enter copy mode (vi) |
| `copy-mode: v` then `y` | Select and copy to clipboard (`wl-copy`) |
| `Prefix + r` | Reload `~/.tmux.conf` |

## Kitty Terminal Keymaps

| Keybind | Action |
|---|---|
| `Startup` | Dashboard banner with system/repo context and quick actions |
| `Ctrl + Shift + D` | Open dashboard tab |
| `Ctrl + Shift + 1` | Open scratch shell tab |
| `Ctrl + Shift + 2` | Open live logs tab |
| `Ctrl + Shift + 3` | Open repo tab |
| `Ctrl + Shift + 4` | Open AI tab |
| `Ctrl + Shift + Y` | Clipboard history picker |
| `Ctrl + Shift + T` | New tab (inherits current working directory) |
| `Ctrl + Shift + Q` | Close current split/window |
| `Ctrl + Shift + W` | Close current tab |
| `Ctrl + Shift + [` / `Ctrl + Shift + ]` | Previous / next tab |
| `Ctrl + Shift + Enter` | New terminal window (same cwd) |
| `Ctrl + Shift + O` / `Ctrl + Shift + E` | Split horizontal / vertical |
| `Ctrl + Shift + H/J/K/L` | Focus left/down/up/right split |
| `Alt + Left` / `Alt + Right` | Backward/forward word movement in terminal input |
| `Ctrl + Left` / `Ctrl + Right` | Backward/forward word movement in terminal input |
| `Alt + Backspace` | Delete previous word in terminal input |
| `Ctrl + Shift + Alt + H/J/K/L` | Resize split (narrow/short/tall/wide) |
| `Ctrl + Shift + F5` | Reload kitty config |
| `Super + Ctrl + Shift + Y` | Reload theme, Kitty, Hyprland, panel, and caches |
| `Super + Shift + O` | Switch to next wallpaper |
| Select text | Auto-copy to clipboard (`copy_on_select`) |

## Rofi Menus (Launcher + Quick Actions)

| Key | Action |
|---|---|
| `Ctrl + 1..0` | Quick-select row 1..10 |
| `Enter` | Run/open selected item |
| `Esc` or opener key again | Close menu (`Super+Space` / `Super+A`) |

## Workspace Hub In-Menu Hotkeys

| Key | Action |
|---|---|
| `Ctrl + Alt + R` | Rename selected workspace |
| `Ctrl + Alt + Backspace` | Clear selected workspace label |
| `Ctrl + Alt + F` | Toggle selected workspace favorite |
| `Ctrl + Alt + S` | Show overview shortcuts panel |
| `Ctrl + Alt + M` | Move selected window to workspace |
| `Ctrl + Alt + O` | Move selected window + follow |
| `Ctrl + Alt + P` | Send selected window to Sidecar |

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

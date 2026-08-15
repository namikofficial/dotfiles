# 07 — Test Matrix

**Date:** 2026-07-31
**Branch:** `codex/unified-shell-redesign-20260728`

Run against the real running Hyprland session. Use logs and screenshots, not
assumptions. Each row: **how to run**, **expected**, **pass/fail**.

Static checks (run first, before any live testing):

```sh
./setup/release-gate.sh                      # full gate (Rust, QML, units, live)
./setup/check-shell.sh --all                # shellcheck severity=error + shfmt
cargo test --workspace                       # Rust tests
node shell/noxflow/tests/test_protocol.js    # QML protocol fixtures
qmllint -I shell/noxflow $(find shell/noxflow -name '*.qml')   # QML lint
setup/check-keybind-docs.sh                 # keybind docs current
systemd-analyze --user verify systemd/user/*.service
```

---

## 1. Shell lifecycle

| # | Test | How | Expected |
|---|---|---|---|
| 1 | Cold login | Log out → log in | Exactly 1 quickshell, 0 wayle, bar + island visible |
| 2 | Quickshell restart | `systemctl --user restart noxflow-shell.service` | No duplicate instance; journal shows clean start |
| 3 | Hyprland reload | `hyprctl reload` | No config errors; shell surfaces persist |
| 4 | Service health | `systemctl --user status noxd noxflow-shell` | Both active; no crash loops |
| 5 | Daemon down | `systemctl --user stop noxd` → open panels | Panels degrade gracefully (degraded providers), no crash |

## 2. Morph engine (M6/M7)

| # | Test | How | Expected |
|---|---|---|---|
| 6 | Open calendar from clock | Click clock pill | Frame grows from clock position; radius interpolates; content fades in at ~40% |
| 7 | Open control centre from volume | Click volume pill | Morphs from the volume chip |
| 8 | Rapid open/close | `noxctl panel toggle calendar` ×3 fast | Retargets; settles to final state; no clipping |
| 9 | Swap panels mid-open | Open calendar → immediately open notifications | Crossfades; frame retargets; no double windows |
| 10 | Close to chip | Close any panel | Compact origin glyph appears in shrinking frame; window height retained until frame collapses |
| 11 | Reduced motion | Set `reduceMotion` | All geometry animation skipped; instant appear/disappear |
| 12 | Click outside | Open panel → click desktop | Panel closes (click-through outside surface) |

## 3. Keybinds (M11)

| # | Test | How | Expected |
|---|---|---|---|
| 13 | Control centre | `SUPER+C` | Opens; `SUPER+CTRL+C` centers window |
| 14 | Media | `SUPER+M` | Media panel; `SUPER+SHIFT+F` fullscreen maximized |
| 15 | Clipboard | `SUPER+V` | Clipboard panel; enter copies, delete removes |
| 16 | Wallpaper | `SUPER+W` | Wallpaper panel grid; apply changes wallpaper |
| 17 | Quick Share | `SUPER+S` | Left-side panel opens; daemon status honest |
| 18 | Notifications | `SUPER+N` | Notification centre |
| 19 | Escape chain | Open panel → Escape | Closes topmost; second Escape does nothing |

## 4. ScrollOverview (M10)

| # | Test | How | Expected |
|---|---|---|---|
| 20 | Plugin loaded | `hyprctl plugin list` | scrolloverview present |
| 21 | Toggle | `SUPER+TAB` | Overview opens/closes |
| 22 | Keyboard nav | arrows/hjkl in overview | Selection moves |
| 23 | Select | Enter/click | Focuses workspace/window; overview closes |
| 24 | Close window | middle-click / Delete | Closes hovered window |
| 25 | Gesture | 3-finger up | Opens overview |
| 26 | Submap | In overview, workspace keys | Universal binds still work |
| 27 | Rebuild path | `setup/scrolloverview-rebuild.sh --source` | Builds + loads |

## 5. Quick Share (M12)

| # | Test | How | Expected |
|---|---|---|---|
| 28 | Daemon down | Stop localsend → open panel | "LocalSend not running" + launch button |
| 29 | Daemon up | Start localsend → refresh | "Nearby sharing ready" + alias |
| 30 | Send intent | Click "Share files…" | LocalSend opens; history records intent truthfully |
| 31 | Receive | Send from phone | LocalSend popup handles accept/decline (app-owned) |

## 6. Wallpaper/theme (M13)

| # | Test | How | Expected |
|---|---|---|---|
| 32 | Grid loads | `SUPER+W` | Thumbnails async-load; no flash of broken images |
| 33 | Apply | Click wallpaper | Wallpaper changes; matugen runs; theme propagates |
| 34 | Theme pass | Theme pass button | GTK/kitty/shell refreshed |
| 35 | Empty dirs | Point WALLPAPER_DIRS at empty dir | Honest empty state |
| 36 | Apply failure | Set unwritable path | Error surfaces; no fake success |

## 7. Regression (pre-redesign bugs)

| # | Test | How | Expected |
|---|---|---|---|
| 37 | No volume OSD on login | Log out → log in | No volume/brightness island flash |
| 38 | Minimize/restore | `SUPER+SHIFT+M` then `SUPER+ALT+M` | Window returns to original workspace |
| 39 | Group + minimize | Group 2 windows, minimize, restore | Group intact; window returns |
| 40 | Fullscreen restore | Minimize fullscreen window, restore | Fullscreen restored |
| 40a | Workspace focus feedback | Switch rapidly by click and keyboard | Target chip updates immediately, then confirms without flicker |
| 40b | Active app chip | Focus windows and change a tab title | Active chip shows the app marker/name; tooltip title stays current |
| 40c | Empty and multi-monitor workspaces | Focus empty workspaces on each monitor | Each monitor retains its own active chip; no workspace list disappears |

## 8. System

| # | Test | How | Expected |
|---|---|---|---|
| 41 | Fullscreen app | Open fullscreen game/app | Shell layer surfaces don't block input; panels still open above |
| 42 | Multi-monitor | Plug external monitor | Panels per-screen; morph from correct trigger |
| 43 | Mixed scale | Different monitor scales | Panels sized correctly per monitor |
| 44 | Suspend/resume | `systemctl suspend` → wake | Shell recovers; no stale state |
| 45 | Backend crash | Kill noxd → restart | Providers recover; shell reconnects |
| 46 | Memory | Open/close all panels 20× | No unbounded growth (watch `ps` RSS) |
| 47 | QML warnings | `journalctl --user -u noxflow-shell` | Zero warnings/errors (except benign FileView first-run) |
| 48 | Application opacity | Compare focused/background apps on light and dark wallpapers | Focused app is 0.96, inactive apps 0.84, text remains readable |
| 49 | Opaque stability exception | Focus/unfocus Android Studio | Android Studio remains fully opaque |

---

## Log locations

- Shell: `journalctl --user -u noxflow-shell --no-pager`
- Daemon: `journalctl --user -u noxd --no-pager`
- Hyprland: `journalctl --user -u hyprland --no-pager` or `/tmp/hypr/$(ls /tmp/hypr | head -1)/hyprland.log`
- LocalSend: `journalctl --user -u localsend --no-pager`

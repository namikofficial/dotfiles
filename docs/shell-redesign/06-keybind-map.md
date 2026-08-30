# 06 — Keybind Map

**Date:** 2026-07-31
Canonical source: `hypr/conf/40-binds-launch.lua`, `50-binds-layout.lua`,
`60-binds-media.lua`, `95-plugins.lua`. Generated doc: `docs/KEYBINDS.md`.

## Shell surfaces (mental model)

| Bind | Surface | Notes |
|---|---|---|
| `SUPER+TAB` | ScrollOverview (plugin) | falls back to legacy script if plugin absent |
| `SUPER+SPACE` | Launcher | exclusive overlay |
| `SUPER+C` | Control centre | `window.center()` moved to `SUPER+CTRL+C` |
| `SUPER+N` | Notification centre | |
| `SUPER+M` | Media panel | fullscreen maximized stays `SUPER+SHIFT+F` |
| `SUPER+V` | Clipboard panel | new |
| `SUPER+S` | Quick Share (left panel) | new |
| `SUPER+W` | Wallpaper & theme panel | new; `SUPER+O`/`SUPER+SHIFT+O` = rofi pick/next |
| `SUPER+ESC` | Power/session menu | |

## ScrollOverview submap (active while overview is open)

| Key | Action |
|---|---|
| arrows / hjkl | navigate |
| Enter / Space | select workspace/window |
| Delete | close hovered window |
| Escape | close overview |
| left-click | select under cursor + close |
| middle-click | close window under cursor |

## Window management (unchanged)

| Bind | Action |
|---|---|
| `SUPER+T` | window group toggle |
| `SUPER+ALT+.` / `SUPER+ALT+;` | group next / prev |
| `SUPER+CTRL+T` | move out of group |
| `SUPER+SHIFT+M` | minimize to special:minimized |
| `SUPER+ALT+M` | restore newest minimized |
| `SUPER+CTRL+C` | center window (moved from SUPER+C) |
| `SUPER+SHIFT+F` / `SUPER+CTRL+F` | fullscreen maximized / fullscreen |
| `SUPER+SHIFT+Q` | close window |

## Conflict resolutions applied (M11)

| Conflict | Resolution |
|---|---|
| `SUPER+C` was window center | → `SUPER+CTRL+C`; `SUPER+C` = control centre |
| `SUPER+M` was fullscreen maximized | → stays only on `SUPER+SHIFT+F`; `SUPER+M` = media |
| `SUPER+W` was free | → wallpaper panel |
| `SUPER+V`/`SUPER+S` were free | → clipboard / quick share |
| `SUPER+CTRL+V`/`SUPER+SHIFT+V` | kept as cliphist rofi fallbacks |
| `SUPER+SHIFT+S` | kept as capture (unchanged) |

## Verification

```sh
setup/check-keybind-docs.sh   # KEYBINDS.md matches the Lua config
hyprctl binds                 # live bind list
```

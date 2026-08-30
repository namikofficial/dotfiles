# 04 — Implementation Plan

**Date:** 2026-07-31
**Branch:** `codex/unified-shell-redesign-20260728`

## Order executed (all committed)

| Module | Commit | Deliverable |
|---|---|---|
| M0 baseline | `107c884` | `00-baseline.md` |
| M1 OSD flash fix | `e711a3b` | hasSynced guard in NoxIsland |
| M2 minimize/restore | `7dafde8` | group-aware, workspace-id restore |
| M3 service lifecycle | `a8ce9e7` | single-start, no dual-shell race |
| M4 reference analysis | `70f6b4f` | `02-reference-analysis.md`, REFERENCES.md ADOPT |
| M5 design contract | `29c2ab4` | `03-design-contract.md` |
| M6+M7 state+morph | `e883e4c` | PanelController + MorphSurface rewrite |
| M8 bar origin | `e1be6f9` | origin chip mirroring |
| M10 overview plugin | `854ce15` | 95-plugins.lua, delete QML overview, rebuild helper |
| M11 keybinds+clipboard | `1e5a20c` | SUPER+C/M/V/S/W, ClipboardPanel, config guard fix |
| M12+M9 quick share | `575442b` | TransferService, QuickSharePanel, localsend.service |
| M13 wallpaper | `97410e3` | WallpaperModel + WallpaperPanel |
| M15+M16 docs | (this commit) | test matrix, rollback, dependency matrix, keybind map, limitations, README |

## Remaining / low priority

- **M14** panel polish (notification/media/system monitor) — existing panels
  are functional; polish deferred as non-blocking.

## Post-merge user actions

1. Install the scroll-overview plugin (sudo): see `setup/scrolloverview-rebuild.sh`
   and the known hyprpm state-store fix (`sudo rm -rf /var/cache/hyprpm/<user>`).
2. `make install-systemd` + `systemctl --user enable --now localsend.service`.
3. Restart shell: `systemctl --user restart noxflow-shell.service`.
4. Run the test matrix (`07-test-matrix.md`).

#!/usr/bin/env bash
# Static regression checks for the panel lifecycle + settings hydration
# contract (NF-03 / NF-04 / NF-05 / NF-06).
#
# Companion to test_panel_lifecycle.js. The JS file exercises the JS-extractable
# logic end-to-end; this script catches the patterns that aren't reasonable to
# mirror in Node — service unit coverage, daemon response plumbing and the
# NF-06 supported-operation requirement.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONTROLLER="$ROOT/shell/noxflow/core/PanelController.qml"
SHELL="$ROOT/shell/noxflow/shell.qml"
SETTINGS="$ROOT/shell/noxflow/surfaces/settings/SettingsPanel.qml"
TOKENS="$ROOT/shell/noxflow/theme/Tokens.qml"
NOXD_CLIENT="$ROOT/shell/noxflow/NoxdClient.qml"
SERVICE="$ROOT/systemd/user/noxflow-shell.service"

fail() { printf 'forbidden: %s\n' "$*" >&2; exit 1; }

# ── NF-06: shell service must not pretend to support reload ──
# systemd reports CanReload=no for a unit with no ExecReload / ReloadSignal.
# SettingsPanel must not issue a silent reload — that fails with no output.
if grep -Eq '^[[:space:]]*ExecReload[[:space:]]*=' "$SERVICE"; then
    fail "noxflow-shell.service must not declare ExecReload (CanReload=no)"
fi
if grep -Eq '^[[:space:]]*ReloadSignal[[:space:]]*=' "$SERVICE"; then
    fail "noxflow-shell.service must not declare ReloadSignal (CanReload=no)"
fi

# ── NF-06: SettingsPanel must use the verified restart operation, not reload ──
if grep -Fq 'Quickshell.exec("systemctl --user reload noxflow-shell")' "$SETTINGS"; then
    fail "SettingsPanel must not silently reload noxflow-shell (CanReload=no)"
fi
if ! grep -Fq '"restart"' "$SETTINGS"; then
    fail "SettingsPanel must use systemctl restart for the shell"
fi
if ! grep -Fq 'maintenanceProc' "$SETTINGS"; then
    fail "SettingsPanel must wire maintenance commands through Process (visible exit code)"
fi
if ! grep -Fq 'onExited' "$SETTINGS"; then
    fail "SettingsPanel must observe onExited to surface success/failure"
fi
if grep -Fq 'noxflow-gallery' "$SETTINGS"; then
    fail "SettingsPanel must not reference noxflow-gallery (no such unit exists on disk)"
fi

# ── NF-03: PanelController must define the new lifecycle helpers ──
for fn in unregisterPanel pruneDestroyed isDestroyed; do
    if ! grep -Fq "function $fn(" "$CONTROLLER"; then
        fail "PanelController.qml must define $fn()"
    fi
done

# ── NF-03: open must be idempotent ──
# Extract the idempotent branch — must NOT call close() inside it.
IDEMPOTENT="$(awk '/function open\(name/,/^    \}$/' "$CONTROLLER")"
if ! grep -Eq 'activePanel === name && surface\(name\) === target' <<< "$IDEMPOTENT"; then
    fail "open() must compare activePanel AND surface() for idempotency"
fi
# Inside the idempotent branch, only an initialSection retarget is allowed.
if awk '/if \(activePanel === name && surface\(name\) === target\)/,/^        \}$/' "$CONTROLLER" \
        | grep -Eq 'close\(name\)'; then
    fail "open() idempotent branch must not call close(name)"
fi

# ── NF-03: toggle must call close() — bare alias of open is forbidden ──
TOGGLE_BODY="$(awk '/function toggle\(name/,/^    \}$/' "$CONTROLLER")"
if grep -Eq 'function toggle\(name[^{]*\{ return open\(' "$CONTROLLER"; then
    fail "toggle() must not be a one-line alias of open()"
fi
if ! grep -Fq 'close(name)' <<< "$TOGGLE_BODY"; then
    fail "toggle(name) must call close(name) when activePanel === name"
fi

# ── NF-03: close must be name-safe ──
CLOSE_BODY="$(awk '/function close\(name/,/^    \}$/' "$CONTROLLER")"
if ! grep -Fq 'requested !== activePanel' <<< "$CLOSE_BODY"; then
    fail "close(name) must compare requested vs activePanel and skip state mutation on mismatch"
fi

# ── NF-04: shell.qml must unregister on per-monitor destruction ──
DESTRUCTION="$(awk '/Component.onDestruction:/,/^            \}$/' "$SHELL")"
for panel in quick-settings calendar notifications media clipboard wallpaper quick-share sync; do
    if ! grep -Fq "panelController.unregisterPanel(\"$panel\", this)" <<< "$DESTRUCTION"; then
        fail "shell.qml must unregister $panel on per-monitor MorphSurface destruction"
    fi
done

# ── NF-05: NoxdClient.setSetting must accept callbacks ──
if ! grep -Eq 'function setSetting\(key, value, callback, errorCallback\)' "$NOXD_CLIENT"; then
    fail "NoxdClient.setSetting must accept callback + errorCallback parameters"
fi

# ── NF-05: Tokens.appearanceRadius must be writable so the label reflects state ──
if grep -Eq 'readonly[[:space:]]+property[[:space:]]+int[[:space:]]+appearanceRadius' "$TOKENS"; then
    fail "Tokens.qml: appearanceRadius must NOT be readonly (radius label would always show 14)"
fi
if ! grep -Fq 'function applyRadius(' "$TOKENS"; then
    fail "Tokens.qml must define applyRadius() to keep radius scale and label in sync"
fi

# ── NF-05: SettingsPanel must hydrate from get_settings ──
if ! grep -Fq 'noxd.getSettings(' "$SETTINGS"; then
    fail "SettingsPanel must hydrate from noxd.getSettings()"
fi
if ! grep -Fq 'applyAppearanceFromMap(' "$SETTINGS"; then
    fail "SettingsPanel must apply the hydrated map via applyAppearanceFromMap()"
fi
if ! grep -Fq 'pendingWrites' "$SETTINGS"; then
    fail "SettingsPanel must track per-key pending writes for the pending UI state"
fi

printf 'noxflow panel lifecycle / settings hydration contract checks passed\n'

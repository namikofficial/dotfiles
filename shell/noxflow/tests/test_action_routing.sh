#!/usr/bin/env bash
set -euo pipefail

# Static regression checks for the IPC action routing contract.
#
# NF-02 established that every QML runAction payload must be either a
# canonical typed daemon action (declared in core/noxflow-ipc/src/lib.rs) or
# a shell-local call with a tested handler. The four names in this list were
# previously sent to noxd with no daemon owner; they must not be reintroduced
# because the daemon now rejects them with InvalidRequest (see
# core/noxflow-ipc/src/lib.rs::shell_local_action_names_are_not_action_variants
# and core/noxd/tests/server.rs::shell_local_action_names_are_not_action_variants).
#
# These checks walk the surfaces listed in the worktree ownership and fail
# loudly if any of them regresses back to a noxd.runAction({...}) call for
# one of these names.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LAUNCHER="$ROOT/shell/noxflow/surfaces/launcher/Launcher.qml"
CLIPBOARD="$ROOT/shell/noxflow/surfaces/clipboard/ClipboardPanel.qml"
NOTIFICATIONS="$ROOT/shell/noxflow/surfaces/notifications/NotificationCentre.qml"
RADIAL="$ROOT/shell/noxflow/surfaces/radialmenu/RadialWheel.qml"

rejects_run_action() {
    local needle="$1" file="$2" context="$3"
    if grep -Fq -- "runAction({$needle" "$file"; then
        printf 'forbidden: %s must not send %s via noxd.runAction (%s)\n' \
            "$file" "$needle" "$context" >&2
        exit 1
    fi
    # Also catch pretty-printed / spaced variants of the same shape, e.g.
    # `runAction( { toggle_launcher: {} })`.
    if grep -Fq -- "runAction( {$needle" "$file"; then
        printf 'forbidden: %s must not send %s via noxd.runAction (%s)\n' \
            "$file" "$needle" "$context" >&2
        exit 1
    fi
}

# window_focus is shell-local: hyprctl dispatch on the focused client address.
rejects_run_action "window_focus" "$LAUNCHER" \
    "window_focus is shell-local; use hyprctl dispatch focuswindow"

# clipboard_copy has no daemon owner and was removed; wl-copy owns the write.
rejects_run_action "clipboard_copy" "$CLIPBOARD" \
    "clipboard_copy is shell-local; wl-copy already performs the copy"

# notification_action has no daemon owner and is shell-local; the only
# implemented action id is "dismiss" which dispatches into NotificationModel.
rejects_run_action "notification_action" "$NOTIFICATIONS" \
    "notification_action is shell-local; the daemon does not own notifications"

# toggle_launcher has no daemon owner and is shell-local; the radial wheel
# must call shellRoot.toggleLauncher() instead of round-tripping through
# the daemon socket.
rejects_run_action "toggle_launcher" "$RADIAL" \
    "toggle_launcher is shell-local; the launcher is a shell surface"

# Positive coverage: the launcher must still offer a typed shell-local route
# for window focus, and the radial wheel must still wire the launcher toggle
# to shellRoot. If these go missing, the previous guard rails would still
# pass and the user-visible action would silently disappear.
if ! grep -Fq 'focusWindowByAddress' "$LAUNCHER"; then
    printf 'missing shell-local focusWindowByAddress in %s\n' "$LAUNCHER" >&2
    exit 1
fi
if ! grep -Fq 'shellRoot.toggleLauncher' "$RADIAL"; then
    printf 'missing shellRoot.toggleLauncher wiring in %s\n' "$RADIAL" >&2
    exit 1
fi

# Clipboard copy must still go through wl-copy so the runAction removal does
# not regress the actual copy behaviour.
if ! grep -Fq 'wl-copy' "$CLIPBOARD"; then
    printf 'missing wl-copy call in %s\n' "$CLIPBOARD" >&2
    exit 1
fi

# Notifications must still dismiss in-shell on the "dismiss" action id; that
# is the only implemented shell-local notification action today.
if ! grep -Fq 'dismissNotification' "$NOTIFICATIONS"; then
    printf 'missing dismissNotification call in %s\n' "$NOTIFICATIONS" >&2
    exit 1
fi

printf 'noxflow IPC action routing contract checks passed\n'

#!/usr/bin/env bash
set -euo pipefail

# Static regression checks for the Toggle controlled-component contract.
#
# NF-18: Toggle assigns to its own checked property on user interaction,
# which breaks when callers bind checked to provider/token state. The fix
# makes Toggle emit toggled(newValue) WITHOUT mutating checked, letting
# the binding source reconcile. This prevents binding-loop-prone checked
# mutation while preserving keyboard/tap activation.
#
# NF-18 also requires keyboard activation (Space/Enter) and reduced motion
# to work correctly through the token system.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TOGGLE="$ROOT/shell/noxflow/components/Toggle.qml"

# ── NF-18: Toggle must NOT mutate checked directly on interaction ──
# The onTapped handler must emit toggled(newValue) WITHOUT assigning to checked.
# If we find "root.checked = " inside onTapped, that's the regression.

# Extract the onTapped handler
extract_tap_handler() {
    local file="$1"
    # Find onTapped block up to the closing brace
    grep -A 20 "onTapped:" "$file" | head -20
}

tap_handler=$(extract_tap_handler "$TOGGLE")
if echo "$tap_handler" | grep -q "root.checked = "; then
    # Allow "if (!root.enabled) return" guard before the check
    if ! echo "$tap_handler" | grep -v "enabled" | grep -q "root.checked = "; then
        :
    else
        printf 'Toggle.onTapped must not assign to root.checked directly\n' >&2
        printf 'Emit toggled(!root.checked) signal instead to maintain binding integrity\n' >&2
        exit 1
    fi
fi

# onTapped must emit toggled signal with the new value
if ! echo "$tap_handler" | grep -q "toggled("; then
    printf 'Toggle.onTapped must emit toggled(newValue) signal\n' >&2
    exit 1
fi

# onTapped must NOT directly assign to checked (the controlled component fix)
# The new value should be !root.checked passed to toggled, not an assignment
if echo "$tap_handler" | grep "root.checked = !root.checked"; then
    printf 'Toggle.onTapped must not assign to root.checked - use toggled(!root.checked) signal\n' >&2
    exit 1
fi

# ── Keyboard activation must use the same signal-emit pattern ──
# Both Keys.onSpacePressed and Keys.onReturnPressed must emit toggled
# without direct checked mutation.

if ! grep -q "Keys.onSpacePressed" "$TOGGLE"; then
    printf 'Toggle must handle Keys.onSpacePressed\n' >&2
    exit 1
fi

if ! grep -q "Keys.onReturnPressed" "$TOGGLE"; then
    printf 'Toggle must handle Keys.onReturnPressed\n' >&2
    exit 1
fi

# Keyboard handlers must call toggled signal, not assign to checked directly
space_handler=$(grep -A 5 "Keys.onSpacePressed" "$TOGGLE")
return_handler=$(grep -A 5 "Keys.onReturnPressed" "$TOGGLE")

if echo "$space_handler" | grep -q "root.checked = "; then
    printf 'Keys.onSpacePressed must not assign to root.checked - use toggled signal\n' >&2
    exit 1
fi

if echo "$return_handler" | grep -q "root.checked = "; then
    printf 'Keys.onReturnPressed must not assign to root.checked - use toggled signal\n' >&2
    exit 1
fi

# Both keyboard handlers must emit toggled
if ! echo "$space_handler" | grep -q "toggled("; then
    printf 'Keys.onSpacePressed must emit toggled signal\n' >&2
    exit 1
fi

if ! echo "$return_handler" | grep -q "toggled("; then
    printf 'Keys.onReturnPressed must emit toggled signal\n' >&2
    exit 1
fi

# ── Toggle must maintain required accessibility properties ──
if ! grep -q "Accessible.role: Accessible.CheckBox" "$TOGGLE"; then
    printf 'Toggle must declare Accessible.role as CheckBox\n' >&2
    exit 1
fi

if ! grep -q "Accessible.checked: root.checked" "$TOGGLE"; then
    printf 'Toggle must expose checked state via Accessible.checked\n' >&2
    exit 1
fi

if ! grep -q "activeFocusOnTab: true" "$TOGGLE"; then
    printf 'Toggle must be focusable via Tab\n' >&2
    exit 1
fi

# ── Toggle must use Tokens for animations (reduced motion support) ──
# Duration and easing must come from Tokens, not hardcoded values.
if ! grep -q "Theme.Tokens.duration" "$TOGGLE"; then
    printf 'Toggle animations must use Theme.Tokens.duration for reduced motion support\n' >&2
    exit 1
fi

# ── Toggle must have hovered and pressed states for visual feedback ──
if ! grep -q "property bool hovered" "$TOGGLE"; then
    printf 'Toggle must have hovered property\n' >&2
    exit 1
fi

if ! grep -q "property bool pressed" "$TOGGLE"; then
    printf 'Toggle must have pressed property\n' >&2
    exit 1
fi

# ── Toggle must scale on hover/press for tactile feedback ──
if ! grep -q "Behavior on scale" "$TOGGLE"; then
    printf 'Toggle must animate scale on hover/press\n' >&2
    exit 1
fi

printf 'noxflow toggle contract checks passed\n'

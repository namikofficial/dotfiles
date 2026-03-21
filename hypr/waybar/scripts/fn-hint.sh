#!/usr/bin/env sh
set -eu

tooltip="$(cat <<'TXT'
Fn shortcuts
- Fn+1: vendor max-fan key (firmware-level on many G5/Clevo models)
- Fn+2..Fn+5: mapped in Hyprland to AI Helper modes
  XF86Launch2 ask
  XF86Launch3 clip
  XF86Launch4 shell
  XF86Launch5 debug
TXT
)"

jq -cn --arg text "Fn" --arg tooltip "$tooltip" '{text:$text, tooltip:$tooltip}'

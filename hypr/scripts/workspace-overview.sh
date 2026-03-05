#!/usr/bin/env sh
set -eu

name_store="$HOME/.config/hypr/scripts/workspace-name-store.sh"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "Workspace Overview" "$1" "${2:-}"
}

get_active_workspace_id() {
  hyprctl -j activeworkspace 2>/dev/null | jq -r '.id // 1' 2>/dev/null || printf '1\n'
}

get_names_json() {
  if [ -x "$name_store" ]; then
    "$name_store" json 2>/dev/null || printf '{}\n'
  else
    printf '{}\n'
  fi
}

rename_workspace() {
  ws_id="$1"
  [ -n "$ws_id" ] || return 0

  if [ ! -x "$name_store" ]; then
    notify "Workspace rename unavailable" "workspace-name-store.sh is missing."
    return 0
  fi

  current_name="$($name_store get "$ws_id" 2>/dev/null || true)"

  set +e
  new_name="$(printf '%s\n' "$current_name" | rofi -dmenu -i \
    -p "Rename Workspace $ws_id" \
    -theme "$HOME/.config/rofi/launcher.rasi" \
    -no-show-icons \
    -kb-cancel 'Escape,Control+g' \
    -mesg 'Enter a workspace label (max 32 chars).')"
  rofi_status=$?
  set -e

  [ "$rofi_status" -eq 0 ] || return 0

  if ! "$name_store" set "$ws_id" "$new_name" >/dev/null 2>&1; then
    notify "Workspace rename failed" "Name must be non-empty and <= 32 chars."
    return 0
  fi

  notify "Workspace renamed" "Workspace $ws_id updated."
}

clear_workspace_name() {
  ws_id="$1"
  [ -n "$ws_id" ] || return 0

  if [ ! -x "$name_store" ]; then
    notify "Workspace clear-name unavailable" "workspace-name-store.sh is missing."
    return 0
  fi

  "$name_store" unset "$ws_id" >/dev/null 2>&1 || true
  notify "Workspace label cleared" "Workspace $ws_id"
}

if ! command -v hyprctl >/dev/null 2>&1; then
  exit 1
fi

if ! command -v rofi >/dev/null 2>&1; then
  hyprctl dispatch workspace e+1
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  hyprctl dispatch workspace e+1
  exit 0
fi

while :; do
  clients_json="$(hyprctl -j clients 2>/dev/null || echo '[]')"
  workspaces_json="$(hyprctl -j workspaces 2>/dev/null || echo '[]')"
  names_json="$(get_names_json)"
  active_ws_id="$(get_active_workspace_id)"

  if ! printf '%s' "$clients_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
    clients_json='[]'
  fi

  if ! printf '%s' "$workspaces_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
    workspaces_json='[]'
  fi

  if ! printf '%s' "$names_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
    names_json='{}'
  fi

  entries="$({
    jq -rn \
      --argjson workspaces "$workspaces_json" \
      --argjson clients "$clients_json" \
      --argjson names "$names_json" \
      --argjson active "$active_ws_id" '
      def ws_ids:
        ([
          ($workspaces[]? | .id?),
          ($clients[]? | .workspace.id?),
          ($names | keys[]? | tonumber?)
        ]
        | map(select(type == "number" and . > 0))
        | unique
        | sort);

      (ws_ids) as $ids
      | (if ($ids | length) > 0 then $ids else [$active] end)[] as $ws
      | ($clients | map(select(.workspace.id == $ws)) | length) as $count
      | ($names[($ws | tostring)] // "") as $label
      | if ($label | length) > 0 then
          "\($ws)\tworkspace\t󰍹  Workspace \($ws) (\($label)) (\($count) windows)\t"
        else
          "\($ws)\tworkspace\t󰍹  Workspace \($ws) (\($count) windows)\t"
        end
    '

    printf '%s' "$clients_json" | jq -r '
      map(select(.workspace.id > 0))
      | sort_by(.workspace.id, .address)
      | .[]
      | "\(.workspace.id)\twindow\t󰖯  [\(.workspace.id)] \((.class // "app") | gsub("[\\t\\r\\n]+"; " ")) - \((.title // "untitled") | gsub("[\\t\\r\\n]+"; " "))\t\(.address // "")"
    '
  } | awk 'NF')"

  [ -n "$entries" ] || exit 0

  set +e
  choice="$(printf '%s\n' "$entries" | rofi -dmenu -i \
    -p 'Workspace Overview' \
    -theme "$HOME/.config/rofi/launcher.rasi" \
    -no-show-icons \
    -no-sort \
    -kb-cancel 'Escape,Control+g,Super+Shift+space' \
    -kb-custom-1 'Alt+r' \
    -kb-custom-2 'Alt+BackSpace' \
    -mesg 'Enter: jump/focus | Alt+R: rename workspace | Alt+BackSpace: clear workspace label' \
    -display-columns 3 \
    -display-column-separator '\t')"
  rofi_status=$?
  set -e

  case "$rofi_status" in
    1|130)
      exit 0
      ;;
  esac

  selected_ws_id="$(printf '%s' "$choice" | awk -F '\t' '{print $1}')"
  entry_type="$(printf '%s' "$choice" | awk -F '\t' '{print $2}')"
  window_addr="$(printf '%s' "$choice" | awk -F '\t' '{print $4}')"

  if [ -z "$selected_ws_id" ]; then
    selected_ws_id="$active_ws_id"
  fi

  case "$rofi_status" in
    10)
      rename_workspace "$selected_ws_id"
      continue
      ;;
    11)
      clear_workspace_name "$selected_ws_id"
      continue
      ;;
  esac

  [ -n "$selected_ws_id" ] || exit 0

  hyprctl dispatch workspace "$selected_ws_id" >/dev/null 2>&1 || true

  if [ "$entry_type" = "window" ] && [ -n "$window_addr" ]; then
    hyprctl dispatch focuswindow "address:$window_addr" >/dev/null 2>&1 || true
  fi

  exit 0
done

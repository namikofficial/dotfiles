#!/usr/bin/env sh
set -eu

name_store="$HOME/.config/hypr/scripts/workspace-name-store.sh"
meta_store="$HOME/.config/hypr/scripts/workspace-meta-store.sh"

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

get_meta_json() {
  if [ -x "$meta_store" ]; then
    "$meta_store" json 2>/dev/null || printf '{"favorites":[],"recent":[]}\n'
  else
    printf '{"favorites":[],"recent":[]}\n'
  fi
}

record_recent_workspace() {
  ws_id="$1"
  [ -n "$ws_id" ] || return 0
  if [ -x "$meta_store" ]; then
    "$meta_store" recent-push "$ws_id" >/dev/null 2>&1 || true
  fi
}

toggle_workspace_favorite() {
  ws_id="$1"
  [ -n "$ws_id" ] || return 0

  if [ ! -x "$meta_store" ]; then
    notify "Favorite toggle unavailable" "workspace-meta-store.sh is missing."
    return 0
  fi

  before_json="$(get_meta_json)"
  was_favorite="$(printf '%s' "$before_json" | jq -r --argjson ws "$ws_id" 'if (.favorites // [] | index($ws)) == null then "0" else "1" end')"
  "$meta_store" favorite-toggle "$ws_id" >/dev/null 2>&1 || true

  if [ "$was_favorite" = "1" ]; then
    notify "Workspace unstarred" "Workspace $ws_id"
  else
    notify "Workspace starred" "Workspace $ws_id"
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

show_shortcuts_panel() {
  shortcuts="$(cat <<'EOF_KEYS'
Super + Y (Primary) -> Open Workspace Hub
Super + W -> Open Workspace Hub directly
Super + Shift + Space -> Open Workspace Hub directly
Super + Shift + Tab -> Open Workspace Hub directly
Super + Tab -> Overview toggle (hyprexpo if available, Rofi hub fallback)
Super + Ctrl + Space + Ctrl + 4 -> Quick Actions path to Workspace Hub
Super + / + Ctrl + 4 -> Quick Actions path to Workspace Hub
Super + A + Ctrl + 4 -> Quick Actions path to Workspace Hub
Super + D + Ctrl + 4 -> Quick Actions path to Workspace Hub
Ctrl + Alt + R (inside overview) -> Rename selected workspace
Ctrl + Alt + BackSpace (inside overview) -> Clear selected workspace label
Ctrl + Alt + F (inside overview) -> Toggle favorite workspace
Ctrl + Alt + S (inside overview) -> Open this shortcuts panel
Ctrl + Alt + M (window row) -> Move window to workspace
Ctrl + Alt + O (window row) -> Move window and follow
Ctrl + Alt + P (window row) -> Send window to side panel
EOF_KEYS
)"

  set +e
  _="$(printf '%s\n' "$shortcuts" | rofi -dmenu -i \
    -p 'Overview Shortcuts' \
    -theme "$HOME/.config/rofi/actions.rasi" \
    -mesg 'Esc closes. Enter copies selected row if wl-copy is available.' \
    -no-show-icons \
    -kb-cancel 'Escape,Control+g' )"
  _status=$?
  set -e

  [ "$_status" -eq 0 ] || return 0
}

choose_workspace_target() {
  workspaces_json="$1"
  clients_json="$2"
  names_json="$3"
  active_ws_id="$4"

  choices="$(jq -rn \
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
    | ($names[($ws|tostring)] // "") as $label
    | if ($label|length) > 0 then
        "\($ws)\t󰍹  Workspace \($ws) (\($label)) (\($count) windows)"
      else
        "\($ws)\t󰍹  Workspace \($ws) (\($count) windows)"
      end
  ' | awk 'NF')"

  [ -n "$choices" ] || return 1

  set +e
  picked="$(printf '%s\n' "$choices" | rofi -dmenu -i \
    -p 'Move To Workspace' \
    -theme "$HOME/.config/rofi/launcher.rasi" \
    -no-show-icons \
    -display-columns 2 \
    -display-column-separator '\t' \
    -kb-cancel 'Escape,Control+g')"
  status=$?
  set -e

  [ "$status" -eq 0 ] || return 1
  printf '%s' "$picked" | awk -F '\t' '{print $1}'
}

move_window_to_workspace() {
  window_addr="$1"
  follow="$2"
  clients_json="$3"
  workspaces_json="$4"
  names_json="$5"
  active_ws_id="$6"

  [ -n "$window_addr" ] || return 0

  target_ws="$(choose_workspace_target "$workspaces_json" "$clients_json" "$names_json" "$active_ws_id" || true)"
  [ -n "$target_ws" ] || return 0

  hyprctl dispatch focuswindow "address:$window_addr" >/dev/null 2>&1 || true
  hyprctl dispatch movetoworkspacesilent "$target_ws" >/dev/null 2>&1 || true

  if [ "$follow" = "1" ]; then
    hyprctl dispatch workspace "$target_ws" >/dev/null 2>&1 || true
    hyprctl dispatch focuswindow "address:$window_addr" >/dev/null 2>&1 || true
  fi

  notify "Window moved" "Workspace $target_ws"
  record_recent_workspace "$target_ws"
}

send_window_to_sidepanel() {
  window_addr="$1"
  [ -n "$window_addr" ] || return 0

  hyprctl dispatch focuswindow "address:$window_addr" >/dev/null 2>&1 || true
  "$HOME/.config/hypr/scripts/sidepanel.sh" send >/dev/null 2>&1 || true
  notify "Window sent" "Moved to side panel"
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
  meta_json="$(get_meta_json)"
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

  if ! printf '%s' "$meta_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
    meta_json='{"favorites":[],"recent":[]}'
  fi

  entries="$({
    printf '%s\taction\t󰘳  Overview shortcuts\t\n' "$active_ws_id"

    jq -rn \
      --argjson workspaces "$workspaces_json" \
      --argjson clients "$clients_json" \
      --argjson names "$names_json" \
      --argjson meta "$meta_json" \
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

      def fav_ids: (($meta.favorites // []) | map(select(type == "number" and . > 0)));
      def recent_ids: (($meta.recent // []) | map(select(type == "number" and . > 0)));
      def recent_rank($ws): ((recent_ids | to_entries | map(select(.value == $ws)) | .[0].key) // -1);

      (ws_ids) as $ids
      | (fav_ids) as $fav
      | ([ $fav[] | select($ids | index(.)) ] + [ $ids[] | select($fav | index(.) | not) ]) as $ordered
      | (if ($ordered | length) > 0 then $ordered else [$active] end)[] as $ws
      | ($clients | map(select(.workspace.id == $ws)) | length) as $count
      | ($names[($ws | tostring)] // "") as $label
      | ($fav | index($ws)) as $fav_idx
      | (recent_rank($ws)) as $ridx
      | ([
          (if $fav_idx != null then "★" else empty end),
          (if $ridx >= 0 then ("R" + (($ridx + 1)|tostring)) else empty end)
        ]) as $meta_bits
      | (if ($meta_bits | length) > 0 then " {" + ($meta_bits | join(",")) + "}" else "" end) as $meta_suffix
      | if ($label | length) > 0 then
          "\($ws)\tworkspace\t󰍹  Workspace \($ws) (\($label)) (\($count) windows)\($meta_suffix)\t"
        else
          "\($ws)\tworkspace\t󰍹  Workspace \($ws) (\($count) windows)\($meta_suffix)\t"
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
    -kb-custom-1 'Control+Alt+r' \
    -kb-custom-2 'Control+Alt+BackSpace' \
    -kb-custom-3 'Control+Alt+f' \
    -kb-custom-4 'Control+Alt+s' \
    -kb-custom-5 'Control+Alt+m' \
    -kb-custom-6 'Control+Alt+o' \
    -kb-custom-7 'Control+Alt+p' \
    -mesg 'Enter jump/focus | Ctrl+Alt+R rename | Ctrl+Alt+BackSpace clear | Ctrl+Alt+F star | Ctrl+Alt+S shortcuts | Ctrl+Alt+M/O/P window actions' \
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
    12)
      toggle_workspace_favorite "$selected_ws_id"
      continue
      ;;
    13)
      show_shortcuts_panel
      continue
      ;;
    14)
      if [ "$entry_type" = "window" ] && [ -n "$window_addr" ]; then
        move_window_to_workspace "$window_addr" 0 "$clients_json" "$workspaces_json" "$names_json" "$active_ws_id"
      else
        notify "Move unavailable" "Select a window row first."
      fi
      continue
      ;;
    15)
      if [ "$entry_type" = "window" ] && [ -n "$window_addr" ]; then
        move_window_to_workspace "$window_addr" 1 "$clients_json" "$workspaces_json" "$names_json" "$active_ws_id"
      else
        notify "Move+follow unavailable" "Select a window row first."
      fi
      continue
      ;;
    16)
      if [ "$entry_type" = "window" ] && [ -n "$window_addr" ]; then
        send_window_to_sidepanel "$window_addr"
      else
        notify "Sidepanel send unavailable" "Select a window row first."
      fi
      continue
      ;;
  esac

  if [ "$entry_type" = "action" ]; then
    show_shortcuts_panel
    continue
  fi

  [ -n "$selected_ws_id" ] || exit 0

  hyprctl dispatch workspace "$selected_ws_id" >/dev/null 2>&1 || true
  record_recent_workspace "$selected_ws_id"

  if [ "$entry_type" = "window" ] && [ -n "$window_addr" ]; then
    hyprctl dispatch focuswindow "address:$window_addr" >/dev/null 2>&1 || true
  fi

  exit 0
done

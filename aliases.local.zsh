# Local aliases/functions loaded after aliases.zsh.
# This file is tracked in git by design.
#
# In order to keep custom machine-specific tweaks here so they stay separate from
# shared defaults in aliases.zsh.
#
# Example:
# alias myvpn='~/scripts/connect-vpn'

# Local project shortcuts.
alias noxflow='cd ~/Documents/code/noxflow'
alias wellvantage='cd ~/Documents/code/WellVantage'
alias dotfiles='cd ~/Documents/code/dotfiles'

_vpn_nm_ready() {
  if ! command -v nmcli >/dev/null 2>&1; then
    return 1
  fi

  if nmcli general status >/dev/null 2>&1; then
    return 0
  fi

  echo "NetworkManager is not running. Trying to start it..." >&2
  if ! command -v systemctl >/dev/null 2>&1; then
    return 1
  fi

  if ! systemctl is-active --quiet NetworkManager 2>/dev/null; then
    sudo systemctl start NetworkManager || return 1
    sleep 2
  fi

  nmcli general status >/dev/null 2>&1
}

_vpn_connect_openvpn_fallback() {
  local ovpn_file="$1"
  local vpn_password="$2"
  local pid_file="/tmp/wellvantage-openvpn.pid"
  local log_file="/tmp/wellvantage-openvpn.log"
  local auth_file="/tmp/wellvantage-openvpn.auth"
  local vpn_user

  if ! command -v openvpn >/dev/null 2>&1; then
    echo "openvpn is not installed." >&2
    if command -v pacman >/dev/null 2>&1; then
      echo "Install it with: sudo pacman -S --needed openvpn" >&2
    fi
    return 1
  fi

  if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    echo "OpenVPN is already running."
    return 0
  fi

  if command grep -Eq '^[[:space:]]*auth-user-pass([[:space:]]+[^[:space:]]+)?[[:space:]]*$' "$ovpn_file"; then
    vpn_user="$(sed -n 's/^# OVPN_ACCESS_SERVER_USERNAME=//p' "$ovpn_file" | head -n1)"
    vpn_user="${vpn_user:-namik}"
    printf '%s\n%s\n' "$vpn_user" "$vpn_password" > "$auth_file"
    chmod 600 "$auth_file"
    sudo openvpn --config "$ovpn_file" --auth-user-pass "$auth_file" --daemon --writepid "$pid_file" --log "$log_file" || return 1
  else
    sudo openvpn --config "$ovpn_file" --daemon --writepid "$pid_file" --log "$log_file" || return 1
  fi

  sleep 1
  if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    echo "VPN connected via openvpn fallback."
    return 0
  fi

  echo "OpenVPN fallback failed. Check $log_file" >&2
  return 1
}

vpn-connect() {
  local ovpn_file="$HOME/Documents/code/scripts/keys/wellvantage-namikArch.ovpn"
  local vpn_name="wellvantage-vpn"
  local vpn_password="noobnamik"
  local nm_error=""

  if [ ! -f "$ovpn_file" ]; then
    echo "VPN config not found: $ovpn_file" >&2
    return 1
  fi

  if _vpn_nm_ready; then
    if ! nmcli -t -f NAME connection show | command grep -Fxq "$vpn_name"; then
      local import_output imported_name
      import_output="$(nmcli connection import type openvpn file "$ovpn_file" 2>&1)" || nm_error="$import_output"

      if [ -z "$nm_error" ]; then
        imported_name="$(printf '%s\n' "$import_output" | sed -n "s/.*Connection '\\(.*\\)'.*/\\1/p" | head -n1)"
        if [ -n "$imported_name" ] && [ "$imported_name" != "$vpn_name" ]; then
          nmcli connection modify "$imported_name" connection.id "$vpn_name" >/dev/null 2>&1 || true
        fi
      fi
    fi

    if [ -z "$nm_error" ]; then
      nmcli connection modify "$vpn_name" +vpn.data "password-flags=0" >/dev/null 2>&1 || true
      nmcli connection modify "$vpn_name" +vpn.secrets "password=$vpn_password" >/dev/null 2>&1 || true

      local up_output
      up_output="$(nmcli connection up "$vpn_name" 2>&1)" || nm_error="$up_output"
      [ -z "$nm_error" ] && return 0
    fi
  else
    nm_error="NetworkManager is not available."
  fi

  if printf '%s\n' "$nm_error" | command grep -Fq 'unknown VPN plugin "org.freedesktop.NetworkManager.openvpn"'; then
    echo "NetworkManager OpenVPN plugin is missing. Falling back to openvpn..." >&2
    if command -v pacman >/dev/null 2>&1; then
      echo "To fix NetworkManager path permanently: sudo pacman -S --needed networkmanager-openvpn" >&2
    fi
    _vpn_connect_openvpn_fallback "$ovpn_file" "$vpn_password"
    return $?
  fi

  echo "$nm_error" >&2
  return 1
}

vpn-disconnect() {
  local vpn_name="wellvantage-vpn"
  local active_vpn
  local pid_file="/tmp/wellvantage-openvpn.pid"
  local auth_file="/tmp/wellvantage-openvpn.auth"

  if _vpn_nm_ready; then
    if nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2=="vpn" {print $1}' | command grep -Fxq "$vpn_name"; then
      nmcli connection down "$vpn_name"
      return $?
    fi

    active_vpn="$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2=="vpn" {print $1; exit}')"
    if [ -n "$active_vpn" ]; then
      nmcli connection down "$active_vpn"
      return $?
    fi
  fi

  if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    sudo kill "$(cat "$pid_file")" || return 1
    rm -f "$pid_file" "$auth_file"
    echo "VPN disconnected (openvpn fallback)."
    return 0
  fi

  echo "No active VPN connection found."
  return 0
}

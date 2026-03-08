#!/usr/bin/env sh
set -eu

interval="${NOXFLOW_TELEMETRY_NET_INTERVAL:-2}"

find_primary_iface() {
  ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'
}

read_counter() {
  path="$1"
  if [ -r "$path" ]; then
    cat "$path"
  else
    echo 0
  fi
}

human_rate() {
  bytes_per_sec="${1:-0}"

  awk -v value="$bytes_per_sec" '
    function fmt(v, unit) {
      if (v >= 100) return sprintf("%.0f %s/s", v, unit)
      if (v >= 10) return sprintf("%.1f %s/s", v, unit)
      return sprintf("%.2f %s/s", v, unit)
    }
    BEGIN {
      if (value < 1024) {
        print sprintf("%d B/s", value)
      } else if (value < 1024 * 1024) {
        print fmt(value / 1024, "KiB")
      } else if (value < 1024 * 1024 * 1024) {
        print fmt(value / (1024 * 1024), "MiB")
      } else {
        print fmt(value / (1024 * 1024 * 1024), "GiB")
      }
    }
  '
}

iface="$(find_primary_iface)"
if [ -z "$iface" ]; then
  printf 'No default network interface found.\n'
  printf 'Waiting for a default route...\n'
fi

rx_prev=0
tx_prev=0

if [ -n "$iface" ]; then
  rx_prev="$(read_counter "/sys/class/net/$iface/statistics/rx_bytes")"
  tx_prev="$(read_counter "/sys/class/net/$iface/statistics/tx_bytes")"
fi

while :; do
  iface_new="$(find_primary_iface)"
  if [ "$iface_new" != "$iface" ]; then
    iface="$iface_new"
    if [ -n "$iface" ]; then
      rx_prev="$(read_counter "/sys/class/net/$iface/statistics/rx_bytes")"
      tx_prev="$(read_counter "/sys/class/net/$iface/statistics/tx_bytes")"
    else
      rx_prev=0
      tx_prev=0
    fi
  fi

  printf '\033[H\033[2J'
  printf 'Network Telemetry\n\n'
  printf 'Updated: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"

  if [ -z "$iface" ]; then
    printf '\nNo active default route.\n'
    sleep "$interval"
    continue
  fi

  rx_now="$(read_counter "/sys/class/net/$iface/statistics/rx_bytes")"
  tx_now="$(read_counter "/sys/class/net/$iface/statistics/tx_bytes")"

  rx_rate=0
  tx_rate=0
  if [ "$interval" -gt 0 ]; then
    rx_rate=$(( (rx_now - rx_prev) / interval ))
    tx_rate=$(( (tx_now - tx_prev) / interval ))
  fi

  if [ "$rx_rate" -lt 0 ]; then
    rx_rate=0
  fi
  if [ "$tx_rate" -lt 0 ]; then
    tx_rate=0
  fi

  rx_prev="$rx_now"
  tx_prev="$tx_now"

  printf '\nInterface\n'
  printf '  %-12s %s\n' "device" "$iface"
  printf '  %-12s %s\n' "rx" "$(human_rate "$rx_rate")"
  printf '  %-12s %s\n' "tx" "$(human_rate "$tx_rate")"

  printf '\nAddresses\n'
  ip -br addr show dev "$iface" 2>/dev/null || true

  printf '\nDefault Route\n'
  ip route show default 2>/dev/null | sed 's/^/  /'

  printf '\nEstablished Connections (top 10)\n'
  if ! ss -Htu state established 2>/dev/null | head -n 10 | sed 's/^/  /'; then
    printf '  unavailable\n'
  fi

  printf '\nListening Ports (top 10)\n'
  if ! ss -Hltunp 2>/dev/null | head -n 10 | sed 's/^/  /'; then
    printf '  unavailable\n'
  fi

  sleep "$interval"
done

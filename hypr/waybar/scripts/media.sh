#!/usr/bin/env sh
set -eu

if ! command -v playerctl >/dev/null 2>&1; then
  echo "󰐊 no player"
  exit 0
fi

status="$(playerctl status 2>/dev/null || true)"
if [ -z "$status" ]; then
  echo "󰐊 idle"
  exit 0
fi

artist="$(playerctl metadata artist 2>/dev/null || true)"
title="$(playerctl metadata title 2>/dev/null || true)"

if [ -z "$artist$title" ]; then
  echo "󰐊 $status"
  exit 0
fi

printf '󰎈 %s - %s\n' "${artist:-Unknown}" "${title:-Unknown}"

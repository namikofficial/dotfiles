#!/usr/bin/env bash
set -euo pipefail

if systemctl --user is-active --quiet syncthing.service; then
  text="ON"
  if systemctl --user is-failed --quiet syncthing.service; then
    text="ERR"
  fi
else
  text="OFF"
fi

printf '{"text":"%s","tooltip":"Syncthing service status"}\n' "$text"

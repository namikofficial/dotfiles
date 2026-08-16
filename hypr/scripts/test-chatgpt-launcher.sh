#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"; script="$root/hypr/scripts/chatgpt-launcher.sh"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.local/state/noxflow"
cat >"$tmp/bin/jq" <<'EOF'
#!/usr/bin/env bash
[ "${MOCK_VISIBLE:-0}" = 1 ] && printf '0x1234\n'
EOF
cat >"$tmp/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "clients -j" ]; then printf '[]\n'; else printf '%s\n' "$*" >>"$MOCK_DISPATCH"; fi
EOF
cat >"$tmp/bin/ps" <<'EOF'
#!/usr/bin/env bash
[ "${MOCK_HEADLESS:-0}" = 1 ] && printf '650052 %s --ozone-platform=wayland\n' "$CHATGPT_BINARY"
EOF
cat >"$tmp/bin/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$tmp/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MOCK_NOTIFY"
EOF
cat >"$tmp/fake-chatgpt" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MOCK_EXEC"
sleep "${MOCK_APP_SLEEP:-0}"
EOF
chmod +x "$tmp/bin/"* "$tmp/fake-chatgpt"
export HOME="$tmp/home" PATH="$tmp/bin:$PATH" MOCK_DISPATCH="$tmp/dispatch.log" MOCK_EXEC="$tmp/exec.log" MOCK_NOTIFY="$tmp/notify.log" CHATGPT_BINARY="$tmp/fake-chatgpt" CHATGPT_RECOVERY_ATTEMPTS=1 CHATGPT_STARTUP_ATTEMPTS=1 MOCK_APP_SLEEP=1
grep -Fq 'select(((.class // "") | ascii_downcase) == "chatgpt")' "$script"
MOCK_VISIBLE=1 "$script"; grep -Fx 'dispatch focuswindow address:0x1234' "$MOCK_DISPATCH" >/dev/null; [ ! -s "$MOCK_EXEC" ]
rm -f "$MOCK_DISPATCH" "$MOCK_EXEC" "$MOCK_NOTIFY"
MOCK_HEADLESS=1 "$script"; grep -Fx -- '--ozone-platform=wayland' "$MOCK_EXEC" >/dev/null
if grep -F 'already running' "$MOCK_NOTIFY" >/dev/null 2>&1; then
  echo 'headless recovery reported already running' >&2
  exit 1
fi
rm -f "$MOCK_DISPATCH" "$MOCK_EXEC" "$MOCK_NOTIFY"
callback='codex://connector/oauth_callback?state=keep-me'; MOCK_VISIBLE=1 "$script" "$callback"; [ ! -s "$MOCK_EXEC" ]; grep -F 'callback received' "$MOCK_NOTIFY" >/dev/null
rm -f "$MOCK_DISPATCH" "$MOCK_EXEC" "$MOCK_NOTIFY"; "$script" "$callback"; grep -Fx -- "--ozone-platform=wayland $callback" "$MOCK_EXEC" >/dev/null
printf 'chatgpt launcher: ok\n'

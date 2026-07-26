#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_dir/setup/install-workbench-desktop-services.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
systemctl_log="$tmp_dir/systemctl.log"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>%q\n' "$systemctl_log" >"$tmp_dir/bin/systemctl"
chmod +x "$tmp_dir/bin/systemctl"

test_home="$tmp_dir/home"
test_config="$tmp_dir/config"
mkdir -p "$test_home" "$test_config"

HOME="$test_home" XDG_CONFIG_HOME="$test_config" PATH="$tmp_dir/bin:$PATH" "$installer" install >/dev/null

for unit in \
  ai-workbench-desktop-observer.service \
  ai-workbench-project-watch.service \
  ai-workbench-notification-bridge.service; do
  test -f "$test_config/systemd/user/$unit"
  cmp -s "$repo_dir/systemd/user/$unit" "$test_config/systemd/user/$unit"
done
grep -Fx -- '--user daemon-reload' "$systemctl_log" >/dev/null

HOME="$test_home" XDG_CONFIG_HOME="$test_config" PATH="$tmp_dir/bin:$PATH" "$installer" uninstall >/dev/null
for unit in \
  ai-workbench-desktop-observer.service \
  ai-workbench-project-watch.service \
  ai-workbench-notification-bridge.service; do
  test ! -e "$test_config/systemd/user/$unit"
done
grep -F -- '--user disable --now ai-workbench-desktop-observer.service' "$systemctl_log" >/dev/null

dry_config="$tmp_dir/dry-config"
HOME="$test_home" XDG_CONFIG_HOME="$dry_config" PATH="$tmp_dir/bin:$PATH" "$installer" --dry-run >/dev/null
test ! -e "$dry_config/systemd/user"

printf 'workbench desktop service installer: ok\n'

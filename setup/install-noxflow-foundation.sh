#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install_root="${NOXFLOW_INSTALL_ROOT:-${HOME}/.local}"
bin_dir="$install_root/bin"
unit_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user"

mkdir -p "$bin_dir" "$unit_dir"
cargo install --path "$repo_dir/core/noxd" --root "$install_root" --force
cargo install --path "$repo_dir/cli/noxctl" --root "$install_root" --force
ln -sfn "$repo_dir/systemd/user/noxd.service" "$unit_dir/noxd.service"
ln -sfn "$repo_dir/systemd/user/noxflow-shell.service" "$unit_dir/noxflow-shell.service"
ln -sfn "$repo_dir/systemd/user/noxflow-fallback.service" "$unit_dir/noxflow-fallback.service"
ln -sfn "$repo_dir/systemd/user/localsend.service" "$unit_dir/localsend.service"
ln -sfn "$repo_dir/setup/noxflow-shell-launcher.sh" "$bin_dir/noxflow-shell"
mkdir -p "${XDG_CONFIG_HOME:-${HOME}/.config}/noxflow"
ln -sfn "$repo_dir/shell/noxflow" "${XDG_CONFIG_HOME:-${HOME}/.config}/noxflow/shell"

echo "Installed noxd and noxctl to $bin_dir"
echo "Linked noxd.service; enable it after validating the fallback path with:"
echo "  systemctl --user daemon-reload"
echo "  systemctl --user enable --now noxd.service"

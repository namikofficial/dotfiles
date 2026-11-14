#!/usr/bin/env bash
# Regression test for the systemd user units.
#
# A unit is a public default: it is linked into every user's
# ~/.config/systemd/user. Three things can silently break it:
#
#   * a path that only resolves on the machine where the unit was written
#     (the repository checkout location, or an account's home);
#   * a path that points at a file the repository no longer has;
#   * a unit nobody installs, so the feature it describes never arrives.
#
# Every home-relative path in a unit is checked against the tables below,
# and every repository-backed entry must exist and be provided by an
# installer.
set -uo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

failures=0

ok() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

# The repository file that provides each home-relative path a unit starts.
declare -A providers=(
  ["%h/.config/hypr/scripts/panel-switch.sh"]="hypr/scripts/panel-switch.sh"
  ["%h/.config/hypr/scripts/startup.sh"]="hypr/scripts/startup.sh"
  ["%h/.config/llama-router/render-preset.py"]="system/llama-router/render-preset.py"
  ["%h/.local/bin/llama-router"]="system/llama-router/llama-router.sh"
  ["%h/.local/bin/noxflow-shell"]="setup/noxflow-shell-launcher.sh"
)

# Home-relative paths a unit reads that are not repository files, with the
# reason they exist. A path that is in neither table is a path nobody
# checked.
declare -A generated=(
  ["%h/.config/llama-router/models.ini"]="written by render-preset.py at install time"
  ["%h/.local/bin/noxd"]="cargo build output, installed by setup/bootstrap-noxflow.sh"
)

# Units that are installed by hand, with the reason.
manual_units=(
  "nox-tunnel.service:setup/install-ssh-config.sh prints the systemctl --user link command for it"
)

printf '== units carry no machine-specific path ==\n'

for unit in systemd/user/*; do
  name="$(basename "$unit")"
  if grep -qE '/home/[a-zA-Z0-9_-]+|%h/Documents' "$unit"; then
    fail "$name carries no absolute home or checkout path"
    grep -nE '/home/[a-zA-Z0-9_-]+|%h/Documents' "$unit" >&2
  else
    ok "$name carries no absolute home or checkout path"
  fi
done

printf '== every home-relative path a unit uses is accounted for ==\n'

for unit in systemd/user/*; do
  name="$(basename "$unit")"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -n "${providers[$path]:-}" ]; then
      if [ ! -e "${providers[$path]}" ]; then
        fail "$name: '$path' resolves to '${providers[$path]}', which does not exist"
      else
        ok "$name: '$path' resolves to ${providers[$path]}"
      fi
    elif [ -n "${generated[$path]:-}" ]; then
      ok "$name: '$path' is generated (${generated[$path]})"
    else
      fail "$name: '$path' is not accounted for"
    fi
  done < <(grep -hoE '%h/[^ ;]+' "$unit" | sort -u)
done

printf '== every provider is installed by an installer ==\n'

for path in "${!providers[@]}"; do
  source_file="${providers[$path]}"
  base="$(basename "$source_file")"
  if rg -l --fixed-strings "$base" setup/*.sh >/dev/null 2>&1; then
    ok "$base is provided by an installer"
  else
    fail "$base is provided by an installer"
  fi
done

printf '== every unit is installed by someone ==\n'

for unit in systemd/user/*; do
  name="$(basename "$unit")"
  manual=0
  for entry in "${manual_units[@]}"; do
    if [[ "$entry" == "$name:"* ]]; then
      manual=1
      break
    fi
  done
  if [ "$manual" -eq 1 ]; then
    ok "$name is installed by hand, as documented"
    continue
  fi
  if rg -l --fixed-strings "systemd/user/$name" setup/*.sh >/dev/null 2>&1; then
    ok "$name is linked by an installer"
  else
    fail "$name is linked by an installer"
  fi
done

printf '\n'
if [ "$failures" -eq 0 ]; then
  printf 'systemd units: ok\n'
  exit 0
fi
printf 'systemd units: %d failure(s)\n' "$failures" >&2
exit 1

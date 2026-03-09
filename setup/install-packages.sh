#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACMAN_LIST="$SCRIPT_DIR/pacman-packages.txt"
AUR_LIST="$SCRIPT_DIR/aur-packages.txt"
NVIDIA_LIST="$SCRIPT_DIR/nvidia-packages.txt"
WITH_AUR=0
DRY_RUN=0
WITH_NVIDIA=0
NONCONFIRM=0
AS_USER="${SUDO_USER:-$USER}"

for arg in "$@"; do
  case "$arg" in
    --with-aur) WITH_AUR=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --with-nvidia) WITH_NVIDIA=1 ;;
    --no-nvidia) WITH_NVIDIA=0 ;;
    --noconfirm) NONCONFIRM=1 ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: $0 [--with-aur] [--with-nvidia|--no-nvidia] [--noconfirm] [--dry-run]" >&2
      exit 1
      ;;
  esac
done

read_list() {
  local file="$1"
  grep -E -v '^\s*($|#)' "$file"
}

run_pacman() {
  if (( EUID == 0 )); then
    pacman "$@"
  else
    sudo pacman "$@"
  fi
}

check_pacman_lock() {
  local lock_file="/var/lib/pacman/db.lck"
  if [ ! -f "$lock_file" ]; then
    return 0
  fi

  if pgrep -x pacman >/dev/null 2>&1; then
    echo "pacman is currently running; wait for it to finish and retry." >&2
  else
    echo "stale pacman lock detected at $lock_file" >&2
    echo "fix with: sudo rm -f $lock_file" >&2
  fi
  exit 1
}

run_yay() {
  if (( EUID == 0 )); then
    if [ -z "${SUDO_USER:-}" ]; then
      echo "warning: skipping AUR operation because script is running as root without SUDO_USER" >&2
      return 1
    fi
    local user_home
    user_home="$(getent passwd "$AS_USER" | cut -d: -f6)"
    sudo -u "$AS_USER" env -u SUDO_USER -u SUDO_UID -u SUDO_GID \
      HOME="$user_home" XDG_CACHE_HOME="$user_home/.cache" \
      PATH="/usr/local/sbin:/usr/local/bin:/usr/bin:/bin" \
      yay "$@"
  else
    yay "$@"
  fi
}

filter_pacman_packages() {
  local entry
  local candidate
  local picked
  local -a candidates=()
  local -a filtered=()
  for entry in "$@"; do
    IFS='|' read -r -a candidates <<< "$entry"
    picked=""
    for candidate in "${candidates[@]}"; do
      if pacman -Si "$candidate" >/dev/null 2>&1; then
        picked="$candidate"
        break
      fi
    done
    if [ -n "$picked" ]; then
      filtered+=("$picked")
    else
      echo "warning: skipping unavailable pacman package '$entry'" >&2
    fi
  done
  if (( ${#filtered[@]} > 0 )); then
    printf '%s\n' "${filtered[@]}"
  fi
}

filter_aur_packages() {
  local entry
  local candidate
  local picked
  local -a candidates=()
  local -a filtered=()
  for entry in "$@"; do
    IFS='|' read -r -a candidates <<< "$entry"
    picked=""
    for candidate in "${candidates[@]}"; do
      if run_yay -Si "$candidate" >/dev/null 2>&1; then
        picked="$candidate"
        break
      fi
    done
    if [ -n "$picked" ]; then
      filtered+=("$picked")
    else
      echo "warning: skipping unavailable AUR package '$entry'" >&2
    fi
  done
  if (( ${#filtered[@]} > 0 )); then
    printf '%s\n' "${filtered[@]}"
  fi
}

mapfile -t BASE_PACKAGES < <(read_list "$PACMAN_LIST")
if (( ${#BASE_PACKAGES[@]} == 0 )); then
  echo "No pacman packages defined in $PACMAN_LIST" >&2
  exit 1
fi

if (( WITH_NVIDIA == 0 )) && command -v lspci >/dev/null 2>&1 && lspci | grep -qi 'NVIDIA'; then
  echo "info: NVIDIA hardware detected; leaving the current driver stack untouched (use --with-nvidia to opt in)." >&2
fi

PACMAN_FLAGS=()
YAY_FLAGS=()
if (( NONCONFIRM )); then
  PACMAN_FLAGS+=(--noconfirm)
  YAY_FLAGS+=(--noconfirm --answerclean None --answerdiff None)
fi

EXTRA_PACKAGES=()
if (( WITH_NVIDIA )); then
  mapfile -t EXTRA_PACKAGES < <(read_list "$NVIDIA_LIST")
fi

mapfile -t PACMAN_PACKAGES < <(filter_pacman_packages "${BASE_PACKAGES[@]}" "${EXTRA_PACKAGES[@]}")

if (( ${#PACMAN_PACKAGES[@]} > 0 )); then
  check_pacman_lock
  if (( DRY_RUN )); then
    echo "[dry-run] sudo pacman -Syu --needed ${PACMAN_FLAGS[*]} ${PACMAN_PACKAGES[*]}"
  else
    run_pacman -Syu --needed "${PACMAN_FLAGS[@]}" "${PACMAN_PACKAGES[@]}"
  fi
else
  echo "No installable pacman packages after filtering."
fi

if (( WITH_AUR )); then
  if (( EUID == 0 )); then
    if ! sudo -u "$AS_USER" env -u SUDO_USER -u SUDO_UID -u SUDO_GID \
      PATH="/usr/local/sbin:/usr/local/bin:/usr/bin:/bin" \
      sh -lc 'command -v yay >/dev/null 2>&1'; then
      echo "yay is required for AUR packages. Install yay for user '$AS_USER' first." >&2
      exit 1
    fi
  elif ! command -v yay >/dev/null 2>&1; then
    echo "yay is required for AUR packages. Install yay first." >&2
    exit 1
  fi

  mapfile -t AUR_PACKAGES < <(read_list "$AUR_LIST")
  if (( ${#AUR_PACKAGES[@]} > 0 )); then
    mapfile -t AUR_FILTERED < <(filter_aur_packages "${AUR_PACKAGES[@]}")
    if (( ${#AUR_FILTERED[@]} > 0 )); then
      if (( DRY_RUN )); then
        echo "[dry-run] yay -S --needed ${YAY_FLAGS[*]} ${AUR_FILTERED[*]}"
      else
        run_yay -S --needed "${YAY_FLAGS[@]}" "${AUR_FILTERED[@]}"
      fi
    else
      echo "No installable AUR packages after filtering."
    fi
  fi
fi

if (( ! DRY_RUN )) && command -v pkgfile >/dev/null 2>&1; then
  echo "Refreshing pkgfile database..."
  if (( EUID == 0 )); then
    pkgfile --update || echo "warning: pkgfile --update failed" >&2
  else
    sudo pkgfile --update || echo "warning: pkgfile --update failed" >&2
  fi
fi

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_ROOT=/var/lib/noxflow-workstation/resource-profile
SWAP_DIR=/swap
SWAP_FILE=/swap/swapfile
SWAP_SIZE=50G
FSTAB_LINE='/swap/swapfile none swap defaults,pri=10 0 0'

managed_files=(
  /etc/systemd/zram-generator.conf
  /etc/sysctl.d/90-noxflow-resources.conf
  /etc/systemd/oomd.conf.d/90-noxflow-resources.conf
  /etc/systemd/system/user.slice.d/90-noxflow-resources.conf
  /etc/fstab
)

need_root() {
  ((EUID == 0)) || {
    printf 'Run as root: sudo %q %s\n' "$0" "$*" >&2
    exit 2
  }
}

plan() {
  cat <<EOF
NoxFlow development resource profile:
  - configure 16 GiB zram (zstd, priority 100)
  - create a Btrfs-safe 50 GiB swapfile at $SWAP_FILE (priority 10)
  - prefer zram with vm.swappiness=180 and vm.page-cluster=0
  - enable systemd-oomd protection for the user slice
  - switch Docker from always-on service to socket activation
  - back up every replaced system file below $STATE_ROOT/backups
EOF
}

backup_path() {
  local backup="$1" path="$2" relative
  relative="${path#/}"
  if [[ -e "$path" || -L "$path" ]]; then
    install -d "$backup/$(dirname "$relative")"
    cp -a "$path" "$backup/$relative"
  else
    install -d "$backup/absent/$(dirname "$relative")"
    : >"$backup/absent/$relative"
  fi
}

record_service_state() {
  local backup="$1" unit="$2"
  systemctl is-enabled "$unit" >"$backup/${unit}.enabled" 2>/dev/null || true
  systemctl is-active "$unit" >"$backup/${unit}.active" 2>/dev/null || true
}

create_backup() {
  local stamp backup path
  stamp="$(date +%Y%m%d-%H%M%S)"
  backup="$STATE_ROOT/backups/$stamp"
  install -d "$backup"
  for path in "${managed_files[@]}"; do
    backup_path "$backup" "$path"
  done
  record_service_state "$backup" docker.service
  record_service_state "$backup" docker.socket
  record_service_state "$backup" containerd.service
  record_service_state "$backup" systemd-oomd.service
  printf '%s\n' "$stamp" >"$STATE_ROOT/last-backup"
  printf '%s\n' "$backup"
}

install_config() {
  local source="$1" target="$2"
  install -Dm644 "$REPO_DIR/$source" "$target"
}

ensure_swap() {
  local backup="$1"
  if [[ ! -e "$SWAP_DIR" ]]; then
    btrfs subvolume create "$SWAP_DIR"
    chmod 700 "$SWAP_DIR"
    : >"$backup/swap-subvolume-created"
  elif ! btrfs subvolume show "$SWAP_DIR" >/dev/null 2>&1; then
    printf '%s exists but is not a Btrfs subvolume; refusing to continue.\n' "$SWAP_DIR" >&2
    exit 1
  fi

  if [[ ! -e "$SWAP_FILE" ]]; then
    btrfs filesystem mkswapfile --size "$SWAP_SIZE" "$SWAP_FILE"
    : >"$backup/swapfile-created"
  fi

  if ! grep -Fqx "$FSTAB_LINE" /etc/fstab; then
    printf '\n# Managed by NoxFlow resource profile\n%s\n' "$FSTAB_LINE" >>/etc/fstab
  fi
  swapon --priority 10 "$SWAP_FILE" 2>/dev/null || true
}

apply_profile() {
  need_root apply
  local backup
  if [[ -e "$STATE_ROOT/applied" ]]; then
    printf 'Resource profile is already applied; verifying current state.\n'
    verify_profile
    return
  fi
  backup="$(create_backup)"

  install_config system/etc/systemd/zram-generator.conf /etc/systemd/zram-generator.conf
  install_config system/etc/sysctl.d/90-noxflow-resources.conf /etc/sysctl.d/90-noxflow-resources.conf
  install_config system/etc/systemd/oomd.conf.d/90-noxflow-resources.conf /etc/systemd/oomd.conf.d/90-noxflow-resources.conf
  install_config system/etc/systemd/system/user.slice.d/90-noxflow-resources.conf /etc/systemd/system/user.slice.d/90-noxflow-resources.conf
  ensure_swap "$backup"

  systemctl daemon-reload
  systemctl disable --now docker.service 2>/dev/null || true
  systemctl enable --now docker.socket 2>/dev/null || true
  systemctl stop containerd.service 2>/dev/null || true
  systemctl enable --now systemd-oomd.service
  sysctl --system >/dev/null
  : >"$STATE_ROOT/applied"

  printf 'Resource profile applied; backup: %s\n' "$backup"
  printf 'Reboot to resize zram from its current size to 16 GiB.\n'
}

size_gib() {
  awk -v bytes="$1" 'BEGIN { printf "%.1f", bytes / 1024 / 1024 / 1024 }'
}

verify_profile() {
  local rc=0 zram_size disk_size zram_prio disk_prio
  # Some util-linux versions ignore --output when combined with --raw. Read
  # the stable NAME TYPE SIZE USED PRIO columns instead of assuming a
  # two-column response.
  zram_size="$(swapon --show --bytes --noheadings --raw | awk '$1=="/dev/zram0" {print $3; exit}')"
  disk_size="$(swapon --show --bytes --noheadings --raw | awk -v file="$SWAP_FILE" '$1==file {print $3; exit}')"
  zram_prio="$(swapon --show --noheadings --raw | awk '$1=="/dev/zram0" {print $5; exit}')"
  disk_prio="$(swapon --show --noheadings --raw | awk -v file="$SWAP_FILE" '$1==file {print $5; exit}')"

  if [[ -n "$zram_size" ]]; then
    printf 'OK   zram: %s GiB, priority %s\n' "$(size_gib "$zram_size")" "$zram_prio"
    ((zram_size >= 15 * 1024 * 1024 * 1024)) || {
      printf 'WARN reboot required for 16 GiB zram\n'
      rc=1
    }
  else
    printf 'FAIL zram is not active\n' >&2
    rc=1
  fi
  if [[ -n "$disk_size" ]]; then
    printf 'OK   disk swap: %s GiB, priority %s\n' "$(size_gib "$disk_size")" "$disk_prio"
  else
    printf 'FAIL %s is not active\n' "$SWAP_FILE" >&2
    rc=1
  fi
  [[ "$zram_prio" == 100 ]] || {
    printf 'FAIL zram priority is not 100\n' >&2
    rc=1
  }
  [[ "$disk_prio" == 10 ]] || {
    printf 'FAIL disk swap priority is not 10\n' >&2
    rc=1
  }
  [[ "$(sysctl -n vm.swappiness)" == 180 ]] || {
    printf 'FAIL vm.swappiness is not 180\n' >&2
    rc=1
  }
  [[ "$(sysctl -n vm.page-cluster)" == 0 ]] || {
    printf 'FAIL vm.page-cluster is not 0\n' >&2
    rc=1
  }
  systemctl is-active --quiet systemd-oomd.service && printf 'OK   systemd-oomd active\n' || {
    printf 'FAIL systemd-oomd inactive\n' >&2
    rc=1
  }
  systemctl is-enabled --quiet docker.socket && printf 'OK   Docker socket enabled on demand\n' || {
    printf 'FAIL Docker socket is not enabled\n' >&2
    rc=1
  }
  systemctl is-active --quiet docker.service && printf 'INFO Docker daemon currently active\n' || printf 'OK   Docker daemon idle\n'
  return "$rc"
}

restore_path() {
  local backup="$1" path="$2" relative
  relative="${path#/}"
  if [[ -e "$backup/$relative" || -L "$backup/$relative" ]]; then
    install -d "$(dirname "$path")"
    rm -f "$path"
    cp -a "$backup/$relative" "$path"
  elif [[ -e "$backup/absent/$relative" ]]; then
    rm -f "$path"
  fi
}

restore_service() {
  local backup="$1" unit="$2" enabled active
  enabled="$(cat "$backup/${unit}.enabled" 2>/dev/null || true)"
  active="$(cat "$backup/${unit}.active" 2>/dev/null || true)"
  if [[ "$enabled" == enabled ]]; then systemctl enable "$unit" 2>/dev/null || true; else systemctl disable "$unit" 2>/dev/null || true; fi
  if [[ "$active" == active ]]; then systemctl start "$unit" 2>/dev/null || true; else systemctl stop "$unit" 2>/dev/null || true; fi
}

rollback_profile() {
  need_root rollback
  local stamp backup path
  stamp="$(cat "$STATE_ROOT/last-backup" 2>/dev/null || true)"
  [[ -n "$stamp" ]] || {
    printf 'No resource-profile backup found.\n' >&2
    exit 1
  }
  backup="$STATE_ROOT/backups/$stamp"
  [[ -d "$backup" ]] || {
    printf 'Missing backup: %s\n' "$backup" >&2
    exit 1
  }

  swapoff "$SWAP_FILE" 2>/dev/null || true
  for path in "${managed_files[@]}"; do restore_path "$backup" "$path"; done
  if [[ -e "$backup/swapfile-created" && -f "$SWAP_FILE" ]]; then rm -f "$SWAP_FILE"; fi
  if [[ -e "$backup/swap-subvolume-created" && -d "$SWAP_DIR" ]]; then btrfs subvolume delete "$SWAP_DIR"; fi
  restore_service "$backup" docker.socket
  restore_service "$backup" docker.service
  restore_service "$backup" containerd.service
  restore_service "$backup" systemd-oomd.service
  systemctl daemon-reload
  sysctl --system >/dev/null
  rm -f "$STATE_ROOT/applied"
  printf 'Restored resource profile backup: %s\n' "$backup"
  printf 'Reboot to restore the previous zram size.\n'
}

case "${1:-plan}" in
  plan | --dry-run) plan ;;
  apply) apply_profile ;;
  verify) verify_profile ;;
  rollback) rollback_profile ;;
  *)
    printf 'Usage: %s {plan|apply|verify|rollback}\n' "$0" >&2
    exit 2
    ;;
esac

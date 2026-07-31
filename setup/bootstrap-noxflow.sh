#!/usr/bin/env bash
# NoxFlow — Full production setup from dotfiles source.
# Idempotent: safe to run multiple times.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="${HOME}/.local/bin"
CONFIG_DIR="${HOME}/.config/noxflow"
STATE_DIR="${HOME}/.local/state/noxflow"
SYSTEMD_DIR="${HOME}/.config/systemd/user"

echo "=== NoxFlow Bootstrap ==="
echo "  Repo:     $REPO_DIR"
echo "  Bins:     $BIN_DIR"
echo "  Config:   $CONFIG_DIR"
echo "  State:    $STATE_DIR"
echo "  Systemd:  $SYSTEMD_DIR"
echo ""

# ── 1. Build from source ──
echo "--- Building Rust binaries ---"
cargo build --release --workspace --manifest-path "$REPO_DIR/Cargo.toml"

# ── 2. Install binaries ──
echo "--- Installing binaries ---"
mkdir -p "$BIN_DIR"
install -m 755 "$REPO_DIR/target/release/noxd" "$BIN_DIR/noxd"
install -m 755 "$REPO_DIR/target/release/noxctl" "$BIN_DIR/noxctl"
install -m 755 "$REPO_DIR/setup/noxflow-shell-launcher.sh" "$BIN_DIR/noxflow-shell"

# Verify architectures match
echo "  noxd:     $(file "$BIN_DIR/noxd" | grep -o 'ELF 64-bit\|ELF 32-bit\|script')"
echo "  noxctl:   $(file "$BIN_DIR/noxctl" | grep -o 'ELF 64-bit\|ELF 32-bit\|script')"
echo "  shell:    $(file "$BIN_DIR/noxflow-shell" | grep -o 'ELF 64-bit\|ELF 32-bit\|script')"

# ── 3. Symlink systemd units ──
echo "--- Installing systemd units ---"
mkdir -p "$SYSTEMD_DIR"
for f in noxd.service noxflow-shell.service noxflow-fallback.service noxflow-session-optional.service localsend.service; do
  if [ -f "$REPO_DIR/systemd/user/$f" ]; then
    ln -sf "$REPO_DIR/systemd/user/$f" "$SYSTEMD_DIR/$f"
    echo "  $f → $SYSTEMD_DIR/$f"
  fi
done
systemctl --user daemon-reload

# ── 4. Symlink shell QML ──
echo "--- Setting up shell config ---"
mkdir -p "$CONFIG_DIR"
if [ -L "$CONFIG_DIR/shell" ]; then
  rm "$CONFIG_DIR/shell"
fi
ln -sfn "$REPO_DIR/shell/noxflow" "$CONFIG_DIR/shell"
echo "  shell:    $CONFIG_DIR/shell → $REPO_DIR/shell/noxflow"

# ── 5. Symlink config.toml ──
if [ -f "$REPO_DIR/configs/noxflow/config.toml" ]; then
  ln -sf "$REPO_DIR/configs/noxflow/config.toml" "$CONFIG_DIR/config.toml"
  echo "  config:   $CONFIG_DIR/config.toml"
else
  echo "  config:   WARNING — configs/noxflow/config.toml not found, skipping"
fi

# ── 6. Set panel engine to noxflow ──
echo "--- Setting panel engine ---"
mkdir -p "$STATE_DIR"
echo "noxflow" > "$STATE_DIR/panel.engine"
echo "  engine:   $STATE_DIR/panel.engine → noxflow"

# ── 7. Enable and restart services ──
echo "--- Enabling services ---"
systemctl --user enable noxd.service 2>/dev/null || true
systemctl --user enable noxflow-shell.service 2>/dev/null || true

echo "--- Starting services ---"
systemctl --user restart noxd.service || true
sleep 1
systemctl --user restart noxflow-shell.service || true

# ── 8. Verify ──
echo ""
echo "=== Verification ==="
echo "  noxd:     $(systemctl --user is-active noxd.service)"
echo "  shell:    $(systemctl --user is-active noxflow-shell.service)"
echo "  noxctl:   $(command -v noxctl)"
echo ""
echo "=== Done ==="

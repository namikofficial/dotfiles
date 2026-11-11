#!/usr/bin/env bash
# Install the Devin CLI (local terminal coding agent) from the vendor manifest.
#
# The binary is installed into the XDG data dir with a versioned layout and a
# symlink on PATH. It is not managed by the system package manager, so this
# script is the single place that decides where it lives.
#
# Authentication is intentionally NOT performed here. Credentials are written
# by the user with:
#
#   devin auth login
#
# Usage: setup/install-devin-cli.sh [--dry-run]
set -euo pipefail

MANIFEST_URL="${DEVIN_CLI_MANIFEST_URL:-https://static.devin.ai/cli/current/manifest.json}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
INSTALL_ROOT="$DATA_HOME/devin/cli"
VERSIONS_DIR="$INSTALL_ROOT/_versions"
DRY_RUN=0

while (($#)); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    -h | --help)
      cat <<USAGE
Usage: setup/install-devin-cli.sh [--dry-run]
Installs the Devin CLI from the vendor manifest. Never touches credentials.
USAGE
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

for cmd in curl jq tar sha256sum; do
  command -v "$cmd" >/dev/null 2>&1 || {
    printf 'Missing command: %s\n' "$cmd" >&2
    exit 1
  }
done

case "$(uname -s)" in
  Linux) ;;
  Darwin) ;;
  *)
    printf 'Unsupported platform: %s\n' "$(uname -s)" >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  x86_64 | amd64) TARGET="x86_64-unknown-linux" ;;
  aarch64 | arm64) TARGET="aarch64-unknown-linux" ;;
  *)
    printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

printf 'Fetching Devin CLI manifest for %s\n' "$TARGET"
manifest="$(curl -fsSL "$MANIFEST_URL")"

version="$(printf '%s' "$manifest" | jq -r '.version // empty')"
[ -n "$version" ] || {
  printf 'Could not parse version from manifest\n' >&2
  exit 1
}

entry="$(printf '%s' "$manifest" | jq -c --arg t "$TARGET" '.platforms[$t] // empty')"
[ -n "$entry" ] || {
  printf 'No bundle available for platform %s\n' "$TARGET" >&2
  exit 1
}

url="$(printf '%s' "$entry" | jq -r '.url')"
expected_sha="$(printf '%s' "$entry" | jq -r '.sha256')"

version_dir="$VERSIONS_DIR/$version"
bin_path="$version_dir/bin/devin"

if [ -x "$bin_path" ]; then
  printf 'ok   Devin CLI %s already installed\n' "$version"
else
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  printf 'Downloading Devin CLI %s\n' "$version"
  archive="$tmp_dir/devin.tar.gz"
  curl -fsSL "$url" -o "$archive"

  actual_sha="$(sha256sum "$archive" | cut -d' ' -f1)"
  if [ "$actual_sha" != "$expected_sha" ]; then
    printf 'Checksum mismatch for %s\n' "$url" >&2
    printf 'Expected: %s\n' "$expected_sha" >&2
    printf 'Got:      %s\n' "$actual_sha" >&2
    exit 1
  fi

  extract_dir="$tmp_dir/extract"
  mkdir -p "$extract_dir"
  tar xzf "$archive" -C "$extract_dir"

  if ((DRY_RUN)); then
    printf '[dry-run] install Devin CLI %s to %s\n' "$version" "$version_dir"
  else
    rm -rf "$version_dir"
    mkdir -p "$version_dir"
    cp -a "$extract_dir/." "$version_dir/"
    printf 'curl-bash\n' >"$version_dir/distribution"
    printf 'Installed Devin CLI %s to %s\n' "$version" "$version_dir"
  fi
fi

if ((DRY_RUN)); then
  printf '[dry-run] ln -sfn %s %s\n' "$version" "$VERSIONS_DIR/current"
  printf '[dry-run] ln -sfn %s %s\n' "$VERSIONS_DIR/current/bin/devin" "$BIN_DIR/devin"
else
  mkdir -p "$BIN_DIR"
  ln -sfn "$version" "$VERSIONS_DIR/current"
  ln -sfn "$VERSIONS_DIR/current/bin/devin" "$BIN_DIR/devin"
  printf 'link %s -> %s\n' "$VERSIONS_DIR/current" "$version"
  printf 'link %s -> %s\n' "$BIN_DIR/devin" "$VERSIONS_DIR/current/bin/devin"
fi

printf '%s\n' 'Devin CLI installed. Sign in separately with: devin auth login'

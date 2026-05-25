#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK_ALL=0

usage() {
  cat <<USAGE
Usage: setup/check-shell.sh [--all]

Default: check changed shell scripts in this git worktree.
  --all   Check every shell script under setup, system, and hypr/scripts.
USAGE
}

while (($#)); do
  case "$1" in
    --all) CHECK_ALL=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

command -v shellcheck >/dev/null 2>&1 || {
  printf 'Missing command: shellcheck\n' >&2
  exit 1
}

command -v shfmt >/dev/null 2>&1 || {
  printf 'Missing command: shfmt\n' >&2
  exit 1
}

cd "$REPO_DIR"

declare -a files=()
if ((CHECK_ALL)); then
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find setup system hypr/scripts -type f -name '*.sh' -print0)
else
  while IFS= read -r file; do
    [ -f "$file" ] || continue
    case "$file" in
      setup/*.sh | system/*.sh | hypr/scripts/*.sh | hypr/scripts/*/*.sh) files+=("$file") ;;
    esac
  done < <(git ls-files --modified --others --exclude-standard)
fi

if ((${#files[@]} == 0)); then
  echo "No changed shell scripts to check. Use --all for full-tree check."
  exit 0
fi

printf 'Checking %s shell script(s)\n' "${#files[@]}"
shellcheck --severity=error "${files[@]}"
shfmt -d -i 2 -ci "${files[@]}"

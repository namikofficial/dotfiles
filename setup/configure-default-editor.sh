#!/usr/bin/env bash
set -euo pipefail

pick_editor_desktop() {
  local -a candidates=(
    "code.desktop"
    "visual-studio-code.desktop"
    "code-oss.desktop"
    "codium.desktop"
    "nvim.desktop"
  )
  local candidate

  for candidate in "${candidates[@]}"; do
    if [ -f "/usr/share/applications/${candidate}" ] || [ -f "$HOME/.local/share/applications/${candidate}" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

editor_desktop="${1:-}"
if [ -z "$editor_desktop" ]; then
  editor_desktop="$(pick_editor_desktop || true)"
fi

if [ -z "$editor_desktop" ]; then
  echo "No editor desktop file found."
  echo "Install VS Code or pass desktop id manually:"
  echo "  ./setup/configure-default-editor.sh code.desktop"
  exit 1
fi

mime_types=(
  "text/plain"
  "text/markdown"
  "application/json"
  "application/javascript"
  "text/javascript"
  "text/x-python"
  "text/x-shellscript"
  "text/x-csrc"
  "text/x-c++src"
  "text/x-java"
  "text/x-rustsrc"
  "application/x-yaml"
)

for mime in "${mime_types[@]}"; do
  xdg-mime default "$editor_desktop" "$mime" >/dev/null 2>&1 || true
done

echo "Default editor desktop: $editor_desktop"
echo "Applied MIME defaults:"
printf ' - %s\n' "${mime_types[@]}"

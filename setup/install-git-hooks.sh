#!/usr/bin/env bash
# Install a local pre-commit hook that runs setup/check-local.sh.
#
# Git reads hooks from the directory named by core.hooksPath. The managed
# gitconfig points that at ~/.config/git/hooks, so a hook written into
# .git/hooks is never executed — the previous version of this script
# installed a hook git silently ignored. This one asks git where to look and
# installs there.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"

hooks_path="$(git config --path --get core.hooksPath 2>/dev/null || true)"
if [ -z "$hooks_path" ]; then
  hooks_path="$REPO_DIR/.git/hooks"
fi
# A relative hooksPath is resolved against the top of the working tree.
case "$hooks_path" in
  /*) ;;
  *) hooks_path="$REPO_DIR/$hooks_path" ;;
esac

HOOK="$hooks_path/pre-commit"

mkdir -p "$hooks_path"

if [ -e "$HOOK" ] || [ -L "$HOOK" ]; then
  mv "$HOOK" "$HOOK.bak.$STAMP"
  echo "Backed up the existing hook to $HOOK.bak.$STAMP"
fi

# The repository path is baked in: the hook may live outside the checkout,
# where deriving it from the hook's own location would be wrong.
cat >"$HOOK" <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo "Running dotfiles local checks..."
exec "$REPO_DIR/setup/check-local.sh"
EOF

chmod +x "$HOOK"
echo "Installed pre-commit hook at $HOOK"

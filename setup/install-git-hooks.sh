#!/usr/bin/env bash
# Install a local pre-commit hook that runs setup/check-local.sh.
# Run once after cloning; the hook stays in .git/hooks/ (not committed).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_DIR/.git/hooks/pre-commit"

mkdir -p "$REPO_DIR/.git/hooks"

cat >"$HOOK" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
echo "Running dotfiles local checks..."
exec "$REPO_DIR/setup/check-local.sh"
EOF

chmod +x "$HOOK"
echo "Installed pre-commit hook at $HOOK"

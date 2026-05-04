#!/usr/bin/env bash
# empty-terminal.sh
# Bare terminal for running commands, starting projects, viewing logs

set -euo pipefail

project_path="${PWD}"
if [ "${#project_path}" -gt 46 ]; then
  project_path="...${project_path: -43}"
fi

# Print welcome banner
cat <<EOF

╔════════════════════════════════════════════════════════════════╗
║                     Project Runner                            ║
║  Run project commands, logs, or services here                 ║
║  Type 'project-logs' to view context-aware project logs       ║
║  Type 'exit' to close                                         ║
╚════════════════════════════════════════════════════════════════╝

EOF

printf 'Repo: %s\n\n' "$project_path"

# Start interactive shell
exec zsh -i

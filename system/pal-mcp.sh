#!/usr/bin/env bash
set -euo pipefail

pal_env="${XDG_CONFIG_HOME:-$HOME/.config}/pal/env"
if [[ -r "$pal_env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$pal_env"
  set +a
fi

export DEFAULT_MODEL="${DEFAULT_MODEL:-auto}"
export DISABLED_TOOLS="${DISABLED_TOOLS:-chat,precommit,secaudit,docgen,analyze,refactor,tracer,apilookup}"

exec /home/namik/.local/bin/uvx \
  --with 'mcp<2' \
  --from git+https://github.com/BeehiveInnovations/pal-mcp-server.git \
  pal-mcp-server

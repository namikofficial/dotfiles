# shellcheck shell=bash
# Load the MiniMax Token Plan key only for Claude Code invocations.
# This file is sourced by the repository-managed Bash and Zsh startup files.
claude() {
  local minimax_token_file="$HOME/.config/minimax/token"
  local minimax_token

  if [[ ! -r "$minimax_token_file" ]]; then
    printf 'claude: MiniMax token file is missing or unreadable: %s\n' "$minimax_token_file" >&2
    return 1
  fi
  IFS= read -r minimax_token <"$minimax_token_file"
  if [[ -z "$minimax_token" ]]; then
    printf 'claude: MiniMax token file is empty: %s\n' "$minimax_token_file" >&2
    return 1
  fi

  (
    unset ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN
    export ANTHROPIC_AUTH_TOKEN="$minimax_token"
    export ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic"
    command "$HOME/.local/bin/claude" "$@"
  )
}

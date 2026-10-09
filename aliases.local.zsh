# Local aliases/functions loaded after aliases.zsh.
# This file is tracked in git by design.
#
# In order to keep custom machine-specific tweaks here so they stay separate from
# shared defaults in aliases.zsh.
#
# Example:
# alias myvpn='~/scripts/connect-vpn'

# Local project shortcuts.
alias wellvantage='cd ~/Documents/code/WellVantage'
alias trackme='cd /home/namik/Documents/code/trackMe'
alias scripts='cd ${SCRIPTS_HOME:-$HOME/Documents/code/dotfiles/private/scripts}'
alias dotfiles='cd ~/Documents/code/dotfiles'

# ── NoxOrigin ───────────────────────────────────────────────────────────────
# ~/Documents/code/noxorigin holds three repos: noxorigin (product monorepo),
# noxorigin-docs (Docusaurus) and noxorigin-website (Next.js).
NOXORIGIN_HOME="${NOXORIGIN_HOME:-$HOME/Documents/code/noxorigin}"
NOX_REPO="$NOXORIGIN_HOME/noxorigin"
NOX_DOCS_REPO="$NOXORIGIN_HOME/noxorigin-docs"
NOX_WEB_REPO="$NOXORIGIN_HOME/noxorigin-website"
NOX_DOTFILES_HOME="${DOTFILES_HOME:-$HOME/Documents/code/dotfiles}"
NOX_SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$NOX_DOTFILES_HOME/private/scripts/noxorigin/sops/age/keys.txt}"

# sops only looks in ~/.config/sops/age/keys.txt by default; point it at the
# private-submodule key so `sops`, `just secrets-check` and VS Code launched
# from a terminal can all decrypt without per-command flags.
if [[ -z "${SOPS_AGE_KEY_FILE:-}" && -r "$NOX_SOPS_AGE_KEY_FILE" ]]; then
  export SOPS_AGE_KEY_FILE="$NOX_SOPS_AGE_KEY_FILE"
fi

alias nox-root='cd "$NOXORIGIN_HOME"'
alias noxorigin='cd "$NOX_REPO"'
alias nox='cd "$NOX_REPO"'
alias nox-docs='cd "$NOX_DOCS_REPO"'
alias nox-web='cd "$NOX_WEB_REPO"'

nox-edit() { code "$NOX_REPO" "$@"; }
nox-docs-edit() { code "$NOX_DOCS_REPO" "$@"; }
nox-web-edit() { code "$NOX_WEB_REPO" "$@"; }

# Run a recipe from the noxorigin justfile from any directory.
nox-just() { just --justfile "$NOX_REPO/justfile" "$@"; }
nox-up() { nox-just up "$@"; }
nox-down() { nox-just down "$@"; }
nox-status() { nox-just status "$@"; }
nox-logs() { nox-just logs "$@"; }

nox-env-file() {
  case "${1:-}" in
    staging|production|redis) printf '%s/deploy/env/%s.env.sops\n' "$NOX_REPO" "$1" ;;
    android-signing) printf '%s/deploy/secrets/android-signing.env.sops\n' "$NOX_REPO" ;;
    *)
      print -u2 "Usage: ${funcstack[2]:-nox-env-file} staging|production|redis|android-signing"
      return 2
      ;;
  esac
}

# Open an encrypted env in VS Code; the SOPS extension decrypts it in memory
# and re-encrypts on save.
nox-env-edit() {
  local env_file
  env_file="$(nox-env-file "$@")" || return
  [[ -f "$env_file" ]] || { print -u2 "Encrypted environment file not found: $env_file"; return 1; }
  code "$env_file"
}

# Terminal alternative: `sops edit` in $EDITOR. The .env.sops suffix is not a
# format sops recognises, so the dotenv type must be explicit.
nox-env-sops() {
  local env_file
  env_file="$(nox-env-file "$@")" || return
  [[ -f "$env_file" ]] || { print -u2 "Encrypted environment file not found: $env_file"; return 1; }
  [[ -r "$NOX_SOPS_AGE_KEY_FILE" ]] || { print -u2 "SOPS age key is not readable: $NOX_SOPS_AGE_KEY_FILE"; return 1; }
  (cd "$NOX_REPO" && SOPS_AGE_KEY_FILE="$NOX_SOPS_AGE_KEY_FILE" \
    sops edit --input-type dotenv --output-type dotenv "$env_file")
}

# Validate every tracked *.env.sops without printing values.
nox-env-validate() {
  [[ -r "$NOX_SOPS_AGE_KEY_FILE" ]] || { print -u2 "SOPS age key is not readable: $NOX_SOPS_AGE_KEY_FILE"; return 1; }
  (cd "$NOX_REPO" && SOPS_AGE_KEY_FILE="$NOX_SOPS_AGE_KEY_FILE" just secrets-check)
}

nox-help() {
  print 'NoxOrigin shortcuts:'
  print '  nox / noxorigin        cd into the noxorigin monorepo'
  print '  nox-docs / nox-web     cd into noxorigin-docs / noxorigin-website'
  print '  nox-root               cd into ~/Documents/code/noxorigin'
  print '  nox-edit, nox-docs-edit, nox-web-edit   Open a repo in VS Code'
  print '  nox-just RECIPE        Run a noxorigin just recipe from anywhere'
  print '  nox-up / nox-down / nox-status / nox-logs SVC   Dev stack wrappers'
  print '  nox-env-edit NAME      Edit encrypted env in VS Code (staging|production|redis|android-signing)'
  print '  nox-env-sops NAME      Edit encrypted env with sops in $EDITOR'
  print '  nox-env-validate       Validate all encrypted envs (just secrets-check)'
  print 'trackMe: trackme, trackme-edit, trackme-env-edit NAME, trackme-up, trackme-log'
}

# ── trackMe ─────────────────────────────────────────────────────────────────
trackme-edit() {
  code /home/namik/Documents/code/trackMe "$@"
}

trackme-env-edit() {
  local environment="${1:-}"
  local env_file
  case "$environment" in
    staging) env_file="$HOME/Documents/code/trackMe/backend/.env" ;;
    production) env_file="$HOME/Documents/code/trackMe/backend/.env.prod" ;;
    *) print -u2 "Usage: trackme-env-edit staging|production"; return 2 ;;
  esac
  [[ -f "$env_file" ]] || { print -u2 "Environment file not found: $env_file"; return 1; }
  code "$env_file"
}

trackme-log() {
  cd /home/namik/Documents/code/trackMe/backend && npm run docker:logs "$@"
}

trackme-up() {
  just --justfile /home/namik/Documents/code/trackMe/justfile up "$@"
}

# Use Kitty's SSH kitten to auto-bootstrap remote terminal capabilities.
if command -v kitten >/dev/null 2>&1; then
  alias ssh='kitten ssh'
fi

vpn-connect() {
  "${SCRIPTS_BIN:-${DOTFILES_HOME:-$HOME/Documents/code/dotfiles}/private/scripts/bin}/vpn-connect" "$@"
}

vpn-disconnect() {
  "${SCRIPTS_BIN:-${DOTFILES_HOME:-$HOME/Documents/code/dotfiles}/private/scripts/bin}/vpn-disconnect" "$@"
}

vpn-logs() {
  "${SCRIPTS_BIN:-${DOTFILES_HOME:-$HOME/Documents/code/dotfiles}/private/scripts/bin}/vpn-logs" "$@"
}

vpn-status() {
  "${SCRIPTS_BIN:-${DOTFILES_HOME:-$HOME/Documents/code/dotfiles}/private/scripts/bin}/vpn-status" "$@"
}

smbshare() {
  "${SCRIPTS_BIN:-${DOTFILES_HOME:-$HOME/Documents/code/dotfiles}/private/scripts/bin}/smb-share" "$@"
}

batroot() {
  if command -v bat >/dev/null 2>&1; then
    sudo bat --paging=never --style=plain "$@"
  elif command -v batcat >/dev/null 2>&1; then
    sudo batcat --paging=never --style=plain "$@"
  else
    sudo cat "$@"
  fi
}

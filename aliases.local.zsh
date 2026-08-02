# Local aliases/functions loaded after aliases.zsh.
# This file is tracked in git by design.
#
# In order to keep custom machine-specific tweaks here so they stay separate from
# shared defaults in aliases.zsh.
#
# Example:
# alias myvpn='~/scripts/connect-vpn'

# Local project shortcuts.
alias noxcrm='cd /home/namik/Documents/code/noxorigin/workspace'
alias nox-billings='cd /home/namik/Documents/code/noxorigin/nox-billings'
alias nox-tickets='cd /home/namik/Documents/code/noxorigin/nox-tickets'
alias noxorigin='cd /home/namik/Documents/code/noxorigin'
alias wellvantage='cd ~/Documents/code/WellVantage'
alias scripts='cd ${SCRIPTS_HOME:-$HOME/Documents/code/dotfiles/private/scripts}'
alias dotfiles='cd ~/Documents/code/dotfiles'

NOXORIGIN_HOME="${NOXORIGIN_HOME:-$HOME/Documents/code/noxorigin}"
NOX_DOTFILES_HOME="${DOTFILES_HOME:-$HOME/Documents/code/dotfiles}"
NOX_SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$NOX_DOTFILES_HOME/private/scripts/noxorigin/sops/age/keys.txt}"

nox-ensure-root() {
  if [[ ! -d "$NOXORIGIN_HOME" ]]; then
    print -u2 "NoxOrigin workspace not found: $NOXORIGIN_HOME"
    return 1
  fi
}

nox-env-file() {
  local environment="${1:-}"
  case "$environment" in
    staging|production) ;;
    *)
      print -u2 "Usage: nox-env-edit staging|production"
      return 2
      ;;
  esac
  printf '%s/workspace/infra/env/%s.env.sops\n' "$NOXORIGIN_HOME" "$environment"
}

nox-env-edit() {
  nox-ensure-root || return
  local env_file
  env_file="$(nox-env-file "$1")" || return
  [[ -f "$env_file" ]] || { print -u2 "Encrypted environment file not found: $env_file"; return 1; }
  code "$env_file"
}

nox-billings-env-edit() {
  local environment="${1:-}"
  case "$environment" in
    staging|production) ;;
    *) print -u2 "Usage: nox-billings-env-edit staging|production"; return 2 ;;
  esac
  local env_file="$NOXORIGIN_HOME/nox-billings/deploy/server/env.${environment}.env.sops"
  [[ -f "$env_file" ]] || { print -u2 "Encrypted environment file not found: $env_file"; return 1; }
  code "$env_file"
}

nox-tickets-env-edit() {
  local environment="${1:-}"
  case "$environment" in
    staging|production) ;;
    *) print -u2 "Usage: nox-tickets-env-edit staging|production"; return 2 ;;
  esac
  local env_file="$NOXORIGIN_HOME/nox-tickets/deploy/server/env.${environment}.env.sops"
  [[ -f "$env_file" ]] || { print -u2 "Encrypted environment file not found: $env_file"; return 1; }
  code "$env_file"
}

nox-env-validate() {
  nox-ensure-root || return
  local environment="${1:-}"
  case "$environment" in
    staging|production) ;;
    *)
      print -u2 "Usage: nox-env-validate staging|production"
      return 2
      ;;
  esac
  [[ -r "$NOX_SOPS_AGE_KEY_FILE" ]] || {
    print -u2 "SOPS age key is not readable: $NOX_SOPS_AGE_KEY_FILE"
    return 1
  }
  SOPS_AGE_KEY_FILE="$NOX_SOPS_AGE_KEY_FILE" \
    "$NOXORIGIN_HOME/workspace/infra/scripts/validate-sops-env.sh"
}

nox-infra-edit() {
  nox-ensure-root || return
  code "$NOXORIGIN_HOME/workspace/infra" "$@"
}

nox-help() {
  print 'NoxOrigin shortcuts:'
  print '  noxorigin              Open the umbrella workspace'
  print '  noxcrm                 Enter the NoxCRM workspace'
  print '  nox-billings           Enter the Nox-Billings workspace'
  print '  nox-env-edit staging   Edit encrypted staging environment in VS Code'
  print '  nox-env-edit production Edit encrypted production environment in VS Code'
  print '  nox-billings-env-edit NAME Edit Nox-Billings encrypted environment'
  print '  nox-tickets-env-edit NAME Edit Nox-Tickets encrypted environment'
  print '  nox-env-validate NAME  Validate encrypted deployment environment'
  print '  nox-infra-edit         Open workspace infrastructure'
}

noxcrm-edit() {
  code /home/namik/Documents/code/noxorigin/workspace "$@"
}

nox-billings-edit() {
  code /home/namik/Documents/code/noxorigin/nox-billings "$@"
}

nox-tickets-edit() {
  code /home/namik/Documents/code/noxorigin/nox-tickets "$@"
}

noxorigin-edit() {
  code /home/namik/Documents/code/noxorigin "$@"
}

noxcrm-log() {
  :
}

nox-billings-log() {
  :
}

nox-billings-emulator() {
  "${DOTFILES_HOME:-$HOME/Documents/code/dotfiles}/hypr/scripts/android-dev.sh" start Noxflow_API_36 "$@"
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

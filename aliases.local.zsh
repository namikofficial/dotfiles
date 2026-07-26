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

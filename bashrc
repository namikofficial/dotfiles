# shellcheck shell=bash
#
# ~/.bashrc — repository-managed interactive Bash startup
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                   # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" # This loads nvm bash_completion

if [ -r "$HOME/.cargo/env" ]; then
  . "$HOME/.cargo/env"
fi

if [ -f "$HOME/.config/trackme/android-env.sh" ]; then
  . "$HOME/.config/trackme/android-env.sh"
fi

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
# pnpm end
export PATH="$PATH:$HOME/.maestro/bin"

# Added by Antigravity CLI installer
export PATH="$HOME/.local/bin:$PATH"

DOTFILES_HOME="${DOTFILES_HOME:-$HOME/Documents/code/dotfiles}"
if [ -r "$DOTFILES_HOME/shell/claude-minimax.sh" ]; then
  . "$DOTFILES_HOME/shell/claude-minimax.sh"
fi

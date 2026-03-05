# Suppress zsh-syntax-highlighting "unhandled ZLE widget" warnings globally.
# Keep this at the top so it applies even if the plugin is sourced early.
typeset -g ZSH_HIGHLIGHT_WARNINGS=0

# Color support for prompt/completion
autoload -Uz colors && colors
zmodload zsh/datetime

# Centralize repo locations so we can source shared configs from here.
if [[ -z "${DOTFILES_HOME:-}" ]]; then
  zshrc_source="${(%):-%N}"
  DOTFILES_HOME="${zshrc_source:A:h}"
fi

if [[ -z "${SCRIPTS_HOME:-}" ]]; then
  for scripts_candidate in \
    "$HOME/Documents/code/scripts" \
    "$HOME/dev/personal-scripts"; do
    if [[ -d "$scripts_candidate" ]]; then
      SCRIPTS_HOME="$scripts_candidate"
      break
    fi
  done
fi

SCRIPTS_HOME="${SCRIPTS_HOME:-$HOME/Documents/code/scripts}"
SCRIPTS_BIN="${SCRIPTS_BIN:-$SCRIPTS_HOME/bin}"
export DOTFILES_HOME SCRIPTS_HOME SCRIPTS_BIN
unset zshrc_source scripts_candidate

# Optional startup profiler.
if [[ "${ZSH_PROFILE_STARTUP:-0}" == "1" ]]; then
  zmodload zsh/zprof
  typeset -g __ZSH_STARTUP_BEGIN_MS="${EPOCHREALTIME}"
fi

# Shell behavior
setopt autocd interactive_comments noclobber no_beep
setopt hist_ignore_all_dups hist_ignore_space hist_reduce_blanks hist_save_no_dups
setopt share_history append_history inc_append_history extended_history hist_fcntl_lock
# Keep unmatched globs explicit to avoid accidental wildcard typos.
setopt nomatch
bindkey -e
typeset -U path PATH

# History
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history

# Repair common history corruption (NUL bytes) once, with backup.
if [ -f "$HISTFILE" ] && [ "$(LC_ALL=C tr -cd '\000' < "$HISTFILE" | wc -c)" -gt 0 ]; then
  hist_backup="${HISTFILE}.corrupt.$(date +%Y%m%d_%H%M%S)"
  hist_tmp="${HISTFILE}.tmp.$$"
  cp "$HISTFILE" "$hist_backup"
  tr -d '\000' < "$hist_backup" >| "$hist_tmp"
  mv "$hist_tmp" "$HISTFILE"
  chmod 600 "$HISTFILE"
  echo "zsh: repaired history file (backup: $hist_backup)" >&2
  unset hist_backup
  unset hist_tmp
fi

# Completion setup
mkdir -p "$HOME/.cache/zsh"

# zsh-completions (must be in fpath before compinit)
if [ -d "$HOME/.local/share/zsh/plugins/zsh-completions/src" ]; then
  fpath=("$HOME/.local/share/zsh/plugins/zsh-completions/src" $fpath)
fi

autoload -Uz compinit
zmodload -F zsh/stat b:zstat 2>/dev/null || true
zcompdump_file="$HOME/.cache/zsh/.zcompdump"
zcompdump_refresh_days="${ZCOMPDUMP_REFRESH_DAYS:-7}"
zcompdump_age_seconds=$(( zcompdump_refresh_days * 86400 ))
zcompdump_is_fresh=0
if [[ -f "$zcompdump_file" ]]; then
  typeset -A _zstat_data
  if zstat -H _zstat_data -F %s +mtime "$zcompdump_file" 2>/dev/null; then
    if (( EPOCHSECONDS - _zstat_data[mtime] < zcompdump_age_seconds )); then
      zcompdump_is_fresh=1
    fi
  fi
fi
if (( zcompdump_is_fresh )); then
  compinit -C -d "$zcompdump_file"
else
  compinit -d "$zcompdump_file"
fi
unset zcompdump_file zcompdump_refresh_days zcompdump_age_seconds zcompdump_is_fresh _zstat_data

zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete _correct _approximate
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' list-prompt '%SAt %p: hit TAB for more%s'
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
zstyle ':completion:*' menu select=long
zstyle ':completion:*' select-prompt '%SScrolling active: current selection at %p%s'
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

if command -v dircolors >/dev/null 2>&1; then
  eval "$(dircolors -b)"
  zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
fi

# Warn once per day when commonly expected tools are missing.
warn_missing_tools_once() {
  emulate -L zsh
  [[ -o interactive ]] || return 0

  local cache_dir="$HOME/.cache/zsh"
  local stamp_file="${cache_dir}/.missing-tools-warned-$(date +%Y%m%d)"
  mkdir -p "$cache_dir"
  [ -f "$stamp_file" ] && return 0

  local -a expected_tools=(fzf rg eza zoxide)
  local -a missing_tools=()
  local tool
  for tool in "${expected_tools[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || missing_tools+=("$tool")
  done

  if (( ${#missing_tools[@]} > 0 )); then
    print -P "%F{yellow}zsh:%f missing optional tools: ${missing_tools[*]}"
    print -P "%F{yellow}zsh:%f run 'dev-doctor' and see docs/setup.md for install guidance"
  fi

  : >| "$stamp_file"
}
warn_missing_tools_once

# Small TTL cache for expensive shell lookups.
zsh_cache_run() {
  emulate -L zsh
  local key="$1"
  local ttl="${2:-60}"
  shift 2

  local safe_key="${key//[^A-Za-z0-9_.-]/_}"
  local cache_file="$HOME/.cache/zsh/${safe_key}.cache"
  local age=999999
  typeset -A _cache_stat

  if [[ -f "$cache_file" ]] && zstat -H _cache_stat -F %s +mtime "$cache_file" 2>/dev/null; then
    age=$(( EPOCHSECONDS - _cache_stat[mtime] ))
  fi

  if (( age < ttl )); then
    cat "$cache_file"
    return 0
  fi

  local out
  out="$("$@" 2>/dev/null || true)"
  print -r -- "$out" >| "$cache_file"
  print -r -- "$out"
}

# Colorful ls defaults (prefer eza)
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --icons=auto --group-directories-first'
  alias ll='eza -lah --icons=auto --group-directories-first --git'
elif ls --color=auto -d . >/dev/null 2>&1; then
  alias ls='ls --color=auto -hF'
  alias ll='ls -la'
elif ls -G -d . >/dev/null 2>&1; then
  alias ls='ls -G -hF'
  alias ll='ls -la'
fi

# Unified list presets across eza/GNU/BSD ls.
_ls_unified() {
  emulate -L zsh
  local mode="$1"
  shift || true
  if command -v eza >/dev/null 2>&1; then
    case "$mode" in
      all) eza -la --icons=auto --group-directories-first "$@" ;;
      time) eza -lah --sort=modified --icons=auto --group-directories-first "$@" ;;
      size) eza -lah --sort=size --icons=auto --group-directories-first "$@" ;;
      *) eza --icons=auto --group-directories-first "$@" ;;
    esac
    return 0
  fi

  if ls --color=auto -d . >/dev/null 2>&1; then
    case "$mode" in
      all) command ls -lah --color=auto "$@" ;;
      time) command ls -lath --color=auto "$@" ;;
      size) command ls -laSh --color=auto "$@" ;;
      *) command ls -hF --color=auto "$@" ;;
    esac
    return 0
  fi

  if ls -G -d . >/dev/null 2>&1; then
    case "$mode" in
      all) command ls -lahG "$@" ;;
      time) command ls -latGh "$@" ;;
      size) command ls -laSGh "$@" ;;
      *) command ls -hFG "$@" ;;
    esac
    return 0
  fi
}
la() { _ls_unified all "$@"; }
lt() { _ls_unified time "$@"; }
lS() { _ls_unified size "$@"; }

# Auto-ls controls:
#   AUTO_LS=0 disables automatic listing after cd
#   AUTO_LS_MAX_ENTRIES limits auto-ls output size in large directories
AUTO_LS="${AUTO_LS:-1}"
AUTO_LS_MAX_ENTRIES="${AUTO_LS_MAX_ENTRIES:-200}"

# Auto-list directory contents after changing directories.
auto_ls_chpwd() {
  emulate -L zsh
  [[ "$AUTO_LS" == "0" ]] && return 0
  [[ -o interactive ]] || return 0

  integer max_entries=200
  if [[ "$AUTO_LS_MAX_ENTRIES" == <-> ]] && (( AUTO_LS_MAX_ENTRIES > 0 )); then
    max_entries=$AUTO_LS_MAX_ENTRIES
  fi

  local -a entries
  entries=( *(DN) )
  integer total_entries=${#entries}

  if ! [[ -t 1 ]]; then
    command ls -1A
    return 0
  fi

  if (( total_entries > max_entries )); then
    print -P "%F{yellow}auto-ls:%f showing first ${max_entries}/${total_entries} entries (set AUTO_LS_MAX_ENTRIES to change)"
    command ls -1A | head -n "$max_entries"
    return 0
  fi

  if command -v eza >/dev/null 2>&1; then
    eza --icons=auto --group-directories-first
  elif ls --color=auto -d . >/dev/null 2>&1; then
    command ls --color=auto -hF
  elif ls -G -d . >/dev/null 2>&1; then
    command ls -G -hF
  else
    command ls -hF
  fi
}
typeset -ga chpwd_functions
if (( ${chpwd_functions[(Ie)auto_ls_chpwd]} == 0 )); then
  chpwd_functions+=(auto_ls_chpwd)
fi

# Startup behavior controls
ZSH_LAZY_LOAD_HEAVY="${ZSH_LAZY_LOAD_HEAVY:-1}"

# NVM init (lazy by default)
export NVM_DIR="$HOME/.nvm"
_load_nvm() {
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
}
if [ -s "$NVM_DIR/nvm.sh" ]; then
  if [[ "$ZSH_LAZY_LOAD_HEAVY" == "1" ]]; then
    nvm() {
      unset -f nvm
      _load_nvm
      nvm "$@"
    }
  elif ! command -v nvm >/dev/null 2>&1; then
    _load_nvm
  fi
fi

# Ensure common user bin paths are present (without duplicates).
for user_bin in "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/bin"; do
  [ -d "$user_bin" ] && path=("$user_bin" $path)
done

find_codex_bin_dir() {
  emulate -L zsh
  typeset -a latest_node_dirs
  latest_node_dirs=("$HOME"/.nvm/versions/node/*(N/om[1]))
  if [ -n "${latest_node_dirs[1]}" ] && [ -x "${latest_node_dirs[1]}/bin/codex" ]; then
    print -r -- "${latest_node_dirs[1]}/bin"
    return 0
  fi
  for codex_bin in "$HOME"/.vscode/extensions/openai.chatgpt-*-linux-x64/bin/linux-x86_64/codex(N); do
    [ -x "$codex_bin" ] || continue
    print -r -- "${codex_bin:h}"
    return 0
  done
  return 1
}

# Ensure codex CLI stays available even if Node/NVM PATH state changes.
if ! command -v codex >/dev/null 2>&1; then
  codex_bin_dir="$(zsh_cache_run codex_bin_dir 600 find_codex_bin_dir)"
  [ -n "$codex_bin_dir" ] && path=("$codex_bin_dir" $path)
fi

# GitHub Copilot shell aliases (safe no-op when not installed).
if command -v gh >/dev/null 2>&1; then
  if gh extension list 2>/dev/null | rg -q 'github/gh-copilot'; then
    eval "$(gh copilot alias -- zsh)"
  fi
elif command -v github-copilot-cli >/dev/null 2>&1; then
  eval "$(github-copilot-cli alias -- zsh)"
fi

# Android SDK Configuration
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
path=(
  "$ANDROID_SDK_ROOT/emulator"
  "$ANDROID_SDK_ROOT/platform-tools"
  "$ANDROID_SDK_ROOT/build-tools/35.0.0"
  "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin"
  $path
)

# Android Studio
export ANDROID_STUDIO="/opt/android-studio"

# Gradle
export GRADLE_HOME="$HOME/gradle/gradle-8.13"
path=("$GRADLE_HOME/bin" $path)

# Zoxide (smarter cd)
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

# FZF (fuzzy finder, lazy integration by default)
_fzf_integration_loaded=0
load_fzf_integration() {
  (( _fzf_integration_loaded )) && return 0
  if fzf --zsh >/dev/null 2>&1; then
    eval "$(fzf --zsh)"
  else
    [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && source /usr/share/doc/fzf/examples/key-bindings.zsh
    [ -f /usr/share/doc/fzf/examples/completion.zsh ] && source /usr/share/doc/fzf/examples/completion.zsh
  fi
  _fzf_integration_loaded=1
}
if command -v fzf >/dev/null 2>&1; then
  if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
  fi
  export FZF_DEFAULT_OPTS="--height=55% --layout=reverse --border=rounded --info=inline-right --pointer='>' --marker='*' --color=fg:#d0d0d0,bg:#11111b,hl:#f5c2e7,fg+:#ffffff,bg+:#313244,hl+:#89b4fa,prompt:#a6e3a1,pointer:#f38ba8,marker:#fab387,info:#94e2d5"
  if [[ "$ZSH_LAZY_LOAD_HEAVY" == "1" ]]; then
    fzf() {
      load_fzf_integration
      command fzf "$@"
    }
  else
    load_fzf_integration
  fi
fi

# Wallpaper-driven shell tool theme overrides (fzf, bat, lazygit).
if [ -f "$HOME/.cache/hypr/theme-shell.zsh" ]; then
  source "$HOME/.cache/hypr/theme-shell.zsh"
fi

# fzf-git.sh (Ctrl-g shortcuts for git objects)
if [ -f "$HOME/.local/share/zsh/plugins/fzf-git.sh/fzf-git.sh" ]; then
  source "$HOME/.local/share/zsh/plugins/fzf-git.sh/fzf-git.sh"
fi

# fzf-tab (interactive fuzzy completion menu)
fzf_tab_loaded=0
for plugin in \
  "$HOME/.local/share/zsh/plugins/fzf-tab/fzf-tab.plugin.zsh" \
  /usr/share/zsh/plugins/fzf-tab/fzf-tab.plugin.zsh \
  /usr/share/fzf-tab/fzf-tab.plugin.zsh; do
  [ -f "$plugin" ] || continue
  source "$plugin"
  fzf_tab_loaded=1
  break
done
if (( fzf_tab_loaded )); then
  zstyle ':fzf-tab:*' fzf-command fzf
  zstyle ':fzf-tab:*' switch-group ',' '.'
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color=always -1 $realpath 2>/dev/null'
fi
unset fzf_tab_loaded

# direnv (project-local env loading)
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi

# atuin (better shell history)
_atuin_loaded=0
load_atuin_integration() {
  (( _atuin_loaded )) && return 0
  eval "$(command atuin init zsh)"
  _atuin_loaded=1
}
if command -v atuin >/dev/null 2>&1; then
  load_atuin_integration
fi

# pay-respects (modern command correction + command-not-found)
if command -v pay-respects >/dev/null 2>&1; then
  eval "$(pay-respects zsh --alias fuck)"
fi

# zsh-you-should-use (teaches aliases)
for plugin in \
  "$HOME/.local/share/zsh/plugins/zsh-you-should-use/you-should-use.plugin.zsh" \
  /usr/share/zsh/plugins/zsh-you-should-use/you-should-use.plugin.zsh; do
  [ -f "$plugin" ] || continue
  # NOTE: plugin enables hardcore if the variable merely exists (even "0")
  unset YSU_HARDCORE
  export YSU_MODE=BESTMATCH
  source "$plugin"
  break
done

# zsh-vi-mode (Vim motions in command line editing)
for plugin in \
  "$HOME/.local/share/zsh/plugins/zsh-vi-mode/zsh-vi-mode.plugin.zsh" \
  /usr/share/zsh/plugins/zsh-vi-mode/zsh-vi-mode.plugin.zsh; do
  [ -f "$plugin" ] && source "$plugin" && break
done

# Optional plugins (if installed)
for plugin in \
  "$HOME/.local/share/zsh/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh" \
  /usr/share/zsh/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh; do
  [ -f "$plugin" ] && source "$plugin" && break
done

for plugin in \
  "$HOME/.local/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" \
  /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
  /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh; do
  [ -f "$plugin" ] && source "$plugin" && break
done
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6c7086'

# zsh-autopair
for plugin in \
  "$HOME/.local/share/zsh/plugins/zsh-autopair/autopair.zsh" \
  /usr/share/zsh/plugins/zsh-autopair/autopair.zsh; do
  [ -f "$plugin" ] && source "$plugin" && break
done

# zsh-history-substring-search
for plugin in \
  "$HOME/.local/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh" \
  /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh; do
  [ -f "$plugin" ] || continue
  source "$plugin"
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
  bindkey '^P' history-substring-search-up
  bindkey '^N' history-substring-search-down
  break
done

# forgit (widgets / keybindings)
for plugin in \
  "$HOME/.local/share/zsh/plugins/forgit/forgit.plugin.zsh" \
  /usr/share/zsh/plugins/forgit/forgit.plugin.zsh; do
  [ -f "$plugin" ] && source "$plugin" && break
done

typeset -gi __nox_syntax_highlight_loaded=0
for plugin in \
  "$HOME/.local/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh" \
  /usr/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh \
  /usr/share/zsh-fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh; do
  [ -f "$plugin" ] || continue
  { source "$plugin"; } 2>/dev/null
  __nox_syntax_highlight_loaded=1
  break
done

if (( ! __nox_syntax_highlight_loaded )); then
  for plugin in \
    "$HOME/.local/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
    /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
    [ -f "$plugin" ] && { source "$plugin"; } 2>/dev/null && break
  done
fi
unset __nox_syntax_highlight_loaded

# History/jump UX: Ctrl-r for Atuin search, Alt-c for fuzzy directory jump.
if [[ -o interactive ]]; then
  if zle -l | command grep -Eq '^atuin-search([[:space:]]|$)'; then
    bindkey '^R' atuin-search
    bindkey -M emacs '^R' atuin-search 2>/dev/null || true
    if zle -l | command grep -Eq '^atuin-search-viins([[:space:]]|$)'; then
      bindkey -M viins '^R' atuin-search-viins 2>/dev/null || true
    else
      bindkey -M viins '^R' atuin-search 2>/dev/null || true
    fi
  else
    bindkey '^R' history-incremental-search-backward
    bindkey -M emacs '^R' history-incremental-search-backward 2>/dev/null || true
    bindkey -M viins '^R' history-incremental-search-backward 2>/dev/null || true
  fi

  fzf_jump_widget() {
    emulate -L zsh
    command -v fzf >/dev/null 2>&1 || return 0

    local target=""
    if command -v zoxide >/dev/null 2>&1; then
      target="$(
        zoxide query -l 2>/dev/null |
          awk 'NF' |
          fzf --height=45% --layout=reverse --prompt='jump> ' \
            --preview='ls -la --color=always {} 2>/dev/null | head -n 80'
      )"
    fi

    [ -n "$target" ] || return 0
    cd "$target" || return 0
    zle reset-prompt
  }
  zle -N fzf_jump_widget
  bindkey '^[c' fzf_jump_widget
  bindkey -M emacs '^[c' fzf_jump_widget 2>/dev/null || true
  bindkey -M viins '^[c' fzf_jump_widget 2>/dev/null || true
fi

# Compact RPROMPT with command duration + context (optional).
ENABLE_COMPACT_RPROMPT="${ENABLE_COMPACT_RPROMPT:-1}"
PROMPT_CMD_DURATION_MIN_MS="${PROMPT_CMD_DURATION_MIN_MS:-2000}"
SHOW_NODE_RPROMPT="${SHOW_NODE_RPROMPT:-0}"
typeset -g __cmd_started_ms=""
typeset -g __cmd_duration_seg=""

__now_ms() {
  printf '%.0f' "$(( EPOCHREALTIME * 1000 ))"
}

preexec_record_command_start() {
  __cmd_started_ms="$(__now_ms)"
}

update_compact_rprompt() {
  emulate -L zsh
  [[ "$ENABLE_COMPACT_RPROMPT" == "1" ]] || { RPROMPT=""; return 0; }

  local -a segs=()
  [ -n "$__cmd_duration_seg" ] && segs+=("$__cmd_duration_seg")
  [ -n "${DIRENV_DIR:-}" ] && segs+=("direnv")

  local branch dirty
  branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [ -n "$branch" ]; then
    dirty=""
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
      dirty="*"
    fi
    segs+=("git:${branch}${dirty}")
  fi

  [ -n "${VIRTUAL_ENV:-}" ] && segs+=("py:${VIRTUAL_ENV:t}")
  if [[ "$SHOW_NODE_RPROMPT" == "1" ]] && command -v node >/dev/null 2>&1; then
    node_v="$(zsh_cache_run node_version 120 node -v)"
    [ -n "$node_v" ] && segs+=("node:${node_v#v}")
  fi

  RPROMPT="%F{8}${(j: | :)segs}%f"
}

precmd_update_prompt_timing() {
  emulate -L zsh
  if [[ -n "$__cmd_started_ms" ]]; then
    local now_ms elapsed_ms
    now_ms="$(__now_ms)"
    elapsed_ms=$(( now_ms - __cmd_started_ms ))
    if (( elapsed_ms >= PROMPT_CMD_DURATION_MIN_MS )); then
      __cmd_duration_seg="${elapsed_ms}ms"
    else
      __cmd_duration_seg=""
    fi
  fi
  __cmd_started_ms=""
  update_compact_rprompt
}

typeset -ga preexec_functions precmd_functions
(( ${preexec_functions[(Ie)preexec_record_command_start]} == 0 )) && preexec_functions+=(preexec_record_command_start)
(( ${precmd_functions[(Ie)precmd_update_prompt_timing]} == 0 )) && precmd_functions+=(precmd_update_prompt_timing)

# Aliases
DOTFILES_HOME="${DOTFILES_HOME:-$HOME/Documents/code/dotfiles}"
if [ -f "$DOTFILES_HOME/aliases.zsh" ]; then
  source "$DOTFILES_HOME/aliases.zsh"
fi
if [ -f "$DOTFILES_HOME/aliases.local.zsh" ]; then
  source "$DOTFILES_HOME/aliases.local.zsh"
fi

# Custom helpers
fix-time() {
  sudo timedatectl set-ntp true || return 1
  if command -v chronyc >/dev/null 2>&1; then
    sudo systemctl restart chronyd >/dev/null 2>&1 || sudo systemctl restart chrony >/dev/null 2>&1 || true
    sudo chronyc makestep >/dev/null 2>&1 || true
  fi
  timedatectl status | sed -n '1,20p'
}

# Starship prompt (should be last)
eval "$(starship init zsh)"

if [[ "${ZSH_PROFILE_STARTUP:-0}" == "1" ]]; then
  startup_elapsed_ms=$(( (EPOCHREALTIME - __ZSH_STARTUP_BEGIN_MS) * 1000 ))
  printf 'zsh startup: %.2fms\n' "$startup_elapsed_ms"
  zprof
fi

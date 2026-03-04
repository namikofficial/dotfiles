# Git aliases
alias gs="git status"
alias ga="git add"
alias gp="git push"
alias gpl="git pull"
alias gc="git commit"
alias gco="git checkout"
alias gb="git branch"
alias gd="git diff"
alias gl="git log --oneline -n 20"
alias greset="git reset --hard"
alias gresetfull="git fetch origin && git reset --hard origin/\$(git branch --show-current) && git clean -fd"

# Docker aliases
alias dc="docker compose"
alias dcu="docker compose up"
alias dcd="docker compose down"
alias dcl="docker compose logs -f --tail=200"
alias dcb="docker compose build"
alias dcub="docker compose up -d --build"
alias dcps="docker compose ps"
alias dclast="docker compose logs --tail=100"
alias dcrestart="docker compose restart"
alias dcdownv="docker compose down -v --remove-orphans"
alias dcup="docker compose up -d"
alias dcreup="docker compose up -d --force-recreate"
alias dps='docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dpsa='docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}"'
alias dimg='docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"'
alias dvol='docker volume ls --format "table {{.Name}}\t{{.Driver}}"'
alias dnet='docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}"'
alias drestart="docker restart"
alias dstopall='docker stop $(docker ps -q)'
alias drmstopped='docker rm $(docker ps -aq -f status=exited)'
alias ddf="docker system df"
alias dinspect='docker inspect --format "Name={{.Name}} | Image={{.Config.Image}} | IP={{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}} | State={{.State.Status}}"'
alias dtop='docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"'
alias dpruneall='docker system prune -af --volumes'
alias dcleanimg='docker image prune -af'
alias dcleanctr='docker container prune -f'
alias dcleanvol='docker volume prune -f'

# Kubernetes aliases
alias k="kubectl"
alias kgp="kubectl get pods"
alias kdesc="kubectl describe"
alias klogs="kubectl logs"

# Utility aliases
alias c="clear"
alias h="history"
if command -v devlink >/dev/null 2>&1; then
  alias dl="$SCRIPTS_BIN/devlink-easy"
  alias dld="devlink dev show"
  alias dlp="devlink port show"
  alias dlh="devlink health show"
  alias dlm="devlink monitor"
fi
if command -v jq >/dev/null 2>&1; then
  alias je="$SCRIPTS_BIN/jq-easy"
  alias jj="jq-easy pretty"
  alias jc="jq-easy compact"
  alias jk="jq-easy keys"
  alias jl="jq-easy len"
  alias jp="jq-easy pick"
  alias jf="jq-easy find"
  alias jv="jq-easy valid"
  alias jh="jq-easy help"
fi
alias ports="$SCRIPTS_BIN/ports"
alias reload="exec zsh"
alias helpcmd="tldr"
alias doctor="$SCRIPTS_BIN/dev-doctor"
alias path='echo -e ${PATH//:/\\n}'
alias cwd='pwd -P'
alias now='date +"%Y-%m-%d %H:%M:%S"'
alias myip='curl -s ifconfig.me && echo'
alias duh='du -sh ./* 2>/dev/null | sort -h'
alias dfh='df -h'
if command -v btop >/dev/null 2>&1; then
  alias sysmon='btop'
fi
if command -v duf >/dev/null 2>&1; then
  alias disks='duf'
fi
if command -v lazygit >/dev/null 2>&1; then
  alias lg='lazygit'
fi
if command -v eza >/dev/null 2>&1; then
  alias lli='eza --tree --level=3 -lh --icons=auto --group-directories-first --git --git-ignore --ignore-glob=.git --time-style=long-iso'
fi

# Better defaults (tools already installed)
if command -v bat >/dev/null 2>&1; then
  alias cat="bat --paging=never --style=plain"
elif command -v batcat >/dev/null 2>&1; then
  alias cat="batcat --paging=never --style=plain"
fi
if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
  alias bat="batcat"
fi
if command -v fdfind >/dev/null 2>&1; then
  alias fd="fdfind"
fi
if command -v rg >/dev/null 2>&1; then
  alias grep="rg -n --smart-case"
fi
if command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
  alias python="python3"
fi
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -I'

# Atuin helpers
alias hs="atuin search"
alias hsync="atuin sync"
alias hstatus="atuin status"
alias hlogin="atuin login"
alias hstats="atuin stats --count 20"
alias hweek="atuin stats 7d --count 20"
alias hmonth="atuin stats 30d --count 20"

# Directory navigation (common projects)
alias dev="cd ~/dev"
alias cdev="cd ~/Documents/code"
alias scripts="cd $SCRIPTS_HOME"
alias projects="cd ~/projects"
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."

# Quick edits
alias zrc="vim ~/.zshrc"
alias zalias="vim $DOTFILES_HOME/aliases.zsh"
alias zshc="vim $DOTFILES_HOME/zshrc"
alias starc="vim ~/.config/starship.toml"
alias cheat="vim $DOTFILES_HOME/SHELL_CHEATSHEET.md"

# Git extras
alias gss="git status -sb"
alias gco-="git checkout -"
alias gcm="git commit -m"
alias gca="git commit --amend --no-edit"
alias gcam="git commit -am"
alias glg="git log --graph --oneline --decorate --all"
alias gundo="git reset --soft HEAD~1"
alias greflog="git reflog -n 30 --date=relative"
alias gsw="git switch"
alias gswc="git switch -c"
alias gsta="git stash push -u -m"
alias gstp="git stash pop"
alias gpr="git pull --rebase"
alias gclean="$SCRIPTS_BIN/git-clean-merged"
alias gwt="$SCRIPTS_BIN/git-worktree"
alias gwtl="gwt list"
alias gwtn="gwt new"
alias gsyncd="$SCRIPTS_BIN/git-default-branch-sync"
alias gbage="$SCRIPTS_BIN/git-branch-age"
alias gpropen="$SCRIPTS_BIN/git-pr-open"
alias wtprune="$SCRIPTS_BIN/prune-worktrees"
alias chlog="$SCRIPTS_BIN/changelog-since"
gwtc() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    echo "usage: gwtc <branch|path>" >&2
    return 1
  fi
  local wt
  wt="$(gwt path "$target")" || return 1
  cd "$wt" || return 1
}
gwtnc() {
  local ticket="${1:-}"
  shift || true
  if [ -z "$ticket" ]; then
    echo "usage: gwtnc <TICKET-ID> [summary words...]" >&2
    return 1
  fi
  local out branch wt
  out="$(gwt new "$ticket" "$@")" || return 1
  printf '%s\n' "$out"
  branch="$(printf '%s\n' "$out" | sed -n 's/^created: //p' | head -n1)"
  [ -n "$branch" ] || return 1
  wt="$(gwt path "$branch")" || return 1
  cd "$wt" || return 1
}

# Docker extras
alias dimages="docker images"
alias dexec="docker exec -it"
alias dprune="docker system prune -f"
alias dclean="$SCRIPTS_BIN/docker-clean-safe"
alias dclg="docker compose logs -f --tail=200"

# Kubernetes extras
alias kg="kubectl get"
alias kga="kubectl get all"
alias kctx="kubectl config current-context"
alias kns="kubectl config set-context --current --namespace"
alias kf="$SCRIPTS_BIN/klogs-fzf"

# Node / package manager
alias ni="npm install"
alias nr="npm run"
alias nt="npm test"
alias nb="npm run build"
alias pi="pnpm install"
alias pr="pnpm run"
alias yi="yarn install"
alias yr="yarn run"
alias root-node-shims="$SCRIPTS_BIN/root-node-shims"
snpx() { sudo "$(command -v npx)" "$@"; }

# GitHub CLI
if command -v gh >/dev/null 2>&1; then
  alias ghs="gh status"
  alias ghpr="gh pr status"
  alias ghpv="gh pr view --web"
fi
alias gpf="$SCRIPTS_BIN/git-pr-flow"
alias ghwatch="$SCRIPTS_BIN/gh-run-watch"
alias japi="$SCRIPTS_BIN/json-api"
alias pathdoc="$SCRIPTS_BIN/path-doctor"
alias pathclean="$SCRIPTS_BIN/path-sanitize"
alias envcheck="$SCRIPTS_BIN/env-validate"
alias rup="$SCRIPTS_BIN/repo-update-all"
alias pnew="$SCRIPTS_BIN/project-new"
alias zshprofile="$SCRIPTS_BIN/zsh-startup-profile"

# Installed modern CLIs
if command -v procs >/dev/null 2>&1; then
  alias pps="procs"
  alias ppsc="procs --sortd cpu"
  alias ppsm="procs --sortd memory"
fi
if command -v dust >/dev/null 2>&1; then
  alias dsz="dust"
  alias dsz2="dust -d 2"
fi
if command -v hyperfine >/dev/null 2>&1; then
  alias bench="hyperfine --warmup 3"
fi
if command -v pipx >/dev/null 2>&1; then
  alias pxl="pipx list"
  alias pxi="pipx install"
fi

# Helpers
mkcd() {
  [ -z "${1:-}" ] && { echo "usage: mkcd <dir>"; return 1; }
  mkdir -p "$1" && cd "$1" || return 1
}
take() {
  [ -z "${1:-}" ] && { echo "usage: take <dir>"; return 1; }
  mkdir -p "$1" && cd "$1" || return 1
}
dsh() {
  local c="$1"
  [ -z "$c" ] && { echo "usage: dsh <container>"; return 1; }
  docker exec -it "$c" bash 2>/dev/null || docker exec -it "$c" sh
}
groot() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  cd "$root" || return 1
}
cdf() {
  local roots=()
  local excludes=(".git" "node_modules" "dist" "build")
  local ex
  local selected=""

  [ -d "$HOME/dev" ] && roots+=("$HOME/dev")
  [ -d "$HOME/Documents/code" ] && roots+=("$HOME/Documents/code")
  [ ${#roots[@]} -eq 0 ] && roots=("$HOME")

  if command -v fd >/dev/null 2>&1; then
    local fd_args=(-t d . "${roots[@]}" --hidden --follow)
    for ex in "${excludes[@]}"; do
      fd_args+=(--exclude "$ex")
    done
    selected=$(fd "${fd_args[@]}" 2>/dev/null | fzf --height=50% --layout=reverse --border --prompt="cdf > ")
  elif command -v fdfind >/dev/null 2>&1; then
    local fdfind_args=(-t d . "${roots[@]}" --hidden --follow)
    for ex in "${excludes[@]}"; do
      fdfind_args+=(--exclude "$ex")
    done
    selected=$(fdfind "${fdfind_args[@]}" 2>/dev/null | fzf --height=50% --layout=reverse --border --prompt="cdf > ")
  else
    selected=$(
      find "${roots[@]}" \
        \( -name .git -o -name node_modules -o -name dist -o -name build \) -prune \
        -o -type d -print 2>/dev/null \
        | fzf --height=50% --layout=reverse --border --prompt="cdf > "
    )
  fi

  if [ -n "$selected" ]; then
    cd "$selected" || return 1
  fi
}
ff() {
  local files
  local preview_cmd
  local selected_files=()
  local line

  if command -v bat >/dev/null 2>&1; then
    preview_cmd='bat --color=always --style=plain --line-range=:200 {}'
  elif command -v batcat >/dev/null 2>&1; then
    preview_cmd='batcat --color=always --style=plain --line-range=:200 {}'
  else
    preview_cmd='sed -n "1,200p" {}'
  fi
  if command -v fd >/dev/null 2>&1; then
    files="$(fd -t f . --hidden --follow --exclude .git 2>/dev/null | fzf -m --height=60% --layout=reverse --border --preview "$preview_cmd" --prompt='ff > ')"
  elif command -v fdfind >/dev/null 2>&1; then
    files="$(fdfind -t f . --hidden --follow --exclude .git 2>/dev/null | fzf -m --height=60% --layout=reverse --border --preview "$preview_cmd" --prompt='ff > ')"
  else
    files="$(find . -type f 2>/dev/null | fzf -m --height=60% --layout=reverse --border --prompt='ff > ')"
  fi
  [ -z "$files" ] && return 0
  while IFS= read -r line; do
    [ -n "$line" ] && selected_files+=("$line")
  done <<< "$files"
  [ ${#selected_files[@]} -gt 0 ] && "${EDITOR:-vim}" "${selected_files[@]}"
}
frg() {
  local q
  local preview_cmd
  q="${*:-}"
  if [ -z "$q" ]; then
    echo "usage: frg <pattern>"
    return 1
  fi
  if command -v bat >/dev/null 2>&1; then
    preview_cmd='bat --color=always --style=plain --highlight-line {2} {1}'
  elif command -v batcat >/dev/null 2>&1; then
    preview_cmd='batcat --color=always --style=plain --highlight-line {2} {1}'
  else
    preview_cmd='sed -n "1,200p" {1}'
  fi
  rg --line-number --column --smart-case "$q" . \
    | fzf --delimiter ':' --height=70% --layout=reverse --border \
      --preview "$preview_cmd" \
    | awk -F: '{print $1":"$2":"$3}' \
    | xargs -r ${EDITOR:-vim}
}
fkill() {
  local pid
  pid="$(ps -ef | sed 1d | fzf --height=60% --layout=reverse --border --prompt='fkill > ' | awk '{print $2}')"
  [ -n "$pid" ] && kill -9 "$pid"
}
tnotes() {
  local f="$SCRIPTS_HOME/docs/NOTES.md"
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] || touch "$f"
  ${EDITOR:-vim} "$f"
}
pkillport() {
  "$SCRIPTS_BIN/port-kill" "$@"
}
extract() {
  if [ -f "$1" ]; then
    case "$1" in
      *.tar.bz2) tar xjf "$1" ;;
      *.tar.gz) tar xzf "$1" ;;
      *.bz2) bunzip2 "$1" ;;
      *.rar) unrar x "$1" ;;
      *.gz) gunzip "$1" ;;
      *.tar) tar xf "$1" ;;
      *.tbz2) tar xjf "$1" ;;
      *.tgz) tar xzf "$1" ;;
      *.zip) unzip "$1" ;;
      *.Z) uncompress "$1" ;;
      *.7z) 7z x "$1" ;;
      *) echo "'$1' cannot be extracted via extract()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}
alias dive="docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock wagoodman/dive"

# Clipboard helpers (Wayland/X11 safe fallbacks)
clipcopy() {
  if command -v wl-copy >/dev/null 2>&1; then
    wl-copy
  elif command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard
  else
    echo "No clipboard tool found (need wl-copy or xclip)"
    return 1
  fi
}
clippaste() {
  if command -v wl-paste >/dev/null 2>&1; then
    wl-paste
  elif command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard -o
  else
    echo "No clipboard tool found (need wl-paste or xclip)"
    return 1
  fi
}
jclip() {
  clippaste | jq-easy pretty
}

# Power profile helper (Arch power-profiles-daemon)
# Usage: pp [status|power-saver|balanced|performance]
pp() {
  if ! command -v powerprofilesctl >/dev/null 2>&1; then
    echo "powerprofilesctl is not installed"
    return 1
  fi

  case "${1:-status}" in
    power-saver|balanced|performance)
      powerprofilesctl set "$1" >/dev/null 2>&1 || return 1
      powerprofilesctl get
      ;;
    status)
      powerprofilesctl get
      ;;
    *)
      echo "usage: pp [status|power-saver|balanced|performance]"
      return 1
      ;;
  esac
}
alias ppb='pp power-saver'
alias ppd='pp balanced'
alias ppp='pp performance'

# Combined power + GPU status
pstatus() {
  if ! command -v powerprofilesctl >/dev/null 2>&1; then
    echo "powerprofilesctl is not installed"
    return 1
  fi

  echo "== Power =="
  powerprofilesctl get
  if command -v nvidia-smi >/dev/null 2>&1; then
    echo
    echo "== NVIDIA =="
    nvidia-smi --query-gpu=name,driver_version,pstate,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader
  fi
}

# Battery summary (renamed to avoid conflict with 'bat')
# Usage: batt
batt() {
  if ! command -v upower >/dev/null 2>&1; then
    echo "upower is not installed"
    return 1
  fi

  local bat_dev
  bat_dev="$(upower -e | rg -m1 'battery|BAT')"
  if [ -z "$bat_dev" ]; then
    echo "No battery device found"
    return 1
  fi

  local summary
  summary="$(upower -i "$bat_dev" | awk '
    /^[[:space:]]*(vendor|model|serial|state|warning-level|percentage|time to empty|time to full|energy|energy-empty|energy-full|energy-full-design|energy-rate|voltage|charge-cycles|capacity|technology|temperature):/ {print}
  ')"
  if [ -n "$summary" ]; then
    printf '%s\n' "$summary"
  else
    upower -i "$bat_dev" | sed -n '1,60p'
  fi
}

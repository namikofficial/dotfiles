#!/usr/bin/env zsh
# Git function aliases - Must be sourced BEFORE aliases.zsh to override forgit plugin
# Source this before aliases.zsh loads if you see parse errors

# In zsh, explicitly unalias ONLY the aliases that forgit creates (don't blanket unalias)
# This prevents the "defining function based on alias" error
unalias gat 2>/dev/null || true
unalias gcb 2>/dev/null || true
unalias gcf 2>/dev/null || true
unalias gclean 2>/dev/null || true
unalias gco 2>/dev/null || true
unalias gd 2>/dev/null || true
unalias gds 2>/dev/null || true
unalias ga 2>/dev/null || true
unalias gc 2>/dev/null || true
unalias gp 2>/dev/null || true
unalias gpl 2>/dev/null || true
unalias gb 2>/dev/null || true
unalias gl 2>/dev/null || true
unalias gs 2>/dev/null || true
unalias greset 2>/dev/null || true
unalias gresetfull 2>/dev/null || true
unalias gcm 2>/dev/null || true

# Now define all functions cleanly
ga() {
  # ga with no args → add all; with args → add those files
  if [ $# -eq 0 ]; then
    git add .
  else
    git add "$@"
  fi
}

gs() { git status "$@"; }
gp() { git push "$@"; }
gpl() { git pull "$@"; }
gc() { git commit "$@"; }
gco() { git checkout "$@"; }
gb() { git branch "$@"; }
gd() { git diff "$@"; }

gds() { 
  git -C "$(pwd)" diff --stat "$@"
}

gl() { 
  git log --oneline -n 20 "$@"
}

greset() { 
  git reset --hard "$@"
}

gresetfull() { 
  git fetch origin && \
  git reset --hard origin/$(git branch --show-current) && \
  git clean -fd
}

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

# Git commit message function (from aliases.zsh)
gcm() {
  if [ $# -eq 0 ]; then
    # Interactive mode: prompt for message
    read -p "Commit message: " msg
    [ -z "$msg" ] && { echo "Aborted"; return 1; }
    git commit -m "$msg"
  else
    # Direct mode: use provided message
    git commit -m "$*"
  fi
}

# Additional useful aliases
alias ll="ls -lh"
alias la="ls -lah"
alias l="ls -1"
alias mkdir="mkdir -p"
alias cp="cp -i"
alias rm="rm -i"
alias mv="mv -i"
alias grep="grep --color=auto"

# Kubernetes aliases (if kubectl installed)
if command -v kubectl >/dev/null; then
  alias k="kubectl"
  alias kaf="kubectl apply -f"
  alias kgp="kubectl get pods"
  alias kgd="kubectl get deployment"
  alias kdesc="kubectl describe"
  alias klogs="kubectl logs"
fi

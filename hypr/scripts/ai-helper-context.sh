#!/usr/bin/env bash
set -euo pipefail

action="${1:-prompt}"
mode="${2:-ask}"

project_cache="${XDG_CACHE_HOME:-$HOME/.cache}/kage/project-current.json"
workbench_status_cache="${XDG_CACHE_HOME:-$HOME/.cache}/ai-workbench/project-status-v1.json"
project_context_script="${HOME}/.config/hypr/scripts/get-project-context.sh"
llm_base_url="${LLM_BASE_URL:-http://127.0.0.1:8080/v1}"
llm_model_alias="${LLM_CHAT_MODEL:-local}"

project_path=""
project_name=""
project_branch=""
project_framework=""
project_modified="0"
project_staged="0"
project_dirty="false"
current_file=""
machine_arch="$(uname -m 2>/dev/null || printf 'unknown')"

detect_framework() {
  local dir="${1:-}"
  [ -d "$dir" ] || return 0
  if [ -f "$dir/package.json" ]; then
    printf 'node\n'
  elif [ -f "$dir/pyproject.toml" ] || [ -f "$dir/requirements.txt" ]; then
    printf 'python\n'
  elif [ -f "$dir/Cargo.toml" ]; then
    printf 'rust\n'
  elif [ -f "$dir/go.mod" ]; then
    printf 'go\n'
  elif [ -f "$dir/flake.nix" ] || [ -f "$dir/home.nix" ]; then
    printf 'nix\n'
  elif [ -f "$dir/.dotfiles" ] || [ -f "$dir/zshrc" ] || [ -d "$dir/hypr" ]; then
    printf 'dotfiles\n'
  else
    printf 'unknown\n'
  fi
}

load_project_from_dir() {
  local dir="${1:-}"
  [ -d "$dir" ] || return 1

  project_path="$(cd "$dir" 2>/dev/null && pwd -P)"
  project_name="$(basename "$project_path")"
  project_branch=""
  project_framework="$(detect_framework "$project_path")"
  project_modified="0"
  project_staged="0"
  project_dirty="false"

  if git -C "$project_path" rev-parse --git-dir >/dev/null 2>&1; then
    project_path="$(git -C "$project_path" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$project_path")"
    project_name="$(basename "$project_path")"
    project_branch="$(git -C "$project_path" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')"
    project_modified="$(git -C "$project_path" status --porcelain 2>/dev/null | awk 'END {print NR+0}')"
    project_staged="$(git -C "$project_path" diff --cached --name-only 2>/dev/null | awk 'END {print NR+0}')"
    [ "${project_modified:-0}" -gt 0 ] && project_dirty="true"
  fi

  project_framework="$(detect_framework "$project_path")"
  return 0
}

load_project_from_cache() {
  command -v jq >/dev/null 2>&1 || return 1
  [ -s "$project_cache" ] || return 1

  local cache_path
  cache_path="$(jq -r '.path // empty' "$project_cache" 2>/dev/null || true)"
  [ -d "$cache_path" ] || return 1

  project_path="$cache_path"
  project_name="$(jq -r '.name // empty' "$project_cache" 2>/dev/null || true)"
  project_branch="$(jq -r '.branch // empty' "$project_cache" 2>/dev/null || true)"
  project_framework="$(jq -r '.framework // .lang // empty' "$project_cache" 2>/dev/null || true)"
  project_modified="$(jq -r '.modified // 0' "$project_cache" 2>/dev/null || printf '0')"
  project_staged="$(jq -r '.staged // 0' "$project_cache" 2>/dev/null || printf '0')"
  project_dirty="$(jq -r '.dirty // false' "$project_cache" 2>/dev/null || printf 'false')"
  [ -n "$project_name" ] || project_name="$(basename "$project_path")"
  [ -n "$project_framework" ] || project_framework="$(detect_framework "$project_path")"
  return 0
}

load_project_from_workbench() {
  command -v jq >/dev/null 2>&1 || return 1
  [ -s "$workbench_status_cache" ] || return 1
  jq -e '.schemaVersion == 1 and (.status.project.path // "") != ""' "$workbench_status_cache" >/dev/null 2>&1 || return 1

  project_path="$(jq -r '.status.project.path // ""' "$workbench_status_cache")"
  [ -d "$project_path" ] || return 1
  project_name="$(jq -r '.status.project.name // ""' "$workbench_status_cache")"
  project_branch="$(jq -r '.status.git.branch // ""' "$workbench_status_cache")"
  project_framework="workbench"
  project_modified="$(jq -r '(.status.git.modified // 0) + (.status.git.deleted // 0) + (.status.git.renamed // 0) + (.status.git.untracked // 0)' "$workbench_status_cache")"
  project_staged="$(jq -r '.status.git.staged // 0' "$workbench_status_cache")"
  project_dirty="$(jq -r '.status.git.dirty // false' "$workbench_status_cache")"
  [ -n "$project_name" ] || project_name="$(basename "$project_path")"
  return 0
}

load_project_context() {
  if [ -n "${NOXFLOW_AI_CONTEXT:-}" ] && [ -d "${NOXFLOW_AI_CONTEXT}" ]; then
    load_project_from_dir "${NOXFLOW_AI_CONTEXT}" || true
  fi

  if [ -z "$project_path" ]; then
    load_project_from_workbench || true
  fi

  if [ -z "$project_path" ]; then
    case "$(pwd -P)" in
      "$HOME"|/)
        ;;
      *)
        load_project_from_dir "$(pwd -P)" || true
        ;;
    esac
  fi

  if [ -z "$project_path" ]; then
    load_project_from_cache || true
  fi

  if [ -z "$project_path" ]; then
    load_project_from_dir "$HOME" || true
  fi
}

load_current_file() {
  command -v jq >/dev/null 2>&1 || return 0
  [ -x "$project_context_script" ] || return 0
  current_file="$("$project_context_script" 2>/dev/null | jq -r '.file // empty' 2>/dev/null || true)"
}

distribution_name() {
  if [ -f /etc/arch-release ]; then
    printf 'Arch Linux\n'
  else
    printf 'Linux\n'
  fi
}

shell_summary() {
  local shell_bin shell_name version
  shell_bin="${SHELL:-/bin/sh}"
  shell_name="$(basename "$shell_bin")"
  version="$("$shell_bin" --version 2>/dev/null | head -n1 || true)"
  if [ -n "$version" ]; then
    printf '%s\n' "$version"
  else
    printf '%s\n' "$shell_name"
  fi
}

join_available() {
  local max="$1"
  shift
  local out=()
  local cmd
  for cmd in "$@"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      out+=("$cmd")
    fi
    [ "${#out[@]}" -ge "$max" ] && break
  done
  if [ "${#out[@]}" -eq 0 ]; then
    return 0
  fi
  printf '%s' "${out[0]}"
  local i
  for ((i = 1; i < ${#out[@]}; i++)); do
    printf ', %s' "${out[i]}"
  done
}

project_line() {
  local status="clean"
  if [ "${project_dirty:-false}" = "true" ] || [ "${project_modified:-0}" -gt 0 ]; then
    status="dirty: ${project_modified} modified"
    [ "${project_staged:-0}" -gt 0 ] && status="${status}, ${project_staged} staged"
  fi

  printf '%s at %s' "${project_name:-workspace}" "${project_path:-$HOME}"
  [ -n "${project_branch:-}" ] && printf ' | branch %s' "$project_branch"
  [ -n "${project_framework:-}" ] && printf ' | %s' "$project_framework"
  printf ' | %s' "$status"
  [ -n "${current_file:-}" ] && printf ' | focus %s' "$current_file"
}

print_summary() {
  local modern workstation devtools
  modern="$(join_available 6 rg fd bat eza jq gh)"
  workstation="$(join_available 8 rofi kitty wl-copy wl-paste codex opencode llama-swap-manager)"
  devtools="$(join_available 8 docker kubectl tmux nvim atuin lazygit btop duf procs dust hyperfine pipx)"

  printf 'Workstation: %s %s on Hyprland | shell %s\n' "$(distribution_name)" "$machine_arch" "$(shell_summary)"
  printf 'Local AI: llama-swap-manager at %s | model alias %s\n' "$llm_base_url" "$llm_model_alias"
  printf 'Project: %s\n' "$(project_line)"
  printf 'Conventions: prefer %s; aliases include dc, k, gss, glg, gcm, reload, hreload, clipcopy/clippaste/jclip.\n' "${modern:-rg, fd, bat, eza, jq, gh}"
  [ -n "$workstation" ] && printf 'Helper tools: %s\n' "$workstation"
  [ -n "$devtools" ] && printf 'Common tools: %s\n' "$devtools"
}

print_prompt() {
  cat <<EOF
You are the local AI helper for this laptop. Ground answers in the real workstation context below instead of generic defaults.

$(print_summary)

EOF

  case "$mode" in
    ask)
      cat <<'EOF'
Mode: answer direct questions for this machine and the active project.
- Be concise but complete.
- Prefer exact local commands, aliases, or file paths when they help.
- State assumptions clearly instead of inventing missing facts.
EOF
      ;;
    clip)
      cat <<'EOF'
Mode: summarize clipboard content for quick reuse.
- Assume pasted code/logs/commands came from this Arch/Hyprland/zsh environment unless the text says otherwise.
- Return: 1) one-line summary 2) key points 3) action items 4) risks or ambiguities.
- Do not invent context that is not present in the clipboard.
EOF
      ;;
    shell)
      cat <<'EOF'
Mode: generate shell guidance for this machine.
- Prefer the smallest safe command sequence that is easy to verify and roll back.
- Prefer local conventions and tools above (for example rg/fd/bat/eza/jq/gh, dc for docker compose, k for kubectl).
- Put commands in one fenced bash block.
- Flag sudo, destructive actions, or risky assumptions before the command block.
- Include short validation steps; include rollback only when it matters.
EOF
      ;;
    debug)
      cat <<'EOF'
Mode: debug errors, logs, or broken commands from this machine.
- Interpret logs in the context of Arch Linux, Hyprland, zsh, and the active project when relevant.
- Return: 1) likely root causes in probability order 2) next checks/commands 3) minimal fix plan 4) what evidence would confirm or rule out each guess.
- Prefer practical commands that use the installed tools listed above.
EOF
      ;;
    scratchpad)
      cat <<'EOF'
Mode: persistent local scratchpad chat.
- Stay practical, terse, and action-oriented.
- Use the workstation/project context above in every answer.
- When suggesting commands, prefer local tools and aliases when useful and call out risky steps.
- Use markdown code fences for commands or code; avoid long preambles.
EOF
      ;;
    raw)
      cat <<'EOF'
Mode: preserve the user's freeform prompt.
- Keep the user's wording primary.
- Only apply the workstation context above when it helps with commands, tooling, paths, or system-specific advice.
EOF
      ;;
    *)
      printf 'Unknown mode: %s\n' "$mode" >&2
      exit 1
      ;;
  esac
}

load_project_context
load_current_file

case "$action" in
  prompt) print_prompt ;;
  summary) print_summary ;;
  *)
    printf 'usage: %s [prompt <ask|clip|shell|debug|scratchpad|raw>|summary]\n' "$0" >&2
    exit 1
    ;;
esac

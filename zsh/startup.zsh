# Startup health checks that are safe to run during interactive shell init.

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

run_weekly_dev_doctor_check() {
  emulate -L zsh
  [[ -o interactive ]] || return 0

  local doctor_bin=""
  if [ -x "${SCRIPTS_BIN:-}/dev-doctor" ]; then
    doctor_bin="${SCRIPTS_BIN}/dev-doctor"
  elif command -v dev-doctor >/dev/null 2>&1; then
    doctor_bin="$(command -v dev-doctor)"
  else
    return 0
  fi

  local cache_dir="$HOME/.cache/zsh"
  local stamp_file="${cache_dir}/.dev-doctor-weekly-$(date +%G%V)"
  mkdir -p "$cache_dir"
  [ -f "$stamp_file" ] && return 0

  if command -v timeout >/dev/null 2>&1; then
    timeout 12s "$doctor_bin" >/dev/null 2>&1 || print -P "%F{yellow}zsh:%f weekly dev-doctor found issues (run: dev-doctor)"
  else
    "$doctor_bin" >/dev/null 2>&1 || print -P "%F{yellow}zsh:%f weekly dev-doctor found issues (run: dev-doctor)"
  fi

  : >| "$stamp_file"
}

warn_missing_tools_once
run_weekly_dev_doctor_check


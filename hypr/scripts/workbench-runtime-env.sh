#!/usr/bin/env bash

workbench_runtime_env="${AI_WORKBENCH_RUNTIME_ENV:-${XDG_CONFIG_HOME:-$HOME/.config}/ai-workbench/runtime.env}"

# Explicit process environment is the highest-precedence runtime override. Preserve
# it while importing the shared EnvironmentFile, whose values otherwise replace
# already-exported variables when sourced by a desktop client.
workbench_runtime_keys=(
  AI_API_PORT
  AI_WEB_PORT
  AI_API_URL
  AI_WORKBENCH_API_URL
  AI_WORKBENCH_URL
  AI_LOCAL_BASE_URL
  LLM_BASE_URL
  LLM_HEALTH_ENDPOINT
)
declare -A workbench_runtime_overrides=()
declare -A workbench_runtime_override_set=()
for workbench_runtime_key in "${workbench_runtime_keys[@]}"; do
  if [[ -v $workbench_runtime_key ]]; then
    workbench_runtime_override_set["$workbench_runtime_key"]=1
    workbench_runtime_overrides["$workbench_runtime_key"]="${!workbench_runtime_key}"
  fi
done

if [ -r "$workbench_runtime_env" ]; then
  # This file is user-owned and uses the same KEY=value format as systemd EnvironmentFile.
  # shellcheck disable=SC1090
  source "$workbench_runtime_env"
fi

for workbench_runtime_key in "${workbench_runtime_keys[@]}"; do
  if [ "${workbench_runtime_override_set[$workbench_runtime_key]:-0}" = "1" ]; then
    printf -v "$workbench_runtime_key" '%s' "${workbench_runtime_overrides[$workbench_runtime_key]}"
  fi
done
unset workbench_runtime_key workbench_runtime_keys workbench_runtime_overrides workbench_runtime_override_set

: "${AI_API_PORT:=4417}"
: "${AI_WEB_PORT:=4317}"
: "${AI_WORKBENCH_API_URL:=${AI_API_URL:-http://127.0.0.1:${AI_API_PORT}}}"
: "${AI_WORKBENCH_URL:=http://127.0.0.1:${AI_WEB_PORT}}"
: "${AI_LOCAL_BASE_URL:=http://127.0.0.1:8080/v1}"
: "${LLM_BASE_URL:=$AI_LOCAL_BASE_URL}"
: "${LLM_HEALTH_ENDPOINT:=${LLM_BASE_URL%/}/models}"

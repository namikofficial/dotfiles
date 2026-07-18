#!/usr/bin/env bash

workbench_runtime_env="${AI_WORKBENCH_RUNTIME_ENV:-${XDG_CONFIG_HOME:-$HOME/.config}/ai-workbench/runtime.env}"
if [ -r "$workbench_runtime_env" ]; then
  # This file is user-owned and uses the same KEY=value format as systemd EnvironmentFile.
  # shellcheck disable=SC1090
  source "$workbench_runtime_env"
fi

: "${AI_API_PORT:=4417}"
: "${AI_WEB_PORT:=4317}"
: "${AI_WORKBENCH_API_URL:=${AI_API_URL:-http://127.0.0.1:${AI_API_PORT}}}"
: "${AI_WORKBENCH_URL:=http://127.0.0.1:${AI_WEB_PORT}}"
: "${AI_LOCAL_BASE_URL:=http://127.0.0.1:8080/v1}"
: "${LLM_BASE_URL:=$AI_LOCAL_BASE_URL}"
: "${LLM_HEALTH_ENDPOINT:=${LLM_BASE_URL%/}/models}"

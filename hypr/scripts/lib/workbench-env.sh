#!/usr/bin/env bash
# workbench-env.sh — Workbench endpoint defaults for desktop scripts.
#
# This replaces `hypr/scripts/workbench-runtime-env.sh`, which was deleted in
# 8022f56 ("retire local workbench and model runtime") while four live scripts
# still sourced it. Under `set -euo pipefail` the missing file aborted them at
# line 1, so `kage`, `kage-project-rofi.sh`, `project-resume.sh` and
# `setup/project-profile.sh` were all dead.
#
# The scripts themselves are still live desktop entry points and still talk to
# a Workbench when one is running, so this keeps the behaviour they were written
# against instead of deleting them: read the user-owned EnvironmentFile when it
# exists, then apply the same defaults. Workbench being absent is not an error —
# callers fall back to their XDG caches.

workbench_runtime_env="${AI_WORKBENCH_RUNTIME_ENV:-${XDG_CONFIG_HOME:-$HOME/.config}/ai-workbench/runtime.env}"

if [ -r "$workbench_runtime_env" ]; then
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

export AI_API_PORT AI_WEB_PORT AI_WORKBENCH_API_URL AI_WORKBENCH_URL
export AI_LOCAL_BASE_URL LLM_BASE_URL LLM_HEALTH_ENDPOINT

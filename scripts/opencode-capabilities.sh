#!/usr/bin/env bash
set -u

printf '%-18s %s\n' capability status
for tool in rg git gh docker node npm pnpm uv uvx adb emulator maestro opencode; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '%-18s %s\n' "$tool" available
  else
    printf '%-18s %s\n' "$tool" NOT_CONFIGURED
  fi
done
for tool in bru bruno schemathesis playwright; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '%-18s %s\n' "$tool" available
  else
    printf '%-18s %s\n' "$tool" NOT_CONFIGURED
  fi
done

printf '%-18s %s\n' playwright-mcp configured

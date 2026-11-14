#!/usr/bin/env bash
# Regression test for the local model root.
#
# The router defaulted to /home/namik/llama-models, which made the public
# repository unusable on any other account. The default is now derived from
# the user's home directory, and an explicit LLAMA_MODEL_ROOT still wins.
#
# The renderer is checked behaviourally: it renders a lane only when the GGUF
# is on disk, so the test creates a dummy model file and reads the root back
# out of the rendered preset.
set -uo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
renderer="$repo_dir/system/llama-router/render-preset.py"

failures=0

ok() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

printf '== no hard-coded account path ==\n'

for script in \
  setup/install-llama-router.sh \
  setup/download-local-models.sh \
  setup/test-local-models.sh \
  system/llama-router/llama-router.sh; do
  path="$repo_dir/$script"
  if grep -q '/home/namik' "$path"; then
    fail "$script has no hard-coded account path"
  else
    ok "$script has no hard-coded account path"
  fi

  if grep -qF 'LLAMA_MODEL_ROOT:-$HOME/llama-models' "$path"; then
    ok "$script defaults to \$HOME/llama-models and keeps the override"
  else
    fail "$script defaults to \$HOME/llama-models and keeps the override"
  fi
done

if grep -q '/home/namik' "$renderer"; then
  fail "render-preset.py has no hard-coded account path"
else
  ok "render-preset.py has no hard-coded account path"
fi

printf '== the renderer honours the default and the override ==\n'

# One lane is enough: the renderer skips lanes whose GGUF is missing.
lane_rel='chat/ling-tiny/Ling-3.0-tiny-sft-agentic-Q4_K_M.gguf'

fake_home="$tmp_root/home"
mkdir -p "$fake_home/llama-models/$(dirname "$lane_rel")"
: >"$fake_home/llama-models/$lane_rel"

out="$tmp_root/default.ini"
HOME="$fake_home" python3 "$renderer" --output "$out" >/dev/null 2>&1
code=$?
if [ "$code" -eq 0 ] && grep -qF "$fake_home/llama-models/$lane_rel" "$out"; then
  ok "the default model root is \$HOME/llama-models"
else
  fail "the default model root is \$HOME/llama-models (exit $code)"
fi

override_root="$tmp_root/override-root"
mkdir -p "$override_root/$(dirname "$lane_rel")"
: >"$override_root/$lane_rel"

out="$tmp_root/override.ini"
LLAMA_MODEL_ROOT="$override_root" python3 "$renderer" --output "$out" >/dev/null 2>&1
code=$?
if [ "$code" -eq 0 ] && grep -qF "$override_root/$lane_rel" "$out"; then
  ok "LLAMA_MODEL_ROOT overrides the default"
else
  fail "LLAMA_MODEL_ROOT overrides the default (exit $code)"
fi

printf '\n'
if [ "$failures" -eq 0 ]; then
  printf 'llama router paths: ok\n'
  exit 0
fi
printf 'llama router paths: %d failure(s)\n' "$failures" >&2
exit 1

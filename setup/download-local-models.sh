#!/usr/bin/env bash
# Download the local GGUF models served by the llama.cpp router.
#
# Non-interactive and idempotent: existing files are left alone. All models
# used here live in public repositories, so the download runs anonymously.
# The stored Hugging Face token is deliberately NOT read - an expired token
# in the local credential store makes `hf` fail on public repos, and this
# script must not depend on credential state.
#
# Set HF_TOKEN in the environment to use a token instead of anonymous access.
#
# Usage:
#   setup/download-local-models.sh [core|optional|embed|all]
#
#   core     the lanes the router preset recommends (default)
#   optional coding fine-tunes kept for A/B comparison
#   embed    embedding models
#   all      everything above
set -euo pipefail

MODEL_ROOT="${LLAMA_MODEL_ROOT:-/home/namik/llama-models}"
HF_BIN="${HF_BIN:-$(command -v hf || true)}"
SCOPE="${1:-core}"

case "$SCOPE" in
  core | optional | embed | all) ;;
  -h | --help)
    sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    printf 'unknown scope: %s (expected core|optional|embed|all)\n' "$SCOPE" >&2
    exit 2
    ;;
esac

if [ -n "${HF_TOKEN:-}" ]; then
  export HF_TOKEN
else
  export HF_HUB_DISABLE_IMPLICIT_TOKEN=1
fi

# fetch <repo> <include-glob> <destination-dir>
fetch() {
  local repo="$1" include="$2" dest="$3"
  mkdir -p "$dest"

  if compgen -G "$dest/*.gguf" >/dev/null 2>&1; then
    printf 'skip    %s (already present)\n' "$repo"
    return 0
  fi

  if [ -n "$HF_BIN" ] && [ -x "$HF_BIN" ]; then
    if "$HF_BIN" download "$repo" --include "$include" --local-dir "$dest"; then
      verify_gguf "$dest"
      return 0
    fi
    printf 'hf download failed for %s; falling back to curl\n' "$repo" >&2
  fi

  command -v curl >/dev/null 2>&1 || {
    printf 'neither hf nor curl is available; cannot fetch %s\n' "$repo" >&2
    exit 1
  }

  local url="https://huggingface.co/${repo}/resolve/main/${include}"
  url="${url//\*/}"
  curl -L --fail --retry 3 --retry-delay 2 -C - -o "$dest/model.gguf" "$url"
  verify_gguf "$dest"
}

# verify_gguf <dir> - reject empty or truncated downloads.
verify_gguf() {
  local dir="$1"
  local file
  file="$(find "$dir" -maxdepth 1 -name '*.gguf' -size +1M -print -quit)"
  if [ -z "$file" ]; then
    printf 'no usable GGUF found in %s\n' "$dir" >&2
    exit 1
  fi
  if [ "$(head -c 4 "$file")" != "GGUF" ]; then
    printf 'downloaded file is not a GGUF: %s\n' "$file" >&2
    exit 1
  fi
  printf 'ok      %s (%s)\n' "$file" "$(du -h "$file" | cut -f1)"
}

run_core() {
  # Qwen3.5-4B: fastest lanes. Q4_K_M for the default, UD-IQ3_XXS for the
  # large-context lane (measured faster than Q4_K_M here: 61.7 vs 51.5 t/s).
  fetch unsloth/Qwen3.5-4B-GGUF '*Q4_K_M.gguf' "$MODEL_ROOT/chat/qwen3.5-4b"
  fetch unsloth/Qwen3.5-4B-GGUF '*UD-IQ3_XXS.gguf' "$MODEL_ROOT/chat/qwen3.5-4b"

  # Qwen3.5-9B: strongest reasoning that still fits at 160K context.
  fetch unsloth/Qwen3.5-9B-GGUF '*UD-IQ3_XXS.gguf' "$MODEL_ROOT/chat/qwen3.5-9b"

  # Qwen3.6-35B-A3B: the only lane that holds a 400K session. The experts
  # are split GPU/CPU by the router preset (n-cpu-moe), so the CPU-resident
  # portion needs ~10 GiB of RAM alongside the model.
  fetch unsloth/Qwen3.6-35B-A3B-GGUF '*UD-IQ2_XXS.gguf' "$MODEL_ROOT/chat/qwen3.6-35b"
}

run_optional() {
  # Coding fine-tunes of Qwen3.5-9B. Kept for A/B comparison: none of them
  # beat the base model on the hard eval, and each costs roughly 4x the
  # context of the base 9B lane.
  fetch Tesslate/OmniCoder-9B-GGUF '*q3_k_m.gguf' "$MODEL_ROOT/chat/omnicoder-9b"
  fetch Jackrong/Qwopus3.5-9B-Coder-GGUF '*Q3_K_M.gguf' "$MODEL_ROOT/chat/qwopus-9b-coder"
  fetch florenciodri/Maestro-2-9B-Preview-GGUF '*Q4_K_M.gguf' "$MODEL_ROOT/chat/maestro-9b"
  # Ling-3.0-tiny SFT-Agentic. Loads (llama.cpp has bailingmoe3 support) but
  # scored 4/8 on the hard eval: it loops on a hallucinated workspace path.
  fetch WaylonJBrown/ling-3.0-tiny-sft-agentic-GGUF '*Q4_K_M.gguf' "$MODEL_ROOT/chat/ling-tiny"
}

run_embed() {
  fetch nomic-ai/nomic-embed-text-v2-moe-GGUF '*Q4_K_M.gguf' "$MODEL_ROOT/embed/nomic-embed-text-v2-moe"
  fetch nomic-ai/nomic-embed-code-GGUF '*Q4_K_S.gguf' "$MODEL_ROOT/embed/nomic-embed-code"
}

case "$SCOPE" in
  core) run_core ;;
  optional) run_optional ;;
  embed) run_embed ;;
  all)
    run_core
    run_optional
    run_embed
    ;;
esac

printf '\nmodel root: %s\n' "$MODEL_ROOT"
find "$MODEL_ROOT" -type f -name '*.gguf' -printf '%p\n' | sort

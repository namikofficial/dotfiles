#!/usr/bin/env bash
# setup/install-local-ai-stack.sh
# Unified local AI stack installer for RTX 4050 Arch Linux setup.
# Usage: ./setup/install-local-ai-stack.sh --help
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODEL_ROOT="${LLAMA_MODEL_ROOT:-$HOME/llama-models}"
RAG_HOME="${RAG_HOME:-$HOME/ai-rag}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/local-ai"
LLAMA_SWAP_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/llama-swap"
BIN_DIR="$HOME/.local/bin"
MANIFEST="$SCRIPT_DIR/local-ai-models.json"
LLAMA_SWAP_TEMPLATE="$REPO_DIR/system/llama-swap/config.template.yaml"
LLAMA_SWAP_LIVE="$LLAMA_SWAP_DIR/config.yaml"
HF_BIN="${HF_BIN:-$HOME/.local/bin/hf}"

DRY_RUN=0
DO_RUNTIME=0
DO_RAG=0
DO_MODELS=0
DO_ALL=0
DO_DOCTOR=0

usage() {
  cat <<EOF2
Usage: $0 [options]
  --dry-run           Show what would be done without making changes
  --install-runtime   Install/link llama-swap, llama-server, local-ai-runtime
  --install-rag       Install RAG Python stack
  --install-models    Download GGUF models listed in local-ai-models.json
  --all               Run all steps
  --doctor            Check current install status
  -h, --help          Show this help
EOF2
}

log() {
  printf '[local-ai] %s\n' "$*"
}

warn() {
  printf '[local-ai][warn] %s\n' "$*" >&2
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

ensure_dir() {
  run mkdir -p "$1"
}

backup_if_exists() {
  local path="$1"
  local stamp backup
  [ -e "$path" ] || return 0
  stamp="$(date +%Y%m%d-%H%M%S)"
  backup="${path}.bak.${stamp}"
  run cp -p "$path" "$backup"
}

link_bin() {
  local src="$1"
  local dest="$2"
  ensure_dir "$(dirname "$dest")"
  if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
    log "link ok: $dest"
    return 0
  fi
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    backup_if_exists "$dest"
  fi
  run ln -sfn "$src" "$dest"
}

write_if_missing() {
  local path="$1"
  local content="$2"
  if [ -e "$path" ]; then
    log "preserving existing $(basename "$path")"
    return 0
  fi
  ensure_dir "$(dirname "$path")"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] create %s\n' "$path"
    return 0
  fi
  printf '%s' "$content" >"$path"
}

render_llama_swap_config() {
  ensure_dir "$LLAMA_SWAP_DIR"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] render %s -> %s\n' "$LLAMA_SWAP_TEMPLATE" "$LLAMA_SWAP_LIVE"
    return 0
  fi
  python - "$LLAMA_SWAP_TEMPLATE" "$LLAMA_SWAP_LIVE" "$MODEL_ROOT" <<'PY'
from pathlib import Path
import datetime
import os
import re
import shutil
import sys

template = Path(sys.argv[1])
live = Path(sys.argv[2])
model_root = Path(sys.argv[3])
llama_server = '/usr/bin/llama-server'
specs = {
    'qwen3-8b': 'Qwen3-8B-Q4_K_M.gguf',
    'qwen-coder-7b': 'qwen2.5-coder-7b-instruct-q4_k_m.gguf',
    'gemma-3-4b': 'google_gemma-3-4b-it-Q4_K_M.gguf',
    'phi-4-mini': 'Phi-4-Mini-Instruct-Q4_K_M.gguf',
    'deepseek-r1-7b': 'DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf',
    'llama-3b': 'Llama-3.2-3B-Instruct-Q4_K_M.gguf',
    'qwen3-4b': 'Qwen_Qwen3-4B-Q4_K_M.gguf',
    'qwen3-router': 'Qwen_Qwen3-1.7B-Q5_K_M.gguf',
}

def valid_gguf(path: Path) -> bool:
    try:
        return path.is_file() and path.stat().st_size > 0 and path.open('rb').read(4) == b'GGUF'
    except OSError:
        return False

available = {name for name, filename in specs.items() if valid_gguf(model_root / filename)}
rendered = template.read_text().replace('__MODEL_ROOT__', str(model_root)).replace('__LLAMA_SERVER__', llama_server)
lines = rendered.splitlines()
out = []
i = 0
while i < len(lines):
    out.append(lines[i])
    if lines[i].strip() == 'models:':
        i += 1
        break
    i += 1
while i < len(lines):
    if lines[i].strip() == 'groups:':
        break
    match = re.match(r'^  ([A-Za-z0-9._-]+):\s*$', lines[i])
    if not match:
        i += 1
        continue
    name = match.group(1)
    block = [lines[i]]
    i += 1
    while i < len(lines) and lines[i].strip() != 'groups:' and not re.match(r'^  [A-Za-z0-9._-]+:\s*$', lines[i]):
        block.append(lines[i])
        i += 1
    if name in available:
        out.extend(block)
        out.append('')
if i < len(lines) and lines[i].strip() == 'groups:':
    groups = []
    for line in lines[i + 1:]:
        match = re.match(r'^  (/[^:]+): \[(.*)\]$', line)
        if not match:
            continue
        members = [item.strip() for item in match.group(2).split(',') if item.strip()]
        members = [item for item in members if item in available]
        if members:
            groups.append(f"  {match.group(1)}: [{', '.join(members)}]")
    if groups:
        out.append('groups:')
        out.extend(groups)
content = '\n'.join(out).rstrip() + '\n'
live.parent.mkdir(parents=True, exist_ok=True)
if live.exists():
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    shutil.copy2(live, live.with_name(f'{live.name}.bak.{stamp}'))
tmp = live.with_name(f'{live.name}.new')
tmp.write_text(content)
os.replace(tmp, live)
PY
}

install_runtime() {
  ensure_dir "$BIN_DIR"
  ensure_dir "$CONFIG_DIR"
  link_bin "$REPO_DIR/system/local-ai-runtime.sh" "$BIN_DIR/local-ai-runtime"
  link_bin "$REPO_DIR/system/llama-swap-manager.sh" "$BIN_DIR/llama-swap-manager"
  link_bin "$REPO_DIR/system/rag.sh" "$BIN_DIR/rag"
  write_if_missing "$CONFIG_DIR/current-model.env" $'CURRENT_MODEL=qwen3-8b\nCURRENT_ALIAS=local\nLOCAL_AI_ENDPOINT=http://127.0.0.1:8080/v1\nMODEL_ROOT='"$MODEL_ROOT"$'\n'
  write_if_missing "$CONFIG_DIR/rag.json" '{
  "endpoint": "http://127.0.0.1:8080/v1",
  "model": "local",
  "rag_home": "~/ai-rag",
  "qdrant_url": "http://127.0.0.1:6333"
}
'
  render_llama_swap_config
}

install_rag() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] bash %s\n' "$REPO_DIR/setup/install-local-rag-stack.sh"
    return 0
  fi
  bash "$REPO_DIR/setup/install-local-rag-stack.sh"
}

install_models() {
  ensure_dir "$MODEL_ROOT"
  python - "$MANIFEST" <<'PY' | while IFS='|' read -r model_id repo filename; do
import json
import sys
manifest = json.load(open(sys.argv[1]))
for model in manifest['models']:
    if model.get('experimental') or not model.get('autoload'):
        continue
    print(f"{model['id']}|{model['hf_repo']}|{model['filename']}")
PY
    [ -n "$model_id" ] || continue
    if [ -f "$MODEL_ROOT/$filename" ]; then
      log "model present: $filename"
      continue
    fi
    case "$model_id" in
      qwen3-8b)
        repo='Qwen/Qwen3-8B-GGUF'
        filename='Qwen3-8B-Q4_K_M.gguf'
        ;;
    esac
    run "$HF_BIN" download "$repo" --include "$filename" --local-dir "$MODEL_ROOT"
  done
}

doctor() {
  log 'doctor'
  command -v /usr/bin/llama-server >/dev/null 2>&1 && log 'llama-server: ok' || warn 'llama-server: missing'
  command -v "$HOME/.local/bin/llama-swap" >/dev/null 2>&1 && log 'llama-swap: ok' || warn 'llama-swap: missing'
  command -v "$HF_BIN" >/dev/null 2>&1 && log 'hf: ok' || warn 'hf: missing'
  [ -f "$MANIFEST" ] && log 'manifest: ok' || warn 'manifest: missing'
  [ -f "$LLAMA_SWAP_TEMPLATE" ] && log 'template: ok' || warn 'template: missing'
  [ -f "$LLAMA_SWAP_LIVE" ] && log 'live config: ok' || warn 'live config: missing'
  [ -f "$CONFIG_DIR/current-model.env" ] && log 'current-model.env: ok' || warn 'current-model.env: missing'
  [ -f "$CONFIG_DIR/rag.json" ] && log 'rag.json: ok' || warn 'rag.json: missing'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --install-runtime) DO_RUNTIME=1 ;;
    --install-rag) DO_RAG=1 ;;
    --install-models) DO_MODELS=1 ;;
    --all) DO_ALL=1 ;;
    --doctor) DO_DOCTOR=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [ "$DO_ALL" -eq 1 ]; then
  DO_RUNTIME=1
  DO_RAG=1
  DO_MODELS=1
  DO_DOCTOR=1
fi

if [ "$DO_RUNTIME" -eq 0 ] && [ "$DO_RAG" -eq 0 ] && [ "$DO_MODELS" -eq 0 ] && [ "$DO_DOCTOR" -eq 0 ]; then
  usage >&2
  exit 1
fi

if [ "$DO_RUNTIME" -eq 1 ]; then
  install_runtime
fi
if [ "$DO_RAG" -eq 1 ]; then
  install_rag
fi
if [ "$DO_MODELS" -eq 1 ]; then
  install_models
fi
if [ "$DO_DOCTOR" -eq 1 ]; then
  doctor
fi

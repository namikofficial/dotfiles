#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SOURCE_PATH")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TARGET_REPO="${TARGET_REPO:-dotfiles}"
RUNS="${RUNS:-5}"
WARMUP="${WARMUP:-1}"
REINDEX_FIRST=0
SEARCH_QUERY="${SEARCH_QUERY:-hyprland notification panel}"
INSPECT_QUERY="${INSPECT_QUERY:-cmd_doctor}"
GRAPH_QUERY="${GRAPH_QUERY:-cmd_doctor}"
WHY_QUERY="${WHY_QUERY:-doctor status health}"
WHY_PATH="${WHY_PATH:-system/rag/cli.py}"
QUICK_QUERY="${QUICK_QUERY:-What does Super Alt S do?}"
DEEP_QUERY="${DEEP_QUERY:-Review the retrieval architecture for this repo.}"
LOG_DIR="${LOG_DIR:-$REPO_DIR/logs}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_FILE="$LOG_DIR/rag-benchmark-$TIMESTAMP.log"
BENCH_FILE="$LOG_DIR/rag-benchmark-$TIMESTAMP.json"

usage() {
  cat <<EOF
Usage: $0 [--repo NAME] [--runs N] [--warmup N] [--reindex]

Runs a repeatable local RAG validation + benchmark pass and writes:
  - report: $REPORT_FILE
  - benchmark json: $BENCH_FILE

Options:
  --repo NAME          Indexed repo name to target (default: $TARGET_REPO)
  --runs N             Benchmark repetitions (default: $RUNS)
  --warmup N           Warmup runs when using hyperfine (default: $WARMUP)
  --reindex            Run a changed-only reindex for the repo before validation/benchmarks
  --search-query Q     Query for search/inspect benchmarks
  --graph-query Q      Query for graph benchmark
  --why-query Q        Query for why benchmark
  --why-path PATH      Indexed path for why benchmark
  --quick-query Q      Query for quick benchmark
  --deep-query Q       Query for deep benchmark
  --help               Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) TARGET_REPO="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --warmup) WARMUP="$2"; shift 2 ;;
    --reindex) REINDEX_FIRST=1; shift ;;
    --search-query) SEARCH_QUERY="$2"; shift 2 ;;
    --graph-query) GRAPH_QUERY="$2"; shift 2 ;;
    --why-query) WHY_QUERY="$2"; shift 2 ;;
    --why-path) WHY_PATH="$2"; shift 2 ;;
    --quick-query) QUICK_QUERY="$2"; shift 2 ;;
    --deep-query) DEEP_QUERY="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

mkdir -p "$LOG_DIR"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

need_cmd rag
need_cmd python3

log() {
  printf '%s\n' "$*" | tee -a "$REPORT_FILE"
}

run_logged() {
  local label="$1"
  shift
  log
  log "### $label"
  {
    printf '$ %s\n' "$*"
    "$@"
  } 2>&1 | tee -a "$REPORT_FILE"
}

rag_cmd() {
  rag "$@"
}

cd "$REPO_DIR"

: >"$REPORT_FILE"
log "# Local RAG validation + benchmark"
log "timestamp: $(date --iso-8601=seconds)"
log "repo root: $REPO_DIR"
log "target repo: $TARGET_REPO"
log "runs: $RUNS"
log "warmup: $WARMUP"
log "reindex first: $REINDEX_FIRST"
log "host: $(uname -srmo)"

run_logged "RAG CLI help" rag_cmd --help
if [ "$REINDEX_FIRST" -eq 1 ]; then
  run_logged "RAG changed-only reindex" rag_cmd index "$REPO_DIR" --changed-only
fi
run_logged "RAG status" rag_cmd status
run_logged "RAG doctor deep" rag_cmd doctor --deep
run_logged "Pytest RAG suite" python3 -m pytest -q tests/rag

MODEL_AVAILABLE=1
if grep -Eiq 'answer model[[:space:]]+fail|answer generation[[:space:]]+fail' "$REPORT_FILE"; then
  MODEL_AVAILABLE=0
  log
  log "### Model-backed benchmarks"
  log "Skipping quick/deep model-backed benchmarks because doctor reported an answer-model failure."
fi

BENCHMARKS=()
BENCHMARKS+=("search::rag search \"$SEARCH_QUERY\" --repo \"$TARGET_REPO\" >/dev/null")
BENCHMARKS+=("inspect::rag inspect \"$INSPECT_QUERY\" --repo \"$TARGET_REPO\" >/dev/null")
BENCHMARKS+=("missing::rag missing \"$SEARCH_QUERY\" --repo \"$TARGET_REPO\" >/dev/null")
BENCHMARKS+=("why::rag why \"$WHY_QUERY\" \"$WHY_PATH\" --repo \"$TARGET_REPO\" >/dev/null")
BENCHMARKS+=("graph::rag graph \"$GRAPH_QUERY\" --repo \"$TARGET_REPO\" >/dev/null")

if [ "$MODEL_AVAILABLE" -eq 1 ]; then
  BENCHMARKS+=("quick::rag quick \"$QUICK_QUERY\" --repo \"$TARGET_REPO\" >/dev/null")
  BENCHMARKS+=("deep::rag deep \"$DEEP_QUERY\" --repo \"$TARGET_REPO\" >/dev/null")
fi

log
log "### Benchmarks"
READY_BENCHMARKS=()
for entry in "${BENCHMARKS[@]}"; do
  name="${entry%%::*}"
  cmd="${entry#*::}"
  if sh -lc "$cmd"; then
    READY_BENCHMARKS+=("$entry")
  else
    log "Skipping benchmark '$name' because its preflight command failed."
  fi
done

if [ "${#READY_BENCHMARKS[@]}" -eq 0 ]; then
  log "No benchmark commands passed preflight."
  log
  log "Benchmark report: $REPORT_FILE"
  exit 1
fi

if command -v hyperfine >/dev/null 2>&1; then
  HYPERFINE_ARGS=()
  for entry in "${READY_BENCHMARKS[@]}"; do
    name="${entry%%::*}"
    cmd="${entry#*::}"
    HYPERFINE_ARGS+=("--command-name" "$name" "$cmd")
  done
  hyperfine \
    --warmup "$WARMUP" \
    --runs "$RUNS" \
    --export-json "$BENCH_FILE" \
    "${HYPERFINE_ARGS[@]}" 2>&1 | tee -a "$REPORT_FILE"
else
  python3 - "$RUNS" "$BENCH_FILE" "${READY_BENCHMARKS[@]}" <<'PY' 2>&1 | tee -a "$REPORT_FILE"
import json
import statistics
import subprocess
import sys
import time

runs = int(sys.argv[1])
out_path = sys.argv[2]
entries = sys.argv[3:]
results = []

for entry in entries:
    name, command = entry.split("::", 1)
    samples = []
    for _ in range(runs):
        start = time.perf_counter()
        completed = subprocess.run(command, shell=True, check=True)
        samples.append(time.perf_counter() - start)
    result = {
        "name": name,
        "runs": runs,
        "mean_seconds": statistics.mean(samples),
        "min_seconds": min(samples),
        "max_seconds": max(samples),
        "samples_seconds": samples,
    }
    results.append(result)
    print(f"{name}: mean={result['mean_seconds']:.3f}s min={result['min_seconds']:.3f}s max={result['max_seconds']:.3f}s")

with open(out_path, "w", encoding="utf-8") as handle:
    json.dump({"results": results}, handle, indent=2)
    handle.write("\n")
PY
fi

log
log "Benchmark report: $REPORT_FILE"
log "Benchmark data: $BENCH_FILE"

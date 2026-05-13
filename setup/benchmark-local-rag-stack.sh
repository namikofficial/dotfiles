#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SOURCE_PATH")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TARGET_REPO="${TARGET_REPO:-dotfiles}"
TARGET_PATH="${TARGET_PATH:-$REPO_DIR}"
RUNS="${RUNS:-5}"
WARMUP="${WARMUP:-1}"
BENCH_TIMEOUT="${BENCH_TIMEOUT:-120}"
REINDEX_FIRST=0
FULL_INDEX=0
SKIP_TESTS=0
SKIP_MODEL_TPS=0
START_RUNTIME=1
SEARCH_QUERY="${SEARCH_QUERY:-hyprland notification panel}"
INSPECT_QUERY="${INSPECT_QUERY:-cmd_doctor}"
GRAPH_QUERY="${GRAPH_QUERY:-cmd_doctor}"
WHY_QUERY="${WHY_QUERY:-doctor status health}"
WHY_PATH="${WHY_PATH:-system/rag/cli.py}"
QUICK_QUERY="${QUICK_QUERY:-What does Super Alt S do?}"
DEEP_QUERY="${DEEP_QUERY:-Review the retrieval architecture for this repo.}"
PLAN_QUERY="${PLAN_QUERY:-implement profile router}"
CONTEXT_QUERY="${CONTEXT_QUERY:-implement profile router}"
TPS_QUERY="${TPS_QUERY:-Write a concise technical summary of this repository in 120 words.}"
LOG_DIR="${LOG_DIR:-$REPO_DIR/logs}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_FILE="$LOG_DIR/rag-benchmark-$TIMESTAMP.log"
BENCH_FILE="$LOG_DIR/rag-benchmark-$TIMESTAMP.json"

usage() {
  cat <<EOF
Usage: $0 [--repo NAME] [--path PATH] [--runs N] [--warmup N] [--reindex]

Runs a repeatable local RAG validation + benchmark pass and writes:
  - report: $REPORT_FILE
  - benchmark json: $BENCH_FILE

Options:
  --repo NAME          Indexed repo name to target (default: $TARGET_REPO)
  --path PATH          Repo/folder path to index when --reindex is used (default: $TARGET_PATH)
  --runs N             Benchmark repetitions (default: $RUNS)
  --warmup N           Warmup runs when using hyperfine (default: $WARMUP)
  --timeout SECONDS    Per-command benchmark timeout (default: $BENCH_TIMEOUT)
  --reindex            Run a changed-only reindex for the repo before validation/benchmarks
  --full-index         Run a full index for --path before validation/benchmarks
  --skip-tests         Skip the dotfiles RAG unit test suite
  --skip-model-tps     Skip the direct local answer-model tokens/sec probe
  --no-start-runtime   Do not run local-ai-runtime start before model checks
  --search-query Q     Query for search/inspect benchmarks
  --graph-query Q      Query for graph benchmark
  --why-query Q        Query for why benchmark
  --why-path PATH      Indexed path for why benchmark
  --quick-query Q      Query for quick benchmark
  --deep-query Q       Query for deep benchmark
  --plan-query Q       Query for v7 --plan benchmark
  --context-query Q    Query for v7 --context benchmark
  --tps-query Q        Prompt for direct answer-model tokens/sec probe
  --help               Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) TARGET_REPO="$2"; shift 2 ;;
    --path) TARGET_PATH="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --warmup) WARMUP="$2"; shift 2 ;;
    --timeout) BENCH_TIMEOUT="$2"; shift 2 ;;
    --reindex) REINDEX_FIRST=1; shift ;;
    --full-index) FULL_INDEX=1; shift ;;
    --skip-tests) SKIP_TESTS=1; shift ;;
    --skip-model-tps) SKIP_MODEL_TPS=1; shift ;;
    --no-start-runtime) START_RUNTIME=0; shift ;;
    --search-query) SEARCH_QUERY="$2"; shift 2 ;;
    --graph-query) GRAPH_QUERY="$2"; shift 2 ;;
    --why-query) WHY_QUERY="$2"; shift 2 ;;
    --why-path) WHY_PATH="$2"; shift 2 ;;
    --quick-query) QUICK_QUERY="$2"; shift 2 ;;
    --deep-query) DEEP_QUERY="$2"; shift 2 ;;
    --plan-query) PLAN_QUERY="$2"; shift 2 ;;
    --context-query) CONTEXT_QUERY="$2"; shift 2 ;;
    --tps-query) TPS_QUERY="$2"; shift 2 ;;
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

run_logged_allow_fail() {
  local label="$1"
  shift
  log
  log "### $label"
  set +e
  {
    printf '$ %s\n' "$*"
    "$@"
  } 2>&1 | tee -a "$REPORT_FILE"
  local status=${PIPESTATUS[0]}
  set -e
  if [ "$status" -ne 0 ]; then
    log "Command exited with status $status; continuing benchmark."
  fi
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
log "target path: $TARGET_PATH"
log "runs: $RUNS"
log "warmup: $WARMUP"
log "benchmark timeout: ${BENCH_TIMEOUT}s"
log "reindex first: $REINDEX_FIRST"
log "full index: $FULL_INDEX"
log "host: $(uname -srmo)"

run_logged "RAG CLI help" rag_cmd --help
if [ "$FULL_INDEX" -eq 1 ]; then
  run_logged "RAG full index" rag_cmd index "$TARGET_PATH"
elif [ "$REINDEX_FIRST" -eq 1 ]; then
  run_logged "RAG changed-only reindex" rag_cmd index "$TARGET_PATH" --changed-only
fi
run_logged "RAG status" rag_cmd status
if [ "$START_RUNTIME" -eq 1 ] && command -v local-ai-runtime >/dev/null 2>&1; then
  run_logged_allow_fail "Local AI runtime start" timeout "${BENCH_TIMEOUT}s" local-ai-runtime start
fi
run_logged_allow_fail "RAG doctor deep" rag_cmd doctor --deep
if [ "$SKIP_TESTS" -eq 0 ]; then
  run_logged "Pytest RAG suite" python3 -m pytest -q tests/rag
else
  log
  log "### Pytest RAG suite"
  log "Skipped by --skip-tests"
fi

MODEL_AVAILABLE=1
if grep -Eiq 'answer model[[:space:]]+fail|answer generation[[:space:]]+fail' "$REPORT_FILE"; then
  MODEL_AVAILABLE=0
  log
  log "### Model-backed benchmarks"
  log "Skipping quick/deep model-backed benchmarks because doctor reported an answer-model failure."
fi

BENCHMARKS=()
BENCHMARKS+=("v7-plan::rag --plan \"$PLAN_QUERY\" --repo \"$TARGET_REPO\" >/dev/null")
BENCHMARKS+=("v7-context::rag --context \"$CONTEXT_QUERY\" --repo \"$TARGET_REPO\" >/dev/null")
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
  if timeout "${BENCH_TIMEOUT}s" sh -lc "$cmd"; then
    wrapped_cmd="timeout ${BENCH_TIMEOUT}s sh -lc $(printf '%q' "$cmd")"
    READY_BENCHMARKS+=("$name::$wrapped_cmd")
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

if [ "$MODEL_AVAILABLE" -eq 1 ] && [ "$SKIP_MODEL_TPS" -eq 0 ]; then
  log
  log "### Answer model tokens/sec"
  python3 - "$TPS_QUERY" "$BENCH_FILE.tps.json" <<'PY' 2>&1 | tee -a "$REPORT_FILE"
import json
import sys
import time
import urllib.request

sys.path.insert(0, "system")
from rag.settings import load_config

prompt = sys.argv[1]
out_path = sys.argv[2]
config = load_config()
payload = {
    "model": config["answer_model"],
    "messages": [
        {"role": "system", "content": "You are a concise local benchmark assistant."},
        {"role": "user", "content": prompt},
    ],
    "max_tokens": 220,
    "temperature": 0,
}
body = json.dumps(payload).encode("utf-8")
request = urllib.request.Request(
    config["answer_url"],
    data=body,
    headers={"Content-Type": "application/json"},
    method="POST",
)
started = time.perf_counter()
with urllib.request.urlopen(request, timeout=240) as response:
    response_payload = json.loads(response.read().decode("utf-8") or "{}")
elapsed = time.perf_counter() - started
usage = response_payload.get("usage", {})
completion_tokens = int(usage.get("completion_tokens") or 0)
prompt_tokens = int(usage.get("prompt_tokens") or 0)
total_tokens = int(usage.get("total_tokens") or (prompt_tokens + completion_tokens))
text = response_payload.get("choices", [{}])[0].get("message", {}).get("content", "")
if completion_tokens <= 0:
    completion_tokens = max(1, len(text.split()))
tokens_per_second = completion_tokens / elapsed if elapsed else 0.0
result = {
    "answer_url": config["answer_url"],
    "answer_model": config["answer_model"],
    "elapsed_seconds": elapsed,
    "prompt_tokens": prompt_tokens,
    "completion_tokens": completion_tokens,
    "total_tokens": total_tokens,
    "tokens_per_second": tokens_per_second,
}
with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(result, handle, indent=2)
    handle.write("\n")
print(
    f"model={result['answer_model']} elapsed={elapsed:.3f}s "
    f"completion_tokens={completion_tokens} tokens_per_second={tokens_per_second:.2f}"
)
PY
else
  log
  log "### Answer model tokens/sec"
  log "Skipped (model unavailable or --skip-model-tps used)."
fi

log
log "Benchmark report: $REPORT_FILE"
log "Benchmark data: $BENCH_FILE"

#!/usr/bin/env bash
# Verify the local model stack: router preset, model files and pi wiring.
#
# Checks the rendered preset against the models that are actually on disk and
# against the pi model catalogue, so a lane can never drift between the
# router and the client without this failing.
#
# Usage: setup/test-local-models.sh [--require-router]
#
#   --require-router  also require the router to be running and healthy
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
model_root="${LLAMA_MODEL_ROOT:-/home/namik/llama-models}"
preset="${LLAMA_ROUTER_PRESET:-$HOME/.config/llama-router/models.ini}"
pi_models="${PI_MODELS_FILE:-$HOME/.pi/agent/models.json}"
require_router=0

if [[ "${1:-}" == "--require-router" ]]; then
  require_router=1
  shift
fi
if (($# != 0)); then
  printf 'Usage: %s [--require-router]\n' "$0" >&2
  exit 64
fi

command -v python3 >/dev/null 2>&1 || {
  printf 'python3 is required\n' >&2
  exit 1
}

command -v llama-server >/dev/null 2>&1 || {
  printf 'llama-server is not installed\n' >&2
  exit 1
}
printf 'llama-server: %s\n' "$(llama-server --version 2>&1 | head -1)"

if [[ ! -d "$model_root" ]]; then
  printf 'model root missing: %s\n' "$model_root" >&2
  exit 1
fi
printf 'model root  : %s\n' "$model_root"

python3 "$repo_dir/system/llama-router/render-preset.py" \
  --model-root "$model_root" --output "$preset" >/dev/null
printf 'preset      : %s\n' "$preset"

# Every lane in the preset must point at a file that exists, and every pi
# model id must correspond to a lane with a matching context window.
python3 - "$preset" "$pi_models" <<'PY'
import json
import re
import sys
from pathlib import Path

preset_path = Path(sys.argv[1])
pi_path = Path(sys.argv[2])

text = preset_path.read_text(encoding="utf-8")
lanes: dict[str, int] = {}
current = None
for line in text.splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("[") and line.endswith("]"):
        current = line[1:-1]
        if current != "*":
            lanes[current] = 0
        continue
    if current and current != "*" and line.startswith("c ="):
        lanes[current] = int(line.split("=", 1)[1].strip())

if not lanes:
    print("preset contains no lanes", file=sys.stderr)
    raise SystemExit(1)

missing = []
for lane, ctx in lanes.items():
    match = re.search(rf"\[{re.escape(lane)}\]\nmodel = (\S+)\nc = (\d+)", text)
    if not match:
        print(f"lane {lane}: malformed preset section", file=sys.stderr)
        raise SystemExit(1)
    model_path = Path(match.group(1))
    if not model_path.is_file():
        missing.append(f"{lane}: {model_path}")
if missing:
    print("preset lanes point at missing files:", file=sys.stderr)
    for item in missing:
        print(f"  {item}", file=sys.stderr)
    raise SystemExit(1)

print(f"lanes       : {len(lanes)} ({', '.join(sorted(lanes))})")

if not pi_path.is_file():
    print(f"pi model catalogue not found: {pi_path}", file=sys.stderr)
    raise SystemExit(1)

catalogue = json.loads(pi_path.read_text(encoding="utf-8"))
providers = catalogue.get("providers", catalogue)
llama = providers.get("llama-cpp", {})
# pi stores the catalogue as a list of model objects.
models = llama.get("models", [])
if isinstance(models, dict):
    models = [dict(spec, id=model_id) for model_id, spec in models.items()]
if not models:
    print("pi catalogue has no llama-cpp models", file=sys.stderr)
    raise SystemExit(1)

for spec in models:
    model_id = spec.get("id")
    if model_id not in lanes:
        print(f"pi model {model_id!r} has no matching router lane", file=sys.stderr)
        raise SystemExit(1)
    declared = int(spec.get("contextWindow", 0))
    if declared != lanes[model_id]:
        print(
            f"pi model {model_id!r} declares contextWindow {declared} "
            f"but the router lane is configured for {lanes[model_id]}",
            file=sys.stderr,
        )
        raise SystemExit(1)

print(f"pi models   : {len(models)} wired to matching lanes")
PY

if ((require_router)); then
  health="$(curl -fsS --max-time 5 http://127.0.0.1:8080/health 2>/dev/null || true)"
  if [[ -z "$health" ]]; then
    printf 'router is not reachable on 127.0.0.1:8080\n' >&2
    exit 1
  fi
  printf 'router      : %s\n' "$health"

  curl -fsS --max-time 5 http://127.0.0.1:8080/models |
    python3 -c '
import json
import sys

payload = json.load(sys.stdin)
ids = {entry.get("id") for entry in payload.get("data", [])}
if not ids:
    print("router exposes no lanes", file=sys.stderr)
    raise SystemExit(1)
print("router lanes: {}".format(len(ids)))
'
fi

printf 'Local model stack: ok\n'

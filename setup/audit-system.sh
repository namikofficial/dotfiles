#!/usr/bin/env bash
set -u -o pipefail

# Read-only workstation evidence collector. It never runs sudo, changes system
# configuration, starts/stops services, mounts filesystems, or performs a
# backup restore. It writes only its Markdown/JSON report.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
output_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow/audits"

while (($#)); do
  case "$1" in
    --output-dir)
      [[ $# -ge 2 ]] || {
        printf '%s\n' '--output-dir requires a path' >&2
        exit 2
      }
      output_dir="$2"
      shift 2
      ;;
    --help | -h)
      printf 'Usage: %s [--output-dir DIR]\n' "${0##*/}"
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$output_dir"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
records="$work_dir/records.tsv"
: >"$records"

record() {
  local id="$1" status="$2" detail="$3"
  detail="${detail//$'\n'/ }"
  detail="${detail//$'\r'/ }"
  detail="${detail//$'\t'/ }"
  printf '%s\t%s\t%s\n' "$id" "$status" "$detail" >>"$records"
}

has() { command -v "$1" >/dev/null 2>&1; }

capture() {
  local max_bytes=4000
  if (($# > 1)) && [[ "$1" == --max-bytes ]]; then
    max_bytes="$2"
    shift 2
  fi
  if ! has "$1"; then
    printf 'not installed: %s' "$1"
    return 0
  fi
  "$@" 2>&1 | head -c "$max_bytes" | tr '\n' ' ' || true
}

record command.jq "$(has jq && echo PASS || echo N/A)" "jq availability"
record command.restic "$(has restic && echo PASS || echo N/A)" "restic availability; restore drill is intentionally not run"
record command.smartctl "$(has smartctl && echo PASS || echo N/A)" "smartctl availability; privileged device reads are not attempted"

if has findmnt; then record storage.filesystem PASS "$(capture findmnt -no SOURCE,FSTYPE,OPTIONS /)"; else record storage.filesystem N/A "findmnt unavailable"; fi
if has lsblk; then record storage.devices PASS "$(capture --max-bytes 3000 lsblk -o NAME,TYPE,FSTYPE,SIZE,MOUNTPOINTS)"; else record storage.devices N/A "lsblk unavailable"; fi
if has systemctl; then
  trim_state="$(systemctl is-enabled fstrim.timer 2>/dev/null || true)"
  case "$trim_state" in
    enabled | static | indirect) record storage.trim PASS "$trim_state periodic TRIM timer" ;;
    disabled | masked) record storage.trim WARN "$trim_state periodic TRIM timer" ;;
    *) record storage.trim N/A "periodic TRIM timer state unavailable" ;;
  esac
  record services.system_failed PASS "$(capture systemctl --failed --no-legend)"
  record services.user_failed PASS "$(capture systemctl --user --failed --no-legend)"
  record services.user_timers PASS "$(capture systemctl --user list-timers --all --no-legend)"
else
  record services.system_failed N/A "systemctl unavailable"
fi

if has free; then record resources.memory PASS "$(capture free -h)"; else record resources.memory N/A "free unavailable"; fi
if has swapon; then record resources.swap PASS "$(capture swapon --show)"; else record resources.swap N/A "swapon unavailable"; fi
if [[ -r /proc/sys/vm/swappiness ]]; then record resources.swappiness PASS "$(</proc/sys/vm/swappiness)"; else record resources.swappiness N/A "sysctl unavailable"; fi
if [[ -r /proc/pressure/memory ]]; then record resources.psi_memory PASS "$(tr '\n' ' ' </proc/pressure/memory)"; else record resources.psi_memory N/A "memory PSI unavailable"; fi
if [[ -r /proc/pressure/io ]]; then record resources.psi_io PASS "$(tr '\n' ' ' </proc/pressure/io)"; else record resources.psi_io N/A "IO PSI unavailable"; fi
if has vmstat; then record resources.vmstat PASS "$(capture vmstat 1 2)"; else record resources.vmstat N/A "vmstat unavailable"; fi

if has biome; then
  biome_path="$(command -v biome)"
  record crash.biome_binary PASS "path=$biome_path resolved=$(readlink -f "$biome_path" 2>/dev/null || printf unknown) version=$(biome --version 2>&1 | head -c 200)"
else
  record crash.biome_binary N/A "biome is not on PATH"
fi
if has coredumpctl; then record crash.coredumps PASS "$(capture --max-bytes 3000 coredumpctl list biome)"; else record crash.coredumps N/A "coredumpctl unavailable"; fi

if has pacman; then
  record packages.database PASS "$(capture pacman -Dk)"
  record packages.foreign PASS "$(capture pacman -Qm)"
  record packages.orphans PASS "$(capture pacman -Qdtq)"
else
  record packages.database N/A "pacman unavailable"
fi
if has checkupdates; then record packages.updates PASS "$(capture checkupdates)"; else record packages.updates N/A "checkupdates unavailable"; fi
pacnew_count="$(find /etc -type f \( -name '*.pacnew' -o -name '*.pacsave' \) 2>/dev/null | wc -l | tr -d ' ')"
record packages.pacnew PASS "$pacnew_count files found under /etc"

if has ss; then record security.listeners PASS "$(capture --max-bytes 5000 ss -lntup)"; else record security.listeners N/A "ss unavailable"; fi
if has nft; then record security.firewall PASS "$(capture --max-bytes 4000 nft list ruleset)"; else record security.firewall N/A "nft unavailable or permission denied"; fi
if has docker; then record security.docker PASS "$(capture docker ps --format '{{.Names}} {{.Ports}}')"; else record security.docker N/A "docker unavailable"; fi

if [[ -f "$repo_root/configs/opencode/opencode.local-llamacpp.json" ]] && has jq; then
  cfg="$repo_root/configs/opencode/opencode.local-llamacpp.json"
  record ai.config PASS "$(jq -r '[.model, .default_agent, (.agent|length|tostring), (.mcp|to_entries|map(select(.value.enabled==true)|.key)|join(",")), (.tool_output.max_bytes|tostring)]|join(" | ")' "$cfg" 2>/dev/null || echo invalid-config)"
else
  record ai.config N/A "canonical OpenCode config or jq unavailable"
fi
if [[ -d "$HOME/.config/opencode/context-mode/sessions" ]]; then
  record ai.context_mode PASS "$(find "$HOME/.config/opencode/context-mode/sessions" -maxdepth 1 -name 'stats-*.json' 2>/dev/null | wc -l | tr -d ' ') stats files"
else
  record ai.context_mode N/A "OpenCode context-mode session stats unavailable"
fi

for repo in "$repo_root" "$HOME/Documents/code/noxorigin/noxorigin"; do
  if [[ -d "$repo/.git" ]] && has git; then
    name="git.$(basename "$repo")"
    record "$name" PASS "$(git -C "$repo" status --short | head -c 3000 | tr '\n' ' ')"
  fi
done

report_md="$output_dir/workstation-audit-$timestamp.md"
report_json="$output_dir/workstation-audit-$timestamp.json"

python3 - "$records" "$report_md" "$report_json" "$timestamp" <<'PY'
import json, pathlib, sys
records_path, md_path, json_path, timestamp = sys.argv[1:]
rows = []
for line in pathlib.Path(records_path).read_text().splitlines():
    fields = line.split("\t", 2)
    if len(fields) == 2:
        fields.append("")
    ident, status, detail = fields
    rows.append({"id": ident, "status": status, "detail": detail})
summary = {s: sum(r["status"] == s for r in rows) for s in ("PASS", "WARN", "FAIL", "N/A", "DEGRADED")}
pathlib.Path(json_path).write_text(json.dumps({"schemaVersion": 1, "generatedAt": timestamp, "readOnly": True, "summary": summary, "checks": rows}, indent=2) + "\n")
lines = [f"# Workstation audit — {timestamp}", "", "Read-only report. No service, credential, filesystem, backup, or configuration changes were made.", "", "## Summary", "", "| Status | Count |", "| --- | ---: |"]
lines += [f"| {s} | {summary[s]} |" for s in summary]
lines += ["", "## Checks", "", "| Check | Status | Evidence |", "| --- | --- | --- |"]
for r in rows:
    detail = r["detail"].replace("|", "\\|")
    lines.append(f"| `{r['id']}` | **{r['status']}** | {detail} |")
pathlib.Path(md_path).write_text("\n".join(lines) + "\n")
PY
python_status=$?
if ((python_status != 0)); then
  printf 'failed to write audit reports\n' >&2
  exit "$python_status"
fi

printf 'Markdown: %s\nJSON: %s\n' "$report_md" "$report_json"

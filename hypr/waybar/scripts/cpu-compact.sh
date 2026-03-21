#!/usr/bin/env sh
set -eu

state_dir="${XDG_RUNTIME_DIR:-/tmp}/noxflow-waybar"
overall_prev="$state_dir/cpu.prev"
cores_prev="$state_dir/cpu-cores.prev"
cores_curr="$state_dir/cpu-cores.curr"
mkdir -p "$state_dir"

read_cpu() {
  awk '/^cpu / {print $2, $3, $4, $5, $6, $7, $8}' /proc/stat
}

set -- $(read_cpu)
user="$1"; nice="$2"; system="$3"; idle="$4"; iowait="$5"; irq="$6"; softirq="$7"

total=$((user + nice + system + idle + iowait + irq + softirq))
idle_all=$((idle + iowait))

if [ -f "$overall_prev" ]; then
  prev_total="$(cut -d' ' -f1 "$overall_prev" 2>/dev/null || echo 0)"
  prev_idle="$(cut -d' ' -f2 "$overall_prev" 2>/dev/null || echo 0)"
else
  prev_total="$total"
  prev_idle="$idle_all"
fi
printf '%s %s\n' "$total" "$idle_all" >"$overall_prev"

delta_total=$((total - prev_total))
delta_idle=$((idle_all - prev_idle))
if [ "$delta_total" -le 0 ]; then
  usage=0
else
  usage=$((100 * (delta_total - delta_idle) / delta_total))
fi

awk '/^cpu[0-9]+ / {total=$2+$3+$4+$5+$6+$7+$8; idle=$5+$6; print $1, total, idle}' /proc/stat >"$cores_curr"

if [ -f "$cores_prev" ]; then
  per_core="$(awk '
    NR==FNR {pt[$1]=$2; pi[$1]=$3; next}
    {
      dt=$2-pt[$1]; di=$3-pi[$1];
      u=(dt>0)?int((100*(dt-di))/dt):0;
      printf "%s: %d%%\n", $1, u;
    }
  ' "$cores_prev" "$cores_curr" | sed -n '1,12p')"
else
  per_core="Core data warming up..."
fi
mv "$cores_curr" "$cores_prev"

load_avg="$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null || echo 'n/a')"
tooltip="$(printf 'CPU %s%%\nLoad %s\n\n%s\n\nClick: open btop' "$usage" "$load_avg" "$per_core")"
jq -cn --arg text "CPU ${usage}%" --arg tooltip "$tooltip" '{text:$text, tooltip:$tooltip}'

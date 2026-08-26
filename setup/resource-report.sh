#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' '== memory =='
free -h
printf '%s\n' '== top RSS =='
ps -eo pid=,ppid=,%cpu=,%mem=,rss=,etime=,comm=,args= --sort=-rss | head -n 20
printf '%s\n' '== swap =='
swapon --show 2>/dev/null || true
printf '%s\n' '== MCP processes =='
mcp_profile="${MCP_PROFILE_BIN:-$(command -v mcp-profile || true)}"
if [ -n "$mcp_profile" ]; then
  "$mcp_profile" status
else
  printf 'mcp-profile is not installed; run setup/bootstrap.sh or use setup/mcp-profile.sh\n'
fi
printf '%s\n' '== TrackMe processes =='
ps -eo pid=,ppid=,rss=,etime=,args= | rg 'trackMe|vite|expo start|tsx watch|cloudflared.*localtrackme' || true
printf '%s\n' '== NoxFlow =='
systemctl --user show noxd.service noxflow-shell.service \
  --property=Id,MainPID,MemoryCurrent,MemoryPeak,CPUUsageNSec --no-pager 2>/dev/null || true

noxd_cgroup="/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/app.slice/noxd.service"
if [ -r "$noxd_cgroup/memory.stat" ]; then
  awk '/^(anon|file|kernel|inactive_file) / { printf "%s=%s KiB\n", $1, $2 / 1024 }' "$noxd_cgroup/memory.stat"
fi

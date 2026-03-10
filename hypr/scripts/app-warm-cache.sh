#!/usr/bin/env bash
set -euo pipefail

if [[ "${NOXFLOW_WARM_CACHE_BACKGROUND:-0}" != "1" ]]; then
  if command -v ionice >/dev/null 2>&1; then
    exec ionice -c3 nice -n 19 env NOXFLOW_WARM_CACHE_BACKGROUND=1 "$0" "$@"
  fi
  exec nice -n 19 env NOXFLOW_WARM_CACHE_BACKGROUND=1 "$0" "$@"
fi

min_avail_kib="${NOXFLOW_WARM_MIN_AVAILABLE_KIB:-6291456}"
available_kib="$(awk '/MemAvailable:/ { print $2 }' /proc/meminfo 2>/dev/null || true)"
if [[ -z "$available_kib" || "$available_kib" -lt "$min_avail_kib" ]]; then
  exit 0
fi

print_if_readable() {
  local file="$1"
  [[ -r "$file" ]] || return 0
  printf '%s\0' "$file"
}

print_ldd_files() {
  local file="$1"
  [[ -x "$file" ]] || return 0
  ldd "$file" 2>/dev/null \
    | awk '/=> \// { print $3 } /^\/[^[:space:]]+/ { print $1 }' \
    | while IFS= read -r dep; do
        [[ -r "$dep" ]] || continue
        printf '%s\0' "$dep"
      done
}

chrome_files() {
  local root="/opt/google/chrome"
  print_if_readable "$root/chrome"
  print_if_readable "$root/resources.pak"
  print_if_readable "$root/chrome_100_percent.pak"
  print_if_readable "$root/icudtl.dat"
  print_if_readable "$root/v8_context_snapshot.bin"
  print_if_readable "$root/libEGL.so"
  print_if_readable "$root/libGLESv2.so"
  print_if_readable "$root/libvulkan.so.1"
  print_if_readable "$root/locales/en-US.pak"
  print_ldd_files "$root/chrome"
}

code_files() {
  local root="/usr/lib/code"
  local electron_root="/usr/lib/electron39"
  print_if_readable "$electron_root/electron"
  print_if_readable "$electron_root/resources.pak"
  print_if_readable "$electron_root/chrome_100_percent.pak"
  print_if_readable "$electron_root/icudtl.dat"
  print_if_readable "$electron_root/v8_context_snapshot.bin"
  print_if_readable "$electron_root/libEGL.so"
  print_if_readable "$electron_root/libGLESv2.so"
  print_if_readable "$electron_root/libffmpeg.so"
  print_if_readable "$root/code.mjs"
  print_if_readable "$root/node_modules.asar"
  print_if_readable "$root/product.json"
  print_ldd_files "$electron_root/electron"
}

warm_stream() {
  sort -zu \
    | while IFS= read -r -d '' file; do
        dd if="$file" of=/dev/null bs=8M iflag=fullblock status=none 2>/dev/null || true
      done
}

case "${1:-all}" in
  chrome)
    chrome_files | warm_stream
    ;;
  code)
    code_files | warm_stream
    ;;
  all|--session)
    {
      chrome_files
      code_files
    } | warm_stream
    ;;
  *)
    echo "usage: $0 [chrome|code|all|--session]" >&2
    exit 2
    ;;
esac

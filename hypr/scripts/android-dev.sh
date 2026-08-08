#!/usr/bin/env bash
set -euo pipefail

# Runtime links are installed by bootstrap.
# shellcheck disable=SC1091
[[ -r "$HOME/.config/environment.d/60-android.conf" ]] && source "$HOME/.config/environment.d/60-android.conf"
# shellcheck disable=SC1091
[[ -r "$HOME/.config/dotfiles/machine.env" ]] && source "$HOME/.config/dotfiles/machine.env"

choose_avd() {
  mapfile -t avds < <(emulator -list-avds 2>/dev/null)
  ((${#avds[@]})) || {
    printf 'No AVDs found. Create one in Android Studio.\n' >&2
    exit 1
  }
  if ((${#avds[@]} == 1)); then
    printf '%s\n' "${avds[0]}"
    return
  fi
  printf '%s\n' "${avds[@]}" | rofi -dmenu -p 'Android AVD'
}

case "${1:-menu}" in
  studio) exec android-studio ;;
  code) exec code "${2:-.}" ;;
  start | start-fast)
    command -v emulator >/dev/null || {
      printf 'Install Android Emulator from SDK Manager.\n' >&2
      exit 1
    }
    mode="$1"
    avd="${2:-$(choose_avd)}"
    memory="${NOX_ANDROID_EMULATOR_MEMORY_MB:-3072}"
    cores="${NOX_ANDROID_EMULATOR_CORES:-2}"
    if [[ "$mode" == start-fast ]]; then
      memory=4096
      cores=4
    fi
    exec emulator -avd "$avd" -accel on -gpu host \
      -memory "$memory" -cores "$cores" -no-boot-anim -no-audio \
      -camera-back none -camera-front none -no-metrics
    ;;
  stop) adb emu kill ;;
  logcat) exec kitty --title Logcat -e adb logcat -v color ;;
  devices) adb devices -l ;;
  health) exec workstationctl verify kvm ;;
  install-emulator)
    sdkmanager="${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager"
    [[ -x "$sdkmanager" ]] || {
      printf 'Android sdkmanager is missing.\n' >&2
      exit 1
    }
    exec "$sdkmanager" emulator platform-tools
    ;;
  menu)
    action="$(printf '%s\n' 'Android Studio' 'VS Code' 'Start emulator' 'Stop emulator' 'Logcat' 'ADB devices' 'KVM health' | rofi -dmenu -p 'Android Dev')"
    case "$action" in
      'Android Studio') exec "$0" studio ;;
      'VS Code') exec "$0" code ;;
      'Start emulator') exec kitty --title Emulator -e "$0" start ;;
      'Stop emulator') exec "$0" stop ;;
      Logcat) exec "$0" logcat ;;
      'ADB devices') exec kitty -e /usr/bin/zsh -lic "'$0' devices; read -r -p 'Press enter'" ;;
      'KVM health') exec kitty -e /usr/bin/zsh -lic "'$0' health; read -r -p 'Press enter'" ;;
    esac
    ;;
  *)
    printf 'Usage: %s {menu|studio|code|start [AVD]|start-fast [AVD]|stop|logcat|devices|health|install-emulator}\n' "$0" >&2
    exit 2
    ;;
esac

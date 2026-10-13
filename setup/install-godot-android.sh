#!/usr/bin/env bash
set -euo pipefail

# Prepares the pacman-installed Godot editor for Android exports: installs the
# SDK packages Godot's Android export docs require, points the editor at JDK 17
# and the SDK, and installs export templates matching `godot --version`.

DRY_RUN=0
ANDROID_SDK="${ANDROID_HOME:-$HOME/Android/Sdk}"
GODOT_JAVA_HOME="${GODOT_JAVA_HOME:-/usr/lib/jvm/java-17-openjdk}"
GODOT_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/godot"
GODOT_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot"

# docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html
# (Godot 4.7), plus android-36 because Google Play requires targetSdk 36.
# cmdline-tools;latest is a precondition, not listed: sdkmanager cannot update
# its own directory and would install the update into cmdline-tools/latest-2.
SDK_PACKAGES=(
  "platform-tools"
  "build-tools;35.0.1"
  "platforms;android-35"
  "platforms;android-36"
  "cmake;3.10.2.4988404"
  "ndk;28.1.13356709"
)

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      cat <<'USAGE'
Usage: install-godot-android.sh [--dry-run]
Installs Godot's Android SDK packages into $ANDROID_HOME (accepting the Android
SDK licenses), sets the editor's Java/Android SDK paths, and installs export
templates for `godot --version`. Refuses to run while the editor is open.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

die() {
  echo "error: $*" >&2
  exit 1
}

command -v godot >/dev/null 2>&1 || die "godot is not installed (setup/pacman-packages.txt)"
[ -x "$GODOT_JAVA_HOME/bin/javac" ] || die "no JDK at $GODOT_JAVA_HOME (install jdk17-openjdk)"
SDKMANAGER="$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"
[ -x "$SDKMANAGER" ] || die "sdkmanager not found at $SDKMANAGER"
# The editor rewrites its settings file on exit, which would undo the patch.
((DRY_RUN)) || ! pgrep -x godot >/dev/null || die "close the Godot editor first"

# "4.7.2.stable.arch_linux" -> number 4.7.2, branch 4.7, status stable.
godot_version="$(godot --version)"
[[ $godot_version =~ ^(([0-9]+\.[0-9]+)(\.[0-9]+)?)\.([a-z]+[0-9]*) ]] ||
  die "cannot parse godot --version output: $godot_version"
version_number="${BASH_REMATCH[1]}"
version_branch="${BASH_REMATCH[2]}"
version_status="${BASH_REMATCH[4]}"

echo "==> Android SDK packages in $ANDROID_SDK"
if ((DRY_RUN)); then
  echo "[dry-run] sdkmanager --install ${SDK_PACKAGES[*]}"
else
  { yes || true; } | "$SDKMANAGER" --sdk_root="$ANDROID_SDK" --licenses >/dev/null
  "$SDKMANAGER" --sdk_root="$ANDROID_SDK" --install "${SDK_PACKAGES[@]}"
fi

echo "==> Godot $version_branch editor Android paths"
settings="$GODOT_CONFIG_DIR/editor_settings-$version_branch.tres"
set_editor_setting() {
  local key="$1" value="$2"
  case "$value" in
    *[\&\\\|\"]*) die "unsupported character in $key value: $value" ;;
  esac
  if grep -q "^$key = " "$settings"; then
    sed -i "s|^$key = .*|$key = \"$value\"|" "$settings"
  else
    printf '%s = "%s"\n' "$key" "$value" >>"$settings"
  fi
}
if ((DRY_RUN)); then
  echo "[dry-run] $settings: java_sdk_path=$GODOT_JAVA_HOME android_sdk_path=$ANDROID_SDK"
else
  if [ ! -f "$settings" ]; then
    # Let the editor write its own settings file once, then patch it.
    scratch="$(mktemp -d)"
    touch "$scratch/project.godot"
    godot --headless --editor --path "$scratch" --quit >/dev/null 2>&1 || true
    rm -rf "$scratch"
  fi
  [ -f "$settings" ] || die "Godot did not create $settings"
  set_editor_setting "export/android/java_sdk_path" "$GODOT_JAVA_HOME"
  set_editor_setting "export/android/android_sdk_path" "$ANDROID_SDK"
fi

template_dir="$GODOT_DATA_DIR/export_templates/$version_number.$version_status"
echo "==> Export templates in $template_dir"
if [ -f "$template_dir/android_source.zip" ]; then
  echo "already installed"
else
  tag="$version_number-$version_status"
  tpz="Godot_v${tag}_export_templates.tpz"
  base="https://github.com/godotengine/godot/releases/download/$tag"
  if ((DRY_RUN)); then
    echo "[dry-run] download and verify $base/$tpz"
  else
    [ ! -e "$template_dir" ] || die "$template_dir is incomplete; remove it and re-run"
    # Stage on the same filesystem so the final install is one atomic rename.
    mkdir -p "$GODOT_DATA_DIR/export_templates"
    work="$(mktemp -d "$GODOT_DATA_DIR/export_templates/.download.XXXXXX")"
    trap 'rm -rf "$work"' EXIT
    curl -fL --retry 3 -o "$work/$tpz" "$base/$tpz"
    curl -fsSL --retry 3 -o "$work/SHA512-SUMS.txt" "$base/SHA512-SUMS.txt"
    expected="$(awk -v f="$tpz" '$2 == f { print $1 }' "$work/SHA512-SUMS.txt")"
    [ -n "$expected" ] || die "$tpz is not listed in SHA512-SUMS.txt"
    echo "$expected  $work/$tpz" | sha512sum -c --quiet - || die "checksum mismatch for $tpz"
    unzip -q "$work/$tpz" -d "$work/extract"
    [ "$(cat "$work/extract/templates/version.txt")" = "$version_number.$version_status" ] ||
      die "template version does not match $version_number.$version_status"
    mv "$work/extract/templates" "$template_dir"
  fi
fi

echo "Godot Android setup complete (Godot $godot_version)."

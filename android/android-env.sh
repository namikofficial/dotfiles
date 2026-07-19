# shellcheck shell=sh
# Shared Android SDK environment for shells, IDE launchers, and systemd users.
ANDROID_HOME=${ANDROID_HOME:-$HOME/Android/Sdk}
ANDROID_SDK_ROOT=$ANDROID_HOME
JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/default}

# Prefer the newest installed build-tools directory instead of pinning the
# shell to one SDK release. Keep the standard locations first when present.
ANDROID_BUILD_TOOLS=""
if [ -d "$ANDROID_HOME/build-tools" ]; then
  ANDROID_BUILD_TOOLS=$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -n 1)
fi

ANDROID_PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin"
if [ -n "$ANDROID_BUILD_TOOLS" ]; then
  ANDROID_PATH="$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS:$ANDROID_PATH"
fi

PATH=$ANDROID_PATH:$PATH
export ANDROID_HOME ANDROID_SDK_ROOT JAVA_HOME PATH
unset ANDROID_BUILD_TOOLS ANDROID_PATH

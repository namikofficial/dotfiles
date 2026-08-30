# shellcheck shell=sh
# Shared Android SDK environment for shells, IDE launchers, and systemd users.
ANDROID_HOME=${ANDROID_HOME:-$HOME/Android/Sdk}
ANDROID_SDK_ROOT=$ANDROID_HOME

# Full JDK for Android/Gradle builds. Use the JetBrains Runtime bundled with
# Android Studio (has javac/jar/javadoc). The distro default is JRE-only and
# lacks javac, which breaks AGP toolchain resolution.
if [ -x /home/namik/.local/opt/android-studio/jbr/bin/javac ]; then
  JAVA_HOME=/home/namik/.local/opt/android-studio/jbr
else
  JAVA_HOME=/usr/lib/jvm/default
fi

# Android upload/release keystores (personal developer account, not an org).
# Each app ships its own keystore + git-ignored key.properties; these vars
# mirror those values so build tooling and CI can reference them consistently.
NOXCRM_KEYSTORE=${NOXCRM_KEYSTORE:-$HOME/Documents/code/noxorigin/workspace/mobile/noxcrm-release.keystore}
NOXCRM_KEY_ALIAS=${NOXCRM_KEY_ALIAS:-noxcrm}
NOXBILLINGS_KEYSTORE=${NOXBILLINGS_KEYSTORE:-$HOME/Documents/code/noxorigin/nox-billings/apps/mobile/android/app/release.keystore}
NOXBILLINGS_KEY_ALIAS=${NOXBILLINGS_KEY_ALIAS:-release}
NOXTICKETS_KEYSTORE=${NOXTICKETS_KEYSTORE:-$HOME/Documents/code/noxorigin/nox-tickets/apps/mobile/noxtickets-release.keystore}
NOXTICKETS_KEY_ALIAS=${NOXTICKETS_KEY_ALIAS:-noxtickets}

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
export NOXCRM_KEYSTORE NOXCRM_KEY_ALIAS NOXBILLINGS_KEYSTORE NOXBILLINGS_KEY_ALIAS NOXTICKETS_KEYSTORE NOXTICKETS_KEY_ALIAS
unset ANDROID_BUILD_TOOLS ANDROID_PATH

# shellcheck shell=sh
# Shared Android SDK environment for shells, IDE launchers, and systemd users.
ANDROID_HOME=${ANDROID_HOME:-$HOME/Android/Sdk}
ANDROID_SDK_ROOT=$ANDROID_HOME
JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/default}
PATH=$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH
export ANDROID_HOME ANDROID_SDK_ROOT JAVA_HOME PATH

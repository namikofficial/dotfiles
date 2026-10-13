#!/bin/sh
# Unreal Engine's Android Turnkey check (UE 5.8 AndroidPlatform.Automation.cs)
# hardcodes ~/android-studio/bin/studio.sh, but current Android Studio builds
# ship only bin/studio. bootstrap.sh links this wrapper into that path.
exec "$HOME/.local/opt/android-studio/bin/studio" "$@"

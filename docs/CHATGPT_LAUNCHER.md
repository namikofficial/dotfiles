# ChatGPT desktop activation

`chatgpt-launcher.sh` makes ordinary desktop activation idempotent: if a
Hyprland client with class `chatgpt` exists, it focuses that client. If none
exists, it starts the native Wayland binary.

Arguments such as `codex://connector/oauth_callback` are passed to the real
binary when no ChatGPT process owns the profile. When an existing visible
instance is found, the wrapper focuses it without replaying the callback so a
second profile process cannot be created.

Before launching, the wrapper also checks for a ChatGPT main process using the
Codex profile. If a main process has no Hyprland window, it is treated as a
failed startup and replaced under an activation lock. If a visible window
exists, it is focused; callbacks are acknowledged without starting another
profile process.

Install and verify with:

```sh
./setup/bootstrap.sh
./hypr/scripts/test-chatgpt-launcher.sh
```

# Arch Zsh Dotfiles

This repo now contains the shell config that runs on your minimal Arch + Hyperland machine; everything is in `~/Documents/code/dotfiles` so you can self-host the zsh, aliases, and cheat sheet you rely on.

## What’s inside

- `zshrc` — the main Zsh startup file with completion tuning, history repair, Starship, plugin hooks, and environment helpers wired to `$DOTFILES_HOME`/`$SCRIPTS_HOME`.
- `aliases.zsh` + `aliases.local.zsh` — the shared alias library and a tracked placeholder for host-specific tweaks.
- `SHELL_CHEATSHEET.md` — a quick reference for the commands and helpers defined above.

## Setup steps

1. **Link the managed configs**

   ```sh
   ln -sf "$HOME/Documents/code/dotfiles/zshrc" ~/.zshrc
   ln -sf "$HOME/Documents/code/dotfiles/SHELL_CHEATSHEET.md" ~/SHELL_CHEATSHEET.md
   ```

2. **Install the dependencies referenced in `zshrc`**

   - `zsh`, `starship`, `fzf`, `ripgrep`, `fd`, `exa`/`eza`, `bat`/`batcat`, `direnv`, `atuin`, `zoxide`
   - `jq`, `docker`, `kubectl`, `gh`, `pay-respects`, and any other CLI tools you plan to use (they are referenced by the aliases but fail gracefully if missing)
   - `wl-clipboard` or `xclip` for the Wayland clipboard helpers

3. **Install the shared scripts repository**

   Clone (or keep) `~/Documents/code/scripts` and expose its `bin/` directory on your `PATH` so the alias shortcuts work:

   ```sh
   ln -sf "$HOME/Documents/code/scripts/bin/"* ~/.local/bin/
   ```

4. **Per-machine overrides**

   Add host-specific tweaks to `aliases.local.zsh`; it’s tracked so you can keep machine-specific commands separate from the shared defaults.

5. **Reload the shell**

   Run `exec zsh` or restart your terminal so the new config and aliases take effect.

## Hypr + Rice

- The `hypr/` folder mirrors your live `~/.config/hypr`, `~/.config/waybar`, and `~/.config/rofi` setups; it holds `hyprland.conf`, `scripts/`, waybar/rofi configs, and supporting `.conf` files so the rice stays versioned with the dotfiles repo.
- To keep the actual config pointing at the repo, recreate the symlinks:

  ```sh
  ln -sf "$HOME/Documents/code/dotfiles/hypr/hyprland.conf" ~/.config/hypr/hyprland.conf
  ln -sf "$HOME/Documents/code/dotfiles/hypr/scripts" ~/.config/hypr/scripts
  ln -sf "$HOME/Documents/code/dotfiles/hypr/waybar" ~/.config/waybar
  ln -sf "$HOME/Documents/code/dotfiles/hypr/rofi" ~/.config/rofi
  ```

- Update any other Wayland helpers (wallpaper scripts, lock screen, etc.) by managing them inside this `hypr/` subtree and pointing their live path at the repo version.

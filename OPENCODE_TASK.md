# OpenCode Task: Repair AI Providers and Finish the NoxFlow Desktop Shell

You are working in `/home/namik/Documents/code/dotfiles`, a Hyprland + Quickshell desktop shell called NoxFlow.

## Goal

Make OpenCode reliably discover and use the user's existing OpenAI OAuth and Google/Gemini credentials, then deliver one cohesive visual overhaul of the Super+Space launcher, top bar, and Dynamic Island.

Preserve unrelated user changes already present in the worktree. Do not reset, checkout, clean, or overwrite unrelated files.

## Non-negotiable safety rules

- Never print, copy, commit, or place API keys, OAuth refresh tokens, access tokens, or account IDs in the repository.
- Inspect credentials only through redacted commands such as `opencode auth list`.
- ChatGPT Plus is not OpenAI API credit. If the OpenAI OAuth path is unsupported or expired, report the exact limitation and keep Gemini/local/OpenCode fallbacks working; do not invent an API key.
- Do not make a remote provider a startup dependency for the shell.
- Keep the existing NoxFlow theme-token system and Quickshell architecture; do not replace it with Waybar, Rofi, or a new shell framework.

## Phase 1 — Diagnose and repair OpenCode

Inspect:

- `/home/namik/.config/opencode/opencode.jsonc`
- `/home/namik/.local/share/opencode/auth.json` through redacted tooling only
- `configs/opencode/opencode.local-llamacpp.json`
- OpenCode version, `opencode auth list`, and model discovery

Repair the configuration so that:

- OpenAI, Google/Gemini, OpenCode Zen, and local fallback providers are not accidentally hidden by an overly narrow `enabled_providers` list.
- Provider IDs match the credentials stored by OpenCode.
- OAuth and API-key providers remain separate and explicit.
- Model aliases are readable and selectable, with a sensible primary model and fallback order.
- Existing MCP servers, permissions, instructions, and local model behavior are preserved.
- The repository template does not contain secrets or machine-specific tokens.

Validate with `opencode auth list`, provider/model listing, config/schema validation, and one minimal non-destructive request per available provider. If an external provider fails, record whether the cause is missing credential, expired OAuth, unavailable model, quota, or billing.

## Phase 2 — Redesign Super+Space as a useful command center

Primary file: `shell/noxflow/surfaces/launcher/Launcher.qml`.

Keep the existing modes and behavior: Apps, Windows, Commands, Calculator, Ask AI, Clipboard; fuzzy search; arrow-key navigation; Enter; Tab mode switching; Escape; click-outside dismissal; and the Super+Space binding.

Implement a full command-center layout:

- A compact centered panel with clear visual hierarchy instead of a heavy opaque full-screen background.
- Restrained scrim/dimming that keeps the current desktop recognizable.
- Strong search field, mode navigation, selected-row states, useful empty states, loading states, and actionable errors.
- Consistent Material/NoxFlow icons and theme tokens; remove emoji as the primary icon system.
- Responsive sizing for small and large monitors.
- Reduced-motion support.
- AI configuration that can use the configured provider path while retaining the local endpoint as a fallback.
- Preserve accessibility names, keyboard focus, and action semantics.

Do not turn the launcher into a decorative dashboard. It must remain fast and useful for launching, switching, calculating, clipboard recall, system actions, and asking AI.

## Phase 3 — Rework the top bar

Primary file: `shell/noxflow/Bar.qml`.

Make it read as a calm, intentional top bar rather than a telemetry dump:

- Left: compact workspaces plus active application/project.
- Center: clock with calendar action.
- Right: network, Bluetooth, audio, battery, notification, and health cluster.
- Keep CPU, RAM, weather, media, Git, task, update, and project detail out of the permanent bar unless actively relevant; expose details through existing panels, tooltips, or contextual chips.
- Use consistent iconography, spacing, typography, contrast, hover/pressed states, truncation, and accessible labels.
- Preserve all existing click actions and MorphRegistry geometry (`clock`, `media`, `notification`, and `status`).
- Preserve multi-monitor behavior, exclusive zone, panel height, and theme profiles.
- Fix all QML warnings encountered while testing, including undefined references and invalid property bindings.

## Phase 4 — Improve Dynamic Island

Primary file: `shell/noxflow/NoxIsland.qml` and existing activity files under `shell/noxflow/surfaces/island/`.

Keep the island hidden while idle and make it a contextual live-activity surface for:

- Volume and brightness
- Media
- Notifications
- Timers
- Microphone and recording
- File transfer/progress
- AI completion
- Build/test result
- Battery and network warnings

Use priority-based event selection, debounce duplicate provider events, and avoid interrupting important activity with low-value updates. Animate compact-pill to expanded-card transitions smoothly, show meaningful progress/content, respect reduced motion, and hide after the correct timeout.

## Verification and acceptance criteria

Run the relevant repository checks and document results. At minimum verify:

1. OpenCode config parses and does not expose secrets.
2. Intended OpenAI/Gemini credentials are discoverable without leaking token values.
3. OpenAI, Gemini, Zen, and local fallback model paths either work or report an exact external blocker.
4. Super+Space opens/closes reliably.
5. All launcher modes, keyboard navigation, AI loading/error states, and reduced-motion behavior work.
6. The bar renders on every configured monitor without QML warnings.
7. Bar actions, tooltips, accessibility labels, and MorphRegistry geometry still work.
8. Dynamic Island debounces duplicate events, handles supported activity types, and hides correctly.
9. Existing smoke tests and relevant QML/config checks pass.
10. `git diff --check` passes and unrelated pre-existing modifications remain untouched.

At the end, summarize changed files, provider results, tests run, and any external authentication or billing action still required from the user.

## Reference material

Use these as inspiration, not as dependencies or architecture to copy:

- `REFERENCES.md`
- `PLAN.md`
- `theplan.md`
- https://github.com/caelestia-dots/shell
- https://github.com/enhaoswen/Tide-island
- https://github.com/Ronin-CK/QuickSnip
- https://github.com/end-4/dots-hyprland
- https://github.com/ilyamiro/nixos-configuration
- https://github.com/binnewbs/arch-hyprland
- https://github.com/Cybersnake223/Hypr
- https://www.reddit.com/r/hyprland/comments/1ulhnr3/hyprland_i_made_a_dynamic_island_on_hyprland/

Keep NoxFlow's identity, theme tokens, IPC, models, and existing shell surfaces intact while borrowing interaction ideas such as contextual islands, morphing surfaces, compact bars, and keyboard-first command centers.

# NoxFlow Atelier visual QA

Live captures from the laptop display on 2026-11-19. Every image is 1920×1080 at monitor scale 1.0; the 1.5-scale trial was restored before this set was captured.

| Surface | Capture | State and notes |
| --- | --- | --- |
| NoxRail | [noxrail.png](noxrail.png) | Idle shell with two workspaces and current system indicators. |
| Nox Command | [nox-command.png](nox-command.png) | Unified app and window search with a live preview for the selected result. The Workbench project registry returned an empty list during capture. |
| Nox Atlas | [atlas.png](atlas.png), [atlas-focus-history.png](atlas-focus-history.png) | Live previews across two workspaces and a single-workspace full-width state; the latter shows selectable recent-window chips. |
| Dashboard | [dashboard.png](dashboard.png) | Weather, calendar, system status, and quick actions with scrolling visible; backdrop dim is restrained and the desktop stays crisp. |
| Media | [media-empty.png](media-empty.png), [media-populated.png](media-populated.png) | Empty state plus a populated view from a temporary synthetic MPRIS player; next, seek, and play/pause reached the player. |
| Nox Studio | [settings.png](settings.png) | Live theme profile chooser at the default display scale. |
| Notifications | [notifications.png](notifications.png) | Unlocked, empty notification state after correcting session discovery. |
| Nox Capture | [capture.png](capture.png) | First-use region-selection hint. OCR now defaults to the installed English data, captures through argument arrays, and keeps recognized text out of notification content. |

These full-display captures retain the real wallpaper and windows behind each surface. They are local QA artifacts, not sanitized presentation images.

## Not captured

- Hyprlock needs a real lock and authentication interaction; it is not launched by the automated capture sequence.
- No real media player or project context was active during QA. The populated media view used a temporary synthetic MPRIS player; the canonical project registry was empty.
- Camera and screen-capture indicators were inactive during capture.

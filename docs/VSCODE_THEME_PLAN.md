# VS Code theme (NoxFlow Dynamic): fix, improve, complete

Date: 2026-10-11. Branch: `dev`. Status: **P0-P6 implemented, P7 partly observed
(see section 9).** Sections 1-8 are the original plan; where implementation
differs, section 9 is authoritative.

## 1. Outcome

NoxFlow Dynamic should be a VS Code theme you want to look at all day, on any
wallpaper the pipeline accepts. Concretely:

- Code has real, distinct syntax colors, not a near-monochrome fallback.
- Sidebar, editor, panel, tabs, title bar and status bar read as separate
  regions. Borders and selections are visible.
- The accent is used sparingly (focus, active item, primary action), not as a
  full-width slab.
- Quality is guaranteed by the generator (contrast floors, tests) rather than by
  whatever the wallpaper happens to produce.
- The same coverage as the rest of the desktop: terminal, git/diff, debug,
  tests, notifications, chat/agent panels, markdown.

## 2. Evidence (what is wrong today)

Sources: `hypr/scripts/theme-sync.sh:648-741` (generator),
`~/.vscode/extensions/noxflow.dynamic-theme-0.0.1/themes/NoxFlow Dynamic-color-theme.json`
(installed output), `~/.cache/hypr/theme-palette.json` (live palette),
`code/vscode-user-settings.json`.

The attached screenshot is blurred and dimmed by the capture overlay, so it
shows only the overall impression: a uniformly dark UI, faint text, a flat teal
status bar and a teal selected row. The orange window frame is the Hyprland
border, not VS Code. The findings below come from the code and palette, not
from reading the pixels. A clean screenshot is a prerequisite for packet P0.

| # | Finding | Measured |
|---|---|---|
| F1 | **No syntax rules.** The generated theme has 83 `colors` keys and `tokenColors: 0`, `semanticTokenColors: 0`. Code falls back to VS Code's minimal built-in dark rules. The palette already has `syntax*` roles for OpenCode (`theme-sync.sh:409-413`) and hue-correct ANSI colors; VS Code uses none of them. | 0 rules |
| F2 | **Surface ramp is too flat.** canvas `#030402`, base `#070b07`, surface1 `#0f130e`, surface2 `#191e18`. Adjacent steps are barely distinguishable, so sidebar, editor, tabs and panels merge into one black mass. | canvas to base 1.04:1, base to surface2 1.17:1 |
| F3 | **Borders are effectively invisible.** `outline` `#0d140c`, `outlineSubtle` `#070b06`, `outlineStrong` `#152013`. Panel, tab and input borders use them. | outline 1.10:1, subtle 1.00:1, strong 1.18:1 |
| F4 | **Accent overuse.** `statusBar.background` is the full accent `#0097b5` with `#242424` text (4.5:1, passes but is heavy). `list.activeSelectionBackground` is a dark surface, so the teal row in the screenshot is another accent fill. Result: one loud slab plus a dead-flat UI. | |
| F5 | **Large coverage gaps.** Missing groups include: `sideBar.border`, `activityBar.border`/`inactiveForeground`, `titleBar.border`, `editor.lineHighlight*`, bracket pair and indent guide colors, whitespace, selection variants, diff editor (`diffEditor.*`), merge, `scm`/graph, breadcrumbs, notifications, menus, quick input, peek view, badges, progress bar, `terminal.foreground/background/cursor/selection`, testing, debug toolbar, symbol icons, `textCodeBlock`, `list.inactiveSelection*`, chat/agent surfaces. Anything unset falls back to base vs-dark colors that clash with the palette. | 83 keys |
| F6 | **Generator is fragile.** The whole theme is a shell heredoc with string interpolation. Alpha is appended as `"${accent}33"`, which breaks if a value is not 6-digit hex. There is no JSON validation, no contrast check and no test. `tests/theme/` covers `nox-theme.py` and tokens only. | no tests |
| F7 | **User settings do nothing for the look.** `code/vscode-user-settings.json` has only `workbench.colorTheme`. Unset: semantic highlighting, bracket colorization, icon theme, minimap/breadcrumbs, cursor, font ligatures, `workbench.colorCustomizations` fallbacks. | |
| F8 | **Docs are inconsistent.** `docs/NOXFLOW_TODO.md:34` says a VS Code palette merge into `workbench.colorCustomizations` was added; `docs/WALLPAPER_THEMING.md:117` says settings are never mutated. The second matches the code. | |

## 3. Design decisions

1. **Keep it dynamic, make it safe.** The theme stays wallpaper-driven, but the
   generator enforces floors so a bad wallpaper cannot produce a bad editor.
2. **Move generation out of the heredoc** into `hypr/scripts/vscode-theme.py`.
   It is called by `theme-sync.sh`, reads `theme-palette.json`, writes the
   cache file and the extension, and validates before writing. Same pattern as
   `nox-theme.py`. The package files remain generated and isolated.
3. **Roles, not raw palette keys.** Define a small VS Code role table (surface
   ramp, border, text tiers, accent, state colors, 8 syntax roles) derived from
   the palette, with contrast-adjustment where a derived value misses its floor.
4. **Syntax colors come from the hue-correct terminal ramp**
   (`colors.terminal.*`), not from UI accents, which are not hue-safe on warm
   wallpapers (see the comment at `theme-sync.sh:309-311`).
5. **Do not rewrite `settings.json` from the pipeline.** Static look settings go
   in `code/vscode-user-settings.json` by a normal reviewed change.
6. **Contrast floors** (checked in tests against live and fixture palettes):

| Pair | Floor |
|---|---|
| Editor text, syntax tokens (except comments) on editor bg | 4.5:1 |
| Comments on editor bg | 3.5:1 (still readable, clearly de-emphasized) |
| Sidebar/tab/status text on its bg | 4.5:1 |
| Adjacent surface step (canvas, base, panel, editor, float) | 1.12:1 minimum, with visible separator via border |
| Region border on adjacent surface | 1.6:1 |
| Focus ring, active indicator, input border on bg | 3:1 |
| Selection vs editor bg | 1.3:1 with text staying at 4.5:1 |

## 4. Work packets

Ordered. Each packet is independently reviewable; commit per packet. P1 blocks
P2-P5. P2-P5 can run in parallel after P1 once the role table is agreed.

### P0 - Baseline and fixtures (scout + verifier)

- Take a clean screenshot of the current theme (grim of the VS Code window, not
  the overlay capture) with the fixture workspace below. Keep it in `/tmp`, not
  the repo.
- Add `tests/theme/fixtures/vscode/` with small sample files: TypeScript, Rust,
  Python, QML, shell, JSON, Markdown, a `.diff`, plus a git repo state that
  yields modified/added/deleted/untracked/conflict.
- Freeze 3 palette JSON fixtures for tests: warm dark (current), cool dark, light.
- Acceptance: baseline screenshot and fixtures exist; the current theme's
  F1-F4 numbers are reproduced by a script, not by hand.

### P1 - Generator and role table (planner, then implementer)

- Create `hypr/scripts/vscode-theme.py` with: palette loader (nested and legacy
  flat keys, never emit `null`), hex/alpha helper that validates input, contrast
  helper, role table, contrast-adjust step, JSON writer with `$schema`-valid
  output, extension `package.json` writer.
- `theme-sync.sh` replaces the heredoc (lines ~648-756) with one call. Keep the
  same install path and `NoxFlow Dynamic` label so the one-time selection still
  holds. Link or install the script like `nox-theme.py` (check
  `setup/normalize-links.sh`).
- Fail closed: if validation fails, keep the last good theme file and exit
  non-zero with a message, never write a partial theme.
- Acceptance: running the generator on the live palette reproduces today's
  colors where no change was intended (diff of the colors block is explained);
  `python3 -I hypr/scripts/vscode-theme.py <palette> <out> --validate` exits 0.

### P2 - Syntax: tokenColors + semanticTokenColors (implementer)

- Map 8 roles: keyword, function/method, string, number/constant, type/class,
  variable/parameter, operator/punctuation, comment. Add tag/attribute,
  decorator, escape/regex, link, invalid, and markdown heading/code/emphasis.
- Add `semanticHighlighting: true` in the theme and `semanticTokenColors` for
  language-server tokens (rust-analyzer, TS, Python, QML are the installed
  languages).
- Distinguish at least keyword vs type vs function vs string vs constant by
  hue, not only by lightness. Italic for comments and a few keywords only if
  the user wants it (open question Q2).
- Acceptance: every token color meets its floor on all 3 palette fixtures;
  a rendered screenshot of the fixture files shows 6+ distinct hues in the
  TS and Rust samples.

### P3 - Surfaces, borders, selection, accent discipline (implementer)

- Rebuild the surface ramp inside the role table so steps meet the 1.12:1
  floor, and map regions deliberately: activity bar (deepest), sidebar, editor
  (reference), tab strip, panel, floating widgets (highest).
- Real borders on sideBar, activityBar, titleBar, panel, editorGroup, tabs,
  inputs (1.6:1 floor; focus 3:1).
- Status bar: neutral surface by default with accent text/indicator; accent fill
  only for debugging/no-folder-remote states. (Q1 below if the user prefers the
  filled accent.)
- Selections: use a translucent accent over the surface with defined
  `list.activeSelection*`, `list.inactiveSelection*`, `list.hover*`,
  `list.focus*`, `editor.selection*`, `editor.lineHighlight*`, find/match,
  word highlight.
- Acceptance: the numeric table in section 3 passes on all fixtures; screenshot
  shows sidebar, editor and panel clearly separable and exactly one accent
  surface in the default view.

### P4 - Coverage completion (implementer, split by area if needed)

Add the groups listed in F5, each with state coverage (hover, active, disabled,
focus): git/SCM and graph, diff editor and inline diff, merge conflicts,
breadcrumbs, notifications, menus/quick input/command palette, peek view,
badges and progress, terminal (fg/bg/cursor/selection + ANSI from the hue-correct
ramp), testing, debug, symbol icons, chat/agent panels, scrollbars, minimap
slider, bracket pair and indent guides, whitespace, inlay hints, ErrorLens
decorations (installed), SOPS and YAML markers.
- Acceptance: a checker that loads a VS Code color-key list (from the VS Code
  docs reference or an extracted `colors` registry) and lists unset keys in the
  groups above; the unresolved list is empty or each entry is justified in the
  plan doc. No key resolves to `null` or an invalid hex.

### P5 - User settings and editor chrome (implementer)

In `code/vscode-user-settings.json`, only values the user agrees to (Q2-Q4):
`editor.semanticHighlighting.enabled`, `editor.bracketPairColorization.enabled`,
`editor.guides.bracketPairs`, `workbench.iconTheme`, `editor.minimap.*`,
`editor.fontFamily` (JetBrainsMono Nerd Font is already used in the terminal),
`editor.fontLigatures`, `editor.cursorBlinking`, `window.titleBarStyle` and
`workbench.activityBar.location`. Keep existing SOPS/YAML keys untouched.
- Acceptance: file stays valid JSON(C); `./setup/check-dotfiles.sh --all`
  passes; no key duplicated.

### P6 - Tests, docs, wiring (verifier + reviewer)

- `tests/theme/test_vscode_theme.py`: JSON validity, no `null`, hex validity,
  contrast floors on the 3 fixtures, tokenColors non-empty, required key set
  present, idempotence (same palette gives identical output).
- Update `docs/WALLPAPER_THEMING.md` for the new generator and fix the
  contradiction in `docs/NOXFLOW_TODO.md:34`.
- Add the check to the repo's check entry points if `setup/check-dotfiles.sh`
  enumerates theme tests.
- Acceptance: `python3 -I -m unittest discover -s tests/theme` passes;
  `./setup/check-dotfiles.sh --all` and `./setup/check-shell.sh --all` pass.

### P7 - Live verification (verifier, then user)

- Run `theme-sync.sh` with the current wallpaper, reload VS Code, open the
  fixture workspace, capture screenshots for: editor with code, source control
  with changes, diff, terminal, command palette, settings, chat/agent panel.
- Repeat with 2 other wallpapers (a cool dark one and a light one) via
  `set-wallpaper.sh`.
- Acceptance: user signs off on the screenshots. Unobserved states remain
  explicitly listed as unverified.

## 5. Agent assignment

| Packet | Agent | Notes |
|---|---|---|
| P0 | `scout` + `verifier` | read-only plus capture and fixtures |
| P1 | `planner` for the role table, then main agent implements | contract for everything after |
| P2, P3, P4 | main agent or parallel implementers on separate sections of the role table | agree on role names first to avoid conflicts |
| P5 | main agent | needs the user's answers |
| P6 | `verifier` | cheapest authoritative checks |
| all | `reviewer` after P1, P3 and P6 | contract and regression review |

Rules for every agent: read `AGENTS.md` and `setup/AGENTS.md` before editing;
stage exact paths; do not touch `settings.json` from the pipeline; do not commit
or push unless the user asks; `git diff --check` on changed text.

## 6. Risks

- Contrast adjustment can shift hues on unusual wallpapers. Mitigate with a
  hue-preserving lightness adjustment and fixture coverage for light and cool
  palettes.
- A light-mode palette needs its own surface ramp direction. If it is too much,
  make light mode an explicit non-goal and say so in the generator.
- VS Code caches theme files; a reload may be needed after regeneration.
- Extensions with their own colors (ErrorLens, SOPS, Qt) may ignore the theme.
- Visual quality is subjective; numeric floors prevent bad, not guarantee good.
  P7 sign-off is the real gate.

## 7. Decisions needed from the user

- **Q1:** Status bar: neutral with an accent indicator (recommended), or keep the
  filled accent?
- **Q2:** Italic comments and keywords, yes or no?
- **Q3:** Keep a single dynamic theme (recommended), or also ship a hand-tuned
  static "NoxFlow Night" as a fallback and for stable reference screenshots?
- **Q4:** Which icon theme (Material Icon Theme, Catppuccin icons, or the
  built-in)? Installing one adds an extension.
- **Q5:** Is light mode in scope?

## 8. Not verified yet

- Anything about how the current theme actually looks beyond the blurred
  screenshot. The numbers above are computed from the generated JSON and the
  live palette only.
- No tests, generator changes or VS Code runs have been done.

## 9. Decisions and implementation status

Decisions taken: status bar neutral with an accent indicator (Q1); italic
comments, upright keywords (Q2); dynamic theme only (Q3); built-in icon theme
(Q4); light mode in scope (Q5).

| Packet | Status | Where |
|---|---|---|
| P0 fixtures | Done | `tests/theme/fixtures/palettes/*.json` (warm/cool/neon dark, light, light-vibrant, legacy-flat), `tests/theme/fixtures/vscode/workspace/`, `tests/theme/render-vscode.sh` |
| P1 generator | Done | `hypr/scripts/vscode-theme.py`; `theme-sync.sh` calls it, fail-closed, no-rewrite when unchanged |
| P2 syntax | Done | 28 TextMate rules + 27 semantic token rules |
| P3 surfaces/accent | Done | own surface ramp per mode, neutral status bar, accent reserved for focus/primary actions |
| P4 coverage | Done | 626 color keys; all emitted keys exist in the installed VS Code 1.140 bundle (test skips if VS Code is absent) |
| P5 settings | Minimal | `editor.semanticHighlighting.enabled`, `editor.guides.bracketPairs` only; fonts/icons untouched |
| P6 tests/docs | Done | `tests/theme/test_vscode_theme.py`, light/dark cases in `test_nox_theme.py`, `docs/WALLPAPER_THEMING.md` |
| P7 live render | Partly observed | see below |

Light-wallpaper palette generation (`nox-theme.py`, light mode only) was broken
independently of VS Code: the surface ladder clamped flat at L 0.98 (all six
surfaces near `#fcf5ff`), the dark-mode +220 degree hue nudge turned cream and
sky wallpapers lilac, outlines were lighter than the canvas, text was `#000000`,
accent contrast stopped at 3:1, and terminal background differed from the
canvas. Fixed with a dedicated light ladder, wallpaper-derived hue, darker
borders, softer text and 4.5:1 accents. Dark palettes are byte-identical to
before (checked on 4 real wallpapers and 6 solid-color wallpapers against
`HEAD`, and pinned by a golden test).

Floors as implemented (differ slightly from section 3):

| Pair | Floor |
|---|---|
| Editor text | 7:1 |
| Syntax tokens, foregrounds on chrome, terminal colors, git decorations | 4.5:1 |
| Comments | 3.5:1 (aims for 4.0) |
| Selection text, composited in encoded sRGB like VS Code | 4.5:1 |
| Surface steps vs editor (side bar, activity bar, status bar, tab strip) | OKLCH lightness 0.025-0.040 |
| Region border vs editor | 1.3:1 validated (1.45:1 targeted) |
| Input border vs input fill | 1.8:1 validated (2.0:1 targeted) |
| Focus border | 3:1 |
| Syntax hues | at least 25 degrees apart; hue preserved, lightness fitted |

Observed in a real VS Code 1.140 window (isolated profile, `render-vscode.sh`):
editor, source control, diff, command palette, terminal and settings on the live
dark palette; editor, source control, diff and terminal on the light-vibrant
fixture. Rendered pixels for editor, side bar, activity bar and status bar
equal the generated colors. Not rendered: Problems, debug, test explorer, merge
editor, notebooks, chat/agent panels, extension-provided views, and language
server semantic tokens other than TypeScript (the isolated profile has no
rust-analyzer, Python or QML extensions).

An independent review after implementation found, and this change then fixed:
light-mode `ansiWhite` at 1.29:1, hover and slash-command text below 4.5:1 (the
validator now discovers every sibling foreground/background pair, 86 per theme,
plus hover states and all 16 ANSI slots), red/orange syntax hues that could
collide (red spread cut to 5 degrees), half-written output on I/O failure
(files are staged together; cache and extension are independent), tests that
read the developer's real `~/.config/noxflow` policy, and a render helper that
could target any VS Code window (it now selects its own by a unique title).

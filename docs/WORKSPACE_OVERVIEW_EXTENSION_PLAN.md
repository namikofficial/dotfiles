# Workspace Overview Extension Plan

## Execution Tracker

Status legend:
- `[ ]` not started
- `[-]` in progress
- `[x]` done

Current status:
- `[x]` Baseline discovery and shortcut inventory
- `[x]` Feature scope definition (rename, shortcuts, dynamic workspaces, favorites/recents, move/send)
- `[x]` Shell compact-list design scope added
- `[x]` Implementation in scripts/config (Sessions 1-3 code landed)
- `[x]` Validation + regression pass (automated/script-level checks complete)
- `[x]` Docs sync after implementation

Session 1 progress update:
- `[x]` `workspace-name-store.sh` implemented
- `[x]` `workspace-overview.sh` switched to dynamic workspace detection
- `[x]` rename/clear workspace label actions integrated into overview UI
- `[x]` optional live interactive keyflow verification handled by final user validation pass

## Next 3 Working Sessions

Session 1 (Workspace core):
1. [x] Implement dynamic workspace discovery.
2. [x] Add workspace naming persistence helper.
3. [x] Integrate rename/clear actions in overview.

Session 2 (Power features):
1. [x] Add favorites + recents metadata helper.
2. [x] Add window move/send actions from overview.
3. [x] Add overview shortcuts panel as second menu.

Session 3 (Shell UX + hardening):
1. [x] Update `zshrc` completion strategy for large match sets.
2. [x] Update auto-`ls` truncation output to `... and N more`.
3. [x] Run fallback/regression checklist and update docs.

## Scope

Create a feature roadmap for extending the current workspace overview with:

- Workspace renaming
- Shortcut visibility inside overview
- Better navigation and actions
- Dynamic workspace detection
- Improved reliability and keyboard-first workflow
- Favorites + recent-workspace memory
- Window move/send actions directly from overview
- zsh completion noise reduction for huge match sets
- auto-`ls` cap on `cd` with explicit `... and N more` summary

This document started as a planning artifact and now also tracks implementation progress.

## Current Baseline (As-Is)

### Current overview entrypoints

- `hypr/scripts/workspace-overview.sh`
  - Rofi-based workspace/window picker.
  - Lists workspaces and window counts.
  - Lists windows under each workspace.
  - Selecting workspace jumps to it.
  - Selecting window jumps and focuses window.

- `hypr/scripts/workspace-overview-toggle.sh`
  - Tries `hyprexpo:expo toggle` first.
  - Falls back to `workspace-overview.sh`.

### Current capabilities already present

- Workspace + window inventory from `hyprctl -j clients`.
- Rofi menu with custom theme.
- Direct jump/focus behavior.

### Previous gaps (now addressed by implementation)

- Workspace label persistence was missing (now added).
- Rename UI/action was missing in Rofi flow (now added).
- In-overview shortcut cheat sheet was missing (now added).
- Multi-action row model was missing (now added for favorites + window actions).
- Workspace range was static `1..10` (now dynamic).

### Related shell behavior baseline (requested add-on)

From current `zshrc`:
- Auto-`ls` after directory changes is already enabled via `chpwd` hook.
- Auto-`ls` cap now defaults to `AUTO_LS_MAX_ENTRIES=30`.
- Completion behavior is tuned with `LISTMAX=0` and compact completion list sizing.

---

## Current Shortcuts That Open Workspace Overview Right Now

### A) Direct keyboard shortcuts

From `hypr/hyprland.conf`:

- `Super + Y` -> `workspace-overview.sh` (primary)
- `Super + Shift + Space` -> `workspace-overview.sh`
- `Super + W` -> `workspace-overview.sh`
- `Super + Shift + Tab` -> `workspace-overview.sh`
- `Super + Tab` -> `hyprexpo:expo toggle` (Mission Control overview)

### B) Indirect keyboard paths (open via Quick Actions)

Quick Actions opener keys (all open `quick-actions.sh`):

- `Super + Ctrl + Space`
- `Super + /`
- `Super + A`
- `Super + D`

Inside Quick Actions:

- Select row `Workspace Overview` (case index `3`) to run `workspace-overview-toggle.sh`.
- Fast row-select while menu is open:
  - `Ctrl + 4` (or `Super + 4`) picks row 4 (0-based index 3 action).

### C) Non-keyboard trigger

- Historical desktop-widget route was removed; use `workspace-overview-toggle.sh`.

---

## Companion Plan: Shell Large-List UX (New)

This section is added to solve your specific shell pain points:
- avoid giant completion dumps and repeated confirmation prompt noise
- always show compact listing after `cd`
- clearly show hidden remainder count (`... and N more`)

### Problem statement

Observed issue:
- `ls<TAB>` or broad completion contexts can trigger:
  - `zsh: do you wish to see all ... possibilities (...) ?`

Desired behavior:
- never flood terminal with giant item lists by default
- keep interactive output compact
- show deterministic truncation messaging

### Internet-inspired strategy (common zsh patterns)

Use official zsh completion controls + hook-based directory listing:
- Tune completion listing policy using `LISTMAX` and completion menu behavior.
- Keep `chpwd`-based auto-list workflow for `cd`.
- Prefer menu/fuzzy selection UX for very large completion sets instead of full dumps.

### Proposed shell UX target behavior

1) Completion behavior (TAB)
- For large match sets, prefer interactive selection menu (or fzf-tab flow) instead of raw full list output.
- Keep a small visible candidate window by default (recommended 20-40 items visible at once).
- Avoid the current giant “show all possibilities” flow for normal usage paths.

2) Auto-list behavior on `cd`
- Continue auto-listing after each directory change.
- Reduce default cap from `200` to a smaller ergonomic value (recommended `30`).
- Print:
  - first `N` entries only
  - final summary line: `... and <remaining> more`

3) Explicit full-list escape hatch
- Keep one explicit command for full output when needed:
  - e.g. `ll`/`la` unchanged for full detail
  - compact auto-list remains default only for passive `cd` transitions

### Candidate config policy to evaluate

Candidate A (balanced, recommended first):
- completion menu-first behavior + small list threshold
- auto-`ls` cap `N=30`

Candidate B (very strict compact mode):
- aggressive completion truncation + fzf-only selector for large sets
- auto-`ls` cap `N=20`

Candidate C (terminal-aware adaptive):
- cap `N = min(40, LINES-8)`
- same `... and N more` summary rule

Success criteria:
- no more noisy giant completion dumps in normal workflows
- directory entry after `cd` remains readable in < 1 screen
- remainder count always visible when truncated

---

# Design Direction (Target UX)

### 1) Single unified “Workspace Hub” behavior

Primary key should be `Super + Y` (with `Super + W` kept as secondary alias for compatibility).

Interface supports:

- Jump to workspace
- Focus windows
- Rename workspace
- Clear workspace name
- Show shortcut legend/help
- Optional fallback to Mission Control view

---

### 2) Rename workflow (minimal friction)

Recommended flow:

1. Open overview.
2. Choose a workspace row.
3. Trigger `Rename` action (`Ctrl + Alt + R` hotkey or action row).
4. Prompt for name (Rofi dmenu input).
5. Persist mapping and refresh overview.

Notes:
- Keep workspace rename as the primary action for workspace rows.
- Keep window/app rename out of scope for v1 to reduce complexity.
- Keep window list visible in overview for fast context and focus.

---

### 3) Shortcut visibility

A dedicated section in overview: “Overview Controls”.

Show only operational shortcuts relevant to workspace navigation and overview launch.

Sync the same subset into:
- `docs/KEYBINDS.md`
- `hypr/scripts/hypr-binds.sh` display output

Key priority rule:
- Show `Super + Y` first everywhere overview shortcuts are documented.

---

### 4) Favorites + recent-workspace quick switching (new feature)

Goal:
- Reach important workspaces in 1 key action from inside overview.

Behavior:
- Allow star/unstar workspace as favorite.
- Show pinned favorites at top of overview list.
- Track last 3 visited workspaces and show a `Recent` section.
- Provide actions:
  - `Jump to favorite #1..#5`
  - `Toggle favorite on selected workspace`

Why this helps:
- Faster switching than scanning full dynamic list.
- Preserves keyboard-first flow when many workspaces exist.

---

### 5) Window move/send actions from overview (new feature)

Goal:
- Avoid leaving overview when reorganizing windows.

Behavior:
- On selected window row, offer actions:
  - `Move window to workspace...`
  - `Send window to sidepanel`
  - `Move and follow`
- Keep existing `focus window` as default Enter behavior.

Why this helps:
- Turns overview into a control plane, not only a navigator.
- Reduces repetitive drag/drop or separate keybind steps.

---

# Proposed Technical Architecture

## Dynamic workspace detection

Instead of hardcoding workspace range `1..10`, detect workspaces dynamically using:

`hyprctl -j workspaces`

Benefits:

- Works with unlimited workspaces
- Correct window counts
- Compatible with dynamic workspace creation.

---

## State files

Workspace names state file (XDG-compliant):

`~/.local/state/noxflow/workspace-names.json`

Optional schema:

- Keys: workspace IDs (`"1".."n"`)
- Values: user labels (string, <= 32 chars)

Additional state (new):

- Favorites:
  - `~/.local/state/noxflow/workspace-favorites.json`
  - Array of workspace IDs in display order.
- Recent workspaces:
  - `~/.local/state/noxflow/workspace-recent.json`
  - Last N visited IDs (recommended N=3), most-recent-first.

Example:

```json
{
  "1": "Web",
  "2": "Code",
  "3": "Chat"
}
```

---

## Script responsibilities

### `workspace-overview.sh`

- Read workspace names file.
- Query dynamic workspace list.
- Render workspace rows as:

Workspace 2 (Code) (3 windows)

- Add command/action rows for:
  - Rename workspace
  - Clear workspace name
  - Show overview shortcuts
  - Toggle favorite workspace
  - Move selected window to workspace
  - Send selected window to side panel

---

### `workspace-overview-toggle.sh`

Keep current behavior:

1. Attempt expo overview
2. Fallback to rofi overview

Future optional flags:

- `--rofi`
- `--expo`
- `--force-rofi`

---

### New helper (planned)

`workspace-name-store.sh`

Responsibilities:

- Safe read/write/update/clear for workspace name map.

Commands supported:

- `set <ws> <name>`
- `get <ws>`
- `unset <ws>`
- `list`

Additional helper (planned):

`workspace-meta-store.sh`

Responsibilities:
- Manage favorites list.
- Manage recent-workspaces ring buffer.
- Validate IDs against current dynamic workspace set.

---

# Data hygiene rules

Before writing state:

- Trim whitespace.
- Reject empty names after trim.
- Length limit recommended: 32 chars.
- Escape or remove tabs/newlines.
- Validate JSON before commit.
- Use atomic write (`tmp` + `mv`) to avoid corruption.

For shell list truncation output:
- Count entries from source list before truncating.
- Compute `remaining = total - shown`.
- Emit summary only when `remaining > 0`.
- Keep summary format stable: `... and <remaining> more`.

Example write pattern:

write to
`workspace-names.json.tmp`

then atomically move to

`workspace-names.json`

---

# Implementation Plan (Phased)

### Phase 0: Baseline lock + behavior tests

Snapshot current behavior of:

Direct launch keys:

- Super + W
- Super + Shift + Space
- Super + Shift + Tab

Indirect launch paths:

- Quick Actions route
- Removed desktop-widget route

Deliverable:
Checklist confirming unchanged baseline before feature work.

Execution checklist:
- [x] `hyprctl -j clients | jq length` works in-session
- [x] `Super + Y` path opens Workspace Hub
- [x] `Super + W` opens current overview
- [x] `Super + Shift + Space` opens current overview
- [x] Workspace overview opens through Hyprland/Rofi bindings

---

### Phase 1: Workspace naming backend

Add helper script for workspace name persistence.

Functions:

- read state
- write state
- validate JSON
- atomic update

Manual CLI tests for:

set
get
unset
list

Deliverable:
Stable workspace label persistence.

Execution checklist:
- [x] `workspace-name-store.sh set 2 Code` persists value
- [x] `workspace-name-store.sh get 2` returns `Code`
- [x] `workspace-name-store.sh unset 2` clears value
- [x] invalid names (empty/newline-only) are rejected
- [x] file writes use `tmp + mv`

---

### Phase 2: Overview UI integration

Update `workspace-overview.sh` rendering:

Display format:

Workspace 3 (Code) (4 windows)

Add action rows:

- Rename workspace
- Clear workspace name
- Show overview shortcuts

Deliverable:
Extended overview UI supporting naming actions.

Execution checklist:
- [x] workspace list is dynamically discovered from live Hypr state
- [x] workspace row shows `Workspace <id> (<label>) (<count> windows)` when label exists
- [x] rename action refreshes menu without manual restart
- [x] clear-name action restores numeric-only display

---

### Phase 3: Shortcut panel in overview

Add selectable row:

Show shortcuts

Opens second menu displaying overview-related shortcuts only.

Possible implementations:

- Rofi second menu
- Script view of filtered `hypr-binds.sh`

Deliverable:
In-overview discoverability of shortcuts.

Execution checklist:
- [x] second menu opens from `Show shortcuts`
- [x] list includes all direct + indirect launch paths
- [x] `Super + Y` appears first in this list

---

### Phase 4: Favorites + recents integration (new)

Implement:
- Favorite toggle action on workspace rows.
- Favorite-first sorting in render output.
- Recent-workspace section (last 3 visited).

Optional future enhancement:
- `Alt + 1..5` in overview to jump favorites.

Deliverable:
Fast-access workspace navigation for large workspace sets.

Execution checklist:
- [x] favorite toggle persists in metadata file
- [x] favorites render first without breaking sort stability
- [x] recent list updates on workspace switches

---

### Phase 5: Window move/send actions (new)

Implement window-level action flow:
- Select window row -> action picker menu.
- Actions:
  - Move to workspace (dynamic target list)
  - Move to workspace and follow
  - Send to side panel

Safety checks:
- Ignore invalid/stale window address.
- Show non-blocking notification on failed dispatch.

Deliverable:
Overview-driven workspace reorganization workflow.

Execution checklist:
- [x] move action sends selected window to chosen workspace
- [x] move+follow changes workspace after dispatch
- [x] sidepanel send action works from window row

---

### Phase 6: Consistency pass (docs + scripts)

Align text in:

- `docs/KEYBINDS.md`
- `README.md`

Ensure rename workflow and overview shortcuts are documented.
Ensure all docs present `Super + Y` as primary for workspace hub.

Deliverable:
Documentation synced with final UX.

Execution checklist:
- [x] `README.md` shortcut block matches final behavior
- [x] `docs/KEYBINDS.md` includes overview panel flow
- [x] `hypr-binds.sh` output presents `Super + Y` first

---

### Phase 7: Reliability + regression checks

Validate behavior with missing dependencies:

No `rofi`
No `jq`

Ensure graceful fallback behavior.

Validate:

- missing workspace names file
- corrupted JSON
- dynamic workspace counts

Deliverable:
Regression checklist and fallback validation.

Execution checklist:
- [x] no `rofi` => graceful fallback path
- [x] no `jq` => graceful fallback path
- [x] malformed metadata file => recover or ignore safely
- [x] empty workspace set handled without script crash

---

### Phase 8: Shell UX compact-list rollout (new)

Implement and validate:
- Completion behavior tuning for large match sets.
- Auto-`ls` default cap reduction (200 -> target 30, configurable).
- Standardized truncation footer: `... and N more`.

Test matrix:
- small dir (`<= N` entries): no truncation line
- large dir (`> N` entries): truncation line appears with exact count
- deep project dirs + mixed files/dirs
- completion on broad prefixes (commands, files, dirs)

Deliverable:
Consistent compact shell UX with clear overflow messaging.

Execution checklist:
- [x] `AUTO_LS_MAX_ENTRIES` default lowered to target value
- [x] truncated auto-`ls` always prints `... and N more`
- [x] completion behavior tuned (`LISTMAX=0` + compact list-lines)
- [x] full explicit listing commands (`ll`, `la`) stay unchanged

---

# Shortcut Inventory To Keep in “Overview Shortcuts” Panel

Recommended list:

Direct overview shortcuts:

- `Super + Y` (primary)
- `Super + W` (secondary/alias)
- `Super + Shift + Space`
- `Super + Shift + Tab`
- `Super + Tab` (Mission Control plugin overview)

Quick Actions fast path:

- `Super + Ctrl + Space` + `Ctrl + 4`
- `Super + /` + `Ctrl + 4`
- `Super + A` + `Ctrl + 4`
- `Super + D` + `Ctrl + 4`

---

# Risks and Mitigations

Risk: Rofi row parsing collisions due to tabs/custom formatting.

Mitigation:
Strict TSV format + robust parsing.

---

Risk: Name file corruption.

Mitigation:
Atomic writes + JSON validation.

---

Risk: Keybind drift between docs and config.

Mitigation:
Maintain one canonical source for keybind documentation.

---

Risk: Dependency absence.

Mitigation:
Graceful fallback when `rofi` or `jq` are unavailable.

---

# Acceptance Criteria (Definition of Done)

- Workspace names can be set, changed, cleared, and persist across sessions.
- Overview displays numeric ID + optional label + window count.
- Overview exposes shortcut list for all current launch paths.
- All current launch paths still work after changes.
- Workspace detection is dynamic.
- Favorites and recents persist and render correctly.
- Window move/send actions work from overview without regressions.
- README + KEYBINDS are updated to match behavior.
- `cd` auto-list is compact by default and prints `... and N more` when truncated.
- Large completion flows no longer spam giant raw lists in normal usage.

---

# Files Updated During Implementation

- `hypr/scripts/workspace-overview.sh`
- `hypr/scripts/workspace-overview-toggle.sh`
- `hypr/scripts/workspace-name-store.sh`
- `hypr/scripts/workspace-meta-store.sh`
- `docs/KEYBINDS.md`
- `README.md`
- `zshrc`
- `hypr/hyprland.conf`

---

# External References (for implementation inspiration)

- Zsh `LISTMAX` behavior (official docs):
  - https://zsh.sourceforge.io/Doc/Release/Parameters.html#index-LISTMAX
- Zsh completion system styles (`list-prompt`, menu behavior):
  - https://zsh.sourceforge.io/Doc/Release/Completion-System.html
- Zsh hook functions (`add-zsh-hook`, `chpwd`):
  - https://zsh.sourceforge.io/Doc/Release/User-Contributions.html#Manipulating-Hook-Functions
- Example of line-capped completion UX in the wild (`list-lines`):
  - https://github.com/marlonrichert/zsh-autocomplete#change-the-max-number-of-lines-shown

# NoxFlow Refactor Plan — "One Surface, Many Shapes"

**Branch:** `inspired-rewrite` · **Date:** 2026-07-28 · **Supersedes:** the steal-table in `session-ses_05bd.md` prompt
**Reviewed by:** zen-deep-reviewer, zen-long-context, zen-general-mimo, zen-general-big-pickle (round 1) · **Revised by:** zen-general-mimo + 2× zen-vision-context (round 2 — 10 revisions folded in below)

---

## 0. Honest Status

TASKS.md says ~99%. Reality is closer to **~65%** — the skeleton is complete, but several features are UI-complete/backend-stub:

| Claimed | Reality |
|---|---|
| Capture with OCR/Lens/search | Region select works; **OCR output never read back** (`Capture.qml:243-257` — tesseract runs, result is placeholder text); Lens/Search open `file://` URLs in browser (won't upload) |
| Calendar with Google sync | Grid + agenda render; **`syncGCal()` is a TODO comment** (`CalendarModel.qml:82-86`) |
| Khoj AI launcher mode | Hardcoded OpenAI-compatible endpoint `http://127.0.0.1:8080/v1` (`Launcher.qml:33`); **no Khoj integration at all** |
| Clipboard history + persistence | In-memory works; persistence via shell-escaped `echo '...' > file` (**injection-fragile**, `ClipboardModel.qml:79`); no auto-capture |
| NoxIsland "10-state FSM" | 10 states exist but it's an if/else chain, no transition table, no priority queue, no autonomous notification subscription |
| Morphing animations | Per-surface scale+opacity entrances only; **no shared-geometry morphing** (button → popup → panel) anywhere |

Remaining runtime warnings: `Bar.qml` (6× `parent is not defined` + undefined bool), `Tooltip.qml:14` (undefined QObject).

---

## 1. Unifying Concept

Adopt one mental model for the whole shell (from zen-general-big-pickle):

> **NoxFlow is a single living Surface that changes shape.** Context determines form, not the user picking a tool.

Canonical morph targets, smallest to largest:

| Target | Size | Used for |
|---|---|---|
| **Chip** | pill in Bar | weather, media, clock, status |
| **Island** | floating pill below Bar | notification preview, timer, recording, mic, capture progress |
| **Popup** | ~400×480 | Launcher, OCR results, AI answers, calendar picker |
| **Panel** | edge-anchored | ControlCentre, NotificationCentre, Settings, Dashboard |
| **Fullscreen** | overlay | Overview, region capture |

Rule: **never teleport.** Every transition interpolates x/y/width/height/radius simultaneously. Chip → Island → Popup is the bread-and-butter path; ephemeral content stops at Island, anything >5s of attention opens a Panel.

Intelligence is one surface: OCR results, translations, AI answers, and web search all render in the **same popup component** with tabs (Text / Translate / Explain / Search). One capture event, one results shell.

---

## 2. The Biggest Risk (and the mitigation)

**Scope metastasis from 15 reference repos.** The shell works today. The failure mode is starting a provider-architecture rewrite + a morphing system + calendar sync simultaneously, breaking working surfaces, and ending up worse than before.

Mitigations (non-negotiable):
- **One system per branch.** Never refactor models and the island FSM in the same PR. Every phase below is independently revertable in <10 min.
- **Depth before breadth.** Phases 0–1 fix broken things before any new steal-lands.
- **REFERENCE.md with pinned commit hashes** instead of submodules/vendoring (see §6).
- **TASKS.md gets a REAL/PARTIAL/STUB column** so "done" stops meaning "UI renders."

---

## 3. Phased Roadmap

### Phase 0 — Fix What's Broken (2–3 weeks) · no new features

**Pre-step (day 0):** Quickshell `Process` API spike — verify stdin/stdout capture works before rewriting OCR on it (pre-1.0 API churn risk).

| Task | File(s) |
|---|---|
| Fix OCR pipeline: capture tesseract stdout via `Process` + stdin/stdout, not shell redirect + `cat` | `surfaces/capture/Capture.qml:234-257` |
| Replace clipboard persistence shell-`echo` with JSON write via helper script or `Process` stdin | `ClipboardModel.qml:64-83` |
| Fix `Bar.qml` 6× `parent is not defined` + undefined bool; fix `Tooltip.qml:14` | `Bar.qml:19,291-333`, `components/Tooltip.qml` |
| Make AI endpoint a `noxd` setting, not a hardcoded constant | `Launcher.qml:33` → `setSetting("ai.endpoint", …)` |
| Add `validStates` guard to NoxIsland so typo'd states fail loudly | `NoxIsland.qml:21` |
| **Visual prereqs for morphing:** wrap Bar right-side indicators (media/network/bt/volume/battery/notif) in chip `Rectangle`s (`radiusSm`, `surfaceSurfaceContainerHigh`, hover StateLayer); give them ids (`mediaLabel`, `notifBadge`, `clock`); match Bar background token to panel `surfaceSurfaceContainerHigh` to avoid light→dark flash | `Bar.qml` |
| Unify animation timing: replace 6 duration/easing combos (250/200/180/150/120/80ms, OutBack bounces) with one `durationLong: 350ms OutCubic` token; keep reduced-motion honored | `NoxIsland.qml`, `NotificationCentre.qml`, `ControlCentre.qml`, `theme/Tokens.qml` |
| Replace runtime `Qt.createQmlObject` close animations with pre-declared `SequentialAnimation` (7 surfaces — memory churn + stutter) | NotificationCentre, ControlCentre, others |
| Rewrite TASKS.md status column to REAL/PARTIAL/STUB | `TASKS.md` |

**Exit gate:** zero runtime warnings in `journalctl --user -u noxflow-shell`; OCR round-trips real text into the results popup; every Bar morph-origin element has a container with reportable geometry.

### Phase 1 — Architecture De-Risking (1–2 weeks)

**Phase 1.0 (prerequisite, day 1): noxd source audit.** The `noxd` binary lives at `~/.local/bin/noxd` and `noxctl` at `~/.local/bin/noxctl`; **neither source is in this repo.** Locate the sources, determine the license, decide vendoring vs pinned submodule. If sources are unrecoverable, the protocol must be re-implemented from `PROTOCOL.md` — this changes Phase 1 scope materially. Do not start other Phase 1 work until this is resolved.

| Task | Why |
|---|---|
| `InstanceTracker.qml` — replace 6× copy-pasted push/splice per-screen tracking in `shell.qml:46-224` | Fragile on hotplug/re-parenting |
| `PROTOCOL.md` — document the noxd JSON-lines contract, version matrix, provider list | Version drift is silent without it |
| Vendor `noxd` + `noxctl` (per 1.0 outcome) with build script in `setup/` | Shell is fully dependent on unversioned external binaries |
| Extract close-animation helper (started in Phase 0, finish remaining surfaces) | Drift |
| `MODELS.md` or JSDoc on each model's property contract | Required before any provider-registry refactor |
| Add `gcalcli/` and any OAuth paths to `.gitignore`; SECURITY note in README | Waylandar/GCal work is coming; tokens must never enter the repo |

### Phase 2 — NoxIsland Tide-Parity (2 weeks) · **moved before morphing**

The island must know what state it's in (real FSM + priority queue) before any morph can animate *from* or *to* it — the FSM is what calls the morph contract with correct geometry. Steal deeply from **enhaoswen/Tide-island**.

| Task |
|---|
| Extract inline timer logic → `island/TimerIndicator.qml`; mic/recording → `island/MicIndicator.qml`; new `island/NotificationIndicator.qml` subscribed to NotificationModel |
| Replace if/else `handleEvent` with a real FSM module (`NoxIslandState.js`, Node-testable) with priority queue: notification > recording > mic > timer > media > volume/brightness |
| Fix island geometry so morphs can target it: full-width `anchors.left/right` PanelWindow means the visual pill's screen position is layout-internal, not window-level. Add an inner `Item` with known screen-relative rect that MorphRegistry can read as `destRect` (do NOT try `anchors.horizontalCenter` — unsupported) |
| Visual richness vs Tide: circular progress ring for timer/recording (`ConicalGradient`/`Canvas`, `tonalPrimary`), album-art treatment, pulsing recording dot, app icon + body preview in notification state |
| IPC-controllable like Tide (`noxctl island show timer 300`) — **update `hypr/conf/40-binds-launch.lua` keybinds in the same commit as any IPC rename** |

### Phase 3 — Morphing Surface System (5–6 weeks) · **the #1 want**

Steal deeply from **caelestia-dots/shell** (drawer geometry morphing). Split into 3a primitives → 3b integration.

**3a — Primitives:**
| Task |
|---|
| `MorphRegistry.qml` — Bar chips report screen-space rects (`clockGeometry`, `mediaChipGeometry`, `notificationBadgeGeometry` from Phase 0's new chip containers); registry snapshots destination geometry at trigger time |
| `MorphingSurface.qml` base: animates x/y/w/h/radius from `sourceRect` to `destRect`, owns scrim (`opacityScrim` 0.6 fade), mount/unmount lifecycle |
| **Non-blocking rule:** input is accepted from frame 0; animation is cosmetic, never gates interaction. (Resolves the "350ms = latency" contradiction — morphs start instantly and are interruptible) |
| **Multi-screen rule:** morph destination is snapshotted at trigger time and never re-read mid-animation; singleton surfaces (Dashboard/Settings follow `Quickshell.activeScreen`) must not rebind screens mid-morph — either snapshot or convert to per-screen Variants first |

**3b — Integration (one surface per PR, old entrance kept behind setting as fallback):**
| Order | Morph |
|---|---|
| 1 | notification badge → NotificationCentre |
| 2 | status cluster → ControlCentre |
| 3 | clock → CalendarWidget |
| 4 | media chip → NoxIsland media state → full media panel |
| 5 | settings gear → SettingsPanel |

Content staging per panel: header fades 0–50%, body 30–80%, scrollables last.

**Exit gate:** clicking a Bar chip visibly grows that chip into its panel; nothing pops in from nowhere; all morphs interruptible; keybinds unchanged or migrated in the same commit.

### Phase 4a — Capture & Intelligence (2 weeks)

Steal from **QuickSnip** + **end-4**.

| Task | Reference |
|---|---|
| Unified results popup: one component with Text / Translate / Explain / Search tabs (pill tabs matching existing CC/NC tab treatment, `PopupContainer` shell ~400×480, action row: Copy / Share) — fed by OCR, AI, or web | QuickSnip + end-4 |
| Annotation layer (arrows, boxes, highlight) on Capture before copy/save | QuickSnip |
| Screen translation: OCR → detect language → translate (configurable provider) → same results popup | end-4 |
| Keep launcher "Ask AI" on the local endpoint by default; Khoj stays optional, never a startup dependency | — |

### Phase 4b — Calendar Sync (1–2 weeks)

Steal from **waylandar**. Separate from 4a — no shared code path, and OAuth/gcalcli plumbing is its own risk.

| Task |
|---|
| `CalendarModel.syncGCal()`: wire `gcalcli --format=json agenda`, merge with local events |
| Background sync timer + reminder → Island notification state (uses Phase 2 FSM) |
| Read-only sync; no OAuth secrets in repo (`.gitignore` from Phase 1) |

### Phase 5 — Deferred Polish (only after 0–4 ship)

| Item | Reference | Notes |
|---|---|---|
| RadialWheel editable slots (wire existing dead `loadConfig()`) | monochrome-os | `RadialWheel.qml:278` — loader exists, nothing calls it |
| Theatrical notification entrances (urgency-restricted) | Rivendell | Never animate routine notifications |
| Theme export/import + preview cards | HyDE | Existing 5 profiles suffice until then |
| Smooth kinetic scroll in QML Overview | scroll-overview | **QML-only — do NOT adopt the hyprexpo plugin** (ABI breakage per Hyprland update) |
| Quickshare surface | Caelestia/GSConnect | Optional, new surface — last |
| Sidebar/shell-variant concepts | end4-pC | Skim only; don't depend on another person's shell repo |

### Explicitly OUT of scope (protect momentum)

- Rewriting noxd as a compiled Go/Rust backend (DankMaterialShell-style) — current protocol works; revisit only at a measured ceiling
- Khoj as an integrated service; rtk in the interactive shell path — both are optional external tools, install them, don't wire the shell to them
- Migrating to NixOS (ilyamiro config is navbar/calendar *inspiration* only)
- Any new surface beyond Quickshare; multi-compositor abstraction beyond keeping Hyprland coupling contained to Bar/Overview/Launcher-Windows
- Emoji-as-icons (monochrome-os), collage-style architecture (binnewbs/Cybersnake223 — visual recipes only, e.g. their Super+Space tool aesthetic)

---

## 4. Reference Priority

- **Deep study:** Caelestia shell (morphing), Tide-island (island states), QuickSnip (capture pipeline)
- **Skim:** end-4 (AI patterns, Material treatment), waylandar (sync architecture), HyDE (theme packaging), ilyamiro (navbar/calendar ideas)
- **Defer:** DankMaterialShell, Rivendell, monochrome-os, scroll-overview, end4-pC, khoj, rtk
- **Mood-board only:** Reddit rice screenshots (several don't render; no interaction behavior to learn)

## 5. Risks Register (ranked)

1. **Scope explosion** — mitigated by one-system-per-branch + phase gates (§2)
2. **noxd external binary drift** — `PROTOCOL.md` + version check on handshake; repo the source (Phase 1)
3. **Quickshell pre-1.0 API churn** — already bitten once (see TASKS.md fix list); pin the package version in setup scripts
4. **Hyprland ABI plugins** — do not adopt scroll-overview/hyprexpo forks; keep Overview pure QML
5. **OAuth/token leakage** — gcalcli/waylandar credentials live outside the repo, gitignored
6. **RTX 4050 6GB VRAM** — local 4B model only with aggressive quant; AI features must degrade gracefully, never block startup
7. **Clipboard shell-injection** — fixed in Phase 0

## 6. REFERENCES.md format

Create `REFERENCES.md` at repo root — no submodules, no vendoring:

```markdown
## caelestia-dots/shell — DEEP STUDY
- URL: https://github.com/caelestia-dots/shell
- Pinned: <commit> (checked 2026-07-28)
- Steal: drawer morph geometry, component/module/service split, shell IPC
- Ignore: visual identity, dependency set

## enhaoswen/Tide-island — DEEP STUDY
- Steal: contextual state priority, IPC control, user-service lifecycle
…(one block per repo, incl. Codeberg rivendell link + Lemmy mirror note)
```

## 7. Definition of Done (per phase)

- Phase gates require: no new runtime warnings, `noxctl` toggles still work, TASKS.md reality column updated, commit per task with conventional message.
- **Daily-driver safety check at every merge:** open 5 surfaces in sequence, verify no crash, verify all keybinds still fire.
- The refactor is complete when: every surface morphs from its origin chip, the island autonomously prioritizes contexts, capture round-trips OCR/translate/AI in one popup, calendar shows real synced events, and TASKS.md's REAL column is 100%.

## 8. Rollback Protocol (daily-driver safety)

This is a live workstation. Every phase must be revertable in <10 minutes:

1. **One system per branch** (already §2). Branch names: `phase-N-<system>`. Merge to `inspired-rewrite` only after the phase gate passes.
2. **Fallback path:** `hypr/recovery.conf` exists and stays working — document in README how to boot into it (comment the `noxflow.lua` include chain, uncomment recovery).
3. **Broken-shell one-liner:** `systemctl --user stop noxflow-shell && systemctl --user start wayle` (Wayle package stays installed until the refactor completes; its user unit stays disabled).
4. **Git discipline:** never force-push `inspired-rewrite`; tag `pre-phase-N` before each phase merges so `git checkout pre-phase-N` restores the last-good state.
5. **Service safety:** `noxflow-fallback.service` (already exists) must keep working after every service-file change.

## 9. Testing Strategy

QML has no standard unit-test framework, so testing is layered:

| Layer | Tool | Covers |
|---|---|---|
| Pure logic | Node tests in `shell/noxflow/tests/` (pattern: existing `test_protocol.js`) | `Protocol.js`, `ModelUtils.js`, new `NoxIslandState.js` FSM (transition table, priority queue, invalid-state guards) |
| Runtime smoke | `scripts/shell-check.sh` — restart `noxflow-shell.service`, sleep, assert zero ERROR lines and no new WARN lines in journal | Every commit that touches QML |
| Visual/component | `Gallery.qml` showcase (already renders components, surfaces at forced-open states, density switcher, reduced-motion toggle) — extend with a Morph page in Phase 3 | Manual per-phase review |
| Manual QA checklist | Per-phase list in TASKS.md: 5-surface open/close, keybind sweep, per-screen check on multi-monitor, reduced-motion on/off | Phase gates |

Note: there are currently **no screenshots of the shell in the repo** (only SDDM login-theme assets). Add a `docs/screenshots/` capture step to Phase 3's exit gate so morph behavior is visually documented.

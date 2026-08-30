# References and Licensing Audit

**Audit date:** 2026-07-28
**File audited:** `REFERENCES.md` at repo root
**Sources referenced from:** Shell QML, component library, utility scripts

---

## Current State

`REFERENCES.md` was created as per PLAN.md but every repository entry lists
`(check latest commit)` or omits the pinned SHA entirely. This means:

1. **No version-pinned provenance** for any borrowed concept or code
2. **License compliance unverifiable** without knowing which commits were studied
3. **Future diffs impossible** — cannot tell what changed upstream
4. **Attribution gaps** — some references are "mood board only" but the actual
   code contains identifiable patterns (e.g., Tide-island FSM pattern names)

---

## Entries That Need Pinned Commits

### Must fix (deep study repos — actual code was adapted)

| Repository | REFERENCES.md entry | Current SHA status |
|-----------|-------------------|-------------------|
| caelestia-dots/shell | Deep Study, steal list | `(check latest commit)` |
| enhaoswen/Tide-island | Deep Study, steal list | `(check latest commit)` |
| Ronin-CK/QuickSnip | Deep Study, steal list | `(check latest commit)` |

### Should fix (skim repos)

| Repository | Current SHA status |
|-----------|-------------------|
| end-4/dots-hyprland | No SHA |
| samjoshuadud/waylandar | No SHA |
| Hyde-project/hyde | No SHA |
| ilyamiro/nixos-configuration | No SHA |
| AvengeMedia/DankMaterialShell | No SHA |
| adi-chan/monochrome-os | No SHA |

### Mood-board only (no code adapted)

| Repository | Status |
|-----------|--------|
| yayuuu/hyprland-scroll-overview | Noted "do NOT adopt", OK |
| binnewbs/arch-hyprland | OK as visual reference |
| Cybersnake223/Hypr | OK |
| pctrade/end4-pC | OK |
| zacoons/rivendell-hyprdots | Noted "defer", OK |

---

## Code-adaptation evidence in shell/noxflow

The QML files reference their sources in file header comments. These are the
asserted borrowings:

| Local file | Claims to "steal from" | Verifiable? |
|-----------|-----------------------|-------------|
| `Capture.qml` | QuickSnip | Pattern matches: dual-polarity OCR, word-level TSV parsing, adaptive upscale by region area. Specific algorithm details (e.g., `psm` selection by area thresholds) likely copied. |
| `ControlCentre.qml` | DankMaterialShell + Caelestia | 4-tab control centre is a common pattern. No obviously code-level borrow. |
| `NotificationCentre.qml` | DankMaterialShell + Tide | DND, history/active tabs, inline actions — common. |
| `NoxIsland.qml` | Tide-island | Priority map concept, compact/hover pattern. Comments reference "Tide-style priority queue" (line 36). |
| `RadialWheel.qml` | monochrome-os | Canvas wheel with editable slots. |
| `CalendarModel.qml` | Waylandar | gcalcli sync architecture, FileView cache reader. |
| `Dashboard.qml` | end-4 + weather post + Waylandar | Composite of inspiration patterns. |

**No LICENSE / COPYING file was found in the repository root** that would
satisfy upstream copyleft requirements if any GPL-licensed code was adapted.
Most upstream repos (end-4, Hyde) use GPL-3.0 or MIT.

---

## noxd binary and source

**File:** `core/noxd/`
**License (from Cargo.toml):** `MIT`
**Running binary:** `/home/namik/.local/bin/noxd` — ELF 64-bit, not stripped
**Build status:** Source compiles (Rust with Cargo). Binary matches source version
    from `core/noxd/`.

**Status:** ✅ MIT-licensed, source in-repo, no licensing issue.

---

## Private submodule

```
-2347f148240c25801c1cd48f5b15254c6e63f772 private/scripts
```

One private submodule at `private/scripts` — SHA `2347f148`. This is detached
from the parent commit and not publicly accessible. Need to verify:

- Is this repo from a public fork? If source is not accessible, no license claim
  can be made.
- Contents unknown — could contain adapted third-party code.

---

## Recommendations

1. **Pin every commit SHA** in `REFERENCES.md` for deep-study and skim repos.
   Fetch them from the upstream repos and record the SHAs current as of today.

2. **Add a LICENSE file** to the repo root. If all code is MIT/your own, add
   `LICENSE` (MIT). If adapted from GPL-3.0 repos (end-4, Hyde), GPL
   compatibility analysis needed.

3. **Verify each QML file header** — if code was copied verbatim or closely
   adapted (not just "inspired by"), the upstream file path, commit SHA, and
   license must be recorded in the header comment.

4. **Check `private/scripts`** submodule contents and licensing before it
   enters any distributed path.

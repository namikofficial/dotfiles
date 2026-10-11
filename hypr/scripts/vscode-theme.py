#!/usr/bin/env python3
"""Generate the NoxFlow Dynamic VS Code color theme from the canonical palette.

Pure function of the palette JSON written by nox-theme.py: no wallpaper access,
no user settings, no clock. The emitted theme is validated (contrast floors,
surface separation, syntax hue separation, color syntax) before anything is
written; on failure nothing is touched, so the last good theme stays installed.

    vscode-theme.py PALETTE.json [--cache FILE] [--extension-dir DIR]

With neither output option the theme JSON is printed to stdout.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

THEME_NAME = "NoxFlow Dynamic"
THEME_FILE = "NoxFlow Dynamic-color-theme.json"

HEX6 = re.compile(r"^#[0-9a-fA-F]{6}$")
HEX_ANY = re.compile(r"^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")

# ── color math ───────────────────────────────────────────────────────────────


class PaletteError(ValueError):
    """The palette is missing a role or holds an invalid color."""


def parse_hex(value: str) -> tuple[int, int, int]:
    if not isinstance(value, str) or not HEX6.match(value):
        raise PaletteError(f"not a #rrggbb color: {value!r}")
    return int(value[1:3], 16), int(value[3:5], 16), int(value[5:7], 16)


def to_hex(rgb: tuple[float, float, float]) -> str:
    r, g, b = (max(0, min(255, round(v))) for v in rgb)
    return f"#{r:02x}{g:02x}{b:02x}"


def _lin(c: float) -> float:
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _unlin(c: float) -> float:
    c = max(0.0, min(1.0, c))
    return 255.0 * (12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055)


def luminance(value: str) -> float:
    r, g, b = parse_hex(value)
    return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b)


def contrast(a: str, b: str) -> float:
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def to_oklch(value: str) -> tuple[float, float, float]:
    r, g, b = (_lin(v) for v in parse_hex(value))
    l_ = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m_ = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s_ = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    lab_l = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
    lab_a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
    lab_b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    return lab_l, math.hypot(lab_a, lab_b), math.degrees(math.atan2(lab_b, lab_a)) % 360


def _oklch_rgb(L: float, C: float, H: float) -> tuple[float, float, float]:
    a = C * math.cos(math.radians(H))
    b = C * math.sin(math.radians(H))
    l_ = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m_ = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s_ = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (
        4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_,
        -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_,
        -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_,
    )


def from_oklch(L: float, C: float, H: float) -> str:
    """OKLCH to hex, reducing chroma (never shifting hue) until in gamut."""
    L = max(0.0, min(1.0, L))
    for _ in range(40):
        lin = _oklch_rgb(L, C, H)
        if all(-0.0005 <= v <= 1.0005 for v in lin):
            return to_hex(tuple(_unlin(v) for v in lin))
        C *= 0.93
    return to_hex(tuple(_unlin(v) for v in _oklch_rgb(L, 0.0, H)))


def hue_dist(a: float, b: float) -> float:
    d = abs(a - b) % 360
    return min(d, 360 - d)


def mix(a: str, b: str, t: float) -> str:
    """Mix in encoded sRGB (how VS Code composites alpha); t=0 gives a, t=1 gives b."""
    ra, rb = parse_hex(a), parse_hex(b)
    return to_hex(tuple(x * (1 - t) + y * t for x, y in zip(ra, rb)))


def alpha(value: str, amount: float) -> str:
    """#rrggbb plus an 8-bit alpha channel."""
    parse_hex(value)
    if not 0.0 <= amount <= 1.0:
        raise PaletteError(f"alpha out of range: {amount}")
    return f"{value.lower()}{round(amount * 255):02x}"


def composite(over: str, base: str) -> str:
    """Flatten an #rrggbbaa color onto an opaque #rrggbb base."""
    if len(over) == 7:
        return over
    a = int(over[7:9], 16) / 255.0
    return mix(base, over[:7], a)


def fit(color: str, backgrounds: list[str], minimum: float, *,
        chroma_floor: float = 0.0, direction: int | None = None) -> str:
    """Move lightness (hue and chroma preserved) until every background passes."""
    L, C, H = to_oklch(color)
    if C >= chroma_floor and all(contrast(color, bg) >= minimum for bg in backgrounds):
        return color
    C = max(C, chroma_floor)
    if direction is None:
        direction = 1 if max(luminance(bg) for bg in backgrounds) < 0.3 else -1
    candidate = L
    for _ in range(300):
        out = from_oklch(candidate, C, H)
        if all(contrast(out, bg) >= minimum for bg in backgrounds):
            return out
        candidate += 0.004 * direction
        if not 0.0 <= candidate <= 1.0:
            break
    return from_oklch(max(0.0, min(1.0, candidate)), C, H)


def clamp_hue(hue: float, anchor: float, spread: float) -> float:
    delta = (hue - anchor + 540) % 360 - 180
    return (anchor + max(-spread, min(spread, delta))) % 360


# ── palette ──────────────────────────────────────────────────────────────────

# Syntax hue anchors (OKLCH degrees) and how far a palette hue may drift from
# them. The spread keeps the roles >= 25 degrees apart whatever the wallpaper.
HUE_ANCHORS = {
    "red": (25.0, 5.0),
    "orange": (55.0, 0.0),
    "yellow": (90.0, 8.0),
    "green": (145.0, 10.0),
    "cyan": (200.0, 10.0),
    "blue": (255.0, 10.0),
    "magenta": (320.0, 10.0),
}
# Syntax roles share one visual weight so no hue dominates; only the hue is
# taken from the palette, and lightness moves further only to meet contrast.
SYNTAX_WEIGHT = {"dark": (0.76, 0.125), "light": (0.46, 0.130)}
SYNTAX_CHROMA_FLOOR = 0.085
ACCENT_FILL_CHROMA = 0.72


@dataclass(frozen=True)
class Palette:
    mode: str
    tint_hue: float
    tint_chroma: float
    editor_seed_l: float
    text: str
    muted: str
    accent: str
    ramp: dict[str, str]  # red green yellow blue cyan magenta (+ bright*)


def _get(data: dict, *paths: str) -> str | None:
    for path in paths:
        node: object = data
        for part in path.split("."):
            node = node.get(part) if isinstance(node, dict) else None
        if isinstance(node, str):
            return node
    return None


def load_palette(data: dict) -> Palette:
    """Read nested `colors.*` roles, falling back to the legacy flat keys."""
    def need(*paths: str) -> str:
        value = _get(data, *paths)
        if value is None:
            raise PaletteError(f"palette lacks {' or '.join(paths)}")
        parse_hex(value)
        return value

    surface = need("colors.surfaceBase", "surface", "bg")
    text = need("colors.onBackground", "text")
    muted = need("colors.onSurfaceVariant", "muted")
    accent = need("colors.primary", "colors.accent.primary", "accent")
    danger = need("colors.error", "colors.terminal.red", "danger")
    success = need("colors.success", "colors.terminal.green", "success")
    warning = need("colors.warning", "colors.terminal.yellow", "warn")
    accent2 = _get(data, "colors.secondary", "accent2") or accent
    mode = _get(data, "scheme.mode")
    if mode not in ("dark", "light", "oled"):
        mode = "light" if luminance(need("colors.surfaceCanvas", "bg")) > 0.4 else "dark"
    mode = "light" if mode == "light" else "dark"

    ramp = {
        "red": _get(data, "colors.terminal.red") or danger,
        "green": _get(data, "colors.terminal.green") or success,
        "yellow": _get(data, "colors.terminal.yellow") or warning,
        "blue": _get(data, "colors.terminal.blue") or accent2,
        "cyan": _get(data, "colors.terminal.cyan") or accent,
        "magenta": _get(data, "colors.terminal.magenta") or _get(data, "colors.tertiary") or accent2,
    }
    for name in list(ramp):
        bright = _get(data, f"colors.terminal.bright{name.title()}")
        ramp[f"bright{name.title()}"] = bright or ramp[name]
    for value in ramp.values():
        parse_hex(value)

    L, C, H = to_oklch(surface)
    if mode == "light":
        chroma = max(0.004, min(C, 0.016))
    else:
        chroma = max(0.006, min(C, 0.028))
    return Palette(mode, H, chroma, L, text, muted, accent, ramp)


# ── theme model ──────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class Surfaces:
    chrome: str   # activity bar, title bar, status bar (deepest chrome)
    tabs: str     # tab strip behind inactive tabs
    editor: str   # reference surface
    side: str     # side bar and panel
    header: str   # section headers inside the side bar
    hover: str    # row hover
    raised: str   # inputs, dropdowns, secondary buttons
    select: str   # inactive selection, pressed states
    float_: str   # menus, widgets, notifications, hover cards


def build_surfaces(p: Palette) -> Surfaces:
    def tint(L: float) -> str:
        return from_oklch(L, p.tint_chroma, p.tint_hue)

    if p.mode == "dark":
        e = max(0.17, min(0.21, p.editor_seed_l))
        return Surfaces(
            chrome=tint(e - 0.050), tabs=tint(e - 0.030), editor=tint(e),
            side=tint(e + 0.035), header=tint(e + 0.055), hover=tint(e + 0.070),
            raised=tint(e + 0.085), select=tint(e + 0.115), float_=tint(e + 0.080),
        )
    e = 0.985
    return Surfaces(
        chrome=tint(e - 0.075), tabs=tint(e - 0.050), editor=tint(e),
        side=tint(e - 0.035), header=tint(e - 0.060), hover=tint(e - 0.085),
        raised=tint(0.997), select=tint(e - 0.115), float_=tint(0.997),
    )


@dataclass(frozen=True)
class Roles:
    s: Surfaces
    mode: str
    text: str
    muted: str
    dim: str
    border: str
    border_subtle: str
    border_strong: str
    accent: str          # accent as text / indicator
    accent_fill: str     # accent as a button / badge fill
    on_accent: str
    error: str
    warning: str
    success: str
    info: str
    syntax: dict[str, str]
    report: dict[str, dict]


def _hue_role(p: Palette, role: str, name: str, backgrounds: list[str],
              report: dict[str, dict], *, weighted: bool = False) -> str:
    """Palette hue (clamped near its anchor), contrast-fitted by lightness only."""
    anchor, spread = HUE_ANCHORS[name]
    base = p.ramp[name]
    L, C, H = to_oklch(base)
    target = clamp_hue(H, anchor, spread) if spread else anchor
    if weighted:
        L, C = SYNTAX_WEIGHT[p.mode]
    color = fit(from_oklch(L, max(C, SYNTAX_CHROMA_FLOOR), target), backgrounds, 4.5)
    report[role] = {"source": base, "anchor": anchor, "spread": spread, "targetHue": target, "emitted": color}
    return color


def build_roles(p: Palette) -> Roles:
    s = build_surfaces(p)
    text_bgs = [s.chrome, s.tabs, s.editor, s.side, s.header, s.hover, s.raised, s.select, s.float_]
    text = fit(p.text, text_bgs, 9.0)
    muted = fit(p.muted, text_bgs, 4.5)
    dim = fit(mix(muted, s.editor, 0.35), [s.editor, s.side], 3.6)

    # Borders: visible against every region they separate. Surface steps carry
    # the separation; borders are reinforcement.
    border_bgs = [s.editor, s.side, s.tabs, s.chrome]
    seed = from_oklch(to_oklch(s.editor)[0], p.tint_chroma, p.tint_hue)
    border = fit(seed, border_bgs, 1.45)
    border_subtle = fit(seed, border_bgs, 1.25)
    border_strong = fit(seed, [s.editor, s.side, s.raised, s.float_], 2.0)

    accent_bgs = [s.editor, s.side, s.chrome, s.raised]
    accent = fit(p.accent, accent_bgs, 4.5)
    ink_dark, ink_light = from_oklch(0.18, p.tint_chroma, p.tint_hue), from_oklch(0.985, p.tint_chroma, p.tint_hue)
    on_accent = ink_dark if contrast(p.accent, ink_dark) >= contrast(p.accent, ink_light) else ink_light
    # Fills are calmer than accent text: a full-width Commit button in neon
    # accent dominates the sidebar, so lower its chroma (hue is unchanged).
    fL, fC, fH = to_oklch(p.accent)
    accent_fill = fit(from_oklch(fL, fC * ACCENT_FILL_CHROMA, fH), [on_accent], 4.5,
                      direction=1 if on_accent == ink_dark else -1)

    report: dict[str, dict] = {}
    syn_bgs = [s.editor, s.side, s.float_]
    err = _hue_role(p, "error", "red", text_bgs, report)
    warn = _hue_role(p, "warning", "yellow", text_bgs, report)
    ok = _hue_role(p, "success", "green", text_bgs, report)
    info = _hue_role(p, "info", "blue", text_bgs, report)

    # Orange has no terminal slot; it is synthesized at its anchor hue.
    wL, wC = SYNTAX_WEIGHT[p.mode]
    orange = fit(from_oklch(wL, wC, HUE_ANCHORS["orange"][0]), syn_bgs, 4.5)
    report["number"] = {"source": p.ramp["yellow"], "anchor": HUE_ANCHORS["orange"][0], "spread": 0.0,
                        "targetHue": HUE_ANCHORS["orange"][0], "emitted": orange}

    syntax = {
        "keyword": _hue_role(p, "keyword", "magenta", syn_bgs, report, weighted=True),
        "function": _hue_role(p, "function", "blue", syn_bgs, report, weighted=True),
        "string": _hue_role(p, "string", "green", syn_bgs, report, weighted=True),
        "type": _hue_role(p, "type", "cyan", syn_bgs, report, weighted=True),
        "tag": _hue_role(p, "tag", "red", syn_bgs, report, weighted=True),
        "decorator": _hue_role(p, "decorator", "yellow", syn_bgs, report, weighted=True),
        "number": orange,
    }
    syntax["escape"] = fit(mix(syntax["type"], text, 0.20), syn_bgs, 4.5)
    syntax["property"] = fit(mix(text, syntax["function"], 0.45), syn_bgs, 4.5)
    syntax["parameter"] = fit(mix(text, syntax["number"], 0.22), syn_bgs, 4.5)
    syntax["variable"] = text
    syntax["operator"] = fit(mix(text, syntax["type"], 0.30), syn_bgs, 4.5)
    syntax["punctuation"] = fit(mix(text, s.editor, 0.35), syn_bgs, 4.5)
    syntax["comment"] = fit(mix(muted, s.editor, 0.30), [s.editor, s.side], 4.0)
    return Roles(s, p.mode, text, muted, dim, border, border_subtle, border_strong,
                 accent, accent_fill, on_accent, err, warn, ok, info, syntax, report)


# ── theme body ───────────────────────────────────────────────────────────────


def build_colors(p: Palette, r: Roles) -> dict[str, str]:
    s = r.s
    light = r.mode == "light"
    t = r.text
    a = alpha
    sel_alpha = 0.26 if light else 0.32
    shadow = alpha("#000000", 0.14 if light else 0.45)
    line_hl = mix(s.editor, t, 0.05 if not light else 0.045)
    accent_hover = fit(mix(r.accent_fill, r.on_accent, 0.14), [r.on_accent], 4.5,
                       direction=1 if luminance(r.on_accent) < 0.3 else -1)
    slash_bg = a(r.accent, 0.18)
    slash_fg = fit(r.accent, [composite(slash_bg, s.side), composite(slash_bg, s.editor)], 4.5)
    gutter = (r.warning, r.success, r.error)
    bracket = [r.syntax["decorator"], r.syntax["keyword"], r.syntax["type"],
               r.syntax["string"], r.syntax["function"], r.syntax["number"]]
    ramp = p.ramp
    terminal_bg = s.side

    # "Black" and "white" swap roles with the mode but stay readable on the
    # terminal background: programs print with them, so a faint grey is a bug.
    faint = fit(s.select, [terminal_bg], 4.5)
    ansi_black = faint if not light else r.text
    ansi_white = r.text if not light else faint
    git_untracked = fit(mix(r.success, t, 0.25), [s.side, s.editor], 4.5)
    git_conflict = r.syntax["number"]
    git_renamed = r.syntax["type"]
    sym = r.syntax

    c: dict[str, str] = {}

    add = c.update

    # Global
    add({
        "foreground": t, "disabledForeground": r.dim, "descriptionForeground": r.muted,
        "errorForeground": r.error, "focusBorder": r.accent, "icon.foreground": r.muted,
        "selection.background": a(r.accent, 0.40), "widget.border": r.border_strong,
        "widget.shadow": shadow, "sash.hoverBorder": r.accent, "scrollbar.shadow": shadow,
        "textLink.foreground": r.accent, "textLink.activeForeground": fit(mix(r.accent, t, 0.25), [s.editor, s.side], 4.5),
        "textPreformat.foreground": r.syntax["string"], "textPreformat.background": s.raised,
        "textBlockQuote.background": s.side, "textBlockQuote.border": r.border,
        "textCodeBlock.background": s.raised, "textSeparator.foreground": r.border,
        "toolbar.hoverBackground": s.hover, "toolbar.activeBackground": s.select,
        "toolbar.hoverOutline": "#00000000",
    })
    # Title bar, command center, menus
    add({
        "titleBar.activeBackground": s.chrome, "titleBar.activeForeground": t,
        "titleBar.inactiveBackground": s.chrome, "titleBar.inactiveForeground": r.muted,
        "titleBar.border": r.border_subtle,
        "commandCenter.background": s.raised, "commandCenter.foreground": r.muted,
        "commandCenter.activeBackground": s.hover, "commandCenter.activeForeground": t,
        "commandCenter.border": r.border, "commandCenter.activeBorder": r.border_strong,
        "commandCenter.inactiveForeground": r.muted, "commandCenter.inactiveBorder": r.border_subtle,
        "menu.background": s.float_, "menu.foreground": t, "menu.border": r.border_strong,
        "menu.selectionBackground": s.select, "menu.selectionForeground": t,
        "menu.separatorBackground": r.border,
        "menubar.selectionBackground": s.select, "menubar.selectionForeground": t,
    })
    # Activity bar
    add({
        "activityBar.background": s.chrome, "activityBar.foreground": t,
        "activityBar.inactiveForeground": r.muted, "activityBar.border": r.border_subtle,
        "activityBar.activeBorder": r.accent, "activityBar.activeFocusBorder": r.accent,
        "activityBar.dropBorder": r.accent,
        "activityBarBadge.background": r.accent_fill, "activityBarBadge.foreground": r.on_accent,
        "activityBarTop.foreground": t, "activityBarTop.inactiveForeground": r.muted,
        "activityBarTop.activeBorder": r.accent,
        "badge.background": r.accent_fill, "badge.foreground": r.on_accent,
    })
    # Side bar
    add({
        "sideBar.background": s.side, "sideBar.foreground": t, "sideBar.border": r.border,
        "sideBar.dropBackground": a(r.accent, 0.20),
        "sideBarTitle.foreground": t, "sideBarSectionHeader.background": s.header,
        "sideBarSectionHeader.foreground": t, "sideBarSectionHeader.border": r.border_subtle,
        "sideBarStickyScroll.background": s.side, "sideBarStickyScroll.border": r.border,
    })
    # Editor groups and tabs
    tab_hover = mix(s.tabs, s.editor, 0.5)
    add({
        "editorGroup.border": r.border, "editorGroup.dropBackground": a(r.accent, 0.18),
        "editorGroup.emptyBackground": s.editor,
        "editorGroupHeader.tabsBackground": s.tabs, "editorGroupHeader.tabsBorder": r.border_subtle,
        "editorGroupHeader.noTabsBackground": s.editor,
        "tab.activeBackground": s.editor, "tab.activeForeground": t,
        "tab.inactiveBackground": s.tabs, "tab.inactiveForeground": r.muted,
        "tab.border": r.border_subtle, "tab.activeBorder": s.editor,
        "tab.activeBorderTop": r.accent, "tab.unfocusedActiveBorderTop": r.border_strong,
        "tab.hoverBackground": tab_hover, "tab.hoverForeground": t,
        "tab.unfocusedActiveBackground": s.editor, "tab.unfocusedActiveForeground": r.muted,
        "tab.unfocusedInactiveBackground": s.tabs, "tab.unfocusedInactiveForeground": r.muted,
        "tab.unfocusedHoverBackground": tab_hover, "tab.unfocusedHoverForeground": t,
        "tab.activeModifiedBorder": r.warning, "tab.inactiveModifiedBorder": r.warning,
        "tab.unfocusedActiveModifiedBorder": r.warning, "tab.unfocusedInactiveModifiedBorder": r.warning,
        "tab.lastPinnedBorder": r.border_strong,
        "breadcrumb.foreground": r.muted, "breadcrumb.focusForeground": t,
        "breadcrumb.activeSelectionForeground": t, "breadcrumb.background": s.editor,
        "breadcrumbPicker.background": s.float_,
    })
    # Editor
    add({
        "editor.background": s.editor, "editor.foreground": t,
        "editorLineNumber.foreground": r.dim, "editorLineNumber.activeForeground": t,
        "editorLineNumber.dimmedForeground": r.dim,
        "editorCursor.foreground": r.accent, "editorMultiCursor.primary.foreground": r.accent,
        "editorMultiCursor.secondary.foreground": r.muted,
        "editor.selectionBackground": a(r.accent, sel_alpha),
        "editor.inactiveSelectionBackground": a(r.accent, 0.14),
        "editor.selectionHighlightBackground": a(r.accent, 0.16),
        "editor.wordHighlightBackground": a(t, 0.10), "editor.wordHighlightStrongBackground": a(t, 0.16),
        "editor.wordHighlightTextBackground": a(t, 0.10),
        "editor.findMatchBackground": a(r.warning, 0.45), "editor.findMatchBorder": r.warning,
        "editor.findMatchHighlightBackground": a(r.warning, 0.22),
        "editor.findRangeHighlightBackground": a(r.accent, 0.10),
        "editor.hoverHighlightBackground": a(r.accent, 0.14),
        "editor.lineHighlightBackground": line_hl, "editor.lineHighlightBorder": "#00000000",
        "editor.rangeHighlightBackground": a(r.accent, 0.08),
        "editor.symbolHighlightBackground": a(r.accent, 0.18),
        "editor.foldBackground": a(r.accent, 0.08), "editor.foldPlaceholderForeground": r.muted,
        "editor.snippetTabstopHighlightBackground": a(r.accent, 0.18),
        "editor.snippetFinalTabstopHighlightBorder": r.accent,
        "editor.linkedEditingBackground": a(r.accent, 0.12),
        "editor.compositionBorder": r.accent,
        "editorLink.activeForeground": r.accent,
        "editorWhitespace.foreground": a(t, 0.20 if light else 0.16),
        "editorIndentGuide.background1": r.border_subtle, "editorIndentGuide.activeBackground1": r.border_strong,
        "editorRuler.foreground": r.border_subtle,
        "editorCodeLens.foreground": r.dim, "editorInlayHint.foreground": r.muted,
        "editorInlayHint.background": mix(s.editor, t, 0.07),
        "editorInlayHint.typeForeground": r.muted, "editorInlayHint.parameterForeground": r.muted,
        "editorGhostText.foreground": a(t, 0.42),
        "editorGutter.background": s.editor,
        "editorGutter.modifiedBackground": gutter[0], "editorGutter.addedBackground": gutter[1],
        "editorGutter.deletedBackground": gutter[2],
        "editorGutter.commentRangeForeground": r.dim, "editorGutter.foldingControlForeground": r.muted,
        "editorBracketMatch.background": a(r.accent, 0.20), "editorBracketMatch.border": a(r.accent, 0.60),
        "editorError.foreground": r.error, "editorWarning.foreground": r.warning,
        "editorInfo.foreground": r.info, "editorHint.foreground": r.success,
        "editorLightBulb.foreground": r.warning, "editorLightBulbAutoFix.foreground": r.info,
        "editorUnnecessaryCode.opacity": "#000000a0",
        "editorUnicodeHighlight.border": r.warning,
        "editorStickyScroll.background": s.editor, "editorStickyScrollHover.background": s.hover,
        "editorStickyScroll.border": r.border, "editorStickyScroll.shadow": shadow,
        "editorOverviewRuler.border": "#00000000", "editorOverviewRuler.background": s.editor,
        "editorOverviewRuler.errorForeground": r.error, "editorOverviewRuler.warningForeground": r.warning,
        "editorOverviewRuler.infoForeground": r.info, "editorOverviewRuler.modifiedForeground": a(gutter[0], 0.8),
        "editorOverviewRuler.addedForeground": a(gutter[1], 0.8),
        "editorOverviewRuler.deletedForeground": a(gutter[2], 0.8),
        "editorOverviewRuler.findMatchForeground": a(r.warning, 0.7),
        "editorOverviewRuler.selectionHighlightForeground": a(r.accent, 0.7),
        "editorOverviewRuler.wordHighlightForeground": a(t, 0.4),
        "editorOverviewRuler.bracketMatchForeground": a(r.accent, 0.7),
        "editorOverviewRuler.rangeHighlightForeground": a(r.accent, 0.4),
        "editorActionList.background": s.float_, "editorActionList.foreground": t,
        "editorActionList.focusBackground": s.select, "editorActionList.focusForeground": t,
    })
    for index, color in enumerate(bracket, start=1):
        c[f"editorBracketHighlight.foreground{index}"] = color
        c[f"editorBracketPairGuide.background{index}"] = a(color, 0.28)
        c[f"editorBracketPairGuide.activeBackground{index}"] = a(color, 0.70)
    c["editorBracketHighlight.unexpectedBracket.foreground"] = r.error
    # Widgets, hover, suggest, peek, quick input
    add({
        "editorWidget.background": s.float_, "editorWidget.foreground": t,
        "editorWidget.border": r.border_strong, "editorWidget.resizeBorder": r.accent,
        "editorSuggestWidget.background": s.float_, "editorSuggestWidget.border": r.border_strong,
        "editorSuggestWidget.foreground": t, "editorSuggestWidget.selectedBackground": s.select,
        "editorSuggestWidget.selectedForeground": t, "editorSuggestWidget.highlightForeground": r.accent,
        "editorSuggestWidget.focusHighlightForeground": r.accent,
        "editorHoverWidget.background": s.float_, "editorHoverWidget.foreground": t,
        "editorHoverWidget.border": r.border_strong, "editorHoverWidget.highlightForeground": r.accent,
        "editorHoverWidget.statusBarBackground": s.hover,
        "peekView.border": r.accent, "peekViewEditor.background": s.side,
        "peekViewEditorGutter.background": s.side, "peekViewResult.background": s.chrome,
        "peekViewResult.selectionBackground": s.select, "peekViewResult.selectionForeground": t,
        "peekViewResult.lineForeground": t, "peekViewResult.fileForeground": t,
        "peekViewResult.matchHighlightBackground": a(r.warning, 0.35),
        "peekViewEditor.matchHighlightBackground": a(r.warning, 0.35),
        "peekViewTitle.background": s.tabs, "peekViewTitleLabel.foreground": t,
        "peekViewTitleDescription.foreground": r.muted,
        "quickInput.background": s.float_, "quickInput.foreground": t,
        "quickInputList.focusBackground": s.select, "quickInputList.focusForeground": t,
        "quickInputTitle.background": s.hover, "pickerGroup.foreground": r.accent,
        "pickerGroup.border": r.border,
        "keybindingLabel.background": s.raised, "keybindingLabel.foreground": t,
        "keybindingLabel.border": r.border_strong, "keybindingLabel.bottomBorder": r.border_strong,
    })
    # Inputs, buttons, checkboxes
    def validation(name: str, color: str) -> dict[str, str]:
        return {
            f"inputValidation.{name}Background": mix(s.raised, color, 0.16),
            f"inputValidation.{name}Border": color,
            f"inputValidation.{name}Foreground": t,
        }
    add({
        "input.background": s.raised, "input.foreground": t, "input.border": r.border_strong,
        "input.placeholderForeground": r.muted,
        "inputOption.activeBackground": a(r.accent, 0.25), "inputOption.activeBorder": r.accent,
        "inputOption.activeForeground": t, "inputOption.hoverBackground": s.hover,
        **validation("error", r.error), **validation("warning", r.warning), **validation("info", r.info),
        "dropdown.background": s.raised, "dropdown.foreground": t, "dropdown.border": r.border_strong,
        "dropdown.listBackground": s.float_,
        "button.background": r.accent_fill, "button.foreground": r.on_accent,
        "button.hoverBackground": accent_hover, "button.border": "#00000000",
        "button.separator": a(r.on_accent, 0.40),
        "button.secondaryBackground": s.select, "button.secondaryForeground": t,
        "button.secondaryHoverBackground": mix(s.select, t, 0.08),
        "checkbox.background": s.raised, "checkbox.border": r.border_strong,
        "checkbox.foreground": t, "checkbox.selectBackground": s.raised,
        "checkbox.selectBorder": r.accent,
        "progressBar.background": r.accent,
    })
    # Lists and trees
    add({
        "list.activeSelectionBackground": mix(s.side, r.accent, 0.20 if not light else 0.16),
        "list.activeSelectionForeground": t, "list.activeSelectionIconForeground": t,
        "list.inactiveSelectionBackground": s.select, "list.inactiveSelectionForeground": t,
        "list.inactiveSelectionIconForeground": t,
        "list.hoverBackground": s.hover, "list.hoverForeground": t,
        "list.focusBackground": mix(s.side, r.accent, 0.20 if not light else 0.16),
        "list.focusForeground": t, "list.focusOutline": r.accent,
        "list.focusAndSelectionOutline": r.accent, "list.inactiveFocusOutline": r.border_strong,
        "list.highlightForeground": r.accent, "list.focusHighlightForeground": r.accent,
        "list.invalidItemForeground": r.error, "list.errorForeground": r.error,
        "list.warningForeground": r.warning, "list.deemphasizedForeground": r.muted,
        "list.dropBackground": a(r.accent, 0.20),
        "list.filterMatchBackground": a(r.warning, 0.30), "list.filterMatchBorder": a(r.warning, 0.60),
        "tree.indentGuidesStroke": r.border, "tree.inactiveIndentGuidesStroke": r.border_subtle,
        "tree.tableColumnsBorder": r.border, "tree.tableOddRowsBackground": a(t, 0.03),
        "scrollbarSlider.background": a(t, 0.14), "scrollbarSlider.hoverBackground": a(t, 0.24),
        "scrollbarSlider.activeBackground": a(t, 0.34),
        "minimap.background": s.editor, "minimap.selectionHighlight": a(r.accent, 0.60),
        "minimap.selectionOccurrenceHighlight": a(t, 0.30),
        "minimap.findMatchHighlight": a(r.warning, 0.70), "minimap.errorHighlight": r.error,
        "minimap.warningHighlight": r.warning, "minimap.infoHighlight": r.info,
        "minimapSlider.background": a(t, 0.08), "minimapSlider.hoverBackground": a(t, 0.14),
        "minimapSlider.activeBackground": a(t, 0.20),
        "minimapGutter.addedBackground": gutter[1], "minimapGutter.modifiedBackground": gutter[0],
        "minimapGutter.deletedBackground": gutter[2],
    })
    # Status bar: neutral by default; filled accent only for remote sessions,
    # debugging and problem states.
    def fill(color: str) -> str:
        """A state color usable as a filled status item under on_accent text."""
        return fit(color, [r.on_accent], 4.5, direction=1 if luminance(r.on_accent) < 0.3 else -1)

    debug_bg = fill(r.syntax["number"])
    add({
        "statusBar.background": s.chrome, "statusBar.foreground": r.muted,
        "statusBar.border": r.border, "statusBar.focusBorder": r.accent,
        "statusBar.noFolderBackground": s.chrome, "statusBar.noFolderForeground": r.muted,
        "statusBar.noFolderBorder": r.border,
        "statusBar.debuggingBackground": debug_bg, "statusBar.debuggingForeground": r.on_accent,
        "statusBar.debuggingBorder": debug_bg,
        "statusBarItem.hoverBackground": mix(s.chrome, t, 0.10), "statusBarItem.hoverForeground": t,
        "statusBarItem.activeBackground": s.select,
        "statusBarItem.prominentBackground": s.raised, "statusBarItem.prominentForeground": t,
        "statusBarItem.prominentHoverBackground": s.hover,
        "statusBarItem.remoteBackground": r.accent_fill, "statusBarItem.remoteForeground": r.on_accent,
        "statusBarItem.remoteHoverBackground": accent_hover,
        "statusBarItem.errorBackground": fill(r.error),
        "statusBarItem.errorForeground": r.on_accent,
        "statusBarItem.warningBackground": fill(r.warning),
        "statusBarItem.warningForeground": r.on_accent,
        "statusBarItem.compactHoverBackground": s.hover,
    })
    # Panel and terminal
    add({
        "panel.background": s.side, "panel.border": r.border, "panel.dropBorder": r.accent,
        "panelTitle.activeBorder": r.accent, "panelTitle.activeForeground": t,
        "panelTitle.inactiveForeground": r.muted, "panelInput.border": r.border_strong,
        "panelSection.border": r.border, "panelSectionHeader.background": s.header,
        "panelStickyScroll.background": s.side,
        "terminal.background": terminal_bg, "terminal.foreground": t,
        "terminal.selectionBackground": a(r.accent, 0.30), "terminal.inactiveSelectionBackground": a(r.accent, 0.15),
        "terminalCursor.foreground": r.accent, "terminalCursor.background": terminal_bg,
        "terminal.findMatchBackground": a(r.warning, 0.50), "terminal.findMatchHighlightBackground": a(r.warning, 0.25),
        "terminal.border": r.border, "terminal.tab.activeBorder": r.accent,
        "terminal.dropBackground": a(r.accent, 0.18), "terminal.hoverHighlightBackground": a(r.accent, 0.12),
        "terminalCommandDecoration.defaultBackground": r.dim,
        "terminalCommandDecoration.successBackground": r.success,
        "terminalCommandDecoration.errorBackground": r.error,
        "terminalCommandGuide.foreground": r.border_strong,
        "terminal.ansiBlack": ansi_black, "terminal.ansiWhite": ansi_white,
        "terminal.ansiBrightBlack": r.muted, "terminal.ansiBrightWhite": t,
    })
    for name in ("red", "green", "yellow", "blue", "magenta", "cyan"):
        c[f"terminal.ansi{name.title()}"] = fit(ramp[name], [terminal_bg], 4.5)
        c[f"terminal.ansiBright{name.title()}"] = fit(
            ramp[f"bright{name.title()}"], [terminal_bg], 4.5)
    # Source control, diff, merge
    add({
        "gitDecoration.addedResourceForeground": r.success,
        "gitDecoration.modifiedResourceForeground": r.warning,
        "gitDecoration.deletedResourceForeground": r.error,
        "gitDecoration.renamedResourceForeground": git_renamed,
        "gitDecoration.untrackedResourceForeground": git_untracked,
        "gitDecoration.ignoredResourceForeground": r.dim,
        "gitDecoration.stageModifiedResourceForeground": r.warning,
        "gitDecoration.stageDeletedResourceForeground": r.error,
        "gitDecoration.conflictingResourceForeground": git_conflict,
        "gitDecoration.submoduleResourceForeground": r.info,
        "scmGraph.historyItemRefColor": r.accent, "scmGraph.historyItemRemoteRefColor": sym["keyword"],
        "scmGraph.historyItemBaseRefColor": sym["number"],
        "scmGraph.historyItemHoverAdditionsForeground": r.success,
        "scmGraph.historyItemHoverDeletionsForeground": r.error,
        "scmGraph.historyItemHoverDefaultLabelForeground": t,
        "scmGraph.foreground1": sym["decorator"], "scmGraph.foreground2": sym["keyword"],
        "scmGraph.foreground3": sym["type"], "scmGraph.foreground4": sym["string"],
        "scmGraph.foreground5": sym["function"],
        "diffEditor.insertedTextBackground": a(r.success, 0.22), "diffEditor.insertedLineBackground": a(r.success, 0.10),
        "diffEditor.removedTextBackground": a(r.error, 0.24), "diffEditor.removedLineBackground": a(r.error, 0.10),
        "diffEditor.diagonalFill": a(t, 0.10), "diffEditor.border": r.border,
        "diffEditor.unchangedRegionBackground": s.side, "diffEditor.unchangedRegionForeground": r.muted,
        "diffEditor.unchangedCodeBackground": a(t, 0.04),
        "diffEditor.move.border": a(r.info, 0.60), "diffEditor.moveActive.border": r.info,
        "diffEditorGutter.insertedLineBackground": a(r.success, 0.18),
        "diffEditorGutter.removedLineBackground": a(r.error, 0.18),
        "diffEditorOverview.insertedForeground": a(r.success, 0.60),
        "diffEditorOverview.removedForeground": a(r.error, 0.60),
        "multiDiffEditor.background": s.editor, "multiDiffEditor.headerBackground": s.tabs,
        "multiDiffEditor.border": r.border,
        "merge.currentHeaderBackground": a(r.info, 0.40), "merge.currentContentBackground": a(r.info, 0.18),
        "merge.incomingHeaderBackground": a(r.success, 0.40), "merge.incomingContentBackground": a(r.success, 0.18),
        "merge.commonHeaderBackground": a(r.muted, 0.35), "merge.commonContentBackground": a(r.muted, 0.16),
        "merge.border": r.border_strong,
        "editorOverviewRuler.currentContentForeground": a(r.info, 0.70),
        "editorOverviewRuler.incomingContentForeground": a(r.success, 0.70),
        "editorOverviewRuler.commonContentForeground": a(r.muted, 0.50),
        "mergeEditor.change.background": a(r.success, 0.18), "mergeEditor.change.word.background": a(r.success, 0.30),
        "mergeEditor.conflict.unhandledUnfocused.border": a(r.warning, 0.60),
        "mergeEditor.conflict.unhandledFocused.border": r.warning,
        "mergeEditor.conflict.handledUnfocused.border": a(r.success, 0.50),
        "mergeEditor.conflict.handledFocused.border": r.success,
        "mergeEditor.conflict.input1.background": a(r.info, 0.18),
        "mergeEditor.conflict.input2.background": a(r.success, 0.18),
    })
    # Notifications, banners, extensions, settings, welcome
    add({
        "notifications.background": s.float_, "notifications.foreground": t,
        "notifications.border": r.border_strong,
        "notificationCenter.border": r.border_strong, "notificationToast.border": r.border_strong,
        "notificationCenterHeader.background": s.hover, "notificationCenterHeader.foreground": t,
        "notificationLink.foreground": r.accent,
        "notificationsErrorIcon.foreground": r.error, "notificationsWarningIcon.foreground": r.warning,
        "notificationsInfoIcon.foreground": r.info,
        "banner.background": s.raised, "banner.foreground": t, "banner.iconForeground": r.info,
        "problemsErrorIcon.foreground": r.error, "problemsWarningIcon.foreground": r.warning,
        "problemsInfoIcon.foreground": r.info,
        "extensionButton.prominentBackground": r.accent_fill, "extensionButton.prominentForeground": r.on_accent,
        "extensionButton.prominentHoverBackground": accent_hover,
        "extensionButton.background": s.select, "extensionButton.foreground": t,
        "extensionButton.hoverBackground": mix(s.select, t, 0.08),
        "extensionBadge.remoteBackground": r.accent_fill, "extensionBadge.remoteForeground": r.on_accent,
        "extensionIcon.starForeground": r.warning, "extensionIcon.verifiedForeground": r.info,
        "extensionIcon.preReleaseForeground": sym["number"], "extensionIcon.sponsorForeground": sym["keyword"],
        "settings.headerForeground": t, "settings.modifiedItemIndicator": r.accent,
        "settings.dropdownBackground": s.raised, "settings.dropdownBorder": r.border_strong,
        "settings.dropdownForeground": t, "settings.checkboxBackground": s.raised,
        "settings.checkboxBorder": r.border_strong, "settings.checkboxForeground": t,
        "settings.textInputBackground": s.raised, "settings.textInputBorder": r.border_strong,
        "settings.textInputForeground": t, "settings.numberInputBackground": s.raised,
        "settings.numberInputBorder": r.border_strong, "settings.numberInputForeground": t,
        "settings.focusedRowBackground": a(r.accent, 0.06), "settings.focusedRowBorder": a(r.accent, 0.60),
        "settings.rowHoverBackground": a(t, 0.04), "settings.headerBorder": r.border,
        "settings.sashBorder": r.border,
        "welcomePage.background": s.editor, "welcomePage.tileBackground": s.raised,
        "welcomePage.tileHoverBackground": s.hover, "welcomePage.tileBorder": r.border,
        "welcomePage.progress.background": s.raised, "welcomePage.progress.foreground": r.accent,
        "walkThrough.embeddedEditorBackground": s.side,
    })
    # Debug and testing
    add({
        "debugToolBar.background": s.float_, "debugToolBar.border": r.border_strong,
        "debugIcon.breakpointForeground": r.error, "debugIcon.breakpointDisabledForeground": r.dim,
        "debugIcon.breakpointUnverifiedForeground": r.dim, "debugIcon.breakpointCurrentStackframeForeground": r.warning,
        "debugIcon.breakpointStackframeForeground": r.success,
        "debugIcon.startForeground": r.success, "debugIcon.pauseForeground": r.warning,
        "debugIcon.stopForeground": r.error, "debugIcon.disconnectForeground": r.error,
        "debugIcon.restartForeground": r.success, "debugIcon.stepOverForeground": r.info,
        "debugIcon.stepIntoForeground": r.info, "debugIcon.stepOutForeground": r.info,
        "debugIcon.stepBackForeground": r.info, "debugIcon.continueForeground": r.info,
        "debugConsole.errorForeground": r.error, "debugConsole.infoForeground": r.info,
        "debugConsole.sourceForeground": r.muted, "debugConsole.warningForeground": r.warning,
        "debugConsoleInputIcon.foreground": r.accent,
        "editor.stackFrameHighlightBackground": a(r.warning, 0.20),
        "editor.focusedStackFrameHighlightBackground": a(r.success, 0.20),
        "debugTokenExpression.name": sym["property"], "debugTokenExpression.value": sym["string"],
        "debugTokenExpression.string": sym["string"], "debugTokenExpression.number": sym["number"],
        "debugTokenExpression.boolean": sym["keyword"], "debugTokenExpression.error": r.error,
        "debugView.stateLabelForeground": r.muted, "debugView.stateLabelBackground": s.raised,
        "debugView.valueChangedHighlight": r.accent, "editor.inlineValuesForeground": r.dim,
        "testing.iconPassed": r.success, "testing.iconFailed": r.error, "testing.iconErrored": r.error,
        "testing.iconQueued": r.warning, "testing.iconUnset": r.dim, "testing.iconSkipped": r.dim,
        "testing.runAction": r.success,
        "testing.message.error.lineBackground": a(r.error, 0.12),
        "testing.peekBorder": r.error, "testing.peekHeaderBackground": a(r.error, 0.10),
        "testing.coveredBackground": a(r.success, 0.15), "testing.uncoveredBackground": a(r.error, 0.15),
        "testing.uncoveredBranchBackground": a(r.warning, 0.20),
        "testing.coveredGutterBackground": a(r.success, 0.60), "testing.uncoveredGutterBackground": a(r.error, 0.60),
        "testing.coverCountBadgeBackground": s.raised, "testing.coverCountBadgeForeground": t,
    })
    # Symbol icons follow the syntax roles
    symbol_map = {
        "array": "type", "boolean": "number", "class": "type", "constant": "number",
        "constructor": "function", "enumerator": "type", "enumeratorMember": "number",
        "event": "number", "field": "property", "function": "function", "interface": "type",
        "key": "property", "keyword": "keyword", "method": "function", "module": "type",
        "namespace": "type", "null": "number", "number": "number", "object": "type",
        "operator": "operator", "package": "type", "property": "property", "string": "string",
        "struct": "type", "typeParameter": "type", "unit": "number", "variable": "variable",
    }
    for name, role in symbol_map.items():
        c[f"symbolIcon.{name}Foreground"] = sym[role]
    for name in ("file", "folder", "reference", "snippet", "text", "color"):
        c[f"symbolIcon.{name}Foreground"] = r.muted if name != "text" else t
    # Chat and agent surfaces, charts, notebooks, ErrorLens (extension colors)
    add({
        "chat.requestBackground": s.side, "chat.requestBorder": r.border,
        "chat.requestBubbleBackground": s.raised, "chat.requestBubbleHoverBackground": s.hover,
        "chat.slashCommandBackground": slash_bg, "chat.slashCommandForeground": slash_fg,
        "chat.avatarBackground": s.raised, "chat.avatarForeground": t,
        "chat.editedFileForeground": r.warning, "chat.linesAddedForeground": r.success,
        "chat.linesRemovedForeground": r.error, "chat.checkpointSeparator": r.border,
        "inlineChat.background": s.float_, "inlineChat.border": r.border_strong,
        "inlineChat.foreground": t, "inlineChat.shadow": shadow,
        "inlineChatInput.background": s.raised, "inlineChatInput.border": r.border_strong,
        "inlineChatInput.focusBorder": r.accent, "inlineChatInput.placeholderForeground": r.muted,
        "inlineChatDiff.inserted": a(r.success, 0.20), "inlineChatDiff.removed": a(r.error, 0.20),
        "charts.foreground": t, "charts.lines": r.muted, "charts.red": r.error, "charts.blue": r.info,
        "charts.yellow": r.warning, "charts.orange": sym["number"], "charts.green": r.success,
        "charts.purple": sym["keyword"],
        "notebook.cellBorderColor": r.border, "notebook.focusedCellBorder": r.accent,
        "notebook.focusedEditorBorder": r.accent, "notebook.cellEditorBackground": s.editor,
        "notebook.editorBackground": s.editor, "notebook.cellHoverBackground": s.hover,
        "notebook.selectedCellBackground": s.hover, "notebookStatusSuccessIcon.foreground": r.success,
        "notebookStatusErrorIcon.foreground": r.error, "notebookStatusRunningIcon.foreground": r.accent,
        "errorLens.errorBackground": a(r.error, 0.10), "errorLens.errorForeground": r.error,
        "errorLens.warningBackground": a(r.warning, 0.10), "errorLens.warningForeground": r.warning,
        "errorLens.infoBackground": a(r.info, 0.10), "errorLens.infoForeground": r.info,
        "errorLens.hintBackground": a(r.success, 0.10), "errorLens.hintForeground": r.success,
        "errorLens.statusBarErrorForeground": r.error, "errorLens.statusBarWarningForeground": r.warning,
        "errorLens.statusBarInfoForeground": r.info, "errorLens.statusBarHintForeground": r.success,
    })
    return c


def build_token_colors(r: Roles) -> list[dict]:
    sy = r.syntax
    rules: list[tuple[list[str], str, str]] = [
        (["comment", "punctuation.definition.comment"], sy["comment"], "italic"),
        (["comment.block.documentation", "comment.documentation"], mix(sy["comment"], r.text, 0.25), "italic"),
        (["keyword", "keyword.control", "storage", "storage.type", "storage.modifier",
          "keyword.operator.new", "keyword.operator.expression", "keyword.operator.word",
          "keyword.operator.logical.python", "keyword.other", "variable.language",
          "constant.language.import-export-all", "keyword.control.import"], sy["keyword"], ""),
        (["keyword.operator", "keyword.operator.assignment", "keyword.operator.arithmetic",
          "keyword.operator.comparison", "keyword.operator.logical", "punctuation.accessor"], sy["operator"], ""),
        (["punctuation", "meta.brace", "punctuation.separator", "punctuation.terminator",
          "punctuation.definition.block", "punctuation.definition.parameters",
          "punctuation.definition.arguments", "punctuation.section"], sy["punctuation"], ""),
        (["entity.name.function", "support.function", "meta.function-call", "variable.function",
          "entity.name.function.member", "support.function.builtin", "entity.name.command"], sy["function"], ""),
        (["entity.name.type", "entity.name.class", "entity.name.namespace", "entity.other.inherited-class",
          "support.class", "support.type", "support.type.primitive", "storage.type.primitive",
          "storage.type.core.rust", "keyword.type", "meta.type", "entity.name.type.alias"], sy["type"], ""),
        (["string", "string.quoted", "punctuation.definition.string", "string.template",
          "markup.inline.raw", "markup.fenced_code.block", "markup.raw.block"], sy["string"], ""),
        (["string.regexp", "constant.character.escape", "constant.other.character-class.regexp",
          "keyword.operator.quantifier.regexp"], sy["escape"], ""),
        (["constant.numeric", "constant.language", "constant.other", "support.constant",
          "keyword.other.unit", "constant.character", "variable.other.constant",
          "variable.other.enummember"], sy["number"], ""),
        (["variable", "variable.other", "meta.definition.variable", "punctuation.definition.variable"],
         sy["variable"], ""),
        (["variable.parameter", "meta.parameter", "variable.parameter.function"], sy["parameter"], ""),
        (["variable.other.property", "variable.other.object.property", "support.variable.property",
          "meta.object-literal.key", "support.type.property-name", "entity.name.tag.yaml",
          "entity.name.tag.toml", "support.type.property-name.css", "variable.other.member"], sy["property"], ""),
        (["entity.name.tag", "punctuation.definition.tag", "entity.name.tag.css"], sy["tag"], ""),
        (["entity.other.attribute-name", "entity.other.attribute-name.html"], sy["decorator"], ""),
        (["entity.other.attribute-name.class.css", "entity.other.attribute-name.id.css",
          "support.class.component"], sy["type"], ""),
        (["meta.decorator", "entity.name.function.decorator", "punctuation.decorator",
          "storage.type.annotation", "meta.attribute.rust", "entity.name.function.macro",
          "support.function.macro", "entity.name.lifetime.rust", "storage.modifier.lifetime.rust",
          "meta.annotation", "entity.name.function.preprocessor"], sy["decorator"], ""),
        (["markup.heading", "entity.name.section", "markup.heading.setext"], sy["function"], "bold"),
        (["markup.bold"], r.text, "bold"),
        (["markup.italic"], r.text, "italic"),
        (["markup.underline.link", "string.other.link", "markup.underline"], r.accent, "underline"),
        (["markup.quote"], sy["comment"], "italic"),
        (["punctuation.definition.list", "markup.list"], sy["decorator"], ""),
        (["markup.inserted", "meta.diff.header.to-file"], r.success, ""),
        (["markup.deleted", "meta.diff.header.from-file"], r.error, ""),
        (["markup.changed", "meta.diff.range"], r.warning, ""),
        (["invalid", "invalid.illegal"], r.error, "underline"),
        (["invalid.deprecated"], r.warning, "strikethrough"),
    ]
    out = []
    for scopes, color, style in rules:
        settings = {"foreground": color}
        if style:
            settings["fontStyle"] = style
        out.append({"scope": scopes, "settings": settings})
    return out


def build_semantic_tokens(r: Roles) -> dict:
    sy = r.syntax
    mapping = {
        "namespace": sy["type"], "type": sy["type"], "class": sy["type"], "enum": sy["type"],
        "interface": sy["type"], "struct": sy["type"], "typeParameter": sy["type"],
        "function": sy["function"], "method": sy["function"], "macro": sy["decorator"],
        "decorator": sy["decorator"], "variable": sy["variable"], "parameter": sy["parameter"],
        "property": sy["property"], "enumMember": sy["number"], "event": sy["number"],
        "string": sy["string"], "number": sy["number"], "regexp": sy["escape"],
        "operator": sy["operator"], "keyword": sy["keyword"], "comment": sy["comment"],
        "lifetime": sy["decorator"], "selfKeyword": sy["keyword"], "boolean": sy["number"],
    }
    out: dict[str, object] = dict(mapping)
    out["variable.defaultLibrary"] = sy["type"]
    out["*.deprecated"] = {"strikethrough": True}
    out["comment"] = {"foreground": sy["comment"], "italic": True}
    return out


def build_theme(data: dict) -> tuple[dict, dict]:
    """Return (theme, report). Raises PaletteError for unusable palettes."""
    p = load_palette(data)
    r = build_roles(p)
    theme = {
        "$schema": "vscode://schemas/color-theme",
        "name": THEME_NAME,
        "type": p.mode,
        "semanticHighlighting": True,
        "colors": build_colors(p, r),
        "tokenColors": build_token_colors(r),
        "semanticTokenColors": build_semantic_tokens(r),
    }
    return theme, r.report


# ── validation of the emitted theme ──────────────────────────────────────────

REQUIRED_KEYS = (
    "editor.background", "editor.foreground", "sideBar.background", "activityBar.background",
    "statusBar.background", "statusBar.foreground", "titleBar.activeBackground", "tab.activeBackground",
    "tab.inactiveBackground", "panel.background", "terminal.background", "terminal.foreground",
    "list.activeSelectionBackground", "focusBorder", "button.background", "input.background",
)

PROBE_SCOPES = {
    "keyword": "keyword.control", "function": "entity.name.function", "string": "string",
    "number": "constant.numeric", "type": "entity.name.type", "tag": "entity.name.tag",
    "decorator": "meta.decorator",
}
SEPARATION_FLOOR = 25.0
SURFACE_STEP_FLOOR = {  # (key, key): minimum OKLCH lightness difference
    ("editor.background", "sideBar.background"): 0.030,
    ("editor.background", "activityBar.background"): 0.040,
    ("editor.background", "editorGroupHeader.tabsBackground"): 0.025,
    ("editor.background", "statusBar.background"): 0.040,
}


def _flat(color: str, base: str) -> str:
    return composite(color, base) if len(color) == 9 else color


ANSI_NAMES = tuple(
    prefix + name for prefix in ("", "Bright")
    for name in ("Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"))
# Foreground/background pairs that cannot be discovered from key names.
EXTRA_TEXT_PAIRS = (
    ("button.foreground", "button.hoverBackground"),
    ("button.secondaryForeground", "button.secondaryBackground"),
    ("button.secondaryForeground", "button.secondaryHoverBackground"),
    ("extensionButton.prominentForeground", "extensionButton.prominentBackground"),
    ("extensionButton.prominentForeground", "extensionButton.prominentHoverBackground"),
    ("extensionButton.foreground", "extensionButton.background"),
    ("extensionButton.foreground", "extensionButton.hoverBackground"),
    ("statusBarItem.remoteForeground", "statusBarItem.remoteHoverBackground"),
    ("statusBarItem.errorForeground", "statusBarItem.errorBackground"),
    ("statusBarItem.warningForeground", "statusBarItem.warningBackground"),
    ("sideBar.foreground", "sideBar.background"),
    ("editor.foreground", "editor.lineHighlightBackground"),
    ("tab.activeForeground", "tab.activeBackground"),
    ("tab.inactiveForeground", "tab.inactiveBackground"),
    ("tab.hoverForeground", "tab.hoverBackground"),
    ("titleBar.activeForeground", "titleBar.activeBackground"),
    ("titleBar.inactiveForeground", "titleBar.inactiveBackground"),
    ("activityBar.foreground", "activityBar.background"),
    ("activityBar.inactiveForeground", "activityBar.background"),
    ("panelTitle.activeForeground", "panel.background"),
    ("panelTitle.inactiveForeground", "panel.background"),
    ("editorLineNumber.activeForeground", "editor.background"),
    ("input.placeholderForeground", "input.background"),
    ("list.hoverForeground", "list.hoverBackground"),
)
# Pairs whose foreground is decorative or intentionally faint, so a text floor
# does not apply (ghost text, inlay hints are measured separately below).
TEXT_PAIR_EXEMPT = {"editorGhostText.foreground", "editorInlayHint.foreground"}


def text_pairs(colors: dict[str, str]):
    """Yield (foreground, background) keys: sibling names plus explicit pairs."""
    seen = set()
    for key in colors:
        match = re.match(r"^(.*?)(\.foreground|Foreground)$", key)
        if not match or key in TEXT_PAIR_EXEMPT:
            continue
        bg = match.group(1) + (".background" if match.group(2) == ".foreground" else "Background")
        if bg in colors and (key, bg) not in seen:
            seen.add((key, bg))
            yield key, bg
    for pair in EXTRA_TEXT_PAIRS:
        if pair[0] in colors and pair[1] in colors and pair not in seen:
            seen.add(pair)
            yield pair


def token_foregrounds(theme: dict) -> dict[str, str]:
    """scope -> foreground for every rule scope (first definition wins)."""
    found: dict[str, str] = {}
    for rule in theme.get("tokenColors", []):
        fg = rule.get("settings", {}).get("foreground")
        scopes = rule.get("scope", [])
        for scope in [scopes] if isinstance(scopes, str) else scopes:
            if fg and scope not in found:
                found[scope] = fg
    return found


def validate_theme(theme: dict) -> list[str]:
    """Check the emitted theme itself; an empty list means it may be written."""
    problems: list[str] = []
    colors = theme.get("colors")
    if not isinstance(colors, dict) or not colors:
        return ["theme has no colors"]
    for key, value in colors.items():
        if not isinstance(value, str) or not HEX_ANY.match(value):
            problems.append(f"colors[{key}] is not a hex color: {value!r}")
    for key in REQUIRED_KEYS:
        if key not in colors:
            problems.append(f"missing required color {key}")
    if problems:
        return problems
    tokens = theme.get("tokenColors") or []
    if not tokens:
        problems.append("tokenColors is empty")
    semantic = theme.get("semanticTokenColors") or {}
    if not semantic:
        problems.append("semanticTokenColors is empty")

    editor = colors["editor.background"]
    light = theme.get("type") == "light"

    def need(label: str, fg: str, bg: str, floor: float) -> None:
        bg_flat = _flat(bg, editor)
        ratio = contrast(_flat(fg, bg_flat), bg_flat)
        if ratio < floor:
            problems.append(f"{label}: {ratio:.2f}:1 < {floor}:1 ({fg} on {bg})")

    need("editor text", colors["editor.foreground"], editor, 7.0)
    for fg, bg in text_pairs(colors):
        need(fg, colors[fg], colors[bg], 4.5)
    side = colors["sideBar.background"]
    for key in ("list.activeSelectionBackground", "list.inactiveSelectionBackground", "list.hoverBackground"):
        need(f"text on {key}", colors["sideBar.foreground"], _flat(colors[key], side), 4.5)
    need("text on editor selection", colors["editor.foreground"],
         _flat(colors["editor.selectionBackground"], editor), 4.5)
    for key in ("gitDecoration.addedResourceForeground", "gitDecoration.modifiedResourceForeground",
                "gitDecoration.deletedResourceForeground", "gitDecoration.untrackedResourceForeground",
                "gitDecoration.conflictingResourceForeground", "gitDecoration.renamedResourceForeground"):
        need(key, colors[key], side, 4.5)
    for name in ANSI_NAMES:  # all 16 slots: programs print with every one of them
        need(f"terminal.ansi{name}", colors[f"terminal.ansi{name}"], colors["terminal.background"], 4.5)
    for key in ("editorError.foreground", "editorWarning.foreground", "editorInfo.foreground"):
        need(key, colors[key], editor, 4.5)
    need("focusBorder", colors["focusBorder"], editor, 3.0)
    need("editor line numbers", colors["editorLineNumber.foreground"], editor, 3.0)

    # Syntax and semantic tokens, measured on the emitted values.
    for scope, fg in token_foregrounds(theme).items():
        floor = 3.5 if "comment" in scope or scope.startswith("markup.quote") else 4.5
        need(f"token {scope}", fg, editor, floor)
        need(f"token {scope} (side bar)", fg, side, floor - 0.5)
    for token, value in semantic.items():
        fg = value if isinstance(value, str) else value.get("foreground") if isinstance(value, dict) else None
        if fg:
            need(f"semantic {token}", fg, editor, 3.5 if token == "comment" else 4.5)

    # Syntax roles must stay distinguishable by hue, not by lightness alone.
    foregrounds = token_foregrounds(theme)
    probes = {role: foregrounds.get(scope) for role, scope in PROBE_SCOPES.items()}
    hues = {}
    for role, color in probes.items():
        if color is None:
            problems.append(f"no syntax color for probe scope {PROBE_SCOPES[role]}")
            continue
        _, chroma, hue = to_oklch(color)
        if chroma < 0.04:
            problems.append(f"syntax role {role} is nearly achromatic ({color})")
        hues[role] = hue
    names = sorted(hues)
    for i, first in enumerate(names):
        for second in names[i + 1:]:
            if hue_dist(hues[first], hues[second]) < SEPARATION_FLOOR:
                problems.append(
                    f"syntax hues {first}/{second} only {hue_dist(hues[first], hues[second]):.0f} degrees apart")

    # Regions must read as separate without relying on borders.
    for (a, b), floor in SURFACE_STEP_FLOOR.items():
        if a in colors and b in colors:
            diff = abs(to_oklch(colors[a])[0] - to_oklch(colors[b])[0])
            if diff < floor:
                problems.append(f"surfaces {a} / {b} differ by only {diff:.3f} lightness (< {floor})")
    # Borders: visible but subordinate to the surface steps.
    need("sideBar.border", colors["sideBar.border"], editor, 1.3)
    need("input.border", colors["input.border"], colors["input.background"], 1.8)
    if light and contrast(editor, "#ffffff") > 1.15:
        problems.append("light theme editor background is not close to white")
    return problems


# ── output ───────────────────────────────────────────────────────────────────


def render(theme: dict) -> str:
    return json.dumps(theme, indent=2, ensure_ascii=False) + "\n"


def package_json(mode: str) -> str:
    return json.dumps({
        "name": "noxflow-dynamic-theme",
        "displayName": "NoxFlow Dynamic Theme",
        "version": "0.0.1",
        "publisher": "noxflow",
        "engines": {"vscode": ">=1.80.0"},
        "contributes": {"themes": [{
            "label": THEME_NAME,
            "uiTheme": "vs-light" if mode == "light" else "vs-dark",
            "path": f"./themes/{THEME_FILE}",
        }]},
    }, indent=2) + "\n"


def write_group(files: list[tuple[Path, str]]) -> str | None:
    """Write several files all-or-nothing; return an error message or None.

    Every changed file is staged beside its target first, so a failure while
    staging (permissions, full disk) leaves every target untouched. Unchanged
    files are skipped so VS Code is not told about no-op rewrites.
    """
    staged: list[tuple[Path, Path]] = []
    try:
        for path, content in files:
            try:
                if path.read_text(encoding="utf-8") == content:
                    continue
            except FileNotFoundError:
                pass
            path.parent.mkdir(parents=True, exist_ok=True)
            tmp = path.with_name(f".{path.name}.tmp")
            staged.append((tmp, path))
            tmp.write_text(content, encoding="utf-8")
        for tmp, path in staged:
            os.replace(tmp, path)
    except OSError as error:
        for tmp, _ in staged:
            tmp.unlink(missing_ok=True)
        return str(error)
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("palette", type=Path)
    parser.add_argument("--cache", type=Path, help="write the theme JSON here")
    parser.add_argument("--extension-dir", type=Path, help="install as a VS Code extension here")
    args = parser.parse_args(argv)

    try:
        data = json.loads(args.palette.read_text(encoding="utf-8"))
        theme, _ = build_theme(data)
    except (OSError, json.JSONDecodeError, PaletteError) as error:
        print(f"vscode-theme: {error}", file=sys.stderr)
        return 1
    problems = validate_theme(theme)
    if problems:
        print("vscode-theme: refusing to write an invalid theme; keeping the previous one:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    content = render(theme)
    if not args.cache and not args.extension_dir:
        sys.stdout.write(content)
        return 0
    # The cache copy and the installed extension are independent outputs; one
    # failing must not block the other. Within the extension the theme and its
    # package.json are written together, so uiTheme never lags the colors.
    groups: list[tuple[str, list[tuple[Path, str]]]] = []
    if args.cache:
        groups.append(("cache", [(args.cache, content)]))
    if args.extension_dir:
        groups.append(("extension", [
            (args.extension_dir / "themes" / THEME_FILE, content),
            (args.extension_dir / "package.json", package_json(theme["type"])),
        ]))
    failed = False
    for name, files in groups:
        error = write_group(files)
        if error:
            failed = True
            print(f"vscode-theme: could not write the {name}: {error}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

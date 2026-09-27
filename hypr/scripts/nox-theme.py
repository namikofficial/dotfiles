#!/usr/bin/env python3
"""Deterministic wallpaper-to-theme compiler used by NoxFlow.

Uses OKLCH internally for perceptually uniform color operations. Accepts an
optional theme-policy.toml to override personality, chroma, contrast, and
individual color assignments. Produces a versioned JSON palette compatible with
the nox-theme-schema-v1 contract.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
import tomllib
from pathlib import Path
from typing import Optional

from PIL import Image, ImageEnhance

SCHEMA = "nox-theme-schema-v1"
POLICY_VERSION = "nox-policy-2"

# ── OKLCH / OKLAB CONVERSION ─────────────────────────────────────────────────

# Pre-computed sRGB-to-Linear table for fast channel conversion.
def _srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _linear_to_srgb(c: float) -> float:
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1.0 / 2.4)) - 0.055


def rgb_to_oklch(r: int, g: int, b: int) -> tuple[float, float, float]:
    """Convert sRGB (0-255) to OKLCH (L: 0-1, C: 0-0.4+, H: 0-360)."""
    r, g, b = (x / 255.0 for x in (r, g, b))
    lr, lg, lb = _srgb_to_linear(r), _srgb_to_linear(g), _srgb_to_linear(b)

    l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
    m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
    s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb

    l_ = l ** (1.0 / 3.0)
    m_ = m ** (1.0 / 3.0)
    s_ = s ** (1.0 / 3.0)

    L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
    a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
    b_val = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_

    L = max(0.0, L)
    C = math.sqrt(a * a + b_val * b_val)
    H = math.degrees(math.atan2(b_val, a)) % 360.0
    return (L, C, H)


def oklch_to_rgb(L: float, C: float, H: float) -> tuple[int, int, int]:
    """Convert OKLCH (L: 0-1, C: 0-0.4+, H: 0-360) to sRGB (0-255) with gamut clip."""
    H_rad = math.radians(H)
    a = C * math.cos(H_rad)
    b_val = C * math.sin(H_rad)

    l_ = L + 0.3963377774 * a + 0.2158037573 * b_val
    m_ = L - 0.1055613458 * a - 0.0638541728 * b_val
    s_ = L - 0.0894841775 * a - 1.2914855480 * b_val

    l = l_ * l_ * l_
    m = m_ * m_ * m_
    s = s_ * s_ * s_

    r = +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    b_rgb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

    r = max(0.0, min(1.0, r))
    g = max(0.0, min(1.0, g))
    b_rgb = max(0.0, min(1.0, b_rgb))

    return (
        round(_linear_to_srgb(r) * 255),
        round(_linear_to_srgb(g) * 255),
        round(_linear_to_srgb(b_rgb) * 255),
    )


def oklch_blend(base: tuple[float, float, float], overlay: tuple[float, float, float], amount: float) -> tuple[float, float, float]:
    """Blend two OKLCH colors perceptually (interpolates in OKLCH space)."""
    L1, C1, H1 = base
    L2, C2, H2 = overlay
    # Interpolate L and C directly; interpolate H on the shortest arc.
    delta_h = ((H2 - H1 + 180) % 360) - 180
    return (
        L1 + (L2 - L1) * amount,
        C1 + (C2 - C1) * amount,
        (H1 + delta_h * amount) % 360,
    )


def oklch_lift_lightness(L: float, target_L: float, amount: float = 0.08) -> float:
    """Move L toward target by a fixed perceptual step amount."""
    if L < target_L:
        return min(target_L, L + amount)
    return max(target_L, L - amount)


def oklch_lightness_scale(L: float, factor: float) -> float:
    """Scale lightness perceptually: factor > 1 brightens, < 1 darkens."""
    if factor >= 1.0:
        # Exponential approach to 1.0 for brightening.
        return 1.0 - (1.0 - L) * (1.0 / factor)
    else:
        # Exponential approach to 0 for darkening.
        return L * factor


def clamp_chroma(L: float, C: float, H: float, max_c: float = 0.4) -> tuple[float, float, float]:
    """Clamp chroma to prevent out-of-gamut sRGB; reduces C until RGB is in range."""
    C = min(C, max_c)
    for _ in range(24):
        rgb = oklch_to_rgb(L, C, H)
        if all(0 <= v <= 255 for v in rgb):
            return (L, C, H)
        C *= 0.88
    # Last resort: return achromatic.
    return (L, 0.0, H)


def rgb_lightness(r: int, g: int, b: int) -> float:
    """Relative luminance via IEC 61966-2-1."""
    def ch(x: int) -> float:
        x /= 255.0
        return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast_ratio(rgb1: tuple[int, int, int], rgb2: tuple[int, int, int]) -> float:
    """WCAG contrast ratio between two sRGB colors."""
    l1, l2 = sorted([rgb_lightness(*rgb1), rgb_lightness(*rgb2)], reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)


def hex_rgb(rgb: tuple[int, int, int]) -> str:
    return "#%02x%02x%02x" % rgb


def oklch_to_hex(L: float, C: float, H: float) -> str:
    return hex_rgb(oklch_to_rgb(L, C, H))


def hue_dist(deg1: float, deg2: float) -> float:
    d = abs(deg1 - deg2) % 360
    return min(d, 360 - d)


# ── POLICY ───────────────────────────────────────────────────────────────────

DEFAULT_POLICY: dict = {}


def load_policy() -> dict:
    """Load optional theme-policy.toml from the usual config locations."""
    candidates = [
        Path.home() / ".config" / "noxflow" / "theme-policy.toml",
        Path.home() / ".config" / "noxflow" / "config.toml",  # may contain [theme] table
    ]
    data: dict = {}
    for path in candidates:
        if path.exists():
            try:
                raw = path.read_text(encoding="utf-8")
                parsed = tomllib.loads(raw)
                if "theme" in parsed:
                    data.update(parsed["theme"])
                    if "tint" in parsed.get("surface", {}):
                        data["surface_tint"] = parsed["surface"]["tint"]
                    accent = parsed.get("accent", {})
                    overrides = dict(parsed.get("overrides", {}))
                    for source, target in (
                        ("primary_override", "primary"),
                        ("secondary_override", "secondary"),
                        ("tertiary_override", "tertiary"),
                    ):
                        value = accent.get(source)
                        if isinstance(value, str) and value.startswith("#"):
                            overrides[target] = value
                    if overrides:
                        data["overrides"] = overrides
                elif parsed:
                    data.update(parsed)
            except Exception:
                pass
            break
    return data


def personality_from_policy(policy: dict, entries: list[dict], entropy: float) -> dict:
    """Classify wallpaper personality from image analysis + optional policy override."""
    avg_chroma = sum(float(e["chroma"]) * float(e["fraction"]) for e in entries)
    avg_lum = sum(float(e["lum"]) * float(e["fraction"]) for e in entries)
    max_chroma = max((float(e["chroma"]) for e in entries), default=0.0)
    max_lum = max((float(e["lum"]) for e in entries), default=0.0)

    mode_override = policy.get("mode", "auto")
    personality_override = policy.get("personality", "auto")

    if personality_override != "auto":
        personality_class = personality_override
    elif avg_lum < 0.12 and max_chroma > 0.20:
        personality_class = "neon"
    elif avg_lum < 0.12:
        personality_class = "dark"
    elif avg_lum > 0.70 and avg_chroma < 0.10:
        personality_class = "pastel"
    elif avg_lum > 0.70:
        personality_class = "bright"
    elif entropy < 3.2:
        personality_class = "minimal"
    elif avg_chroma > 0.22:
        personality_class = "vibrant"
    else:
        personality_class = "muted"

    if mode_override != "auto":
        mode = mode_override
    elif personality_class in ("neon", "dark"):
        mode = "dark"
    elif personality_class in ("pastel", "bright"):
        mode = "light"
    else:
        mode = "dark"

    chroma_boost = float(policy.get("chroma_boost", 1.0))
    warmth = float(policy.get("warmth", 0.0))
    contrast_mult = float(policy.get("contrast", 1.0))

    return {
        "class": personality_class,
        "mode": mode,
        "entropy": round(entropy, 4),
        "avgChroma": round(avg_chroma, 4),
        "avgLuminance": round(avg_lum, 4),
        "maxChroma": round(max_chroma, 4),
        "chromaBoost": round(chroma_boost, 3),
        "warmth": round(warmth, 3),
        "contrastMult": round(contrast_mult, 3),
    }


PERSONALITY_TUNES: dict = {
    # personality: (surface_chroma_mult, accent_chroma_mult, surface_lightness_bump, accent_footprint, transparency)
    "dark":      (0.30, 0.90,  0.00, "medium", 0.80),
    "neon":      (1.50, 1.60,  0.00, "large",  0.95),
    "pastel":    (0.60, 0.70, +0.08, "small",  0.90),
    "bright":    (0.80, 1.00, +0.06, "medium", 0.85),
    "minimal":   (0.35, 0.40,  0.00, "small",  0.70),
    "vibrant":   (1.20, 1.30,  0.00, "medium", 0.82),
    "muted":     (0.45, 0.65,  0.00, "medium", 0.78),
}


# ── IMAGE SAMPLING ────────────────────────────────────────────────────────────

def samples(path: Path) -> tuple[list[dict], float]:
    """Quantize wallpaper to ≤48 colors, return entries with OKLCH + HSV data."""
    image = Image.open(path).convert("RGB")
    image.thumbnail((640, 640))
    # Slightly boost color saturation before sampling so muted wallpapers still yield usable chroma.
    image = ImageEnhance.Color(image).enhance(1.12)
    quantized = image.quantize(colors=48, method=Image.Quantize.MEDIANCUT)
    palette = quantized.getpalette()
    rows = quantized.getcolors() or []
    total = sum(count for count, _ in rows) or 1

    entries: list[dict] = []
    for count, idx in sorted(rows, reverse=True):
        rgb = tuple(palette[idx * 3: idx * 3 + 3])
        if len(rgb) != 3:
            continue
        L, C, H = rgb_to_oklch(*rgb)
        lum = rgb_lightness(*rgb)
        r, g, b = rgb
        chroma = (max(rgb) - min(rgb)) / 255.0
        frac = count / total
        entries.append({
            "rgb": rgb,
            "fraction": frac,
            "lum": lum,
            "chroma": chroma,
            "L": L,
            "C": C,
            "H": H % 360,
        })

    if not entries:
        entries = [{"rgb": (18, 20, 28), "fraction": 1.0, "lum": 0.006, "chroma": 0.04,
                    "L": 0.03, "C": 0.015, "H": 220.0}]

    entropy = -sum(float(e["fraction"]) * math.log2(float(e["fraction"]))
                   for e in entries if e["fraction"] > 0)
    return entries, entropy


# ── PALETTE EXTRACTION ───────────────────────────────────────────────────────

def pick_background(entries: list[dict]) -> tuple[float, float, float]:
    """Select the dominant dark sample as the background seed in OKLCH."""
    dark = [e for e in entries if e["L"] <= 0.22] or entries

    def score(e: dict) -> float:
        return float(e["fraction"]) * 2.0 \
            - abs(float(e["L"]) - 0.10) * 1.5 \
            - float(e["C"]) * 0.40

    seed = max(dark, key=score)
    L_s, C_s, H_s = seed["L"], seed["C"], seed["H"]
    # Darken + desaturate slightly toward a comfortable dark base.
    L_b = max(0.025, L_s - 0.015)
    C_b = C_s * 0.40
    H_b = (H_s + 220.0) % 360  # nudge toward blue-purple darkness
    L_b, C_b, H_b = clamp_chroma(L_b, C_b, H_b)
    return (L_b, C_b, H_b)


def pick_accent_hues(entries: list[dict], bg_L: float, personality: dict) -> list[tuple[float, float, float]]:
    """Extract distinct accent hue peaks from the wallpaper, ordered by prominence."""
    chroma_boost = personality.get("chromaBoost", 1.0)
    min_chroma = 0.12 / chroma_boost if chroma_boost > 0 else 0.12

    candidates = []
    for e in entries:
        if 0.14 <= e["L"] <= 0.82 and e["C"] >= min_chroma:
            ratio = contrast_ratio(e["rgb"], oklch_to_rgb(bg_L, 0.0, 0.0))
            score = (float(e["C"]) * 2.4 * chroma_boost +
                     float(e["fraction"]) * 1.4 +
                     min(ratio, 4.0) * 0.25 -
                     abs(float(e["L"]) - 0.52) * 0.80)
            candidates.append((score, e))

    candidates.sort(key=lambda x: (-x[0], x[1]["rgb"]))

    hues: list[tuple[float, float, float]] = []
    for score, entry in candidates:
        H = entry["H"]
        too_close = any(hue_dist(H, existing[0]) < 28.0 for existing in hues)
        if not too_close:
            hues.append((H, float(entry["C"]), float(entry["L"])))
        if len(hues) >= 3:
            break

    return hues


def make_neutral_hues(
    entries: list[dict], bg_H: float, accent_hues: list,
    personality: dict, surface_tint: float,
) -> tuple[float, float, float, float]:
    """Derive tinted surface hues from the wallpaper's actual color balance."""
    chromatic = [e for e in entries if float(e["C"]) >= 0.035]
    if chromatic:
        weights = [float(e["fraction"]) * max(float(e["C"]), 0.035) for e in chromatic]
        angle_x = sum(w * math.cos(math.radians(float(e["H"]))) for e, w in zip(chromatic, weights))
        angle_y = sum(w * math.sin(math.radians(float(e["H"]))) for e, w in zip(chromatic, weights))
        neutral_H = math.degrees(math.atan2(angle_y, angle_x)) % 360.0
        avg_chroma = sum(w * float(e["C"]) for e, w in zip(chromatic, weights)) / sum(weights)
    elif accent_hues:
        neutral_H = float(accent_hues[0][0])
        avg_chroma = 0.0
    else:
        neutral_H = bg_H
        avg_chroma = 0.0

    # Even monochrome wallpapers get a restrained hue-led rice; colorful
    # wallpapers tint the neutral layers more strongly without turning them
    # into competing accent blocks.
    neutral_C = min(max(0.012, avg_chroma * 0.10 + surface_tint * 0.12), 0.055)

    # neutral-variant is a slightly warmer/cooler shift.
    warmth = personality.get("warmth", 0.0)
    neutral_var_H = (neutral_H + warmth * 18.0) % 360
    neutral_var_C = neutral_C * 1.4

    return neutral_H, neutral_C, neutral_var_H, neutral_var_C


# ── TONAL PALETTE BUILDER ─────────────────────────────────────────────────────

def build_tonal_palette(
    entries: list[dict],
    personality: dict,
    policy: dict,
) -> dict[str, str]:
    """Build the complete tonal palette from wallpaper analysis + policy."""
    chroma_boost = personality.get("chromaBoost", 1.0)
    warmth = personality.get("warmth", 0.0)
    contrast_mult = personality.get("contrastMult", 1.0)
    tunes = PERSONALITY_TUNES.get(personality["class"], PERSONALITY_TUNES["muted"])
    surf_chroma_mult, accent_chroma_mult, surf_L_bump, _, _ = tunes

    bg_L, bg_C, bg_H = pick_background(entries)
    if personality["mode"] == "light":
        # Explicit light mode uses a neutral, stable canvas; wallpaper hue is
        # still expressed through accents and the softly tinted surface ladder.
        bg_L, bg_C = 0.92, 0.0
    elif personality["mode"] == "oled":
        bg_L, bg_C = 0.025, 0.0
    else:
        # `pick_background` falls back to all samples when a wallpaper has no
        # dark pixels. Keep the shell canvas in a stable dark range in that
        # case instead of deriving a pale canvas with near-white text.
        bg_L = min(bg_L, 0.10)
        bg_C = min(bg_C, 0.025)

    # ── Neutral hues ──
    accent_hues = pick_accent_hues(entries, bg_L, personality)
    surface_tint = float(policy.get("surface_tint", 0.10))
    neutral_H, neutral_C, neutral_var_H, neutral_var_C = make_neutral_hues(
        entries, bg_H, accent_hues, personality, surface_tint)
    del accent_hues  # recomputed below with full context

    # ── Accent hues (up to 3 distinct) ──
    accent_hues = pick_accent_hues(entries, bg_L, personality)
    if len(accent_hues) == 0:
        primary_H, primary_C, primary_L = 210.0, 0.18, 0.60
    elif len(accent_hues) == 1:
        primary_H, primary_C, primary_L = accent_hues[0]
        secondary_H = (primary_H + 60.0) % 360
        secondary_C, secondary_L = neutral_C * 4, 0.62
    if len(accent_hues) == 0:
        primary_H, primary_C, primary_L = 210.0, 0.18, 0.60
        secondary_H, secondary_C, secondary_L = (primary_H + 58.0) % 360, 0.10, 0.62
        tertiary_H = (primary_H + 152.0) % 360
    elif len(accent_hues) == 1:
        primary_H, primary_C, primary_L = accent_hues[0]
        secondary_H, secondary_C, secondary_L = (primary_H + 58.0) % 360, neutral_C * 4, 0.62
        tertiary_H = (primary_H + 152.0) % 360
    elif len(accent_hues) == 2:
        primary_H, primary_C, primary_L = accent_hues[0]
        secondary_H, secondary_C, secondary_L = accent_hues[1]
        tertiary_H = (primary_H + 152.0) % 360
    else:
        primary_H, primary_C, primary_L = accent_hues[0]
        secondary_H, secondary_C, secondary_L = accent_hues[1]
        tertiary_H = accent_hues[2][0]

    # Apply warmth rotation.
    primary_H = (primary_H + warmth * 12.0) % 360
    secondary_H = (secondary_H + warmth * 10.0) % 360
    tertiary_H = (tertiary_H + warmth * 14.0) % 360

    # Apply chroma boost.
    primary_C = min(primary_C * chroma_boost * accent_chroma_mult, 0.38)
    secondary_C = min(secondary_C * chroma_boost * accent_chroma_mult * 0.85, 0.32)
    tertiary_C = min(max(0.12, 0.18 * accent_chroma_mult) * chroma_boost, 0.30)

    # ── Surface ladder (OKLCH L steps) ──
    def surf_L(n: int) -> float:
        """L for surface level n (0=base, 1-4=elevated)."""
        base = bg_L + surf_L_bump
        steps = [0.00, 0.042, 0.082, 0.128, 0.178]
        return min(0.98, base + steps[n])

    def neutral_chroma(n: int) -> float:
        mult = surf_chroma_mult * (1.0 + n * 0.12)
        tint = surface_tint * (0.06 + n * 0.008)
        return min(neutral_C * mult + tint, 0.075)

    surf0_L = surf_L(0)
    surf0_C = neutral_chroma(0)
    surf0_H = neutral_H  # carry the wallpaper's own hue into the neutral surfaces

    colors: dict[str, tuple[float, float, float]] = {}

    # ── Background / canvas ──
    bg_C = min(max(bg_C, surface_tint * 0.035), 0.035)
    colors["background"] = (bg_L, bg_C, bg_H)

    # ── Surface ladder ──
    levels = [
        ("surfaceCanvas",   surf_L(0), min(bg_C * 0.55, 0.02), bg_H),
        ("surfaceBase",     surf_L(1), neutral_chroma(1), surf0_H),
        ("surface1",        surf_L(2), neutral_chroma(2), surf0_H),
        ("surface2",        surf_L(3), neutral_chroma(3), surf0_H),
        ("surface3",        surf_L(4), neutral_chroma(4), surf0_H),
        ("surfaceFloating", min(0.96, surf_L(4) + 0.04), neutral_chroma(5) * 1.2, surf0_H),
    ]
    for name, L, C, H in levels:
        C = min(C, 0.055)  # keep surfaces clearly neutral
        colors[name] = (L, C, H)
        colors[f"on{name[0].upper()}{name[1:]}"] = (
            1.0 - L, 0.0, bg_H
        )  # placeholder, replaced below

    surface_colors = [colors[name] for name in (
        "surfaceCanvas", "surfaceBase", "surface1", "surface2", "surface3", "surfaceFloating",
    )]
    accent_direction = 1 if personality["mode"] != "light" else -1

    # Primary text uses a deliberately strong endpoint. The muted role below
    # can be tuned to the minimum readable contrast without dimming body copy.
    colors["onBackground"] = (
        (0.04 if personality["mode"] == "light" else 0.96), 0.0, bg_H,
    )

    # ── Neutral / neutral-variant ──
    colors["neutral"] = (surf_L(2), min(neutral_C * 1.5, 0.040), neutral_H)
    colors["onNeutral"] = (1.0 - surf_L(2), 0.0, neutral_H)
    colors["neutralContainer"] = (surf_L(3), min(neutral_C * 2.0, 0.050), neutral_H)
    colors["onNeutralContainer"] = (1.0 - surf_L(3), 0.0, neutral_H)
    colors["neutralVariant"] = (surf_L(2), min(neutral_var_C, 0.045), neutral_var_H)
    colors["onNeutralVariant"] = (1.0 - surf_L(2), 0.0, neutral_var_H)

    # ── Primary ──
    primary_L = max(0.38, min(0.76, primary_L))
    primary_L_ok = primary_L
    primary_C = min(primary_C, 0.38)
    primary_L_ok, primary_C, primary_H = _ensure_surface_contrast(
        primary_L_ok, primary_C, primary_H, surface_colors, accent_direction,
    )
    colors["primary"] = (primary_L_ok, primary_C, primary_H)
    # onPrimary: contrast against primary
    on_p = _contrast_foreground(primary_L_ok, primary_C, primary_H, 4.5 * contrast_mult)
    colors["onPrimary"] = on_p

    # primaryContainer
    pc_L = oklch_lift_lightness(primary_L_ok, surf_L(2), 0.0)
    pc_C = primary_C * 0.55
    pc_L, pc_C, _ = clamp_chroma(pc_L, pc_C, primary_H)
    colors["primaryContainer"] = (pc_L, pc_C, primary_H)
    opc = _contrast_foreground(pc_L, pc_C, primary_H, 4.5 * contrast_mult)
    colors["onPrimaryContainer"] = opc

    # ── Secondary ──
    secondary_L = max(0.36, min(0.74, secondary_L))
    secondary_C = min(secondary_C, 0.32)
    secondary_L, secondary_C, secondary_H = _ensure_surface_contrast(
        secondary_L, secondary_C, secondary_H, surface_colors, accent_direction,
    )
    colors["secondary"] = (secondary_L, secondary_C, secondary_H)
    osc = _contrast_foreground(secondary_L, secondary_C, secondary_H, 3.8 * contrast_mult)
    colors["onSecondary"] = osc

    sc_L = oklch_lift_lightness(secondary_L, surf_L(2), 0.0)
    sc_C = secondary_C * 0.50
    sc_L, sc_C, _ = clamp_chroma(sc_L, sc_C, secondary_H)
    colors["secondaryContainer"] = (sc_L, sc_C, secondary_H)
    osc2 = _contrast_foreground(sc_L, sc_C, secondary_H, 3.8 * contrast_mult)
    colors["onSecondaryContainer"] = osc2

    # ── Tertiary ──
    tertiary_C = min(tertiary_C, 0.30)
    tertiary_L = max(0.38, min(0.74, 0.60))
    tertiary_L, tertiary_C, tertiary_H = _ensure_surface_contrast(
        tertiary_L, tertiary_C, tertiary_H, surface_colors, accent_direction,
    )
    colors["tertiary"] = (tertiary_L, tertiary_C, tertiary_H)
    otc = _contrast_foreground(tertiary_L, tertiary_C, tertiary_H, 3.8 * contrast_mult)
    colors["onTertiary"] = otc

    tc_L = oklch_lift_lightness(tertiary_L, surf_L(2), 0.0)
    tc_C = tertiary_C * 0.50
    tc_L, tc_C, _ = clamp_chroma(tc_L, tc_C, tertiary_H)
    colors["tertiaryContainer"] = (tc_L, tc_C, tertiary_H)
    otc2 = _contrast_foreground(tc_L, tc_C, tertiary_H, 3.8 * contrast_mult)
    colors["onTertiaryContainer"] = otc2

    # ── Semantic: warning / danger / success / info ──
    sem = {
        "warning":   (0.65, 0.22, 85.0),
        "danger":    (0.58, 0.26, 25.0),
        "success":   (0.62, 0.24, 145.0),
        "info":      (0.62, 0.22, 255.0),
    }
    for name, (L, C, H) in sem.items():
        L, C, H = _ensure_surface_contrast(
            L, C * chroma_boost * 0.9, H, surface_colors, accent_direction,
        )
        colors[name] = (L, C, H)
        fg = _contrast_foreground(L, C, H, 4.5 * contrast_mult)
        colors[f"on{name[0].upper()}{name[1:]}"] = fg
        container_L = oklch_lift_lightness(L, surf_L(2), 0.0)
        container_C = C * 0.45
        container_L, container_C, _ = clamp_chroma(container_L, container_C, H)
        colors[f"{name}Container"] = (container_L, container_C, H)
        colors[f"on{name[0].upper()}{name[1:]}Container"] = _contrast_foreground(
            container_L, container_C, H, 4.5 * contrast_mult)

    # ── Outline / border ──
    colors["outline"] = (surf_L(2), neutral_chroma(3) * 1.5, surf0_H)
    colors["outlineSubtle"] = (surf_L(1), neutral_chroma(2), surf0_H)
    colors["outlineStrong"] = (surf_L(3), neutral_chroma(4) * 2.0, surf0_H)
    # Outlines are surface colors and must never be reused as muted text.
    # Check every actual surface because chroma clipping can change their
    # perceived lightness order at the edges of the palette.
    colors["onSurfaceVariant"] = _contrast_foreground_on_surfaces(
        surface_colors, neutral_H, personality["mode"], 4.5 * contrast_mult,
    )

    # ANSI bright slots are color variants, not aliases of the regular slots.
    # This keeps syntax and terminal output expressive while retaining the
    # semantic hue of each standard role.
    colors["brightBlack"] = colors["onSurfaceVariant"]
    for role in ("danger", "success", "warning", "primary", "tertiary", "secondary"):
        L, C, H = colors[role]
        bright_L = min(0.97, L + 0.07) if accent_direction > 0 else max(0.03, L - 0.07)
        colors[f"bright{role[0].upper()}{role[1:]}"] = _ensure_surface_contrast(
            bright_L, min(0.38, C * 1.08), H, surface_colors, accent_direction,
        )
    colors["brightWhite"] = colors["onBackground"]

    # ── Accent interaction states ──
    pL, pC, pH = colors["primary"]
    colors["accentPrimary"] = colors["primary"]
    colors["accentHover"] = (
        min(0.98, pL + 0.05) if accent_direction > 0 else max(0.04, pL - 0.05),
        pC, pH,
    )
    colors["accentPressed"] = (
        max(0.04, pL - 0.06) if accent_direction > 0 else min(0.98, pL + 0.06),
        pC, pH,
    )
    colors["accentFocus"] = (
        min(0.98, pL + 0.04) if accent_direction > 0 else max(0.04, pL - 0.04),
        min(pC * 1.15, 0.38),
        pH,
    )
    sL, sC, sH = colors["secondary"]
    colors["accentSecondary"] = colors["secondary"]
    colors["accentTertiary"] = colors["tertiary"]

    # ── Convert to hex ──
    out: dict[str, str] = {}
    for key, (L, C, H) in colors.items():
        rgb = oklch_to_rgb(L, C, H)
        out[key] = hex_rgb(rgb)

    return out


def _contrast_foreground(ref_L: float, ref_C: float, ref_H: float,
                          min_ratio: float) -> tuple[float, float, float]:
    """Find the nearest neutral foreground that meets the requested contrast."""
    candidates = (index / 1000 for index in range(30, 971, 5))
    valid = [
        fg_L for fg_L in candidates
        if _oklch_contrast((ref_L, ref_C, ref_H), (fg_L, 0.0, ref_H)) >= min_ratio
    ]
    if valid:
        return (min(valid, key=lambda fg_L: abs(fg_L - ref_L)), 0.0, ref_H)
    # Preserve a strong light/dark fallback if an unusually high policy
    # contrast multiplier cannot be met within the supported lightness range.
    return (0.97 if ref_L < 0.5 else 0.03, 0.0, ref_H)


def _ensure_surface_contrast(
    L: float, C: float, H: float,
    surfaces: list[tuple[float, float, float]], direction: int,
    min_ratio: float = 3.0,
) -> tuple[float, float, float]:
    """Move a wallpaper-derived accent just enough to read on every surface."""
    stop = 0.97 if direction > 0 else 0.03
    step = 0.005 * (1 if direction > 0 else -1)
    candidate_L = L
    while (candidate_L <= stop if direction > 0 else candidate_L >= stop):
        candidate = clamp_chroma(candidate_L, C, H)
        if all(_oklch_contrast(candidate, surface) >= min_ratio for surface in surfaces):
            return candidate
        candidate_L += step
    return clamp_chroma(stop, C, H)


def _contrast_foreground_on_surfaces(
    surfaces: list[tuple[float, float, float]], hue: float,
    mode: str, min_ratio: float,
) -> tuple[float, float, float]:
    """Find a usable muted text neutral that meets contrast on every surface."""
    valid = []
    for index in range(30, 971, 5):
        candidate = (index / 1000, 0.0, hue)
        if all(_oklch_contrast(candidate, surface) >= min_ratio for surface in surfaces):
            valid.append(candidate)
    if valid:
        # Stay as close to the background as possible while retaining the
        # requested contrast, so muted text remains visually subordinate.
        return max(valid, key=lambda color: color[0]) if mode == "light" else min(valid, key=lambda color: color[0])
    return (0.03 if mode == "light" else 0.97, 0.0, hue)


def _oklch_contrast(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    """WCAG contrast between two OKLCH colors."""
    rgb_a = oklch_to_rgb(*a)
    rgb_b = oklch_to_rgb(*b)
    return contrast_ratio(rgb_a, rgb_b)


# ── MAIN COMPILER ────────────────────────────────────────────────────────────

def compile_theme(path: Path, policy_override: Optional[dict] = None) -> dict:
    policy = dict(DEFAULT_POLICY)
    if policy_override:
        policy.update(policy_override)
    else:
        policy.update(load_policy())

    entries, entropy = samples(path)
    personality = personality_from_policy(policy, entries, entropy)

    raw = build_tonal_palette(entries, personality, policy)

    # Apply per-key overrides from policy.
    overrides = policy.get("overrides", {})
    for key, value in overrides.items():
        if isinstance(value, str) and value.startswith("#"):
            raw[key] = value

    # ── Build validation pairs ──
    def hex_to_rgb(h: str) -> tuple[int, int, int]:
        h = h.lstrip("#")
        return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

    bg_rgb = hex_to_rgb(raw["background"])
    txt_rgb = hex_to_rgb(raw["onBackground"])
    muted_rgb = hex_to_rgb(raw["onSurfaceVariant"])
    pairs = {
        "background_text": round(contrast_ratio(bg_rgb, txt_rgb), 3),
        "primary_onPrimary": round(contrast_ratio(
            hex_to_rgb(raw["primary"]),
            hex_to_rgb(raw["onPrimary"]),
        ), 3),
    }
    for surface_name in ("surfaceCanvas", "surfaceBase", "surface1", "surface2", "surface3", "surfaceFloating"):
        pairs[f"onBackground_{surface_name}"] = round(
            contrast_ratio(hex_to_rgb(raw[surface_name]), hex_to_rgb(raw["onBackground"])), 3,
        )
        pairs[f"onSurfaceVariant_{surface_name}"] = round(
            contrast_ratio(hex_to_rgb(raw[surface_name]), muted_rgb), 3,
        )
        for role in ("primary", "secondary", "tertiary", "danger", "warning", "success", "info"):
            pairs[f"color_{role}_{surface_name}"] = round(
                contrast_ratio(hex_to_rgb(raw[role]), hex_to_rgb(raw[surface_name])), 3,
            )
    failed = [
        key for key, value in pairs.items()
        if value < (3.0 if key.startswith("color_") else 4.5)
    ]

    source_hash = hashlib.sha256(path.read_bytes()).hexdigest()

    effects_opacity = min(0.94, max(0.72, 0.72 + entropy / 8))
    blur_val = 16

    # ── Legacy adapter keys (backward compatibility) ──
    legacy = {
        "bg": raw["background"],
        "bg_soft": raw["surface3"],
        "surface": raw["surfaceBase"],
        "surface_alt": raw["surface2"],
        "text": raw["onBackground"],
        "muted": raw["onSurfaceVariant"],
        "accent": raw["primary"],
        "accent_soft": raw["primaryContainer"],
        "accent2": raw["secondary"],
        "success": raw["success"],
        "warn": raw["warning"],
        "danger": raw["danger"],
    }

    return {
        "schema": SCHEMA,
        "policy_version": POLICY_VERSION,
        "source": {
            "wallpaper": str(path),
            "sha256": source_hash,
            "seed": raw.get("primary", "#7B9EE8"),
        },
        "scheme": {
            "mode": personality["mode"],
            "variant": personality["class"],
        },
        "colors": {
            "background": raw["background"],
            "onBackground": raw["onBackground"],
            "surfaceCanvas": raw["surfaceCanvas"],
            "surfaceBase": raw["surfaceBase"],
            "surface1": raw["surface1"],
            "surface2": raw["surface2"],
            "surface3": raw["surface3"],
            "surfaceFloating": raw["surfaceFloating"],
            "onSurface": raw["onBackground"],
            "onSurfaceVariant": raw["onSurfaceVariant"],
            "primary": raw["primary"],
            "onPrimary": raw["onPrimary"],
            "primaryContainer": raw["primaryContainer"],
            "onPrimaryContainer": raw["onPrimaryContainer"],
            "secondary": raw["secondary"],
            "onSecondary": raw["onSecondary"],
            "secondaryContainer": raw["secondaryContainer"],
            "onSecondaryContainer": raw["onSecondaryContainer"],
            "tertiary": raw["tertiary"],
            "onTertiary": raw["onTertiary"],
            "tertiaryContainer": raw["tertiaryContainer"],
            "onTertiaryContainer": raw["onTertiaryContainer"],
            "neutral": raw["neutral"],
            "onNeutral": raw["onNeutral"],
            "neutralContainer": raw["neutralContainer"],
            "onNeutralContainer": raw["onNeutralContainer"],
            "neutralVariant": raw["neutralVariant"],
            "onNeutralVariant": raw["onNeutralVariant"],
            "error": raw["danger"],
            "warning": raw["warning"],
            "success": raw["success"],
            "info": raw["info"],
            "outline": raw["outline"],
            "outlineSubtle": raw["outlineSubtle"],
            "outlineStrong": raw["outlineStrong"],
            "accent": {
                "primary": raw["accentPrimary"],
                "secondary": raw["accentSecondary"],
                "tertiary": raw["accentTertiary"],
                "hover": raw["accentHover"],
                "pressed": raw["accentPressed"],
                "focus": raw["accentFocus"],
            },
            "terminal": {
                "background": raw["background"],
                "foreground": raw["onBackground"],
                "red": raw["danger"],
                "green": raw["success"],
                "yellow": raw["warning"],
                "blue": raw["primary"],
                "cyan": raw["secondary"],
                "magenta": raw["tertiary"],
                "brightBlack": raw["brightBlack"],
                "brightRed": raw["brightDanger"],
                "brightGreen": raw["brightSuccess"],
                "brightYellow": raw["brightWarning"],
                "brightBlue": raw["brightPrimary"],
                "brightCyan": raw["brightSecondary"],
                "brightMagenta": raw["brightTertiary"],
                "brightWhite": raw["brightWhite"],
            },
        },
        "effects": {
            "surfaceOpacity": round(effects_opacity, 3),
            "scrimOpacity": round(min(0.72, effects_opacity - 0.18), 3),
            "blur": blur_val,
        },
        "motion": {"themeTransitionMs": 380},
        "validation": {
            "contrast": pairs,
            "passed": len(failed) == 0,
            "failed": failed,
        },
        "selection": {
            "entropy": round(entropy, 4),
            "candidateCount": 0,
            "personality": personality,
            "explanation": (
                f"Personality '{personality['class']}' ({personality['mode']}) "
                f"from entropy={entropy:.2f}, avgChroma={personality['avgChroma']:.3f}. "
                f"Tonal palette built with OKLCH; surfaces from neutral hue "
                f"{raw.get('neutral', '?')[:7]}, accent from wallpaper-derived hues."
            ),
        },
        **legacy,
    }


# ── CLI ───────────────────────────────────────────────────────────────────────

def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] in {"targets", "doctor"}:
        if sys.argv[1] == "targets":
            print("noxflow kitty hyprland hyprlock rofi gtk hooks")
            return 0
        print(f"python={sys.version.split()[0]}")
        print("pillow=available")
        return 0

    if len(sys.argv) > 2 and sys.argv[1] in {"apply", "validate", "explain", "print"}:
        verb, wallpaper = sys.argv[1], Path(sys.argv[2])
        if not wallpaper.is_file():
            print(f"wallpaper does not exist: {wallpaper}", file=sys.stderr)
            return 2
        result = compile_theme(wallpaper)
        if verb in {"print", "explain"}:
            print(json.dumps(result, indent=2, sort_keys=True))
        if verb == "explain":
            print(result["selection"]["explanation"], file=sys.stderr)
        if verb == "apply":
            output = Path(sys.argv[3]) if len(sys.argv) > 3 else Path.home() / ".cache/hypr/theme-palette.json"
            output.parent.mkdir(parents=True, exist_ok=True)
            tmp = output.with_name(f".{output.name}.tmp")
            tmp.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            tmp.replace(output)
        return 0 if verb != "validate" or result["validation"]["passed"] else 1

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wallpaper", type=Path)
    parser.add_argument("output", type=Path, nargs="?")
    parser.add_argument("--validate", action="store_true")
    parser.add_argument("--explain", action="store_true")
    parser.add_argument("--policy", type=str, default=None,
                        help="Inline TOML overrides, e.g. 'personality=vibrant,chroma_boost=1.2'")
    args = parser.parse_args()

    if not args.wallpaper.is_file():
        parser.error(f"wallpaper does not exist: {args.wallpaper}")

    policy: dict = {}
    if args.policy:
        # Minimal inline TOML via dict syntax.
        for segment in args.policy.split(","):
            if "=" in segment:
                k, v = segment.split("=", 1)
                k, v = k.strip(), v.strip()
                try:
                    policy[k] = float(v)
                except ValueError:
                    policy[k] = v

    result = compile_theme(args.wallpaper, policy_override=policy)
    if args.validate and not result["validation"]["passed"]:
        print(json.dumps(result["validation"], sort_keys=True), file=sys.stderr)
        return 1
    rendered = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        tmp = args.output.with_name(f".{args.output.name}.tmp")
        tmp.write_text(rendered, encoding="utf-8")
        tmp.replace(args.output)
    else:
        print(rendered, end="")
    if args.explain:
        print(result["selection"]["explanation"], file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

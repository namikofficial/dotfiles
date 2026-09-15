#!/usr/bin/env python3
"""Deterministic wallpaper-to-theme compiler used by NoxFlow.

The compiler deliberately has one output contract.  It uses Pillow only for
sampling (Material/Matugen adapters can consume the same schema later), keeps
the wallpaper content hash in the result, and never mutates application config
files.  The legacy top-level colour keys are retained for existing adapters.
"""

from __future__ import annotations

import argparse
import colorsys
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageEnhance

SCHEMA = "nox-theme-schema-v1"
POLICY_VERSION = "nox-policy-1"


def rgb_luminance(rgb: tuple[int, int, int]) -> float:
    def channel(value: int) -> float:
        value /= 255.0
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4

    r, g, b = (channel(value) for value in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(first: tuple[int, int, int], second: tuple[int, int, int]) -> float:
    one, two = sorted((rgb_luminance(first), rgb_luminance(second)), reverse=True)
    return (one + 0.05) / (two + 0.05)


def blend(first: tuple[int, int, int], second: tuple[int, int, int], amount: float) -> tuple[int, int, int]:
    return tuple(round(a * (1 - amount) + b * amount) for a, b in zip(first, second))


def hex_rgb(rgb: tuple[int, int, int]) -> str:
    return "#%02x%02x%02x" % rgb


def hue(rgb: tuple[int, int, int]) -> float:
    return colorsys.rgb_to_hsv(*(channel / 255 for channel in rgb))[0]


def hue_distance(first: float, second: float) -> float:
    distance = abs(first - second)
    return min(distance, 1 - distance)


def lift_for_contrast(color: tuple[int, int, int], background: tuple[int, int, int], minimum: float) -> tuple[int, int, int]:
    """Prefer tone changes over hue changes when a semantic pair is unsafe."""
    current = color
    for _ in range(32):
        if contrast_ratio(current, background) >= minimum:
            return current
        current = blend(current, (255, 255, 255), 0.08)
    return current


def ensure_on_color(color: tuple[int, int, int], minimum: float = 4.5) -> tuple[tuple[int, int, int], tuple[int, int, int]]:
    """Find a nearby tone with a readable black-or-white foreground."""
    dark = (20, 20, 24)
    light = (255, 255, 255)
    if max(contrast_ratio(dark, color), contrast_ratio(light, color)) >= minimum:
        return color, (dark if contrast_ratio(dark, color) >= contrast_ratio(light, color) else light)
    for amount in [index / 40 for index in range(1, 41)]:
        for target in (dark, light):
            candidate = blend(color, target, amount)
            dark_ratio = contrast_ratio(dark, candidate)
            light_ratio = contrast_ratio(light, candidate)
            if max(dark_ratio, light_ratio) >= minimum:
                return candidate, (dark if dark_ratio >= light_ratio else light)
    return color, (dark if contrast_ratio(dark, color) >= contrast_ratio(light, color) else light)


def samples(path: Path) -> tuple[list[dict[str, object]], float]:
    image = Image.open(path).convert("RGB")
    image.thumbnail((640, 640))
    image = ImageEnhance.Color(image).enhance(1.10)
    quantized = image.quantize(colors=48, method=Image.Quantize.MEDIANCUT)
    palette = quantized.getpalette()
    rows = quantized.getcolors() or []
    total = sum(count for count, _ in rows) or 1
    entries: list[dict[str, object]] = []
    for count, index in sorted(rows, reverse=True):
        rgb = tuple(palette[index * 3 : index * 3 + 3])
        if len(rgb) != 3:
            continue
        lightness = rgb_luminance(rgb)
        hsv = colorsys.rgb_to_hsv(*(channel / 255 for channel in rgb))
        entries.append(
            {
                "rgb": rgb,
                "fraction": count / total,
                "lum": lightness,
                "h": hsv[0],
                "s": hsv[1],
                "v": hsv[2],
            }
        )
    if not entries:
        entries = [{"rgb": (18, 20, 28), "fraction": 1.0, "lum": 0.006, "h": 0.62, "s": 0.36, "v": 0.11}]
    entropy = -sum(float(row["fraction"]) * math.log2(float(row["fraction"])) for row in entries if row["fraction"])
    return entries, entropy


def compile_theme(path: Path) -> dict[str, object]:
    entries, entropy = samples(path)
    dark = [row for row in entries if float(row["lum"]) <= 0.22] or entries

    def background_score(row: dict[str, object]) -> float:
        return float(row["fraction"]) * 2 - abs(float(row["lum"]) - 0.08) * 1.5 - float(row["s"]) * 0.4

    bg_seed = max(dark, key=background_score)["rgb"]
    background = blend(bg_seed, (10, 12, 18), 0.55)
    surface = blend(background, (255, 255, 255), 0.08)
    surface_alt = blend(background, (255, 255, 255), 0.15)

    candidates = []
    for row in entries:
        rgb = row["rgb"]
        ratio = contrast_ratio(rgb, background)
        score = float(row["s"]) * 2.2 + float(row["fraction"]) * 1.4 + min(ratio, 4) * 0.25
        if 0.12 <= float(row["lum"]) <= 0.85 and ratio >= 1.8 and float(row["s"]) >= 0.16:
            candidates.append((score, row))
    candidates.sort(key=lambda item: (-item[0], item[1]["rgb"]))
    primary_row = candidates[0][1] if candidates else {"rgb": (120, 160, 220), "h": 0.60, "s": 0.45, "v": 0.86}
    primary = tuple(primary_row["rgb"])
    secondary_row = next((row for _, row in candidates[1:] if hue_distance(float(row["h"]), float(primary_row["h"])) >= 0.12), None)
    if secondary_row is None:
        secondary_hue = (float(primary_row["h"]) + 0.18) % 1
        secondary = tuple(round(value * 255) for value in colorsys.hsv_to_rgb(secondary_hue, 0.42, 0.82))
    else:
        secondary = tuple(secondary_row["rgb"])

    # Keep the wallpaper hue, but move its tone far enough from both the
    # chrome and its on-colour to guarantee a readable control label.
    primary = lift_for_contrast(primary, background, 4.5)
    primary, on_primary = ensure_on_color(primary)
    secondary = lift_for_contrast(secondary, background, 2.0)
    text = (245, 242, 238)
    muted = lift_for_contrast((170, 170, 175), surface, 3.0)
    primary_container = blend(primary, background, 0.62)
    secondary_container = blend(secondary, background, 0.68)
    warning = lift_for_contrast((232, 178, 72), background, 4.5)
    danger = lift_for_contrast((224, 108, 116), background, 4.5)
    success = lift_for_contrast(secondary, background, 4.5)

    pairs = {
        "background_text": contrast_ratio(text, background),
        "surface_text": contrast_ratio(text, surface),
        "primary_on_primary": contrast_ratio(on_primary, primary),
        "muted_surface": contrast_ratio(muted, surface),
        "warning_background": contrast_ratio(warning, background),
        "danger_background": contrast_ratio(danger, background),
    }
    failed = [name for name, value in pairs.items() if value < (4.5 if "muted" not in name else 3.0)]
    source_hash = hashlib.sha256(path.read_bytes()).hexdigest()
    opacity = min(0.94, max(0.72, 0.72 + entropy / 8))
    colors = {
        "background": hex_rgb(background), "onBackground": hex_rgb(text),
        "surface": hex_rgb(surface), "surfaceContainer": hex_rgb(surface_alt),
        "onSurface": hex_rgb(text), "onSurfaceVariant": hex_rgb(muted),
        "primary": hex_rgb(primary), "onPrimary": hex_rgb(on_primary),
        "primaryContainer": hex_rgb(primary_container), "onPrimaryContainer": hex_rgb(text),
        "secondary": hex_rgb(secondary), "onSecondary": hex_rgb((20, 22, 25)),
        "secondaryContainer": hex_rgb(secondary_container), "onSecondaryContainer": hex_rgb(text),
        "error": hex_rgb(danger), "warning": hex_rgb(warning), "success": hex_rgb(success),
        "outline": hex_rgb(blend(muted, background, 0.35)),
        "terminal": {"background": hex_rgb(background), "foreground": hex_rgb(text), "red": hex_rgb(danger), "green": hex_rgb(success), "yellow": hex_rgb(warning), "blue": hex_rgb(primary)},
    }
    legacy = {"bg": colors["background"], "bg_soft": colors["surfaceContainer"], "surface": colors["surface"], "surface_alt": colors["surfaceContainer"], "text": colors["onBackground"], "muted": colors["onSurfaceVariant"], "accent": colors["primary"], "accent_soft": colors["primaryContainer"], "success": colors["success"], "accent2": colors["secondary"], "warn": colors["warning"], "danger": colors["error"]}
    return {
        "schema": SCHEMA, "policy_version": POLICY_VERSION,
        "source": {"wallpaper": str(path), "sha256": source_hash, "seed": hex_rgb(tuple(primary_row["rgb"]))},
        "scheme": {"mode": "dark", "variant": "content"},
        "colors": colors, "effects": {"surfaceOpacity": round(opacity, 3), "scrimOpacity": round(min(0.72, opacity - 0.18), 3), "blur": 16},
        "motion": {"themeTransitionMs": 380},
        "validation": {"contrast": {key: round(value, 3) for key, value in pairs.items()}, "passed": not failed, "failed": failed},
        "selection": {"entropy": round(entropy, 4), "candidateCount": len(candidates), "explanation": "dark surface from dominant low-luminance sample; accents from highest-scoring distinct wallpaper hues"},
        **legacy,
    }


def main() -> int:
    # Keep the CLI useful in scripts while exposing explicit inspection verbs
    # for humans and health checks. The direct ``<wallpaper> [output]`` form is
    # retained for the existing theme-sync caller.
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
            temporary = output.with_name(f".{output.name}.tmp")
            temporary.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            temporary.replace(output)
        return 0 if verb != "validate" or result["validation"]["passed"] else 1

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wallpaper", type=Path)
    parser.add_argument("output", type=Path, nargs="?")
    parser.add_argument("--validate", action="store_true")
    parser.add_argument("--explain", action="store_true")
    args = parser.parse_args()
    if not args.wallpaper.is_file():
        parser.error(f"wallpaper does not exist: {args.wallpaper}")
    result = compile_theme(args.wallpaper)
    if args.validate and not result["validation"]["passed"]:
        print(json.dumps(result["validation"], sort_keys=True), file=sys.stderr)
        return 1
    rendered = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.output.with_name(f".{args.output.name}.tmp")
        temporary.write_text(rendered, encoding="utf-8")
        temporary.replace(args.output)
    else:
        print(rendered, end="")
    if args.explain:
        print(result["selection"]["explanation"], file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Validate and export the canonical NoxFlow Material tokens to QML."""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
import tomllib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "theme" / "tokens.toml"
TARGET = ROOT / "shell" / "noxflow" / "theme" / "Tokens.qml"
REQUIRED = {"meta", "appearance", "tonal", "surface", "text", "outline", "state", "spacing", "radius", "elevation", "typography", "icon", "duration", "easing", "opacity", "blur", "height", "reduced_motion"}
HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")


def luminance(value: str) -> float:
    rgb = [int(value[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def validate(data: dict) -> None:
    missing = REQUIRED - data.keys()
    if missing:
        raise ValueError(f"missing token groups: {', '.join(sorted(missing))}")
    for group, values in data.items():
        if not isinstance(values, dict):
            raise ValueError(f"token group {group} must be a table")
        for key, value in values.items():
            if isinstance(value, str) and value.startswith("#") and not HEX.match(value):
                raise ValueError(f"{group}.{key} is not a six-digit hex colour: {value}")
    pairs = [("text.primary", "surface.surface", 4.5), ("text.secondary", "surface.surface", 4.5), ("text.muted", "surface.surface", 4.5), ("outline.focus", "surface.surface", 3.0), ("tonal.on_primary", "tonal.primary", 4.5), ("tonal.on_secondary", "tonal.secondary", 4.5)]
    for foreground, background, threshold in pairs:
        fg_group, fg_key = foreground.split(".")
        bg_group, bg_key = background.split(".")
        fg, bg = luminance(data[fg_group][fg_key]), luminance(data[bg_group][bg_key])
        ratio = (max(fg, bg) + 0.05) / (min(fg, bg) + 0.05)
        if ratio < threshold:
            raise ValueError(f"contrast failure {foreground}/{background}: {ratio:.2f} < {threshold}")


def qml_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return f'"{value}"'
    return str(value)


def property_name(group: str, key: str) -> str:
    return "".join(part.title() if index else part for index, part in enumerate((group + "_" + key).split("_")))


def generate(data: dict) -> str:
    # Tokens.qml contains runtime-only helpers (profile switching, QtQuick
    # colour operations) that are intentionally not represented in the TOML
    # source. Preserve that host file while updating canonical token values;
    # the previous generator silently deleted those helpers on every run.
    if TARGET.exists():
        template = TARGET.read_text()
        for group, values in data.items():
            if group == "meta":
                continue
            for key, value in values.items():
                name = property_name(group, key)
                pattern = re.compile(rf"(^\s*(?:readonly\s+)?property\s+\w+\s+{re.escape(name)}:\s*).*$", re.MULTILINE)
                template, count = pattern.subn(rf"\g<1>{qml_value(value)}", template, count=1)
                if count != 1:
                    raise ValueError(f"runtime token export is missing property {name}")
        return template

    lines = ["pragma Singleton", "import QtQml", "", "QtObject {", "    id: root", ""]
    for group, values in data.items():
        if group == "meta":
            continue
        lines.append(f"    // {group}")
        for key, value in values.items():
            if isinstance(value, bool):
                qtype = "bool"
            elif isinstance(value, int):
                qtype = "int"
            elif isinstance(value, float):
                qtype = "real"
            elif isinstance(value, str) and value.startswith("#"):
                qtype = "color"
            else:
                qtype = "string"
            lines.append(f"    readonly property {qtype} {property_name(group, key)}: {qml_value(value)}")
        lines.append("")
    lines.extend(["    property string activeDensity: appearanceDensity", "    property bool reducedMotion: reducedMotionEnabled", "    function scale(value, density) { return value * (density === \"compact\" ? 0.9 : density === \"spacious\" ? 1.1 : 1.0); }", "    function scaled(value) { return scale(value, activeDensity); }", "    function duration(value) { return reducedMotion ? reducedMotionDurationScale * value : value; }", "    function withAlpha(value, alpha) { return Qt.rgba(value.r, value.g, value.b, alpha); }", "}"])
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data = tomllib.loads(SOURCE.read_text())
    validate(data)
    output = generate(data)
    if args.check:
        return int(not TARGET.exists() or TARGET.read_text() != output)
    TARGET.write_text(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, tomllib.TOMLDecodeError) as error:
        print(f"material token generation failed: {error}", file=sys.stderr)
        raise SystemExit(1)

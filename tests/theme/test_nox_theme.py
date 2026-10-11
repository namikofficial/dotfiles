#!/usr/bin/env python3
"""Contract tests for the deterministic wallpaper theme compiler."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path
from typing import ClassVar
from unittest import mock

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "hypr" / "scripts" / "nox-theme.py"
SPEC = importlib.util.spec_from_file_location("nox_theme", MODULE_PATH)
assert SPEC and SPEC.loader
nox_theme = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(nox_theme)


_POLICY_PATCH = mock.patch.object(nox_theme, "load_policy", return_value={})


def setUpModule() -> None:
    """Never read the developer's real ~/.config/noxflow policy file."""
    _POLICY_PATCH.start()


def tearDownModule() -> None:
    _POLICY_PATCH.stop()


class NoxThemeContractTests(unittest.TestCase):
    def make_wallpaper(self, directory: Path, name: str, colour: tuple[int, int, int]) -> Path:
        path = directory / name
        Image.new("RGB", (64, 64), colour).save(path)
        return path

    def test_same_bytes_are_bitwise_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            wallpaper = self.make_wallpaper(Path(raw), "blue.png", (32, 72, 180))
            first = nox_theme.compile_theme(wallpaper)
            second = nox_theme.compile_theme(wallpaper)
            self.assertEqual(first, second)
            self.assertEqual(first["schema"], "nox-theme-schema-v1")
            self.assertTrue(first["validation"]["passed"])
            self.assertEqual(len(first["source"]["sha256"]), 64)

    def test_wallpaper_hue_reaches_semantic_accent(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            blue = nox_theme.compile_theme(self.make_wallpaper(directory, "blue.png", (32, 72, 180)))
            red = nox_theme.compile_theme(self.make_wallpaper(directory, "red.png", (180, 40, 32)))
            self.assertNotEqual(blue["colors"]["primary"], red["colors"]["primary"])
            self.assertNotEqual(blue["source"]["sha256"], red["source"]["sha256"])

    def test_legacy_adapter_keys_are_present(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            theme = nox_theme.compile_theme(self.make_wallpaper(Path(raw), "dark.png", (8, 10, 14)))
            for key in ("bg", "surface", "text", "muted", "accent", "accent2", "warn", "danger"):
                self.assertIn(key, theme)

    def test_secondary_text_contrasts_on_surfaces_for_varied_wallpapers(self) -> None:
        samples = {
            "near-black": (5, 7, 10),
            "navy": (24, 55, 132),
            "warm-bright": (246, 207, 157),
            "cool-bright": (187, 222, 232),
            "pastel": (246, 242, 226),
            "gray": (128, 128, 128),
            "vivid": (226, 35, 146),
        }
        palette_signatures = set()
        schemes = set()
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            for name, colour in samples.items():
                with self.subTest(wallpaper=name):
                    theme = nox_theme.compile_theme(self.make_wallpaper(directory, f"{name}.png", colour))
                    self.assertTrue(theme["validation"]["passed"], theme["validation"])
                    palette_signatures.add((
                        theme["colors"]["primary"], theme["colors"]["secondary"],
                        theme["colors"]["tertiary"], theme["colors"]["surface1"],
                    ))
                    schemes.add(theme["scheme"]["mode"])
                    for surface in (
                        "surfaceCanvas", "surfaceBase", "surface1", "surface2",
                        "surface3", "surfaceFloating",
                    ):
                        self.assertGreaterEqual(
                            theme["validation"]["contrast"][f"onSurfaceVariant_{surface}"],
                            4.5,
                        )
                        for role in ("primary", "secondary", "tertiary", "danger", "warning", "success", "info"):
                            self.assertGreaterEqual(
                                theme["validation"]["contrast"][f"color_{role}_{surface}"],
                                3.0,
                            )
                    self.assertNotEqual(theme["muted"], theme["colors"]["outline"])
                    self.assertEqual(len({
                        theme["colors"][name] for name in ("primary", "secondary", "tertiary")
                    }), 3)
                    terminal = theme["colors"]["terminal"]
                    self.assertGreaterEqual(len(set(terminal.values())), 12)
                    for base, bright in (
                        ("red", "brightRed"), ("green", "brightGreen"),
                        ("yellow", "brightYellow"), ("blue", "brightBlue"),
                        ("cyan", "brightCyan"), ("magenta", "brightMagenta"),
                    ):
                        self.assertNotEqual(terminal[base], terminal[bright])
        self.assertGreaterEqual(len(palette_signatures), 6)
        self.assertEqual(schemes, {"dark", "light"})

    def test_explicit_light_mode_keeps_text_contrast(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            wallpaper = self.make_wallpaper(Path(raw), "bright.png", (246, 207, 157))
            theme = nox_theme.compile_theme(wallpaper, {"mode": "light"})
            self.assertEqual(theme["scheme"]["mode"], "light")
            self.assertTrue(theme["validation"]["passed"], theme["validation"])

    def test_surface_tint_changes_wallpaper_derived_neutrals(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            wallpaper = self.make_wallpaper(Path(raw), "teal.png", (38, 164, 154))
            restrained = nox_theme.compile_theme(wallpaper, {"surface_tint": 0.0})
            richer = nox_theme.compile_theme(wallpaper, {"surface_tint": 0.25})
            self.assertNotEqual(
                restrained["colors"]["surface1"], richer["colors"]["surface1"],
            )


class LightModeTests(unittest.TestCase):
    """Light palettes need their own ladder: surfaces step darker, borders
    darker than the canvas, text off pure black, accents at AA contrast."""

    SURFACES = ("surfaceCanvas", "surfaceBase", "surface1", "surface2", "surface3", "surfaceFloating")
    WALLPAPERS: ClassVar[dict[str, tuple[int, int, int]]] = {
        "cream": (240, 232, 215), "sky": (200, 225, 245), "pink": (245, 210, 225),
        "white": (250, 250, 250), "warm-bright": (246, 207, 157),
    }

    def compile_light(self, colour: tuple[int, int, int]) -> dict:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "w.png"
            Image.new("RGB", (64, 64), colour).save(path)
            return nox_theme.compile_theme(path, {"mode": "light"})

    @staticmethod
    def contrast(a: str, b: str) -> float:
        return nox_theme.contrast_ratio(nox_theme_hex(a), nox_theme_hex(b))

    def test_surface_ladder_is_not_collapsed(self) -> None:
        for name, colour in self.WALLPAPERS.items():
            with self.subTest(wallpaper=name):
                colors = self.compile_light(colour)["colors"]
                values = [colors[key] for key in self.SURFACES]
                self.assertEqual(len(set(values)), len(values), values)
                lightness = [nox_theme.rgb_to_oklch(*nox_theme_hex(v))[0] for v in values]
                for first, second in zip(sorted(lightness), sorted(lightness)[1:]):
                    self.assertGreaterEqual(second - first, 0.02)

    def test_borders_are_darker_than_the_canvas_and_visible(self) -> None:
        for name, colour in self.WALLPAPERS.items():
            with self.subTest(wallpaper=name):
                colors = self.compile_light(colour)["colors"]
                canvas = colors["surfaceCanvas"]
                for key, floor in (("outlineSubtle", 1.15), ("outline", 1.3), ("outlineStrong", 1.8)):
                    self.assertGreaterEqual(self.contrast(colors[key], canvas), floor, key)
                    self.assertLess(
                        nox_theme.rgb_lightness(*nox_theme_hex(colors[key])),
                        nox_theme.rgb_lightness(*nox_theme_hex(canvas)), key)

    def test_text_is_soft_and_background_matches_canvas(self) -> None:
        for name, colour in self.WALLPAPERS.items():
            with self.subTest(wallpaper=name):
                theme = self.compile_light(colour)
                self.assertNotEqual(theme["colors"]["onBackground"], "#000000")
                self.assertEqual(theme["bg"], theme["colors"]["surfaceCanvas"])
                self.assertEqual(theme["colors"]["terminal"]["background"], theme["colors"]["surfaceCanvas"])
                self.assertGreaterEqual(theme["validation"]["contrast"]["onBackground_surface3"], 7.0)

    def test_accents_and_terminal_colours_reach_aa_on_every_surface(self) -> None:
        for name, colour in self.WALLPAPERS.items():
            with self.subTest(wallpaper=name):
                colors = self.compile_light(colour)["colors"]
                swatches = [colors[k] for k in ("primary", "secondary", "tertiary", "error", "warning", "success", "info")]
                swatches += [colors["terminal"][k] for k in ("red", "green", "yellow", "blue", "cyan", "magenta")]
                for swatch in swatches:
                    for surface in self.SURFACES:
                        self.assertGreaterEqual(self.contrast(swatch, colors[surface]), 4.5, (swatch, surface))

    def test_surface_hue_follows_the_wallpaper_not_a_fixed_purple(self) -> None:
        cream = self.compile_light(self.WALLPAPERS["cream"])["colors"]
        wallpaper_hue = nox_theme.rgb_to_oklch(*self.WALLPAPERS["cream"])[2]
        surface_hue = nox_theme.rgb_to_oklch(*nox_theme_hex(cream["surfaceBase"]))[2]
        self.assertLess(nox_theme.hue_dist(wallpaper_hue, surface_hue), 30.0, (wallpaper_hue, surface_hue))


def nox_theme_hex(value: str) -> tuple[int, int, int]:
    return tuple(int(value[i:i + 2], 16) for i in (1, 3, 5))


class DarkModeRegressionTests(unittest.TestCase):
    """Dark output must not change when light mode is tuned."""

    def test_solid_dark_wallpaper_golden(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "dark.png"
            Image.new("RGB", (64, 64), (8, 10, 14)).save(path)
            theme = nox_theme.compile_theme(path, {})
        colors = theme["colors"]
        self.assertEqual(theme["scheme"]["mode"], "dark")
        self.assertEqual(
            {key: colors[key] for key in ("surfaceCanvas", "surfaceBase", "surface2", "outline", "primary", "onBackground")},
            {"surfaceCanvas": "#030303", "surfaceBase": "#090a06", "surface2": "#1c1d16",
             "outline": "#121309", "primary": "#0097b5", "onBackground": "#f2f2f2"},
        )


if __name__ == "__main__":
    unittest.main()

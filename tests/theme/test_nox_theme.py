#!/usr/bin/env python3
"""Contract tests for the deterministic wallpaper theme compiler."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "hypr" / "scripts" / "nox-theme.py"
SPEC = importlib.util.spec_from_file_location("nox_theme", MODULE_PATH)
assert SPEC and SPEC.loader
nox_theme = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(nox_theme)


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


if __name__ == "__main__":
    unittest.main()

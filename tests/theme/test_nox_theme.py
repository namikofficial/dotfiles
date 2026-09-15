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


if __name__ == "__main__":
    unittest.main()

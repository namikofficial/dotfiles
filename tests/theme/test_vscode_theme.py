#!/usr/bin/env python3
"""Contract tests for the NoxFlow Dynamic VS Code theme generator.

Everything here measures the *emitted* theme, not the intermediate palette.
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path
from typing import ClassVar
from unittest import mock

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "tests" / "theme" / "fixtures" / "palettes"


def load(name: str, relative: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module  # dataclasses resolve annotations through sys.modules
    spec.loader.exec_module(module)
    return module


vt = load("vscode_theme", "hypr/scripts/vscode-theme.py")
nox_theme = load("nox_theme", "hypr/scripts/nox-theme.py")

_POLICY_PATCH = mock.patch.object(nox_theme, "load_policy", return_value={})


def setUpModule() -> None:
    """Never read the developer's real ~/.config/noxflow policy file."""
    _POLICY_PATCH.start()


def tearDownModule() -> None:
    _POLICY_PATCH.stop()


FIXTURE_NAMES = sorted(path.stem for path in FIXTURES.glob("*.json"))
LIGHT_FIXTURES = {"light", "light-vibrant"}


def fixture(name: str) -> dict:
    return json.loads((FIXTURES / f"{name}.json").read_text())


class FixtureTheme(unittest.TestCase):
    def test_fixture_set_covers_dark_light_and_legacy(self) -> None:
        self.assertTrue(LIGHT_FIXTURES.issubset(FIXTURE_NAMES))
        self.assertIn("legacy-flat", FIXTURE_NAMES)
        self.assertGreaterEqual(len([n for n in FIXTURE_NAMES if n not in LIGHT_FIXTURES]), 3)

    def test_every_fixture_builds_and_validates(self) -> None:
        for name in FIXTURE_NAMES:
            with self.subTest(fixture=name):
                theme, _ = vt.build_theme(fixture(name))
                self.assertEqual(vt.validate_theme(theme), [])

    def test_mode_follows_palette(self) -> None:
        for name in FIXTURE_NAMES:
            with self.subTest(fixture=name):
                theme, _ = vt.build_theme(fixture(name))
                self.assertEqual(theme["type"], "light" if name in LIGHT_FIXTURES else "dark")

    def test_no_null_or_invalid_values_anywhere(self) -> None:
        for name in FIXTURE_NAMES:
            with self.subTest(fixture=name):
                theme, _ = vt.build_theme(fixture(name))
                for key, value in theme["colors"].items():
                    self.assertRegex(value, vt.HEX_ANY, key)
                self.assertNotRegex(json.dumps(theme), r'(?::|,|\[)\s*(?:null|"null"|"None"|"undefined")')

    def test_syntax_is_present_and_covers_semantic_tokens(self) -> None:
        for name in FIXTURE_NAMES:
            with self.subTest(fixture=name):
                theme, _ = vt.build_theme(fixture(name))
                self.assertGreater(len(theme["tokenColors"]), 20)
                self.assertTrue(theme["semanticHighlighting"])
                for token in ("function", "class", "variable", "property", "comment", "macro"):
                    self.assertIn(token, theme["semanticTokenColors"])
                fonts = {
                    scope: rule["settings"].get("fontStyle", "")
                    for rule in theme["tokenColors"] for scope in rule["scope"]
                }
                self.assertEqual(fonts["comment"], "italic")
                self.assertNotIn("italic", fonts["keyword"])  # keywords stay upright

    def test_every_color_role_is_emitted_for_the_main_surfaces(self) -> None:
        theme, _ = vt.build_theme(fixture("warm-dark"))
        for key in vt.REQUIRED_KEYS:
            self.assertIn(key, theme["colors"])
        for group in ("diffEditor.", "gitDecoration.", "notifications.", "menu.", "debugIcon.",
                      "testing.", "symbolIcon.", "scmGraph.", "terminal.ansi", "chat.", "peekView"):
            self.assertTrue(any(k.startswith(group) for k in theme["colors"]), group)

    def test_emitted_hues_are_preserved_and_separated(self) -> None:
        for name in FIXTURE_NAMES:
            with self.subTest(fixture=name):
                _, report = vt.build_theme(fixture(name))
                for role, entry in report.items():
                    source_hue = vt.to_oklch(entry["source"])[2]
                    # The target hue is the palette hue unless that strays past
                    # the role's spread, in which case it stops at the boundary.
                    if entry["spread"] and vt.hue_dist(source_hue, entry["anchor"]) <= entry["spread"]:
                        self.assertAlmostEqual(entry["targetHue"], source_hue, places=6, msg=role)
                    self.assertLessEqual(vt.hue_dist(entry["targetHue"], entry["anchor"]), entry["spread"] + 1e-6, role)
                    # Contrast fitting must not move the emitted hue off target.
                    _, chroma, hue = vt.to_oklch(entry["emitted"])
                    if chroma >= 0.05:
                        self.assertLessEqual(vt.hue_dist(hue, entry["targetHue"]), 4.0, role)

    def test_contrast_correction_moves_lightness_not_hue(self) -> None:
        fitted = vt.fit("#3a4a66", ["#101418"], 7.0)
        before, after = vt.to_oklch("#3a4a66"), vt.to_oklch(fitted)
        self.assertGreater(vt.contrast(fitted, "#101418"), 6.99)
        self.assertGreater(after[0], before[0])
        self.assertLess(vt.hue_dist(before[2], after[2]), 3.0)
        light = vt.fit("#c8d0e0", ["#fafafa"], 4.5)
        self.assertLess(vt.to_oklch(light)[0], vt.to_oklch("#c8d0e0")[0])
        self.assertGreaterEqual(vt.contrast(light, "#fafafa"), 4.5)

    def test_regions_separate_by_surface_not_only_border(self) -> None:
        for name in FIXTURE_NAMES:
            with self.subTest(fixture=name):
                c = vt.build_theme(fixture(name))[0]["colors"]
                editor = vt.to_oklch(c["editor.background"])[0]
                for key in ("sideBar.background", "activityBar.background",
                            "editorGroupHeader.tabsBackground", "statusBar.background"):
                    self.assertGreaterEqual(abs(vt.to_oklch(c[key])[0] - editor), 0.025, key)
                side = vt.to_oklch(c["sideBar.background"])[0]
                if name in LIGHT_FIXTURES:
                    self.assertGreater(editor, side)
                else:
                    self.assertGreater(side, editor)

    def test_status_bar_is_neutral_and_accent_reserved_for_meaningful_states(self) -> None:
        for name in FIXTURE_NAMES:
            with self.subTest(fixture=name):
                c = vt.build_theme(fixture(name))[0]["colors"]
                self.assertEqual(c["statusBar.background"], c["activityBar.background"])
                self.assertEqual(c["statusBar.noFolderBackground"], c["statusBar.background"])
                self.assertNotEqual(c["statusBar.debuggingBackground"], c["statusBar.background"])
                self.assertNotEqual(c["statusBarItem.remoteBackground"], c["statusBar.background"])
                # Accent fills are limited to action/indicator roles.
                accent = c["button.background"]
                filled = {k for k, v in c.items()
                          if v == accent and k.endswith(("Background", "background"))}
                self.assertLessEqual(filled, {
                    "button.background", "badge.background", "activityBarBadge.background",
                    "statusBarItem.remoteBackground", "extensionButton.prominentBackground",
                    "extensionBadge.remoteBackground", "progressBar.background"})

    def test_all_sixteen_ansi_slots_are_readable_in_both_modes(self) -> None:
        for name in FIXTURE_NAMES:
            with self.subTest(fixture=name):
                c = vt.build_theme(fixture(name))[0]["colors"]
                for slot in vt.ANSI_NAMES:
                    self.assertGreaterEqual(
                        vt.contrast(c[f"terminal.ansi{slot}"], c["terminal.background"]), 4.5, slot)

    def test_hover_and_state_backgrounds_keep_text_readable(self) -> None:
        pairs = (("button.foreground", "button.hoverBackground"),
                 ("extensionButton.prominentForeground", "extensionButton.prominentHoverBackground"),
                 ("statusBarItem.remoteForeground", "statusBarItem.remoteHoverBackground"),
                 ("statusBarItem.hoverForeground", "statusBarItem.hoverBackground"),
                 ("tab.hoverForeground", "tab.hoverBackground"),
                 ("list.hoverForeground", "list.hoverBackground"))
        for name in FIXTURE_NAMES:
            with self.subTest(fixture=name):
                c = vt.build_theme(fixture(name))[0]["colors"]
                for fg, bg in pairs:
                    self.assertGreaterEqual(vt.contrast(c[fg], vt.composite(c[bg], c["sideBar.background"])), 4.5, (fg, bg))
                slash_bg = vt.composite(c["chat.slashCommandBackground"], c["sideBar.background"])
                self.assertGreaterEqual(vt.contrast(c["chat.slashCommandForeground"], slash_bg), 4.5)

    def test_every_sibling_foreground_background_pair_is_validated(self) -> None:
        theme, _ = vt.build_theme(fixture("warm-dark"))
        pairs = list(vt.text_pairs(theme["colors"]))
        self.assertGreater(len(pairs), 60)
        self.assertIn(("button.foreground", "button.hoverBackground"), pairs)
        self.assertIn(("statusBarItem.remoteForeground", "statusBarItem.remoteBackground"), pairs)

    def test_red_and_orange_stay_separated_for_reddish_palettes(self) -> None:
        for red in ("#ff3300", "#ff5a00", "#e8002a", "#ef2030"):
            with self.subTest(red=red):
                palette = fixture("warm-dark")
                palette["colors"]["terminal"]["red"] = red
                theme, _ = vt.build_theme(palette)
                self.assertEqual(vt.validate_theme(theme), [])

    def test_generation_is_deterministic_and_environment_independent(self) -> None:
        first = vt.render(vt.build_theme(fixture("warm-dark"))[0])
        with tempfile.TemporaryDirectory() as home, mock.patch.dict(os.environ, {"HOME": home, "XDG_CONFIG_HOME": home}):
            settings = Path(home) / ".config" / "Code" / "User"
            settings.mkdir(parents=True)
            (settings / "settings.json").write_text('{"workbench.colorCustomizations": {"editor.background": "#ff00ff"}}')
            second = vt.render(vt.build_theme(fixture("warm-dark"))[0])
        self.assertEqual(first, second)
        self.assertNotIn("#ff00ff", second)

    def test_legacy_flat_palette_matches_nested_roles_it_can_express(self) -> None:
        theme, _ = vt.build_theme(fixture("legacy-flat"))
        self.assertEqual(vt.validate_theme(theme), [])
        flat = fixture("legacy-flat")
        self.assertEqual(theme["colors"]["editor.foreground"], vt.fit(flat["text"], [theme["colors"]["editor.background"]], 9.0))

    def test_invalid_palettes_are_rejected(self) -> None:
        for broken in ({}, {"bg": "#000000", "text": "null", "accent": "#00ff00", "danger": "#f00000",
                                "success": "#00f000", "warn": "#f0f000", "muted": "#999999",
                                "surface": "#101010"}):
            with self.subTest(palette=broken), self.assertRaises(vt.PaletteError):
                vt.build_theme(broken)


class Alpha(unittest.TestCase):
    def test_alpha_is_eight_digit_hex(self) -> None:
        self.assertEqual(vt.alpha("#112233", 0.0), "#11223300")
        self.assertEqual(vt.alpha("#112233", 1.0), "#112233ff")
        self.assertEqual(vt.alpha("#ABCDEF", 0.5), "#abcdef80")

    def test_alpha_rejects_bad_input(self) -> None:
        for color, amount in (("#12345", 0.5), ("112233", 0.5), ("#11223344", 0.5), ("#112233", 1.2), ("#112233", -0.1)):
            with self.subTest(color=color, amount=amount), self.assertRaises(vt.PaletteError):
                vt.alpha(color, amount)

    def test_composite_matches_encoded_srgb_blend(self) -> None:
        self.assertEqual(vt.composite("#ffffff80", "#000000"), "#808080")
        self.assertEqual(vt.composite("#123456", "#ffffff"), "#123456")

    def test_selection_text_contrast_is_checked_after_compositing(self) -> None:
        theme, _ = vt.build_theme(fixture("warm-dark"))
        theme["colors"]["editor.selectionBackground"] = "#ffffffe6"  # text would vanish
        self.assertTrue(any("editor selection" in p for p in vt.validate_theme(theme)))


class Validator(unittest.TestCase):
    def theme(self) -> dict:
        return json.loads(json.dumps(vt.build_theme(fixture("warm-dark"))[0]))

    def test_flags_empty_syntax(self) -> None:
        theme = self.theme()
        theme["tokenColors"] = []
        self.assertIn("tokenColors is empty", vt.validate_theme(theme))

    def test_flags_low_contrast_token_and_semantic_token(self) -> None:
        theme = self.theme()
        editor = theme["colors"]["editor.background"]
        theme["tokenColors"][2]["settings"]["foreground"] = editor
        theme["semanticTokenColors"]["function"] = editor
        problems = vt.validate_theme(theme)
        self.assertTrue(any(p.startswith("token ") for p in problems))
        self.assertTrue(any(p.startswith("semantic function") for p in problems))

    def test_flags_merged_surfaces_and_invisible_borders(self) -> None:
        theme = self.theme()
        theme["colors"]["sideBar.background"] = theme["colors"]["editor.background"]
        theme["colors"]["sideBar.border"] = theme["colors"]["editor.background"]
        problems = " ".join(vt.validate_theme(theme))
        self.assertIn("differ by only", problems)
        self.assertIn("sideBar.border", problems)

    def test_flags_collapsed_syntax_hues(self) -> None:
        theme = self.theme()
        fg = vt.token_foregrounds(theme)
        for rule in theme["tokenColors"]:
            if "entity.name.function" in rule["scope"]:
                rule["settings"]["foreground"] = fg["keyword.control"]
        self.assertTrue(any("degrees apart" in p for p in vt.validate_theme(theme)))

    def test_flags_unreadable_ansi_and_hover_pairs(self) -> None:
        theme = self.theme()
        theme["colors"]["terminal.ansiWhite"] = theme["colors"]["terminal.background"]
        theme["colors"]["button.hoverBackground"] = theme["colors"]["button.foreground"]
        problems = " ".join(vt.validate_theme(theme))
        self.assertIn("terminal.ansiWhite", problems)
        self.assertIn("button.foreground", problems)

    def test_flags_malformed_color(self) -> None:
        theme = self.theme()
        theme["colors"]["focusBorder"] = "null"
        self.assertTrue(any("focusBorder" in p for p in vt.validate_theme(theme)))


class WallpaperSweep(unittest.TestCase):
    """Compiler output for awkward wallpapers must always yield a valid theme."""

    COLOURS: ClassVar[list[tuple[int, int, int]]] = [
        (0, 0, 0), (255, 255, 255), (128, 128, 128), (90, 90, 90), (170, 170, 170),
        (255, 240, 0), (255, 0, 80), (0, 255, 200), (10, 60, 200), (245, 235, 215),
        (200, 225, 245), (250, 210, 225), (30, 10, 10), (20, 120, 60), (110, 70, 10),
    ]

    def test_every_awkward_wallpaper_yields_a_valid_theme_in_both_modes(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            for colour in self.COLOURS:
                path = Path(raw) / f"{colour[0]}-{colour[1]}-{colour[2]}.png"
                Image.new("RGB", (32, 32), colour).save(path)
                for policy in ({}, {"mode": "light"}, {"mode": "dark"}, {"personality": "vibrant"}):
                    with self.subTest(colour=colour, policy=policy):
                        palette = nox_theme.compile_theme(path, dict(policy))
                        theme, _ = vt.build_theme(palette)
                        self.assertEqual(vt.validate_theme(theme), [])


class Output(unittest.TestCase):
    def run_cli(self, *args: str) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = vt.main(list(args))
        return code, out.getvalue(), err.getvalue()

    def test_writes_cache_and_extension_with_matching_ui_theme(self) -> None:
        for name, ui_theme in (("warm-dark", "vs-dark"), ("light", "vs-light")):
            with self.subTest(fixture=name), tempfile.TemporaryDirectory() as raw:
                base = Path(raw)
                code, _, err = self.run_cli(str(FIXTURES / f"{name}.json"), "--cache", str(base / "cache.json"),
                                            "--extension-dir", str(base / "ext"))
                self.assertEqual((code, err), (0, ""))
                package = json.loads((base / "ext" / "package.json").read_text())
                self.assertEqual(package["contributes"]["themes"][0]["uiTheme"], ui_theme)
                self.assertEqual(package["contributes"]["themes"][0]["label"], "NoxFlow Dynamic")
                emitted = base / "ext" / "themes" / vt.THEME_FILE
                self.assertEqual(emitted.read_text(), (base / "cache.json").read_text())
                self.assertTrue((base / "ext" / "package.json").exists())
                self.assertEqual(sorted(p.name for p in base.rglob(".*.tmp")), [])

    def test_unchanged_theme_is_not_rewritten(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            args = (str(FIXTURES / "cool-dark.json"), "--cache", str(Path(raw) / "t.json"))
            self.run_cli(*args)
            target = Path(raw) / "t.json"
            os.utime(target, (1, 1))
            self.run_cli(*args)
            self.assertEqual(target.stat().st_mtime, 1)

    def test_failed_validation_keeps_previous_theme(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            base = Path(raw)
            ext = base / "ext"
            self.run_cli(str(FIXTURES / "warm-dark.json"), "--cache", str(base / "c.json"), "--extension-dir", str(ext))
            before = {p: p.read_bytes() for p in (base / "c.json", ext / "package.json", ext / "themes" / vt.THEME_FILE)}
            with mock.patch.object(vt, "validate_theme", return_value=["forced failure"]):
                code, _, err = self.run_cli(str(FIXTURES / "light.json"), "--cache", str(base / "c.json"),
                                            "--extension-dir", str(ext))
            self.assertEqual(code, 1)
            self.assertIn("forced failure", err)
            self.assertEqual({p: p.read_bytes() for p in before}, before)

    def test_unwritable_cache_does_not_block_the_extension(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            base = Path(raw)
            blocker = base / "not-a-dir"
            blocker.write_text("file where a directory is needed")
            code, _, err = self.run_cli(str(FIXTURES / "warm-dark.json"), "--cache", str(blocker / "c.json"),
                                        "--extension-dir", str(base / "ext"))
            self.assertEqual(code, 1)
            self.assertIn("could not write the cache", err)
            self.assertTrue((base / "ext" / "package.json").exists())
            self.assertTrue((base / "ext" / "themes" / vt.THEME_FILE).exists())

    def test_staging_failure_leaves_extension_consistent_and_clean(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            ext = Path(raw) / "ext"
            self.run_cli(str(FIXTURES / "warm-dark.json"), "--extension-dir", str(ext))
            before = {p: p.read_bytes() for p in (ext / "package.json", ext / "themes" / vt.THEME_FILE)}
            real = Path.write_text

            def flaky(path: Path, *args, **kwargs):
                if path.name == ".package.json.tmp":
                    raise PermissionError("denied")
                return real(path, *args, **kwargs)

            with mock.patch.object(Path, "write_text", flaky):
                code, _, err = self.run_cli(str(FIXTURES / "light.json"), "--extension-dir", str(ext))
            self.assertEqual(code, 1)
            self.assertIn("could not write the extension", err)
            self.assertEqual({p: p.read_bytes() for p in before}, before)  # nothing half-updated
            self.assertEqual(sorted(p.name for p in ext.rglob(".*.tmp")), [])

    def test_unreadable_or_invalid_palette_exits_nonzero_without_writing(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            base = Path(raw)
            bad = base / "bad.json"
            bad.write_text("{not json")
            for palette in (bad, base / "missing.json"):
                code, _, err = self.run_cli(str(palette), "--cache", str(base / "c.json"))
                self.assertEqual(code, 1)
                self.assertTrue(err.startswith("vscode-theme:"))
            self.assertFalse((base / "c.json").exists())

    def test_stdout_mode_prints_valid_json(self) -> None:
        code, out, _ = self.run_cli(str(FIXTURES / "cool-dark.json"))
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["name"], "NoxFlow Dynamic")


class KnownKeys(unittest.TestCase):
    """Optional: every emitted key must exist in the installed VS Code build."""

    BUNDLE = Path("/usr/share/code/resources/app/out/vs/workbench/workbench.desktop.main.js")
    GIT = Path("/usr/share/code/resources/app/extensions/git/package.json")
    SINGLE_WORD: ClassVar[set[str]] = {"foreground", "disabledForeground", "descriptionForeground", "errorForeground", "focusBorder"}

    @unittest.skipUnless(BUNDLE.exists() and GIT.exists(), "VS Code is not installed")
    def test_emitted_color_ids_exist_in_vscode(self) -> None:
        text = self.BUNDLE.read_text(encoding="utf-8", errors="replace")
        known = set(re.findall(r'"([A-Za-z]+(?:\.[A-Za-z0-9]+)+)"', text)) | self.SINGLE_WORD
        known |= {c["id"] for c in json.loads(self.GIT.read_text())["contributes"]["colors"]}
        known |= {f"terminal.ansi{n}" for n in (
            "Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White", "BrightBlack", "BrightRed",
            "BrightGreen", "BrightYellow", "BrightBlue", "BrightMagenta", "BrightCyan", "BrightWhite")}
        theme, _ = vt.build_theme(fixture("warm-dark"))
        unknown = [k for k in theme["colors"] if k not in known and not k.startswith("errorLens.")]
        self.assertEqual(unknown, [])


if __name__ == "__main__":
    unittest.main()

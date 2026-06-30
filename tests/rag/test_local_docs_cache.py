from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
sys.path.insert(0, str(SYSTEM_DIR))

from local_docs_cache import Source, doc_path, markdown_links, refresh_source


class LocalDocsCacheTest(unittest.TestCase):
    def test_markdown_links_follow_relative_same_host_links(self) -> None:
        links = markdown_links(
            "[Variables](Basics/Variables.md) [External](https://example.com/nope)",
            "https://raw.githubusercontent.com/hyprwm/hyprland-wiki/main/content/Configuring/_index.md",
            ("/content/Configuring/",),
        )

        self.assertEqual(
            links,
            [
                "https://raw.githubusercontent.com/hyprwm/hyprland-wiki/main/content/Configuring/Basics/Variables.md",
            ],
        )

    def test_markdown_links_skip_template_and_non_ascii_links(self) -> None:
        links = markdown_links(
            '[Template]({{ meta.url | safeUrl }}) [Localized](https://wiki.archlinux.org/title/Foo_(العربية))',
            "https://wiki.archlinux.org/title/Foo",
            ("/title/",),
        )

        self.assertEqual(links, [])

    def test_command_source_writes_searchable_cache_text(self) -> None:
        if shutil.which("python") is None:
            self.skipTest("python executable is not available")
        with tempfile.TemporaryDirectory() as tempdir:
            cache_dir = Path(tempdir)
            source = Source(
                id="python-help",
                name="Python Help",
                kind="commands",
                commands=({"label": "python help", "argv": ["python", "--help"]},),
            )

            result = refresh_source(cache_dir, source)
            text = doc_path(cache_dir, "python-help").read_text()

        self.assertGreater(result["bytes"], 0)
        self.assertIn("python help", text)
        self.assertIn("Command: python --help", text)


if __name__ == "__main__":
    unittest.main()

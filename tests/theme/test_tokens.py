#!/usr/bin/env python3
import importlib.util
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("material_tokens", ROOT / "setup" / "generate-material-tokens.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class MaterialTokenTests(unittest.TestCase):
    def test_source_has_all_token_groups_and_passes_contrast(self):
        data = MODULE.tomllib.loads(MODULE.SOURCE.read_text())
        MODULE.validate(data)
        self.assertTrue(MODULE.REQUIRED.issubset(data))

    def test_generated_qml_is_current_and_has_runtime_helpers(self):
        data = MODULE.tomllib.loads(MODULE.SOURCE.read_text())
        self.assertEqual(MODULE.TARGET.read_text(), MODULE.generate(data))
        output = MODULE.TARGET.read_text()
        self.assertIn("function scaled(value)", output)
        self.assertIn("property bool reducedMotion", output)

    def test_components_do_not_define_hex_colours(self):
        literals = []
        for path in (ROOT / "shell" / "noxflow" / "components").glob("*.qml"):
            literals.extend(re.findall(r"#[0-9A-Fa-f]{6}", path.read_text()))
        self.assertEqual(literals, [])


if __name__ == "__main__":
    unittest.main()

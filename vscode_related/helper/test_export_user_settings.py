"""Regression checks for preserving Settings Sync line endings on export."""

import argparse
import json
import os
import tempfile
import unittest
from pathlib import Path

from export_user_settings import export


class ExportLineEndingsTest(unittest.TestCase):
    def test_preserves_lf_and_crlf_without_extra_blank_lines(self):
        # Keep fixtures in the workspace because Windows sandbox temp paths may
        # not allow child file creation.
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as temporary:
            root = Path(temporary)
            user = root / "User"
            storage = user / "globalStorage" / "storage.json"
            storage.parent.mkdir(parents=True)
            storage.write_text("{}", encoding="utf-8")
            local = user / "settings.json"
            local.write_text("{}", encoding="utf-8")
            os.utime(local, (1, 1))
            snapshot = user / "sync" / "settings" / "lastSyncsettings.json"
            snapshot.parent.mkdir(parents=True)
            output = root / "output" / "user_settings.json"
            args = argparse.Namespace(
                user_data_dir=root, profile="Default", workspace=None, output=output,
            )
            for newline in ("\n", "\r\n"):
                with self.subTest(newline=repr(newline)):
                    settings = newline.join([
                        "{", "", "  // Preserve comments and intentional spacing.",
                        '  "editor.fontSize": 14,', "}",
                    ])
                    local.write_text(settings, encoding="utf-8", newline="")
                    os.utime(local, (1, 1))
                    snapshot.write_text(json.dumps({
                        "syncData": {"content": json.dumps({"settings": settings})},
                    }), encoding="utf-8")
                    export(args)
                    self.assertEqual(output.read_bytes(), (settings + "\n").encode("utf-8"))


if __name__ == "__main__":
    unittest.main()

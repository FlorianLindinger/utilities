"""Regression coverage for stale machine settings in both export formats."""

import argparse
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from export_synced_vscode_profile import synced_settings
from export_user_settings import export
from filter_sync_settings import extension_manifests, filter_settings, members, restore_section_comments


class FilterSyncSettingsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=Path(__file__).parent)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.manifest = self.root / "package.json"
        self.manifest.write_text(json.dumps({"contributes": {"configuration": [{"properties": {
            "python.defaultInterpreterPath": {"scope": "machine-overridable"},
            "extension.local": {"scope": "machine"},
            "extension.private": {"ignoreSync": True},
        }}]}}), encoding="utf-8")

    def test_machine_values_removed_with_comments_and_nested_values_preserved(self):
        text = '''{
  // Python section
  "python.defaultInterpreterPath": "C:\\\\Python", // local default
  "extension.local": {"nested": [1, 2]},
  "extension.private": true,
  "editor.fontSize": 14,
  "[python]": {"editor.tabSize": 4},
  "url": "https://example.org//text", // retain this
}'''
        result = filter_settings(text, [self.manifest])
        self.assertNotIn("defaultInterpreterPath", result)
        self.assertNotIn("extension.local", result)
        self.assertNotIn("extension.private", result)
        self.assertIn("// Python section", result)
        self.assertIn('"[python]": {"editor.tabSize": 4}', result)
        self.assertIn('"https://example.org//text", // retain this', result)
        self.assertEqual(len(members(result)), 3)

    def test_explicit_exclusions_and_negative_overrides(self):
        text = '{"python.defaultInterpreterPath":"python", "editor.fontSize":14}'
        local = '''{"settingsSync.ignoredSettings": [
            // Explicitly sync this machine setting.
            "-python.defaultInterpreterPath", "editor.fontSize",
        ]}'''
        result = filter_settings(text, [self.manifest], local)
        self.assertIn('"python.defaultInterpreterPath":"python"', result)
        self.assertNotIn("editor.fontSize", result)

    def test_extension_index_ignores_obsolete_version_directories(self):
        active = self.root / "active"
        obsolete = self.root / "obsolete"
        active.mkdir()
        obsolete.mkdir()
        (active / "package.json").write_text("{}", encoding="utf-8")
        (obsolete / "package.json").write_text("{}", encoding="utf-8")
        (self.root / "extensions.json").write_text(json.dumps([{
            "location": {"scheme": "file", "path": active.as_posix()},
        }]), encoding="utf-8")
        with patch.dict(os.environ, {"VSCODE_EXTENSIONS": str(self.root)}):
            paths = list(extension_manifests())
        self.assertIn(active / "package.json", paths)
        self.assertNotIn(obsolete / "package.json", paths)

    def test_first_middle_last_and_only_properties(self):
        for text in (
            '{"extension.local":[], "keep":1}',
            '{"first":1, "extension.local":[], "last":2}',
            '{"keep":1, "extension.local":[]}',
            '{"extension.local":[]}',
        ):
            with self.subTest(text=text):
                result = filter_settings(text, [self.manifest])
                self.assertNotIn("extension.local", result)
                members(result)  # JSONC permits a trailing comma after removal.

    def test_restore_python_heading_missing_from_sync_snapshot(self):
        local = '''{
  "keep": true,
  // =====================================
  // Python
  //
  "python.defaultInterpreterPath": "local",
  "python.analysis.inlayHints.variableTypes": false,
}'''
        snapshot = '''{
  "keep": true,
  "python.analysis.inlayHints.variableTypes": true,
}'''
        for newline in ("\n", "\r\n"):
            with self.subTest(newline=repr(newline)):
                text = snapshot.replace("\n", newline)
                result = restore_section_comments(text, local)
                self.assertIn(newline.join([
                    "  // =====================================", "  // Python", "  //",
                    '  "python.analysis.inlayHints.variableTypes": true,',
                ]), result)
                self.assertNotIn("defaultInterpreterPath", result)
                self.assertEqual(restore_section_comments(result, local), result)

    def test_comment_preservation_in_both_export_paths(self):
        user = self.root / "User"
        storage = user / "globalStorage" / "storage.json"
        storage.parent.mkdir(parents=True)
        storage.write_text("{}", encoding="utf-8")
        local = user / "settings.json"
        local.write_text('''{
  // =====================================
  // Python
  "python.defaultInterpreterPath": "local",
  "editor.fontSize": 14
}''', encoding="utf-8")
        os.utime(local, (1, 1))
        snapshot = user / "sync" / "settings" / "lastSyncsettings.json"
        snapshot.parent.mkdir(parents=True)
        snapshot.write_text(json.dumps({"syncData": {
            "content": json.dumps({"settings": '{\n  "editor.fontSize": 16\n}'}),
        }}), encoding="utf-8")
        with patch("export_synced_vscode_profile.extension_manifests", return_value=[self.manifest]):
            profile_settings = json.loads(synced_settings(user, {}, local))["settings"]
            output = export(argparse.Namespace(
                user_data_dir=self.root, profile="Default", workspace=None,
                output=self.root / "user_settings.json",
            ))
        self.assertIn("// =====================================\n  // Python\n", profile_settings)
        self.assertIn('"editor.fontSize": 16', profile_settings)
        self.assertNotIn("defaultInterpreterPath", profile_settings)
        self.assertEqual(output.read_text(encoding="utf-8"), profile_settings + "\n")

    def test_preserves_empty_final_section_and_trailing_comment_lines(self):
        local = '''{
  "keep": true,
  // =====================================
  // Python
  "python.defaultInterpreterPath": "local",
  //
}'''
        snapshot = '{\n  "keep": true,\n}'
        result = restore_section_comments(snapshot, local)
        self.assertIn("// =====================================\n  // Python\n  //\n}", result)
        self.assertEqual(restore_section_comments(result, local), result)

    def test_shared_profile_payload_and_user_export_apply_current_schema(self):
        user = self.root / "User"
        storage = user / "globalStorage" / "storage.json"
        storage.parent.mkdir(parents=True)
        storage.write_text("{}", encoding="utf-8")
        local = user / "settings.json"
        settings = '{"python.defaultInterpreterPath":"local", "editor.fontSize":14}'
        local.write_text(settings, encoding="utf-8")
        os.utime(local, (1, 1))
        snapshot = user / "sync" / "settings" / "lastSyncsettings.json"
        snapshot.parent.mkdir(parents=True)
        snapshot.write_text(json.dumps({"syncData": {
            "content": json.dumps({"settings": settings}),
        }}), encoding="utf-8")
        with patch("export_synced_vscode_profile.extension_manifests", return_value=[self.manifest]):
            profile_settings = json.loads(synced_settings(user, {}, local))["settings"]
            args = argparse.Namespace(
                user_data_dir=self.root, profile="Default", workspace=None,
                output=self.root / "user_settings.json",
            )
            output = export(args)
        self.assertNotIn("defaultInterpreterPath", profile_settings)
        self.assertEqual(output.read_text(encoding="utf-8"), profile_settings + "\n")

    def test_newer_local_comments_and_excluded_changes_do_not_block_export(self):
        user = self.root / "User"
        user.mkdir()
        local = user / "settings.json"
        text = '''{
  // =====================================
  // Python
  "python.defaultInterpreterPath": "changed-local-path",
  "editor.fontSize": 14,
}'''
        local.write_text(text, encoding="utf-8", newline="")
        snapshot = user / "sync" / "settings" / "lastSyncsettings.json"
        snapshot.parent.mkdir(parents=True)
        snapshot.write_text(json.dumps({"syncData": {"content": json.dumps({
            "settings": '{"python.defaultInterpreterPath":"old-path","editor.fontSize":14}',
        })}}), encoding="utf-8")
        os.utime(snapshot, (1, 1))
        with patch("export_synced_vscode_profile.extension_manifests", return_value=[self.manifest]):
            result = json.loads(synced_settings(user, {}, local))["settings"]
        self.assertEqual(result, filter_settings(text, [self.manifest]))
        self.assertNotIn("defaultInterpreterPath", result)

    def test_newer_actual_synced_value_still_reports_pending_sync(self):
        user = self.root / "User"
        user.mkdir()
        local = user / "settings.json"
        local.write_text('{"editor.fontSize": 18}', encoding="utf-8")
        snapshot = user / "sync" / "settings" / "lastSyncsettings.json"
        snapshot.parent.mkdir(parents=True)
        snapshot.write_text(json.dumps({"syncData": {"content": json.dumps({
            "settings": '{"editor.fontSize":14}',
        })}}), encoding="utf-8")
        os.utime(snapshot, (1, 1))
        with patch("export_synced_vscode_profile.extension_manifests", return_value=[self.manifest]):
            with self.assertRaisesRegex(RuntimeError, "synced setting values differ"):
                synced_settings(user, {}, local)


if __name__ == "__main__":
    unittest.main()

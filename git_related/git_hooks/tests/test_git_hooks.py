"""Install the hooks into throwaway repositories and let Git run them for real.

Run: python git_related/git_hooks/tests/test_git_hooks.py   (needs Git; on Windows Git for Windows' sh)
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import git_hooks  # noqa: E402

# A token in GitHub's format, assembled so this file itself does not contain one.
FAKE_TOKEN = "gh" + "p_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"


def git(repo: Path, *arguments: str, check: bool = True) -> subprocess.CompletedProcess:
    env = {**os.environ, "NO_COLOR": "1"}
    env.pop("SKIP", None)
    completed = subprocess.run(
        ["git", *arguments], cwd=repo, capture_output=True, text=True, encoding="utf-8", check=False, env=env
    )
    if check and completed.returncode:
        raise AssertionError(f"git {' '.join(arguments)} failed:\n{completed.stdout}\n{completed.stderr}")
    return completed


class HookTest(unittest.TestCase):
    def setUp(self) -> None:
        if not shutil.which("git"):
            self.skipTest("Git is required")
        self.folder = Path(tempfile.mkdtemp(prefix="git hooks "))
        self.addCleanup(shutil.rmtree, self.folder, True)
        self.repo = self.folder / "repo"
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "config", "user.name", "Test")
        git(self.repo, "config", "user.email", "test@example.invalid")
        git(self.repo, "config", "commit.gpgsign", "false")
        (self.repo / "readme.txt").write_text("start\n", encoding="utf-8")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-q", "-m", "Start", "--no-verify")

    def install(self, *hooks: str) -> str:
        completed = subprocess.run(
            [sys.executable, str(HERE / "git_hooks.py"), "install", *hooks, "--repo", str(self.repo)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return completed.stderr

    def commit(self, files: dict, message: str = "Change", *options: str) -> subprocess.CompletedProcess:
        for name, content in files.items():
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            if isinstance(content, bytes):
                path.write_bytes(content)
            else:
                path.write_text(content, encoding="utf-8")
        git(self.repo, "add", "-A")
        return git(self.repo, *options, "commit", "-q", "-m", message, check=False)

    def hooks_folder(self) -> Path:
        return Path(git(self.repo, "rev-parse", "--path-format=absolute", "--git-path", "hooks").stdout.strip())


class InstallTest(HookTest):
    def test_install_copies_everything_the_hooks_need(self):
        self.install()
        folder = self.hooks_folder()
        for hook in git_hooks.HOOKS:
            text = (folder / hook).read_bytes()
            self.assertIn(git_hooks.MARKER.encode(), text)
            self.assertNotIn(b"\r\n", text)  # sh needs LF line endings
        self.assertTrue((folder / git_hooks.SCRIPT_NAME).is_file())

    def test_an_earlier_hook_is_kept_runs_first_and_comes_back(self):
        folder = self.hooks_folder()
        folder.mkdir(parents=True, exist_ok=True)
        earlier = "#!/bin/sh\necho earlier hook ran >&2\nexit 0\n"
        (folder / "pre-commit").write_bytes(earlier.encode())
        self.install("pre-commit")
        self.assertTrue((folder / "pre-commit.pre-existing").is_file())
        result = self.commit({"a.txt": "fine\n"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("earlier hook ran", result.stderr)
        subprocess.run(
            [sys.executable, str(HERE / "git_hooks.py"), "uninstall", "--repo", str(self.repo)],
            capture_output=True,
            check=True,
        )
        self.assertEqual((folder / "pre-commit").read_bytes(), earlier.encode())
        self.assertFalse((folder / git_hooks.SCRIPT_NAME).exists())

    def test_a_custom_hooks_path_is_not_touched_without_force(self):
        git(self.repo, "config", "core.hooksPath", "tools/hooks")
        completed = subprocess.run(
            [sys.executable, str(HERE / "git_hooks.py"), "install", "--repo", str(self.repo)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=False,
        )
        self.assertEqual(completed.returncode, 1)
        self.assertIn("core.hooksPath", completed.stderr)
        self.assertFalse((self.repo / "tools" / "hooks").exists())

    def test_the_installed_copy_follows_its_source(self):
        source_folder = self.folder / "source"
        source_folder.mkdir()
        source = source_folder / "git_hooks.py"
        shutil.copyfile(HERE / "git_hooks.py", source)
        subprocess.run(
            [sys.executable, str(source), "install", "pre-commit", "--repo", str(self.repo)],
            capture_output=True,
            check=True,
        )
        source.write_text(source.read_text(encoding="utf-8") + "\n# edited\n", encoding="utf-8")
        result = self.commit({"a.txt": "fine\n"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(
            (self.hooks_folder() / git_hooks.SCRIPT_NAME).read_text(encoding="utf-8").endswith("# edited\n")
        )


class PreCommitTest(HookTest):
    def setUp(self) -> None:
        super().setUp()
        self.install("pre-commit")

    def test_a_clean_commit_passes(self):
        result = self.commit({"code.py": "print('hello')\n"})
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_a_token_stops_the_commit_and_is_masked(self):
        result = self.commit({"config.py": f"TOKEN = '{FAKE_TOKEN}'\n"})
        self.assertEqual(result.returncode, 1)
        self.assertIn("Commit blocked: secrets", result.stderr)
        self.assertIn("config.py:1", result.stderr)
        self.assertNotIn(FAKE_TOKEN, result.stderr)

    def test_a_check_can_be_skipped_once_or_a_line_accepted(self):
        result = self.commit({"config.py": f"TOKEN = '{FAKE_TOKEN}'\n"}, "Change", "-c", "hooks.secrets=off")
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.commit({"other.py": f"TOKEN = '{FAKE_TOKEN}'  # pragma: allowlist secret\n"})
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_conflict_markers_stop_it_but_trailing_spaces_only_warn(self):
        result = self.commit({"code.py": "a = 1\n<<<<<<< HEAD\nb = 2\n"})
        self.assertEqual(result.returncode, 1)
        self.assertIn("conflict markers", result.stderr)
        git(self.repo, "reset", "-q")
        (self.repo / "code.py").unlink()
        result = self.commit({"notes.py": "x = 1   \n"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("whitespace", result.stderr)

    def test_secret_files_large_files_and_bad_names(self):
        self.assertEqual(self.commit({".env.example": "KEY=\n"}).returncode, 0)
        result = self.commit({".env": "KEY=value\n"})
        self.assertEqual(result.returncode, 1)
        self.assertIn("secret files", result.stderr)
        git(self.repo, "rm", "-q", "--cached", ".env")
        git(self.repo, "config", "hooks.maxFileMB", "0.001")
        result = self.commit({"big.bin": b"\0" * 5000})
        self.assertEqual(result.returncode, 1)
        self.assertIn("large files", result.stderr)

    def test_ruff_judges_only_projects_set_up_for_it(self):
        if not shutil.which("ruff"):
            self.skipTest("Ruff is not on PATH")
        self.assertEqual(self.commit({"a.py": "import os\n"}).returncode, 0)  # no Ruff configuration
        result = self.commit({"ruff.toml": "", "b.py": "import sys\n"})
        self.assertEqual(result.returncode, 1)
        self.assertIn("F401", result.stderr)

    def test_personal_paths_warn_but_urls_do_not(self):
        context = git_hooks.Context("pre-commit", [], "")
        context._added = [
            git_hooks.Line("a.py", 1, r"path = 'C:\Users\alice\data.csv'"),
            git_hooks.Line("b.py", 2, "url = 'https://api.github.com/users/alice'"),
            git_hooks.Line("c.py", 3, "home = '/home/runner/work'"),
        ]
        problems = git_hooks.check_personal_paths(context)
        self.assertEqual([p.text.split()[0] for p in problems], ["a.py:1"])


class CommitMessageTest(HookTest):
    def test_conventional_commits_only_when_switched_on(self):
        self.install("commit-msg")
        self.assertEqual(self.commit({"a.txt": "1\n"}, "Add a").returncode, 0)
        git(self.repo, "config", "hooks.conventional-commits", "block")
        self.assertEqual(self.commit({"a.txt": "2\n"}, "Add b").returncode, 1)
        self.assertEqual(self.commit({"a.txt": "3\n"}, "feat: add c").returncode, 0)


class PrePushTest(HookTest):
    def setUp(self) -> None:
        super().setUp()
        self.remote = self.folder / "remote.git"
        git(self.folder, "init", "-q", "--bare", str(self.remote))
        git(self.repo, "remote", "add", "origin", str(self.remote))
        git(self.repo, "push", "-q", "origin", "main")
        self.install("pre-push")

    def test_force_push_to_main_is_stopped(self):
        self.commit({"a.txt": "1\n"}, "One", "-c", "core.hooksPath=/nonexistent")
        git(self.repo, "push", "-q", "origin", "main")
        git(self.repo, "commit", "-q", "--amend", "-m", "One again", "--no-verify")
        result = git(self.repo, "push", "-q", "--force", "origin", "main", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("force push", result.stderr)

    def test_fixup_commits_and_secrets_are_not_pushed(self):
        git(self.repo, "checkout", "-q", "-b", "feature")
        self.commit({"a.txt": "1\n"}, "fixup! Start")
        result = git(self.repo, "push", "-q", "origin", "feature", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unfinished commits", result.stderr)
        git(self.repo, "reset", "-q", "--hard", "HEAD~1")
        self.commit({"key.py": f"KEY = '{FAKE_TOKEN}'\n"}, "Add key", "-c", "core.hooksPath=/nonexistent")
        result = git(self.repo, "push", "-q", "origin", "feature", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("secrets in pushed commits", result.stderr)


class AfterCheckoutTest(HookTest):
    def test_changed_dependency_files_are_mentioned(self):
        self.install("post-checkout")
        git(self.repo, "checkout", "-q", "-b", "other")
        self.commit({"requirements.txt": "requests\n"}, "Add requirements")
        result = git(self.repo, "checkout", "main")
        self.assertIn("requirements.txt changed", result.stderr)


if __name__ == "__main__":
    unittest.main()

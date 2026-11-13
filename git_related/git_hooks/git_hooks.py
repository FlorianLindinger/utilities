"""Generic Git hooks: checks before a commit and a push, and reminders after a pull or checkout.

One file, Python 3.8+ standard library only. The install batch files copy it, with a small shell
script per hook, into the repository's hooks folder (.git/hooks), so the hooks keep working when
this folder is moved or deleted. While this folder still exists, every hook run refreshes the copy
from it, so edits here reach the installed hooks without installing again.

    python git_hooks.py install [HOOK ...] [--repo PATH] [--force]
    python git_hooks.py uninstall [HOOK ...] [--repo PATH]
    python git_hooks.py status [--repo PATH]
    python git_hooks.py run HOOK [ARGS ...]      (what the installed hooks call)

Every check can be switched per repository (or globally with --global):

    git config hooks.<check> block|warn|off      e.g. git config hooks.whitespace off
    git config hooks.maxFileMB 10                 largest file a commit may add
    git config hooks.protectedBranches main,dev   no force push or deletion (default main,master)
    git config hooks.prePushCommand "python -m pytest -q"
    git config hooks.verbose true                 list every check, also when all pass
    SKIP=secrets,ruff git commit ...              skip checks once (as the pre-commit tool does)
    git commit --no-verify                        skip all commit checks once (push: git push --no-verify)

See README.md for what each check does and when you want it.
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable, Dict, List, NamedTuple, Optional, Sequence, Tuple

VERSION = "1.0.0"
MARKER = "generic-git-hooks"  # in every shell script this tool installs: only those are replaced or removed
SCRIPT_NAME = "generic_git_hooks.py"  # the copy in the hooks folder
SOURCE_FILE = "generic_git_hooks.source"  # where the copy came from, for refreshing it
PRE_EXISTING = ".pre-existing"  # a hook that was there before is kept under this suffix and still runs
HOOKS = ("pre-commit", "commit-msg", "pre-push", "post-merge", "post-checkout")
NO_COMMIT = "0" * 40
BLOCK, WARN, OFF = "block", "warn", "off"


# ---------------------------------------------------------------- output


def _prepare_stream(stream: object) -> None:
    reconfigure = getattr(stream, "reconfigure", None)
    if reconfigure is not None:
        reconfigure(encoding="utf-8", errors="replace")


_prepare_stream(sys.stderr)
_prepare_stream(sys.stdout)
INTERACTIVE = bool(sys.stderr is not None and sys.stderr.isatty())
COLOR = INTERACTIVE and "NO_COLOR" not in os.environ and os.environ.get("TERM") != "dumb"
if COLOR and os.name == "nt":
    try:  # the classic Windows console needs this switch for colors
        import ctypes

        _kernel32 = ctypes.windll.kernel32
        _handle = _kernel32.GetStdHandle(-12)
        _mode = ctypes.c_uint32()
        if _kernel32.GetConsoleMode(_handle, ctypes.byref(_mode)):
            _kernel32.SetConsoleMode(_handle, _mode.value | 0x0004)
    except (AttributeError, OSError):
        pass

STYLES = {"ok": "32", "warn": "33", "block": "31", "dim": "90", "head": "1;36", "bold": "1"}
SYMBOLS = {"ok": "✓", "warn": "!", "block": "✗", "skip": "-"}


def paint(text: str, style: str) -> str:
    return f"\x1b[{STYLES[style]}m{text}\x1b[0m" if COLOR else text


def say(text: str = "") -> None:
    """Everything goes to stderr: Git clients show it there when a hook fails."""
    print(text, file=sys.stderr, flush=True)


# ---------------------------------------------------------------- Git


def git(*arguments: str, check: bool = True, input_bytes: Optional[bytes] = None) -> str:
    completed = subprocess.run(
        ["git", "-c", "core.quotePath=false", *arguments],
        input=input_bytes,
        capture_output=True,
        check=False,
    )
    if check and completed.returncode:
        raise RuntimeError(completed.stderr.decode("utf-8", "replace").strip() or f"git {arguments[0]} failed")
    return completed.stdout.decode("utf-8", "replace")


def succeeds(*arguments: str) -> bool:
    return subprocess.run(["git", *arguments], capture_output=True, check=False).returncode == 0


def git_bytes(*arguments: str) -> bytes:
    completed = subprocess.run(["git", *arguments], capture_output=True, check=False)
    return completed.stdout if completed.returncode == 0 else b""


def config(name: str, default: str = "") -> str:
    return git("config", "--get", f"hooks.{name}", check=False).strip() or default


def config_list(name: str, default: str) -> List[str]:
    return [item.strip() for item in config(name, default).split(",") if item.strip()]


# ---------------------------------------------------------------- checks


class Problem(NamedTuple):
    text: str
    severity: str = ""  # "" = the check's own severity; WARN makes a finding only a warning
    source: str = ""  # the line it is about, secrets masked
    link: str = ""  # file:///...#L12: Ctrl+click opens the line from VS Code's "Show Command Output"


def repo_root() -> Path:
    return Path(git("rev-parse", "--show-toplevel").strip())


def file_link(path: str, number: int = 0) -> str:
    """A link to a file of the working tree, at a line if given ("" if the file is not there).

    VS Code shows a blocked commit's output as plain text, where "app.py:12" cannot be clicked
    but a full file:/// link can; terminals and other editors open them too.
    """
    target = repo_root() / path
    if not target.is_file():
        return ""
    return target.resolve().as_uri() + (f"#L{number}" if number else "")


def at_line(line: Line, text: str, severity: str = "", source: str = "") -> Problem:
    """A finding on an added line: with the line itself and, for staged changes, a link to it.

    A line of a pushed commit gets no link: the file on disk may have changed since.
    """
    link = "" if line.commit else file_link(line.path, line.number)
    return Problem(text, severity, (source if source else line.text).strip()[:160], link)


class Check(NamedTuple):
    name: str
    title: str
    default: str
    run: Callable[["Context"], List[Problem]]


class Line(NamedTuple):
    """A line a commit adds: where (path, line number, commit) and its text."""

    path: str
    number: int
    text: str
    commit: str = ""

    def where(self) -> str:
        place = f"{self.path}:{self.number}"
        return f"{self.commit[:8]} {place}" if self.commit else place


class Context:
    """What a hook run knows: its arguments, its input and the lines it adds (read once)."""

    def __init__(self, hook: str, arguments: Sequence[str], stdin: str) -> None:
        self.hook = hook
        self.arguments = list(arguments)
        self.stdin = stdin
        self.notes: List[str] = []
        self._added: Optional[List[Line]] = None
        self._push: Optional[List["PushedRef"]] = None

    # -- pre-commit

    def staged_paths(self, filter_: str = "ACMR") -> List[str]:
        out = git("diff", "--cached", "--name-only", f"--diff-filter={filter_}", "-z")
        return [path for path in out.split("\0") if path]

    def added_lines(self) -> List[Line]:
        """pre-commit: the staged lines; pre-push: the lines of the commits being pushed."""
        if self._added is None:
            if self.hook == "pre-push":
                commits = [sha for ref in self.pushed() for sha in ref.commits]
                # Through stdin: a long push would exceed the Windows command-line limit.
                log = (
                    git(
                        "log",
                        "-p",
                        "-U0",
                        "--no-color",
                        "--no-ext-diff",
                        "--format=commit %H",
                        "--no-walk",
                        "--stdin",
                        input_bytes="\n".join(commits).encode("ascii"),
                    )
                    if commits
                    else ""
                )
                self._added = parse_diff(log)
            else:
                self._added = parse_diff(
                    git("diff", "--cached", "-U0", "--no-color", "--no-ext-diff", "--diff-filter=ACMR")
                )
        return self._added

    # -- pre-push

    def pushed(self) -> List["PushedRef"]:
        if self._push is None:
            remote = self.arguments[0] if self.arguments else "origin"
            self._push = [parse_pushed(line, remote) for line in self.stdin.splitlines() if line.strip()]
        return self._push


class PushedRef(NamedTuple):
    local_sha: str
    remote_ref: str
    remote_sha: str
    commits: List[str]  # new commits this push publishes, newest first
    forced: bool  # the remote branch loses commits


def parse_pushed(line: str, remote: str) -> PushedRef:
    _local_ref, local_sha, remote_ref, remote_sha = (line.split() + ["", "", "", ""])[:4]
    if local_sha == NO_COMMIT:
        return PushedRef(local_sha, remote_ref, remote_sha, [], False)
    if remote_sha != NO_COMMIT and succeeds("cat-file", "-e", remote_sha + "^{commit}"):
        commits = git("rev-list", f"{remote_sha}..{local_sha}", check=False).split()
        forced = not succeeds("merge-base", "--is-ancestor", remote_sha, local_sha)
    else:
        # A new branch, or a remote state this clone has not fetched: everything not on the remote yet.
        commits = git("rev-list", local_sha, "--not", f"--remotes={remote}", check=False).split()
        forced = False
    return PushedRef(local_sha, remote_ref, remote_sha, commits, forced)


def parse_diff(text: str) -> List[Line]:
    """Added lines of a unified diff with -U0 (from git diff or git log -p)."""
    lines: List[Line] = []
    path, number, commit = "", 0, ""
    for row in text.splitlines():
        if row.startswith("commit ") and len(row) == 47:
            commit = row[7:]
        elif row.startswith("+++ "):
            path = row[6:] if row.startswith("+++ b/") else ""
        elif row.startswith("@@"):
            match = re.search(r"\+(\d+)", row)
            number = int(match.group(1)) if match else 0
        elif row.startswith("+") and path:
            lines.append(Line(path, number, row[1:], commit))
            number += 1
    return lines


# ---- secrets and personal data

IGNORE_MARKERS = ("pragma: allowlist secret", "gitleaks:allow", "hooks: ignore", "leak-check: ignore")
SECRET_PATTERNS: Tuple[Tuple[str, "re.Pattern[str]"], ...] = tuple(
    (label, re.compile(pattern))
    for label, pattern in (
        ("private key", r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP |ENCRYPTED )?PRIVATE KEY"),
        ("AWS access key", r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"),
        ("GitHub token", r"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,})"),
        ("GitLab token", r"\bglpat-[A-Za-z0-9_-]{20,}"),
        ("Slack token", r"\bxox[abprs]-[A-Za-z0-9-]{10,}"),
        ("Google API key", r"\bAIza[0-9A-Za-z_-]{35}\b"),
        ("Stripe live key", r"\b[rs]k_live_[0-9A-Za-z]{24,}"),
        ("OpenAI key", r"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}T3BlbkFJ[A-Za-z0-9_-]{20,}"),
        ("Anthropic key", r"\bsk-ant-[A-Za-z0-9_-]{40,}"),
        ("Hugging Face token", r"\bhf_[A-Za-z0-9]{34,}\b"),
        ("npm token", r"\bnpm_[A-Za-z0-9]{36}\b"),
        ("PyPI token", r"\bpypi-AgEIcHlwaS5vcmc[A-Za-z0-9_-]{50,}"),
        ("password in URL", r"[a-z][a-z0-9+.-]*://[^\s:/@]+:[^\s:/@]{3,}@[^\s/]+"),
    )
)
# "password = 'something'" is only a warning: tests and examples are full of them.
ASSIGNED_SECRET = re.compile(
    r"""(?i)\b(?:password|passwd|pwd|secret|api_?key|access_?key|auth_?token|token|client_?secret)\b["']?\s*[:=]\s*["']([^"'\s]{8,})["']"""
)
PLACEHOLDER = re.compile(
    r"(?i)^(?:x+|\*+|\.+|<.*>|\{.*\}|\$\{.*\}|%.*%|changeme|change_me|example|dummy|test|password|secret|your[_-].*|placeholder)$"
)
# C:\Users\name, /home/name, /Users/name; not URLs such as https://api.github.com/users/name.
PERSONAL_PATH = re.compile(
    r"(?:\b[A-Za-z]:[\\/]+[Uu][Ss][Ee][Rr][Ss][\\/]+|(?<![\w./:-])/home/|(?<![\w./:-])/Users/)([^\\/\s\"'<>:|*?]+)"
)
GENERIC_USER_FOLDERS = {
    "public",
    "default",
    "default user",
    "all users",
    "runner",
    "user",
    "username",
    "you",
    "me",
    "name",
    "%username%",
    "$user",
    "${user}",
    "<user>",
    "<username>",
}


def mask(secret: str) -> str:
    return secret[:4] + "…" + secret[-2:] if len(secret) > 10 else "…"


def ignored(line: Line) -> bool:
    return any(marker in line.text for marker in IGNORE_MARKERS)


def masked_line(text: str) -> str:
    """The line with every recognized secret masked, so it can be shown."""
    for _label, pattern in SECRET_PATTERNS:
        text = pattern.sub(lambda match: mask(match.group(0)), text)
    return ASSIGNED_SECRET.sub(lambda match: match.group(0).replace(match.group(1), mask(match.group(1))), text)


def check_secrets(context: Context) -> List[Problem]:
    problems: List[Problem] = []
    for line in context.added_lines():
        if ignored(line):
            continue
        for label, pattern in SECRET_PATTERNS:
            match = pattern.search(line.text)
            if match:
                problems.append(
                    at_line(line, f"{line.where()}  {label}  {mask(match.group(0))}", source=masked_line(line.text))
                )
                break
        else:
            match = ASSIGNED_SECRET.search(line.text)
            if (
                match
                and not PLACEHOLDER.match(match.group(1))
                and not re.search(r"(?i)environ|getenv|secrets\.|vault", line.text)
            ):
                text = f"{line.where()}  value assigned to a secret-like name  {mask(match.group(1))}"
                problems.append(at_line(line, text, WARN, masked_line(line.text)))
    return problems


def check_personal_paths(context: Context) -> List[Problem]:
    problems: List[Problem] = []
    me = {os.environ.get("USERNAME", "").lower(), os.environ.get("USER", "").lower()} - {""}
    for line in context.added_lines():
        if ignored(line):
            continue
        for match in PERSONAL_PATH.finditer(line.text):
            name = match.group(1).lower()
            if name not in GENERIC_USER_FOLDERS:
                mine = " (your user name)" if name in me else ""
                text = f"{line.where()}  home folder path{mine}: {match.group(0)}…"
                problems.append(at_line(line, text, source=masked_line(line.text)))
                break
    return problems


SECRET_FILES = (
    ".env",
    ".env.*",
    "*.pem",
    "*.key",
    "*.p12",
    "*.pfx",
    "*.keystore",
    "*.jks",
    "id_rsa",
    "id_dsa",
    "id_ecdsa",
    "id_ed25519",
    ".netrc",
    "_netrc",
    ".pypirc",
    ".npmrc",
    "credentials.json",
    "client_secret*.json",
    "*.kdbx",
    "service-account*.json",
    ".htpasswd",
)
SAFE_FILES = (".env.example", ".env.sample", ".env.template", ".env.dist", "*.pub")


def check_secret_files(context: Context) -> List[Problem]:
    found = []
    for path in context.staged_paths("A"):
        name = path.rsplit("/", 1)[-1].lower()
        if any(fnmatch.fnmatch(name, p) for p in SECRET_FILES) and not any(
            fnmatch.fnmatch(name, p) for p in SAFE_FILES
        ):
            found.append(
                Problem(f"{path}  (a file that usually holds secrets; add it to .gitignore)", link=file_link(path))
            )
    return found


# ---- content

CONFLICT = re.compile(r"^(?:<{7}|>{7})(?: |$)")
SEPARATOR = re.compile(r"^={7}$")  # also a heading underline in text documents
TEXT_DOCUMENTS = (".md", ".rst", ".txt", ".adoc")


def check_conflict_markers(context: Context) -> List[Problem]:
    return [
        at_line(line, f"{line.where()}  conflict marker")
        for line in context.added_lines()
        if CONFLICT.match(line.text) or (SEPARATOR.match(line.text) and not line.path.endswith(TEXT_DOCUMENTS))
    ]


def check_whitespace(context: Context) -> List[Problem]:
    out = git("diff", "--cached", "--check", "--no-color", check=False)
    problems: List[Problem] = []
    for row in out.splitlines():
        location = re.match(r"^(.+):(\d+): ", row)
        if location:
            problems.append(Problem(row, link=file_link(location.group(1), int(location.group(2)))))
    return problems


DEBUG_PATTERNS = (
    (".py", re.compile(r"^\s*(?:breakpoint\(\)|import i?pdb\b|from i?pdb import|i?pdb\.set_trace\(\))")),
    ((".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".vue"), re.compile(r"^\s*debugger\s*;?\s*$")),
)


def check_debug_statements(context: Context) -> List[Problem]:
    problems: List[Problem] = []
    for line in context.added_lines():
        for suffixes, pattern in DEBUG_PATTERNS:
            if line.path.endswith(suffixes) and pattern.match(line.text) and not ignored(line):
                problems.append(at_line(line, f"{line.where()}  debug statement"))
    return problems


# ---- files


def check_large_files(context: Context) -> List[Problem]:
    limit_mb = float(config("maxFileMB", "5") or 5)
    problems: List[Problem] = []
    for path in context.staged_paths("AM"):
        size = git("cat-file", "-s", f":{path}", check=False).strip()
        if size.isdigit() and int(size) > limit_mb * 1024 * 1024:
            text = f"{path}  {int(size) / 1024 / 1024:.1f} MB (limit {limit_mb:g} MB: git config hooks.maxFileMB)"
            problems.append(Problem(text, link=file_link(path)))
    return problems


RESERVED = re.compile(r"(?i)^(?:con|prn|aux|nul|com[0-9¹²³]|lpt[0-9¹²³])(?:\..*)?$")
BAD_CHARACTERS = re.compile(r'[<>:"|?*\x00-\x1f\\]')


def check_filenames(context: Context) -> List[Problem]:
    """Names Windows cannot check out, and names that differ only in letter case."""
    problems: List[Problem] = []
    new = context.staged_paths("AR")
    for path in new:
        for part in path.split("/"):
            if BAD_CHARACTERS.search(part) or RESERVED.match(part) or part.endswith((" ", ".")):
                problems.append(Problem(f"{path}  (Windows cannot use the name {part!r})"))
                break
    if new:
        by_folded: Dict[str, List[str]] = {}
        for path in git("ls-files", "-z").split("\0"):
            if path:
                by_folded.setdefault(path.lower(), []).append(path)
        for path in new:
            same = by_folded.get(path.lower(), [])
            if len(same) > 1:
                problems.append(
                    Problem(
                        f"{' and '.join(same)}  (differ only in letter case: one overwrites the other on Windows and macOS)"
                    )
                )
    return problems


def check_notebook_outputs(context: Context) -> List[Problem]:
    problems: List[Problem] = []
    for path in context.staged_paths("AM"):
        if not path.endswith(".ipynb"):
            continue
        try:
            notebook = json.loads(git_bytes("show", f":{path}").decode("utf-8"))
        except ValueError:
            continue
        cells = [c for c in notebook.get("cells", []) if c.get("cell_type") == "code" and c.get("outputs")]
        if cells:
            problems.append(
                Problem(
                    f"{path}  {len(cells)} cell(s) with output (clear them, or: git config hooks.notebook-outputs off)",
                    link=file_link(path),
                )
            )
    return problems


# ---- Ruff


def ruff_configured() -> bool:
    root = Path(git("rev-parse", "--show-toplevel").strip())
    if (root / "ruff.toml").is_file() or (root / ".ruff.toml").is_file():
        return True
    pyproject = root / "pyproject.toml"
    return pyproject.is_file() and "[tool.ruff" in pyproject.read_text(encoding="utf-8", errors="replace")


def run_ruff(arguments: List[str], path: str, content: bytes) -> Tuple[int, str]:
    completed = subprocess.run(
        [shutil.which("ruff") or "ruff", *arguments, "--force-exclude", "--stdin-filename", path, "-"],
        input=content,
        capture_output=True,
        check=False,
        cwd=git("rev-parse", "--show-toplevel").strip(),
    )
    return completed.returncode, (completed.stdout + completed.stderr).decode("utf-8", "replace").strip()


def ruff_problems(
    context: Context, arguments: List[str], describe: Callable[[str, str], List[Problem]]
) -> List[Problem]:
    names = [p for p in context.staged_paths("ACMR") if p.endswith((".py", ".pyi"))]
    if not names:
        return []
    if not ruff_configured():
        return []  # a project that does not use Ruff is not judged by Ruff's default rules
    if not shutil.which("ruff"):
        note = "The project is set up for Ruff, but Ruff is not on PATH: its checks were skipped."
        if note not in context.notes:
            context.notes.append(note)
        return []
    problems: List[Problem] = []
    for name in names:
        code, output = run_ruff(arguments, name, git_bytes("show", f":{name}"))
        if code:
            problems.extend(describe(name, output))
    return problems


def ruff_diagnostics(name: str, output: str) -> List[Problem]:
    """One problem per "path:row:col: CODE message" line, with a link to that row."""
    problems: List[Problem] = []
    for row in output.splitlines():
        if not row.strip():
            continue
        location = re.match(r"^.+?:(\d+):\d+: ", row)
        problems.append(Problem(row, link=file_link(name, int(location.group(1))) if location else ""))
    return problems or [Problem(f"{name}: Ruff failed", link=file_link(name))]


def check_ruff(context: Context) -> List[Problem]:
    return ruff_problems(context, ["check", "--no-fix", "--output-format", "concise", "--quiet"], ruff_diagnostics)


def check_ruff_format(context: Context) -> List[Problem]:
    return ruff_problems(
        context,
        ["format", "--check", "--quiet"],
        lambda name, _output: [Problem(f"{name}  not formatted (ruff format {name})", link=file_link(name))],
    )


# ---- branch


def current_branch() -> str:
    return git("symbolic-ref", "--short", "-q", "HEAD", check=False).strip()


def check_protected_commit(context: Context) -> List[Problem]:
    branch = current_branch()
    if branch and branch in config_list("protectedBranches", "main,master"):
        return [
            Problem(
                f"committing directly on {branch} (use a feature branch, or: git config hooks.protected-commit off)"
            )
        ]
    return []


# ---- commit message

CONVENTIONAL = re.compile(r"^(?:build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(?:\([\w./-]+\))?!?: \S")


def message_subject(context: Context) -> str:
    path = Path(context.arguments[0]) if context.arguments else None
    if not path or not path.is_file():
        return ""
    for row in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if row.startswith("#"):
            continue
        if row.strip():
            return row.strip()
    return ""


def check_subject_length(context: Context) -> List[Problem]:
    subject = message_subject(context)
    limit = int(config("subjectMaxLength", "72") or 72)
    if len(subject) > limit:
        return [Problem(f"the first line has {len(subject)} characters (at most {limit} read well in logs)")]
    return []


def check_conventional(context: Context) -> List[Problem]:
    subject = message_subject(context)
    if (
        subject
        and not CONVENTIONAL.match(subject)
        and not subject.startswith(("Merge ", "Revert ", "fixup! ", "squash! ", "amend! "))
    ):
        return [Problem('the message does not start like "feat: …", "fix(parser): …" (Conventional Commits)')]
    return []


# ---- pre-push


def check_protected_push(context: Context) -> List[Problem]:
    protected = config_list("protectedBranches", "main,master")
    problems: List[Problem] = []
    for ref in context.pushed():
        branch = ref.remote_ref.replace("refs/heads/", "", 1)
        if branch not in protected:
            continue
        if ref.local_sha == NO_COMMIT:
            problems.append(Problem(f"deleting the protected branch {branch}"))
        elif ref.forced:
            problems.append(
                Problem(f"force push to the protected branch {branch}: commits on the remote would be lost")
            )
    return problems


def check_unfinished_commits(context: Context) -> List[Problem]:
    problems: List[Problem] = []
    for ref in context.pushed():
        for sha in ref.commits:
            subject = git("log", "-1", "--format=%s", sha).strip()
            if subject.startswith(("fixup! ", "squash! ", "amend! ")):
                problems.append(Problem(f"{sha[:8]} {subject}  (squash it first: git rebase -i --autosquash)"))
            elif re.match(r"(?i)^(?:wip|do not (?:push|merge)|dnm)\b", subject):
                problems.append(Problem(f"{sha[:8]} {subject}", WARN))
    return problems


def check_push_command(context: Context) -> List[Problem]:
    command = config("prePushCommand")
    if not command:
        return []
    root = git("rev-parse", "--show-toplevel").strip()
    say(paint(f"    running: {command}", "dim"))
    completed = subprocess.run(command, shell=True, cwd=root, check=False)
    return [Problem(f"{command!r} failed with exit code {completed.returncode}")] if completed.returncode else []


# ---- after merge / checkout

DEPENDENCY_FILES = (
    "requirements*.txt",
    "pyproject.toml",
    "uv.lock",
    "poetry.lock",
    "Pipfile.lock",
    "environment.yml",
    "environment.yaml",
    "setup.py",
    "setup.cfg",
    "package.json",
    "package-lock.json",
    "pnpm-lock.yaml",
    "yarn.lock",
    "Cargo.lock",
    "go.sum",
    "Gemfile.lock",
    "composer.lock",
    ".pre-commit-config.yaml",
)


def changed_after(context: Context) -> List[str]:
    if context.hook == "post-merge":
        return git("diff", "--name-only", "ORIG_HEAD", "HEAD", check=False).split("\n")
    previous, new, branch_switch = (context.arguments + ["", "", ""])[:3]
    if branch_switch != "1" or previous in ("", NO_COMMIT) or previous == new:
        return []
    return git("diff", "--name-only", previous, new, check=False).split("\n")


def check_dependency_changes(context: Context) -> List[Problem]:
    changed = [
        p
        for p in changed_after(context)
        if p and any(fnmatch.fnmatch(p.rsplit("/", 1)[-1], d) for d in DEPENDENCY_FILES)
    ]
    return [Problem(f"{path} changed: install or sync the dependencies again") for path in changed]


CHECKS: Dict[str, Tuple[Check, ...]] = {
    "pre-commit": (
        Check("secrets", "secrets", BLOCK, check_secrets),
        Check("secret-files", "secret files", BLOCK, check_secret_files),
        Check("personal-paths", "personal paths", WARN, check_personal_paths),
        Check("conflict-markers", "conflict markers", BLOCK, check_conflict_markers),
        Check("large-files", "large files", BLOCK, check_large_files),
        Check("filenames", "file names", BLOCK, check_filenames),
        Check("whitespace", "whitespace", WARN, check_whitespace),
        Check("debug-statements", "debug statements", WARN, check_debug_statements),
        Check("notebook-outputs", "notebook outputs", WARN, check_notebook_outputs),
        Check("ruff", "Ruff lint", BLOCK, check_ruff),
        Check("ruff-format", "Ruff format", WARN, check_ruff_format),
        Check("protected-commit", "commit on a protected branch", OFF, check_protected_commit),
    ),
    "commit-msg": (
        Check("subject-length", "subject length", WARN, check_subject_length),
        Check("conventional-commits", "Conventional Commits", OFF, check_conventional),
    ),
    "pre-push": (
        Check("protected-push", "force push / delete protected branch", BLOCK, check_protected_push),
        Check("unfinished-commits", "unfinished commits", BLOCK, check_unfinished_commits),
        Check("secrets", "secrets in pushed commits", BLOCK, check_secrets),
        Check("push-command", "pre-push command", BLOCK, check_push_command),
    ),
    "post-merge": (Check("dependency-changes", "dependency files", WARN, check_dependency_changes),),
    "post-checkout": (Check("dependency-changes", "dependency files", WARN, check_dependency_changes),),
}
BLOCKING_HOOKS = ("pre-commit", "commit-msg", "pre-push")
ACTION = {"pre-commit": "Commit", "commit-msg": "Commit", "pre-push": "Push"}
BYPASS = {
    "pre-commit": "git commit --no-verify",
    "commit-msg": "git commit --no-verify",
    "pre-push": "git push --no-verify",
}


# ---------------------------------------------------------------- running a hook


def severity_of(check: Check) -> str:
    value = config(check.name, check.default).lower()
    return value if value in (BLOCK, WARN, OFF) else check.default


def run_hook(hook: str, arguments: Sequence[str]) -> int:
    started = time.monotonic()
    stdin = sys.stdin.read() if hook == "pre-push" and not sys.stdin.isatty() else ""
    refreshed = refresh_installed_copy()
    code = run_pre_existing(hook, arguments, stdin)
    if code:
        return code
    context = Context(hook, arguments, stdin)
    skip = {s.strip() for s in (os.environ.get("SKIP", "") + "," + config("skip")).split(",") if s.strip()}
    verbose = config("verbose").lower() in ("true", "1", "yes")
    results: List[Result] = []
    for check in CHECKS[hook]:
        severity = severity_of(check)
        if severity == OFF or check.name in skip:
            if check.name in skip and severity != OFF:
                results.append((check, "skip", [], 0.0))
            continue
        check_started = time.monotonic()
        try:
            problems = check.run(context)
        except (OSError, RuntimeError, ValueError) as error:
            problems = [Problem(f"the check could not run: {error}", WARN)]
        status = "ok"
        if problems:
            status = BLOCK if severity == BLOCK and any(p.severity != WARN for p in problems) else "warn"
        results.append((check, status, problems, time.monotonic() - check_started))
    report(hook, results, context.notes, time.monotonic() - started, verbose, refreshed)
    blocked = hook in BLOCKING_HOOKS and any(status == BLOCK for _, status, _, _ in results)
    return 1 if blocked else 0


def plural(count: int, word: str) -> str:
    return f"{count} {word}" + ("" if count == 1 else "s")


Result = Tuple[Check, str, List[Problem], float]  # check, "ok"/"warn"/"block"/"skip", findings, seconds


def report(hook: str, results: List[Result], notes: List[str], seconds: float, verbose: bool, refreshed: str) -> None:
    blocked = [r for r in results if r[1] == BLOCK]
    warned = [r for r in results if r[1] == "warn"]
    if hook not in BLOCKING_HOOKS:
        # After a merge or checkout: only something worth knowing.
        for check, _status, problems, _ in warned:
            say(paint(f"{SYMBOLS['warn']} {check.title}:", "warn"))
            for problem in problems:
                say(f"    {problem.text}")
        return
    if not blocked and not warned and not verbose:
        if INTERACTIVE:  # quiet in editors and scripts; one line in a terminal
            ran = sum(1 for r in results if r[1] == "ok")
            say(
                paint(f"{SYMBOLS['ok']} {hook}: {ran} checks passed ({seconds:.1f} s)", "ok")
                + (paint(f"  {refreshed}", "dim") if refreshed else "")
            )
        return
    action = ACTION[hook]
    if blocked and not INTERACTIVE:
        # Editors such as VS Code show only one line of a failed hook: name the problem in it.
        first = blocked[0]
        # "Show Command Output" is the button of VS Code's error message that opens the full report.
        say(f'{action} blocked: {first[0].title}: {first[2][0].text}. Click "Show Command Output" for details.')
        say()
    say(paint(f"── {hook} " + "─" * max(3, 66 - len(hook)), "head"))
    width = max(len(check.title) for check, *_ in results) if results else 0
    for check, status, problems, check_seconds in results:
        if status == "ok" and not verbose:
            continue
        symbol = paint(SYMBOLS[status], {"ok": "ok", "warn": "warn", BLOCK: "block", "skip": "dim"}[status])
        detail = {
            BLOCK: plural(len(problems), "problem"),
            "warn": plural(len(problems), "warning"),
            "skip": "skipped",
            "ok": "",
        }[status]
        timing = paint(f"{check_seconds:.1f} s", "dim") if check_seconds >= 0.5 else ""
        say(f"  {symbol} {check.title.ljust(width)}  {detail}  {timing}".rstrip())
        for problem in problems[:20]:
            say(f"      {problem.text}")
            if problem.source:
                say(paint(f"        | {problem.source}", "dim"))
            if problem.link:
                say(paint(f"        {problem.link}", "dim"))
        if len(problems) > 20:
            say(paint(f"      … and {len(problems) - 20} more", "dim"))
    passed = sum(1 for r in results if r[1] == "ok")
    if passed and not verbose:
        say(paint(f"  {SYMBOLS['ok']} {plural(passed, 'other check')} passed", "dim"))
    for note in notes:
        say(paint(f"  note: {note}", "dim"))
    if refreshed:
        say(paint(f"  note: {refreshed}", "dim"))
    if any(problem.link for _check, _status, problems, _ in results for problem in problems):
        say(paint("  Ctrl+click a file:/// link to open its line (in VS Code and most terminals).", "dim"))
    say()
    if blocked:
        # "git -c" works in every shell and only for that one command (hooks see it through Git).
        once = " ".join(f"-c hooks.{check.name}=off" for check, *_ in blocked)
        command = "push" if hook == "pre-push" else 'commit -m "..."'
        say(paint(f"{SYMBOLS[BLOCK]} {action} blocked ({seconds:.1f} s). Fix it and try again, or once:", "block"))
        say(f"    skip these checks:  git {once} {command}")
        say(f"    skip all checks:    {BYPASS[hook]}")
        say(paint(f"    turn a check off:   git config hooks.{blocked[0][0].name} off", "dim"))
    else:
        say(paint(f"{SYMBOLS['warn']} {action} goes ahead with warnings ({seconds:.1f} s).", "warn"))


def find_shell() -> Optional[str]:
    shell = shutil.which("sh")
    if shell:
        return shell
    git_exe = shutil.which("git")
    if git_exe:
        candidate = Path(git_exe).resolve().parents[1] / "bin" / "sh.exe"
        if candidate.is_file():
            return str(candidate)
    return None


def run_pre_existing(hook: str, arguments: Sequence[str], stdin: str) -> int:
    """A hook that was installed before these is kept next to them and runs first."""
    previous = Path(__file__).with_name(hook + PRE_EXISTING)
    if Path(__file__).name != SCRIPT_NAME or not previous.is_file():
        return 0
    shell = find_shell()
    command = [shell, str(previous), *arguments] if shell else [str(previous), *arguments]
    completed = subprocess.run(command, input=stdin.encode("utf-8"), check=False)
    if completed.returncode:
        say(
            paint(
                f"{SYMBOLS[BLOCK]} the earlier {hook} hook ({previous.name}) failed with exit code {completed.returncode}",
                "block",
            )
        )
    return completed.returncode


def refresh_installed_copy() -> str:
    """While the folder it was installed from exists, the installed copy follows its git_hooks.py."""
    here = Path(__file__)
    record = here.with_name(SOURCE_FILE)
    if here.name != SCRIPT_NAME or not record.is_file():
        return ""
    source = Path(record.read_text(encoding="utf-8").strip())
    try:
        if (
            source.is_file()
            and hashlib.sha256(source.read_bytes()).digest() != hashlib.sha256(here.read_bytes()).digest()
        ):
            shutil.copyfile(source, here)  # takes effect from the next hook run
            return f"hooks updated from {source.parent}"
    except OSError:
        pass
    return ""


# ---------------------------------------------------------------- install


SHIM = """#!/bin/sh
# {marker} {version}: runs {script} (installed by git_hooks.py install; removed by uninstall).
hooks_dir=$(dirname "$0")
for python in python py python3; do
    if command -v "$python" >/dev/null 2>&1 && "$python" -c "import sys; sys.exit(sys.version_info < (3, 8))" >/dev/null 2>&1; then
        exec "$python" -B "$hooks_dir/{script}" run "$(basename "$0")" "$@"
    fi
done
echo "{hook} hook: Python 3.8 or newer was not found, so its checks could not run." >&2
{no_python}
"""


def hooks_dir(repo: Path) -> Tuple[Path, str]:
    """The folder Git runs hooks from, and core.hooksPath if one is set."""
    path = git("-C", str(repo), "rev-parse", "--path-format=absolute", "--git-path", "hooks", check=True).strip()
    custom = git("-C", str(repo), "config", "--get", "core.hooksPath", check=False).strip()
    return Path(path), custom


def is_ours(path: Path) -> bool:
    try:
        return MARKER in path.read_text(encoding="utf-8", errors="replace")[:300]
    except OSError:
        return False


def install(repo: Path, hooks: Sequence[str], force: bool) -> int:
    folder, custom = hooks_dir(repo)
    top = git("-C", str(repo), "rev-parse", "--show-toplevel").strip()
    say(paint(f"── Install Git hooks into {top}", "head"))
    if custom and not force:
        say(paint(f"{SYMBOLS[BLOCK]} This repository runs its hooks from core.hooksPath = {custom}", "block"))
        say("    That folder may belong to another tool or be part of the project. Installing there could")
        say("    replace its hooks. Use --force to install there anyway (earlier hooks are kept and still run),")
        say("    or remove the setting first: git config --unset core.hooksPath")
        return 1
    folder.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(Path(__file__), folder / SCRIPT_NAME)
    (folder / SOURCE_FILE).write_text(str(Path(__file__).resolve()), encoding="utf-8")
    for hook in hooks:
        target = folder / hook
        kept = ""
        if target.exists() and not is_ours(target):
            backup = target.with_name(hook + PRE_EXISTING)
            if backup.exists():
                say(
                    paint(
                        f"  {SYMBOLS[BLOCK]} {hook}: {target.name} and {backup.name} both exist; left as they are",
                        "block",
                    )
                )
                continue
            target.rename(backup)
            kept = f" (the earlier {hook} hook is kept as {backup.name} and runs first)"
        no_python = (
            "exit 0"
            if hook not in BLOCKING_HOOKS
            else 'echo "Install Python, or skip once with --no-verify." >&2\nexit 1'
        )
        text = SHIM.format(marker=MARKER, version=VERSION, script=SCRIPT_NAME, hook=hook, no_python=no_python)
        target.write_bytes(text.encode("utf-8"))  # LF line endings: sh needs them
        if os.name != "nt":
            target.chmod(0o755)
        say(f"  {paint(SYMBOLS['ok'], 'ok')} {hook}{kept}")
    say(paint(f"Installed in {folder}. Settings: git config hooks.<check> block|warn|off (see README.md).", "dim"))
    return 0


def uninstall(repo: Path, hooks: Sequence[str]) -> int:
    folder, _ = hooks_dir(repo)
    say(paint(f"── Remove Git hooks from {folder}", "head"))
    for hook in hooks:
        target = folder / hook
        backup = target.with_name(hook + PRE_EXISTING)
        if target.exists() and is_ours(target):
            target.unlink()
            note = ""
            if backup.exists():
                backup.rename(target)
                note = " (the earlier hook is back)"
            say(f"  {paint(SYMBOLS['ok'], 'ok')} {hook} removed{note}")
    if not any(is_ours(folder / hook) for hook in HOOKS):
        for name in (SCRIPT_NAME, SOURCE_FILE):
            if (folder / name).exists():
                (folder / name).unlink()
    return 0


def status(repo: Path) -> int:
    folder, custom = hooks_dir(repo)
    say(paint(f"── Git hooks of {git('-C', str(repo), 'rev-parse', '--show-toplevel').strip()}", "head"))
    say(f"  folder  {folder}" + (f"  (core.hooksPath = {custom})" if custom else ""))
    source = folder / SOURCE_FILE
    if source.is_file():
        say(f"  source  {source.read_text(encoding='utf-8').strip()}")
    os.chdir(git("-C", str(repo), "rev-parse", "--show-toplevel").strip())  # its settings, not the caller's
    for hook in HOOKS:
        target = folder / hook
        state = "installed" if is_ours(target) else "another hook" if target.exists() else "not installed"
        if (folder / (hook + PRE_EXISTING)).exists():
            state += " (+ earlier hook)"
        say(f"  {hook.ljust(14)} {state}")
        if is_ours(target):
            for check in CHECKS[hook]:
                say(paint(f"      {check.name.ljust(20)} {severity_of(check)}", "dim"))
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("install", "uninstall"):
        command = sub.add_parser(name)
        command.add_argument("hooks", nargs="*", metavar="HOOK", help="default: all of " + ", ".join(HOOKS))
        command.add_argument("--repo", default=".")
        if name == "install":
            command.add_argument("--force", action="store_true", help="also install into a core.hooksPath folder")
    command = sub.add_parser("status")
    command.add_argument("--repo", default=".")
    command = sub.add_parser("run")
    command.add_argument("hook", choices=HOOKS)
    command.add_argument("arguments", nargs=argparse.REMAINDER)
    arguments = parser.parse_args(argv)
    try:
        if arguments.command == "run":
            return run_hook(arguments.hook, arguments.arguments)
        repo = Path(arguments.repo).resolve()
        if arguments.command == "status":
            return status(repo)
        hooks = arguments.hooks or list(HOOKS)
        unknown = [hook for hook in hooks if hook not in HOOKS]
        if unknown:
            parser.error(f"unknown hook {unknown[0]!r}; choose from {', '.join(HOOKS)}")
        if arguments.command == "install":
            return install(repo, hooks, arguments.force)
        return uninstall(repo, hooks)
    except (OSError, RuntimeError) as error:
        say(paint(f"{SYMBOLS[BLOCK]} {error}", "block"))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

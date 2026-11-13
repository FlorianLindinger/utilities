# Git hooks

Checks that Git runs for you: before a commit, before a push, and after a pull or branch switch.
They stop the mistakes that are hard to undo once they are pushed (a token in the history, a
force push over `main`) and warn about the ones that are merely annoying.

No dependencies: one Python file (3.8+, standard library) and Git. Works with Git for Windows,
in a terminal and in VS Code.

## Quick start

1. Copy this `git_hooks` folder anywhere into the repository you want to protect.
2. Double-click **`install_all_hooks.bat`** (or one of the `install_<hook>.bat` files).
3. Commit as usual. When everything passes you see one line in a terminal, nothing in VS Code.

The installer copies what the hooks need into the repository's `.git/hooks`, so **the folder you
copied can be deleted afterwards** (or left out of Git) and the hooks keep working. While the
folder exists, every hook run refreshes the installed copy from it: edit `git_hooks.py` here and
the next commit uses the new version. Run the install again whenever you want to be sure; it is
safe to repeat.

To install into another repository without copying the folder, drop that repository's folder onto
a batch file, or run `python git_hooks.py install --repo C:\path\to\repo`.

| Batch file | Installs |
| --- | --- |
| `install_all_hooks.bat` | everything below |
| `install_pre-commit.bat` | checks on what you are about to commit |
| `install_commit-msg.bat` | checks on the commit message |
| `install_pre-push.bat` | checks on what you are about to publish |
| `install_dependency_reminder.bat` | post-merge and post-checkout: a note when dependency files changed |
| `uninstall_hooks.bat` | removes them again; hooks that were there before come back |
| `hooks_status.bat` | what is installed, and every check's setting |

Hooks that already exist are not lost: an earlier `pre-commit` is renamed to
`pre-commit.pre-existing` and still runs first. If the repository uses `core.hooksPath` (another
hook tool, or hooks kept in the project), the installer stops and explains instead of mixing in.

## When you want it

- **Yes, for any repository you push somewhere:** the secret checks alone are worth it. A token
  that reaches GitHub has to be revoked, and removing it from the history is painful.
- **Especially for public repositories, notebooks and data projects:** home-folder paths with your
  user name, notebook outputs and large files are the usual unintended leaks.
- **Teams:** hooks are per clone and never pushed, so everyone installs them once. A hook is a
  safety net, not an enforcement (`--no-verify` skips it); for rules everyone must follow, add the
  matching GitHub workflow from `../github_workflows`.
- **Not needed** for scratch repositories that never leave your PC.

For many languages and community hooks, the [pre-commit](https://pre-commit.com/) framework is the
bigger tool; it needs a configuration file in the project and installs its hooks per language.
These hooks cover the language-independent basics with nothing to install.

## The checks

`block` stops the commit or push, `warn` lets it through with a note, `off` skips the check.

### pre-commit (before each commit; checks only what is staged)

| Check | Default | What it finds |
| --- | --- | --- |
| `secrets` | block | tokens and keys in their known formats (GitHub, GitLab, AWS, Google, Slack, Stripe, OpenAI, Anthropic, Hugging Face, npm, PyPI, private keys, passwords in URLs), masked in the output; a value assigned to a name like `password` or `api_key` is a warning |
| `secret-files` | block | new files that usually hold secrets: `.env`, `*.pem`, `*.key`, `id_rsa`, `credentials.json`, `.pypirc`, ... (`.env.example` is fine) |
| `personal-paths` | warn | `C:\Users\<name>\`, `/home/<name>/`, `/Users/<name>/` (not URLs) |
| `conflict-markers` | block | `<<<<<<<`, `>>>>>>>` and `=======` left over from a merge |
| `large-files` | block | files over 5 MB (`git config hooks.maxFileMB 20`) |
| `filenames` | block | names Windows cannot check out (`aux.py`, `a:b.txt`, trailing dots) and names that differ only in letter case |
| `whitespace` | warn | trailing spaces and space-before-tab (Git's own `--check`) |
| `debug-statements` | warn | `breakpoint()`, `import pdb`, `debugger;` |
| `notebook-outputs` | warn | `.ipynb` files saved with cell outputs (often large, sometimes private) |
| `ruff` / `ruff-format` | block / warn | Ruff lint and format of the staged Python files; only in projects with a Ruff configuration (`ruff.toml` or `[tool.ruff]`) and only if `ruff` is on PATH |
| `protected-commit` | off | committing directly on `main` or `master` (for branch-based workflows) |

### commit-msg

| Check | Default | What it finds |
| --- | --- | --- |
| `subject-length` | warn | a first line longer than 72 characters (`hooks.subjectMaxLength`) |
| `conventional-commits` | off | messages not like `feat: ...` or `fix(parser): ...` ([Conventional Commits](https://www.conventionalcommits.org/)) |

### pre-push

| Check | Default | What it finds |
| --- | --- | --- |
| `protected-push` | block | a force push that would drop commits from `main`/`master`, or deleting them (`hooks.protectedBranches`) |
| `unfinished-commits` | block | `fixup!`/`squash!` commits (squash them with `git rebase -i --autosquash`); `WIP` commits are a warning |
| `secrets` | block | the secret patterns again, over every commit being pushed: catches commits made with `--no-verify` |
| `push-command` | block | runs `hooks.prePushCommand` if you set one, e.g. `git config hooks.prePushCommand "python -m pytest -q"` |

### post-merge, post-checkout

`dependency-changes` prints a note when a pull or branch switch changed `requirements*.txt`,
`pyproject.toml`, `uv.lock`, `package-lock.json`, ... so you install them again. It never stops anything.

## Settings and skipping

Settings are Git configuration: per repository, or for all of them with `--global`.

```bat
git config hooks.whitespace off                 :: a check: block, warn or off
git config hooks.protected-commit block
git config hooks.maxFileMB 20
git config hooks.protectedBranches main,release
git config hooks.prePushCommand "python -m pytest -q"
git config hooks.verbose true                   :: list every check, also when all pass
git config --global hooks.notebook-outputs off  :: for every repository on this PC
```

When something is blocked, the output says how to go ahead anyway:

```bat
git -c hooks.secrets=off commit -m "..."        :: skip one check, for this command only
git commit --no-verify -m "..."                 :: skip all commit checks once
git push --no-verify                            :: skip all push checks once
```

To accept one line for good, put `pragma: allowlist secret` (or `hooks: ignore`) in it.

## How it looks

```text
Commit blocked: secrets: app.py:1  GitHub token  ghp_…r8. Click "Show Command Output" for details.

── pre-commit ──────────────────────────────────────────────────────
  ✗ secrets           1 problem
      app.py:1  GitHub token  ghp_…r8
        | token = "ghp_…r8"
        file:///D:/projects/app/app.py#L1
  ! whitespace        1 warning
      app.py:2: trailing whitespace.
        file:///D:/projects/app/app.py#L2
  ✓ 9 other checks passed
  Ctrl+click a file:/// link to open its line (in VS Code and most terminals).

✗ Commit blocked (0.4 s). Fix it and try again, or once:
    skip these checks:  git -c hooks.secrets=off commit -m "..."
    skip all checks:    git commit --no-verify
    turn a check off:   git config hooks.secrets off
```

In a terminal it is colored and a passing commit shows a single `✓ pre-commit: 11 checks passed
(0.3 s)`. Outside a terminal (VS Code, other Git tools) the report starts with a one-line
summary, because those tools show only a short error message; the full report is under
**Show Command Output** in VS Code. Each finding in a file shows its line (secrets masked) and a
`file:///…#L<line>` link, because that page is plain text where only full links can be clicked.
Findings in commits being pushed get no link: the file on disk may have changed since.

## More hook ideas

Not included because they depend on the project, but easy to add as a check in `git_hooks.py` or
with `hooks.prePushCommand`:

- run the test suite or a type checker before a push (`prePushCommand`);
- block commits whose author email is a private address (GitHub's `noreply` address instead);
- `prepare-commit-msg`: put the ticket number from the branch name (`feature/ABC-123-...`) into the message;
- refuse commits to a branch that is behind its remote, or remind to pull first;
- `post-checkout`: regenerate files that are derived from tracked ones;
- check that a version number or changelog entry changed when release files did.

## Tests

`python tests/test_git_hooks.py` installs the hooks into throwaway repositories and lets Git run
them for real (commits, a bare remote for pushes, branch switches).

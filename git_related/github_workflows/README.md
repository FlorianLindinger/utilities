# GitHub workflows

Ready-made GitHub Actions workflows to copy into a repository. Each file is self-contained: copy
it, commit it, push it. Nothing else to set up.

| File | Copy to | Runs | When you want it |
| --- | --- | --- | --- |
| `workflows/leaks.yml` | `.github/workflows/` | [Gitleaks](https://github.com/gitleaks/gitleaks) over the whole history, on every push and pull request | any repository that is or may become public, and every repository others push to |
| `workflows/python-lint.yml` | `.github/workflows/` | Ruff lint and format check | Python projects with a Ruff configuration |
| `workflows/python-tests.yml` | `.github/workflows/` | pytest on Windows and Linux, Python 3.10 and 3.14 | Python projects with tests (pytest fails when it finds none) |
| `dependabot.yml` | `.github/` (not into `workflows`) | weekly pull requests that update the versions above and your Python dependencies | every repository with workflows: pinned versions only stay safe if something updates them |

## How to use

1. In your repository, create the folder `.github/workflows` if it does not exist.
2. Copy the files you want (keep the names, or rename them; the name only matters to you).
3. Commit and push. The **Actions** tab on GitHub shows the runs; a failed run marks the commit
   and the pull request with a red cross.

To require a passing check before merging, add it in the repository settings under
**Rules → Rulesets** (or **Branches → Branch protection**): "Require status checks to pass".

## Hooks or workflows?

The [Git hooks](../git_hooks) check on your PC, before anything leaves it; that is where a secret
should be caught, because a pushed secret has to be revoked. But hooks are per clone and can be
skipped (`--no-verify`). A workflow runs on GitHub for every push, from everyone, and cannot be
skipped. Use both for what matters: the hooks for fast feedback, the workflow as the backstop.

## Choices made in these files

- **Pinned versions** (`actions/checkout@v7.0.1`, Gitleaks 8.30.1): a workflow does not change
  under you when an action publishes a new release. `dependabot.yml` proposes the updates.
- **Least privilege:** `permissions: contents: read` and `persist-credentials: false`, so a step
  cannot push or use the repository token beyond reading.
- **Gitleaks without its GitHub action:** the action needs a license key for organization
  accounts; the program itself needs none. The workflow downloads it from the official release and
  checks it against the release's checksum file.
- **uv for Python:** one fast tool for the Python version and the packages; the test workflow
  adapts to `uv.lock`, `pyproject.toml` or `requirements.txt`.

## Adjusting

- Only on the main branch: replace `push:` with `push: { branches: [main] }`.
- Other Python versions or only Windows: edit the `matrix` in `python-tests.yml`.
- False positives in the leak check: `gitleaks:allow` on the line, or a `.gitleaksignore` file
  with the fingerprints Gitleaks prints.

## More ideas

Not included, but common additions:

- **CodeQL** (GitHub's code scanning, free for public repositories): Security tab → Code scanning → set up.
- **Release on a tag:** build and attach files to a GitHub release when you push `v1.2.3`.
- **Scheduled runs:** add `schedule: - cron: "0 6 * * 1"` to run the tests weekly, catching
  breakage from new dependency versions.
- **Type checking:** a step with `uvx pyrefly check` or `uvx mypy .` in the lint workflow.

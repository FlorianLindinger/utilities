# Local Pyrefly Profile Switcher

The existing Commands status button calls this helper. It supports Local,
Basic, Default, Strict, Custom, Off, and editing the shared custom rules.

- Local searches upward from the active Python file or notebook (or the selected workspace folder when neither is active), including parents outside the workspace. It accepts `pyrefly.toml` or a `[tool.pyrefly]` section (including subtables) in `pyproject.toml`. Following Pyrefly project-root discovery, it stops at the nearest `pyproject.toml`, `setup.py`, `mypy.ini`, or `pyrightconfig.json`, or the filesystem root. If no native Pyrefly config governs that location, it warns and keeps the current profile; otherwise it clears `configPath` and uses `auto`. This guard checks the active location at selection time; Pyrefly still discovers configs separately for other source files.
- Basic, Default, and Strict select explicit generated preset configs. Local
  project configs therefore cannot override the selected preset.
- Custom generates a config that extends `pyreflyProfiles.customConfigPath`.
- Off clears the explicit config and disables type diagnostics.

Generated configs live in VS Code extension storage, not in project folders.
They set `import-root` and explicit include patterns for only the selected
workspace folder. Both Windows drive-letter cases are included because Pyrefly
glob matching can distinguish them. Shared rules should contain rule settings
and their base preset, without repository-wide `project-includes`.

Changes target the active editor's workspace folder. In a multi-folder workspace
without an identifiable active folder, the command asks which folder to change.
Settings for other folders and profiles are retained.

Run the local tests with `node --test test.js`. The helper has no npm dependencies.

## Build and install

Run `./install.cmd` on Windows (or `./install.ps1` where scripts are enabled)
to build the VSIX and install it only in the Default profile. Profiles such as
Agents that inherit Default's extensions are covered automatically. Java, C#,
and C++/Arduino are not modified by the installer.

```powershell
./install.cmd
./install.cmd -BuildOnly
```

The installer requires VS Code's `code` command on PATH. Use `-CodeCommand`
with the full path to `code.cmd` if necessary. VSIX files are written under
`dist/`, which is excluded from Git. The source lives in
`utilities/vscode related/vscode-pyrefly-profiles`; moving it does not affect
installed extension copies.

The Windows launcher permits this script for its own PowerShell process only;
it does not change the machine or user execution policy.

The Windows launcher reports success or failure and waits for a keypress before closing, preserving errors for review.

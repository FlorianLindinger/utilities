# Codex Usage custom colors

Backup of the patched renderer for `ganymede404.vscode-codex-usage` version **0.2.4**.

The hourly and weekly windows have independent colors based on percentage used:

| Used | Color |
| --- | --- |
| Below 25% | Green `#73c991` |
| 25% to below 50% | Yellow `#e5c07b` |
| 50% to below 75% | Orange `#e9953a` |
| 75% and above | Red `#f14c4c` |

These colors also apply to tooltip bars and usage-summary indicators.

## Restore

Double-click `change_color_scheme.bat`, or run from the utilities repository:

```bat
"vscode related\codex-usage\change_color_scheme.bat"
```

Then run **Developer: Reload Window** in VS Code.
The script keeps the existing renderer as `statusBar.js.before-custom-colors` before replacing it.
For a different installation location, pass the extension directory as the first argument:

```bat
change_color_scheme.bat "D:\path\to\ganymede404.vscode-codex-usage-0.2.4"
```

Extension updates can overwrite the installed patch. This backup remains in the repository.
The restore script intentionally checks for version 0.2.4; a newer version needs the changes ported and verified against its code.
VS Code Settings Sync does not back up edits inside installed extensions.
To retain the remaining-percentage display, keep this User setting:

```json
"codexUsage.showRemaining": true
```

Commit this directory to Git, or copy them to your normal backup location, to keep a second copy.

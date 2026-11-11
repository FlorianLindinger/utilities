@echo off
setlocal
rem --- Console presentation: NO_COLOR disables ANSI; UTILITIES_QUIET hides headings. ---
set "UTIL_UI_ESC="
set "UTIL_UI_INFO="
set "UTIL_UI_OK="
set "UTIL_UI_WARN="
set "UTIL_UI_ERROR="
set "UTIL_UI_RESET="
if not defined NO_COLOR if /I not "%TERM%"=="dumb" for /F "delims=#" %%E in ('"prompt #$E# & for %%E in (1) do rem"') do set "UTIL_UI_ESC=%%E"
if defined UTIL_UI_ESC set "UTIL_UI_INFO=%UTIL_UI_ESC%[96m"
if defined UTIL_UI_ESC set "UTIL_UI_OK=%UTIL_UI_ESC%[92m"
if defined UTIL_UI_ESC set "UTIL_UI_WARN=%UTIL_UI_ESC%[93m"
if defined UTIL_UI_ESC set "UTIL_UI_ERROR=%UTIL_UI_ESC%[91m"
if defined UTIL_UI_ESC set "UTIL_UI_RESET=%UTIL_UI_ESC%[0m"
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%============================================================%UTIL_UI_RESET%
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%  Export enabled VS Code extensions%UTIL_UI_RESET%
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%============================================================%UTIL_UI_RESET%
rem --- End console presentation. ---

REM Export installed extensions enabled for the current folder (or --workspace).
REM Requires Python 3 on PATH, or the Windows py launcher. No extra packages.
REM Optional: --profile "Profile Name", --user-data-dir PATH, --output PATH.
REM Enabled means saved enablement, not just extensions activated this session.
set "EXPORT_SELF=%~f0"
where python >nul 2>nul
if errorlevel 1 goto use_py
python -c "import os,sys; from pathlib import Path; p=Path(os.environ['EXPORT_SELF']); exec(compile(p.read_text(encoding='utf-8').split(chr(10)+'# PYTHON_PAYLOAD'+chr(10),1)[1],str(p),'exec'))" %*
goto finish
:use_py
py -3 -c "import os,sys; from pathlib import Path; p=Path(os.environ['EXPORT_SELF']); exec(compile(p.read_text(encoding='utf-8').split(chr(10)+'# PYTHON_PAYLOAD'+chr(10),1)[1],str(p),'exec'))" %*
:finish
set "EXPORT_RESULT=%errorlevel%"
if "%EXPORT_RESULT%"=="0" (
    echo:%UTIL_UI_OK%[OK] Export completed.%UTIL_UI_RESET%
) else (
    >&2 echo:%UTIL_UI_ERROR%[ERROR] Export failed. Exit code: %EXPORT_RESULT%.%UTIL_UI_RESET%
)
if not defined EXPORT_NO_PAUSE pause
exit /b %EXPORT_RESULT%
# PYTHON_PAYLOAD
import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
from urllib.parse import unquote, urlparse


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def identifiers(database, key):
    """Read saved VS Code state without creating or modifying a database."""
    with closing(sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True)) as connection:
        row = connection.execute("SELECT value FROM ItemTable WHERE key = ?", (key,)).fetchone()
    return {item["id"].lower() for item in json.loads(row[0] if row else "[]")}


def uri_path(uri):
    parsed = urlparse(uri)
    if parsed.scheme != "file":
        return None
    path = unquote(parsed.path)
    if parsed.netloc:
        path = "//" + parsed.netloc + path
    elif len(path) > 2 and path[0] == "/" and path[2] == ":":
        path = path[1:]
    return Path(path).resolve()


def export(args):
    """Combine profile defaults with saved workspace overrides."""
    cli = shutil.which("code") or shutil.which("code-insiders")
    if not cli:
        raise RuntimeError("VS Code CLI not found on PATH.")
    product = "Code - Insiders" if "insiders" in Path(cli).name else "Code"
    user_data = args.user_data_dir or Path(os.environ["APPDATA"]) / product
    user = user_data / "User"
    storage = read_json(user / "globalStorage" / "storage.json")
    workspace = args.workspace.resolve()
    profile_name = args.profile
    if not profile_name:
        associations = storage.get("profileAssociations", {}).get("workspaces", {})
        profile_id = next((value for uri, value in associations.items()
                           if uri_path(uri) == workspace), "__default__profile__")
        if profile_id != "__default__profile__":
            profile_name = next((p["name"] for p in storage.get("userDataProfiles", [])
                                 if p["location"] == profile_id), None)
            if not profile_name:
                raise RuntimeError("Cannot resolve workspace profile; supply --profile.")
    profile_dir = user
    if profile_name and profile_name != "Default":
        profile = next((p for p in storage.get("userDataProfiles", [])
                        if p["name"] == profile_name), None)
        if profile is None:
            raise RuntimeError("Unknown profile: " + profile_name)
        if not profile.get("useDefaultFlags", {}).get("extensions", False):
            profile_dir = user / "profiles" / profile["location"]
    key = "extensionsIdentifiers/disabled"
    disabled = identifiers(profile_dir / "globalStorage" / "state.vscdb", key)
    matches = []
    for metadata in (user / "workspaceStorage").glob("*/workspace.json"):
        record = read_json(metadata)
        uri = record.get("folder") or record.get("workspace")
        if uri and uri_path(uri) == workspace:
            matches.append(metadata.parent / "state.vscdb")
    if len(matches) > 1:
        raise RuntimeError("Multiple saved workspace states found; refusing an ambiguous export.")
    if matches:
        enabled = identifiers(matches[0], "extensionsIdentifiers/enabled")
        disabled = (disabled - enabled) | identifiers(matches[0], key)
    command = [cli, "--user-data-dir", str(user_data), "--list-extensions"]
    if profile_name:
        command.extend(["--profile", profile_name])
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    if result.stderr.strip():
        print(result.stderr.strip(), file=sys.stderr)
    extensions = sorted({line.strip() for line in result.stdout.splitlines()
                         if line.strip() and line.strip().lower() not in disabled})
    # Reject unexpected CLI output rather than putting diagnostics in recommendations.
    if any("." not in item or any(c.isspace() for c in item) for item in extensions):
        raise RuntimeError("Unexpected output from VS Code --list-extensions.")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"recommendations": extensions}, indent=2) + "\n",
                           encoding="utf-8")
    print(f"Exported {len(extensions)} enabled extensions to {args.output}")
    print(f"Profile: {profile_name or 'Default'}; workspace: {workspace}")
    print("Uses saved enablement; runtime activation, trust and compatibility restrictions are not evaluated.")


def main():
    parser = argparse.ArgumentParser(description="Export saved enabled VS Code extensions.")
    parser.add_argument("--workspace", type=Path, default=Path.cwd(),
                        help="Folder or .code-workspace file (default: current folder)")
    parser.add_argument("--profile", help="Profile name (default: saved workspace association)")
    parser.add_argument("--user-data-dir", type=Path, help="Custom VS Code user-data directory")
    parser.add_argument("--output", type=Path, default=Path(os.environ["EXPORT_SELF"]).parent / "output" / "enabled_extensions.json")
    args = parser.parse_args()
    try:
        export(args)
    except (OSError, ValueError, KeyError, TypeError, sqlite3.Error,
            subprocess.CalledProcessError, RuntimeError) as error:
        print(f"Export failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

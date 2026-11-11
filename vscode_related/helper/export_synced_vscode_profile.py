"""Export a VS Code profile from a sync snapshot with current extension exclusions."""

import argparse
import json
import os
import re
import sqlite3
import sys
from contextlib import closing
from datetime import datetime
from pathlib import Path
from urllib.parse import unquote, urlparse

from filter_sync_settings import extension_manifests, filter_settings, restore_section_comments, settings_values


def read_json(path: Path):
    """Read VS Code's UTF-8 JSON files without changing them."""
    return json.loads(path.read_text(encoding="utf-8-sig"))


def uri_path(uri: str) -> Path | None:
    parsed = urlparse(uri)
    if parsed.scheme != "file":
        return None
    path = unquote(parsed.path)
    if parsed.netloc:
        path = "//" + parsed.netloc + path
    elif len(path) > 2 and path[0] == "/" and path[2] == ":":
        path = path[1:]
    return Path(path).resolve()


def current_profile_name(user: Path, storage: dict, workspace: Path | None) -> str:
    """Resolve the profile associated with a workspace or the last active window."""
    if workspace is None:
        active = storage.get("windowsState", {}).get("lastActiveWindow", {})
        workspace_id = active.get("workspaceIdentifier", {}).get("id")
        if workspace_id:
            metadata = user / "workspaceStorage" / workspace_id / "workspace.json"
            if metadata.is_file():
                record = read_json(metadata)
                workspace = uri_path(record.get("folder") or record.get("workspace") or "")
    if workspace is None:
        raise RuntimeError("Cannot identify the active VS Code workspace; pass --profile NAME.")
    associations = storage.get("profileAssociations", {}).get("workspaces", {})
    profile_id = next(
        (value for uri, value in associations.items() if uri_path(uri) == workspace),
        "__default__profile__",
    )
    if profile_id == "__default__profile__":
        return "Default"
    for profile in storage.get("userDataProfiles", []):
        if profile.get("location") == profile_id:
            return profile["name"]
    raise RuntimeError("The workspace profile is unknown; pass --profile NAME.")


def select_profile(user: Path, storage: dict, name: str) -> tuple[dict, str]:
    if name == "Default":
        return {}, ""
    for profile in storage.get("userDataProfiles", []):
        if profile.get("name") == name:
            return profile, profile["location"]
    raise RuntimeError(f"Unknown VS Code profile: {name}")


def category_directory(user: Path, profile: dict, category: str) -> Path:
    if not profile or profile.get("useDefaultFlags", {}).get(category, False):
        return user
    return user / "profiles" / profile["location"]


def synced_settings(user: Path, profile: dict, settings_file: Path) -> str:
    """Verify newer local content against sync, ignoring excluded values and comments."""
    if not settings_file.is_file():
        raise RuntimeError(f"Profile settings file is missing: {settings_file}")
    profile_id = "" if settings_file.parent == user else profile["location"]
    sync_root = user / "sync" / profile_id if profile_id else user / "sync"
    snapshot = sync_root / "settings" / "lastSyncsettings.json"
    if not snapshot.is_file():
        raise RuntimeError(f"No synced settings snapshot for this profile: {snapshot}")
    content = read_json(snapshot).get("syncData", {}).get("content")
    if not isinstance(content, str):
        raise RuntimeError("The Settings Sync snapshot has no settings content.")
    payload = json.loads(content)
    if not isinstance(payload, dict) or not isinstance(payload.get("settings"), str):
        raise RuntimeError("The Settings Sync snapshot has an unexpected format.")
    with settings_file.open(encoding="utf-8-sig", newline="") as source:
        local_settings = source.read()
    manifests = list(extension_manifests())
    snapshot_settings = filter_settings(payload["settings"], manifests, local_settings)
    local_filtered = filter_settings(local_settings, manifests, local_settings)
    if settings_values(local_filtered) == settings_values(snapshot_settings):
        # Sync need not rewrite its snapshot after comment/excluded-setting edits.
        # Prefer local text so all current headings, spacing and line endings survive.
        payload["settings"] = local_filtered
    elif snapshot.stat().st_mtime_ns < settings_file.stat().st_mtime_ns:
        raise RuntimeError("Local synced setting values differ from Settings Sync. Let VS Code sync, then rerun.")
    else:
        payload["settings"] = restore_section_comments(snapshot_settings, local_settings)
    return json.dumps(payload, ensure_ascii=False)


def disabled_extensions(database: Path) -> set[str]:
    """Read saved profile enablement from SQLite without writing to VS Code."""
    if not database.is_file():
        raise RuntimeError(f"Profile extension state is missing: {database}")
    with closing(sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True)) as connection:
        row = connection.execute(
            "SELECT value FROM ItemTable WHERE key = ?",
            ("extensionsIdentifiers/disabled",),
        ).fetchone()
    return {item["id"].lower() for item in json.loads(row[0] if row else "[]")}


def profile_extensions(source: Path, database: Path) -> str:
    """Convert the installed extension list into VS Code's profile format."""
    items = read_json(source)
    if not isinstance(items, list):
        raise RuntimeError(f"Invalid extension list: {source}")
    disabled = disabled_extensions(database)
    result = []
    for item in items:
        identifier = item.get("identifier", {})
        extension_id = identifier.get("id")
        if not extension_id:
            continue
        metadata = item.get("metadata") or {}
        entry = {"identifier": identifier}
        if metadata.get("pinned") and item.get("version"):
            entry["version"] = item["version"]
        elif metadata.get("preRelease") or metadata.get("isPreReleaseVersion"):
            entry["preRelease"] = True
        if extension_id.lower() in disabled:
            entry["disabled"] = True
        result.append(entry)
    return json.dumps(result, ensure_ascii=False, separators=(",", ":"))


def add_optional_file(template: dict, source: Path, key: str) -> None:
    if not source.is_file():
        return
    content = source.read_text(encoding="utf-8-sig")
    if key == "keybindings":
        template[key] = json.dumps({"keybindings": content, "platform": 3})
    elif key == "tasks":
        template[key] = json.dumps({"tasks": content})


def add_snippets(template: dict, directory: Path) -> None:
    if not directory.is_dir():
        return
    snippets = {
        file.relative_to(directory).as_posix(): file.read_text(encoding="utf-8-sig")
        for file in directory.rglob("*")
        if file.is_file() and file.suffix in {".json", ".code-snippets"}
    }
    if snippets:
        template["snippets"] = json.dumps({"snippets": snippets}, ensure_ascii=False)


def export(args: argparse.Namespace) -> Path:
    user_data = args.user_data_dir or Path(os.environ["APPDATA"]) / "Code"
    user = user_data / "User"
    storage = read_json(user / "globalStorage" / "storage.json")
    name = args.profile or current_profile_name(user, storage, args.workspace)
    profile, _ = select_profile(user, storage, name)
    settings_dir = category_directory(user, profile, "settings")
    extensions_dir = category_directory(user, profile, "extensions")
    settings = synced_settings(user, profile, settings_dir / "settings.json")
    if extensions_dir == user:
        extensions_file = args.extensions_dir or Path.home() / ".vscode" / "extensions" / "extensions.json"
    else:
        extensions_file = extensions_dir / "extensions.json"
    if not extensions_file.is_file():
        raise RuntimeError(f"Profile extension list is missing: {extensions_file}")
    state_db = extensions_dir / "globalStorage" / "state.vscdb"
    template = {
        "name": name,
        "settings": settings,
        "extensions": profile_extensions(extensions_file, state_db),
    }
    for category, filename in (("keybindings", "keybindings.json"), ("tasks", "tasks.json")):
        source_dir = category_directory(user, profile, category)
        add_optional_file(template, source_dir / filename, category)
    add_snippets(template, category_directory(user, profile, "snippets") / "snippets")
    output = args.output
    if output is None:
        export_dir = Path(__file__).resolve().parent.parent / "output"
        safe_name = re.sub(r"[^A-Za-z0-9._-]+", "_", name).strip("._") or "profile"
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        output = export_dir / f"{safe_name}-synced-{stamp}.code-profile"
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists() and not args.overwrite:
        raise RuntimeError(f"Output already exists: {output}. Pass --overwrite to replace it.")
    output.write_text(json.dumps(template, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Exported profile '{name}' to {output}")
    print(f"Included {len(json.loads(template['extensions']))} extensions with saved profile enablement.")
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", help="Profile name; default is the last active VS Code workspace profile")
    parser.add_argument("--workspace", type=Path, help="Select the profile associated with this workspace")
    parser.add_argument("--output", type=Path, help="Destination .code-profile file")
    parser.add_argument("--overwrite", action="store_true", help="Replace an existing export")
    parser.add_argument("--user-data-dir", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--extensions-dir", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        export(args)
    except (OSError, ValueError, KeyError, sqlite3.Error, RuntimeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

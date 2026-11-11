"""Export user settings from VS Code's filtered Settings Sync snapshot."""

import argparse
import json
import os
import sys
from pathlib import Path

from export_synced_vscode_profile import (
    category_directory,
    current_profile_name,
    read_json,
    select_profile,
    synced_settings,
)


def export(args: argparse.Namespace) -> Path:
    """Preserve the synced settings text, including JSONC comments."""
    user_data = args.user_data_dir or Path(os.environ["APPDATA"]) / "Code"
    user = user_data / "User"
    storage = read_json(user / "globalStorage" / "storage.json")
    name = args.profile or current_profile_name(user, storage, args.workspace)
    profile, _ = select_profile(user, storage, name)
    settings_dir = category_directory(user, profile, "settings")
    # The sync payload already excludes machine settings and user sync exclusions.
    # Compare synced values so comment/excluded-setting edits need no new snapshot.
    payload = synced_settings(user, profile, settings_dir / "settings.json")
    settings = json.loads(payload)["settings"]
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    # Sync text already has line endings; Windows translation would double CRs.
    output.write_text(settings.rstrip("\r\n") + "\n", encoding="utf-8", newline="")
    print(f"Exported synced user settings for profile '{name}' to {output}")
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", help="Profile name; default is the last active VS Code workspace profile")
    parser.add_argument("--workspace", type=Path, help="Select the profile associated with this workspace")
    parser.add_argument("--user-data-dir", type=Path, help="VS Code user-data directory (default: APPDATA/Code)")
    parser.add_argument(
        "--output", type=Path,
        default=Path(__file__).resolve().parent.parent / "output" / "user_settings.json",
        help="Destination file (default: output/user_settings.json beside the batch file)",
    )
    args = parser.parse_args()
    try:
        export(args)
    except (OSError, ValueError, KeyError, TypeError, RuntimeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

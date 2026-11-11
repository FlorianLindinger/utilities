"""Remove currently excluded extension settings from cached sync content.

VS Code can retain old ignored values in remote snapshots. Apply installed
extension schemas and explicit user exclusions again before sharing an export.
Core exclusions still rely on VS Code's snapshot; this is not a full registry.
"""

import json
import os
import re
import shutil
from collections.abc import Iterable
from pathlib import Path

_TOKEN = re.compile(r'\s+|//[^\r\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|[^\s{}\[\],:]+|[{}\[\],:]')


def members(text: str) -> list[tuple[str, int, int, int]]:
    """Locate root properties in JSONC without changing comments or values."""
    tokens = [match for match in _TOKEN.finditer(text)
              if not match[0].isspace() and not match[0].startswith(("//", "/*"))]
    if not tokens or tokens[0][0] != "{" or tokens[-1][0] != "}":
        raise ValueError("Settings must contain a JSONC object.")
    result = []
    index = 1
    while index < len(tokens) - 1:
        key = tokens[index]
        if not key[0].startswith('"') or tokens[index + 1][0] != ":":
            raise ValueError("Invalid JSONC settings property.")
        value_start = index + 2
        index = value_start
        stack = []
        while index < len(tokens):
            token = tokens[index][0]
            if not stack and token in (",", "}"):
                break
            if token in ("{", "["):
                stack.append(token)
            elif token in ("}", "]") and (not stack or stack.pop() != {"}": "{", "]": "["}[token]):
                raise ValueError("Unbalanced JSONC settings value.")
            index += 1
        if index == value_start or index >= len(tokens):
            raise ValueError("Missing or unterminated JSONC settings value.")
        end = tokens[index].end() if tokens[index][0] == "," else tokens[index - 1].end()
        result.append((json.loads(key[0]), key.start(), tokens[value_start].start(), end))
        if tokens[index][0] == "}":
            break
        index += 1
    return result


def exclusions(text: str) -> list[str]:
    """Read ignoredSettings, including comments and trailing commas in its array."""
    for key, _, start, end in members(text):
        if key == "settingsSync.ignoredSettings":
            # Only string tokens are values in this string-array setting.
            return [json.loads(token[0]) for token in _TOKEN.finditer(text[start:end])
                    if token[0].startswith('"')]
    return []


def settings_values(text: str) -> dict:
    """Decode JSONC values for sync comparison, ignoring comments and formatting."""
    tokens = [token[0] for token in _TOKEN.finditer(text)
              if not token[0].isspace() and not token[0].startswith(("//", "/*"))]
    # Remove trailing commas token-wise so comma/bracket text inside strings is safe.
    content = "".join(token for index, token in enumerate(tokens)
                      if token != "," or index + 1 == len(tokens) or tokens[index + 1] not in ("}", "]"))
    result = json.loads(content)
    if not isinstance(result, dict):
        raise ValueError("Settings must contain a JSONC object.")
    return result


def standalone_comments(text: str, start: int, end: int) -> list[tuple[int, int, str]]:
    """Find whole comment lines between properties, excluding inline comments."""
    result = []
    for token in _TOKEN.finditer(text, start, end):
        if not token[0].startswith(("//", "/*")):
            continue
        line_start = text.rfind("\n", 0, token.start()) + 1
        line_end = text.find("\n", token.end())
        line_end = len(text) if line_end < 0 else line_end + 1
        if not text[line_start:token.start()].strip() and not text[token.end():line_end].strip():
            result.append((line_start, line_end, text[line_start:line_end]))
    return result


def restore_section_comments(settings: str, local_settings: str) -> str:
    """Restore local headings lost by Sync without changing exported values.

    Anchor comments to the next retained setting. If excluded settings followed
    a heading locally, their heading still belongs before the next synced one.
    """
    synced_members = members(settings)
    synced_keys = {key for key, _, _, _ in synced_members}
    headings: dict[str | None, list[str]] = {}
    pending: list[str] = []
    previous_end = 0
    for key, start, _, end in members(local_settings):
        pending.extend(comment for _, _, comment in standalone_comments(local_settings, previous_end, start))
        previous_end = end
        if key in synced_keys:
            headings[key] = pending
            pending = []
    local_close = next(token.start() for token in reversed(list(_TOKEN.finditer(local_settings)))
                       if token[0] == "}")
    pending.extend(comment for _, _, comment in standalone_comments(local_settings, previous_end, local_close))
    headings[None] = pending
    synced_close = next(token.start() for token in reversed(list(_TOKEN.finditer(settings))) if token[0] == "}")
    newline = "\r\n" if "\r\n" in settings else "\n"
    edits = []
    previous_end = 0
    for key, start, _, end in [*synced_members, (None, synced_close, synced_close, synced_close)]:
        desired = headings.get(key, [])
        existing = standalone_comments(settings, previous_end, start)
        previous_end = end
        if not desired or [line.strip() for line in desired] == [line.strip() for _, _, line in existing]:
            continue
        # Change only standalone comments, retaining inline comments and whitespace.
        position = existing[0][0] if existing else settings.rfind("\n", 0, start) + 1
        if position == 0 and settings[:start].strip():
            # Compact JSONC may put the first property beside the opening brace.
            position = start
        restored = "".join(line.replace("\r\n", "\n").replace("\n", newline) for line in desired)
        if position and settings[position - 1] not in "\r\n":
            restored = newline + restored
        if existing:
            edits.append((position, existing[0][1], restored))
            edits.extend((begin, finish, "") for begin, finish, _ in existing[1:])
        else:
            edits.append((position, position, restored))
    for start, end, replacement in sorted(edits, reverse=True):
        settings = settings[:start] + replacement + settings[end:]
    return settings


def extension_manifests() -> Iterable[Path]:
    """Find user and built-in extension manifests for the local VS Code install."""
    extension_dir = Path(os.environ.get("VSCODE_EXTENSIONS", Path.home() / ".vscode" / "extensions"))
    index = extension_dir / "extensions.json"
    if index.is_file():
        # Ignore old extension-version directories left over after an update.
        for extension in json.loads(index.read_text(encoding="utf-8-sig")):
            location = extension["location"]
            if location.get("scheme") != "file":
                continue
            path = location["path"]
            if os.name == "nt" and re.match(r"^/[A-Za-z]:", path):
                path = path[1:]
            yield Path(path) / "package.json"
    else:
        yield from extension_dir.glob("*/package.json")
    cli = shutil.which("code") or shutil.which("code-insiders")
    if cli:
        yield from (Path(cli).parent.parent / "resources" / "app" / "extensions").glob("*/package.json")


def filter_settings(settings: str, manifests: Iterable[Path], local_settings: str | None = None) -> str:
    """Respect machine scopes, ignoreSync and explicit '-' sync overrides."""
    ignored = set()
    disallowed = {"settingsSync.ignoredSettings", "settingsSync.ignoredExtensions"}
    for path in manifests:
        manifest = json.loads(path.read_text(encoding="utf-8-sig"))
        configurations = manifest.get("contributes", {}).get("configuration", [])
        if isinstance(configurations, dict):
            configurations = [configurations]
        for configuration in configurations:
            for key, schema in configuration.get("properties", {}).items():
                if schema.get("ignoreSync") or schema.get("scope", configuration.get("scope")) in (
                    "machine", "machine-overridable",
                ):
                    ignored.add(key)
                if schema.get("disallowSyncIgnore"):
                    disallowed.add(key)
    overrides = exclusions(local_settings if local_settings is not None else settings)
    # VS Code removes negative entries after adding all explicit exclusions.
    ignored.update(key for key in overrides if not key.startswith("-"))
    ignored.difference_update(key[1:] for key in overrides if key.startswith("-"))
    ignored.difference_update(disallowed)
    edits = []
    for key, start, _, end in members(settings):
        if key not in ignored:
            continue
        line_start = settings.rfind("\n", 0, start) + 1
        line_end = settings.find("\n", end)
        line_end = len(settings) if line_end < 0 else line_end
        # Remove a property's inline comment with it, but keep section comments.
        tail = settings[end:line_end].strip()
        if not settings[line_start:start].strip() and (not tail or tail.startswith("//")):
            start, end = line_start, min(line_end + 1, len(settings))
        edits.append((start, end))
    for start, end in reversed(edits):
        settings = settings[:start] + settings[end:]
    return settings

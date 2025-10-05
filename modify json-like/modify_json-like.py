##########################################
# settings

# decide if to replace or only to add if undefined:
replace_existing = True
# will define/replace key: value in settings.json:
settings = {
    "python.defaultInterpreterPath": r"${env:USERPROFILE}\\Documents\\python_envs\\default_env\\Scripts\\python.exe",
    "terminal.integrated.defaultProfile.windows": "Command Prompt",
}
# will add value to key in settings.json as key: [value]:
folder_settings = {"python.venvFolders": r"Documents\\python_envs"}

##########################################
import os, re, json

appdata = os.environ["APPDATA"]
path = os.path.join(appdata, "Code", "User", "settings.json")

def read_text(p):
    if not os.path.exists(p) or os.path.getsize(p) == 0:
        return "{\n}\n"
    return open(p, "r", encoding="utf-8").read()

def write_text(p, txt):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(txt)

def set_key_value(jsonc: str, key: str, value_json: str, replace_existing: bool = True) -> str:
    """
    Replace value for "key": ... preserving indentation, trailing comma, and inline // comments.
    If key not present, insert before final '}' with a trailing comma when needed.
    """
    
    pattern = re.compile(
        rf'^(?P<indent>\s*)"{re.escape(key)}"\s*:\s*(?P<val>[^\r\n]*?)(?P<comma>\s*,?)\s*(?P<cmt>//[^\r\n]*)?$',
        re.M,
    )

    if replace_existing:
        def repl(m):
            ind = m.group("indent")
            comma = m.group("comma") or ""
            cmt = (" " + m.group("cmt")) if m.group("cmt") else ""
            return f'{ind}"{key}": {value_json}{comma}{cmt}'
        new, n = pattern.subn(repl, jsonc, count=1)
        if n:
            return new
    else:
        # skip if key already exists
        if pattern.search(jsonc):
            return jsonc

    # insertion logic unchanged...

    ins_pt = jsonc.rfind("}")
    if ins_pt == -1:
        raise RuntimeError("Invalid settings.json: missing closing brace.")
    before = jsonc[:ins_pt].rstrip()
    after = jsonc[ins_pt:]

    prop_lines = [ln for ln in jsonc.splitlines() if re.search(r'^\s*".*?"\s*:', ln)]
    base_indent = re.match(r'^(\s*)', prop_lines[-1]).group(1) if prop_lines else "  "

    prev_non_ws = re.search(r"[^\s]", before[::-1])
    need_comma = False
    if prev_non_ws:
        ch = before[::-1][prev_non_ws.start()]
        need_comma = ch not in "{,"
    if need_comma:
        before += ","

    eol = "\r\n" if "\r\n" in jsonc else "\n"
    insertion = f'{eol}{base_indent}"{key}": {value_json}{eol}'
    return before + insertion + after

def _strip_comments_safe(s: str) -> str:
    out = []
    i, n = 0, len(s)
    in_str = esc = False
    in_line = in_block = False
    while i < n:
        c = s[i]
        if in_str:
            out.append(c)
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        elif in_line:
            if c in "\r\n":
                in_line = False
                out.append(c)
        elif in_block:
            if c == "*" and i + 1 < n and s[i + 1] == "/":
                in_block = False
                i += 1
        else:
            if c == '"':
                in_str = True
                out.append(c)
            elif c == "/" and i + 1 < n:
                if s[i + 1] == "/":
                    in_line = True
                    i += 1
                elif s[i + 1] == "*":
                    in_block = True
                    i += 1
                else:
                    out.append(c)
            else:
                out.append(c)
        i += 1
    return "".join(out)

def _skip_ws_comments(s: str, i: int) -> int:
    n = len(s)
    while i < n:
        c = s[i]
        if c in " \t\r\n":
            i += 1
            continue
        if c == "/" and i + 1 < n:
            if s[i + 1] == "/":
                i += 2
                while i < n and s[i] not in "\r\n":
                    i += 1
                continue
            if s[i + 1] == "*":
                i += 2
                while i + 1 < n:
                    if s[i] == "*" and s[i + 1] == "/":
                        i += 2
                        break
                    i += 1
                continue
        break
    return i

def add_to_folder(jsonc: str, key: str, elem: str) -> str:
    # locate key:
    m = re.search(rf'"{re.escape(key)}"\s*:', jsonc)
    if not m:
        return set_key_value(jsonc, key, f'["{elem}"]')
    i = _skip_ws_comments(jsonc, m.end())
    if i >= len(jsonc) or jsonc[i] != "[":
        return set_key_value(jsonc, key, f'["{elem}"]')

    # find matching ']'
    lb = i
    i += 1
    depth = 1
    in_str = esc = False
    in_line = in_block = False
    while i < len(jsonc):
        c = jsonc[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        elif in_line:
            if c in "\r\n":
                in_line = False
        elif in_block:
            if c == "*" and i + 1 < len(jsonc) and jsonc[i + 1] == "/":
                in_block = False
                i += 1
        else:
            if c == '"':
                in_str = True
            elif c == "/" and i + 1 < len(jsonc):
                if jsonc[i + 1] == "/":
                    in_line = True
                    i += 1
                elif jsonc[i + 1] == "*":
                    in_block = True
                    i += 1
            elif c == "[":
                depth += 1
            elif c == "]":
                depth -= 1
                if depth == 0:
                    rb = i
                    break
        i += 1
    else:
        raise RuntimeError(f"Unclosed array for {key}")

    inner = jsonc[lb + 1 : rb]

    # membership: strip comments, drop trailing commas, parse
    body = _strip_comments_safe(inner)
    body = re.sub(r',\s*(?=[]}])', '', body)
    try:
        arr = json.loads("[" + body + "]")
    except json.JSONDecodeError:
        # fallback: take quoted strings only
        toks = re.findall(r'"((?:\\.|[^"\\])*)"', body)
        arr = []
        for t in toks:
            try:
                arr.append(json.loads('"' + t + '"'))
            except json.JSONDecodeError:
                arr.append(t)

    try:
        target = json.loads(f'"{elem}"')  # decode escapes
    except json.JSONDecodeError:
        target = elem

    if any(isinstance(x, str) and x == target for x in arr):
        return jsonc  # already present

    # insert preserving format
    eol = "\r\n" if "\r\n" in jsonc else "\n"

    # one-line array
    if ("\n" not in inner) and ("\r" not in inner):
        inner_no_comments = _strip_comments_safe(inner).strip()
        has_items = bool(inner_no_comments)
        has_trailing_comma = bool(re.search(r',\s*$', _strip_comments_safe(inner)))
        if has_items:
            if has_trailing_comma:
                new_inner = inner + f' "{elem}"'
            else:
                new_inner = inner.rstrip() + f', "{elem}"'
        else:
            new_inner = inner + f'"{elem}"'
        return jsonc[: lb + 1] + new_inner + jsonc[rb :]

    # multi-line array
    line_start = jsonc.rfind("\n", 0, rb) + 1
    closing_indent = re.match(r"^(\s*)", jsonc[line_start:rb]).group(1)
    elem_indent = closing_indent + "  "

    lines = inner.splitlines()

    # ensure last non-empty (post-comment) line ends with comma
    last_idx = None
    for j in range(len(lines) - 1, -1, -1):
        if _strip_comments_safe(lines[j]).strip():
            last_idx = j
            break
    if last_idx is not None:
        stripped = _strip_comments_safe(lines[last_idx]).rstrip()
        if not stripped.endswith(","):
            lines[last_idx] = lines[last_idx].rstrip() + ","

    lines.append(f'{elem_indent}"{elem}"')
    new_inner = eol.join(lines)
    return jsonc[: lb + 1] + new_inner + jsonc[rb :]

# --- execute ---

# read
txt = read_text(path)

# replace normal settings
for setting_key, value in settings.items():
    v_json = '"' + value.replace('"', '\\"') + '"'    # serialize simple strings
    txt = set_key_value(txt, setting_key, v_json,replace_existing)

# replace settings that have a list as value
for folder_key,elem in folder_settings.items():
    txt = add_to_folder(txt, folder_key, elem)
    
# write
write_text(path, txt)






"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const os = require("node:os");
const { pathToFileURL } = require("node:url");
const { buildConfig, sourcePatterns } = require("./profiles");
const { createController } = require("./extension");

function fixture() {
  const uri = (value) => ({ fsPath: value, toString: () => pathToFileURL(value).toString() });
  const first = { name: "first", uri: uri(path.join(os.tmpdir(), "workspace-a")) };
  const second = { name: "second", uri: uri(path.join(os.tmpdir(), "workspace-b")) };
  const files = new Map();
  const settings = new Map();
  const updates = [];
  const commands = [];
  const warnings = [];
  const custom = path.join(os.tmpdir(), "shared-rules.toml");
  files.set(custom, Buffer.from('preset = "default"\n'));
  const vscode = {
    Uri: { file: uri, joinPath: (parent, ...parts) => uri(path.join(parent.fsPath, ...parts)) },
    ConfigurationTarget: { WorkspaceFolder: 3 },
    workspace: {
      workspaceFolders: [first, second],
      getWorkspaceFolder: (document) => [first, second].find((folder) => document.fsPath.startsWith(folder.uri.fsPath + path.sep)),
      getConfiguration: (section, resource) => ({
        get: (key, fallback) => section === "pyreflyProfiles" ? custom : settings.get(resource.toString() + ":" + key) ?? fallback,
        update: async (key, value, target) => {
          assert.equal(target, 3);
          updates.push([resource.toString(), key, value]);
          settings.set(resource.toString() + ":" + key, value);
        },
      }),
      fs: {
        readFile: async (file) => {
          if (files.has(file.fsPath)) return files.get(file.fsPath);
          throw Object.assign(new Error("File not found"), { code: "FileNotFound" });
        },
        stat: async (file) => { if (!files.has(file.fsPath)) throw new Error("Missing custom rules"); },
        createDirectory: async () => {},
        writeFile: async (file, content) => { files.set(file.fsPath, content); },
      },
      openTextDocument: async (file) => file,
    },
    window: {
      activeTextEditor: { document: { uri: uri(path.join(first.uri.fsPath, "file.py")) } },
      showWorkspaceFolderPick: async () => second,
      showTextDocument: async () => {},
      showWarningMessage: async (message) => { warnings.push(message); },
    },
    extensions: { getExtension: () => ({ isActive: true }) },
    commands: { executeCommand: async (command) => { commands.push(command); } },
  };
  const context = { globalStorageUri: uri(path.join(os.tmpdir(), "profile-storage")) };
  return { first, second, vscode, context, files, settings, updates, commands, warnings, custom, controller: createController(vscode, context) };
}

test("Windows includes cover both drive cases and only the selected folder", () => {
  const patterns = sourcePatterns("D:\\Projects\\one");
  assert.equal(patterns.length, 8);
  assert(patterns.includes("d:/Projects/one/**/*.py"));
  assert(patterns.includes("D:/Projects/one/**/*.ipynb"));
  assert(patterns.every((pattern) => /^[dD]:\/Projects\/one\//.test(pattern)));
});

test("Custom extends shared rules while explicit presets are independent", () => {
  const custom = buildConfig("custom", "/projects/one", "/shared/rules.toml");
  assert(custom.includes('extends = "/shared/rules.toml"'));
  assert(custom.includes('import-root = "/projects/one"'));
  for (const mode of ["basic", "default", "strict"]) {
    const preset = buildConfig(mode, "/projects/one");
    assert(preset.includes(`preset = "${mode}"`));
    assert(!preset.includes("extends"));
    assert(!preset.includes("/projects/two"));
  }
});

test("Selecting every explicit mode writes scoped storage configs and updates only the active folder", async () => {
  const f = fixture();
  for (const mode of ["basic", "default", "strict", "custom"]) {
    await f.controller.apply(mode);
    assert.equal(f.controller.status().toLowerCase(), mode);
    const selected = f.settings.get(f.first.uri.toString() + ":configPath");
    assert(selected.startsWith(f.context.globalStorageUri.fsPath));
    assert(!selected.startsWith(f.first.uri.fsPath));
    const content = f.files.get(selected).toString();
    assert(content.includes("workspace-a"));
    assert(!content.includes("workspace-b"));
    assert.equal(f.settings.get(f.first.uri.toString() + ":disableTypeErrors"), false);
  }
  assert(f.updates.every(([folder]) => folder === f.first.uri.toString()));
  assert.equal(f.commands.length, 4);
});

test("Local clears the explicit config; Off additionally disables diagnostics", async () => {
  const f = fixture();
  await f.controller.apply("strict");
  f.files.set(path.join(f.first.uri.fsPath, 'pyrefly.toml'), Buffer.from(''));
  await f.controller.apply("local");
  assert.equal(f.controller.status(), "Local");
  assert.equal(f.settings.get(f.first.uri.toString() + ":configPath"), "");
  assert.equal(f.settings.get(f.first.uri.toString() + ":typeCheckingMode"), "auto");
  await f.controller.apply("off");
  assert.equal(f.controller.status(), "Off");
  assert.equal(f.settings.get(f.first.uri.toString() + ":disableTypeErrors"), true);
});

test("A multi-folder workspace without an active editor targets the chosen folder", async () => {
  const f = fixture();
  f.vscode.window.activeTextEditor = undefined;
  await f.controller.apply("default");
  assert(f.updates.every(([folder]) => folder === f.second.uri.toString()));
});

test("Missing custom rules leave existing workspace settings untouched", async () => {
  const f = fixture();
  f.files.delete(f.custom);
  await assert.rejects(f.controller.apply("custom"), /Missing custom rules/);
  assert.equal(f.updates.length, 0);
});

test("The status preserves an explicit preset across VS Code profile switches", async () => {
  const f = fixture();
  await f.controller.apply("strict");
  const otherContext = {
    globalStorageUri: f.vscode.Uri.file(path.join(os.tmpdir(), "other-user-profile", "profile-storage")),
  };
  assert.equal(createController(f.vscode, otherContext).status(), "Strict");
});

test("Missing local config warns and preserves the current profile without restarting", async () => {
  const f = fixture();
  await f.controller.apply("strict");
  const updates = f.updates.length;
  const restarts = f.commands.length;
  f.files.set(path.join(f.first.uri.fsPath, "pyproject.toml"), Buffer.from("[tool.ruff]\n"));
  await f.controller.apply("local");
  assert.equal(f.controller.status(), "Strict");
  assert.equal(f.updates.length, updates);
  assert.equal(f.commands.length, restarts);
  assert.equal(f.warnings.length, 1);
  assert.match(f.warnings[0], /Keeping the current profile/);
});

test("A local pyproject Pyrefly section allows switching", async () => {
  const f = fixture();
  f.files.set(path.join(f.first.uri.fsPath, "pyproject.toml"),
    Buffer.from("[tool.pyrefly] # project rules\npreset = \"strict\"\n"));
  assert.equal(await f.controller.apply("local"), "Local");
  assert.equal(f.warnings.length, 0);
  assert.equal(f.controller.status(), "Local");
});

test("Unreadable local configuration is reported instead of treated as missing", async () => {
  const f = fixture();
  f.vscode.workspace.fs.readFile = async () => {
    throw Object.assign(new Error("Access denied"), { code: "NoPermissions" });
  };
  await assert.rejects(f.controller.apply("local"), /Access denied/);
  assert.equal(f.updates.length, 0);
  assert.equal(f.warnings.length, 0);
});
test("Local finds a nested config governing the active source", async () => {
  const f = fixture();
  const nested = path.join(f.first.uri.fsPath, "nested");
  f.vscode.window.activeTextEditor.document.uri = f.vscode.Uri.file(path.join(nested, "src", "file.py"));
  f.files.set(path.join(nested, "pyrefly.toml"), Buffer.from(""));
  assert.equal(await f.controller.apply("local"), "Local");
  assert.equal(f.warnings.length, 0);
});

test("Local discovers parent configs outside the workspace", async () => {
  const f = fixture();
  f.files.set(path.join(f.first.uri.fsPath, "..", "pyproject.toml"),
    Buffer.from("[tool.pyrefly.errors]\nbad-return = false\n"));
  assert.equal(await f.controller.apply("local"), "Local");
});

test("A nearer project boundary prevents using an unrelated parent config", async () => {
  for (const marker of ["pyproject.toml", "setup.py", "mypy.ini", "pyrightconfig.json"]) {
    const f = fixture();
    f.files.set(path.join(f.first.uri.fsPath, marker), Buffer.from(""));
    f.files.set(path.join(f.first.uri.fsPath, "..", "pyrefly.toml"), Buffer.from(""));
    await f.controller.apply("local");
    assert.equal(f.warnings.length, 1, marker);
    assert.equal(f.updates.length, 0, marker);
  }
});

test("A config in an unrelated nested folder does not satisfy the guard", async () => {
  const f = fixture();
  f.files.set(path.join(f.first.uri.fsPath, "other", "pyrefly.toml"), Buffer.from(""));
  await f.controller.apply("local");
  assert.equal(f.warnings.length, 1);
  assert.equal(f.updates.length, 0);
});

test("Notebook discovery starts at its directory, even with a cell editor", async () => {
  const f = fixture();
  const nested = path.join(f.first.uri.fsPath, "notebooks");
  f.vscode.window.activeTextEditor.document.uri = f.vscode.Uri.file(path.join(nested, "cell"));
  f.vscode.window.activeNotebookEditor = {
    notebook: { uri: f.vscode.Uri.file(path.join(nested, "example.ipynb")) },
  };
  f.files.set(path.join(nested, "pyrefly.toml"), Buffer.from(""));
  assert.equal(await f.controller.apply("local"), "Local");
});

test("Without a Python editor, discovery starts at the selected workspace folder", async () => {
  const f = fixture();
  f.vscode.window.activeTextEditor = undefined;
  f.files.set(path.join(f.second.uri.fsPath, "pyrefly.toml"), Buffer.from(""));
  assert.equal(await f.controller.apply("local"), "Local");
  assert(f.updates.every(([folder]) => folder === f.second.uri.toString()));
});

test("pyrefly.toml takes precedence over a pyproject without Pyrefly settings", async () => {
  const f = fixture();
  f.files.set(path.join(f.first.uri.fsPath, "pyrefly.toml"), Buffer.from(""));
  f.files.set(path.join(f.first.uri.fsPath, "pyproject.toml"), Buffer.from("[tool.ruff]\n"));
  assert.equal(await f.controller.apply("local"), "Local");
});
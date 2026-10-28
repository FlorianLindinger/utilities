"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const os = require("node:os");
const { pathToFileURL } = require("node:url");
const { LABELS, buildConfig, sourcePatterns } = require("./profiles");
const { createController, registerStatusBar } = require("./extension");

function fixture() {
  const uri = (value) => ({ fsPath: value, toString: () => pathToFileURL(value).toString() });
  const first = { name: "first", uri: uri(path.join(os.tmpdir(), "workspace-a")) };
  const second = { name: "second", uri: uri(path.join(os.tmpdir(), "workspace-b")) };
  const files = new Map();
  const settings = new Map();
  const updates = [];
  const commands = [];
  const warnings = [];
  const information = [];
  const opened = [];
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
      showTextDocument: async (file) => { opened.push(file.fsPath); },
      showWarningMessage: async (message) => { warnings.push(message); },
      showInformationMessage: async (message, ...actions) => { information.push({ message, actions }); },
    },
    extensions: { getExtension: () => ({ isActive: true }) },
    commands: { executeCommand: async (command) => { commands.push(command); } },
  };
  const context = { globalStorageUri: uri(path.join(os.tmpdir(), "profile-storage")) };
  return { first, second, vscode, context, files, settings, updates, commands, warnings, information, opened, custom, controller: createController(vscode, context) };
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
  assert(custom.includes('search-path = ["/projects/one"]'));
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
    assert.equal(f.controller.status(), LABELS[mode]);
    const selected = f.settings.get(f.first.uri.toString() + ":configPath");
    assert(selected.startsWith(f.context.globalStorageUri.fsPath));
    assert(!selected.startsWith(f.first.uri.fsPath));
    const content = f.files.get(selected).toString();
    const expectedRoot = f.first.uri.fsPath.replace(/\\/g, "/");
    assert(content.includes(`search-path = [${JSON.stringify(expectedRoot)}]`));
    assert(!content.includes("import-root"));
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
  assert.equal(f.controller.status(), "Local Custom");
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
  assert.equal(await f.controller.apply("local"), "Local Custom");
  assert.equal(f.warnings.length, 0);
  assert.equal(f.controller.status(), "Local Custom");
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
  assert.equal(await f.controller.apply("local"), "Local Custom");
  assert.equal(f.warnings.length, 0);
});

test("Local discovers parent configs outside the workspace", async () => {
  const f = fixture();
  f.files.set(path.join(f.first.uri.fsPath, "..", "pyproject.toml"),
    Buffer.from("[tool.pyrefly.errors]\nbad-return = false\n"));
  assert.equal(await f.controller.apply("local"), "Local Custom");
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
  assert.equal(await f.controller.apply("local"), "Local Custom");
});

test("Without a Python editor, discovery starts at the selected workspace folder", async () => {
  const f = fixture();
  f.vscode.window.activeTextEditor = undefined;
  f.files.set(path.join(f.second.uri.fsPath, "pyrefly.toml"), Buffer.from(""));
  assert.equal(await f.controller.apply("local"), "Local Custom");
  assert(f.updates.every(([folder]) => folder === f.second.uri.toString()));
});

test("pyrefly.toml takes precedence over a pyproject without Pyrefly settings", async () => {
  const f = fixture();
  f.files.set(path.join(f.first.uri.fsPath, "pyrefly.toml"), Buffer.from(""));
  f.files.set(path.join(f.first.uri.fsPath, "pyproject.toml"), Buffer.from("[tool.ruff]\n"));
  assert.equal(await f.controller.apply("local"), "Local Custom");
});
test("Local Custom reports the exact config path and offers an edit button", async () => {
  const f = fixture();
  const config = path.join(f.first.uri.fsPath, "pyrefly.toml");
  f.files.set(config, Buffer.from(""));
  await f.controller.apply("local");
  assert.equal(f.information.length, 1);
  assert(f.information[0].message.includes(config));
  assert.deepEqual(f.information[0].actions, ["Edit Local settings"]);
  assert.equal(f.opened.length, 0);
});

test("The notification edit button opens the discovered parent pyproject", async () => {
  const f = fixture();
  const config = path.join(f.first.uri.fsPath, "..", "pyproject.toml");
  f.files.set(config, Buffer.from("[tool.pyrefly]\n"));
  f.vscode.window.showInformationMessage = async () => "Edit Local settings";
  await f.controller.apply("local");
  assert.deepEqual(f.opened, [config]);
});

test("Edit Local settings opens the nested config without changing the selected preset", async () => {
  const f = fixture();
  await f.controller.apply("strict");
  const updates = f.updates.length;
  const restarts = f.commands.length;
  const nested = path.join(f.first.uri.fsPath, "nested");
  const config = path.join(nested, "pyrefly.toml");
  f.files.set(config, Buffer.from(""));
  f.vscode.window.activeTextEditor.document.uri = f.vscode.Uri.file(path.join(nested, "file.py"));
  await f.controller.editLocal();
  assert.deepEqual(f.opened, [config]);
  assert.equal(f.controller.status(), "Strict");
  assert.equal(f.updates.length, updates);
  assert.equal(f.commands.length, restarts);
});

test("Edit Local settings warns when no config exists and creates no files", async () => {
  const f = fixture();
  const files = f.files.size;
  await f.controller.editLocal();
  assert.equal(f.warnings.length, 1);
  assert.equal(f.opened.length, 0);
  assert.equal(f.updates.length, 0);
  assert.equal(f.files.size, files);
});

test("Global Custom preserves the existing custom command and shared-file edit action", async () => {
  const f = fixture();
  assert.equal(await f.controller.apply("custom"), "Global Custom");
  assert.equal(f.controller.status(), "Global Custom");
  await f.controller.editCustom();
  assert.deepEqual(f.opened, [f.custom]);
});
function statusBarFixture(groups = []) {
  const listeners = new Map();
  const event = (name) => (callback) => {
    listeners.set(name, callback);
    return { dispose() { listeners.delete(name); } };
  };
  class TabInputText { constructor(path) { this.uri = { path }; } }
  class TabInputNotebook { constructor(path) { this.uri = { path }; } }
  const button = {
    visible: false,
    show() { this.visible = true; },
    hide() { this.visible = false; },
    dispose() { this.disposed = true; },
  };
  const tabGroups = { all: groups, onDidChangeTabs: event("tabs"), onDidChangeTabGroups: event("groups") };
  const vscode = {
    TabInputText, TabInputNotebook, StatusBarAlignment: { Right: 2 },
    window: {
      tabGroups,
      createStatusBarItem: () => button,
      onDidChangeActiveTextEditor: event("editor"),
      onDidChangeActiveNotebookEditor: event("notebook"),
    },
    workspace: {
      onDidChangeConfiguration: event("config"),
      onDidChangeWorkspaceFolders: event("folders"),
    },
  };
  const context = { subscriptions: [] };
  let mode = "Basic";
  registerStatusBar(vscode, context, { status: () => mode });
  return { vscode, tabGroups, button, context, listeners, setMode: value => { mode = value; } };
}

test("Status button follows Python tabs across groups and hides after the last closes", () => {
  const f = statusBarFixture();
  const text = name => ({ input: new f.vscode.TabInputText(name) });
  const notebook = name => ({ input: new f.vscode.TabInputNotebook(name) });
  assert.equal(f.button.visible, false);
  f.tabGroups.all = [
    { tabs: [text("/project/README.md")] },
    { tabs: [text("/project/example.py"), notebook("/project/analysis.ipynb")] },
  ];
  f.listeners.get("tabs")();
  assert.equal(f.button.visible, true);
  assert.equal(f.button.command, "pyreflyProfiles.apply");
  // Switching to another file or the terminal must not hide the button.
  f.listeners.get("editor")(undefined);
  assert.equal(f.button.visible, true);
  f.tabGroups.all[1].tabs.shift();
  f.listeners.get("tabs")();
  assert.equal(f.button.visible, true);
  f.tabGroups.all.pop();
  f.listeners.get("groups")();
  assert.equal(f.button.visible, false);
  // Other tab types and misleading extensions must not count.
  f.tabGroups.all = [{ tabs: [{ input: { uri: { path: "/not-a-text-tab.py" } } }, text("/file.py.txt")] }];
  f.listeners.get("tabs")();
  assert.equal(f.button.visible, false);
});

test("Status button handles restored tabs, label updates, and subscription disposal", () => {
  const f = statusBarFixture();
  f.tabGroups.all = [{ tabs: [{ input: new f.vscode.TabInputNotebook("/RESTORED.IPYNB") }] }];
  f.listeners.get("tabs")();
  f.setMode("Default");
  f.listeners.get("config")();
  assert.equal(f.button.text, "Pyrefly: Default $(chevron-down)");
  // A new registration discovers existing tabs without waiting for an event.
  f.context.subscriptions.forEach(item => item.dispose());
  const nextContext = { subscriptions: [] };
  registerStatusBar(f.vscode, nextContext, { status: () => "Strict" });
  assert.equal(f.button.visible, true);
  assert.equal(f.button.text, "Pyrefly: Strict $(chevron-down)");
  f.listeners.get("config")();
  assert.equal(f.button.text, "Pyrefly: Strict $(chevron-down)");
  assert.equal(f.listeners.size, 6);
  nextContext.subscriptions.forEach(item => item.dispose());
  assert.equal(f.listeners.size, 0);
  assert.equal(f.button.disposed, true);
  assert(require("./package.json").activationEvents.includes("onStartupFinished"));
});

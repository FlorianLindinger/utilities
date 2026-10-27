"use strict";

const path = require("node:path");
const os = require("node:os");
const { LABELS, EXPLICIT_MODES, folderId, buildConfig } = require("./profiles");

function createController(vscode, context) {
  function activeFolder() {
    const editor = vscode.window.activeTextEditor?.document.uri;
    const notebook = vscode.window.activeNotebookEditor?.notebook.uri;
    return (editor && vscode.workspace.getWorkspaceFolder(editor)) ||
      (notebook && vscode.workspace.getWorkspaceFolder(notebook)) ||
      (vscode.workspace.workspaceFolders?.length === 1 ? vscode.workspace.workspaceFolders[0] : undefined);
  }

  async function chooseFolder() {
    const active = activeFolder();
    if (active) return active;
    if (!vscode.workspace.workspaceFolders?.length) throw new Error("Open a workspace folder first.");
    return vscode.window.showWorkspaceFolderPick({ placeHolder: "Choose the folder whose Pyrefly mode to change" });
  }

  function customUri(folder) {
    let value = vscode.workspace.getConfiguration("pyreflyProfiles", folder?.uri).get("customConfigPath", "");
    if (!value) throw new Error("Set pyreflyProfiles.customConfigPath to your shared TOML rules.");
    if (folder) value = value.replace(/\$\{workspaceFolder\}/g, folder.uri.fsPath);
    if (value.startsWith("~/") || value.startsWith("~\\")) value = path.join(os.homedir(), value.slice(2));
    if (!path.isAbsolute(value)) {
      if (!folder) throw new Error("A relative custom rules path needs an open workspace folder.");
      value = path.resolve(folder.uri.fsPath, value);
    }
    return vscode.Uri.file(value);
  }

  function configUri(folder, mode) {
    return vscode.Uri.joinPath(context.globalStorageUri, "configs", folderId(folder.uri.toString()), `${mode}.toml`);
  }

  async function apply(mode) {
    if (!Object.hasOwn(LABELS, mode)) {
      const selection = await vscode.window.showQuickPick(
        Object.entries(LABELS).map(([value, label]) => ({ label, value })),
        { placeHolder: "Select Local discovery, an explicit preset, Custom rules, or Off" },
      );
      if (!selection) return;
      mode = selection.value;
    }
    const folder = await chooseFolder();
    if (!folder) return;
    if (mode === "local") {
      const editor = vscode.window.activeTextEditor?.document.uri;
      const notebook = vscode.window.activeNotebookEditor?.notebook.uri;
      const source = [editor, notebook].find((uri) =>
        uri && uri.scheme !== "vscode-notebook-cell" && /\.(py|pyi|ipynb)$/i.test(uri.fsPath) &&
        vscode.workspace.getWorkspaceFolder(uri)?.uri.toString() === folder.uri.toString());
      let directory = source ? vscode.Uri.joinPath(source, "..") : folder.uri;
      const start = directory.fsPath;
      async function readLocal(name) {
        try {
          const bytes = await vscode.workspace.fs.readFile(vscode.Uri.joinPath(directory, name));
          return Buffer.from(bytes).toString("utf8");
        } catch (error) {
          if (error.code === "FileNotFound") return undefined;
          throw error;
        }
      }
      let found = false;
      while (true) {
        const config = await readLocal("pyrefly.toml");
        if (config !== undefined) {
          found = true;
          break;
        }
        const project = await readLocal("pyproject.toml");
        if (project !== undefined) {
          found = /^\s*\[tool\.pyrefly(?:\s*\]|\s*\.)/m.test(project);
          break;
        }
        // These files stop Pyrefly's upward project-root search too.
        let boundary = false;
        for (const name of ["setup.py", "mypy.ini", "pyrightconfig.json"]) {
          if (await readLocal(name) !== undefined) {
            boundary = true;
            break;
          }
        }
        if (boundary) break;
        const parent = vscode.Uri.joinPath(directory, "..");
        if (parent.toString() === directory.toString()) break;
        directory = parent;
      }
      if (!found) {
        await vscode.window.showWarningMessage(
          `Pyrefly: No native local config (pyrefly.toml or [tool.pyrefly] in pyproject.toml) found searching upward from "${start}" before a project boundary or filesystem root. Keeping the current profile.`,
        );
        return;
      }
    }
    let selectedPath = "";
    if (EXPLICIT_MODES.includes(mode)) {
      let shared;
      if (mode === "custom") {
        shared = customUri(folder);
        await vscode.workspace.fs.stat(shared);
      }
      const file = configUri(folder, mode);
      await vscode.workspace.fs.createDirectory(vscode.Uri.joinPath(file, ".."));
      await vscode.workspace.fs.writeFile(file, Buffer.from(buildConfig(mode, folder.uri.fsPath, shared?.fsPath)));
      selectedPath = file.fsPath;
    }
    const settings = vscode.workspace.getConfiguration("python.pyrefly", folder.uri);
    const target = vscode.ConfigurationTarget.WorkspaceFolder;
    // Do not publish intermediate diagnostics while the three settings change.
    await settings.update("disableTypeErrors", true, target);
    await settings.update("configPath", selectedPath, target);
    await settings.update("typeCheckingMode", mode === "off" ? "off" : mode === "local" || mode === "custom" ? "auto" : mode, target);
    await settings.update("disableTypeErrors", mode === "off", target);
    const pyrefly = vscode.extensions.getExtension("meta.pyrefly");
    if (pyrefly && !pyrefly.isActive) await pyrefly.activate();
    if (pyrefly) await vscode.commands.executeCommand("pyrefly.restartClient");
    return LABELS[mode];
  }

  function status() {
    const folder = activeFolder();
    if (!folder) return "Choose folder";
    const settings = vscode.workspace.getConfiguration("python.pyrefly", folder.uri);
    if (settings.get("disableTypeErrors", false)) return "Off";
    const selected = settings.get("configPath", "");
    if (selected) {
      const normalize = (value) => process.platform === "win32" ? value.toLowerCase() : value;
      for (const mode of EXPLICIT_MODES) {
        if (normalize(selected) === normalize(configUri(folder, mode).fsPath)) return LABELS[mode];
      }
      // Workspace settings survive profile switches, including cached config paths.
      const parts = selected.replace(/\\/g, "/").split("/");
      const filename = parts.at(-1);
      if (parts.at(-2) === folderId(folder.uri.toString()) && parts.at(-3) === "configs" &&
          parts.at(-4) === path.basename(context.globalStorageUri.fsPath)) {
        const mode = filename.replace(/\.toml$/, "");
        if (EXPLICIT_MODES.includes(mode)) return LABELS[mode];
      }
      return "Custom";
    }
    const mode = settings.get("typeCheckingMode", "auto");
    return mode === "auto" ? "Local" : mode === "off" ? "Off" : `Local (${LABELS[mode] || mode} fallback)`;
  }

  async function editCustom() {
    const file = customUri(activeFolder());
    await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(file));
  }

  return { apply, status, editCustom };
}

function activate(context) {
  const vscode = require("vscode");
  const controller = createController(vscode, context);
  for (const [command, callback] of [
    ["pyreflyProfiles.apply", controller.apply],
    ["pyreflyProfiles.status", controller.status],
    ["pyreflyProfiles.editCustom", controller.editCustom],
  ]) {
    context.subscriptions.push(vscode.commands.registerCommand(command, async (...args) => {
      try {
        return await callback(...args);
      } catch (error) {
        await vscode.window.showErrorMessage(`Pyrefly profile: ${error.message}`);
      }
    }));
  }
}

module.exports = { activate, createController };

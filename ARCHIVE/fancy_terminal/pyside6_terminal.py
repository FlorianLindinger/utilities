"""
PySide6 Fancy Terminal
======================

A Qt-native terminal emulator for running Python scripts with interactive input.
This version keeps the behavior of the Tkinter terminal while using better Qt
primitives instead of Tk/Win32 workarounds.

Usage:
    python pyside6_terminal.py <script_path> [options] [-- script_args]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PySide6 import QtCore, QtGui, QtWidgets

DEFAULT_COLORS = {
    "background": QtGui.QColor("#1e1e1e"),
    "input_background": QtGui.QColor("#252526"),
    "foreground": QtGui.QColor("#d4d4d4"),
    "prompt": QtGui.QColor("#00FF00"),
    "stdin": QtGui.QColor("#ce9178"),
    "stdout": QtGui.QColor("#d4d4d4"),
    "stderr": QtGui.QColor("#f44747"),
    "system": QtGui.QColor("#569cd6"),
}


def safe_open(path: Path) -> bool:
    """Open a local path with the operating system default handler."""
    return QtGui.QDesktopServices.openUrl(QtCore.QUrl.fromLocalFile(str(path)))


class HistoryLineEdit(QtWidgets.QLineEdit):
    """QLineEdit that emits history navigation requests on Up/Down."""

    history_requested = QtCore.Signal(int)

    def keyPressEvent(self, event: QtGui.QKeyEvent) -> None:
        if event.key() == QtCore.Qt.Key_Up:
            self.history_requested.emit(-1)
            event.accept()
            return
        if event.key() == QtCore.Qt.Key_Down:
            self.history_requested.emit(1)
            event.accept()
            return
        super().keyPressEvent(event)


class TerminalWindow(QtWidgets.QMainWindow):
    """Main window for the PySide6 terminal."""

    def __init__(
        self,
        script_path: Path,
        script_args: list[str],
        title: str | None = None,
        icon_path: Path | None = None,
        start_on_top: bool = False,
    ) -> None:
        super().__init__()
        self.script_path = script_path
        self.script_args = script_args
        self.icon_path = icon_path

        self.settings = QtCore.QSettings("FancyTerminal", "PySide6Terminal")
        self.font_size = self.settings.value("font_size", 11, type=int)
        self.always_on_top = self.settings.value("always_on_top", start_on_top, type=bool)
        self.highlight_on_print = self.settings.value("highlight_on_print", False, type=bool)
        self.confirm_on_close = self.settings.value("confirm_on_close", False, type=bool)
        self.show_command_printing = self.settings.value("show_command_printing", True, type=bool)

        self.history: list[str] = []
        self.history_index = 0

        self.main_process: QtCore.QProcess | None = None
        self.shell_processes: set[QtCore.QProcess] = set()
        self.tray_icon: QtWidgets.QSystemTrayIcon | None = None
        self.search_bar: QtWidgets.QWidget | None = None
        self.output: QtWidgets.QTextEdit | None = None
        self.input_line: HistoryLineEdit | None = None

        window_title = title or script_path.name
        self.setWindowTitle(window_title)
        self.setMinimumSize(700, 420)
        self.resize(900, 600)

        self.apply_theme()
        self.apply_icon()
        self.build_ui()
        self.install_shortcuts()
        self.setup_tray()
        self.restore_window_state()
        self.set_always_on_top(self.always_on_top)
        self.start_main_process()

    # ------------------------------------------------------------------ setup
    def apply_theme(self) -> None:
        self.setStyleSheet(
            """
            QMainWindow {
                background: #1e1e1e;
            }
            QWidget {
                color: #d4d4d4;
            }
            QToolBar {
                background: #2d2d2d;
                border: none;
                spacing: 4px;
                padding: 4px;
            }
            QToolButton {
                background: transparent;
                border: 1px solid transparent;
                border-radius: 4px;
                padding: 3px 7px;
            }
            QToolButton:hover {
                background: #3e3e42;
            }
            QToolButton:checked {
                color: #00ff00;
                border-color: #00ff00;
            }
            QTextEdit {
                background: #1e1e1e;
                border: none;
                padding: 8px;
            }
            QFrame#InputRow {
                background: #252526;
                border-top: 1px solid #3e3e42;
            }
            QLineEdit {
                background: #252526;
                border: 1px solid #3e3e42;
                border-radius: 4px;
                padding: 5px 7px;
                color: #ffffff;
            }
            """
        )

    def apply_icon(self) -> None:
        icon: QtGui.QIcon | None = None
        if self.icon_path and self.icon_path.exists():
            icon = QtGui.QIcon(str(self.icon_path))
        else:
            fallback = Path(__file__).with_name("fallback_terminal_icon.ico")
            if fallback.exists():
                icon = QtGui.QIcon(str(fallback))
        if icon is not None and not icon.isNull():
            self.setWindowIcon(icon)
            app = QtWidgets.QApplication.instance()
            if app:
                app.setWindowIcon(icon)

    def build_ui(self) -> None:
        self.toolbar = QtWidgets.QToolBar("Controls", self)
        self.toolbar.setMovable(False)
        self.addToolBar(QtCore.Qt.TopToolBarArea, self.toolbar)

        self.action_open_folder = self.toolbar.addAction("Open Folder")
        self.action_open_folder.setToolTip("Open the script folder")
        self.action_open_folder.triggered.connect(self.open_script_folder)

        self.action_minimize_tray = self.toolbar.addAction("To Tray")
        self.action_minimize_tray.setToolTip("Minimize to system tray")
        self.action_minimize_tray.triggered.connect(self.minimize_to_tray)

        self.toolbar.addSeparator()

        self.action_always_on_top = self._add_toggle_action("Always On Top", self.set_always_on_top)
        self.action_highlight = self._add_toggle_action("Highlight", self.set_highlight_on_print)
        self.action_confirm = self._add_toggle_action("Confirm Close", self.set_confirm_on_close)
        self.action_echo = self._add_toggle_action("Command Echo", self.set_show_command_printing)

        self.toolbar.addSeparator()

        clear_action = self.toolbar.addAction("Clear")
        clear_action.setToolTip("Clear output")
        clear_action.triggered.connect(self.clear_output)

        zoom_out_action = self.toolbar.addAction("A-")
        zoom_out_action.setToolTip("Decrease font size")
        zoom_out_action.triggered.connect(lambda: self.adjust_font_size(-1))

        zoom_in_action = self.toolbar.addAction("A+")
        zoom_in_action.setToolTip("Increase font size")
        zoom_in_action.triggered.connect(lambda: self.adjust_font_size(1))

        search_action = self.toolbar.addAction("Search")
        search_action.setToolTip("Show search bar (Ctrl+F)")
        search_action.triggered.connect(self.toggle_search_bar)

        central = QtWidgets.QWidget(self)
        self.setCentralWidget(central)

        layout = QtWidgets.QVBoxLayout(central)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        self.output = QtWidgets.QTextEdit(self)
        self.output.setReadOnly(True)
        self.output.setUndoRedoEnabled(False)
        output_font = self.create_monospace_font(self.font_size)
        self.output.setFont(output_font)
        self.output.installEventFilter(self)
        layout.addWidget(self.output, 1)

        self.search_bar = self.create_search_bar()
        self.search_bar.setVisible(False)
        layout.addWidget(self.search_bar)

        input_row = QtWidgets.QFrame(self)
        input_row.setObjectName("InputRow")
        input_layout = QtWidgets.QHBoxLayout(input_row)
        input_layout.setContentsMargins(10, 8, 10, 8)
        input_layout.setSpacing(8)

        self.prompt_label = QtWidgets.QLabel(">>>", input_row)
        prompt_font = self.create_monospace_font(self.font_size, bold=True)
        self.prompt_label.setFont(prompt_font)
        prompt_palette = self.prompt_label.palette()
        prompt_palette.setColor(QtGui.QPalette.WindowText, DEFAULT_COLORS["prompt"])
        self.prompt_label.setPalette(prompt_palette)
        input_layout.addWidget(self.prompt_label)

        self.input_line = HistoryLineEdit(input_row)
        self.input_line.setPlaceholderText("Type a command and press Enter")
        self.input_line.setFont(output_font)
        self.input_line.returnPressed.connect(self.send_input)
        self.input_line.history_requested.connect(self.navigate_history)
        self.input_line.installEventFilter(self)
        input_layout.addWidget(self.input_line, 1)

        layout.addWidget(input_row)

        self._sync_toggle_action(self.action_always_on_top, self.always_on_top)
        self._sync_toggle_action(self.action_highlight, self.highlight_on_print)
        self._sync_toggle_action(self.action_confirm, self.confirm_on_close)
        self._sync_toggle_action(self.action_echo, self.show_command_printing)

    def create_search_bar(self) -> QtWidgets.QWidget:
        bar = QtWidgets.QFrame(self)
        bar.setStyleSheet("QFrame { background: #252526; border-top: 1px solid #3e3e42; }")
        layout = QtWidgets.QHBoxLayout(bar)
        layout.setContentsMargins(10, 6, 10, 6)
        layout.setSpacing(8)

        label = QtWidgets.QLabel("Find:", bar)
        layout.addWidget(label)

        self.search_input = QtWidgets.QLineEdit(bar)
        self.search_input.setPlaceholderText("Search output")
        layout.addWidget(self.search_input, 1)

        self.search_case = QtWidgets.QCheckBox("Case", bar)
        layout.addWidget(self.search_case)

        prev_btn = QtWidgets.QToolButton(bar)
        prev_btn.setText("Prev")
        prev_btn.clicked.connect(lambda: self.find_text(backward=True))
        layout.addWidget(prev_btn)

        next_btn = QtWidgets.QToolButton(bar)
        next_btn.setText("Next")
        next_btn.clicked.connect(lambda: self.find_text(backward=False))
        layout.addWidget(next_btn)

        close_btn = QtWidgets.QToolButton(bar)
        close_btn.setText("Close")
        close_btn.clicked.connect(self.toggle_search_bar)
        layout.addWidget(close_btn)

        self.search_input.returnPressed.connect(lambda: self.find_text(backward=False))
        return bar

    def _add_toggle_action(self, text: str, callback) -> QtGui.QAction:
        action = self.toolbar.addAction(text)
        action.setCheckable(True)
        action.toggled.connect(callback)
        return action

    def _sync_toggle_action(self, action: QtGui.QAction, value: bool) -> None:
        blocker = QtCore.QSignalBlocker(action)
        action.setChecked(value)
        del blocker

    def create_monospace_font(self, size: int, bold: bool = False) -> QtGui.QFont:
        font = QtGui.QFont("Consolas")
        font.setStyleHint(QtGui.QFont.Monospace)
        font.setFixedPitch(True)
        font.setPointSize(size)
        font.setBold(bold)
        return font

    def install_shortcuts(self) -> None:
        QtGui.QShortcut(QtGui.QKeySequence("Ctrl+F"), self, activated=self.toggle_search_bar)
        QtGui.QShortcut(QtGui.QKeySequence("Ctrl+0"), self, activated=self.reset_font_size)
        QtGui.QShortcut(QtGui.QKeySequence("Ctrl+="), self, activated=lambda: self.adjust_font_size(1))
        QtGui.QShortcut(QtGui.QKeySequence("Ctrl++"), self, activated=lambda: self.adjust_font_size(1))
        QtGui.QShortcut(QtGui.QKeySequence("Ctrl+-"), self, activated=lambda: self.adjust_font_size(-1))

    # ------------------------------------------------------------------ settings
    def restore_window_state(self) -> None:
        geometry = self.settings.value("geometry")
        if isinstance(geometry, QtCore.QByteArray):
            self.restoreGeometry(geometry)

    def save_window_state(self) -> None:
        self.settings.setValue("geometry", self.saveGeometry())
        self.settings.setValue("font_size", self.font_size)
        self.settings.setValue("always_on_top", self.always_on_top)
        self.settings.setValue("highlight_on_print", self.highlight_on_print)
        self.settings.setValue("confirm_on_close", self.confirm_on_close)
        self.settings.setValue("show_command_printing", self.show_command_printing)

    # ------------------------------------------------------------------ tray
    def setup_tray(self) -> None:
        if not QtWidgets.QSystemTrayIcon.isSystemTrayAvailable():
            self.tray_icon = None
            return

        icon = self.windowIcon()
        if icon.isNull():
            icon = self.style().standardIcon(QtWidgets.QStyle.SP_ComputerIcon)

        tray = QtWidgets.QSystemTrayIcon(icon, self)
        menu = QtWidgets.QMenu(self)
        restore_action = menu.addAction("Restore")
        restore_action.triggered.connect(self.restore_from_tray)
        hide_action = menu.addAction("Hide")
        hide_action.triggered.connect(self.hide)
        menu.addSeparator()
        quit_action = menu.addAction("Quit")
        quit_action.triggered.connect(self.close)
        tray.setContextMenu(menu)
        tray.activated.connect(self.on_tray_activated)
        tray.show()
        self.tray_icon = tray

    def minimize_to_tray(self) -> None:
        if self.tray_icon is None:
            self.showMinimized()
            return
        self.hide()
        self.tray_icon.showMessage(
            "Fancy Terminal",
            "Terminal minimized to tray.",
            QtWidgets.QSystemTrayIcon.Information,
            2000,
        )

    def restore_from_tray(self) -> None:
        self.show()
        self.raise_()
        self.activateWindow()

    def on_tray_activated(self, reason: QtWidgets.QSystemTrayIcon.ActivationReason) -> None:
        if reason in (QtWidgets.QSystemTrayIcon.Trigger, QtWidgets.QSystemTrayIcon.DoubleClick):
            self.restore_from_tray()

    # ------------------------------------------------------------------ process
    def start_main_process(self) -> None:
        if not self.script_path.exists():
            self.append_text(f"[System] Script not found: {self.script_path}\n", "stderr")
            self.input_line.setDisabled(True)
            return

        process = QtCore.QProcess(self)
        process.setProgram(sys.executable)
        process.setArguments(["-u", str(self.script_path)] + self.script_args)
        process.setWorkingDirectory(str(self.script_path.parent))
        process.setProcessChannelMode(QtCore.QProcess.SeparateChannels)
        process.readyReadStandardOutput.connect(self.read_main_stdout)
        process.readyReadStandardError.connect(self.read_main_stderr)
        process.finished.connect(self.on_main_process_finished)
        process.errorOccurred.connect(self.on_main_process_error)

        self.main_process = process
        process.start()

        shown_args = " ".join(self.script_args).strip()
        shown_cmd = f"{self.script_path} {shown_args}".strip()
        self.append_text(f"[System] Running: {shown_cmd}\n", "system")

    def read_main_stdout(self) -> None:
        if self.main_process is None:
            return
        text = bytes(self.main_process.readAllStandardOutput()).decode(errors="replace")
        self.append_text(text, "stdout")

    def read_main_stderr(self) -> None:
        if self.main_process is None:
            return
        text = bytes(self.main_process.readAllStandardError()).decode(errors="replace")
        self.append_text(text, "stderr")

    def on_main_process_finished(self, exit_code: int, _status: QtCore.QProcess.ExitStatus) -> None:
        self.append_text(f"\n[System] Process finished with code {exit_code}.\n", "system")
        self.input_line.setDisabled(True)

    def on_main_process_error(self, err: QtCore.QProcess.ProcessError) -> None:
        self.append_text(f"[System] Process error: {err}\n", "stderr")

    def start_shell_command(self, command: str) -> None:
        if not command:
            return

        process = QtCore.QProcess(self)
        process.setWorkingDirectory(str(self.script_path.parent))
        process.setProcessChannelMode(QtCore.QProcess.SeparateChannels)
        if sys.platform.startswith("win"):
            process.setProgram("cmd")
            process.setArguments(["/c", command])
        else:
            process.setProgram("/bin/sh")
            process.setArguments(["-lc", command])

        process.readyReadStandardOutput.connect(lambda p=process: self.read_shell_output(p, "stdout"))
        process.readyReadStandardError.connect(lambda p=process: self.read_shell_output(p, "stderr"))
        process.finished.connect(lambda code, _status, p=process: self.on_shell_finished(p, code))
        process.errorOccurred.connect(lambda err, p=process: self.on_shell_error(p, err))

        self.shell_processes.add(process)
        self.append_text(f"[System] Running shell command: {command}\n", "system")
        process.start()

    def read_shell_output(self, process: QtCore.QProcess, stream: str) -> None:
        if stream == "stdout":
            text = bytes(process.readAllStandardOutput()).decode(errors="replace")
        else:
            text = bytes(process.readAllStandardError()).decode(errors="replace")
        self.append_text(text, stream)

    def on_shell_finished(self, process: QtCore.QProcess, code: int) -> None:
        self.append_text(f"[System] Shell command finished with code {code}.\n", "system")
        self.shell_processes.discard(process)
        process.deleteLater()

    def on_shell_error(self, process: QtCore.QProcess, err: QtCore.QProcess.ProcessError) -> None:
        self.append_text(f"[System] Shell command error: {err}\n", "stderr")
        self.shell_processes.discard(process)
        process.deleteLater()

    # ------------------------------------------------------------------ output
    def append_text(self, text: str, stream: str) -> None:
        if not text:
            return

        cursor = self.output.textCursor()
        cursor.movePosition(QtGui.QTextCursor.End)

        fmt = QtGui.QTextCharFormat()
        fmt.setForeground(DEFAULT_COLORS.get(stream, DEFAULT_COLORS["foreground"]))
        cursor.insertText(text, fmt)

        self.output.setTextCursor(cursor)
        self.output.ensureCursorVisible()

        if stream in {"stdout", "stderr"} and self.highlight_on_print and not self.isActiveWindow():
            QtWidgets.QApplication.alert(self, 1200)

    def clear_output(self) -> None:
        self.output.clear()

    # ------------------------------------------------------------------ input
    def send_input(self) -> None:
        text = self.input_line.text()
        self.input_line.clear()
        stripped = text.strip()

        if stripped:
            self.history.append(text)
            self.history_index = len(self.history)
        else:
            return

        lower = stripped.lower()
        if lower in {"cls", "clear"}:
            self.clear_output()
            return

        if lower == "exit":
            self.close()
            return

        if text.startswith("!"):
            command = text[1:].strip()
            if self.show_command_printing:
                self.append_text(text + "\n", "stdin")
            self.start_shell_command(command)
            return

        if self.show_command_printing:
            self.append_text(text + "\n", "stdin")

        if self.main_process and self.main_process.state() == QtCore.QProcess.Running:
            self.main_process.write((text + "\n").encode())
            return

        self.append_text("[System] Process is not running.\n", "system")

    def navigate_history(self, direction: int) -> None:
        if not self.history:
            return

        self.history_index += direction
        if self.history_index < 0:
            self.history_index = 0
        elif self.history_index > len(self.history):
            self.history_index = len(self.history)

        if self.history_index == len(self.history):
            self.input_line.clear()
            return

        entry = self.history[self.history_index]
        self.input_line.setText(entry)
        self.input_line.setCursorPosition(len(entry))

    # ------------------------------------------------------------------ search
    def toggle_search_bar(self) -> None:
        if self.search_bar is None:
            return
        visible = not self.search_bar.isVisible()
        self.search_bar.setVisible(visible)
        if visible:
            self.search_input.setFocus()
            self.search_input.selectAll()

    def find_text(self, backward: bool = False) -> None:
        query = self.search_input.text()
        if not query:
            return

        flags = QtGui.QTextDocument.FindFlags()
        if backward:
            flags |= QtGui.QTextDocument.FindBackward
        if self.search_case.isChecked():
            flags |= QtGui.QTextDocument.FindCaseSensitively

        if self.output.find(query, flags):
            return

        cursor = self.output.textCursor()
        if backward:
            cursor.movePosition(QtGui.QTextCursor.End)
        else:
            cursor.movePosition(QtGui.QTextCursor.Start)
        self.output.setTextCursor(cursor)
        self.output.find(query, flags)

    # ------------------------------------------------------------------ feature toggles
    def set_always_on_top(self, enabled: bool) -> None:
        self.always_on_top = enabled
        self._sync_toggle_action(self.action_always_on_top, enabled)
        self.setWindowFlag(QtCore.Qt.WindowStaysOnTopHint, enabled)
        self.show()

    def set_highlight_on_print(self, enabled: bool) -> None:
        self.highlight_on_print = enabled
        self._sync_toggle_action(self.action_highlight, enabled)

    def set_confirm_on_close(self, enabled: bool) -> None:
        self.confirm_on_close = enabled
        self._sync_toggle_action(self.action_confirm, enabled)

    def set_show_command_printing(self, enabled: bool) -> None:
        self.show_command_printing = enabled
        self._sync_toggle_action(self.action_echo, enabled)

    def adjust_font_size(self, delta: int) -> None:
        new_size = max(6, min(40, self.font_size + delta))
        if new_size == self.font_size:
            return

        self.font_size = new_size
        font = self.create_monospace_font(self.font_size)
        self.output.setFont(font)
        self.input_line.setFont(font)
        self.prompt_label.setFont(self.create_monospace_font(self.font_size, bold=True))

    def reset_font_size(self) -> None:
        self.adjust_font_size(11 - self.font_size)

    def open_script_folder(self) -> None:
        if not safe_open(self.script_path.parent):
            self.append_text("[System] Could not open script folder.\n", "stderr")

    # ------------------------------------------------------------------ events
    def eventFilter(self, watched: QtCore.QObject, event: QtCore.QEvent) -> bool:
        output_widget = self.output
        input_widget = self.input_line
        if (
            output_widget is not None
            and input_widget is not None
            and watched in {output_widget, input_widget}
            and event.type() == QtCore.QEvent.Wheel
            and QtWidgets.QApplication.keyboardModifiers() & QtCore.Qt.ControlModifier
        ):
            wheel_event = event
            if isinstance(wheel_event, QtGui.QWheelEvent):
                delta = 1 if wheel_event.angleDelta().y() > 0 else -1
                self.adjust_font_size(delta)
                return True
        return super().eventFilter(watched, event)

    def closeEvent(self, event: QtGui.QCloseEvent) -> None:
        if self.confirm_on_close:
            answer = QtWidgets.QMessageBox.question(
                self,
                "Confirm Close",
                "Do you want to quit?",
                QtWidgets.QMessageBox.Yes | QtWidgets.QMessageBox.No,
                QtWidgets.QMessageBox.No,
            )
            if answer != QtWidgets.QMessageBox.Yes:
                event.ignore()
                return

        self.save_window_state()

        if self.main_process and self.main_process.state() != QtCore.QProcess.NotRunning:
            self.main_process.terminate()
            self.main_process.waitForFinished(1200)
            if self.main_process.state() != QtCore.QProcess.NotRunning:
                self.main_process.kill()

        for process in list(self.shell_processes):
            if process.state() != QtCore.QProcess.NotRunning:
                process.kill()
            process.deleteLater()
        self.shell_processes.clear()

        if self.tray_icon:
            self.tray_icon.hide()
            self.tray_icon.deleteLater()
            self.tray_icon = None

        event.accept()


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="PySide6 Fancy Terminal")
    parser.add_argument("script", help="Path to the Python script to run")
    parser.add_argument("--title", help="Window title (default: script filename)", default=None)
    parser.add_argument("--icon", help="Path to icon file (.ico/.png)", default=None)
    parser.add_argument("--on-top", action="store_true", help="Start with always-on-top enabled")
    parser.add_argument("args", nargs=argparse.REMAINDER, help="Arguments for target script")
    return parser


def create_application() -> QtWidgets.QApplication:
    QtCore.QCoreApplication.setOrganizationName("FancyTerminal")
    QtCore.QCoreApplication.setApplicationName("PySide6Terminal")
    app = QtWidgets.QApplication(sys.argv)
    app.setStyle("Fusion")
    return app


def main() -> int:
    args = build_arg_parser().parse_args()
    script_path = Path(args.script).expanduser().resolve()

    icon_path = None
    if args.icon:
        icon_path = Path(args.icon).expanduser().resolve()

    script_args = list(args.args)
    if script_args and script_args[0] == "--":
        script_args = script_args[1:]

    app = create_application()
    window = TerminalWindow(
        script_path=script_path,
        script_args=script_args,
        title=args.title,
        icon_path=icon_path,
        start_on_top=args.on_top,
    )
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())

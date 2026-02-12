"""
PySide6 Terminal Emulator
=========================

A modern, feature-rich terminal emulator built with PySide6.
Designed to run Python scripts with a sleek, customizable UI.

Usage:
    python pyside6_terminal.py <script_path> [options] [-- script_args]

Arguments:
    script_path       Path to the Python script to execute.
    script_args       Arguments to pass to the target script.

Options:
    --title TITLE     Set the window title (default: script filename).
    --icon ICON_PATH  Set the window/tray icon (default: internal icon).
    --on-top          Keep window always on top.

Example:
    python pyside6_terminal.py my_script.py --title "My App" --on-top -- --verbose
"""

import argparse
import json
import os
import queue
import subprocess
import sys
import threading
from pathlib import Path
from typing import Optional

from PySide6.QtCore import (
    QPoint,
    QRect,
    QSettings,
    QSize,
    Qt,
    QTimer,
    Signal,
    Slot,
)
from PySide6.QtGui import (
    QAction,
    QColor,
    QFont,
    QIcon,
    QKeySequence,
    QPalette,
    QSyntaxHighlighter,
    QTextCharFormat,
    QTextCursor,
    QTextDocument,
)
from PySide6.QtWidgets import (
    QApplication,
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMenu,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QSizeGrip,
    QSystemTrayIcon,
    QVBoxLayout,
    QWidget,
)

# ==============================================================================
# Syntax Highlighter for Terminal Output
# ==============================================================================


class TerminalHighlighter(QSyntaxHighlighter):
    """Syntax highlighter for different output types"""

    def __init__(self, parent: QTextDocument, color_scheme: dict):
        super().__init__(parent)
        self.color_scheme = color_scheme
        self.formats = {}
        self.update_formats()

    def update_formats(self):
        """Update text formats based on color scheme"""
        self.formats = {
            "stderr": self._create_format(self.color_scheme["stderr"]),
            "system": self._create_format(self.color_scheme["system"]),
            "stdin": self._create_format(self.color_scheme["stdin"]),
            "stdout": self._create_format(self.color_scheme["stdout"]),
        }

    def _create_format(self, color: str) -> QTextCharFormat:
        """Create a text format with the given color"""
        fmt = QTextCharFormat()
        fmt.setForeground(QColor(color))
        return fmt

    def highlightBlock(self, text: str):
        """Apply highlighting to a block of text"""
        # This is called automatically by Qt
        # We'll handle formatting through direct text insertion instead
        pass


# ==============================================================================
# Custom Title Bar
# ==============================================================================


class CustomTitleBar(QWidget):
    """Custom title bar with window controls"""

    minimize_clicked = Signal()
    maximize_clicked = Signal()
    close_clicked = Signal()
    tray_clicked = Signal()

    def __init__(self, parent: QWidget, title: str, script_path: Optional[str] = None):
        super().__init__(parent)
        self.parent_window = parent
        self.script_path = script_path
        self.drag_position = QPoint()
        self.is_maximized = False

        self.setFixedHeight(35)
        self.setStyleSheet("""
            CustomTitleBar {
                background-color: #2d2d2d;
            }
        """)

        # Main layout
        layout = QHBoxLayout(self)
        layout.setContentsMargins(10, 0, 0, 0)
        layout.setSpacing(5)

        # Title label
        self.title_label = QLabel(title)
        self.title_label.setStyleSheet("""
            QLabel {
                color: #d4d4d4;
                font-size: 10pt;
                font-family: 'Segoe UI';
            }
            QLabel:hover {
                background-color: #0078d4;
            }
        """)
        if script_path:
            self.title_label.setCursor(Qt.PointingHandCursor)
            self.title_label.mousePressEvent = self.open_script_folder
        layout.addWidget(self.title_label)

        layout.addStretch()

        # Settings buttons
        self.settings_frame = QWidget()
        settings_layout = QHBoxLayout(self.settings_frame)
        settings_layout.setContentsMargins(0, 0, 0, 0)
        settings_layout.setSpacing(2)

        # Toggle buttons
        self.top_btn = self._create_toggle_button("📌", "Toggle Always on Top")
        self.highlight_btn = self._create_toggle_button("🔔", "Toggle Highlight on Print")
        self.confirm_btn = self._create_toggle_button("🔒", "Toggle Confirm on Close")
        self.print_btn = self._create_toggle_button("💬", "Toggle Command Printing")
        self.print_btn.setProperty("active", True)  # Default on

        # Zoom buttons
        self.zoom_out_btn = self._create_button("-", "Decrease Font Size", width=30)
        self.zoom_in_btn = self._create_button("+", "Increase Font Size", width=30)

        # Clear button
        self.clear_btn = self._create_button("🗑", "Clear Output")

        # Search button
        self.search_btn = self._create_button("🔍", "Search Output (Ctrl+F)")

        for btn in [
            self.top_btn,
            self.highlight_btn,
            self.confirm_btn,
            self.print_btn,
            self.zoom_out_btn,
            self.zoom_in_btn,
            self.clear_btn,
            self.search_btn,
        ]:
            settings_layout.addWidget(btn)

        layout.addWidget(self.settings_frame)

        # Window control buttons
        self.tray_btn = self._create_button("▼", "Minimize to System Tray", hover_color="#0078d4")
        self.min_btn = self._create_button("―", "Minimize", hover_color="#3e3e42")
        self.max_btn = self._create_button("□", "Maximize", hover_color="#3e3e42", font_size=12)
        self.close_btn = self._create_button("✕", "Close", hover_color="#e81123", width=50)

        layout.addWidget(self.tray_btn)
        layout.addWidget(self.min_btn)
        layout.addWidget(self.max_btn)
        layout.addWidget(self.close_btn)

        # Connect signals
        self.tray_btn.clicked.connect(self.tray_clicked.emit)
        self.min_btn.clicked.connect(self.minimize_clicked.emit)
        self.max_btn.clicked.connect(self.maximize_clicked.emit)
        self.close_btn.clicked.connect(self.close_clicked.emit)

    def _create_button(
        self, text: str, tooltip: str, hover_color: str = "#0078d4", width: int = 40, font_size: int = 10
    ) -> QPushButton:
        """Create a styled button"""
        btn = QPushButton(text)
        btn.setFixedSize(width, 30)
        btn.setToolTip(tooltip)
        btn.setStyleSheet(f"""
            QPushButton {{
                background-color: #2d2d2d;
                color: #d4d4d4;
                border: none;
                font-size: {font_size}pt;
                font-family: 'Segoe UI';
            }}
            QPushButton:hover {{
                background-color: {hover_color};
            }}
        """)
        return btn

    def _create_toggle_button(self, text: str, tooltip: str) -> QPushButton:
        """Create a toggle button"""
        btn = self._create_button(text, tooltip)
        btn.setCheckable(True)
        btn.setProperty("active", False)
        btn.toggled.connect(lambda checked: self._update_toggle_style(btn, checked))
        return btn

    def _update_toggle_style(self, button: QPushButton, active: bool):
        """Update toggle button style"""
        button.setProperty("active", active)
        color = "#00FF00" if active else "#d4d4d4"
        button.setStyleSheet(
            button.styleSheet()
            .replace("color: #d4d4d4;", f"color: {color};")
            .replace("color: #00FF00;", f"color: {color};")
        )

    def open_script_folder(self, event):
        """Open the folder containing the script"""
        if self.script_path:
            folder_path = os.path.dirname(os.path.abspath(self.script_path))
            if sys.platform.startswith("win"):
                os.startfile(folder_path)
            elif sys.platform == "darwin":
                subprocess.run(["open", folder_path], check=False)
            else:
                subprocess.run(["xdg-open", folder_path], check=False)

    def mousePressEvent(self, event):
        """Handle mouse press for dragging"""
        if event.button() == Qt.LeftButton:
            self.drag_position = event.globalPosition().toPoint() - self.parent_window.frameGeometry().topLeft()
            event.accept()

    def mouseMoveEvent(self, event):
        """Handle mouse move for dragging"""
        if event.buttons() == Qt.LeftButton:
            # If maximized, restore before dragging
            if self.parent_window.isMaximized():
                self.parent_window.showNormal()
                # Adjust drag position for restored window
                self.drag_position = QPoint(self.parent_window.width() // 2, 10)

            self.parent_window.move(event.globalPosition().toPoint() - self.drag_position)
            event.accept()

    def mouseDoubleClickEvent(self, event):
        """Handle double-click to maximize/restore"""
        if event.button() == Qt.LeftButton:
            self.maximize_clicked.emit()
            event.accept()


# ==============================================================================
# Main Terminal Widget
# ==============================================================================


class PySide6Terminal(QMainWindow):
    """Main terminal emulator window"""

    output_ready = Signal(str, str)  # text, tag

    def __init__(
        self,
        target_script: str,
        terminal_name: Optional[str] = None,
        icon_path: Optional[str] = None,
        on_top: bool = False,
        script_args: tuple = (),
    ):
        super().__init__()

        self.target_script = target_script
        self.script_args = script_args
        self.process: Optional[subprocess.Popen] = None
        self.output_queue = queue.Queue()
        self.history = []
        self.history_index = 0

        # Settings
        self.settings = QSettings("FancyTerminal", "PySide6Terminal")
        self.always_on_top = on_top
        self.highlight_on_print = False
        self.confirm_on_close = False
        self.show_command_printing = True
        self.auto_scroll = True

        # Color scheme
        self.color_scheme = {
            "bg": "#1e1e1e",
            "fg": "#d4d4d4",
            "cursor": "#ffffff",
            "select_bg": "#264f78",
            "prompt": "#00ff00",
            "stdin": "#ce9178",
            "stdout": "#d4d4d4",
            "stderr": "#f44747",
            "system": "#569cd6",
            "input_bg": "#2d2d2d",
        }

        # Window setup
        if terminal_name is None:
            terminal_name = os.path.basename(target_script)
        self.setWindowTitle(terminal_name)
        self.resize(900, 600)

        # Remove default title bar
        self.setWindowFlags(Qt.FramelessWindowHint | Qt.WindowSystemMenuHint)

        # Icon
        self.icon_path = icon_path
        if icon_path and os.path.exists(icon_path):
            self.setWindowIcon(QIcon(icon_path))

        # Always on top
        if on_top:
            self.setWindowFlag(Qt.WindowStaysOnTopHint, True)

        # Central widget
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)

        # Custom title bar
        self.title_bar = CustomTitleBar(self, terminal_name, target_script)
        self.title_bar.minimize_clicked.connect(self.showMinimized)
        self.title_bar.maximize_clicked.connect(self.toggle_maximize)
        self.title_bar.close_clicked.connect(self.close)
        self.title_bar.tray_clicked.connect(self.minimize_to_tray)
        self.title_bar.top_btn.toggled.connect(self.set_always_on_top)
        self.title_bar.highlight_btn.toggled.connect(self.set_highlight_on_print)
        self.title_bar.confirm_btn.toggled.connect(self.set_confirm_on_close)
        self.title_bar.print_btn.toggled.connect(self.set_show_command_printing)
        self.title_bar.zoom_in_btn.clicked.connect(self.zoom_in)
        self.title_bar.zoom_out_btn.clicked.connect(self.zoom_out)
        self.title_bar.clear_btn.clicked.connect(self.clear_output)
        self.title_bar.search_btn.clicked.connect(self.show_search_dialog)
        main_layout.addWidget(self.title_bar)

        # Output area
        self.output_text = QPlainTextEdit()
        self.output_text.setReadOnly(True)
        self.output_text.setStyleSheet(f"""
            QPlainTextEdit {{
                background-color: {self.color_scheme["bg"]};
                color: {self.color_scheme["fg"]};
                border: none;
                font-family: 'Consolas', 'Courier New', monospace;
                font-size: 11pt;
            }}
        """)
        self.output_text.setWordWrapMode(QTextCursor.WordWrap)
        main_layout.addWidget(self.output_text)

        # Input area
        input_frame = QFrame()
        input_frame.setStyleSheet(f"""
            QFrame {{
                background-color: {self.color_scheme["input_bg"]};
                border-top: 1px solid #3e3e42;
            }}
        """)
        input_layout = QHBoxLayout(input_frame)
        input_layout.setContentsMargins(10, 5, 10, 5)

        # Prompt label
        self.prompt_label = QLabel(">>> ")
        self.prompt_label.setStyleSheet(f"""
            QLabel {{
                color: {self.color_scheme["prompt"]};
                font-family: 'Consolas', 'Courier New', monospace;
                font-size: 11pt;
                font-weight: bold;
            }}
        """)
        input_layout.addWidget(self.prompt_label)

        # Input field
        self.input_entry = QLineEdit()
        self.input_entry.setStyleSheet(f"""
            QLineEdit {{
                background-color: {self.color_scheme["input_bg"]};
                color: #ffffff;
                border: none;
                font-family: 'Consolas', 'Courier New', monospace;
                font-size: 11pt;
            }}
        """)
        self.input_entry.returnPressed.connect(self.send_input)
        input_layout.addWidget(self.input_entry)

        main_layout.addWidget(input_frame)

        # Size grip for resizing
        self.size_grip = QSizeGrip(self)
        self.size_grip.setStyleSheet("QSizeGrip { background-color: transparent; }")

        # System tray
        self.tray_icon = None
        if QSystemTrayIcon.isSystemTrayAvailable():
            self.setup_tray_icon()

        # Connect output signal
        self.output_ready.connect(self.write_to_output)

        # Start subprocess
        self.start_subprocess()

        # Queue checker timer
        self.queue_timer = QTimer()
        self.queue_timer.timeout.connect(self.check_queue)
        self.queue_timer.start(10)

        # Load settings
        self.load_settings()

        # Install event filter for key shortcuts
        self.installEventFilter(self)

    def eventFilter(self, obj, event):
        """Handle global key events"""
        if event.type() == event.Type.KeyPress:
            # Ctrl+F for search
            if event.modifiers() == Qt.ControlModifier and event.key() == Qt.Key_F:
                self.show_search_dialog()
                return True
            # Ctrl+Scroll for zoom (handled in wheelEvent)
        return super().eventFilter(obj, event)

    def wheelEvent(self, event):
        """Handle mouse wheel for zooming"""
        if event.modifiers() == Qt.ControlModifier:
            if event.angleDelta().y() > 0:
                self.zoom_in()
            else:
                self.zoom_out()
            event.accept()
        else:
            super().wheelEvent(event)

    def setup_tray_icon(self):
        """Setup system tray icon"""
        self.tray_icon = QSystemTrayIcon(self)
        if self.icon_path and os.path.exists(self.icon_path):
            self.tray_icon.setIcon(QIcon(self.icon_path))
        else:
            self.tray_icon.setIcon(self.style().standardIcon(self.style().StandardPixmap.SP_ComputerIcon))

        # Tray menu
        tray_menu = QMenu()
        restore_action = QAction("Restore", self)
        restore_action.triggered.connect(self.restore_from_tray)
        quit_action = QAction("Quit", self)
        quit_action.triggered.connect(self.close)

        tray_menu.addAction(restore_action)
        tray_menu.addSeparator()
        tray_menu.addAction(quit_action)

        self.tray_icon.setContextMenu(tray_menu)
        self.tray_icon.activated.connect(self.tray_icon_activated)

    def tray_icon_activated(self, reason):
        """Handle tray icon activation"""
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            self.restore_from_tray()

    def minimize_to_tray(self):
        """Minimize window to system tray"""
        if self.tray_icon:
            self.hide()
            self.tray_icon.show()
            self.tray_icon.showMessage(
                "Minimized to Tray",
                f"{self.windowTitle()} is still running",
                QSystemTrayIcon.MessageIcon.Information,
                2000,
            )

    def restore_from_tray(self):
        """Restore window from system tray"""
        self.show()
        self.activateWindow()
        if self.tray_icon:
            self.tray_icon.hide()

    def toggle_maximize(self):
        """Toggle between maximized and normal state"""
        if self.isMaximized():
            self.showNormal()
        else:
            self.showMaximized()

    def start_subprocess(self):
        """Start the target script as a subprocess"""
        try:
            cmd = [sys.executable, "-u", self.target_script] + list(self.script_args)
            self.process = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=0,
                cwd=os.path.dirname(os.path.abspath(self.target_script)),
            )

            # Start reader threads
            threading.Thread(target=self.read_stream, args=(self.process.stdout, "stdout"), daemon=True).start()
            threading.Thread(target=self.read_stream, args=(self.process.stderr, "stderr"), daemon=True).start()

        except Exception as e:
            self.output_queue.put((f"[System] Error starting process: {e}\n", "system"))

    def read_stream(self, stream, stream_type: str):
        """Read from a stream and put data into queue"""
        try:
            while True:
                char = stream.read(1)
                if not char:
                    break
                self.output_queue.put((char, stream_type))
        except Exception:
            pass
        finally:
            if self.process and self.process.poll() is not None:
                self.output_queue.put(("[System] Process finished.\n", "system"))

    def check_queue(self):
        """Check queue for new output"""
        while not self.output_queue.empty():
            try:
                content, tag = self.output_queue.get_nowait()
                self.output_ready.emit(content, tag)
            except queue.Empty:
                break

        # Disable input if process is dead
        if self.process and self.process.poll() is not None:
            self.input_entry.setEnabled(False)

    @Slot(str, str)
    def write_to_output(self, text: str, tag: str):
        """Write text to output with color coding"""
        cursor = self.output_text.textCursor()
        cursor.movePosition(QTextCursor.End)

        # Set color based on tag
        color = self.color_scheme.get(tag, self.color_scheme["stdout"])
        char_format = QTextCharFormat()
        char_format.setForeground(QColor(color))

        cursor.setCharFormat(char_format)
        cursor.insertText(text)

        # Auto-scroll
        if self.auto_scroll:
            self.output_text.setTextCursor(cursor)
            self.output_text.ensureCursorVisible()

        # Highlight on print
        if self.highlight_on_print and not self.isActiveWindow():
            QApplication.alert(self)

    def send_input(self):
        """Send input to subprocess"""
        text = self.input_entry.text()
        self.input_entry.clear()

        # Add to history
        if text.strip():
            self.history.append(text)
            self.history_index = len(self.history)

        # Handle special commands
        if text.strip().lower() in ["cls", "clear"]:
            self.clear_output()
            return

        if text.strip().lower() == "exit":
            self.close()
            return

        # Handle system commands (prefixed with !)
        if text.startswith("!"):
            cmd = text[1:].strip()
            if self.show_command_printing:
                self.write_to_output(f"{text}\n", "stdin")
            self.write_to_output(f"[System] Running: {cmd}\n", "system")

            try:
                result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
                if result.stdout:
                    self.write_to_output(result.stdout, "stdout")
                if result.stderr:
                    self.write_to_output(result.stderr, "stderr")
            except Exception as e:
                self.write_to_output(f"[System] Error running command: {e}\n", "system")
            return

        # Send to subprocess
        if self.process and self.process.poll() is None:
            if self.show_command_printing:
                self.write_to_output(text + "\n", "stdin")

            try:
                self.process.stdin.write(text + "\n")
                self.process.stdin.flush()
            except Exception as e:
                self.write_to_output(f"\n[System] Error sending input: {e}\n", "system")
        else:
            if self.show_command_printing:
                self.write_to_output(f"{text}\n", "stdin")
            self.write_to_output("\n[System] Process is not running.\n", "system")

    def keyPressEvent(self, event):
        """Handle key press events"""
        # History navigation
        if self.input_entry.hasFocus():
            if event.key() == Qt.Key_Up:
                self.navigate_history(-1)
                return
            elif event.key() == Qt.Key_Down:
                self.navigate_history(1)
                return

        super().keyPressEvent(event)

    def navigate_history(self, direction: int):
        """Navigate command history"""
        if not self.history:
            return

        self.history_index += direction
        self.history_index = max(0, min(self.history_index, len(self.history)))

        if self.history_index < len(self.history):
            self.input_entry.setText(self.history[self.history_index])
        else:
            self.input_entry.clear()

    def clear_output(self):
        """Clear the output area"""
        self.output_text.clear()

    def zoom_in(self):
        """Increase font size"""
        font = self.output_text.font()
        size = font.pointSize()
        if size < 40:
            font.setPointSize(size + 1)
            self.output_text.setFont(font)
            self.input_entry.setFont(font)
            self.prompt_label.setFont(font)

    def zoom_out(self):
        """Decrease font size"""
        font = self.output_text.font()
        size = font.pointSize()
        if size > 6:
            font.setPointSize(size - 1)
            self.output_text.setFont(font)
            self.input_entry.setFont(font)
            self.prompt_label.setFont(font)

    def show_search_dialog(self):
        """Show search dialog"""
        text, ok = QInputDialog.getText(self, "Search", "Find:")
        if ok and text:
            self.search_text(text)

    def search_text(self, text: str):
        """Search for text in output"""
        cursor = self.output_text.textCursor()
        cursor.movePosition(QTextCursor.Start)
        self.output_text.setTextCursor(cursor)

        # Find and highlight
        found = self.output_text.find(text)
        if not found:
            QMessageBox.information(self, "Search", f"'{text}' not found")

    def set_always_on_top(self, enabled: bool):
        """Set always on top"""
        self.always_on_top = enabled
        self.setWindowFlag(Qt.WindowStaysOnTopHint, enabled)
        self.show()

    def set_highlight_on_print(self, enabled: bool):
        """Set highlight on print"""
        self.highlight_on_print = enabled

    def set_confirm_on_close(self, enabled: bool):
        """Set confirm on close"""
        self.confirm_on_close = enabled

    def set_show_command_printing(self, enabled: bool):
        """Set show command printing"""
        self.show_command_printing = enabled

    def save_settings(self):
        """Save window settings"""
        self.settings.setValue("geometry", self.saveGeometry())
        self.settings.setValue("windowState", self.saveState())
        self.settings.setValue("fontSize", self.output_text.font().pointSize())
        self.settings.setValue("alwaysOnTop", self.always_on_top)
        self.settings.setValue("highlightOnPrint", self.highlight_on_print)
        self.settings.setValue("confirmOnClose", self.confirm_on_close)
        self.settings.setValue("showCommandPrinting", self.show_command_printing)

    def load_settings(self):
        """Load window settings"""
        geometry = self.settings.value("geometry")
        if geometry:
            self.restoreGeometry(geometry)

        state = self.settings.value("windowState")
        if state:
            self.restoreState(state)

        font_size = self.settings.value("fontSize", 11, type=int)
        font = self.output_text.font()
        font.setPointSize(font_size)
        self.output_text.setFont(font)
        self.input_entry.setFont(font)
        self.prompt_label.setFont(font)

        # Restore toggle states
        self.always_on_top = self.settings.value("alwaysOnTop", False, type=bool)
        self.title_bar.top_btn.setChecked(self.always_on_top)

        self.highlight_on_print = self.settings.value("highlightOnPrint", False, type=bool)
        self.title_bar.highlight_btn.setChecked(self.highlight_on_print)

        self.confirm_on_close = self.settings.value("confirmOnClose", False, type=bool)
        self.title_bar.confirm_btn.setChecked(self.confirm_on_close)

        self.show_command_printing = self.settings.value("showCommandPrinting", True, type=bool)
        self.title_bar.print_btn.setChecked(self.show_command_printing)

    def closeEvent(self, event):
        """Handle window close event"""
        if self.confirm_on_close:
            reply = QMessageBox.question(
                self, "Confirm Close", "Do you want to quit?", QMessageBox.Yes | QMessageBox.No, QMessageBox.No
            )
            if reply == QMessageBox.No:
                event.ignore()
                return

        # Save settings
        self.save_settings()

        # Terminate process
        if self.process and self.process.poll() is None:
            self.process.terminate()
            self.process.wait(timeout=2)

        # Hide tray icon
        if self.tray_icon:
            self.tray_icon.hide()

        event.accept()

    def resizeEvent(self, event):
        """Handle resize event"""
        super().resizeEvent(event)
        # Position size grip in bottom-right corner
        self.size_grip.move(self.width() - self.size_grip.width(), self.height() - self.size_grip.height())


# ==============================================================================
# Main Entry Point
# ==============================================================================


def main():
    """Main entry point"""
    try:
        parser = argparse.ArgumentParser(description="PySide6 Terminal Emulator")
        parser.add_argument("script", help="Path to the python script to run")
        parser.add_argument("--title", help="Title of the terminal window", default=None)
        parser.add_argument("--icon", help="Path to icon file (.ico, .png)", default=None)
        parser.add_argument("--on-top", action="store_true", help="Keep window always on top")
        parser.add_argument("args", nargs=argparse.REMAINDER, help="Arguments for the script")

        args = parser.parse_args()

        app = QApplication(sys.argv)
        app.setStyle("Fusion")  # Modern look

        # Dark palette
        palette = QPalette()
        palette.setColor(QPalette.Window, QColor("#1e1e1e"))
        palette.setColor(QPalette.WindowText, QColor("#d4d4d4"))
        palette.setColor(QPalette.Base, QColor("#1e1e1e"))
        palette.setColor(QPalette.AlternateBase, QColor("#2d2d2d"))
        palette.setColor(QPalette.ToolTipBase, QColor("#2d2d2d"))
        palette.setColor(QPalette.ToolTipText, QColor("#d4d4d4"))
        palette.setColor(QPalette.Text, QColor("#d4d4d4"))
        palette.setColor(QPalette.Button, QColor("#2d2d2d"))
        palette.setColor(QPalette.ButtonText, QColor("#d4d4d4"))
        palette.setColor(QPalette.Highlight, QColor("#0078d4"))
        palette.setColor(QPalette.HighlightedText, QColor("#ffffff"))
        app.setPalette(palette)

        terminal = PySide6Terminal(args.script, args.title, args.icon, args.on_top, tuple(args.args))
        terminal.show()

        sys.exit(app.exec())

    except Exception as e:
        import traceback

        print(f"ERROR: {e}")
        traceback.print_exc()
        input("Press Enter to exit...")
        sys.exit(1)


if __name__ == "__main__":
    main()

"""
Tkinter Terminal Emulator
=========================

A lightweight, thread-safe terminal emulator built with Tkinter.
Designed to run Python scripts with a modern, dark-themed UI.

Usage:
    python tkinter_terminal.py <script_path> [options] [-- script_args]

Arguments:
    script_path       Path to the Python script to execute.
    script_args       Arguments to pass to the target script.

Options:
    --title TITLE     Set the window title (default: script filename).
    --icon ICON_PATH  Set the window/tray icon (default: internal icon).

Example:
    python tkinter_terminal.py my_script.py --title "My App" --on-top -- --verbose
"""

import argparse
import ctypes
import ctypes.wintypes
import os
import queue
import subprocess
import sys
import threading
import tkinter as tk
from tkinter import font, messagebox

# ==============================================================================
# Needed Functions
# ==============================================================================


def safe_open(path: str, raise_error: bool = False) -> None:
    """safer alternative to os.startfile for cross platform use. Will not raise an error if problems with opening the file occur if raise_error==False."""
    if sys.platform.startswith("win"):
        subprocess.run(["explorer", path], check=raise_error)  # noqa: S603
    elif sys.platform == "darwin":
        subprocess.run(["open", path], check=raise_error)  # noqa: S603
    else:
        subprocess.run(["xdg-open", path], check=raise_error)  # noqa: S603


# ==============================================================================
# Tooltip Class
# ==============================================================================


class Tooltip:
    def __init__(self, widget, text):
        self.widget = widget
        self.text = text
        self.tooltip_window = None
        # Use add='+' to preserve existing bindings (like hover effects)
        self.widget.bind("<Enter>", self.show_tooltip, add="+")
        self.widget.bind("<Leave>", self.hide_tooltip, add="+")

    def show_tooltip(self, event=None):  # noqa: ARG002
        x, y, _, _ = self.widget.bbox("insert")
        x += self.widget.winfo_rootx() + 25
        y += self.widget.winfo_rooty() + 25

        self.tooltip_window = tw = tk.Toplevel(self.widget)
        tw.wm_overrideredirect(True)
        tw.wm_geometry(f"+{x}+{y}")

        label = tk.Label(
            tw,
            text=self.text,
            justify="left",
            background="#2d2d2d",
            foreground="#d4d4d4",
            relief="solid",
            borderwidth=1,
            font=("Segoe UI", 8),
        )
        label.pack(ipadx=1)

    def hide_tooltip(self, event=None):  # noqa: ARG002
        if self.tooltip_window:
            self.tooltip_window.destroy()
            self.tooltip_window = None


# ==============================================================================
# System Tray Icon
# ==============================================================================

# Windows API Constants
WM_LBUTTONUP = 0x0202
WM_RBUTTONUP = 0x0205
WM_USER = 0x400
NIM_ADD = 0x00000000
NIM_MODIFY = 0x00000001
NIM_DELETE = 0x00000002
NIF_MESSAGE = 0x00000001
NIF_ICON = 0x00000002
NIF_TIP = 0x00000004
IDI_APPLICATION = 32512
IMAGE_ICON = 1
LR_LOADFROMFILE = 0x00000010

# Define WNDPROCTYPE first
# LRESULT is LONG_PTR, which varies by arch. c_ssize_t is the correct Python equivalent.
LRESULT = ctypes.c_ssize_t
WNDPROCTYPE = ctypes.WINFUNCTYPE(
    LRESULT, ctypes.wintypes.HWND, ctypes.c_uint, ctypes.wintypes.WPARAM, ctypes.wintypes.LPARAM
)

# Define argtypes for DefWindowProcA to prevent 64-bit truncation/overflow
ctypes.windll.user32.DefWindowProcA.argtypes = [
    ctypes.wintypes.HWND,
    ctypes.c_uint,
    ctypes.wintypes.WPARAM,
    ctypes.wintypes.LPARAM,
]
ctypes.windll.user32.DefWindowProcA.restype = LRESULT


class WNDCLASS(ctypes.Structure):
    _fields_ = [  # noqa: RUF012
        ("style", ctypes.c_uint),
        ("lpfnWndProc", WNDPROCTYPE),
        ("cbClsExtra", ctypes.c_int),
        ("cbWndExtra", ctypes.c_int),
        ("hInstance", ctypes.wintypes.HINSTANCE),
        ("hIcon", ctypes.wintypes.HICON),
        ("hCursor", ctypes.wintypes.HICON),
        ("hbrBackground", ctypes.wintypes.HBRUSH),
        ("lpszMenuName", ctypes.c_char_p),
        ("lpszClassName", ctypes.c_char_p),
    ]


class NOTIFYICONDATA(ctypes.Structure):
    _fields_ = [  # noqa: RUF012
        ("cbSize", ctypes.c_uint),
        ("hWnd", ctypes.wintypes.HWND),
        ("uID", ctypes.c_uint),
        ("uFlags", ctypes.c_uint),
        ("uCallbackMessage", ctypes.c_uint),
        ("hIcon", ctypes.wintypes.HICON),
        ("szTip", ctypes.c_char * 128),
        ("dwState", ctypes.c_uint),
        ("dwStateMask", ctypes.c_uint),
        ("szInfo", ctypes.c_char * 256),
        ("uTimeout", ctypes.c_uint),
        ("szInfoTitle", ctypes.c_char * 64),
        ("dwInfoFlags", ctypes.c_uint),
    ]


class SystemTrayIcon:
    def __init__(self, tooltip, on_click, icon_path=None):
        self.tooltip = tooltip.encode("utf-8")
        self.on_click = on_click
        self.icon_path = icon_path
        self.hwnd = None
        self.hicon = None
        self.thread = None
        self.running = False

    def _window_proc(self, hwnd, msg, wparam, lparam):
        if msg == WM_USER + 20:
            if lparam == WM_LBUTTONUP:
                if self.on_click:
                    self.on_click()
            elif lparam == WM_RBUTTONUP:
                # Right click - maybe show menu later?
                pass
        return ctypes.windll.user32.DefWindowProcA(hwnd, msg, wparam, lparam)

    def _create_window(self):
        self.wnd_proc = WNDPROCTYPE(self._window_proc)

        hinst = ctypes.windll.kernel32.GetModuleHandleA(None)
        class_name = b"SystemTrayIconPy"

        wnd_class = WNDCLASS()
        wnd_class.style = 0
        wnd_class.lpfnWndProc = self.wnd_proc
        wnd_class.cbClsExtra = 0
        wnd_class.cbWndExtra = 0
        wnd_class.hInstance = hinst
        wnd_class.hIcon = 0
        wnd_class.hCursor = 0
        wnd_class.hbrBackground = 0
        wnd_class.lpszMenuName = None
        wnd_class.lpszClassName = class_name

        ctypes.windll.user32.RegisterClassA(ctypes.byref(wnd_class))

        self.hwnd = ctypes.windll.user32.CreateWindowExA(
            0, class_name, b"SystemTrayWindow", 0, 0, 0, 0, 0, 0, 0, hinst, 0
        )

        # Load Icon
        if self.icon_path and isinstance(self.icon_path, str):
            try:
                # Load from file
                self.hicon = ctypes.windll.user32.LoadImageA(
                    0, self.icon_path.encode("utf-8"), IMAGE_ICON, 0, 0, LR_LOADFROMFILE
                )
            except Exception:
                self.hicon = None

        if not self.hicon:
            # Load default application icon
            self.hicon = ctypes.windll.user32.LoadIconA(0, IDI_APPLICATION)

    def _add_icon(self):
        nid = NOTIFYICONDATA()
        nid.cbSize = ctypes.sizeof(NOTIFYICONDATA)
        nid.hWnd = self.hwnd
        nid.uID = 1
        nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP
        nid.uCallbackMessage = WM_USER + 20
        nid.hIcon = self.hicon
        nid.szTip = self.tooltip

        ctypes.windll.shell32.Shell_NotifyIconA(NIM_ADD, ctypes.byref(nid))

    def _remove_icon(self):
        nid = NOTIFYICONDATA()
        nid.cbSize = ctypes.sizeof(NOTIFYICONDATA)
        nid.hWnd = self.hwnd
        nid.uID = 1
        ctypes.windll.shell32.Shell_NotifyIconA(NIM_DELETE, ctypes.byref(nid))

    def _run(self):
        self._create_window()
        self._add_icon()

        msg = ctypes.wintypes.MSG()
        self.running = True
        while self.running and ctypes.windll.user32.GetMessageA(ctypes.byref(msg), None, 0, 0) > 0:
            ctypes.windll.user32.TranslateMessage(ctypes.byref(msg))
            ctypes.windll.user32.DispatchMessageA(ctypes.byref(msg))

        self._remove_icon()
        ctypes.windll.user32.DestroyWindow(self.hwnd)

    def show(self):
        if self.thread and self.thread.is_alive():
            return
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def hide(self):
        self.running = False
        if self.hwnd:
            ctypes.windll.user32.PostMessageA(self.hwnd, 0x0010, 0, 0)  # WM_CLOSE


# ==============================================================================
# Custom Title Bar & Window Logic
# ==============================================================================


class HoverButton(tk.Label):
    """Custom button using Label to support proper hover effects on Windows"""

    def __init__(
        self,
        master,
        text,
        command,
        bg="#2d2d2d",
        fg="#d4d4d4",
        hover_bg="#3e3e42",
        font=("Segoe UI", 10),
        width=5,
        **kwargs,
    ):
        super().__init__(
            master, text=text, bg=bg, fg=fg, font=font, width=width, cursor="hand2", padx=5, pady=3, **kwargs
        )
        self.command = command
        self.default_bg = bg
        self.hover_bg = hover_bg

        self.bind("<Button-1>", lambda e: self.command())  # noqa: ARG005
        self.bind("<Enter>", lambda e: self.config(bg=self.hover_bg))  # noqa: ARG005
        self.bind("<Leave>", lambda e: self.config(bg=self.default_bg))  # noqa: ARG005


class CustomTitleBar(tk.Frame):
    def __init__(
        self,
        master,
        app_title,
        on_minimize,
        on_maximize,
        on_close,
        on_tray,
        on_top_toggle,
        on_highlight_toggle,
        on_confirm_toggle,
        on_print_toggle,
        on_clear,
        script_path=None,
    ):
        super().__init__(master, bg="#2d2d2d", height=30)
        self.pack_propagate(False)  # Prevent shrinking

        self.master = master
        self._drag_data = {"x": 0, "y": 0}
        self._drag_start_geometry = None
        self.script_path = script_path

        self.title_label = tk.Label(
            self, text=app_title, bg="#2d2d2d", fg="#d4d4d4", font=("Segoe UI", 10), cursor="hand2"
        )
        self.title_label.pack(side=tk.LEFT, padx=10)

        # Add single-click to open script folder with blue hover
        if self.script_path:
            self.title_label.bind("<ButtonRelease-1>", self.on_title_click)
            self.title_label.bind("<Enter>", lambda e: self.title_label.config(bg="#0078d4"))  # noqa: ARG005
            self.title_label.bind("<Leave>", lambda e: self.title_label.config(bg="#2d2d2d"))  # noqa: ARG005

        # Buttons Frame
        self.buttons_frame = tk.Frame(self, bg="#2d2d2d")
        self.buttons_frame.pack(side=tk.RIGHT)

        # Button Styles (with FLAT relief to allow hover to work)
        btn_config = {
            "bg": "#2d2d2d",
            "fg": "#d4d4d4",
            "bd": 0,
            "font": ("Segoe UI", 10),
            "width": 5,
            "relief": tk.FLAT,
            "highlightthickness": 0,
        }
        close_config = btn_config.copy()
        close_config["width"] = 6
        # Maximize Button Config (Larger Font)
        max_config = btn_config.copy()
        max_config["font"] = ("Segoe UI", 12)  # Larger font for the square

        # Tray Button (▼) - Bright blue hover
        self.tray_btn = HoverButton(self.buttons_frame, text="▼", command=on_tray, hover_bg="#0078d4")
        self.tray_btn.pack(side=tk.LEFT)
        Tooltip(self.tray_btn, "Minimize to System Tray")

        # Minimize Button (―) - Gray hover
        self.min_btn = HoverButton(self.buttons_frame, text="―", command=on_minimize, hover_bg="#3e3e42")
        self.min_btn.pack(side=tk.LEFT)

        # Maximize Button (□) - Gray hover, larger font
        self.max_btn = HoverButton(
            self.buttons_frame, text="□", command=on_maximize, hover_bg="#3e3e42", font=("Segoe UI", 12)
        )
        self.max_btn.pack(side=tk.LEFT)

        # Close Button (✕) - Red hover
        self.close_btn = HoverButton(self.buttons_frame, text="✕", command=on_close, hover_bg="#e81123", width=6)
        self.close_btn.pack(side=tk.LEFT)

        # --- Settings Buttons (Left Side) ---
        self.settings_frame = tk.Frame(self, bg="#2d2d2d")
        self.settings_frame.pack(side=tk.LEFT, padx=5)

        # Helper to create toggle buttons with bright blue hover
        def create_toggle_button(text, command, tooltip):
            btn = HoverButton(self.settings_frame, text=text, command=command, hover_bg="#0078d4")
            btn.pack(side=tk.LEFT, padx=2)
            Tooltip(btn, tooltip)
            return btn

        self.top_btn = create_toggle_button("📌", self.toggle_top, "Toggle Always on Top")
        self.highlight_btn = create_toggle_button("🔔", self.toggle_highlight, "Toggle Highlight on Print")
        self.confirm_btn = create_toggle_button("🔒", self.toggle_confirm, "Toggle Confirm on Close")
        self.print_btn = create_toggle_button("💬", self.toggle_print, "Toggle Command Printing")
        self.clear_btn = create_toggle_button("🗑", on_clear, "Clear Output")

        self.callbacks = {
            "top": on_top_toggle,
            "highlight": on_highlight_toggle,
            "confirm": on_confirm_toggle,
            "print": on_print_toggle,
        }

        # Initialize states (visual only, logic is in main app)
        self.toggles = {"top": False, "highlight": False, "confirm": False, "print": True}
        self.update_toggle_visuals()

        # Bind dragging
        self.bind("<Button-1>", self.start_drag)
        self.bind("<B1-Motion>", self.do_drag)
        self.bind("<ButtonRelease-1>", self.stop_drag)
        self.title_label.bind("<Button-1>", self.start_drag, add="+")
        self.title_label.bind("<B1-Motion>", self.do_drag, add="+")
        self.title_label.bind("<ButtonRelease-1>", self.stop_drag, add="+")

    def on_title_click(self, event):
        """Handle title click - if it's a drag, don't open folder"""
        # Only open folder if mouse hasn't moved much (not a drag)
        if (
            abs(event.x - self._drag_data.get("x", event.x)) < 5
            and abs(event.y - self._drag_data.get("y", event.y)) < 5
        ):
            self.open_script_folder()

    def toggle_top(self):
        self.toggles["top"] = not self.toggles["top"]
        self.callbacks["top"](self.toggles["top"])
        self.update_toggle_visuals()

    def toggle_highlight(self):
        self.toggles["highlight"] = not self.toggles["highlight"]
        self.callbacks["highlight"](self.toggles["highlight"])
        self.update_toggle_visuals()

    def toggle_confirm(self):
        self.toggles["confirm"] = not self.toggles["confirm"]
        self.callbacks["confirm"](self.toggles["confirm"])
        self.update_toggle_visuals()

    def toggle_print(self):
        self.toggles["print"] = not self.toggles["print"]
        self.callbacks["print"](self.toggles["print"])
        self.update_toggle_visuals()

    def update_toggle_visuals(self):
        for key, btn in [
            ("top", self.top_btn),
            ("highlight", self.highlight_btn),
            ("confirm", self.confirm_btn),
            ("print", self.print_btn),
        ]:
            if self.toggles[key]:
                btn.config(fg="#00FF00", activeforeground="#00FF00")  # Green when active
            else:
                btn.config(fg="#d4d4d4", activeforeground="#ffffff")

    def start_drag(self, event):
        self.master.config(cursor="arrow")
        self._drag_data["x"] = event.x
        self._drag_data["y"] = event.y
        # Store original window state in case we need to restore from maximized
        if self.master.state() == "zoomed":
            # If dragging from maximized, restore to normal first
            self.master.state("normal")

            # Restore original geometry if available
            if hasattr(self.master, "_pre_snap_geometry") and self.master._pre_snap_geometry:
                self.master.geometry(self.master._pre_snap_geometry)
                # Parse width from geometry string "WxH+X+Y"
                try:
                    width = int(self.master._pre_snap_geometry.split("x")[0])
                except (ValueError, IndexError):
                    width = self.master.winfo_width()
            else:
                width = self.master.winfo_width()

            # Center the window under cursor
            self._drag_data["x"] = width // 2

        # Save geometry BEFORE the drag moves it (for restoration)
        self._drag_start_geometry = self.master.geometry()

        return "break"  # Prevent other bindings (like resize) from firing

    def do_drag(self, event):
        deltax = event.x - self._drag_data["x"]
        deltay = event.y - self._drag_data["y"]
        x = self.master.winfo_x() + deltax
        y = self.master.winfo_y() + deltay
        self.master.geometry(f"+{x}+{y}")

    def stop_drag(self, event):
        self.master.config(cursor="")  # Reset cursor
        """Handle window snapping when drag ends"""
        # Get cursor position on screen
        cursor_x = event.x_root
        cursor_y = event.y_root

        # Get screen dimensions
        screen_width = self.master.winfo_screenwidth()
        screen_height = self.master.winfo_screenheight()

        # Define snap threshold (pixels from edge)
        snap_threshold = 10

        # Check if cursor is near top edge - maximize
        if cursor_y <= snap_threshold:
            # Save current geometry before maximizing
            if self.master.state() != "zoomed":
                self.master._pre_snap_geometry = self._drag_start_geometry  # noqa: SLF001
            self.master.state("zoomed")

        # Check if cursor is near left edge - snap to left half
        elif cursor_x <= snap_threshold:
            self.snap_to_half("left", screen_width, screen_height)

        # Check if cursor is near right edge - snap to right half
        elif cursor_x >= screen_width - snap_threshold:
            self.snap_to_half("right", screen_width, screen_height)

    def snap_to_half(self, side, screen_width, screen_height):
        """Snap window to half of the screen"""
        # Save current geometry
        self.master._pre_snap_geometry = self._drag_start_geometry  # noqa: SLF001

        # Calculate half-screen dimensions
        half_width = screen_width // 2

        if side == "left":
            self.master.geometry(f"{half_width}x{screen_height}+0+0")
        elif side == "right":
            self.master.geometry(f"{half_width}x{screen_height}+{half_width}+0")

    def open_script_folder(self, event=None):  # noqa: ARG002
        """Open the folder containing the script in Windows Explorer"""
        if self.script_path:
            folder_path = os.path.dirname(os.path.abspath(self.script_path))
            safe_open(folder_path)


class TkinterTerminal:
    def __init__(self, root, target_script, terminal_name=None, icon_path=None, on_top=False, script_args=()):
        self.root = root

        # Feature States
        self.always_on_top = on_top
        self.highlight_on_print = False
        self.confirm_on_close = False
        self.show_command_printing = True

        # Resize state
        self.resize_border_width = 10  # Width of the resize detection area (increased for easier grabbing)
        self._resize_data = None
        self._resize_direction = None

        # Default title if not provided
        if terminal_name is None:
            terminal_name = os.path.basename(target_script)

        self.root.title(terminal_name)
        self.root.geometry("900x600")

        # Always on Top
        if on_top:
            self.root.attributes("-topmost", True)

        self.icon_path = icon_path

        # Try to find default icon if not provided
        if not self.icon_path:
            if os.path.exists("fallback_terminal_icon.ico"):
                self.icon_path = "fallback_terminal_icon.ico"

        if self.icon_path:
            try:
                self.root.iconbitmap(self.icon_path)
            except tk.TclError:
                print(f"Warning: Could not load icon from {self.icon_path}")

        # Remove default title bar
        self.root.overrideredirect(True)

        # Apply Windows 11 Rounded Corners (DWMWA_WINDOW_CORNER_PREFERENCE = 33)
        try:
            DWMWA_WINDOW_CORNER_PREFERENCE = 33
            DWMWCP_ROUND = 2
            hwnd = ctypes.windll.user32.GetParent(self.root.winfo_id())
            ctypes.windll.dwmapi.DwmSetWindowAttribute(
                hwnd,
                DWMWA_WINDOW_CORNER_PREFERENCE,
                ctypes.byref(ctypes.c_int(DWMWCP_ROUND)),
                ctypes.sizeof(ctypes.c_int),
            )
        except Exception:
            pass  # Fail silently on older Windows

        # Make sure it shows in taskbar (sometimes needed for overrideredirect)
        self.set_appwindow()

        # Modern Dark Theme Colors (VS Code-ish)
        self.colors = {
            "bg": "#1e1e1e",
            "fg": "#d4d4d4",
            "cursor": "#ffffff",
            "select_bg": "#264f78",
            "prompt": "#00ff00",  # Bright Green for high visibility
            "stdin": "#ce9178",  # Orange-ish (String color)
            "stdout": "#d4d4d4",
            "stderr": "#f44747",  # Red
            "system": "#569cd6",  # Blue
            "input_bg": "#2d2d2d",  # Slightly lighter background for input area
        }

        self.root.configure(bg=self.colors["bg"])

        # Configure font
        self.custom_font = font.Font(family="Consolas", size=11)

        # --- Custom Title Bar ---
        self.title_bar = CustomTitleBar(
            root,
            terminal_name,
            self.minimize_window,
            self.maximize_window,
            self.on_closing,
            self.minimize_to_tray,
            self.set_always_on_top,
            self.set_highlight_on_print,
            self.set_confirm_on_close,
            self.set_show_command_printing,
            self.clear_output,
            target_script,
        )
        self.title_bar.pack(side=tk.TOP, fill=tk.X)

        # Sync initial state
        self.title_bar.toggles["top"] = self.always_on_top
        self.title_bar.update_toggle_visuals()

        # --- Input Area (Packed FIRST to ensure visibility at bottom) ---
        self.input_frame = tk.Frame(root, bg=self.colors["input_bg"])
        self.input_frame.pack(side=tk.BOTTOM, fill=tk.X, padx=0, pady=0)

        # Add a separator line
        self.separator = tk.Frame(self.input_frame, bg="#3e3e42", height=1)
        self.separator.pack(side=tk.TOP, fill=tk.X)

        self.input_inner_frame = tk.Frame(self.input_frame, bg=self.colors["input_bg"])
        self.input_inner_frame.pack(fill=tk.X, padx=10, pady=5)

        self.prompt_label = tk.Label(
            self.input_inner_frame,
            text=">>> ",
            bg=self.colors["input_bg"],
            fg=self.colors["prompt"],
            font=(self.custom_font.cget("family"), 11, "bold"),  # Bold prompt
        )
        self.prompt_label.pack(side=tk.LEFT)

        self.input_entry = tk.Entry(
            self.input_inner_frame,
            bg=self.colors["input_bg"],
            fg="#ffffff",  # White text for input
            insertbackground=self.colors["cursor"],
            selectbackground=self.colors["select_bg"],
            font=self.custom_font,
            relief=tk.FLAT,
            bd=0,
            highlightthickness=0,
        )
        self.input_entry.pack(side=tk.LEFT, expand=True, fill=tk.X)
        self.input_entry.bind("<Return>", self.send_input)
        self.input_entry.bind("<Up>", lambda e: self.navigate_history(-1))  # noqa: ARG005
        self.input_entry.bind("<Down>", lambda e: self.navigate_history(1))  # noqa: ARG005
        self.input_entry.focus_set()

        # --- Output Area (Packed SECOND to fill remaining space) ---
        self.main_frame = tk.Frame(root, bg=self.colors["bg"])
        self.main_frame.pack(side=tk.TOP, expand=True, fill=tk.BOTH, padx=10, pady=0)

        # Output area (Text widget)
        self.output_text = tk.Text(
            self.main_frame,
            bg=self.colors["bg"],
            fg=self.colors["fg"],
            insertbackground=self.colors["cursor"],
            selectbackground=self.colors["select_bg"],
            font=self.custom_font,
            state=tk.DISABLED,
            wrap=tk.WORD,
            bd=0,  # No border
            highlightthickness=0,  # No focus highlight
        )
        self.output_text.pack(expand=True, fill=tk.BOTH, side=tk.LEFT)

        # Scrollbar for output (Styled minimal if possible, otherwise standard)
        self.scrollbar = tk.Scrollbar(
            self.main_frame,
            command=self.output_text.yview,
            bg=self.colors["bg"],
            troughcolor=self.colors["bg"],
            bd=0,
            elementborderwidth=0,
        )
        self.output_text.configure(yscrollcommand=self.scrollbar.set)

        # Initialize state variables
        self.process = None
        self.queue = queue.Queue()
        self.history = []
        self.history_index = 0

        # Start the subprocess and queue checking
        self.start_subprocess(target_script, script_args)
        self.check_queue()

        # Bind resize events to root window (using add='+' to preserve other bindings)
        self.root.bind("<Motion>", self.update_cursor, add="+")
        self.root.bind("<Button-1>", self.start_resize, add="+")
        self.root.bind("<B1-Motion>", self.do_resize, add="+")
        self.root.bind("<ButtonRelease-1>", self.stop_resize, add="+")

    def set_appwindow(self):
        # Force the window to appear in the taskbar and behave like a normal app
        GWL_EXSTYLE = -20
        WS_EX_APPWINDOW = 0x00040000
        WS_EX_TOOLWINDOW = 0x00000080

        hwnd = ctypes.windll.user32.GetParent(self.root.winfo_id())
        style = ctypes.windll.user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
        style = style & ~WS_EX_TOOLWINDOW
        style = style | WS_EX_APPWINDOW
        ctypes.windll.user32.SetWindowLongW(hwnd, GWL_EXSTYLE, style)

        # Force refresh
        self.root.wm_withdraw()
        self.root.after(10, lambda: self.root.wm_deiconify())

    def clear_output(self):
        self.output_text.config(state=tk.NORMAL)
        self.output_text.delete("1.0", tk.END)
        self.output_text.config(state=tk.DISABLED)

    def minimize_window(self):
        # Standard minimize to taskbar
        # SW_SHOWMINIMIZED = 2
        ctypes.windll.user32.ShowWindow(ctypes.windll.user32.GetParent(self.root.winfo_id()), 2)

    def maximize_window(self):
        # Simple toggle for now
        if self.root.state() == "zoomed":
            self.root.state("normal")
            # Restore previous geometry if available
            if hasattr(self.root, "_pre_snap_geometry") and self.root._pre_snap_geometry:
                self.root.geometry(self.root._pre_snap_geometry)
        else:
            self.root._pre_snap_geometry = self.root.geometry()  # noqa: SLF001
            self.root.state("zoomed")

    def minimize_to_tray(self):
        # Save current window state (maximized or normal)
        self.saved_state = self.root.state()

        # Only save geometry if not maximized (maximized windows have weird geometry strings)
        if self.saved_state != "zoomed":
            self.saved_geometry = self.root.geometry()

        self.root.withdraw()  # Hide the window completely
        if not hasattr(self, "tray_icon") or self.tray_icon is None:
            # Create tray icon (SystemTrayIcon is now defined in this file)
            self.tray_icon = SystemTrayIcon(self.root.title(), self.restore_from_tray, self.icon_path)

        self.tray_icon.show()

    def restore_from_tray(self):
        # This is called from a separate thread, so we must use after() to schedule GUI updates
        self.root.after(0, self._restore_window_logic)

    def _restore_window_logic(self):
        self.root.deiconify()

        # Re-apply appwindow style if needed after restore
        self.set_appwindow()

        # Restore saved position and size (only if it was not maximized)
        if hasattr(self, "saved_state") and self.saved_state == "zoomed":
            # Restore maximized state
            self.root.state("zoomed")
        elif hasattr(self, "saved_geometry") and self.saved_geometry:
            # Restore normal position and size
            self.root.geometry(self.saved_geometry)

        if self.tray_icon:
            self.tray_icon.hide()
            self.tray_icon = None

    def get_resize_direction(self, event):
        """Determine which edge/corner is being hovered based on mouse position"""
        # Get mouse position relative to root window
        x = event.x_root - self.root.winfo_x()
        y = event.y_root - self.root.winfo_y()

        width = self.root.winfo_width()
        height = self.root.winfo_height()
        border = self.resize_border_width
        corner_size = 20  # Larger area for corners to make them easier to grab

        # Check corners first (they take priority and have larger detection area)
        if x < corner_size and y < corner_size:
            return "nw"
        elif x > width - corner_size and y < corner_size:
            return "ne"
        elif x < corner_size and y > height - corner_size:
            return "sw"
        elif x > width - corner_size and y > height - corner_size:
            return "se"
        # Check edges (smaller detection area)
        elif x < border:
            return "w"
        elif x > width - border:
            return "e"
        elif y < border:
            return "n"
        elif y > height - border:
            return "s"

        return None

    def update_cursor(self, event):
        """Update cursor based on position for resize feedback"""
        # Don't change cursor if window is maximized or if dragging (Button 1 pressed)
        if self.root.state() == "zoomed" or (event.state & 0x100):
            return

        direction = self.get_resize_direction(event)

        cursor_map = {
            "n": "sb_v_double_arrow",
            "s": "sb_v_double_arrow",
            "e": "sb_h_double_arrow",
            "w": "sb_h_double_arrow",
            "ne": "size_ne_sw",
            "nw": "size_nw_se",
            "se": "size_nw_se",
            "sw": "size_ne_sw",
        }

        if direction:
            self.root.config(cursor=cursor_map.get(direction, ""))
        else:
            self.root.config(cursor="")

    def start_resize(self, event):
        """Start resizing operation"""
        # Don't resize if window is maximized
        if self.root.state() == "zoomed":
            return

        direction = self.get_resize_direction(event)

        if direction:
            self._resize_direction = direction
            self._resize_data = {
                "x": event.x_root,
                "y": event.y_root,
                "width": self.root.winfo_width(),
                "height": self.root.winfo_height(),
                "window_x": self.root.winfo_x(),
                "window_y": self.root.winfo_y(),
            }

    def do_resize(self, event):
        """Perform the resize operation"""
        if not self._resize_data or not self._resize_direction:
            return

        # Calculate deltas
        dx = event.x_root - self._resize_data["x"]
        dy = event.y_root - self._resize_data["y"]

        # Get current values
        new_width = self._resize_data["width"]
        new_height = self._resize_data["height"]
        new_x = self._resize_data["window_x"]
        new_y = self._resize_data["window_y"]

        # Minimum window size (reduced for more flexibility)
        min_width = 150
        min_height = 100

        direction = self._resize_direction

        # Handle resizing based on direction
        if "e" in direction:  # East (right edge)
            new_width = max(min_width, self._resize_data["width"] + dx)

        if "w" in direction:  # West (left edge)
            potential_width = self._resize_data["width"] - dx
            # Clamp to minimum and adjust position accordingly
            new_width = max(min_width, potential_width)
            # Only move the window if we're not at minimum size
            if potential_width >= min_width:
                new_x = self._resize_data["window_x"] + dx
            else:
                # At minimum, adjust x to prevent snapping
                new_x = self._resize_data["window_x"] + (self._resize_data["width"] - min_width)

        if "s" in direction:  # South (bottom edge)
            new_height = max(min_height, self._resize_data["height"] + dy)

        if "n" in direction:  # North (top edge)
            potential_height = self._resize_data["height"] - dy
            # Clamp to minimum and adjust position accordingly
            new_height = max(min_height, potential_height)
            # Only move the window if we're not at minimum size
            if potential_height >= min_height:
                new_y = self._resize_data["window_y"] + dy
            else:
                # At minimum, adjust y to prevent snapping
                new_y = self._resize_data["window_y"] + (self._resize_data["height"] - min_height)

        # Apply new geometry
        self.root.geometry(f"{new_width}x{new_height}+{new_x}+{new_y}")

    def stop_resize(self, event):  # noqa: ARG002
        """Stop resizing operation"""
        self._resize_data = None
        self._resize_direction = None
        self.root.config(cursor="")

    def start_subprocess(self, target_script, script_args):
        try:
            # Use python executable that is running this script
            cmd = [sys.executable, "-u", target_script] + script_args

            # Start subprocess with pipes
            # bufsize=0 and -u flag ensure unbuffered output
            self.process = subprocess.Popen(  # noqa: S603
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=0,
                cwd=os.path.dirname(os.path.abspath(target_script)),  # Run in script's directory
            )

            # Start threads to read stdout and stderr
            threading.Thread(target=self.read_stream, args=(self.process.stdout, "stdout"), daemon=True).start()
            threading.Thread(target=self.read_stream, args=(self.process.stderr, "stderr"), daemon=True).start()

        except Exception as e:
            self.queue_write(f"[System] Error starting process: {e}\n", "error")

    def read_stream(self, stream, stream_type):
        """Reads from a stream and puts data into the queue."""
        try:
            while True:
                char = stream.read(1)
                if not char:
                    break
                self.queue.put((char, stream_type))
        except Exception:
            pass
        finally:
            if self.process and self.process.poll() is not None:
                self.queue.put(("[System] Process finished.\n", "system"))

    def check_queue(self):
        """Checks queue for new data and updates text widget."""
        while not self.queue.empty():
            try:
                content, tag = self.queue.get_nowait()
                self.write_to_output(content, tag)
            except queue.Empty:
                break

        # Check if process is dead
        if self.process and self.process.poll() is not None:
            self.input_entry.config(state=tk.DISABLED)

        self.root.after(10, self.check_queue)

    def write_to_output(self, text, tag):
        self.output_text.config(state=tk.NORMAL)

        # Tag configuration
        self.output_text.tag_config("stderr", foreground=self.colors["stderr"])
        self.output_text.tag_config("system", foreground=self.colors["system"])
        self.output_text.tag_config("stdin", foreground=self.colors["stdin"])
        self.output_text.tag_config("stdout", foreground=self.colors["stdout"])

        # Get the position before inserting
        start_pos = self.output_text.index("end-1c")

        # Insert text with the content tag
        self.output_text.insert(tk.END, text, tag)

        # Get the position after inserting
        end_pos = self.output_text.index("end-1c")

        self.output_text.see(tk.END)
        self.output_text.config(state=tk.DISABLED)

        # Create a unique flash tag for this specific text to avoid interference
        if not hasattr(self, "_flash_counter"):
            self._flash_counter = 0
        self._flash_counter += 1
        unique_flash_tag = f"flash_{self._flash_counter}"

        # Start the gradual fade effect with unique tag
        self.start_fade_effect(start_pos, end_pos, tag, unique_flash_tag)

        # Highlight on Print Logic
        if self.highlight_on_print and self.root.focus_displayof() is None:
            # Flash the taskbar icon (simple version: just force attention)
            try:
                ctypes.windll.user32.FlashWindow(ctypes.windll.user32.GetParent(self.root.winfo_id()), True)
            except Exception:
                pass

    def start_fade_effect(self, start_pos, end_pos, original_tag, flash_tag):
        """Start a gradual fade effect for newly printed text"""
        # Define fade steps - very smooth transition with many steps
        fade_colors = [
            "#0078d4",  # Bright blue (Windows accent color)
            "#0074cc",
            "#0070c4",
            "#006cbc",
            "#0068b4",
            "#0064ac",
            "#0060a4",
            "#005c9c",
            "#005894",
            "#00548c",
            "#005084",
            "#004c7c",
            "#004874",
            "#00446c",
            "#004064",
            "#003c5c",
            "#003854",
            "#00344c",
            "#003044",
            "#002c3c",
            "#002834",
            "#00242c",
            "#002024",
            "#001c20",
            "#001a1c",
            "#001919",
            "#001a1a",
            "#001b1b",
            "#001d1d",
            "#1e1e1e",  # Back to normal background
        ]

        # Start the fade animation
        self.fade_step(start_pos, end_pos, original_tag, fade_colors, 0, flash_tag)

    def fade_step(self, start_pos, end_pos, original_tag, colors, step, flash_tag):
        """Perform one step of the fade animation"""
        if step >= len(colors):
            # Fade complete, remove the flash tag
            try:
                self.output_text.config(state=tk.NORMAL)
                self.output_text.tag_remove(flash_tag, start_pos, end_pos)
                self.output_text.config(state=tk.DISABLED)
            except Exception:
                pass
            return

        try:
            self.output_text.config(state=tk.NORMAL)

            # Configure the unique flash tag with the current color
            self.output_text.tag_config(flash_tag, background=colors[step])

            # Apply the flash tag to the text range
            self.output_text.tag_add(flash_tag, start_pos, end_pos)

            self.output_text.config(state=tk.DISABLED)

            # Schedule the next fade step (167ms per step ≈ 5 seconds total for 30 steps)
            self.root.after(167, lambda: self.fade_step(start_pos, end_pos, original_tag, colors, step + 1, flash_tag))
        except Exception:
            pass  # Ignore errors if text was deleted or widget destroyed

    def send_input(self, event):  # noqa: ARG002
        # if self.process and self.process.poll() is None: # Allow commands even if process is dead? Maybe.

        text = self.input_entry.get()
        self.input_entry.delete(0, tk.END)

        # Add to history if not empty
        if text.strip():
            self.history.append(text)
            self.history_index = len(self.history)  # Reset index to end

        # Handle Special Commands
        if text.strip().lower() in ["cls", "clear"]:
            self.output_text.config(state=tk.NORMAL)
            self.output_text.delete(1.0, tk.END)
            self.output_text.config(state=tk.DISABLED)
            return

        if text.strip().lower() == "exit":
            self.on_closing()
            return

        # Handle System Commands (prefixed with !)
        if text.startswith("!"):
            cmd = text[1:].strip()
            if self.show_command_printing:
                self.write_to_output(f"{text}\n", "stdin")
            self.write_to_output(f"[System] Running: {cmd}\n", "system")

            try:
                # Run command and capture output
                result = subprocess.run(cmd, shell=True, capture_output=True, text=True)  # noqa: S602
                if result.stdout:
                    self.write_to_output(result.stdout, "stdout")
                if result.stderr:
                    self.write_to_output(result.stderr, "stderr")
            except Exception as e:
                self.write_to_output(f"[System] Error running command: {e}\n", "error")
            return

        # Send to subprocess
        if self.process and self.process.poll() is None:
            # Echo input to output
            if self.show_command_printing:
                self.write_to_output(text + "\n", "stdin")

            try:
                self.process.stdin.write(text + "\n")
                self.process.stdin.flush()
            except Exception as e:
                self.write_to_output(f"\n[System] Error sending input: {e}\n", "error")
        else:
            if self.show_command_printing:
                self.write_to_output(f"{text}\n", "stdin")
            self.write_to_output("\n[System] Process is not running.\n", "system")

    def navigate_history(self, direction):
        if not self.history:
            return

        # Update index
        self.history_index += direction

        # Clamp index
        if self.history_index < 0:
            self.history_index = 0
        elif self.history_index > len(self.history):
            self.history_index = len(self.history)

        self.input_entry.delete(0, tk.END)

        if self.history_index < len(self.history):
            self.input_entry.insert(0, self.history[self.history_index])
        else:
            # If we go past the end, clear the input (new command)
            pass

    def queue_write(self, text, tag):
        self.queue.put((text, tag))

    def on_closing(self):
        if self.confirm_on_close:
            if not messagebox.askokcancel("Quit", "Do you want to quit?"):
                return

        if hasattr(self, "tray_icon") and self.tray_icon:
            self.tray_icon.hide()
        if self.process and self.process.poll() is None:
            self.process.terminate()
        self.root.destroy()

    # --- Feature Setters ---
    def set_always_on_top(self, enabled):
        self.always_on_top = enabled
        self.root.attributes("-topmost", enabled)

    def set_highlight_on_print(self, enabled):
        self.highlight_on_print = enabled

    def set_confirm_on_close(self, enabled):
        self.confirm_on_close = enabled

    def set_show_command_printing(self, enabled):
        self.show_command_printing = enabled


if __name__ == "__main__":
    try:
        parser = argparse.ArgumentParser(description="Tkinter Terminal Emulator")
        parser.add_argument("script", help="Path to the python script to run")
        parser.add_argument("--title", help="Title of the terminal window", default=None)
        parser.add_argument("--icon", help="Path to icon file (.ico)", default=None)
        parser.add_argument("--on-top", action="store_true", help="Keep window always on top")
        parser.add_argument("args", nargs=argparse.REMAINDER, help="Arguments for the script")

        args = parser.parse_args()

        root = tk.Tk()
        # We handle geometry in the class now

        terminal = TkinterTerminal(root, args.script, args.title, args.icon, args.on_top, args.args)
        root.mainloop()

        sys.exit(0)
    except Exception as e:
        import traceback

        print(f"ERROR: {e}")
        traceback.print_exc()
        input("Press Enter to exit...")

        sys.exit(1)

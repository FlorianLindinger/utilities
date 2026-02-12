# Fancy Terminal - PySide6 Version

A modern, feature-rich terminal emulator built with PySide6 for running Python scripts with a sleek, customizable UI.

## Features

### Core Functionality

- **Subprocess Execution**: Run Python scripts with full stdin/stdout/stderr support
- **Command History**: Navigate previous commands with Up/Down arrows
- **Syntax Highlighting**: Color-coded output for different stream types
- **Input Handling**: Interactive input support for running scripts

### UI Features

- **Custom Title Bar**: Frameless window with custom controls
- **Window Management**: Minimize, maximize, close, and minimize to system tray
- **Drag & Drop**: Drag window by title bar, double-click to maximize
- **Resizable**: Resize from edges and corners with visual feedback
- **Always on Top**: Toggle to keep window above others

### Advanced Features

- **System Tray**: Minimize to tray with restore functionality
- **Search**: Find text in output (Ctrl+F)
- **Font Zoom**: Increase/decrease font size with buttons or Ctrl+Scroll
- **Settings Persistence**: Saves window geometry, font size, and toggle states
- **Command Printing Toggle**: Show/hide echoed commands
- **Highlight on Print**: Flash taskbar when output appears while unfocused
- **Confirm on Close**: Optional confirmation dialog before closing
- **Clear Output**: Clear terminal output with button or `cls`/`clear` command
- **System Commands**: Run shell commands with `!` prefix

### Improvements over Tkinter Version

1. **Better Performance**: QPlainTextEdit handles large outputs more efficiently
2. **Cross-platform**: Uses Qt's system tray instead of Windows API
3. **Modern Look**: Fusion style with dark theme
4. **Search Functionality**: Built-in text search
5. **Settings Persistence**: Automatic save/restore of preferences
6. **Better Text Selection**: Improved copy/paste functionality
7. **Cleaner Code**: Qt's signal/slot mechanism for thread-safe updates

## Installation

```bash
pip install -r requirements_pyside6.txt
```

## Usage

### Basic Usage

```bash
python pyside6_terminal.py script.py
```

### With Options

```bash
python pyside6_terminal.py script.py --title "My App" --on-top --icon app.ico
```

### With Script Arguments

```bash
python pyside6_terminal.py script.py -- --arg1 value1 --arg2 value2
```

## Command Line Arguments

- `script` - Path to the Python script to execute (required)
- `--title TITLE` - Set custom window title (default: script filename)
- `--icon PATH` - Set window/tray icon (.ico or .png file)
- `--on-top` - Start with "Always on Top" enabled
- `-- ARGS` - Pass arguments to the target script (after `--`)

## Keyboard Shortcuts

- **Ctrl+F** - Search in output
- **Ctrl+Scroll** - Zoom in/out
- **Up/Down** - Navigate command history
- **Enter** - Send input to subprocess

## Special Commands

- `cls` or `clear` - Clear terminal output
- `exit` - Close the terminal
- `!command` - Run shell command (e.g., `!dir`, `!echo hello`)

## Toggle Buttons

- **📌 Always on Top** - Keep window above all others
- **🔔 Highlight on Print** - Flash taskbar when output appears
- **🔒 Confirm on Close** - Show confirmation dialog before closing
- **💬 Command Printing** - Show/hide echoed commands in output
- **🗑 Clear** - Clear all output
- **🔍 Search** - Search for text in output

## Color Scheme

The terminal uses a VS Code-inspired dark theme:

- Background: `#1e1e1e`
- Foreground: `#d4d4d4`
- Prompt: `#00ff00` (bright green)
- stdin: `#ce9178` (orange)
- stdout: `#d4d4d4` (light gray)
- stderr: `#f44747` (red)
- system: `#569cd6` (blue)

## Settings Storage

Settings are automatically saved using QSettings:

- **Windows**: Registry under `HKEY_CURRENT_USER\Software\FancyTerminal\PySide6Terminal`
- **Linux**: `~/.config/FancyTerminal/PySide6Terminal.conf`
- **macOS**: `~/Library/Preferences/com.FancyTerminal.PySide6Terminal.plist`

Saved settings include:

- Window geometry and state
- Font size
- Toggle button states (always on top, highlight, confirm, command printing)

## Comparison with Tkinter Version

| Feature | Tkinter | PySide6 |
|---------|---------|---------|
| Performance | Good | Better |
| Large Output Handling | Moderate | Excellent |
| System Tray | Windows API | Cross-platform Qt |
| Search | ❌ | ✅ |
| Settings Persistence | ❌ | ✅ |
| Window Snapping | Custom | Qt Built-in |
| Text Selection | Basic | Advanced |
| Code Complexity | Higher | Lower |
| Dependencies | Built-in | Requires PySide6 |

## Requirements

- Python 3.8+
- PySide6 6.6.0+

## License

This is a utility script for personal use.

## Example Scripts to Test

### Simple Script

```python
# test_script.py
print("Hello from the terminal!")
name = input("Enter your name: ")
print(f"Hello, {name}!")
```

Run with:

```bash
python pyside6_terminal.py test_script.py --title "Test Terminal"
```

### Script with Arguments

```python
# test_args.py
import sys
print(f"Arguments: {sys.argv[1:]}")
```

Run with:

```bash
python pyside6_terminal.py test_args.py -- arg1 arg2 arg3
```

import time
import win32api  # install as pywin32
import win32gui  # install as pywin32
import win32con  # install as pywin32
import sys


def set_window_icon(window_title: str, icon_path: str, print_warning=False):
    try:
        hwnd = win32gui.FindWindow(None, window_title)
        icon_flags = win32gui.LR_LOADFROMFILE | win32gui.LR_DEFAULTSIZE
        hicon = win32gui.LoadImage(
            None, icon_path, win32gui.IMAGE_ICON, 0, 0, icon_flags)
        win32api.SendMessage(hwnd, win32con.WM_SETICON,
                             win32con.ICON_SMALL, hicon)
        win32api.SendMessage(hwnd, win32con.WM_SETICON,
                             win32con.ICON_BIG, hicon)
    except Exception as e:
        if print_warning:
            print(e)
            print(
                "Error: Use change_icon.exe with command:\nchange_icon {window name} {icon_path} {anything_if_you_want_to_print_errors}")


if len(sys.argv) == 3:
    set_window_icon(sys.argv[1], sys.argv[2])
    # needed because windows is slow and otherwise would not do it:
    time.sleep(0.2)
elif len(sys.argv) == 4:
    set_window_icon(sys.argv[1], sys.argv[2], True)
    # needed because windows is slow and otherwise would not do it:
    time.sleep(0.2)
else:
    print(
        "Error: Use change_icon.exe with command:\nchange_icon {window name} {icon_path} {anything_if_you_want_to_print_errors}")

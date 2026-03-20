import builtins
import inspect
import re
import sys
import time
import traceback
import types
from collections.abc import Callable
from functools import wraps

from PyQt5.QtCore import QEvent, QObject, QSettings, QSignalBlocker, Qt, QThread, QTimer, pyqtSignal, pyqtSlot
from PyQt5.QtGui import QBrush, QColor, QFont, QIcon, QImage, QIntValidator, QPainter, QPen, QPixmap
from PyQt5.QtWidgets import (
    QAbstractSpinBox,
    QApplication,
    QCheckBox,
    QComboBox,
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QProgressBar,
    QPushButton,
    QScrollArea,
    QSizePolicy,
    QSlider,
    QSpinBox,
    QSplitter,
    QTabBar,
    QTabWidget,
    QTextEdit,
    QToolButton,
    QVBoxLayout,
    QWidget,
)

try:
    import serial.tools.list_ports  # install as pyserial
except ModuleNotFoundError:
    pass
try:
    import cv2
except ModuleNotFoundError:
    pass
try:
    import numpy as np
except ModuleNotFoundError:
    pass

################################################
# helper code


def get_main_globals():
    """needed if a global is changed in an imported script but meant for the outer most caller. Returns the correct globals()"""
    return sys.modules["__main__"].__dict__


def get_num_required_params(func):
    """Returns number of requried parameters of function."""
    sig = inspect.signature(func)
    return sum(
        1
        for p in sig.parameters.values()
        if p.default is inspect._empty and p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD, p.KEYWORD_ONLY)  # noqa: SLF001
    )


################################################
# launcher code


def Q_start():
    app = QApplication(sys.argv)
    get_main_globals()["app_from_Q_start"] = app
    return app


def Q_end(widget):
    app = get_main_globals()["app_from_Q_start"]
    widget.show()
    sys.exit(app.exec_())


################################################
# code helpers for saveing/loading GUI settings/states


class Q_Settings(QSettings):
    """Child class to QSettings that adds some shorthands for methods and some default args."""

    def __init__(self, parent_class, ini_file_path="GUI_settings.ini"):
        super().__init__(ini_file_path, QSettings.IniFormat)

        self.parent_class = parent_class

        # runs restore_gui_to_startup after child class __init__ to set state with present child widgets:
        QTimer.singleShot(0, self.restore_gui_to_startup)

    def get(self, key):
        return self.value(key)

    def set(self, key, value):
        self.setValue(key, value)

    def reset_gui_startup_setting(self):
        self.beginGroup("gui")
        self.remove("")
        self.endGroup()

    def reset_all_startup_settings(self):
        self.clear()

    def restore_gui_to_startup(self):
        geometry = self.get("gui/geometry")
        state = self.get("gui/state")
        if geometry:
            self.parent_class.restoreGeometry(geometry)
        if state and hasattr(self.parent_class, "restoreState"):
            self.parent_class.restoreState(state)
        for i, widget in enumerate(self.parent_class.findChildren(QSplitter)):
            state = self.get(f"gui/splitter{i}")
            if state:
                widget.restoreState(state)
        for i, widget in enumerate(self.parent_class.findChildren(Q_sidebar)):
            expanded_state = self.get(f"gui/sidebar{i}_expanded")
            if expanded_state is not None:
                widget.set_expanded_state(expanded_state)
                # widget.updateGeometry()

    def set_gui_state_as_startup(self):
        self.set("gui/geometry", self.parent_class.saveGeometry())
        if hasattr(self.parent_class, "saveState"):
            self.set("gui/state", self.parent_class.saveState())
        for i, widget in enumerate(self.parent_class.findChildren(QSplitter)):
            self.set(f"gui/splitter{i}", widget.saveState())
        for i, widget in enumerate(self.parent_class.findChildren(Q_sidebar)):
            self.set(f"gui/sidebar{i}_expanded", widget.isVisible())


################################################
# code interaction with GUI


class Q_add_globals_check:
    def __init__(
        self,
        parent_self,
        label,
        on_change_function,
        start_running=True,
        function_wants_value: None | bool = None,
    ):
        if start_running == True:
            self.running = True
        else:
            self.running = False
        self.label = label
        self.function = on_change_function
        self.parent_self = parent_self
        self.last_seen_value = get_main_globals()[self.label]
        if function_wants_value is None:
            function_wants_value = get_num_required_params(on_change_function) > 0
        self.function_wants_value = function_wants_value

        # add globals check requirements to parent if not already present
        if not hasattr(parent_self, "check_globals_list"):
            # add list of checks to parent if not already
            parent_self.check_globals_list = []

            # global variable change check method
            def _check_globals_change(self):
                if len(self.check_globals_list) == 0:
                    return
                else:
                    for check_globals_object in self.check_globals_list:
                        check_globals_object.check()

            parent_self._check_globals_change = types.MethodType(
                _check_globals_change, parent_self
            )  # extra stuff needed to add method to instance # noqa: SLF001

            parent_self._globals_check_timer = QTimer(parent_self)  # Timer to check globals #noqa: SLF001
            parent_self._globals_check_timer.timeout.connect(parent_self._check_globals_change)  # noqa: SLF001
            parent_self._globals_check_timer.start(100)  # update every 100 ms -> up to 10 fps #noqa: SLF001

        # add check to list
        parent_self.check_globals_list.append(self)

    def check(self):
        if self.running == True:
            value = get_main_globals()[self.label]
            if value != self.last_seen_value:
                self.last_seen_value = value
                if self.function_wants_value == True:
                    self.function(value)
                else:
                    self.function()

    def pause(self):
        self.running = False

    def resume(self):
        self.running = True


def Q_get_current():
    return QApplication.instance()


def Q_print(*args, **kwargs):
    """prints to pyqt5 terminal in current app in addition to normal print"""
    current_app = QApplication.instance()
    if current_app:
        output_terminal = getattr(current_app, "output_terminal", None)
        try:
            output_terminal.log(*args, **kwargs)
        except Exception:
            pass
    sep = kwargs.pop("sep", " ")
    end = kwargs.pop("end", "\n")
    file = kwargs.pop("file", None)
    flush = kwargs.pop("flush", False)
    builtins.print(*args, sep=sep, end=end, file=file, flush=flush)


################################################
# user interaction with GUI


def Q_popup(
    self=None, text="", appearance="info", buttons=None, title=None, wait_for_answer=None, on_click_function=None
):
    msg = QMessageBox()

    if appearance.lower() in ["info", "information"]:
        if buttons is None:
            buttons = ["Ok"]
        if title is None:
            title = "Info"
        if wait_for_answer is None:
            wait_for_answer = False
        msg.setIcon(QMessageBox.Information)
    if appearance.lower() in ["warning"]:
        if buttons is None:
            buttons = ["Ok"]
        if title is None:
            title = "Warning"
        if wait_for_answer is None:
            wait_for_answer = False
        msg.setIcon(QMessageBox.Warning)
    if appearance.lower() in ["critical", "error"]:
        if buttons is None:
            buttons = ["Continue"]
        if title is None:
            title = "Critical"
        if wait_for_answer is None:
            wait_for_answer = True
        msg.setIcon(QMessageBox.Critical)
    if appearance.lower() in ["question", "decision"]:
        if buttons is None:
            buttons = ["Yes", "No"]
        if title is None:
            title = "Question"
        if wait_for_answer is None:
            wait_for_answer = True
        msg.setIcon(QMessageBox.Question)

    msg.setWindowTitle(title)
    msg.setText(text)
    msg.setMinimumSize(800, 300)

    if self is not None:
        if hasattr(self, "_message_boxes"):
            self._message_boxes.append(msg)
        else:
            self._message_boxes = [msg]

    buttons_dict = {}
    for name in buttons:
        btn = msg.addButton(name, QMessageBox.AcceptRole)  # or RejectRole etc.
        buttons_dict[btn] = name

    if wait_for_answer == True:
        msg.exec_()
        if on_click_function is None:
            return buttons_dict[msg.clickedButton()]
        else:
            return on_click_function(buttons_dict[msg.clickedButton()])
    else:
        if on_click_function is not None:
            msg.buttonClicked.connect(on_click_function)
        msg.show()
        return msg


################################################
# Q element generator


def Q_splitter_vertical():
    splitter = QSplitter(Qt.Vertical)
    # splitter.setStyleSheet("""
    #     QSplitter::handle {
    #         background-color: #d0d0d0;
    #         height: 3px;
    #     }
    #     QSplitter::handle:hover {
    #         background-color: #a0a0a0;
    #     }
    # """)
    return splitter


def Q_splitter_horizontal():
    splitter = QSplitter(Qt.Horizontal)
    # splitter.setStyleSheet("""
    #     QSplitter::handle {
    #         background-color: #d0d0d0;
    #         width: 3px;
    #     }
    #     QSplitter::handle:hover {
    #         background-color: #a0a0a0;
    #     }
    # """)
    return splitter


def Q_horizontal_line(height_pxl=2):
    line = QFrame()
    line.setFrameShape(QFrame.HLine)
    line.setFrameShadow(QFrame.Sunken)
    line.setFixedHeight(height_pxl)  # line size
    # so no change in space taken:
    line.setMaximumHeight(line.sizeHint().height())
    return line


def Q_vertical_line(width_pxl=2):
    line = QFrame()
    line.setFrameShape(QFrame.WLine)
    line.setFrameShadow(QFrame.Sunken)
    line.setFixedWidth(width_pxl)  # line size
    # so no change in space taken:
    line.setMaximumHeight(line.sizeHint().height())
    return line


################################
# threading related


class _Q_worker_loop(QObject):
    """looped_function takes as input what was sent to the thread and sends out the output of the function if that is not None"""

    data_out_signal = pyqtSignal(
        object
    )  # define here as a function of the class in order to call its method connect later and not in init

    def __init__(self, looped_function):
        super().__init__()
        self.looped_function = looped_function
        self.exit_signal = False
        self.paused = False
        self.received_data = None

    @pyqtSlot(object)  # Other thread → this thread
    def send_to_thread(self, data):
        """used for other threads to send data to this thread"""
        self.received_data = data  # Store latest received message

    def run(self):
        """start main loop"""
        while True:
            if self.exit_signal == True:
                return
            elif self.paused == True:
                time.sleep(0.1)
            else:
                if self.looped_function.__code__.co_argcount == 0:
                    output = self.looped_function()
                else:
                    output = self.looped_function(self.received_data)
                if output is not None:
                    self.data_out_signal.emit(output)


class Q_thread_single(QObject):
    _data_out = pyqtSignal(object)

    def __init__(self, parent_self, function, connected_function, *args):
        super().__init__()
        self._function = function
        self._connected_function = connected_function
        self._args = args

        self._thread = QThread()
        self.moveToThread(self._thread)
        self._data_out.connect(self._connected_function)
        self._thread.started.connect(self._run)
        self._thread.finished.connect(self.deleteLater)
        self._thread.start()
        # not thread safe probably actually:
        if hasattr(parent_self, "_single_execution_threads"):
            parent_self._single_execution_threads.append(self)  # noqa: SLF001
        else:
            parent_self._single_execution_threads = [self]  # noqa: SLF001

    def _run(self):
        result = self._function(*self._args)
        self._data_out.emit(result)
        self._thread.quit()
        self._thread.wait()


class Q_thread_loop:
    def __init__(self, parent_self=None, looped_function=None, on_output_ready_function=None, start_running=True):
        self._thread = QThread()
        self._worker = _Q_worker_loop(looped_function=looped_function)
        self._worker.moveToThread(self._thread)
        if on_output_ready_function is not None:
            self._worker.data_out_signal.connect(on_output_ready_function)
        self._thread.started.connect(self._worker.run)
        if start_running == True:
            self._worker.paused = False
        else:
            self._worker.paused = True
        self._thread.start()

        if parent_self is not None:
            parent_self.threads.append(self)

    def set_running_state(self, running_state):
        if running_state == True:
            self._worker.paused = False
        else:
            self._worker.paused = True

    def get_running_state(self):
        return not self._worker.paused

    def start(self):
        self._worker.paused = False

    def pause(self):
        self._worker.paused = True

    def send(self, data):
        self._worker.send_to_thread(data)

    def quit(self):
        self._worker.exit_signal = True
        self._thread.quit()
        self._thread.wait()


################################
# standardized custom Q class replacements


# helper to handle label positioning
def Q_handle_label_positioning(self, label="", label_pos="left", moveable=False, align=None):
    layout = QVBoxLayout()
    layout.setContentsMargins(0, 0, 0, 0)
    if label in ["", None]:
        layout.addWidget(self.widget)
    else:
        if isinstance(label, str):
            self.label = QLabel(label)
            label = self.label
        if label_pos == "top":
            layout.addWidget(label)
        if label_pos in ["left", "right"]:
            if moveable == True:
                widget_line = QSplitter(Qt.Horizontal)
            else:
                widget_line = QHBoxLayout()
                if align is None:
                    self.widget.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
                if align == "right":
                    widget_line.addStretch()
            if label_pos == "left":
                widget_line.addWidget(label)
                widget_line.addWidget(self.widget)
            else:
                widget_line.addWidget(self.widget)
                widget_line.addWidget(label)
            if moveable == True:
                layout.addWidget(widget_line)
            else:
                if align == "left":
                    widget_line.addStretch()
                layout.addLayout(widget_line)
        else:
            layout.addWidget(self.widget)
        if label_pos == "bottom":
            layout.addWidget(label)
    self.setLayout(layout)


def Q_block_trigger_decorator(method):
    @wraps(method)
    def wrapper(self, *args, **kwargs):
        blocker = QSignalBlocker(self.widget)
        try:
            return method(self, *args, **kwargs)
        finally:
            del blocker  # ensures unblocking even on exception

    return wrapper


class _Q_class_helper(QWidget):
    def __init__(self, remember=True):
        super().__init__()
        self.remember = remember

    def set_state(self, state):
        if self.remember == True:
            self.set(state)

    def get_state(self):
        if self.remember == True:
            return self.get()
        else:
            return None

    def set_and_trigger(self, value):
        self.set(value)
        self.trigger()

    def trigger(self):
        self.trigger_function(self.get())


class Q_colored_pbar(QWidget):
    def __init__(self, label_text="", unit="", min_val=0, max_val=100, label=True, label_right=True):
        super().__init__()

        self.min_val = min_val
        self.max_val = max_val
        self.label = label
        self.progress = QProgressBar()
        self.progress.setRange(min_val, max_val)
        self.progress.setValue(0)
        self.progress.setTextVisible(False)  # hide default text inside bar

        layout = QHBoxLayout()
        if label == True:
            self.label_text = label_text
            self.unit = unit
            self.label = QLabel(f"{label_text} {unit}")
            if label_right == True:
                layout.addWidget(self.progress)
                layout.addWidget(self.label)
            else:
                layout.addWidget(self.label)
                layout.addWidget(self.progress)
        else:
            layout.addWidget(self.progress)
        self.setLayout(layout)

    def set(self, value):
        value = round(float(value))
        self.progress.setValue(value)
        if self.label == True:
            self.label.setText(f"{self.label_text}{value}{self.unit}")
        self._update_color()

    def get(self):
        return self.progress.value()

    def _jet_colormap(self, frac: float) -> QColor:
        """Return QColor from 0..1 using jet colormap"""
        if frac < 0:
            frac = 0
        if frac > 1:
            frac = 1

        if frac < 0.25:  # blue → cyan
            r = 0
            g = int(4 * frac * 255)
            b = 255
        elif frac < 0.5:  # cyan → green
            r = 0
            g = 255
            b = int((1 - 4 * (frac - 0.25)) * 255)
        elif frac < 0.75:  # green → yellow
            r = int(4 * (frac - 0.5) * 255)
            g = 255
            b = 0
        else:  # yellow → red
            r = 255
            g = int((1 - 4 * (frac - 0.75)) * 255)
            b = 0

        return QColor(r, g, b)

    def _update_color(self):
        frac = (self.get() - self.min_val) / max(1, self.max_val - self.min_val)
        color = self._jet_colormap(frac)

        self.setStyleSheet(f"""
            QProgressBar {{
                border: 1px solid grey;
                border-radius: 3px;
                text-align: center;
            }}
            QProgressBar::chunk {{
                background-color: {color.name()};
            }}
        """)


class _helper_Q_selector_int(QSpinBox):
    def __init__(self):
        super().__init__()

        self.setKeyboardTracking(False)  # commit on Enter/focus-out
        self.setCorrectionMode(QAbstractSpinBox.CorrectToNearestValue)
        self.lineEdit().setAlignment(Qt.AlignRight)
        self.editingFinished.connect(self._snap_and_to_end)

        self.lineEdit().setAlignment(Qt.AlignRight)
        self.editingFinished.connect(lambda: QTimer.singleShot(0, self._to_end))

    def _snap_and_to_end(self):
        # clamp to [min,max] if text is outside
        t = self.lineEdit().text()
        try:
            v = int(t)
            if v < self.minimum():
                self.setValue(self.minimum())
            elif v > self.maximum():
                self.setValue(self.maximum())
        except ValueError:
            pass  # let validator/correction handle non-numeric
        self._to_end()

    def stepBy(self, steps):
        super().stepBy(steps)
        self._to_end()

    def _to_end(self):
        le = self.lineEdit()
        QTimer.singleShot(0, lambda: le.setCursorPosition(len(le.text())))

    def focusOutEvent(self, e):
        super().focusOutEvent(e)
        self._snap_and_to_end()

    # block changing of values with scroll wheel
    def wheelEvent(self, event):
        event.ignore()

    def keyPressEvent(self, e):
        if e.key() in (Qt.Key_Return, Qt.Key_Enter):
            self.interpretText()  # commit text → value()
            self._snap_and_to_end()  # clamp and move caret
            # pick ONE action:
            # self.clearFocus()            # just leave the field
            # self.window().close()        # close window
            # QApplication.instance().quit() # exit app
            e.accept()
            return
        super().keyPressEvent(e)


class Q_selector_int(_Q_class_helper):
    """does not select the value when changed and changes the value to max_val/min_val value instead of preventing to enter it. Commits value on change"""

    def __init__(
        self,
        on_change_function_or_global_label=None,
        start_value=0,
        min_val=-(2**31),
        max_val=2**31 - 1,
        step=1,
        label="",
        label_pos="left",
    ):
        super().__init__()
        self.widget = _helper_Q_selector_int()
        self.widget.valueChanged.connect(self.trigger)

        if on_change_function_or_global_label is None:

            def on_change_function_or_global_label(*_, **__):
                return None
        elif isinstance(on_change_function_or_global_label, str):
            self.global_label = on_change_function_or_global_label

            def on_change_function_or_global_label(value):
                get_main_globals()[self.global_label] = value

        self.trigger_function = on_change_function_or_global_label

        Q_handle_label_positioning(self, label, label_pos)

        self.set_maximum(max_val)
        self.set_minimum(min_val)
        self.set(start_value)

        self.widget.setSingleStep(step)
        self.widget.setWrapping(False)
        self.widget.setReadOnly(False)
        self.widget.setKeyboardTracking(False)  # commit on finish
        self.widget.setCorrectionMode(QAbstractSpinBox.CorrectToNearestValue)
        self.widget.lineEdit().installEventFilter(self)

        self.widget.valueChanged.connect(lambda _: QTimer.singleShot(0, self.widget.lineEdit().deselect))

        self.widget.valueChanged.connect(lambda _: self.trigger_function(self.widget.value()))

        self.widget.lineEdit().setValidator(QIntValidator(-2147483648, 2147483647, self.widget))

    def set_maximum(self, value):
        if value is None:
            value = 2**31 - 1
        self.widget.setMaximum(value)

    def set_minimum(self, value):
        if value is None:
            value = -(2**31)
        self.widget.setMinimum(value)

    def get_maximum(self):
        return self.widget.maximum()

    def get_minimum(self):
        return self.widget.minimum()

    @Q_block_trigger_decorator
    def set(self, value):
        self.widget.setValue(value)

    def get(self):
        return self.widget.value()

    def eventFilter(self, obj, event):
        """needed to deselect number when pressing increment buttons"""
        if event.type() in (QEvent.FocusIn, QEvent.MouseButtonPress):
            QTimer.singleShot(0, self.widget.lineEdit().deselect)
        return super().eventFilter(obj, event)


class Q_bulb(QWidget):
    def __init__(self, color="green", on=False, label="", label_pos="left"):
        super().__init__()
        self.widget = QWidget()
        Q_handle_label_positioning(self, label, label_pos)

        self._on = on
        self._color = color
        self.setFixedSize(30, 30)

    def set_state(self, state):
        self._on = state
        self.update()

    def get_state(self):
        return self._on

    def toggle(self):
        self._on = not self._on
        self.update()

    def set_color(self, color):
        color = QColor(color)
        if color.isValid():
            self._color = color
            self.update()

    def get_color(self):
        return self._color

    def _dim_color(self, c: str, sat=0.35, val=0.55) -> QColor:
        c = QColor(c)
        h, s, v, a = c.getHsv()
        if h == -1:
            h = 0
        dc = QColor()
        dc.setHsv(h, int(s * sat), int(v * val), a)
        return dc

    def _bright_color(self, c: str, factor=130) -> QColor:
        # factor > 100 → lighter; try 170-200 for strong glow
        c = QColor(c)
        return QColor(c).lighter(factor)

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        rect = self.rect().adjusted(6, 6, -6, -6)
        r = min(rect.width(), rect.height())
        x = rect.center().x() - r // 2
        y = rect.center().y() - r // 2
        if self._on == True:
            fill = self._bright_color(self._color)
        else:
            fill = self._dim_color(self._color)

        p.setBrush(QBrush(fill))
        p.setPen(QPen(QColor(60, 60, 60), 2))
        p.drawEllipse(x, y, r, r)
        p.end()


class Q_updating_dropdown(QWidget):
    """updates for opening dropdown"""

    def __init__(self, get_list_function, start_value="", on_select_function=None, label="", label_pos="left"):
        super().__init__()

        if on_select_function is None:

            def on_select_function():
                return None

        self.on_select_function = on_select_function
        self.get_list_function = get_list_function

        self.widget = QComboBox()
        self.widget.setEditable(False)
        self.widget.addItem(str(start_value))
        self.widget.currentTextChanged.connect(self.on_select_function)
        self.widget.original_showPopup = self.widget.showPopup
        self.widget.showPopup = self._new_showPopup

        Q_handle_label_positioning(self, label, label_pos)

    def _new_showPopup(self):
        self.widget.clear()
        self.widget.addItems(self.get_list_function())
        self.widget.original_showPopup()

    def trigger(self):
        self.on_select_function(self.get())

    def set(self, value):
        self.widget.blockSignals(True)
        self.widget.setCurrentText(value)
        self.widget.blockSignals(False)

    def get(self):
        return self.widget.currentText()

    def set_and_trigger(self, value):
        self.set(value)
        self.trigger()


class Q_com_port_dropdown(QWidget):
    """updates available com ports for opening dropdown

    WIP:        placeholder_text="Select COM port",

    """

    def __init__(
        self,
        default_port=None,
        on_select_function=None,
        trigger_for_reselection=False,
        label="",
        label_pos="left",
    ):
        super().__init__()

        self.trigger_for_reselection = trigger_for_reselection
        self.last_trigger_value = None

        self.on_select_function = on_select_function

        self.widget = QComboBox()
        self.widget.setEditable(False)

        # self.widget.currentTextChanged.connect(self.on_select_function)

        self.widget.activated[str].connect(self.trigger)

        self.widget.original_showPopup = self.widget.showPopup
        self.widget.showPopup = self._new_showPopup

        # if placeholder_text is not None:
        #     self.widget.setPlaceholderText(placeholder_text)
        self.set(default_port)

        Q_handle_label_positioning(self, label, label_pos)

    def _new_showPopup(self):
        old = self.get()
        self.widget.clear()
        ports_list = [(elem.device, elem.description) for elem in serial.tools.list_ports.comports()]
        self.widget.addItem("No port selected", "")
        for com_port, description in ports_list:
            self.widget.addItem(f"{com_port}: {description}", com_port)
            if old == com_port:
                self.widget.setCurrentIndex(self.widget.count() - 1)
        self.widget.original_showPopup()

    @Q_block_trigger_decorator
    def set(self, value):
        self.widget.clear()
        if value in [None, False, ""]:
            self.widget.addItem("No port selected", "")
        else:
            if re.fullmatch(r"COM[1-9][0-9]*", value):
                ports_list = [(elem.device, elem.description) for elem in serial.tools.list_ports.comports()]
                for com_port, description in ports_list:
                    if value.upper() == com_port:
                        self.widget.addItem(f"{com_port}: {description}", com_port)
                        break
                else:
                    self.widget.addItem(f"{value} port not found", "")
            else:
                self.widget.addItem(value, "")

    def get(self):
        return self.widget.currentData()

    def trigger(self):
        new_value = self.get()
        if self.trigger_for_reselection == False:
            if self.last_trigger_value == new_value:
                return
        self.last_trigger_value = new_value
        self.on_select_function(new_value)

    def set_and_trigger(self, value):
        self.set(value)
        self.trigger()


class Q_slider(QWidget):
    def __init__(
        self,
        min_val=0,
        max_val=100,
        start_val=None,
        on_change_function=None,
        set_to_edge_for_out_of_range_setbox=True,
        allow_scroll=False,
        setbox_pos="top right",
        label="",
        label_pos="top left",
    ):
        super().__init__()

        self.on_change_function = on_change_function
        self.set_to_edge_for_out_of_range_setbox = set_to_edge_for_out_of_range_setbox

        if setbox_pos is None:
            setbox_pos = ""
        if label_pos is None:
            label_pos = ""
        if ("top" in setbox_pos or "bottom" in setbox_pos) and "left" not in setbox_pos and "right" not in setbox_pos:
            setbox_pos += "right"
        if ("top" in label_pos or "bottom" in label_pos) and "left" not in label_pos and "right" not in label_pos:
            label_pos += "left"

        self.min_val = min_val
        self.max_val = max_val

        # slider
        self.slider = QSlider(Qt.Horizontal)
        self.slider.setRange(self.min_val, self.max_val)
        if start_val is not None:
            self.slider.setValue(start_val)
        self.slider.valueChanged.connect(self._on_slider_changed)

        # setbox
        self.setbox = QLineEdit()
        if start_val is not None:
            self.setbox.setText(str(start_val))
        self.setbox.editingFinished.connect(self._on_line_edit_finished)

        # label
        label = QLabel(label)

        # top line
        top_line = QHBoxLayout()
        if "top" in label_pos and "left" in label_pos:
            top_line.addWidget(label)
        if "top" in setbox_pos and "left" in setbox_pos:
            top_line.addWidget(self.setbox)
        if "top" in label_pos and "right" in label_pos:
            top_line.addWidget(label)
        if "top" in setbox_pos and "right" in setbox_pos:
            top_line.addWidget(self.setbox)

        # slider line
        slider_line = QSplitter(Qt.Horizontal)
        if "top" not in label_pos and "bottom" not in label_pos and "left" in label_pos:
            slider_line.addWidget(label)
        if "top" not in setbox_pos and "bottom" not in setbox_pos and "left" in setbox_pos:
            slider_line.addWidget(self.setbox)
        slider_line.addWidget(self.slider)
        if "top" not in label_pos and "bottom" not in label_pos and "right" in label_pos:
            slider_line.addWidget(label)
        if "top" not in setbox_pos and "bottom" not in setbox_pos and "right" in setbox_pos:
            slider_line.addWidget(self.setbox)

        # bottom line
        bottom_line = QHBoxLayout()
        if "bottom" in label_pos and "left" in label_pos:
            bottom_line.addWidget(label)
        if "bottom" in setbox_pos and "left" in setbox_pos:
            bottom_line.addWidget(self.setbox)
        if "bottom" in label_pos and "right" in label_pos:
            bottom_line.addWidget(label)
        if "bottom" in setbox_pos and "right" in setbox_pos:
            bottom_line.addWidget(self.setbox)

        # vertically stack lines
        layout = QVBoxLayout()
        if top_line.count() > 0:
            layout.addLayout(top_line)
        layout.addWidget(slider_line)
        if bottom_line.count() > 0:
            layout.addLayout(bottom_line)
        self.setLayout(layout)

        if allow_scroll == False:

            def wheelEvent(event):
                event.ignore()

            self.slider.wheelEvent = wheelEvent

    def _on_slider_changed(self, value):
        self.setbox.setText(str(value))
        self.on_change_function(value)

    def _on_line_edit_finished(self):
        try:
            val = round(float(self.setbox.text()))
            if self.min_val <= val <= self.max_val:
                self.slider.setValue(val)
            else:
                if self.set_to_edge_for_out_of_range_setbox == True:
                    if val > self.max_val:
                        self.slider.setValue(self.max_val)
                        self.setbox.setText(str(self.max_val))
                    else:
                        self.slider.setValue(self.min_val)
                        self.setbox.setText(str(self.min_val))
                else:
                    # reset to current slider value if out of range
                    self.setbox.setText(str(self.slider.value()))
        except ValueError:
            # reset to current slider value if invalid input
            self.setbox.setText(str(self.slider.value()))


class Q_command_line(QWidget):
    def __init__(
        self, on_enter_function, placeholder_text="", clear_command="clear", output=None, label="", label_pos="left"
    ):
        super().__init__()

        self.clear_command = clear_command
        self.output = output
        self.on_enter_function = on_enter_function

        self.widget = QLineEdit()
        self.widget.history = []
        self.widget.history_index = -1
        self.widget.returnPressed.connect(self._handle_enter)
        self.widget.setPlaceholderText(placeholder_text)
        self.widget.original_keyPressEvent = self.widget.keyPressEvent
        self.widget.keyPressEvent = self.new_keyPressEvent

        Q_handle_label_positioning(self, label, label_pos)

    def _handle_enter(self):
        text = self.widget.text().strip()
        if text:
            self.widget.history.append(text)
            self.widget.history_index = -1
            if text == self.clear_command and self.output is not None:
                self.output.clear()
            else:
                if self.output is not None:
                    self.output.log(text)
                self.on_enter_function(text)
            self.widget.clear()

    def new_keyPressEvent(self, event):
        if event.key() in (Qt.Key_Return, Qt.Key_Enter):
            # Let the base class handle it and emit returnPressed
            self.widget.original_keyPressEvent(event)
            return
        elif event.key() == Qt.Key_Up:
            if self.widget.history:
                if self.widget.history_index == -1:
                    self.widget.history_index = len(self.widget.history)
                if self.widget.history_index > 0:
                    self.widget.history_index -= 1
                    self.widget.setText(self.widget.history[self.widget.history_index])
            return
        elif event.key() == Qt.Key_Down:
            if self.widget.history:
                if self.widget.history_index == -1:
                    # Already on cleared line, do nothing
                    pass
                elif self.widget.history_index < len(self.widget.history) - 1:
                    self.widget.history_index += 1
                    self.widget.setText(self.widget.history[self.widget.history_index])
                else:
                    self.widget.history_index = -1
                    self.widget.clear()
            return
        self.widget.original_keyPressEvent(event)


class Q_output_terminal(QWidget):
    """Meant for output only. Use Q_command_line for input.

    if replace_print==True (default) it will replace the global print funcatin such that all prints land in the terminal. original_print will be available and act as old print.
    """

    # signal for thread safety for external log call
    _append_log_signal = pyqtSignal(str)

    def __init__(self, label="", label_pos="left", copy_prints_to_log=True, max_history=1000):
        super().__init__()

        self.enable_logging = True

        self.widget = QTextEdit()
        self.widget.setReadOnly(True)
        self.widget.setMinimumHeight(20 * 3)

        self.max_history = max_history  # number of lines to keep

        Q_handle_label_positioning(self, label, label_pos)

        # signal for thread safety for external log call
        self._append_log_signal.connect(self._append_log, type=Qt.QueuedConnection)

        if copy_prints_to_log == True:
            try:
                self.original_print = builtins.original_print
            except AttributeError:
                builtins.original_print = builtins.print
                self.original_print = builtins.original_print

            def _print_and_log(*args, **kwargs):
                self.log(*args, *kwargs)
                sep = kwargs.pop("sep", " ")
                end = kwargs.pop("end", "\n")
                file = kwargs.pop("file", None)
                fl = kwargs.pop("flush", False)
                builtins.original_print(*args, sep=sep, end=end, file=file, flush=fl)

            builtins.print = _print_and_log

    def _append_log(self, html):
        # runs on GUI thread
        self.widget.append(html)
        if self.max_history:
            doc = self.widget.document()
            while doc.blockCount() > self.max_history:
                cursor = self.widget.textCursor()
                cursor.movePosition(cursor.Start)
                cursor.select(cursor.LineUnderCursor)
                cursor.removeSelectedText()
                cursor.deleteChar()

    def log(self, *text, sep=" ", end="\n", color=None, bold=False, bg=None, warn=False, flush=None, file=None):  # noqa: ARG002
        """unused flush and file args are for compatibility with print"""
        if self.enable_logging == False:
            return

        text = str(sep).join([str(t) for t in text]) + str(end)

        if warn == True:
            if color is None:
                color = "white"
            if bg is None:
                bg = "red"
            if bold is None:
                bold = True

        lines = text.split("\n")
        for i, line in enumerate(lines):
            if i == len(lines) - 1 and line == "":
                break
            style = ""
            if color:
                style += f"color: {color};"
            if bg:
                style += f"background-color: {bg};"
            html = f"<span style='{style}'>{line}</span>"
            if bold:
                html = f"<b>{html}</b>"

            if i != len(lines) - 1:
                self._append_log_signal.emit(html)
            else:
                self._append_log_signal.emit(html + "<br>")

    def clear(self):
        self.widget.clear()

    def closeEvent(self, event):
        if hasattr(builtins, "original_print"):
            builtins.print = builtins.original_print
        super().closeEvent(event)


class Q_dropdown(QWidget):
    def __init__(self, values=(), on_select_function=None, label="", label_pos="left"):
        super().__init__()

        self.on_select_function = on_select_function

        self.widget = QComboBox()
        self.widget.setEditable(False)
        self.widget.addItems(values)
        self.widget.currentTextChanged.connect(self.on_select_function)

        Q_handle_label_positioning(self, label, label_pos)

    def trigger(self):
        self.on_select_function(self.get())

    @Q_block_trigger_decorator
    def set(self, value):
        self.widget.setCurrentText(value)

    def get(self):
        return self.widget.currentText()

    def set_and_trigger(self, value):
        self.set(value)
        self.trigger()


class Q_button(QWidget):
    def __init__(self, on_click_function, text, label="", label_pos="left"):
        super().__init__()

        self.on_click_function = on_click_function

        self.widget = QPushButton(text)
        # lambda needed becasue pyqt5 passes bool of button to function:
        self.widget.clicked.connect(lambda _: self.on_click_function())

        Q_handle_label_positioning(self, label, label_pos)


class Q_input_line(QWidget):
    def __init__(
        self,
        label="",
        label_pos="left",
        start_text=None,
        placeholder_text="",
        on_enter_function=lambda _: None,
        on_change_function=lambda _: None,
    ):
        super().__init__()

        self.on_enter_function = on_enter_function
        self.on_change_function = on_change_function

        self.widget = QLineEdit()
        self.widget.setPlaceholderText(placeholder_text)
        self.widget.returnPressed.connect(lambda: self.trigger())
        self.widget.textEdited.connect(self.on_change_function)
        if start_text is not None:
            self.set_and_trigger(start_text)

        Q_handle_label_positioning(self, label, label_pos)

    def trigger(self):
        self.on_enter_function(self.get())

    @Q_block_trigger_decorator
    def set(self, value):
        self.widget.setText(value)

    def get(self):
        return self.widget.text()

    def set_and_trigger(self, value):
        self.set(str(value))
        self.trigger()


class Q_checkbox(QWidget):
    def __init__(
        self, on_change_function_or_global_label=None, label="", label_pos="right", align="left", start_value=False
    ):
        super().__init__()
        self.widget = QCheckBox()
        self.widget.stateChanged.connect(self.trigger)

        if on_change_function_or_global_label is None:

            def on_change_function_or_global_label(*_, **__):
                return None
        elif isinstance(on_change_function_or_global_label, str):
            self.global_label = on_change_function_or_global_label

            def on_change_function_or_global_label(value):
                get_main_globals()[self.global_label] = value

            # needed because the globals of this script might not be in the main globals:
            get_main_globals()[self.global_label] = start_value

        self.trigger_function = on_change_function_or_global_label

        Q_handle_label_positioning(self, label, label_pos, align=align)

    @Q_block_trigger_decorator
    def set(self, value):
        self.widget.setChecked(value)

    def get(self):
        return bool(self.widget.isChecked())

    def set_and_trigger(self, value):
        self.set(value)
        self.trigger()

    def trigger(self):
        self.trigger_function(self.get())


class Q_output_line(QWidget):
    def __init__(self, label="", label_pos="left", placeholder_text=""):
        super().__init__()

        self.widget = QLineEdit()
        self.widget.setPlaceholderText(placeholder_text)
        self.widget.setEditable(False)

        Q_handle_label_positioning(self, label, label_pos)


class Q_file_path(QWidget):
    def __init__(
        self, start_value=None, label="Select File", box_pos="bottom", read_only_textbox=False, placeholder_text=""
    ):
        super().__init__()

        self.label = label

        self.widget = QPushButton(label)
        self.widget.clicked.connect(self._on_open_file_path_menu)

        self.path_box = QLineEdit()
        self.path_box.setPlaceholderText(placeholder_text)
        if read_only_textbox:
            self.path_box.setReadOnly(True)

        if start_value is not None:
            self.set(start_value)

        Q_handle_label_positioning(self, label=self.path_box, label_pos=box_pos)

    def _on_open_file_path_menu(self):
        path, _ = QFileDialog.getOpenFileName(self, self.label)
        self.path_box.setText(path)

    def set(self, value):
        self.path_box.setText(str(value))

    def get(self):
        return self.path_box.text()


class Q_folder_path(QWidget):
    def __init__(self, label="Select Folder", box_pos="bottom", read_only_textbox=False, placeholder_text=""):
        super().__init__()

        self.label = label

        self.widget = QPushButton(label)
        self.widget.clicked.connect(self._on_open_path_menu)

        self.path_box = QLineEdit()
        self.path_box.setPlaceholderText(placeholder_text)
        if read_only_textbox:
            self.path_box.setReadOnly(True)

        Q_handle_label_positioning(self, label=self.path_box, label_pos=box_pos)

    def _on_open_path_menu(self):
        path = QFileDialog.getExistingDirectory(self, self.label)
        self.path_box.setText(path)

    def set(self, value):
        self.path_box.setText(value)

    def get(self):
        return self.path_box.text()


################################################
# big special classes


class Q_tabs(QWidget):
    def __init__(
        self,
        title=None,
        icon_path=None,
        tab_widget_class=None,
        moveable=True,
        closeable=True,
        confirm_tab_close=True,
        allow_new_tab=True,
        renamable=True,
        allow_remove_last_tab=True,
    ):
        super().__init__()

        self.allow_remove_last_tab = allow_remove_last_tab
        self.closeable = closeable
        self.confirm_tab_close = confirm_tab_close
        self.tab_widget_class = tab_widget_class
        self.title = title

        self.set_title(title)
        self.set_icon(icon_path)

        layout = QVBoxLayout(self)
        self.tabs = QTabWidget()
        self.tabs.setMovable(moveable)
        self.tabs.setStyleSheet("""
            QTabBar::tab {
                qproperty-alignment: AlignCenter;  /* centers text */
                padding: 2px 3px;
                margin: 2px;
                min-width: 10px;
                background: lightgray;     /* inactive tabs */
                color: black;
                border-top-left-radius: 3px;
                border-top-right-radius: 3px;
            }

            QTabBar::tab:selected {
                background: dimgray;         /* active tab */
                color: white;              /* invert text color */
            }

            /* Keep the red X prominent */
            QPushButton {
                color: red;
                font-weight: bold;
                font-size: 16px;
                border: none;
            }
        """)
        layout.addWidget(self.tabs)

        # State for renaming
        self._editor = None
        self._rename_index = None
        if renamable == True:
            # Signals
            self.tabs.tabBarDoubleClicked.connect(self._start_rename)
            # Event filter for all clicks and key events
            self.installEventFilter(self)

        # Add "+" button
        if allow_new_tab == True:
            self.add_tab_button = QToolButton()
            self.add_tab_button.setText("+")
            self.add_tab_button.setAutoRaise(True)
            font = QFont()
            font.setPointSize(14)
            font.setBold(True)
            self.add_tab_button.setFont(font)
            self.add_tab_button.setStyleSheet("color: green;")
            self.add_tab_button.clicked.connect(self.add_tab)
            self.tabs.setCornerWidget(self.add_tab_button, Qt.TopRightCorner)

        self.tabs.currentChanged.connect(self._update_close_buttons)

        self.placeholder = None
        self.tabs.tabBar().tabBarClicked.connect(self._on_tab_click)

        # Start with one tab
        self.add_tab()

    def set_title(self, title):
        self.title = title
        self.setWindowTitle(title)

    def set_icon(self, icon_path):
        self.icon_path = icon_path
        if icon_path is not None:
            self.setWindowIcon(QIcon(icon_path))

    def add_tab(self, *_, widget_class=None, title="New Tab"):
        if widget_class is None:
            if self.tab_widget_class is None:
                widget = QLabel("No content")
            else:
                widget = self.tab_widget_class()
        else:
            widget = widget_class()

        index = self.tabs.addTab(widget, title)
        self.set_current_index(index)
        if self.closeable == True:
            self._update_close_buttons()

        if self.tabs.indexOf(self.placeholder) != -1:
            self.tabs.removeTab(self.tabs.indexOf(self.placeholder))

        return index

    def set_current_index(self, index):
        self.tabs.setCurrentIndex(index)

    def get_current_index(self):
        return self.tabs.currentIndex()

    def set_tab_widget(self, widget: QWidget, index=None):
        # Get the existing tab widget
        if index is None:
            index = self.get_current_index()
        tab = self.tabs.widget(index)
        # Remove all old widgets from the layout
        layout = tab.layout()
        if layout is None:
            layout = QVBoxLayout(tab)
            tab.setLayout(layout)
        else:
            while layout.count():
                child = layout.takeAt(0)
                if child.widget():
                    child.widget().setParent(None)

        # Add the new widget
        layout.addWidget(widget)

    def close_tab(self, index=None):
        if index is None:
            index = self.get_current_index()
        if self.tabs.count() == 1:
            if self.confirm_tab_close:
                answer = Q_popup(
                    self,
                    appearance="question",
                    title="Confirm Tab Close",
                    text="Are you sure you want to close this tab?",
                    buttons=["Yes", "No"],
                )
                if answer == "No":
                    return
            self._add_placeholder_tab()
            self.tabs.removeTab(index)
        else:
            if self.confirm_tab_close:
                answer = Q_popup(
                    self,
                    appearance="question",
                    title="Confirm Tab Close",
                    text="Are you sure you want to close this tab?",
                    buttons=["Yes", "No"],
                )
                if answer == "No":
                    return
            self.tabs.removeTab(index)
            if self.closeable == True:
                self._update_close_buttons()

    def eventFilter(self, obj, event):
        # ESC in editor
        if self._editor and obj is self._editor and event.type() == QEvent.KeyPress:
            if event.key() == Qt.Key_Escape:
                self._cancel_rename()
                return True

        # Click anywhere outside editor
        if self._editor and event.type() == QEvent.MouseButtonPress:
            if not self._editor.geometry().contains(self._editor.mapFromGlobal(event.globalPos())):
                self._commit_rename()

        return super().eventFilter(obj, event)

    def _on_tab_click(self, index):
        if index == self.tabs.indexOf(self.placeholder):
            self.add_tab()

    def _add_placeholder_tab(self):
        self.placeholder = QPushButton()
        self.placeholder.clicked.connect(self.add_tab)
        placeholder_layout = QVBoxLayout()
        placeholder_layout.addWidget(QLabel("Click to add tab"))
        self.placeholder.setLayout(placeholder_layout)
        self.tabs.addTab(self.placeholder, "+")

    def _add_close_button(self, index):
        if self.tabs.count() > 1 or self.allow_remove_last_tab == True:
            btn = QPushButton("x")
            btn.setFixedSize(15, 15)
            # Make it bold, red, and bigger
            btn.setStyleSheet("""
                color: red;
                font-weight: bold;
                font-size: 16px;
                border: none;
            """)
            btn.clicked.connect(lambda _, i=index: self.close_tab(i))
            self.tabs.tabBar().setTabButton(index, QTabBar.RightSide, btn)

    def _remove_close_button(self, index):
        self.tabs.tabBar().setTabButton(index, QTabBar.RightSide, None)

    def _update_close_buttons(self):
        for i in range(self.tabs.count()):
            if i == self.tabs.currentIndex():
                if i != self.tabs.indexOf(self.placeholder):
                    self._add_close_button(i)
            else:
                self._remove_close_button(i)

    def _start_rename(self, index):
        if index < 0:
            return
        if self._editor:
            self._commit_rename()

        rect = self.tabs.tabBar().tabRect(index)
        editor = QLineEdit(self.tabs.tabText(index), self.tabs.tabBar())
        editor.setGeometry(rect)
        editor.setFocus()
        editor.selectAll()
        editor.returnPressed.connect(self._commit_rename)
        editor.installEventFilter(self)

        self._editor = editor
        self._rename_index = index
        editor.show()

    def _commit_rename(self):
        if self._editor and self._rename_index is not None:
            new_name = self._editor.text()
            if new_name:
                self.tabs.setTabText(self._rename_index, new_name)
            self._editor.deleteLater()
        self._editor = None
        self._rename_index = None

    def _cancel_rename(self):
        if self._editor:
            self._editor.deleteLater()
        self._editor = None
        self._rename_index = None


class Q_sidebar(QScrollArea):
    def __init__(self, parent_self, button_label="☰", spacing=4, minimum_width=50):
        super().__init__()

        self._add_line_before_next_add = False

        self.setMinimumWidth(minimum_width)

        self.parent_self = parent_self

        self._widget = QWidget()

        self._layout = QVBoxLayout()
        self._layout.setSpacing(spacing)
        self._layout.setContentsMargins(4, 4, 4, 4)
        self._layout.addStretch(10)
        self._strech_at_end = True

        self._widget.setLayout(self._layout)
        self.setWidget(self._widget)
        self.setWidgetResizable(True)

        # Toggle button
        self.toggle_button = QPushButton(button_label)
        self.toggle_button.setFixedSize(30, 30)
        self.toggle_button.clicked.connect(self.toggle_expanded)

        try:
            self.previous_expanded_width = self.get_expanded_width()
        except:
            self.previous_expanded_width = 200

    @property
    def parent_splitter(self):
        return self.parent_self.frame_horizontal_splitter

    def expand(self):
        if self.is_expanded() == False:
            self.show()

    def collapse(self):
        if self.is_expanded() == True:
            self.hide()

    def set_expanded_state(self, expanded_state):
        if self.is_expanded() != expanded_state:
            self.toggle_expanded()

    def toggle_expanded(self):
        if self.is_expanded():
            self.hide()
        else:
            self.show()

    def is_expanded(self):
        return self.isVisible()

    def set_width(self, width):
        total_frame_width = sum(self.parent_splitter.sizes())
        self.parent_splitter.setSizes([width, max(1, total_frame_width - width)])
        if width > 0:
            self.expand()

    def set_expanded_width(self, width):
        self.set_width(width)

    def get_expanded_width(self):
        return self.parent_splitter.sizes()[0]

    def add_line(self, height=2):
        self._layout.insertWidget(self._layout.count() - self._strech_at_end, Q_horizontal_line(height))

    def add(self, *widgets_or_layouts, line_after=True):
        # add line
        if self._add_line_before_next_add:
            self.add_line()
        # add elements
        for elem in widgets_or_layouts:
            if isinstance(elem, QWidget):
                if isinstance(elem, Q_output_terminal):
                    stretch = self._layout.takeAt(self._layout.count() - 1)
                    del stretch
                    self._strech_at_end = False
                else:
                    elem.setMaximumHeight(elem.sizeHint().height())
                self._layout.insertWidget(self._layout.count() - self._strech_at_end, elem)
            elif isinstance(elem, (QHBoxLayout, QVBoxLayout)):
                elem.setMaximumHeight(elem.sizeHint().height())
                self._layout.insertLayout(self._layout.count() - self._strech_at_end, elem)
        # add line on next add
        self._add_line_before_next_add = line_after



class Q_GUI_backend(QWidget):
    """Intended as a parent class for any GUI that has a sidebar.

    Needed in child class:
        Run "super().__init__()" in start of __init__.

        If you define your own closeEvent(self,event) than add "super().closeEvent(event)" at end

        change bulb color or on state by changing the global vars bulb_on and bulb_color

        TODO: Add settings as self.settings.add(~Widget~/~Layout~)

        check:main_box = Q_splitter_vertical()  # allows user to change size between elements

        # mention Q_add_globals_check

    """

    def __init__(
        self,
        title: str = "",
        icon_path: str | None = None,
        ask_confirm_closing: bool = False,
        hide_title_bar: bool = False,
        on_close_function: Callable | None = None,
        settings_file_path: str = "GUI_settings.ini",
    ):
        super().__init__()

        ############################################
        # handle args

        self.ask_confirm_closing = ask_confirm_closing
        if on_close_function is None:
            self.on_close_function = lambda: None
        else:
            self.on_close_function = on_close_function
        self.set_title(title)
        self.set_icon(icon_path)
        if hide_title_bar == True:
            self.setWindowFlags(Qt.FramelessWindowHint | Qt.Window)

        ############################################
        # setup settings file loading/saving

        self.settings = Q_Settings(self, settings_file_path)

    ########################################
    # general methods:

    def log(self, *text, sep=" ", end="\n"):
        if hasattr(self, "output_terminal"):
            self.output_terminal.log(*text, sep=sep, end=end)
        else:
            print(*text, sep=sep, end=end)

    def set_size(self, width, height):
        self.resize(int(width), int(height))

    def set_position(self, x, y):
        self.move(int(x), int(y))

    def set_title(self, title=""):
        self.setWindowTitle(title)

    def set_icon(self, icon_path):
        self.icon_path = icon_path
        if icon_path is not None:
            self.setWindowIcon(QIcon(icon_path))

    #######################################
    # Q event handler replacement (needs specific names)

    def _helper_closeEvent(self):
        """Saves gui sate to next startup. Execute on_close_function. Closes threads in self.threads"""
        self.settings.set_gui_state_as_startup()

        self.on_close_function()

        if hasattr(self, "threads"):
            for thread in self.threads:
                try:
                    thread.quit()
                except Exception:
                    pass

    def closeEvent(self, event):  # type:ignore
        # Optional: ask for confirmation
        if self.ask_confirm_closing == True:
            reply = QMessageBox.question(
                self, "Confirm Exit", "Are you sure you want to quit?", QMessageBox.Yes | QMessageBox.No, QMessageBox.No
            )
            if reply == QMessageBox.Yes:
                self._helper_closeEvent()
                event.accept()  # Close the window
            else:
                event.ignore()  # Ignore the close
        else:
            self._helper_closeEvent()
            event.accept()  # Close the window


class Q_sidebar_GUI(Q_GUI_backend):
    """Intended as a parent class for any GUI that has a sidebar.

    Needed in child class:
        Run "super().__init__()" in start of __init__.

        If you define your own closeEvent(self,event) than add "super().closeEvent(event)" at end

        change bulb color or on state by changing the global vars bulb_on and bulb_color

        TODO: Add settings as self.settings.add(~Widget~/~Layout~)

        check:main_box = Q_splitter_vertical()  # allows user to change size between elements

        # mention Q_add_globals_check

    """

    def __init__(
        self,
        widget: QWidget | None = None,
        title: str = "",
        icon_path: str | None = None,
        ask_confirm_closing: bool = False,
        hide_title_bar: bool = False,
        on_close_function: Callable | None = None,
        add_bulb: bool = True,
        settings_file_path: str = "GUI_settings.ini",
    ):
        super().__init__(
            title=title,
            icon_path=icon_path,
            ask_confirm_closing=ask_confirm_closing,
            hide_title_bar=hide_title_bar,
            on_close_function=on_close_function,
            settings_file_path=settings_file_path,
        )
        ############################################
        # handle args

        if widget is None:
            self._widget = QLabel("Placeholder: Define widget...")
        else:
            self._widget = widget

        ############################################
        # Layout init
        ############################################

        # sidebar
        self.sidebar = Q_sidebar(self)
        if add_bulb == True:
            self.bulb = Q_bulb()
            get_main_globals()["bulb_on"] = self.bulb.get_state()
            get_main_globals()["bulb_color"] = self.bulb.get_color()
            Q_add_globals_check(self, "bulb_on", self.bulb.set_state)
            Q_add_globals_check(self, "bulb_color", self.bulb.set_color)

        # Horizontal splitter for sidebar and main box (right side)
        self.sidebar_main_splitter = Q_splitter_horizontal()
        self.sidebar_main_splitter.addWidget(self.sidebar)
        self.sidebar_main_splitter.addWidget(self._widget)  # widget is at index 1 of sidebar_main_splitter
        self._widget_index = 1
        self.sidebar_main_splitter.setStretchFactor(0, 1)
        self.sidebar_main_splitter.setStretchFactor(1, 4)
        self.sidebar_main_splitter.setStretchFactor(2, 3)

        # to avoid manual scroll collapse:
        self.sidebar_main_splitter.setChildrenCollapsible(False)

        # frame layout for proper display
        frame_layout = QHBoxLayout()
        frame_layout.addWidget(self.sidebar_main_splitter)
        self.setLayout(frame_layout)

    def replace_widget(self, widget: QWidget):
        # replace widget
        self.sidebar_main_splitter.replaceWidget(self._widget_index, widget)
        # Clean up the old widget memory
        self._widget.deleteLater()
        # Update the variable so 'self._widget' points to the new one
        self._widget = widget

    def get_widget(self):
        return self._widget


class Q_image_GUI(Q_sidebar_GUI):
    """Intended as a parent class for an image GUI with settings sidebar.

    Needed in child class:
        Run "super().__init__()" in start of __init__.
        Define get_image method.
        If you define your own closeEvent(self,event) than add "super().closeEvent(event)" at end

        change bulb color or on state by changing the global vars bulb_on and bulb_color
    """

    def __init__(
        self,
        title="",
        icon_path=None,
        ask_confirm_closing=False,
        hide_title_bar=False,
        on_close_function=None,
        add_bulb=True,
        settings_file_path="GUI_settings.ini",
    ):
        super().__init__(
            title=title,
            icon_path=icon_path,
            ask_confirm_closing=ask_confirm_closing,
            hide_title_bar=hide_title_bar,
            add_bulb=add_bulb,
            on_close_function=on_close_function,
            settings_file_path=settings_file_path,
        )

        ############################################
        # init attributes

        self.current_image = None
        self.zoom = 1

        ############################################
        # Timer to update image

        self._image_update_timer = QTimer()
        self._image_update_timer.timeout.connect(self.update_image)
        self._image_update_timer.start(10)  # update every 10 ms -> up to 100 fps

        ############################################
        # layout setup

        self.image = QLabel()
        self.image.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Ignored)
        self.image.setAlignment(Qt.AlignCenter)
        self.image.resizeEvent = self._on_window_resize

        self.top_line = QLabel("My Image Title")
        self.top_line.setAlignment(Qt.AlignCenter)
        self.top_line.setStyleSheet("font-weight: bold; font-size: 20px;")
        self.top_line.setSizePolicy(self.top_line.sizePolicy().horizontalPolicy(), QSizePolicy.Fixed)

        def top_line_get():
            return self.top_line.text()

        self.top_line.get = top_line_get

        def top_line_set(text):
            self.top_line.setText(text)

        self.top_line.set = top_line_set
        self.top_line_layout = QHBoxLayout()
        self.top_line_layout.addWidget(self.sidebar.toggle_button)
        self.top_line_layout.addWidget(self.top_line)

        self.bottom_line = QLabel("")
        self.bottom_line.setAlignment(Qt.AlignCenter)
        self.bottom_line.setStyleSheet("font-weight: bold; font-size: 20px;")

        def bottom_line_get():
            return self.bottom_line.text()

        self.bottom_line.get = bottom_line_get

        def bottom_line_set(text):
            self.bottom_line.setText(text)

        self.bottom_line.set = bottom_line_set
        self.bottom_line_layout = QHBoxLayout()
        self.bottom_line_layout.addWidget(self.bottom_line)
        # self.bottom_line_layout.addStretch()
        self.reset_settings_button = Q_button(self.reset_startup_settings, "Reset Settings")
        self.reset_settings_button.setSizePolicy(QSizePolicy.Fixed, QSizePolicy.Fixed)
        self.bottom_line_layout.addWidget(self.reset_settings_button)
        if add_bulb == True:
            self.bottom_line_layout.addWidget(self.bulb)

        image_box = QWidget()
        image_box_layout = QVBoxLayout(image_box)
        image_box_layout.addLayout(self.top_line_layout)
        image_box_layout.addWidget(self.image)
        image_box_layout.addLayout(self.bottom_line_layout)

        main_box = Q_splitter_vertical()  # allows user to change size between elements
        main_box.addWidget(image_box)

        self.set_widget(main_box)
        self.sidebar_main_splitter.addWidget(main_box)

    ########################################
    # general methods:
    ########################################

    def update_image(self):
        try:
            self.current_image = self.get_image()
            self._repaint_image()
        except Exception as e:
            self.log("--------------------")
            self.log(f"[ERROR START] {e}:")
            self.log(traceback.format_exc())
            self.log(f"[ERROR END] {e}:")
            self.log("--------------------")

    def get_image(self):
        """fallback warning mehtod"""
        warn_frame = np.zeros((480, 640, 3), dtype=np.uint8)
        text = "No get_image method defined"
        font = cv2.FONT_HERSHEY_SIMPLEX
        scale = 1.4
        th = 3
        color = (255, 255, 255)
        (text_w, text_h), _baseline = cv2.getTextSize(text, font, scale, th)
        x = (warn_frame.shape[1] - text_w) // 2
        y = (warn_frame.shape[0] + text_h) // 2
        cv2.putText(warn_frame, text, (x, y), font, scale, color, th, cv2.LINE_AA)
        return warn_frame

    def set_zoom(self, value):
        self.zoom = value

    #######################################
    # helpers

    def _on_window_resize(self, event):
        self._repaint_image()
        event.accept()  # mark event as handled

    def _repaint_image(self):
        if self.current_image is None:
            return

        rgb_image = cv2.cvtColor(self.current_image, cv2.COLOR_BGR2RGB)
        h, w, ch = rgb_image.shape
        bytes_per_line = ch * w
        qt_image = QImage(rgb_image.data, w, h, bytes_per_line, QImage.Format_RGB888)

        pixmap = QPixmap.fromImage(qt_image)

        # Scale pixmap to label size, keeping aspect ratio
        scaled_pixmap = pixmap.scaled(self.image.size(), Qt.KeepAspectRatio, Qt.SmoothTransformation)
        self.image.setPixmap(scaled_pixmap)

    def _on_window_resize2(self, event):
        self._repaint_image2()
        event.accept()  # mark event as handled

    def _repaint_image2(self):
        if self.current_image is None:
            return

        rgb_image = cv2.cvtColor(self.current_image, cv2.COLOR_BGR2RGB)
        h, w, ch = rgb_image.shape
        bytes_per_line = ch * w
        qt_image = QImage(rgb_image.data, w, h, bytes_per_line, QImage.Format_RGB888)

        pixmap = QPixmap.fromImage(qt_image)

        # Scale pixmap to label size, keeping aspect ratio
        scaled_pixmap = pixmap.scaled(self.image2.size(), Qt.KeepAspectRatio, Qt.SmoothTransformation)
        self.image2.setPixmap(scaled_pixmap)

from PyQt5.QtCore import Qt, QPropertyAnimation, pyqtProperty
from PyQt5.QtWidgets import QApplication, QWidget, QPushButton, QHBoxLayout, QVBoxLayout, QLabel
from PyQt5.QtWidgets import (
    QApplication, QWidget, QLabel, QPushButton, QVBoxLayout, QHBoxLayout,
    QComboBox, QFileDialog, QTextEdit, QCheckBox, QSizePolicy, QSplitter,
    QSlider, QLineEdit, QRadioButton, QButtonGroup, QFrame, QProgressBar,
    QScrollArea, QTabWidget, QMessageBox, QTabBar, QToolButton,
)
from PyQt5.QtGui import QImage, QPixmap, QIcon, QFont
from PyQt5.QtCore import Qt, QTimer, QObject, QThread, pyqtSignal, pyqtSlot, QEvent

import cv2
import numpy as np
import traceback
import serial.tools.list_ports
import sys
import time

################################################


def get_available_com_ports_tuple() -> list[str]:
    return [(elem.device, elem.description) for elem in serial.tools.list_ports.comports()]  # nopep8 #type:ignore


def get_frame():
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    cv2.putText(frame, "Aspect Ratio Preserved", (50, 240),
                cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
    return frame


def Q_splitter_vertical(): return QSplitter(Qt.Vertical)
def Q_splitter_horizontal(): return QSplitter(Qt.Horizontal)


def Q_popup(self=None, text="", appearance="info", buttons=None, title=None, wait_for_answer=None, on_click_function=None):

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


class Q_tabs(QWidget):
    def __init__(self, tab_widget_class=None, moveable=True, closeable=True, allow_new_tab=True, renamable=True, allow_remove_last_tab=True):
        super().__init__()

        self.allow_remove_last_tab = allow_remove_last_tab
        self.closeable = closeable
        self.tab_widget_class = tab_widget_class

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
        if len(self.tabs) == 1:
            self._add_placeholder_tab()
            self.tabs.removeTab(index)
        else:
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
        if len(self.tabs) > 1 or self.allow_remove_last_tab == True:
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


def Q_horizontal_line(height_pxl=2):
    line = QFrame()
    line.setFrameShape(QFrame.HLine)
    line.setFrameShadow(QFrame.Sunken)
    line.setFixedHeight(height_pxl)
    return line


def Q_vertical_line(width_pxl=2):
    line = QFrame()
    line.setFrameShape(QFrame.WLine)
    line.setFrameShadow(QFrame.Sunken)
    line.setFixedWidth(width_pxl)
    return line


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
                    self.widget.setSizePolicy(
                        QSizePolicy.Expanding, QSizePolicy.Expanding)
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
            parent_self._single_execution_threads.append(self)
        else:
            parent_self._single_execution_threads = [self]

    def _run(self):
        result = self._function(*self._args)
        self._data_out.emit(result)
        self._thread.quit()
        self._thread.wait()


class helper_Q_worker_loop(QObject):
    """looped_function takes as input what was sent to the thread and sends out the output of the function if that is not None
    """
    data_out_signal = pyqtSignal(
        object)  # define here as a function of the class in order to call its method connect later and not in init

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
                output = self.looped_function(self.received_data)
                if output != None:
                    self.data_out_signal.emit(output)


class Q_thread_loop:
    def __init__(self, looped_function, connected_function, start_running=True):
        self._thread = QThread()
        self._worker = helper_Q_worker_loop(looped_function=looped_function)
        self._worker.moveToThread(self._thread)
        self._worker.data_out_signal.connect(connected_function)
        self._thread.started.connect(self._worker.run)
        if start_running == True:
            self._worker.paused = False
        else:
            self._worker.paused = True
        self._thread.start()

    def resume(self):
        self._worker.paused = False

    def pause(self):
        self._worker.paused = True

    def send(self, data):
        self._worker.send_to_thread(data)

    def quit(self):
        self._worker.exit_signal = True
        self._thread.quit()
        self._thread.wait()


class Q_colored_pbar(QWidget):
    def __init__(self, label_text="", unit="", min_val=0, max_val=100, label=True, label_right=True):
        super().__init__()

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

    def set_value(self, value):
        self.progress.setValue(value)
        if self.label == True:
            self.label.setText(f"{self.label_text}{value}{self.unit}")

        # Change color based on value
        if value < 25:
            color = "green"
        elif value < 50:
            color = "yellow"
        elif value < 75:
            color = "orange"
        elif value < 100:
            color = "red"
        else:
            color = "magenta"

        self.progress.setStyleSheet(f"""
            QProgressBar {{
                border: 1px solid gray;
                border-radius: 3px;
            }}
            QProgressBar::chunk {{
                background-color: {color};
            }}
        """)


class Q_updating_dropdown(QWidget):
    """updates for opening dropdown"""

    def __init__(self, get_list_function, start_value="", on_select_function=None, label="", label_pos="left"):
        super().__init__()

        self.on_select_function = on_select_function
        self.get_list_function = get_list_function

        self.widget = QComboBox()
        self.widget.setEditable(False)
        self.widget.addItem(str(start_value))
        self.widget.currentTextChanged.connect(self.on_select_function)
        self.widget.original_showPopup = self.widget.showPopup
        self.widget.showPopup = self.new_showPopup

        Q_handle_label_positioning(self, label, label_pos)

    def new_showPopup(self):
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
    """updates available com ports for opening dropdown"""

    def __init__(self, start_value="", on_select_function=None, label="", label_pos="left"):
        super().__init__()

        self.on_select_function = on_select_function

        self.widget = QComboBox()
        self.widget.setEditable(False)
        self.widget.addItem(str(start_value).upper())
        self.widget.currentTextChanged.connect(self.on_select_function)
        self.widget.original_showPopup = self.widget.showPopup
        self.widget.showPopup = self.new_showPopup

        Q_handle_label_positioning(self, label, label_pos)

    def new_showPopup(self):
        self.widget.clear()
        ports_list = get_available_com_ports_tuple()
        for com_port, description in ports_list:
            self.widget.addItem(f"{com_port}: {description}", com_port)
        self.widget.original_showPopup()


class Q_slider(QWidget):
    def __init__(self, min_val=0, max_val=100, start_val=None, on_change_function=None, set_to_edge_for_out_of_range_setbox=True, allow_scroll=False, setbox_pos="top right", label="", label_pos="top left"):
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
        if start_val != None:
            self.slider.setValue(start_val)
        self.slider.valueChanged.connect(self._on_slider_changed)

        # setbox
        self.setbox = QLineEdit()
        if start_val != None:
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
    def __init__(self, on_enter_function, placeholder_text="", clear_command="clear", output=None, label="", label_pos="left"):
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
                    self.widget.setText(
                        self.widget.history[self.widget.history_index])
            return
        elif event.key() == Qt.Key_Down:
            if self.widget.history:
                if self.widget.history_index == -1:
                    # Already on cleared line, do nothing
                    pass
                elif self.widget.history_index < len(self.widget.history) - 1:
                    self.widget.history_index += 1
                    self.widget.setText(
                        self.widget.history[self.widget.history_index])
                else:
                    self.widget.history_index = -1
                    self.widget.clear()
            return
        self.widget.original_keyPressEvent(event)


class Q_terminal(QWidget):
    """Meant for output only. Use Q_command_line for input."""

    def __init__(self, label="", label_pos="left"):
        super().__init__()

        self.widget = QTextEdit()
        self.widget.setReadOnly(True)
        self.widget.setMinimumHeight(20*3)

        Q_handle_label_positioning(self, label, label_pos)

    def log(self, *text, sep=" ", end="\n", color=None, bold=False, bg=None, warn=False):
        text = str(sep).join([str(t) for t in text])+str(end)

        if warn == True:
            if color is None:
                color = "white"
            if bg is None:
                bg = "red"
            if bold is None:
                bold = True

        lines = text.split("\n")

        for i, line in enumerate(lines):
            if i == len(lines)-1 and line == "":
                break
            style = ""
            if color:
                style += f"color: {color};"
            if bg:
                style += f"background-color: {bg};"
            html = f"<span style='{style}'>{line}</span>"
            if bold:
                html = f"<b>{html}</b>"
            if i != len(lines)-1:
                self.widget.insertHtml(html + "<br>")
            else:
                self.widget.insertHtml(html)

    def clear(self):
        self.widget.clear()


class Q_dropdown(QWidget):
    def __init__(self, values=[], on_select_function=None, label="", label_pos="left"):
        super().__init__()

        self.on_select_function = on_select_function

        self.widget = QComboBox()
        self.widget.setEditable(False)
        self.widget.addItems(values)
        self.widget.currentTextChanged.connect(self.on_select_function)

        Q_handle_label_positioning(self, label, label_pos)

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


class Q_button(QWidget):
    def __init__(self, on_click_function, text, label="", label_pos="left"):
        super().__init__()

        self.on_click_function = on_click_function

        self.widget = QPushButton(text)
        self.widget.clicked.connect(self.on_click_function)

        Q_handle_label_positioning(self, label, label_pos)


class Q_input_line(QWidget):
    def __init__(self, label="", label_pos="left", placeholder_text="", on_enter_function=lambda x: None, on_change_function=lambda x: None):
        super().__init__()

        self.on_enter_function = on_enter_function
        self.on_change_function = on_change_function

        self.widget = QLineEdit()
        self.widget.setPlaceholderText(placeholder_text)
        self.widget.returnPressed.connect(
            lambda: self.on_enter_function(self.widget.text()))
        self.widget.textEdited.connect(self.on_change_function)

        Q_handle_label_positioning(self, label, label_pos)

    def trigger(self):
        self.on_enter_function(self.get())

    def set(self, value):
        self.widget.blockSignals(True)
        self.widget.setText(value)
        self.widget.blockSignals(False)

    def get(self):
        return self.widget.text()

    def set_and_trigger(self, value):
        self.set(value)
        self.trigger()


class Q_check_box(QWidget):
    def __init__(self, on_switch_function, label="", label_pos="right", align="left"):
        super().__init__()

        self.on_switch_function = on_switch_function

        self.widget = QCheckBox()
        self.widget.stateChanged.connect(self.on_switch_function)

        Q_handle_label_positioning(self, label, label_pos, align=align)

    def trigger(self):
        self.on_switch_function(self.get())

    def set(self, value):
        self.widget.blockSignals(True)
        self.widget.setChecked(value)
        self.widget.blockSignals(False)

    def get(self):
        return self.widget.isChecked()

    def set_and_trigger(self, value):
        self.set(value)
        self.trigger()


class Q_output_line(QWidget):
    def __init__(self, label="", label_pos="left", placeholder_text=""):
        super().__init__()

        self.widget = QLineEdit()
        self.widget.setPlaceholderText(placeholder_text)
        self.widget.setEditable(False)

        Q_handle_label_positioning(self, label, label_pos)


class Q_file_path(QWidget):

    def __init__(self, label="Select File", box_pos="bottom", read_only_textbox=False, placeholder_text=""):
        super().__init__()

        self.label = label

        self.widget = QPushButton(label)
        self.widget.clicked.connect(self._on_open_file_path_menu)

        self.path_box = QLineEdit()
        self.path_box.setPlaceholderText(placeholder_text)
        if read_only_textbox:
            self.path_box.setReadOnly(True)

        Q_handle_label_positioning(
            self, label=self.path_box, label_pos=box_pos)

    def _on_open_file_path_menu(self):
        path, _ = QFileDialog.getOpenFileName(self, self.label)
        self.path_box.setText(path)

    def set(self, value):
        self.path_box.setText(value)

    def get(self, value):
        self.path_box.text()


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

        Q_handle_label_positioning(
            self, label=self.path_box, label_pos=box_pos)

    def _on_open_path_menu(self):
        path = QFileDialog.getExistingDirectory(self, self.label)
        self.path_box.setText(path)

    def set(self, value):
        self.path_box.setText(value)

    def get(self, value):
        self.path_box.text()


class helper_Q_sidebar_animator(QObject):
    def __init__(self, splitter):
        super().__init__()
        self._width = splitter.sizes()[0]
        self.splitter = splitter

    @pyqtProperty(int)
    def width(self):
        return self._width

    @width.setter
    def width(self, w):
        self._width = w
        total = sum(self.splitter.sizes())
        self.splitter.setSizes([w, total - w])


class Q_sidebar(QScrollArea):

    def __init__(self, parent_self):
        super().__init__()

        self.parent_self = parent_self

        self.expanded = True

        self._widget = QWidget()

        self._layout = QVBoxLayout()
        self._layout.setSpacing(4)  # or some spacing you prefer
        self._layout.setContentsMargins(4, 4, 4, 4)

        self._widget.setLayout(self._layout)

        self.setWidget(self._widget)
        self.setWidgetResizable(True)

        # Toggle button
        self.toggle_button = QPushButton("☰")
        self.toggle_button.setFixedSize(30, 30)
        self.toggle_button.clicked.connect(self.toggle_sidebar)

        try:
            self.previous_sidebar_width = self.parent_self.base_horizontal.sizes()[
                0]
        except:
            self.previous_sidebar_width = 200

    def toggle_sidebar(self):
        sidebar_width = self.parent_self.base_horizontal.sizes()[0]

        if self.expanded:
            # Collapsing sidebar: save width
            self.previous_sidebar_width = sidebar_width
            start = sidebar_width
            end = 0
        else:
            # Expanding sidebar: restore previous width
            start = 0
            end = self.previous_sidebar_width

        self.expanded = not self.expanded

        # Animate only the sidebar width
        self._animator = helper_Q_sidebar_animator(
            self.parent_self.base_horizontal)
        self._animation = QPropertyAnimation(self._animator, b"width")
        self._animation.setDuration(100)
        self._animation.setStartValue(start)
        self._animation.setEndValue(end)
        self._animation.start()

    def add_line(self, height=2):
        self._layout.addWidget(Q_horizontal_line(height))

    def add(self, *widgets_or_layouts, line_after=True):
        for elem in widgets_or_layouts:
            if isinstance(elem, QWidget):
                self._layout.addWidget(elem)
            elif isinstance(elem, (QHBoxLayout, QVBoxLayout)):
                self._layout.addLayout(elem)

        if line_after == True:
            self.add_line()


class MainWindow(QWidget):
    def __init__(self, title="", icon_path=None, width=1920/2, height=1080/2, ask_confirm_closing=False, hide_title_bar=False):
        super().__init__()

        self.ask_confirm_closing = ask_confirm_closing

        self.set_title(title)
        self.set_icon(icon_path)
        self.set_size(width, height)

        if hide_title_bar:
            self.setWindowFlags(Qt.FramelessWindowHint | Qt.Window)

        ############################################

        self.button = Q_button(lambda x: None, "Click Me")

        self.dropdown1 = Q_com_port_dropdown(
            default_com_port, lambda: 1, label="dropdown0")

        self.dropdown2 = Q_updating_dropdown(lambda: [
                                             "Option 1", "Option 2", "Option 3"], on_select_function=lambda: 1, label="dropdown1")

        self.dropdown3 = Q_dropdown(values=[
                                    "Option 1", "Option 2", "Option 3"], on_select_function=lambda: 1, label="dropdown2")

        self.switch = Q_check_box(lambda x: None, "Enable Option")

        self.text_input = Q_input_line(
            label="line1", placeholder_text="placeholder")

        self.slider = Q_slider(0, 100, label="slider",
                               on_change_function=self._on_slider_change)

        self.colored_bar = Q_colored_pbar()

        self.terminal_output = Q_terminal()

        self.command_line = Q_command_line(
            on_enter_function=lambda x: None, output=self.terminal_output, placeholder_text="placeholder")

        self.folder_selector = Q_folder_path()
        self.file_selector = Q_file_path()

        #################################

        self.radio_label = QLabel("Whatever:")
        self.radio1 = QRadioButton("Choice 1")
        self.radio2 = QRadioButton("Choice 2")
        self.radio3 = QRadioButton("Choice 3")
        self.radio_group = QButtonGroup()
        self.radio_group.addButton(self.radio1, id=1)
        self.radio_group.addButton(self.radio2, id=2)
        self.radio_group.addButton(self.radio3, id=3)
        self.radio1.setChecked(True)
        self.radio_group.buttonClicked[int].connect(self._on_radio_selected)

        self.progress_bar = QProgressBar()
        self.progress_bar.setMinimum(0)
        self.progress_bar.setMaximum(100)
        self.progress_bar.setValue(0)  # Start at 0%
        self.progress_bar.setFormat("%p%")  # shows "42%"
        self.progress_bar.setTextVisible(True)
        # self.progress_bar.setMaximum(0)  # no max means it's in 'busy' mode

        ###################################

        self.sidebar = Q_sidebar(self)
        
        self.com_port_dropdown = Q_com_port_dropdown(
            on_select_function=lambda:None,
            start_value="Select COM Port"
            )
        
        self.sidebar.add(self.com_port_dropdown)
        

        # self.sidebar.add(self.button, True)
        # self.sidebar.add(self.dropdown1)
        # self.sidebar.add(self.dropdown2, self.dropdown3)
        # self.sidebar.add(self.switch)
        # self.sidebar.add(self.file_selector)
        # self.sidebar.add(self.folder_selector)
        # self.sidebar.add(self.text_input)
        # self.sidebar.add(self.slider)
        # self.sidebar.add(self.radio_label, self.radio1, self.radio2)
        # self.sidebar.add(self.progress_bar)
        # self.sidebar.add(self.colored_bar)
        # self.sidebar.add(self.command_line, self.terminal_output)

        ############################################

        # Image viewer setup
        self.current_frame = None
        self.image = QLabel()
        self.image.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Ignored)
        self.image.setAlignment(Qt.AlignCenter)
        self.image.resizeEvent = self._on_window_resize

        # image_title that does not expand
        self.image_title = QLabel("My Image Title")
        self.image_title.setAlignment(Qt.AlignCenter)
        self.image_title.setStyleSheet("font-weight: bold; font-size: 16px;")
        self.image_title.setSizePolicy(
            self.image_title.sizePolicy().horizontalPolicy(), QSizePolicy.Fixed)

        self.image_title_horizontal = QHBoxLayout()
        self.image_title_horizontal.addWidget(self.sidebar.toggle_button)
        self.image_title_horizontal.addWidget(self.image_title)

        # image box
        image_box = QWidget()
        image_box_layout = QVBoxLayout(image_box)
        image_box_layout.addLayout(self.image_title_horizontal)
        image_box_layout.addWidget(self.image)

        ############################################

        # Vertical splitter
        main_vertical = Q_splitter_vertical()
        main_vertical.addWidget(image_box)
        main_vertical.setStretchFactor(0, 5)  # Give image more space
        # main_vertical.setStretchFactor(1, 1)  # Terminal less space

        ############################################

        # Horizontal splitter for sidebar and right area
        self.base_horizontal = Q_splitter_horizontal()
        self.base_horizontal.addWidget(self.sidebar)
        self.base_horizontal.addWidget(main_vertical)
        self.base_horizontal.setStretchFactor(
            0, 1)  # Sidebar smaller by default
        self.base_horizontal.setStretchFactor(1, 4)  # Right side bigger

        ############################################

        # Main layout
        main_layout = QHBoxLayout()
        main_layout.addWidget(self.base_horizontal)
        self.setLayout(main_layout)

        # Timer to update OpenCV image
        self.timer = QTimer()
        self.timer.timeout.connect(self.update_content)
        self.timer.start(10)

        ############################################
        # code specific initialization:
        ############################################

    ########################################
    # Methods:
    ########################################

    def log(self, *text, sep=" ", end="\n"):
        self.terminal_output.log(*text, sep=sep, end=end)

    def set_image_title(self, text):
        self.image_title.setText(text)

    def update_content(self):
        try:
            self.current_frame = get_frame()
            self._repaint_image()
        except Exception as e:
            self.terminal_output.log("--------------------")
            self.terminal_output.log(f"[ERROR] {str(e)}:")
            self.terminal_output.log(traceback.format_exc)
            self.terminal_output.log("--------------------")

    def set_size(self, width, height):
        self.resize(int(width), int(height))

    def set_position(self, x, y):
        self.move(int(x), int(y))

    def set_title(self, title=""):
        self.setWindowTitle(title)

    def set_icon(self, path):
        if path is not None:
            self.setWindowIcon(QIcon(path))

    ########################################
    # helper GUI event handlers:

    def _on_radio_selected(self, id):
        pass

    def _on_slider_change(self, value):
        self.progress_bar.setValue(value)
        self.colored_bar.set_value(value)
        self.terminal_output.log(value, color="red", bold=True, sep="\n")

    #######################################
    # helpers

    def _on_window_resize(self, event):
        self._repaint_image()
        event.accept()  # mark event as handled

    def _repaint_image(self):
        if self.current_frame is None:
            return

        rgb_image = cv2.cvtColor(self.current_frame, cv2.COLOR_BGR2RGB)
        h, w, ch = rgb_image.shape
        bytes_per_line = ch * w
        qt_image = QImage(rgb_image.data, w, h,
                          bytes_per_line, QImage.Format_RGB888)

        pixmap = QPixmap.fromImage(qt_image)

        # Scale pixmap to label size, keeping aspect ratio
        scaled_pixmap = pixmap.scaled(
            self.image.size(),
            Qt.KeepAspectRatio,
            Qt.SmoothTransformation
        )
        self.image.setPixmap(scaled_pixmap)

    def closeEvent(self, event):
        # print("Window is closing!")  # Custom action

        # Optional: ask for confirmation
        if self.ask_confirm_closing == True:
            reply = QMessageBox.question(
                self,
                "Confirm Exit",
                "Are you sure you want to quit?",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.No
            )

            if reply == QMessageBox.Yes:
                event.accept()  # Close the window
            else:
                event.ignore()  # Ignore the close
        else:
            event.accept()

    ########################################


title = "test"
icon_path = r"icons\icon.ico"
default_com_port = "com9"
window_pixels_h, window_pixels_v = 1000, 700

app = QApplication(sys.argv)
window = MainWindow(title, icon_path, window_pixels_h,
                    window_pixels_v, hide_title_bar=False)
window.show()
sys.exit(app.exec_())

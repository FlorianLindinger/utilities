# autopep8: off

import builtins
import copy
import inspect
import os
import sys
import threading
import time
import traceback
from collections.abc import Sequence
from concurrent.futures import ProcessPoolExecutor, TimeoutError
from contextlib import contextmanager

import numpy as np
import serial.tools.list_ports  # install as pyserial
from numba import njit
from scipy.optimize import curve_fit, least_squares

# autopep8: on


def peak_pos_2D(image):
    """returns x,y (vertical from top,horizonzal) positon of the peak in a 2D image"""
    image = np.asanyarray(image)
    return np.unravel_index(np.argmax(image), image.shape)


def is_list(x):
    """returns True if x is a list type (aka sequence but no string)"""
    if isinstance(x, Sequence) and not isinstance(x, str):
        return True
    else:
        return False

class create_data_list_lock:
    """Thread save locked version of list. Objects can be used as lock with "with object:" or "with object(timeout_s):". If no timeout is given it uses the default timeout (default default_timeout_s=None)."""

    def __init__(self, default_timeout_s=None):
        self.lock = threading.Lock()
        self._data_list = []
        if default_timeout_s in [None, False]:
            default_timeout_s = -1
        self.default_timeout_s = default_timeout_s

    def __length__(self, timeout_s="default_timeout_s"):
        with self(timeout_s):
            return len(self._data_list)

    def __getitem__(self, index, timeout_s="default_timeout_s", deepcopy=True):
        with self(timeout_s):
            if deepcopy == True:
                return copy.deepcopy(self._data_list[index])
            else:
                return self._data_list[index]

    def __setitem__(self, index, value, timeout_s="default_timeout_s"):
        with self(timeout_s):
            self._data_list[index] = value

    def __delitem__(self, index, timeout_s="default_timeout_s"):
        with self(timeout_s):
            del self._data_list[index]

    def __iter__(self):
        with self:
            return copy.deepcopy(iter(self._data_list))

    def __enter__(self):
        timeout = self.default_timeout_s
        if timeout in [None, False]:
            timeout = -1
        self.lock.acquire(timeout=timeout)

    def __exit__(self, *exceptions):
        self.lock.release()
        return False

    @contextmanager
    def _contextmanager(self, *, timeout_s):
        self.lock.acquire(timeout=timeout_s)
        try:
            yield self
        finally:
            self.lock.release()

    def __call__(self, timeout_s="default_timeout_s"):
        if timeout_s in [None, False]:
            timeout_s = -1
        elif timeout_s == "default_timeout_s":
            timeout_s = self.default_timeout_s
        return self._contextmanager(timeout_s=timeout_s)

    def append(self, data, timeout_s="default_timeout_s", deepcopy=True):
        with self(timeout_s):
            if deepcopy == True:
                self._data_list.append(copy.deepcopy(data))
            else:
                self._data_list.append(data)

    def pop(self, index=-1, timeout_s="default_timeout_s"):
        with self(timeout_s):
            return self._data_list.pop(index)

    def clear(self, timeout_s="default_timeout_s"):
        with self(timeout_s):
            self._data_list = []


class create_data_lock:
    """Thread save locked version of variable. Objects can be used as lock with "with object:" or "with object(timeout_s):". If no timeout is given it uses the default timeout (default default_timeout_s=None)."""

    def __init__(self, start_value=None, default_timeout_s=None):
        self.lock = threading.Lock()
        if default_timeout_s in [None, False]:
            default_timeout_s = -1
        self.default_timeout_s = default_timeout_s
        self._data = start_value

    def __enter__(self):
        timeout = self.default_timeout_s
        if timeout in [None, False]:
            timeout = -1
        self.lock.acquire(timeout=timeout)

    def __exit__(self, *_exceptions):
        self.lock.release()
        return False

    def __iadd__(self, delta):
        with self():
            self._data += delta
            return self

    def __isub__(self, delta):
        with self():
            self._data -= delta
            return self

    def __repr__(self):
        return f"locked_data({self.get()})"

    def __str__(self):
        return str(self.get())

    def __bool__(self):
        return bool(self.get())

    def __int__(self):
        return int(self.get())

    def __float__(self):
        return float(self.get())

    def __index__(self):  # enables use in slices, ranges
        return int(self.get())

    def __len__(self):
        return len(self.get())

    @contextmanager
    def _contextmanager(self, *, timeout_s):
        self.lock.acquire(timeout=timeout_s)
        try:
            yield self
        finally:
            self.lock.release()

    def __call__(self, timeout_s="default_timeout_s"):
        if timeout_s in [None, False]:
            timeout_s = -1
        elif timeout_s == "default_timeout_s":
            timeout_s = self.default_timeout_s
        return self._contextmanager(timeout_s=timeout_s)

    def set(self, data, timeout_s="default_timeout_s", deepcopy=True):
        with self(timeout_s):
            if deepcopy == True:
                self._data = copy.deepcopy(data)
            else:
                self._data = data

    def get(self, timeout_s="default_timeout_s", deepcopy=True):
        with self(timeout_s):
            if deepcopy == True:
                return copy.deepcopy(self._data)
            else:
                return self._data


def make_folder(path: str, file_path: bool = False, error_if_exist: bool = False) -> None:
    """creates the folder structure of folderpath if that path does not exist already.
    If parameter file_path is True (default False) it will create the directory for a file_path.
    If error_if_exist is True (default False) it will raise an error if that path already exists

        Args:
                path (str): folderpath (for file_path==True) or file_path (for file_path==False)
                file_path (bool, optional): Decides if path is folderpath or file_path. Defaults to False.
        error_if_exist (bool, optional): Decides if error is raise if folder already exists. Defaults to False.
    """

    if file_path == False:
        os.makedirs(path, exist_ok=True)
    else:
        dir_name = os.path.dirname(path)
        if dir_name != "":
            os.makedirs(dir_name, exist_ok=not error_if_exist)


def estimate_gaussian_widths(image):
    """
    Estimate 1/e² diameters (Dx, Dy) from second moments of the image.
    Assumes image is already cropped to region of interest.
    """
    total = image.sum()
    if total == 0:
        return 1.0, 1.0  # fallback

    nx, ny = image.shape
    x, y = np.indices((nx, ny))

    x_center = (x * image).sum() / total
    y_center = (y * image).sum() / total

    x2 = ((x - x_center) ** 2 * image).sum() / total
    y2 = ((y - y_center) ** 2 * image).sum() / total

    sigma_x = np.sqrt(x2)
    sigma_y = np.sqrt(y2)

    # Convert stddev to 1/e² diameter
    D_x = 2 * np.sqrt(2) * sigma_x
    D_y = 2 * np.sqrt(2) * sigma_y

    return (D_x + D_y) / 2


class returning_thread(threading.Thread):
    """same as threading.Thread but with return value of the threaded function"""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.result = None

    def run(self):
        self.result = self._target(*self._args, **self._kwargs)  # type:ignore

    def join(self, *args, **kwargs):
        super().join(*args, **kwargs)
        return self.result


def run_as_thread(function, *args, **kwargs):
    """Runs function in a separate thread (rest of python code will run concurrently).
    Useful for non CPU heavy tasks that need to be run while the main python code continues.
    Starts a thread that runs until the function is finished but does not block the main code"""
    thread = returning_thread(target=function, args=args, kwargs=kwargs)
    thread.start()
    return thread


def run_with_timeout(func, *args, timeout=None, **kwargs):
    """
    Run `func(*args, **kwargs)` in a separate process.
    Return the result or None if it exceeds `timeout` seconds.
    """
    with ProcessPoolExecutor(max_workers=1) as executor:
        future_instance = executor.submit(func, *args, **kwargs)
        try:
            return future_instance.result(timeout=timeout)
        except TimeoutError:
            executor.shutdown(cancel_futures=True)
            return None


def start_thread_loop(function, stop_handle="stop_global_threads", exception_function=traceback.print_exc):  # type:ignore
    """useful for non CPU heavy tasks that need to be run while the main python code continues.
    Start a loop thread of function which runs until the stop_handle is globally set to True.
    Exception function can be defined for non KeyboardInterrupt exceptions.
    By default the exception traceback is printed (with print_traceback) but no error is raised (raise by defining
    exception_function=raise_exception) for the Exception. By default the stop_handle is set to True globally for the
    KeyboardInterrupt.
    Thread returns:
        0 if external stop with global variable stop_handle
        1 if any other exception excepted
        Function output withing a list if looped function returned not None which stopped loop"""

    # initialize stop_handle if not existing
    if stop_handle not in globals():
        globals()[stop_handle] = False

    # create dummy function for None input
    if exception_function is None:

        def exception_function():
            return None

    # define loop function
    def loop_thread_generator(function):
        def loop_function():
            try:
                while True:
                    if globals()[stop_handle] == True:
                        return 0
                    output = function()
                    if output != None:
                        # to make sure it is differentiable to other returns
                        return [output]
            except Exception:
                exception_function()
                return 1

        return loop_function

    thread = returning_thread(target=loop_thread_generator(function))
    thread.start()
    return thread


def start_main_loop(function=None, stop_handle="stop_global_threads", exception_function=traceback.print_exc):  # type:ignore
    """Make sure a function returnes often enough to handle a program stop and KeyboardInterrupt in wanted time. Call this thread last"""

    # initialize stop_handle if not existing
    if stop_handle not in globals():
        globals()[stop_handle] = False

    # define default KeyboardInterrupt_function which changes a global variable to potentially indicate for other threads to stop
    if function is None:

        def function():
            time.sleep(0.1)

    if exception_function is None:

        def exception_function():
            return None

    try:
        while True:
            if globals()[stop_handle] == True:
                return 0
            output = function()
            if output != None:
                # to make sure it is differentiable to other returns
                return [output]
    except Exception:
        exception_function()
        globals()[stop_handle] = True
        return 1
    except KeyboardInterrupt:
        globals()[stop_handle] = True
        return 2


def add_number_to_path(path: str, number_prefix="_", has_file_ending: bool = True, start_number=0) -> str:
    """adds a number_prefix (default "_") and number to the file/folder name and increments by 1 if it already exists. It assumes the file has a file ending if has_file_ending == True (default unless no "." in path). Starts with 0."""

    if "." not in path:
        has_file_ending = False
    if has_file_ending:
        *path_no_ending, file_ending = path.split(".")  # type: ignore
        path_no_ending = ".".join(path_no_ending) + str(number_prefix)  # type: ignore
        file_ending = "." + file_ending
        out_path = path_no_ending + str(start_number) + file_ending
        i = start_number + 1
        while os.path.exists(out_path):  # type: ignore
            out_path = path_no_ending + str(i) + file_ending  # type: ignore
            i += 1
    else:
        path = path + str(number_prefix)
        out_path = path + str(start_number)
        i = start_number + 1
        while os.path.exists(out_path):  # type: ignore
            out_path = path + str(i)
            i += 1
    return out_path  # type: ignore


def get_available_com_ports() -> list[str]:
    return [str(elem) for elem in serial.tools.list_ports.comports()]  # nopep8 #type:ignore


class suppress_print:
    """Usage:
    with suppress_print():
        hide all print() globally"""

    def __enter__(self):
        self.old_print = builtins.print
        builtins.print = self._pass

    def __exit__(self, exc_type, exc, tb):
        builtins.print = self.old_print

    @staticmethod
    def _pass(*args, **kwargs):
        pass


def round_significant_simple(x, digits=4, return_string=False, fixed_length=False):
    """Round x to digits number of significant digits. Returns a int if
    rounded number is int to avoid 1000.0 instead of 1000 for 4 significant
    digits for example. Format needed to avoid float rounding errors which give
    for example 0001 or 9999 after the significant digits. in return_string==True: numbers >=10^8 it will convert just that number to a string in scientific notation."""

    if fixed_length == True:
        return_string = True

    if isinstance(x, str):
        try:
            x = float(x)
        except:
            return x

    # zero case
    if x == 0:
        if return_string == True:
            return "0"
        else:
            return 0

    # nonzero case
    round_number = digits - int(np.floor(np.log10(abs(np.float64(x))))) - 1
    x_round = float(round(x, round_number))

    if fixed_length == True:
        x_str = str(x_round)
        if len(x_str) > digits + 1 * ("." in x_str) + 1 * (x_str.replace("-", "")[0] == "0") + 1 * (x_str[0] == "-"):
            pass
        else:
            while True:
                if len(x_str) == digits + 1 * ("." in x_str) + 1 * (x_str.replace("-", "")[0] == "0") + 1 * (
                    x_str[0] == "-"
                ):
                    return x_str
                else:
                    if "." in x_str:
                        x_str = x_str + "0"
                    else:
                        x_str = x_str + ".0"

    if return_string == False:
        x_int = int(x_round)
        if x_round == x_int and len(str(x_round)) > len(str(x_int)):
            return x_int
        else:
            return x_round
    else:  # return string case
        x_float = format(x_round, "." + str(max(round_number, 0)) + "f")
        while "." in x_float and x_float[-1] in ["0", "."]:
            x_float = x_float[:-1]
        x_e = format(x_round, "." + str(digits - 1) + "e")
        if x_e[-2] == "0" and x_e[-3] in ["+", "-"]:
            x_e = x_e[:-2] + x_e[-1]
        e_idx = x_e.find("e")
        while "." in x_e and x_e[e_idx - 1] in ["0", "."]:
            x_e = x_e[: e_idx - 1] + x_e[e_idx:]
            e_idx = e_idx - 1

        if len(x_e) < len(x_float):
            return x_e
        else:
            return x_float


###############################################################
from functools import lru_cache

import numpy as np
from numba import njit
from scipy.optimize import least_squares


# ----- core model -----
@njit(
    "(float64[:,::1], float64[:,::1], float64, float64, float64, float64, float64, float64, float64)",
    fastmath=True,
    cache=True,
)
def rotated_2D_gaussian(x, y, A, x0, y0, D_1_over_e2_x, D_1_over_e2_y, phi, offset):
    x_shift = x - x0
    y_shift = y - y0
    c = np.cos(phi)
    s = np.sin(phi)
    xp = c * x_shift + s * y_shift
    yp = -s * x_shift + c * y_shift
    t = xp / D_1_over_e2_x
    u = yp / D_1_over_e2_y
    return A * np.exp(-8.0 * (t * t + u * u)) + offset


@njit(
    "(float64[:,::1], float64[:,::1], float64, float64, float64, float64, float64, float64, float64)",
    fastmath=True,
    cache=True,
)
def model_and_jac(x, y, A, x0, y0, Dx, Dy, phi, offset):
    x_shift = x - x0
    y_shift = y - y0
    c = np.cos(phi)
    s = np.sin(phi)
    xp = c * x_shift + s * y_shift
    yp = -s * x_shift + c * y_shift
    t = xp / Dx
    u = yp / Dy
    g = np.exp(-8.0 * (t * t + u * u))
    invDx2 = 1.0 / (Dx * Dx)
    invDy2 = 1.0 / (Dy * Dy)
    # dE where E = -8*(t^2+u^2)
    dE_dx0 = 16.0 * (c * xp * invDx2 - s * yp * invDy2)
    dE_dy0 = 16.0 * (s * xp * invDx2 + c * yp * invDy2)
    dE_dDx = 16.0 * ((xp * xp) / (Dx * Dx * Dx))
    dE_dDy = 16.0 * ((yp * yp) / (Dy * Dy * Dy))
    dxp_dphi = -s * x_shift + c * y_shift
    dyp_dphi = -c * x_shift - s * y_shift
    dE_dphi = -16.0 * (xp * dxp_dphi * invDx2 + yp * dyp_dphi * invDy2)

    m = A * g + offset
    J_A = g
    J_x0 = A * g * dE_dx0
    J_y0 = A * g * dE_dy0
    J_Dx = A * g * dE_dDx
    J_Dy = A * g * dE_dDy
    J_phi = A * g * dE_dphi
    J_offset = np.ones_like(g)

    return (
        m.ravel(),
        J_A.ravel(),
        J_x0.ravel(),
        J_y0.ravel(),
        J_Dx.ravel(),
        J_Dy.ravel(),
        J_phi.ravel(),
        J_offset.ravel(),
    )


# ----- cached grids -----
_grid_cache = {}


def _get_grids(h, w):
    key = (h, w)
    g = _grid_cache.get(key)
    if g is None:
        y2D, x2D = np.mgrid[0:h, 0:w]
        x2D = np.ascontiguousarray(x2D, dtype=np.float64)
        y2D = np.ascontiguousarray(y2D, dtype=np.float64)
        _grid_cache[key] = (x2D, y2D)
        return x2D, y2D
    return g


# ----- fast fitter (no ROI) -----
def fit_2D_gaussian(image, maxfev=500, initial_guess=None):
    image = np.asarray(image, dtype=np.float64, order="C")
    h, w = image.shape
    vmin = float(image.min())
    vmax = float(image.max())
    vrange = vmax - vmin
    if vrange == 0:
        return None

    if initial_guess is None:
        peak_x, peak_y = peak_pos_2D(image)  # your function
        Dxy = estimate_gaussian_widths(image)  # your function
        initial_guess = [vrange, peak_x, peak_y, Dxy, Dxy, 0.0, vmin]

    lb = np.array([0.0, 0.01 * w, 0.01 * h, 3.0, 3.0, -np.pi / 2, vmin - vrange / 10], dtype=np.float64)
    ub = np.array([1.1 * vrange, 0.99 * w, 0.99 * h, w, h, np.pi / 2, vmin + 0.9 * vrange], dtype=np.float64)

    p0 = np.asarray(initial_guess, dtype=np.float64)
    span = ub - lb
    p0 = np.minimum(np.maximum(p0, lb + 0.01 * span), ub - 0.01 * span)

    x2D, y2D = _get_grids(h, w)
    target = image.ravel()

    def fun(p):
        m, *_ = model_and_jac(x2D, y2D, *p)
        return m - target

    def jac(p):
        _, J_A, J_x0, J_y0, J_Dx, J_Dy, J_phi, J_off = model_and_jac(x2D, y2D, *p)
        return np.column_stack([J_A, J_x0, J_y0, J_Dx, J_Dy, J_phi, J_off])

    res = least_squares(
        fun,
        x0=p0,
        bounds=(lb, ub),
        jac=jac,
        method="trf",
        x_scale="jac",
        ftol=1e-6,
        gtol=1e-6,
        xtol=1e-6,
        max_nfev=maxfev,
        verbose=0,
    )
    if not res.success:
        return None

    rms = np.sqrt(np.mean(res.fun * res.fun))
    return (*res.x, rms)

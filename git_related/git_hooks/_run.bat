@echo off
rem Shared body of the batch files in this folder: runs git_hooks.py with Python 3.8+ for the
rem Git repository that contains this folder, or for a folder dropped onto the batch file.
setlocal EnableExtensions DisableDelayedExpansion
set "here=%~dp0"
set "repo=%~1"
shift
if not defined repo set "repo=%here%."
set "python="
for %%P in (py python python3) do if not defined python (
    %%P -c "import sys; sys.exit(sys.version_info < (3, 8))" >nul 2>&1 && set "python=%%P"
)
if not defined python (
    echo Python 3.8 or newer was not found on PATH. Install it from https://www.python.org/ and try again.
    set "code=1"
    goto done
)
%python% -B "%here%git_hooks.py" %1 %2 %3 %4 %5 %6 %7 %8 %9 --repo "%repo%"
set "code=%ERRORLEVEL%"
:done
if not defined NO_PAUSE (
    echo.
    pause
)
exit /b %code%

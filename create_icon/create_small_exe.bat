@echo off
setlocal enabledelayedexpansion

:: Clean old build artifacts AND PyInstaller cache to avoid permission/corruption issues
rem echo Cleaning old build files and cache...
rem rmdir /s /q build 2>nul
rem rmdir /s /q dist 2>nul
rem del /q *.spec 2>nul
rem rmdir /s /q "%LOCALAPPDATA%\pyinstaller" 2>nul
rem timeout /t 2 /nobreak >nul
rem echo.

:: Install Nuitka and Zstandard
echo Installing/Updating Nuitka...
python -m pip install nuitka zstandard >nul 2>&1
echo.

:: Find python file
for %%f in ("*.py") do (
    set "python_file=%%f"
    set "file_name=%%~nf"
    echo Compiling: !python_file!
    echo.
    goto :found
)
:found

:: Delete old exe
if exist "%file_name%.exe" del "%file_name%.exe"

:: --- MAX OPTIMIZATION FLAGS FOR SMALLEST SIZE ---
:: --onefile: Create a single compressed executable file (not a folder)
:: --lto=yes: Link Time Optimization (smaller binary, faster execution)
:: --deployment: Disables safety checks meant for development
:: --python-flag=no_docstrings,no_asserts,-OO: Strip docstrings, asserts, and optimize bytecode
:: --prefer-source-code: Keep some modules as bytecode instead of compiled (smaller)
:: --nofollow-import-to: Don't follow imports to these modules (excludes them from exe)

rem   --windows-disable-console ^

python -m nuitka ^
  --onefile ^
  --lto=yes ^
  --deployment ^
  --python-flag=no_docstrings,no_asserts,-OO ^
  --prefer-source-code ^
  --nofollow-import-to=pytest ^
  --nofollow-import-to=unittest ^
  --nofollow-import-to=IPython ^
  --nofollow-import-to=setuptools ^
  --nofollow-import-to=distutils ^
  --nofollow-import-to=tkinter ^
  --nofollow-import-to=email ^
  --nofollow-import-to=xml ^
  --nofollow-import-to=http ^
  --nofollow-import-to=urllib ^
  --assume-yes-for-downloads ^
  --remove-output ^
  --output-dir=. ^
  --output-filename="%file_name%_py.exe" ^
  "%python_file%"

echo.
if exist "%file_name%_py.exe" (
    echo ============================================
    echo SUCCESS! Optimized EXE created: %file_name%_py.exe
    echo ============================================
) else (
    echo ============================================
    echo ERROR: Build failed! Check output above.
    echo ============================================
)

echo.
echo Press any key to exit
PAUSE > nul
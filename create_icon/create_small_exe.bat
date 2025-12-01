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

:: --- MAX OPTIMIZATION FLAGS ---
:: --lto=yes: Link Time Optimization (smaller binary, faster execution, slower compile)
:: --static-libpython=yes: Embeds the Python library directly (removes dependency on external python DLLs)
:: --deployment: Disables safety checks meant for development (asserts, docstrings, etc.) to gain speed
:: --disable-console: Standard for GUI apps (remove this line if you want to see print output!)

rem   --windows-disable-console ^

python -m nuitka ^
  --onefile ^
  --standalone ^
  --lto=yes ^
  --deployment ^
  --assume-yes-for-downloads ^
  --remove-output ^
  --output-dir=. ^
  "%python_file%"

echo.
if exist "%file_name%.exe" (
    echo ============================================
    echo SUCCESS! Optimized EXE created: %file_name%.exe
    echo ============================================
) else (
    echo ============================================
    echo ERROR: Build failed! Check output above.
    echo ============================================
)

echo.
echo Press any key to exit
PAUSE > nul
@echo off
setlocal enabledelayedexpansion

:: install pyinstaller (python to exe bundler - no compiler needed)
python -m pip install pyinstaller >nul 2>&1
echo.

:: find python file
for %%f in ("*.py") do (
    set "python_file=%%f"
    set "file_name=%%~nf"
    echo Compiling: !python_file!
    echo.
    goto :found
)
:found

:: Clean old build artifacts AND PyInstaller cache to avoid permission/corruption issues
echo Cleaning old build files and cache...
rmdir /s /q build 2>nul
rmdir /s /q dist 2>nul
del /q *.spec 2>nul
rmdir /s /q "%LOCALAPPDATA%\pyinstaller" 2>nul
timeout /t 2 /nobreak >nul
echo.

:: compile with pyinstaller (no C compiler needed!)
python -m PyInstaller ^
  --distpath . ^
  --workdir exe_build ^
  --onefile ^
  --strip ^
  --optimize=2 ^
  --windowed ^
  --noconfirm ^
  --noupx ^
  --exclude-module tkinter ^
  --exclude-module matplotlib ^
  --exclude-module numpy ^
  --exclude-module scipy ^
  --exclude-module pandas ^
  --exclude-module pytest ^
  --exclude-module setuptools ^
  --exclude-module email ^
  --exclude-module html ^
  --exclude-module http ^
  --exclude-module urllib ^
  --exclude-module xml ^
  --exclude-module sqlite3 ^
  --exclude-module ssl ^
  --exclude-module multiprocessing ^
  --exclude-module unittest ^
  "%python_file%"

echo.
if exist "%file_name%.exe" (
    echo ============================================
    echo SUCCESS! EXE created: %file_name%.exe
    echo ============================================
) else (
    echo ============================================
    echo ERROR: Build failed! Check output above.
    echo ============================================
)
echo.
echo Press any key to exit
PAUSE > nul
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
rem echo Cleaning old build files and cache...
rem rmdir /s /q build 2>nul
rem rmdir /s /q dist 2>nul
rem del /q *.spec 2>nul
rem rmdir /s /q "%LOCALAPPDATA%\pyinstaller" 2>nul
rem timeout /t 2 /nobreak >nul
rem echo.

:: compile with pyinstaller (no C compiler needed!)
python -m PyInstaller ^
  --distpath . ^
  --workpath exe_build ^
  --onefile ^
  --strip ^
  --optimize=2 ^
  --windowed ^
  --noconfirm ^
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
  --exclude-module doctest ^
  --exclude-module pydoc ^
  --exclude-module argparse ^
  --exclude-module asyncio ^
  --exclude-module concurrent ^
  --exclude-module test ^
  --exclude-module lib2to3 ^
  --exclude-module pickle ^
  --exclude-module socket ^
  --exclude-module select ^
  "%python_file%"

echo.
if exist "%file_name%.exe" (
    echo ============================================
    echo SUCCESS! EXE created: %file_name%.exe
    
    :: Check if UPX is available
    where upx >nul 2>&1
    if !errorlevel!==0 (
        echo.
        echo Compressing with UPX (using --force for CFG compatibility)...
        upx --lzma -9 --no-progress "%file_name%.exe" 2>nul
        if !errorlevel!==0 (
            echo UPX compression successful!
        ) else (
            echo UPX compression skipped (already compressed or incompatible)
        )
        echo ============================================
    ) else (
        echo.
        echo TIP: Install UPX for smaller EXE:
        echo   winget install upx.upx
        echo ============================================
    )
) else (
    echo ============================================
    echo ERROR: Build failed! Check output above.
    echo ============================================
)
echo.
echo Press any key to exit
PAUSE > nul
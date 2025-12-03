@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: Ultra-Small Nuitka Compilation Script (OnFile + UPX)
:: Maximizes size reduction with aggressive optimization flags
:: ============================================================================

:: Capture start time
set START_TIME=%TIME%

:: Configuration
set SCRIPT_NAME=create_icon.py
set OUTPUT_NAME=create_icon_ultra_small
set PYTHON_CMD=python

echo.
echo ============================================================================
echo Ultra-Small Nuitka Compilation (OnFile + UPX)
echo ============================================================================
echo.
echo Script: %SCRIPT_NAME%
echo Output: %OUTPUT_NAME%.exe
echo.
echo This may take several minutes...
echo.

:: ============================================================================
:: Step 1: Install/Update Dependencies
:: ============================================================================
echo [1/4] Installing/Updating Nuitka, Zstandard, and UPX...
echo.

%PYTHON_CMD% -m pip install nuitka zstandard Pillow --upgrade --quiet
if errorlevel 1 (
    echo ERROR: Failed to install Nuitka and Zstandard
    pause
    exit /b 1
)

:: Check if UPX is available, if not provide instructions
where upx >nul 2>&1
if errorlevel 1 (
    echo.
    echo WARNING: UPX not found in PATH!
    echo Please download UPX from: https://upx.github.io/
    echo Extract upx.exe to a folder in your PATH or to this directory
    echo.
    set USE_UPX=no
) else (
    echo UPX found - compression will be applied
    set USE_UPX=yes
)

echo.

:: ============================================================================
:: Step 1.5: Generate Icon if Missing
:: ============================================================================
if not exist "favicon.ico" (
    echo Icon not found, generating from Picture1.png...
    if exist "Picture1.png" (
        %PYTHON_CMD% create_icon.py Picture1.png favicon.ico
    ) else (
        echo WARNING: Picture1.png not found, cannot generate icon.
    )
)

echo.
echo Dependencies ready!
echo.

:: ============================================================================
:: Step 2: Clean Previous Builds
:: ============================================================================
echo [2/4] Cleaning previous builds...
echo.

if exist "%OUTPUT_NAME%.dist" (
    echo Removing %OUTPUT_NAME%.dist
    rmdir /s /q "%OUTPUT_NAME%.dist" 2>nul
)
if exist "%OUTPUT_NAME%.build" (
    echo Removing %OUTPUT_NAME%.build
    rmdir /s /q "%OUTPUT_NAME%.build" 2>nul
)
if exist "%OUTPUT_NAME%.exe" (
    echo Removing old %OUTPUT_NAME%.exe
    del /q "%OUTPUT_NAME%.exe" 2>nul
)

echo Build directory cleaned!
echo.

:: ============================================================================
:: Step 3: Compile with Ultra-Aggressive Optimization
:: ============================================================================
echo [3/4] Compiling with maximum size optimization...
echo.

:: Build the nuitka command
set NUITKA_CMD=%PYTHON_CMD% -m nuitka

:: Core flags for smallest size
set FLAGS=--onefile
set FLAGS=%FLAGS% --lto=yes

:: Output control
set FLAGS=%FLAGS% --output-filename=%OUTPUT_NAME%.exe
set FLAGS=%FLAGS% --remove-output

:: Python optimization
set FLAGS=%FLAGS% --python-flag=-OO

:: Windows-specific optimizations
set FLAGS=%FLAGS% --windows-console-mode=disable
set FLAGS=%FLAGS% --windows-icon-from-ico=favicon.ico

:: UPX compression (if available)
if "%USE_UPX%"=="yes" (
    set FLAGS=%FLAGS% --enable-plugin=upx
)

:: Follow imports carefully (adjust based on your needs)
set FLAGS=%FLAGS% --follow-imports

:: Exclude unnecessary standard library modules to reduce size
set FLAGS=%FLAGS% --nofollow-import-to=tkinter
set FLAGS=%FLAGS% --nofollow-import-to=unittest
set FLAGS=%FLAGS% --nofollow-import-to=test
set FLAGS=%FLAGS% --nofollow-import-to=distutils
set FLAGS=%FLAGS% --nofollow-import-to=pydoc
set FLAGS=%FLAGS% --nofollow-import-to=doctest
set FLAGS=%FLAGS% --nofollow-import-to=multiprocessing
set FLAGS=%FLAGS% --nofollow-import-to=asyncio
set FLAGS=%FLAGS% --nofollow-import-to=concurrent
set FLAGS=%FLAGS% --nofollow-import-to=email
set FLAGS=%FLAGS% --nofollow-import-to=xml
set FLAGS=%FLAGS% --nofollow-import-to=html
set FLAGS=%FLAGS% --nofollow-import-to=http
set FLAGS=%FLAGS% --nofollow-import-to=urllib

:: Assume yes for any downloads
set FLAGS=%FLAGS% --assume-yes-for-downloads

:: Additional optimizations
set FLAGS=%FLAGS% --no-deployment-flag=self-execution

:: Show progress
set FLAGS=%FLAGS% --show-progress
set FLAGS=%FLAGS% --show-modules

:: Execute compilation
echo Running: %NUITKA_CMD% %FLAGS% %SCRIPT_NAME%
echo.

%NUITKA_CMD% %FLAGS% %SCRIPT_NAME%

if errorlevel 1 (
    echo.
    echo ============================================================================
    echo ERROR: Compilation failed!
    echo ============================================================================
    pause
    exit /b 1
)

echo.
echo Compilation successful!
echo.

:: ============================================================================
:: Step 4: Report Results
:: ============================================================================
echo [4/4] Compilation complete!
echo.
echo ============================================================================
echo RESULTS
echo ============================================================================
echo.

if exist "%OUTPUT_NAME%.exe" (
    for %%I in ("%OUTPUT_NAME%.exe") do (
        set "SIZE=%%~zI"
        set /a "SIZE_KB=!SIZE! / 1024"
        set /a "SIZE_MB=!SIZE_KB! / 1024"
        echo Output file: %OUTPUT_NAME%.exe
        echo File size:   !SIZE! bytes (!SIZE_KB! KB / !SIZE_MB! MB)
    )
    
    echo.
    echo Comparing with existing exe...
    if exist "create_icon_py_smal_oldl.exe" (
        for %%I in ("create_icon_py_smal_oldl.exe") do (
            set "OLD_SIZE=%%~zI"
            set /a "OLD_SIZE_KB=!OLD_SIZE! / 1024"
            set /a "OLD_SIZE_MB=!OLD_SIZE_KB! / 1024"
            echo Old exe:     create_icon_py_smal_oldl.exe
            echo Old size:    !OLD_SIZE! bytes (!OLD_SIZE_KB! KB / !OLD_SIZE_MB! MB)
            
            set /a "REDUCTION=!OLD_SIZE! - !SIZE!"
            set /a "REDUCTION_KB=!REDUCTION! / 1024"
            set /a "REDUCTION_MB=!REDUCTION_KB! / 1024"
            set /a "PERCENT=(!REDUCTION! * 100) / !OLD_SIZE!"
            
            echo.
            echo Size reduction: !REDUCTION! bytes (!REDUCTION_KB! KB / !REDUCTION_MB! MB)
            echo Percentage:     !PERCENT!%% smaller
        )
    )
) else (
    echo ERROR: Output file not found!
)

echo.
echo ============================================================================

:: Calculate duration
set END_TIME=%TIME%
echo Start time: %START_TIME%
echo End time:   %END_TIME%
echo.
echo ============================================================================

pause

@echo off
setlocal enabledelayedexpansion

:: measure start time
call :count_duration

:: find python file
for %%f in ("*.py") do (
    set "python_file=%%f"
    set "file_name=%%~nf"
    echo Compiling for small filesize: !python_file!
    echo.
    goto :found
)
:found

:: set variables
set "ending=_py_small"
set "output_path="
set "build_folder_path=%file_name%%ending%.build"
set "exe_name=%file_name%%ending%.exe"

:: make output path absolute
call :set_abs_path "%output_path%" "output_path"

:: install Nuitka and Zstandard
echo ===========================
echo Installing/Updating Nuitka:
echo.
python -m pip install nuitka zstandard --upgrade
echo.

:: compile
REM MAX OPTIMIZATION FLAGS FOR SMALLEST SIZE:
REM --onefile: Create a single compressed executable file (not a folder)
REM --jobs=%NUMBER_OF_PROCESSORS%: Use multiple jobs to speed up compilation
REM --lto=yes: Link Time Optimization (smaller binary, faster execution)
REM --deployment: Disables safety checks meant for development
REM --python-flag=no_docstrings,no_asserts,-OO: Strip docstrings, asserts, and optimize bytecode
REM --prefer-source-code: Keep some modules as bytecode instead of compiled (smaller)
REM --nofollow-import-to: Don't follow imports to these modules (excludes them from exe)
echo ===========================
echo Compilation:
echo.
python -m nuitka ^
    --standalone ^
    --no-lto ^
    --low-memory ^
    --python-flag=no_docstrings,no_asserts,-OO ^
    --prefer-source-code ^
    --nofollow-import-to=pytest,unittest,IPython,setuptools,distutils,tkinter,email,xml,http,urllib,multiprocessing,logging.config,decimal ^
    --jobs=%NUMBER_OF_PROCESSORS% ^
    --assume-yes-for-downloads ^
    --output-dir="%build_folder_path%" ^
    --output-filename="%exe_name%" ^
    "%python_file%"
echo.
echo ===========================
echo Compilation over
echo ===========================
echo.

del "%output_path%\%exe_name%" > nul 2>&1

:: move exe to output path
move "%build_folder_path%\%exe_name%" "%output_path%\%exe_name%" > nul 2>&1

:: print execution duration
call :count_duration "Execution Time:"

:: print end message
echo.
if exist "%output_path%\%exe_name%" (
    echo ============================================
    echo [Success] EXE created: "%output_path%\%exe_name%"
    call :print_size "%output_path%\%exe_name%"
    echo ============================================
) else (
    echo ============================================
    echo [Error] Compilation failed^! Check output above.
    echo ============================================
    echo Aborting. Press any key to exit
    PAUSE > nul
    exit /b 1
)

:: wait for user to press any key and exit
echo.
echo Press any key to exit
PAUSE > nul
exit /b 0

:: ====================
:: ==== FUNCTIONS: ====
:: ====================

::::::::::::::::::::::::::::::::::::::::::::::::
:: function to call twice to get printed the duration between the two calls. Arg for second call gives the text before print of e.g. " 18.2 s" (default "Duration:").
::::::::::::::::::::::::::::::::::::::::::::::::
:count_duration
setlocal enabledelayedexpansion
rem %TIME% ? HH:MM:SScc by removing the comma
set "t=%time:,=%"
rem HH = characters 0–1
set "HH=!t:~0,2!"
rem MM = characters 3–4
set "MM=!t:~3,2!"
rem SS = characters 6–7
set "SS=!t:~6,2!"
rem CC = characters 9–2 (centiseconds)
set "CC=!t:~9,2!"
rem calculate centiseconds since midnight
set /a total=(HH*3600 + MM*60 + SS)*100 + CC
REM set global variable to current time if unset or print time passed since start if already set and reset afterwards
if "%count_time_s_start%"=="" (
    endlocal & set "count_time_s_start=%total%"
) else (
    set /a diff=%total%-%count_time_s_start%
    if !diff! lss 0 set /a diff+=24*60*60*100
    set /a SEC=diff/100
    set /a CS=diff%%100
    if "%~1"=="" ( set "text=Duration:"
    ) else ( set "text=%~1" )
    echo !text! !SEC!.!CS! s
    endlocal & set "count_time_s_start="
)
exit /b 0

:: =============================================

::::::::::::::::::::::::::::::::::::::::::::::::
:: function that prints e.g. "{arg2} 40.0 MB" ({arg2} default: "Size:") for first arg = file or folder path. Converts to approprate GB/MB/...
::::::::::::::::::::::::::::::::::::::::::::::::
:print_size
setlocal enabledelayedexpansion
rem %1 = path to the file or folder
set "item_path=%~1"
if not exist "%item_path%" (
    echo File/Folder not found for size determination: %item_path%
    exit /b 1
)
if "%~2"=="" ( set "text=Size:"
) else ( set "text=%~2" )
FOR /F "usebackq tokens=*" %%G IN (`powershell -ExecutionPolicy Bypass -Command "$Path = '%item_path%'; $Item = Get-Item -LiteralPath $Path; $1MB = 1048576; $1GB = 1073741824; if ($Item.PSIsContainer) { $B = (Get-ChildItem -Recurse -File -LiteralPath $Path | Measure-Object -Sum Length).Sum; } else { $B = $Item.Length; } if (-not $B) { $B = 0 }; if ($B -ge $1GB) { '{0:N1} GB' -f ($B / $1GB) } elseif ($B -ge $1MB) { '{0:N1} MB' -f ($B / $1MB) } else { '{0:N0} Bytes' -f $B }"`) DO (
    echo %text% %%G 
)
endlocal
exit /b 0

:: =============================================

::::::::::::::::::::::::::::::::::::::::::::::::
:: function that converts relative (to current working directory) path {arg1} to absolute and sets it to variable {arg2}. Works for empty path {arg1} which then sets the current working directory to variable {arg2}. Raises error if {arg2} is missing:
:: Usage:
::    call :set_abs_path "%some_path%" "some_path"
::::::::::::::::::::::::::::::::::::::::::::::::
:set_abs_path
    if "%~2"=="" (
        echo [Error] Second argument is missing for :set_abs_path function in "%~f0". (First argument was "%~1"^). 
        echo Aborting. Press any key to exit.
        pause > nul
        exit /b 1
    )
    if "%~1"=="" (
        set "%~2=%CD%"
    ) else (
	    set "%~2=%~f1"
    )
goto :EOF

:: =================================================
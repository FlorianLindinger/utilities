@echo off
setlocal enabledelayedexpansion

:: measure start time
call :count_duration

:: find python file
for %%f in ("*.py") do (
    set "python_file=%%f"
    set "file_name=%%~nf"
    echo Compiling for fast execution: !python_file!
    echo.
    goto :found
)
:found

:: set variables
REM Ending "_py_fast" for delete safey of output_folder_path folder deletion! Do not change it to empty or remove from output_folder_path!
set "ending=_py_fast"
set "output_folder_path=%file_name%%ending%"
set "build_folder_path=%file_name%%ending%.build"
set "exe_name=%file_name%%ending%.exe"
set "local_shortcut_name=%file_name%%ending%_local.bat"
set "recreate_local_shortcut_name=recreate_local_workspace_shortcut.bat"

:: make output folder path absolute
call :set_abs_path "%output_folder_path%" "output_folder_path"

:: install Nuitka and Zstandard
echo ===========================
echo Installing/Updating Nuitka:
echo.
python -m pip install nuitka zstandard --upgrade
echo.

:: compile
REM MAX OPTIMIZATION FLAGS FOR FASTEST EXECUTION:
REM --standalone: Create a standalone executable (includes all dependencies)
REM --jobs=%NUMBER_OF_PROCESSORS%: Use multiple jobs to speed up compilation
REM --lto=yes: Link Time Optimization (smaller binary, faster execution)
REM --deployment: Disables safety checks meant for development
REM --python-flag=no_docstrings,no_asserts,-OO: Strip docstrings, asserts, and optimize bytecode
echo ===========================
echo Compilation:
echo.
python -m nuitka ^
  --standalone ^
  --lto=yes ^
  --python-flag=no_docstrings,no_asserts,-OO ^
  --deployment ^
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

:: delete old output folder if exist
if exist "%output_folder_path%" (
    rmdir /s /q "%output_folder_path%"
)

:: move dist folder to root folder and rename
move "%build_folder_path%\%file_name%.dist" "%output_folder_path%" > nul 2>&1

:: print execution duration
call :count_duration "Execution Time:"

:: print end message
echo.
if exist "%output_folder_path%" (
    echo ============================================
    echo [Success] EXE folder created: "%output_folder_path%"
    call :print_size "%output_folder_path%"
    echo ============================================
    echo Run via manually creating a shortcut to "%exe_name%" for execution inside that EXE folder 
    echo or 
    echo run via copying "%local_shortcut_name%" to anywhere for execution inside the destination folder. 
    echo After moving the EXE folder, the former option needs a new manual shortcut, 
    echo while the latter need to be copied again after recreating it via running "%recreate_local_shortcut_name%".
    echo ============================================
    echo.
) else (
    echo ============================================
    echo [Error] Compilation failed^! Check output above.
    echo ============================================
    echo.
    echo Aborting. Press any key to exit
    PAUSE > nul
    exit /b 1
)

:: create "shortcut" that starts relative to its location
> "%output_folder_path%\%local_shortcut_name%" (
    echo @echo off
    echo setlocal
    echo.
    echo call "%output_folder_path%\%exe_name%"
)

:: create: recreate local-workspace-shortcut creator
> "%output_folder_path%\%recreate_local_shortcut_name%" (
    echo @echo off
    echo setlocal
    echo.
    echo ^>  "%local_shortcut_name%" (
    echo    echo @echo off
    echo    echo setlocal
    echo    echo.
    echo    echo call "%%~dp0%exe_name%"
    echo ^)
    echo exit /b 0
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
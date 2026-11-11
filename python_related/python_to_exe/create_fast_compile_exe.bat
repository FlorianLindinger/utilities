@echo off
setlocal enabledelayedexpansion
rem --- Console presentation: NO_COLOR disables ANSI; UTILITIES_QUIET hides headings. ---
set "UTIL_UI_ESC="
set "UTIL_UI_INFO="
set "UTIL_UI_OK="
set "UTIL_UI_WARN="
set "UTIL_UI_ERROR="
set "UTIL_UI_RESET="
if not defined NO_COLOR if /I not "%TERM%"=="dumb" for /F "delims=#" %%E in ('"prompt #$E# & for %%E in (1) do rem"') do set "UTIL_UI_ESC=%%E"
if defined UTIL_UI_ESC set "UTIL_UI_INFO=%UTIL_UI_ESC%[96m"
if defined UTIL_UI_ESC set "UTIL_UI_OK=%UTIL_UI_ESC%[92m"
if defined UTIL_UI_ESC set "UTIL_UI_WARN=%UTIL_UI_ESC%[93m"
if defined UTIL_UI_ESC set "UTIL_UI_ERROR=%UTIL_UI_ESC%[91m"
if defined UTIL_UI_ESC set "UTIL_UI_RESET=%UTIL_UI_ESC%[0m"
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%============================================================%UTIL_UI_RESET%
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%  Create fast compile exe%UTIL_UI_RESET%
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%============================================================%UTIL_UI_RESET%
rem --- End console presentation. ---


:: measure start time
call :count_duration

:: find python file
for %%f in ("*.py") do (
    set "python_file=%%f"
    set "file_name=%%~nf"
    echo:%UTIL_UI_INFO%Compiling with fast compilation: !python_file!%UTIL_UI_RESET%
    echo.
    goto :found
)
:found

:: set variables
REM Ending ".py_fast_compile" for delete safey of output_folder_path folder deletion! Do not change it to empty or remove from output_folder_path!
set "ending=.py_fast_compile"
set "output_folder_path=%file_name%%ending%"
set "build_folder_path=%file_name%%ending%.build"
set "exe_name=%file_name%%ending%.exe"
set "local_shortcut_name=%file_name%%ending%_local.bat"
set "recreate_local_shortcut_name=recreate_local_workspace_shortcut.bat"

:: make output folder path absolute
call :set_abs_path "%output_folder_path%" "output_folder_path"

:: install Nuitka and Zstandard
echo:%UTIL_UI_INFO%===========================%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%Installing/Updating Nuitka:%UTIL_UI_RESET%
echo.
python -m pip install nuitka zstandard --upgrade
echo.

:: compile
REM OPTIMIZATION FLAGS FOR FASTEST COMPILATION:
REM --standalone: Create a standalone executable folder (includes all dependencies)
REM --jobs=%NUMBER_OF_PROCESSORS%: Use all available cores for compilation (faster build)
REM --assume-yes-for-downloads: Automatically accept all download prompts
echo:%UTIL_UI_INFO%===========================%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%Compilation:%UTIL_UI_RESET%
echo.
python -m nuitka ^
  --standalone ^
  --deployment ^
  --jobs=%NUMBER_OF_PROCESSORS% ^
  --assume-yes-for-downloads ^
  --output-dir="%build_folder_path%" ^
  --output-filename="%exe_name%" ^
  "%python_file%"
echo.
echo:%UTIL_UI_INFO%===========================%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%Compilation over%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%===========================%UTIL_UI_RESET%
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
    echo:%UTIL_UI_INFO%============================================%UTIL_UI_RESET%
    echo:%UTIL_UI_OK%[Success] EXE folder created: "%output_folder_path%"%UTIL_UI_RESET%
    call :print_size "%output_folder_path%"
    echo:%UTIL_UI_INFO%============================================%UTIL_UI_RESET%
    echo:%UTIL_UI_INFO%Run via manually creating a shortcut to "%exe_name%" for execution inside that EXE folder %UTIL_UI_RESET%
    echo:%UTIL_UI_INFO%or %UTIL_UI_RESET%
    echo:%UTIL_UI_INFO%run via copying "%local_shortcut_name%" to anywhere for execution inside the destination folder. %UTIL_UI_RESET%
    echo:%UTIL_UI_INFO%After moving the EXE folder, the former option needs a new manual shortcut, %UTIL_UI_RESET%
    echo:%UTIL_UI_INFO%while the latter need to be copied again after recreating it via running "%recreate_local_shortcut_name%".%UTIL_UI_RESET%
    echo:%UTIL_UI_INFO%============================================%UTIL_UI_RESET%
    echo.
) else (
    echo:%UTIL_UI_INFO%============================================%UTIL_UI_RESET%
    echo:%UTIL_UI_ERROR%[Error] Compilation failed^! Check output above.%UTIL_UI_RESET%
    echo:%UTIL_UI_INFO%============================================%UTIL_UI_RESET%
    echo.
    echo:%UTIL_UI_ERROR%Aborting. Press any key to exit%UTIL_UI_RESET%
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
echo:%UTIL_UI_WARN%Press any key to exit%UTIL_UI_RESET%
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
    echo:%UTIL_UI_INFO%!text! !SEC!.!CS! s%UTIL_UI_RESET%
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
    echo:%UTIL_UI_INFO%File/Folder not found for size determination: %item_path%%UTIL_UI_RESET%
    exit /b 1
)
if "%~2"=="" ( set "text=Size:"
) else ( set "text=%~2" )
FOR /F "usebackq tokens=*" %%G IN (`powershell -ExecutionPolicy Bypass -Command "$Path = '%item_path%'; $Item = Get-Item -LiteralPath $Path; $1MB = 1048576; $1GB = 1073741824; if ($Item.PSIsContainer) { $B = (Get-ChildItem -Recurse -File -LiteralPath $Path | Measure-Object -Sum Length).Sum; } else { $B = $Item.Length; } if (-not $B) { $B = 0 }; if ($B -ge $1GB) { '{0:N1} GB' -f ($B / $1GB) } elseif ($B -ge $1MB) { '{0:N1} MB' -f ($B / $1MB) } else { '{0:N0} Bytes' -f $B }"`) DO (
    echo:%UTIL_UI_INFO%%text% %%G %UTIL_UI_RESET%
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
        echo:%UTIL_UI_ERROR%[Error] Second argument is missing for :set_abs_path function in "%~f0". (First argument was "%~1"^). %UTIL_UI_RESET%
        echo:%UTIL_UI_ERROR%Aborting. Press any key to exit.%UTIL_UI_RESET%
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
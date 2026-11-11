@echo off & setlocal enabledelayedexpansion
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
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%  Archive: Useful batch functions%UTIL_UI_RESET%
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%============================================================%UTIL_UI_RESET%
rem --- End console presentation. ---

:: ===================
:: ==== Test Area ====
:: ===================

:: PUT TESTS HERE

:: ===================
echo.
echo:%UTIL_UI_WARN%Press any key to exit.%UTIL_UI_RESET%
pause > nul
EXIT /B
:: ===================

:: ====================
:: ==== Functions: ====
:: ====================

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

::::::::::::::::::::::::::::::::::::::::::::::::
:: function that prompts user with prompt=arg1 and sets OUTPUT=1 for y and OUTPUT=0 for n.
::::::::::::::::::::::::::::::::::::::::::::::::
:prompt_user
setlocal
set "ans="
set "OUT="
:ask
set /p "ans=%~1"
if /i "%ans%"=="y" (
    set "OUT=1"
) else if /i "%ans%"=="n" (
    set "OUT=0"
) else (
    echo:%UTIL_UI_INFO%Invalid input. Please enter y or n.%UTIL_UI_RESET%
    goto ask
)
endlocal & set "OUTPUT=%OUT%"
goto :EOF
:: =================================================

::::::::::::::::::::::::::::::::::::::::::::::::
:: function that sets %OUTPUT% to 1 if input is an integer and 0 else
::::::::::::::::::::::::::::::::::::::::::::::::
:is_integer
SET "val=%~1"
ECHO %val% | FINDSTR /R "^[0-9][0-9]*$" >NUL
IF %ERRORLEVEL%==0 (
	SET "OUTPUT=1"
) ELSE (
	SET "OUTPUT=0"
)
GOTO :EOF

:: =================================================

::::::::::::::::::::::::::::::::::::::::::::::::
:: function to call twice to get printed the duration between the two calls. Arg for second call gives the text before print of e.g. "{arg1} 18.2 s" ({arg1} default: "Duration:").
::::::::::::::::::::::::::::::::::::::::::::::::
:count_duration
setlocal enabledelayedexpansion
rem %TIME% ? HH:MM:SScc by removing the comma
set "t=%time:,=%"
set "HH=!t:~0,2!"
set "MM=!t:~3,2!"
set "SS=!t:~6,2!"
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

:: =================================================

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

:: =================================================

::::::::::::::::::::::::::::::::::::::::::::::::
:: function that prints a line of '=' characters above and below the text {arg1}
::::::::::::::::::::::::::::::::::::::::::::::::
:print_wrap
SETLOCAL Enabledelayedexpansion
set "str=%~1"
set "len=0"
:len_loop_pw
if not "!str:~%len%,1!"=="" (
    set /a len+=1
    goto :len_loop_pw
)
set "sep="
for /L %%i in (1,1,%len%) do set "sep=!sep!="
echo:%UTIL_UI_INFO%!sep!%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%!str!%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%!sep!%UTIL_UI_RESET%
ENDLOCAL & GOTO :EOF
@echo off
setlocal EnableExtensions
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
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%  Export synced VS Code profile%UTIL_UI_RESET%
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%============================================================%UTIL_UI_RESET%
rem --- End console presentation. ---

set "SCRIPT=%~dp0helper\export_synced_vscode_profile.py"
if not exist "%SCRIPT%" (
    echo:%UTIL_UI_ERROR%ERROR: Missing helper: "%SCRIPT%"%UTIL_UI_RESET%
    exit /b 2
)
where python >nul 2>nul
if not errorlevel 1 (
    python "%SCRIPT%" %*
) else (
    py -3 "%SCRIPT%" %*
)
set "RESULT=%ERRORLEVEL%"
if "%RESULT%"=="0" (
    echo:%UTIL_UI_OK%[OK] Export completed.%UTIL_UI_RESET%
) else (
    >&2 echo:%UTIL_UI_ERROR%[ERROR] Export failed. Exit code: %RESULT%.%UTIL_UI_RESET%
)
if not defined EXPORT_NO_PAUSE pause
exit /b %RESULT%

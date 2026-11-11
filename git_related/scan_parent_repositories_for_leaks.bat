@echo off
setlocal EnableExtensions DisableDelayedExpansion
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
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%  Scan repositories for secrets%UTIL_UI_RESET%
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%============================================================%UTIL_UI_RESET%
rem --- End console presentation. ---


if /i "%~1"=="--help" goto :help
if /i "%~1"=="/?" goto :help
if /i "%~1"=="--no-pause" set "NO_PAUSE=1"
if not "%~1"=="" if not defined NO_PAUSE goto :help_error

set "HELPER=%~dp0helper\scan_parent_repositories_for_leaks.ps1"
if not exist "%HELPER%" (
    echo:%UTIL_UI_ERROR%ERROR: Missing helper: "%HELPER%"%UTIL_UI_RESET%
    exit /b 2
)

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%HELPER%"
set "RESULT=%ERRORLEVEL%"
echo.
if "%RESULT%"=="0" (
    echo:%UTIL_UI_OK%[OK] Gitleaks scan completed. Exit code: 0.%UTIL_UI_RESET%
) else (
    >&2 echo:%UTIL_UI_ERROR%[ERROR] Gitleaks scan returned exit code %RESULT%. Review the report above.%UTIL_UI_RESET%
)
if not defined NO_PAUSE (
    echo:%UTIL_UI_WARN%Press any key to close this window.%UTIL_UI_RESET%
    pause >nul
)
exit /b %RESULT%

:help_error
echo:%UTIL_UI_ERROR%ERROR: Unexpected argument: %~1%UTIL_UI_RESET%
exit /b 2
:help
echo:%UTIL_UI_WARN%Usage: %~nx0 [--no-pause]%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%Scans current files and Git history below the parent folder of utilities.%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%Findings print to the console with secret values redacted.%UTIL_UI_RESET%
exit /b 0

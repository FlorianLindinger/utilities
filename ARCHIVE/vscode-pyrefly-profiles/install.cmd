@echo off
setlocal
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
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%  Archive: Install Pyrefly profiles%UTIL_UI_RESET%
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%============================================================%UTIL_UI_RESET%
rem --- End console presentation. ---

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "taskInstallExitCode=%errorlevel%"
echo.
if "%taskInstallExitCode%"=="0" (
    echo:%UTIL_UI_OK%[OK] Pyrefly installer completed.%UTIL_UI_RESET%
) else (
    echo:%UTIL_UI_ERROR%[ERROR] Pyrefly installer exited with code %taskInstallExitCode%.%UTIL_UI_RESET%
    echo:%UTIL_UI_WARN%Review the error details above.%UTIL_UI_RESET%
)
echo.
echo:%UTIL_UI_WARN%Press any key to close this installer . . .%UTIL_UI_RESET%
pause >nul
exit /b %taskInstallExitCode%

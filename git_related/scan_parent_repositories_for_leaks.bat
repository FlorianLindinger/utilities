@echo off
setlocal EnableExtensions DisableDelayedExpansion

if /i "%~1"=="--help" goto :help
if /i "%~1"=="/?" goto :help
if /i "%~1"=="--no-pause" set "NO_PAUSE=1"
if not "%~1"=="" if not defined NO_PAUSE goto :help_error

set "HELPER=%~dp0helper\scan_parent_repositories_for_leaks.ps1"
if not exist "%HELPER%" (
    echo ERROR: Missing helper: "%HELPER%"
    exit /b 2
)

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%HELPER%"
set "RESULT=%ERRORLEVEL%"
echo.
echo Gitleaks scan finished with exit code %RESULT%.
if not defined NO_PAUSE (
    echo Press any key to close this window.
    pause >nul
)
exit /b %RESULT%

:help_error
echo ERROR: Unexpected argument: %~1
exit /b 2
:help
echo Usage: %~nx0 [--no-pause]
echo Scans current files and Git history below the parent folder of utilities.
echo Findings print to the console with secret values redacted.
exit /b 0

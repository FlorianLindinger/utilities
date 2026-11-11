@echo off
setlocal EnableExtensions
set "SCRIPT=%~dp0helper\export_synced_vscode_profile.py"
if not exist "%SCRIPT%" (
    echo ERROR: Missing helper: "%SCRIPT%"
    exit /b 2
)
where python >nul 2>nul
if not errorlevel 1 (
    python "%SCRIPT%" %*
) else (
    py -3 "%SCRIPT%" %*
)
set "RESULT=%ERRORLEVEL%"
if not defined EXPORT_NO_PAUSE pause
exit /b %RESULT%

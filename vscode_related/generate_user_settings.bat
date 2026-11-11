@echo off
setlocal EnableExtensions
REM Export only synced user settings to output\user_settings.json.
REM Requires Python 3 on PATH, or the Windows py launcher. No extra packages.
REM Optional: --profile "Profile Name", --workspace PATH, --user-data-dir PATH.
set "SCRIPT=%~dp0helper\export_user_settings.py"
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

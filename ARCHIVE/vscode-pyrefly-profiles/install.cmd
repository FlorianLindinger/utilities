@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "taskInstallExitCode=%errorlevel%"
echo.
if "%taskInstallExitCode%"=="0" (
    echo SUCCESS: Pyrefly installer completed.
) else (
    echo FAILED: Pyrefly installer exited with code %taskInstallExitCode%.
    echo Review the error details above.
)
echo.
echo Press any key to close this installer . . .
pause >nul
exit /b %taskInstallExitCode%

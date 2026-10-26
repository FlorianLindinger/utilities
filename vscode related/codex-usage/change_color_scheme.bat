@echo off
setlocal DisableDelayedExpansion
set "extension_dir=%USERPROFILE%\.vscode\extensions\ganymede404.vscode-codex-usage-0.2.4"
if not "%~1"=="" set "extension_dir=%~1"
set "manifest=%extension_dir%\package.json"
set "target=%extension_dir%\out\statusBar.js"
set "source=%~dp0statusBar.js"
if not exist "%manifest%" (
    echo ERROR: Extension package.json not found in "%extension_dir%".
    exit /b 1
)
findstr /L /C:"\"publisher\": \"ganymede404\"" "%manifest%" >nul
if errorlevel 1 goto incompatible
findstr /L /C:"\"name\": \"vscode-codex-usage\"" "%manifest%" >nul
if errorlevel 1 goto incompatible
findstr /L /C:"\"version\": \"0.2.4\"" "%manifest%" >nul
if errorlevel 1 goto incompatible
if not exist "%source%" (
    echo ERROR: Custom statusBar.js not found beside this batch file.
    exit /b 1
)
if not exist "%target%" (
    echo ERROR: Installed out\statusBar.js not found.
    exit /b 1
)
if not exist "%target%.before-custom-colors" (
    copy /Y "%target%" "%target%.before-custom-colors" >nul
    if errorlevel 1 exit /b 1
)
copy /Y "%source%" "%target%" >nul
if errorlevel 1 exit /b 1
echo Restored custom colors. Run Developer: Reload Window in VS Code.
exit /b 0

:incompatible
echo ERROR: This backup supports ganymede404.vscode-codex-usage version 0.2.4 only.
echo Review and port the customization before applying it to another version.
exit /b 1

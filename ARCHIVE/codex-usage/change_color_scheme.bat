@echo off
setlocal DisableDelayedExpansion
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
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%  Archive: Change color scheme%UTIL_UI_RESET%
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%============================================================%UTIL_UI_RESET%
rem --- End console presentation. ---

set "extension_dir=%USERPROFILE%\.vscode\extensions\ganymede404.vscode-codex-usage-0.2.4"
if not "%~1"=="" set "extension_dir=%~1"
set "manifest=%extension_dir%\package.json"
set "target=%extension_dir%\out\statusBar.js"
set "source=%~dp0statusBar.js"
if not exist "%manifest%" (
    echo:%UTIL_UI_ERROR%ERROR: Extension package.json not found in "%extension_dir%".%UTIL_UI_RESET%
    exit /b 1
)
findstr /L /C:"\"publisher\": \"ganymede404\"" "%manifest%" >nul
if errorlevel 1 goto incompatible
findstr /L /C:"\"name\": \"vscode-codex-usage\"" "%manifest%" >nul
if errorlevel 1 goto incompatible
findstr /L /C:"\"version\": \"0.2.4\"" "%manifest%" >nul
if errorlevel 1 goto incompatible
if not exist "%source%" (
    echo:%UTIL_UI_ERROR%ERROR: Custom statusBar.js not found beside this batch file.%UTIL_UI_RESET%
    exit /b 1
)
if not exist "%target%" (
    echo:%UTIL_UI_ERROR%ERROR: Installed out\statusBar.js not found.%UTIL_UI_RESET%
    exit /b 1
)
if not exist "%target%.before-custom-colors" (
    copy /Y "%target%" "%target%.before-custom-colors" >nul
    if errorlevel 1 exit /b 1
)
copy /Y "%source%" "%target%" >nul
if errorlevel 1 exit /b 1
echo:%UTIL_UI_OK%Restored custom colors. Run Developer: Reload Window in VS Code.%UTIL_UI_RESET%
exit /b 0

:incompatible
echo:%UTIL_UI_ERROR%ERROR: This backup supports ganymede404.vscode-codex-usage version 0.2.4 only.%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%Review and port the customization before applying it to another version.%UTIL_UI_RESET%
exit /b 1

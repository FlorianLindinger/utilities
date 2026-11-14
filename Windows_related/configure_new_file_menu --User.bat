@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ==================================================
rem Configures the Explorer "New" context menu.
rem The "--User" and "--All Users" versions are identical except for SCOPE.
rem ==================================================

rem ==================================================
rem SETTINGS
rem ==================================================

rem ALL  = all users (asks for Administrator rights)
rem USER = current user
set "SCOPE=USER"

rem ---------------- FILE TYPES ---------------------
rem 1 = show in the New menu, 0 = remove from it.
rem Any other value leaves the entry untouched.

set "NEW_TXT=1"
set "NEW_BAT=1"
set "NEW_PY=1"
set "NEW_IPYNB=1"
set "NEW_GITIGNORE=1"
set "NEW_TOML=1"
set "NEW_JSON=1"
set "NEW_MD=0"
set "NEW_BMP=0"
set "NEW_WIBU=0"
set "NEW_ACCESS=0"
set "NEW_OPENDOCUMENT=0"
set "NEW_PUBLISHER=0"
set "NEW_GOOGLE=0"
set "NEW_RTF=0"

rem "File": creates a file without extension
set "NEW_NO_EXTENSION=1"

rem ---------------- SEARCH REGISTRY ----------------
set "SEARCH_BITMAP=1"
set "SEARCH_WIBU=1"

rem 0 = report matching keys only
rem 1 = delete matching keys after backup
set "DELETE_DISCOVERED=0"

rem ---------------- GENERAL SETTINGS ---------------
set "CREATE_BACKUPS=1"
set "RESTART_EXPLORER=1"

rem ==================================================
rem INITIALIZATION
rem ==================================================

if /i "%SCOPE%"=="ALL" (
    fltmc >nul 2>&1
    if errorlevel 1 (
        rem Wait for the elevated copy, then restart Explorer from this
        rem non-elevated window so the desktop shell keeps normal rights.
        echo Requesting Administrator rights...
        powershell.exe -NoProfile -Command "$p = Start-Process -FilePath '%~f0' -ArgumentList '/elevated' -Verb RunAs -Wait -PassThru; exit $p.ExitCode" >nul 2>&1
        if errorlevel 1 (
            echo ERROR: Administrator rights were denied or the configuration failed.
            pause
            exit /b 1
        )
        call :restart_explorer
        exit /b 0
    )
    set "REG=HKLM\SOFTWARE\Classes"
    set "PSROOT=Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes"
    set "TEMPLATE=%SystemRoot%\ShellNew"
    rem Writes go to HKLM, so existing associations are checked there too.
    set "ASSOC_REG=HKLM\SOFTWARE\Classes"
) else (
    set "REG=HKCU\Software\Classes"
    set "PSROOT=Registry::HKEY_CURRENT_USER\Software\Classes"
    set "TEMPLATE=%LOCALAPPDATA%\ShellNew"
    rem Check the merged HKCR view: a ProgID written to HKCU would override an
    rem association that only exists in HKLM and break opening those files.
    set "ASSOC_REG=HKCR"
)

set "BACKUP=%USERPROFILE%\ShellNew_Backup"

if not exist "%BACKUP%" mkdir "%BACKUP%"
if not exist "%TEMPLATE%" mkdir "%TEMPLATE%"

echo ================================================
echo Windows New Menu Configuration
echo Scope: %SCOPE%
echo ================================================
echo.

rem ==================================================
rem FILE TYPES
rem ==================================================

rem An empty .ipynb is not valid notebook JSON; Jupyter refuses to open it.
> "%TEMPLATE%\ipynb-template.ipynb" echo {"cells": [], "metadata": {}, "nbformat": 4, "nbformat_minor": 5}

(
    echo # Python
    echo __pycache__/
    echo *.py[cod]
    echo .venv/
    echo.
    echo # Jupyter
    echo .ipynb_checkpoints/
    echo.
    echo # Environment
    echo .env
) > "%TEMPLATE%\gitignore-template.txt"

call :settype "%NEW_PY%" .py "Python File"
call :settype "%NEW_IPYNB%" .ipynb "Jupyter Notebook" "%TEMPLATE%\ipynb-template.ipynb"
call :settype "%NEW_TOML%" .toml "TOML File"
call :settype "%NEW_JSON%" .json "JSON File"
call :settype "%NEW_GITIGNORE%" .gitignore "Git Ignore File" "%TEMPLATE%\gitignore-template.txt"
call :settype "%NEW_MD%" .md "Markdown Document"

rem The "." class is the one Windows uses for files without extension.
rem Explorer creates "New File." and Win32 drops the trailing dot.
call :settype "%NEW_NO_EXTENSION%" . "File"

rem Earlier versions added a separate "New Empty File" menu entry instead.
call :remove_legacy_noext

rem ---------------- ENTRIES FROM OTHER PROGRAMS ----

if "%NEW_BMP%"=="0" (
    call :remove .bmp
    call :note_packaged_shellnew Microsoft.Paint Bitmap
)

rem CodeMeter registers "WIBU Control File" for .wbc
if "%NEW_WIBU%"=="0" call :remove .wbc

if "%NEW_ACCESS%"=="0" (
    call :remove .accdb
    call :remove .mdb
)

if "%NEW_OPENDOCUMENT%"=="0" (
    call :remove .odg
    call :remove .odp
    call :remove .ods
    call :remove .odt
)

if "%NEW_PUBLISHER%"=="0" call :remove .pub

if "%NEW_GOOGLE%"=="0" (
    call :remove .gdoc
    call :remove .gsheet
    call :remove .gslides
)

if "%NEW_RTF%"=="0" call :remove .rtf
if "%NEW_TXT%"=="0" call :remove .txt
if "%NEW_BAT%"=="0" call :remove .bat

rem ==================================================
rem SEARCH ADDITIONAL SHELLNEW REGISTRATIONS
rem ==================================================

if "%SEARCH_BITMAP%"=="1" call :searchkeys bmp bitmap paint

if "%SEARCH_WIBU%"=="1" call :searchkeys wibu codemeter

rem ==================================================
rem FINISH
rem ==================================================

echo.
echo ================================================
echo Configuration completed.
echo ================================================

if /i not "%SCOPE%"=="ALL" (
    call :restart_explorer
    echo.
    echo Done.
    exit /b 0
)

rem Restarting Explorer from this elevated window would run the desktop shell
rem with Administrator rights. When started by the non-elevated window, that
rem window does the restart; when started directly as admin, ask the user.
echo.
if /i "%~1"=="/elevated" (
    echo Press any key to close this window and continue in the original one...
    pause >nul
) else (
    if "%RESTART_EXPLORER%"=="1" (
        echo Restart Windows Explorer or sign out to apply the changes:
        echo Task Manager - Windows Explorer - Restart
        echo.
    )
    echo Done.
    pause
)
exit /b 0

rem ==================================================
rem FUNCTIONS
rem ==================================================

rem Must run without elevation; see the comments at the call sites.
:restart_explorer
if not "%RESTART_EXPLORER%"=="1" exit /b

echo.
echo Press any key to restart Windows Explorer...
pause >nul

taskkill /f /im explorer.exe >nul 2>&1
start "" explorer.exe
exit /b

rem :settype <1 or 0> <.ext> <description> [template file]
rem 1 adds the entry, 0 removes it; anything else does nothing.
:settype
if "%~1"=="1" call :addtype "%~2" "%~3" "%~4"
if "%~1"=="0" call :remove "%~2"
exit /b

rem :addtype <.ext> <description> [template file]
rem Without a template file Explorer creates an empty file.
:addtype
set "EXT=%~1"
set "DESC=%~2"
set "TEMPLATE_FILE=%~3"

echo Adding %DESC% [%EXT%]...

call :backup "%EXT%"

rem Preserve an existing default file association. "reg query /ve" also
rem succeeds for an empty default value, so require text after the type.
reg query "%ASSOC_REG%\%EXT%" /ve 2>nul | findstr /r /c:"REG_[A-Z_]*  *[^ ]" >nul

if errorlevel 1 (
    set "PROGID=Custom.NewFile%EXT%"
    if "%EXT%"=="." set "PROGID=Custom.NewFile.NoExtension"
    reg add "%REG%\%EXT%" /ve /d "!PROGID!" /f >nul
    reg add "%REG%\!PROGID!" /ve /d "%DESC%" /f >nul
)

rem Remove the other ShellNew variant so reruns can switch between them.
if defined TEMPLATE_FILE (
    reg delete "%REG%\%EXT%\ShellNew" /v "NullFile" /f >nul 2>&1
    reg add "%REG%\%EXT%\ShellNew" /v "FileName" /t REG_SZ /d "%TEMPLATE_FILE%" /f >nul
) else (
    reg delete "%REG%\%EXT%\ShellNew" /v "FileName" /f >nul 2>&1
    reg add "%REG%\%EXT%\ShellNew" /v "NullFile" /t REG_SZ /d "" /f >nul
)
exit /b

rem :remove <.ext>
rem ShellNew can sit directly below the extension (.bmp\ShellNew) or below a
rem ProgID subkey (.accdb\Access.Application.16\ShellNew), so delete every
rem ShellNew key found below the extension.
:remove
set "EXT=%~1"

echo Removing %EXT%...

call :backup "%EXT%"

for /f "delims=" %%K in ('reg query "%REG%\%EXT%" /s /k /f ShellNew /e 2^>nul ^| findstr /b /i "HKEY_"') do (
    reg delete "%%K" /f >nul 2>&1
    if errorlevel 1 (
        echo   WARNING: Could not remove %%K
    ) else (
        echo   Removed: %%K
    )
)

rem Per-user keys cannot hide entries registered for all users.
if /i not "%SCOPE%"=="ALL" (
    reg query "HKLM\SOFTWARE\Classes\%EXT%" /s /k /f ShellNew /e 2>nul | findstr /b /i "HKEY_" >nul
    if not errorlevel 1 echo   NOTE: %EXT% is registered for all users. Use the All Users version to remove it.
)
exit /b

:backup
if not "%CREATE_BACKUPS%"=="1" exit /b

set "BACKUP_KEY=%~1"
set "SAFE=%BACKUP_KEY:.=%"
if not defined SAFE set "SAFE=noextension"
set "DEST=%BACKUP%\%SCOPE%_%SAFE%.reg"

if not exist "%DEST%" (
    reg export "%REG%\%BACKUP_KEY%" "%DEST%" /y >nul 2>&1
)
exit /b

:searchkeys
setlocal

set "SHELLNEW_ROOT=%PSROOT%"
set "SHELLNEW_BACKUP=%BACKUP%"
set "SHELLNEW_DELETE=%DELETE_DISCOVERED%"
set "SHELLNEW_TERMS=%*"

echo.
echo Searching for ShellNew keys matching: %*

rem Explorer only reads <ext>\ShellNew and <ext>\<ProgID>\ShellNew, so a
rem depth of 2 is enough and avoids crawling CLSID, Interface, etc.
rem Values are matched too: e.g. WIBU's key is .wbc\ShellNew and only its
rem Command value mentions WIBU.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=$env:SHELLNEW_ROOT;" ^
  "$terms=$env:SHELLNEW_TERMS -split ' ';" ^
  "$delete=$env:SHELLNEW_DELETE -eq '1';" ^
  "$backup=$env:SHELLNEW_BACKUP;" ^
  "$keys=Get-ChildItem -LiteralPath $root -Recurse -Depth 2 -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -eq 'ShellNew' } | Where-Object { $key=$_; $text=$key.Name + ' ' + (@($key.GetValueNames() | ForEach-Object { [string]$key.GetValue($_) }) -join ' '); @($terms | Where-Object { $text -match [regex]::Escape($_) }).Count -gt 0 };" ^
  "foreach($k in $keys) {" ^
  "  Write-Host ('Found: ' + $k.Name);" ^
  "  if($delete) {" ^
  "    $file=Join-Path $backup ('discovered_' + [guid]::NewGuid().ToString() + '.reg');" ^
  "    reg export $k.Name $file /y | Out-Null;" ^
  "    if($LASTEXITCODE -eq 0) {" ^
  "      Remove-Item -LiteralPath $k.PSPath -Recurse -Force -ErrorAction Stop;" ^
  "      Write-Host ('Removed: ' + $k.Name);" ^
  "    }" ^
  "  }" ^
  "}"

set "RESULT=%ERRORLEVEL%"
endlocal & exit /b %RESULT%

rem :note_packaged_shellnew <package name> <entry name>
rem Explains entries that come from a Store app manifest (uap4:ShellNewFileName).
:note_packaged_shellnew
powershell.exe -NoProfile -Command "$found = @(Get-AppxPackage -Name '%~1' | Where-Object { Select-String -LiteralPath (Join-Path $_.InstallLocation 'AppxManifest.xml') -Pattern 'ShellNewFileName' -Quiet }); if ($found.Count -gt 0) { exit 0 } else { exit 1 }" >nul 2>&1
if not errorlevel 1 echo   NOTE: The %~2 entry comes from the %~1 app package and cannot be removed through the registry.
exit /b

:remove_legacy_noext
set "NOEXT_ROOT=%REG%\Directory\Background\shell\NewEmptyFile"

reg query "%NOEXT_ROOT%" >nul 2>&1
if errorlevel 1 exit /b

echo Removing old New Empty File menu entry...
reg delete "%NOEXT_ROOT%" /f >nul 2>&1
if exist "%TEMPLATE%\NewEmptyFile.ps1" del "%TEMPLATE%\NewEmptyFile.ps1"
exit /b

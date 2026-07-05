:: =================================================
:: Usage: 
::  make_shortcut.bat "<name>" "<target>" "<target-args>" "<working-dir>" "<icon-path>" "<description>"
:: Add " inside an arg as a ^".
:: =================================================

:: turn off printing of command and make variables local
@echo off & setlocal

:: get call arguments
set "NAME=%~1"
set "TARGET=%~2"
set "ARGS=%~3"
set "WDIR=%~4"
set "ICON=%~5"
set "DESC=%~6"

:: replace ^" with " in ARGS (^" needed to have " inside an arg). Second replacement needed in case of call of this script because batch is weird
set "ARGS=%ARGS:^"="%"
set "ARGS=%ARGS:^"="%"

:: print USAGE if no arg given
if "%~1"=="" (
    echo Usage: %~nx0 "name" "target" "args" "working_dir" "icon_path" "description"
    exit /b 1
)

:: make paths absolute
call :make_absolute_path_if_relative "%NAME%"
set "NAME=%output%"
call :make_absolute_path_if_relative "%TARGET%"
set "TARGET=%output%"
call :make_absolute_path_if_relative "%WDIR%"
set "WDIR=%output%"
call :make_absolute_path_if_relative "%ICON%"
set "ICON=%output%"

:: strip accidental .lnk from NAME so we control extension
if /i "%NAME:~-4%"==".lnk" set "NAME=%NAME:~0,-4%"

:: make link directory if not existing
for %%D in ("%NAME%") do mkdir "%%~dpD" >nul 2>&1

:: add shortcut ending
set "LINK=%NAME%.lnk"

:: create shortcut
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ws=New-Object -ComObject WScript.Shell;" ^
  "$lnk=$ws.CreateShortcut($env:LINK);" ^
  "$lnk.TargetPath=$env:TARGET;" ^
  "$lnk.Arguments=$env:ARGS;" ^
  "$lnk.WorkingDirectory=$env:WDIR;" ^
  "$lnk.IconLocation=$env:ICON+',0';" ^
  "$lnk.Description=$env:DESC;" ^
  "$lnk.Save()"

:: test if shortcut was created and exit
if not exist "%LINK%" (
    exit /b 2
) else (
    EXIT /B 0
)

:: ====================
:: ==== Functions: ====
:: ====================

:: =================================================
:: function that makes relative path (relative to current working directory) to :: absolute if not already. Works for empty path (relative) path:
:: Usage:
::    call :make_absolute_path_if_relative "%some_path%"
::    set "abs_path=%output%"
:: =================================================
:make_absolute_path_if_relative
    if "%~1"=="" (
        set "OUTPUT=%CD%"
    ) else (
	    set "OUTPUT=%~f1"
    )
goto :EOF
:: =================================================
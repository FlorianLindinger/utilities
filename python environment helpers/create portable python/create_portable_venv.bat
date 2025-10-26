@echo off
setlocal

:: set default arg if not given
set "python_folder=%~1"
if "%python_folder%"=="" (
    set "python_folder=portable_python"
)

:: add trailing \ if missing
if not "%python_folder:~-1%"=="\" set "python_folder=%python_folder%\"

:: === [start] delete old venv ===

:: define venv name (carefull because it will be deleted)
set "venv_path=virtual_environment"
call :make_absolute_path_if_relative "%venv_path%"
set "venv_path=%output%"

:: Skip if folder doesn't exist
if not exist "%venv_path%\" (
    goto :skip_delete_old_venv 
)

:: Check for Python venv markers
if not exist "%venv_path%\Scripts\activate.bat" (
    echo: [Error] folder "%venv_path%" does not appear to be a Python virtual environment. Delete manually after confirming. Aborting. Press any key to exit.
    pause > nul
    exit /b 1
)

:: delete folder
rmdir /s /q "%venv_path%"
if exist "%venv_path%\" (
    echo: [Error] Failed to delete "%venv_path%". Delete manually after confirming. Aborting. Press any key to exit.
    pause > nul
    exit /b 1
) else (
    echo: Deleted old virtual environment.
)

:skip_delete_old_venv
:: === [end] delete old venv ===

:: check if python exists
if not exist "%python_folder%python.exe" (
    echo: [Error]"%python_folder%python.exe" does not exist. Aborting. Press any key to exit.
    pause > NUL
    exit /b 1
)

:: create venv
"%python_folder%python.exe" -m venv "%venv_path%"
if errorlevel 1 (
    echo: [Error] venv creation failed. Aborting. Press any key to exit.
    pause > NUL
    exit /b 1
)

:: upgrade pip
"%venv_path%\Scripts\python.exe" -m pip install --upgrade pip >nul 2>&1
if errorlevel 1 (
    echo [Warning] pip upgrade failed.
)

:: ================================================
:: create python.bat file that repairs paths if folder moved

>"%venv_path%\python.bat" (
echo(@echo off
echo(setlocal
echo(
echo(:: ================================================
echo(:: check if portable virtual environment was moved and repair pyvenv.cfg in that case
echo(
echo(:: compute paths relative to this file
echo(set "ROOT=%%~dp0"
echo(if "%%ROOT:~-1%%"=="\" set "ROOT=%%ROOT:~0,-1%%"
echo(set "VENV=%%ROOT%%"
echo(set "BASE=..\%python_folder%"
echo(call :make_absolute_path_if_relative "%%BASE%%"
echo(set "BASE=%%OUTPUT%%"
echo(
echo(:: check if "home" in pyvenv.cfg is correct and replace if not
echo(for /f "tokens=1,* delims==" %%%%A in ('findstr /I /C:"home =" "%%VENV%%\pyvenv.cfg" 2^^^>nul'^) do (
echo(  for /f "tokens=* delims= " %%%%Z in ("%%%%B"^) do set "CURRENT_HOME=%%%%~Z"
echo(^)
echo(if /I "%%CURRENT_HOME%%"=="%%BASE%%" (
echo(    goto :skip_replace
echo(^)
echo(powershell -NoProfile -Command "$cfg='%%VENV%%\pyvenv.cfg'; $newHome=(Resolve-Path '%%BASE%%').Path; $txt=Get-Content -Raw $cfg; if($txt -match '(?m)^home\s*='){ $txt=[regex]::Replace($txt,'(?m)^(home\s*=\s*).+$','${1}'+$newHome) } else { $nl=if($txt -and $txt[-1]-ne [char]10){[environment]::NewLine}else{''}; $txt+=$nl+'home = '+$newHome+[environment]::NewLine }; Set-Content -Encoding UTF8 -NoNewline -Path $cfg -Value $txt"
echo(:skip_replace
echo(:: ================================================
echo(
echo(:: run your command using the venv Python
echo(if "%%~1"=="" (
echo(  "%%VENV%%\Scripts\python.exe"
echo(^) else (
echo(  if /i "%%~1"=="-m" (
echo(    "%%VENV%%\Scripts\python.exe" %%*
echo(  ^) else (
echo(    "%%VENV%%\Scripts\python.exe" "%%~1" %%*
echo(  ^)
echo(^)
echo(
echo(:: return
echo(endlocal ^& exit /b %%ERRORLEVEL%%
echo(
echo(:: ================================================
echo(:make_absolute_path_if_relative
echo(    if "%%~1"=="" (
echo(        set "OUTPUT=%%CD%%"
echo(    ^) else (
echo(	    set "OUTPUT=%%~f1"
echo(    ^)
echo(	goto :EOF
echo(:: ================================================
)
:: check if python.bat file was create
if not exist "%venv_path%\python.bat" (
    ECHO: [Error] Failed to create "%venv_path%\python.bat" (see above^). Aborting. Press any key to exit.
    pause > NUL
    exit /b 2
)
:: ================================================

echo: Finished creation of portable virtual environment.

exit /b

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
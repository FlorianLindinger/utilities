:: Usage:
:: create_portable_venv.bat "<target_dir>" "<python_folder>"
::
:: Args (all optional):
::   <target_dir>: Destination directory. The script creates "<target_dir>\virtual_environment". Default: current working directory.
::   <python_folder>: Path to the portable Python runtime containing python.exe. Accepts relative or absolute. Default: "portable_python".

:: =======================
:: ==== Program Start ====
:: =======================

:: dont print commands & make variables local
@echo off
setlocal

:: process args
set "TARGET_DIR=%~1"
set "PYTHON_FOLDER=%~2"

:: set default arg if not given
if "%PYTHON_FOLDER%"=="" (
    set "PYTHON_FOLDER=portable_python"
)

:: make path absolute
call :make_absolute_path_if_relative "%TARGET_DIR%"
set "TARGET_DIR=%output%"

:: add "virtual_environment" for delete safety 
set "venv_path=%TARGET_DIR%\virtual_environment"

:: make path absolute
call :make_absolute_path_if_relative "%PYTHON_FOLDER%"
set "PYTHON_FOLDER=%output%"

:: === [start] delete old venv ===============

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
:: === [end] delete old venv ===============

:: check if python exists
if not exist "%PYTHON_FOLDER%\python.exe" (
    echo: [Error]"%PYTHON_FOLDER%\python.exe" does not exist. Aborting. Press any key to exit.
    pause > NUL
    exit /b 1
)

:: create venv parent folder if missing
mkdir "%TARGET_DIR%" >nul 2>&1

:: create venv
echo: Creating virtual environment "%venv_path%"
"%PYTHON_FOLDER%\python.exe" -m venv "%venv_path%"
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

:: create python.bat file that repairs paths if folder moved
>"%venv_path%\python.bat" (
echo(@echo off
echo(setlocal
echo(
echo(:: get folder of this file with \ at end
echo(set "VENV_FOLDER=%%~dp0"
echo(
echo(:: get where python exe should be 
echo(set "python_exe_folder=%%VENV_FOLDER%%..\portable_python"
echo(:: compute paths relative to this file
echo(call :make_absolute_path_if_relative "%%python_exe_folder%%"
echo(set "python_exe_folder=%%OUTPUT%%"
echo(
echo(:: ================================================
echo(:: check if portable virtual environment was moved and repair pyvenv.cfg in that case
echo(
echo(:: check if "home" setting in pyvenv.cfg is correct and replace if not
echo(for /f "tokens=1,* delims==" %%%%A in ('findstr /I /C:"home =" "%%VENV_FOLDER%%pyvenv.cfg" 2^^^>nul'^) do (
echo(  for /f "tokens=* delims= " %%%%Z in ("%%%%B"^) do set "CURRENT_HOME=%%%%~Z"
echo(^)
echo(if /I "%%CURRENT_HOME%%"=="%%python_exe_folder%%" (
echo(    goto :skip_replace
echo(^)
echo(powershell -NoProfile -Command "$cfg='%%VENV_FOLDER%%pyvenv.cfg'; $newHome=(Resolve-Path '%%python_exe_folder%%').Path; $txt=Get-Content -Raw $cfg; if($txt -match '(?m)^home\s*='){ $txt=[regex]::Replace($txt,'(?m)^(home\s*=\s*).+$','${1}'+$newHome) } else { $nl=if($txt -and $txt[-1]-ne [char]10){[environment]::NewLine}else{''}; $txt+=$nl+'home = '+$newHome+[environment]::NewLine }; Set-Content -Encoding UTF8 -NoNewline -Path $cfg -Value $txt"
echo(:skip_replace
echo(:: ================================================
echo(
echo(:: run your command using the venv Python
echo(if "%%~1"=="" (
echo(  "%%VENV_FOLDER%%Scripts\python.exe"
echo(^) else (
echo(  if /i "%%~1"=="-m" (
echo(    "%%VENV_FOLDER%%Scripts\python.exe" %%*
echo(  ^) else (
echo(    "%%VENV_FOLDER%%Scripts\python.exe" "%%~1" %%*
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
:: check if python.bat file was created
if not exist "%venv_path%\python.bat" (
    ECHO: [Error] Failed to create "%venv_path%\python.bat" (see above^). Aborting. Press any key to exit.
    pause > NUL
    exit /b 2
)

:: create activate.bat that works for portable folder:
> "%venv_path%\activate.bat" (
  echo @echo off
  echo.
  echo rem This file is UTF-8 encoded, so we need to update the current code page while executing it
  echo for /f "tokens=2 delims=:." %%%%a in (^'"%%SystemRoot%%\System32\chcp.com"^'^) do (
  echo     set _OLD_CODEPAGE=%%%%a
  echo ^)
  echo if defined _OLD_CODEPAGE (
  echo     "%%SystemRoot%%\System32\chcp.com" 65001 ^> nul
  echo ^)
  echo.
  echo :: portable venv path
  echo set "VIRTUAL_ENV=%%~dp0"
  echo.
  echo if not defined PROMPT set PROMPT=$P$G
  echo.
  echo if defined _OLD_VIRTUAL_PROMPT set PROMPT=%%_OLD_VIRTUAL_PROMPT%%
  echo if defined _OLD_VIRTUAL_PYTHONHOME set PYTHONHOME=%%_OLD_VIRTUAL_PYTHONHOME%%
  echo.
  echo set "_OLD_VIRTUAL_PROMPT=%%PROMPT%%"
  echo set "PROMPT=(virtual_environment) %%PROMPT%%"
  echo.
  echo if defined PYTHONHOME set _OLD_VIRTUAL_PYTHONHOME=%%PYTHONHOME%%
  echo set PYTHONHOME=
  echo.
  echo if defined _OLD_VIRTUAL_PATH set PATH=%%_OLD_VIRTUAL_PATH%%
  echo if not defined _OLD_VIRTUAL_PATH set _OLD_VIRTUAL_PATH=%%PATH%%
  echo.
  echo set "PATH=%%VIRTUAL_ENV%%\Scripts;%%PATH%%"
  echo set "VIRTUAL_ENV_PROMPT=virtual_environment"
  echo.
  echo :END
  echo if defined _OLD_CODEPAGE (
  echo     "%%SystemRoot%%\System32\chcp.com" %%_OLD_CODEPAGE%% ^> nul
  echo     set _OLD_CODEPAGE=
  echo ^)
)
:: check if activate.bat file was created
if not exist "%venv_path%\activate.bat" (
    ECHO: [Error] Failed to create "%venv_path%\activate.bat" (see above^). Aborting. Press any key to exit.
    pause > NUL
    exit /b 2
)

:: print success and exit
echo: Sucessfully created portable virtual environment.
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
:: Description:
:: Create a virtual python environment at path "<target_dir>\virt_env" using the portable Python runtime at "<python_folder_rel_path>\python.exe". Should work for Python version 3.5-3.14 and likely later versions when the virtual environment is activated via Script\activate.bat.
::
:: Usage:
:: create_portable_venv.bat "<target_dir>" "<python_folder_rel_path>"
::
:: Args (all optional):
::   <target_dir>: Destination directory. The script creates "<target_dir>\virt_env". Default: current working directory.
::   <python_folder_rel_path>: Relative path to the portable Python runtime containing python.exe. Default: "py_dist".

:: Warning: If you want to use this portable virtual environment in a batch code, you have to use "call python ..." or "call pip ..." in order to correctly return to the calling script. This does not apply to user commands in terminals.

:: =======================
:: ==== Program Start ====
:: =======================

:: dont print commands & make variables local & allow for delayed variable expansion
@echo off & setlocal EnableDelayedExpansion

:: ==================
:: ==== Settings ====
:: ==================

set "fallback_python_folder=py_dist"
set "venv_name=virt_env"
set "venv_portable_scripts_folder_name=portable_Scripts"
SET "tmp_file_path_for_code_execution=%temp%\tmp_relpath.py"


:: ===============
:: ==== Setup ====
:: ===============

:: process args
set "TARGET_DIR=%~1"
set "PYTHON_FOLDER=%~2"

:: set default arg if not given
if "%PYTHON_FOLDER%"=="" (
    set "PYTHON_FOLDER=%fallback_python_folder%"
)

:: make path absolute
call :set_abs_path "%TARGET_DIR%" "TARGET_DIR"

:: add "virt_env" for delete safety 
set "VENV_PATH=%TARGET_DIR%\%venv_name%"

:: make path absolute
call :set_abs_path "%PYTHON_FOLDER%" "PYTHON_FOLDER"

set "portable_scripts_path=%VENV_PATH%\%venv_portable_scripts_folder_name%"

:: find relative path from venv to python folder
REM Create the temporary Python script (using ECHO commands)
> "%tmp_file_path_for_code_execution%" (
    ECHO import os, sys
    ECHO try:
    ECHO     print(os.path.relpath(sys.argv[2], sys.argv[1]^)^)
    ECHO except:
    ECHO     print("ERROR: Check inputs or drive compatibility."^)
)
REM Execute the Python script and capture the output into a Batch variable
FOR /F "delims=" %%L IN ('cmd /c ""%PYTHON_FOLDER%\python.exe" "%tmp_file_path_for_code_execution%" "%VENV_PATH%" "%PYTHON_FOLDER%" 2^>NUL"') DO (
    SET "VENV_TO_PYTHON_REL_PATH=%%L"
)
REM Delete the temporary script
DEL "%tmp_file_path_for_code_execution%" >NUL 2>&1

:: check if python exists
if not exist "%PYTHON_FOLDER%\python.exe" (
    echo: [Error] Relative path (<python_folder_rel_path>^) targets "%PYTHON_FOLDER%\python.exe" which does not exist. Aborting. 
    echo: Usage: create_portable_venv.bat "<target_dir>" "<python_folder_rel_path>"
    echo: Press any key to exit.
    pause > NUL
    exit /b 1
)

:: === [start] delete old venv ===============
REM Skip if folder doesn't exist
if not exist "%VENV_PATH%\" (
    goto :skip_delete_old_venv 
)
REM Check for Python venv markers
if not exist "%VENV_PATH%\Scripts\activate.bat" (
    echo: [Error] folder "%VENV_PATH%" does not appear to be a Python virtual environment. Delete manually after confirming. Aborting. Press any key to exit.
    pause > nul
    exit /b 1
)
REM delete folder
rmdir /s /q "%VENV_PATH%"
if exist "%VENV_PATH%\" (
    echo: [Error] Failed to delete "%VENV_PATH%". Delete manually after confirming. Aborting. Press any key to exit.
    pause > nul
    exit /b 1
) else (
    echo: Deleted old virtual environment.
)
:skip_delete_old_venv
:: === [end] delete old venv ===============

:: create venv parent folder if missing
mkdir "%TARGET_DIR%" >nul 2>&1

:: create venv
echo: Creating virtual environment "%VENV_PATH%"
"%PYTHON_FOLDER%\python.exe" -m venv "%VENV_PATH%"
if errorlevel 1 (
    echo: [Error] venv creation failed. Aborting. Press any key to exit.
    pause > NUL
    exit /b 1
)

:: add folder for portable scripts
mkdir "%portable_scripts_path%" >nul 2>&1

:: add .gitignore to folder to prevent git from syncing of python environment
>> "%VENV_PATH%\.gitignore" (
  echo # Auto added to prevent synchronization of python environment in git by blacklisting everything with wildcard "*"
  echo *
)

:: upgrade pip
"%VENV_PATH%\Scripts\python.exe" -m pip install --upgrade pip >nul 2>&1
if errorlevel 1 (
    echo [Warning] pip upgrade failed.
)

:: create python.bat file that repairs paths if folder moved
>"%portable_scripts_path%\python.bat" (
echo(@echo off & setlocal
echo(
echo(:: get folder of the venv
echo(set "venv_path=%%~dp0.."
echo(
echo(:: get where python exe should be 
echo(set "python_exe_folder=%%venv_path%%\%VENV_TO_PYTHON_REL_PATH%"
echo(:: compute paths relative to this file
echo(call :make_absolute_path_if_relative "%%python_exe_folder%%"
echo(set "python_exe_folder=%%OUTPUT%%"
echo(
echo(:: ================================================
echo(:: check if portable virtual environment was moved and repair pyvenv.cfg in that case
echo(
echo(:: check if "home" setting in pyvenv.cfg is correct and replace if not
echo(for /f "tokens=1,* delims==" %%%%A in ('findstr /I /C:"home =" "%%venv_path%%\pyvenv.cfg" 2^^^>nul'^) do (
echo(  for /f "tokens=* delims= " %%%%Z in ("%%%%B"^) do set "CURRENT_HOME=%%%%~Z"
echo(^)
echo(if /I "%%CURRENT_HOME%%"=="%%python_exe_folder%%" (
echo(    goto :skip_replace
echo(^)
echo(powershell -NoProfile -Command "$cfg='%%venv_path%%\pyvenv.cfg'; $newHome=(Resolve-Path '%%python_exe_folder%%').Path; $txt=Get-Content -Raw $cfg; if($txt -match '(?m)^home\s*='){ $txt=[regex]::Replace($txt,'(?m)^(home\s*=\s*).+$','${1}'+$newHome) } else { $nl=if($txt -and $txt[-1]-ne [char]10){[environment]::NewLine}else{''}; $txt+=$nl+'home = '+$newHome+[environment]::NewLine }; $utf8NoBom=New-Object System.Text.UTF8Encoding $false; [System.IO.File]::WriteAllText($cfg,$txt,$utf8NoBom)"
echo(:skip_replace
echo(:: ================================================
echo(
echo(:: run your command using the venv Python
echo(if "%%~1"=="" (
echo(  "%%venv_path%%\Scripts\python.exe"
echo(^) else (
echo(  "%%venv_path%%\Scripts\python.exe" %%*
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
if not exist "%portable_scripts_path%\python.bat" (
    ECHO: [Error] Failed to create "%portable_scripts_path%\python.bat" (see above^). Aborting. Press any key to exit.
    pause > NUL
    exit /b 2
)

:: replace old activate.bat with new one that works for portable folder (changeing old one because other code might expect activate.bat to be there):
> "%VENV_PATH%\Scripts\activate.bat" (
echo :: The following script is the normal activate.bat file that is created by venv for python 3.13 but with modifications that allow it to work for portable virtual environments as long as the relative path to the python.exe file is the same. The modifications are labeled in the codeb below.
echo.
echo @echo off
echo.
echo rem This file is UTF-8 encoded, so we need to update the current code page while executing it
echo for /f "tokens=2 delims=:." %%%%a in ('"%%SystemRoot%%\System32\chcp.com"'^) do (
echo    set _OLD_CODEPAGE=%%%%a
echo ^)
echo if defined _OLD_CODEPAGE (
echo    "%%SystemRoot%%\System32\chcp.com" 65001 ^> nul
echo ^)
echo.
echo :: Default code: set "VIRTUAL_ENV=path example for default code"
echo :: === Replacement code start ===
echo :: set VIRTUAL_ENV to parent folder of folder of this file
echo set "VIRTUAL_ENV=%%~dp0..\"
echo :: === Replacement code end ===
echo.
echo if not defined PROMPT set PROMPT=$P$G
echo.
echo if defined _OLD_VIRTUAL_PROMPT set PROMPT=%%_OLD_VIRTUAL_PROMPT%%
echo if defined _OLD_VIRTUAL_PYTHONHOME set PYTHONHOME=%%_OLD_VIRTUAL_PYTHONHOME%%
echo.
echo set "_OLD_VIRTUAL_PROMPT=%%PROMPT%%"
echo :: Default code: set "PROMPT=(example virtual environment name) %%PROMPT%%"
echo :: === Replacement code start ===
echo set "PROMPT=(%venv_portable_scripts_folder_name%) %%PROMPT%%"
echo :: === Replacement code end ===
echo.
echo if defined PYTHONHOME set _OLD_VIRTUAL_PYTHONHOME=%%PYTHONHOME%%
echo set PYTHONHOME=
echo.
echo if defined _OLD_VIRTUAL_PATH set PATH=%%_OLD_VIRTUAL_PATH%%
echo if not defined _OLD_VIRTUAL_PATH set _OLD_VIRTUAL_PATH=%%PATH%%
echo.
echo :: Default code: set "PATH=%%VIRTUAL_ENV%%\Scripts;%%PATH%%"
echo :: Default code: set "VIRTUAL_ENV_PROMPT=example virtual environment name"
echo :: === Replacement code start ===
echo set "PATH=%%VIRTUAL_ENV%%\%venv_portable_scripts_folder_name%;%%VIRTUAL_ENV%%\Scripts;%%PATH%%"
echo set "VIRTUAL_ENV_PROMPT=%venv_portable_scripts_folder_name%"
echo :: === Replacement code end ===
echo.
echo :END
echo if defined _OLD_CODEPAGE (
echo    "%%SystemRoot%%\System32\chcp.com" %%_OLD_CODEPAGE%% ^> nul
echo    set _OLD_CODEPAGE=
echo ^)
)
REM check if activate.bat was modified
if errorlevel 1 (
    ECHO: [Error] Failed to modify "%VENV_PATH%\Scripts\activate.bat" (see above^). Aborting. Press any key to continue.
    pause > NUL
    exit /b 2
)

:: create pip.bat such that "pip" command works in activated env after folder move
> "%portable_scripts_path%\pip.bat" (
  echo :: force pip command to use python that works for portable virtual environments
  echo @echo off
  echo "%%~dp0..\python.bat" -m pip %%*
)
:: check if created
if not exist "%portable_scripts_path%\pip.bat" (
    ECHO: [Error] Failed to create "%portable_scripts_path%\pip.bat" (see above^). Aborting. Press any key to continue.
    pause > NUL
)

:: print success and exit
echo: Sucessfully created portable virtual environment.
exit /b 0

:: ====================
:: ==== Functions: ====
:: ====================

::::::::::::::::::::::::::::::::::::::::::::::::
:: function that converts relative (to current working directory) path {arg1} to absolute and sets it to variable {arg2}. Works for empty path {arg1} which then sets the current working directory to variable {arg2}. Raises error if {arg2} is missing:
:: Usage:
::    call :set_abs_path "%some_path%" "some_path"
::::::::::::::::::::::::::::::::::::::::::::::::
:set_abs_path
    if "%~2"=="" (
        echo [Error] Second argument is missing for :set_abs_path function in "%~f0". (First argument was "%~1"^). 
        echo Aborting. Press any key to exit.
        pause > nul
        exit /b 1
    )
    if "%~1"=="" (
        set "%~2=%CD%"
    ) else (
	    set "%~2=%~f1"
    )
goto :EOF
:: =================================================
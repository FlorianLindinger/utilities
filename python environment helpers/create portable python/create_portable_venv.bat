:: Description:
:: Create a virtual python environment at path "<target_dir>\virtual_environment" using the portable Python runtime at "<python_folder_rel_path>\python.exe". Should work for Python version 3.5-3.14 and likely later versions.
::
:: Usage:
:: create_portable_venv.bat "<target_dir>" "<python_folder_rel_path>"
::
:: Args (all optional):
::   <target_dir>: Destination directory. The script creates "<target_dir>\virtual_environment". Default: current working directory.
::   <python_folder_rel_path>: Relative path to the portable Python runtime containing python.exe. Default: "py_dist".

:: =======================
:: ==== Program Start ====
:: =======================

:: dont print commands & make variables local & allow for delayed variable expansion
@echo off & setlocal EnableDelayedExpansion

:: process args
set "TARGET_DIR=%~1"
set "PYTHON_FOLDER=%~2"

:: set default arg if not given
if "%PYTHON_FOLDER%"=="" (
    set "PYTHON_FOLDER=py_dist"
)

:: make path absolute
call :make_absolute_path_if_relative "%TARGET_DIR%"
set "TARGET_DIR=%output%"

:: add "virtual_environment" for delete safety 
set "VENV_PATH=%TARGET_DIR%\virtual_environment"

:: make path absolute
call :make_absolute_path_if_relative "%PYTHON_FOLDER%"
set "PYTHON_FOLDER=%output%"

:: find relative path from venv to python folder
SET "PyScript=temp_relpath.py"
REM Create the temporary Python script (using ECHO commands)
> "%PyScript%" (
    ECHO import os, sys
    ECHO try:
    ECHO     print(os.path.relpath(sys.argv[2], sys.argv[1]^)^)
    ECHO except:
    ECHO     print("ERROR: Check inputs or drive compatibility."^)
)
REM Execute the Python script and capture the output into a Batch variable
FOR /F "delims=" %%L IN ('cmd /c ""%PYTHON_FOLDER%\python.exe" "%PyScript%" "%VENV_PATH%" "%PYTHON_FOLDER%" 2^>NUL"') DO (
    SET "VENV_TO_PYTHON_REL_PATH=%%L"
)
REM Cleanup (Delete the temporary script)
DEL "%PyScript%" >NUL 2>&1

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
>"%VENV_PATH%\python.bat" (
echo(@echo off
echo(setlocal
echo(
echo(:: get folder of this file with \ at end
echo(set "VENV_FOLDER=%%~dp0"
echo(
echo(:: get where python exe should be 
echo(set "python_exe_folder=%%VENV_FOLDER%%%VENV_TO_PYTHON_REL_PATH%"
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
echo(powershell -NoProfile -Command "$cfg='%%VENV_FOLDER%%pyvenv.cfg'; $newHome=(Resolve-Path '%%python_exe_folder%%').Path; $txt=Get-Content -Raw $cfg; if($txt -match '(?m)^home\s*='){ $txt=[regex]::Replace($txt,'(?m)^(home\s*=\s*).+$','${1}'+$newHome) } else { $nl=if($txt -and $txt[-1]-ne [char]10){[environment]::NewLine}else{''}; $txt+=$nl+'home = '+$newHome+[environment]::NewLine }; $utf8NoBom=New-Object System.Text.UTF8Encoding $false; [System.IO.File]::WriteAllText($cfg,$txt,$utf8NoBom)"
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
if not exist "%VENV_PATH%\python.bat" (
    ECHO: [Error] Failed to create "%VENV_PATH%\python.bat" (see above^). Aborting. Press any key to exit.
    pause > NUL
    exit /b 2
)

:: create activate.bat that works for portable folder:
:: create activate.bat that works for portable folder:
> "%VENV_PATH%\activate.bat" (
  echo @echo off
  echo.
  echo :: ---------------------------------------------------------------------
  echo :: UTF-8 ENCODING FIX
  echo :: This block forces the console code page to 65001 ^(UTF-8^) so that
  echo :: paths with special characters display correctly.
  echo :: ---------------------------------------------------------------------
  echo for /f "tokens=2 delims=:." %%%%a in (^'"%%SystemRoot%%\System32\chcp.com"^'^) do (
  echo     set _OLD_CODEPAGE=%%%%a
  echo ^)
  echo if defined _OLD_CODEPAGE (
  echo     "%%SystemRoot%%\System32\chcp.com" 65001 ^> nul
  echo ^)
  echo.
  echo :: ---------------------------------------------------------------------
  echo :: PORTABILITY MAGIC
  echo :: "%%~dp0" gets the directory of THIS script. We use this instead of
  echo :: a hardcoded path so the environment works even if you move the folder.
  echo :: ---------------------------------------------------------------------
  echo set "VIRTUAL_ENV=%%~dp0"
  echo.
  echo if not defined PROMPT set PROMPT=$P$G
  echo.
  echo :: ---------------------------------------------------------------------
  echo :: SAVE OLD STATE
  echo :: We save the current PROMPT, PYTHONHOME, and PATH so we can restore
  echo :: them cleanly when you type 'deactivate'.
  echo :: ---------------------------------------------------------------------
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
  echo :: ---------------------------------------------------------------------
  echo :: ACTIVATE ENVIRONMENT
  echo :: Prepend the 'Scripts' folder to PATH so 'python' and 'pip' run from here.
  echo :: ---------------------------------------------------------------------
  echo set "PATH=%%VIRTUAL_ENV%%\Scripts;%%PATH%%"
  echo set "VIRTUAL_ENV_PROMPT=virtual_environment"
  echo.
  echo :END
  echo :: ---------------------------------------------------------------------
  echo :: RESTORE CODE PAGE
  echo :: Clean up the UTF-8 setting if we changed it.
  echo :: ---------------------------------------------------------------------
  echo if defined _OLD_CODEPAGE (
  echo     "%%SystemRoot%%\System32\chcp.com" %%_OLD_CODEPAGE%% ^> nul
  echo     set _OLD_CODEPAGE=
  echo ^)
)
:: check if activate.bat file was created
if not exist "%VENV_PATH%\activate.bat" (
    ECHO: [Error] Failed to create "%VENV_PATH%\activate.bat" (see above^). Aborting. Press any key to exit.
    pause > NUL
    exit /b 2
)

:: create pip.bat and delete pip.exe such that "pip" command works in activated env after folder move
> "%VENV_PATH%\Scripts\pip.bat" (
  echo @echo off
  echo "%%~dp0..\python.bat" -m pip %%*
)
:: check if created
if not exist "%VENV_PATH%\Scripts\pip.bat" (
    ECHO: [Error] Failed to create "%VENV_PATH%\Scripts\pip.bat" (see above^). Aborting. Press any key to continue.
    pause > NUL
)
REM delete pip.exe
del "%VENV_PATH%\Scripts\pip.exe" > NUL 2>&1

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
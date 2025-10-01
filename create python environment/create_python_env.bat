@setlocal & @echo off & CALL :process_args
:: ########################
:: ### Default Settings ###
:: ########################

:: To define the default vs-code environment, set: @SET "path=%USERPROFILE%\Documents\python_envs\default_env"
SET "def_path=%USERPROFILE%\Documents\python_envs\default_env"
SET "def_version=3"
SET "def_packages=ipykernel numpy matplotlib scipy ipywidgets pyqt5 pandas pillow pyyaml tqdm openpyxl pyarrow html5lib pyserial tifffile py7zr numba pyautogui nptdms pywinauto scipy-stubs cupy-cuda12x nvmath-python"

:: #############################
:: ### Execution starts here ###
:: #############################

:: define undefined args with default settings
IF "%path%"=="" SET "path=%def_path%"
IF "%verion%"=="" SET "version=%def_version%"
IF "%packages%"=="" SET "packages=%def_packages%"

:: convert path to absolute if relative
CALL :make_absolute_path_if_relative "%path%"
SET "path=%OUTPUT%"

:: print settings
echo: --Settings--
echo:
echo: Environment path: %path%
echo: Python version: %version%
echo: Python packages: %packages%
echo:
echo:

:: derive env name from path
for %%F in ("%path%") do set "env_name=%%~nxF"

:: build full paths for shortcuts
set "install_lnk=%USERPROFILE%\Desktop\Install package (%env_name%).lnk"

:: If Python version x.y not found, try to install
py -%version% -c "exit()" >nul 2>&1
IF ERRORLEVEL 1 (
    echo: --Installing Python %version%--
    echo:
    :: Include_launcher=1 sometimes is forbidden by organisation windows settings -> "py" instead of "python"
    winget install --id Python.Python.%version% -e --force --override "InstallAllUsers=0 Include_launcher=0 Include_pip=1 PrependPath=1 /passive /norestart" --accept-source-agreements --accept-package-agreements
    :: check if sucessful install:
    py -%version% -c "exit()" >nul 2>&1 || goto :fail
    echo: --Finished installing Python %version%--
    echo:
) ELSE (
  echo: --Correct python version already installed--
  echo:
)

:: --- create & activate venv ---
py -%version% -m venv "%path%" || goto :fail
call "%path%\Scripts\activate.bat" || goto :fail
echo: --Created and/or activated python environment--
echo:

:: --- package installs ---
echo: --Installing packages--
echo:
python -m pip install --upgrade pip || goto :fail
pip install %packages% || goto :fail
echo: --Finished installing packages--
echo:

:: register the kernel in the system
@REM python -m ipykernel install --prefix "%ProgramData%\jupyter" --name default_env --display-name "%env_name%"
python -m ipykernel install --user --name "%env_name%" --display-name "%env_name%"
echo:
setx JUPYTER_PATH "%PROGRAMDATA%\jupyter;%APPDATA%\jupyter"
echo:

:: --- create folders ---
mkdir "%USERPROFILE%\Documents\Repositories" 

:: create shortcut to install packages in desktop and environment folder
> "%path%\pip_shell.cmd" (
  echo @echo off
  echo call "%%~dp0Scripts\activate.bat"
  echo echo.
  echo echo: Install package into python environment ("%env_name%"^) with command "pip install package_name":
)
powershell -NoProfile -Command "$s=New-Object -ComObject WScript.Shell;$l=$s.CreateShortcut('%install_lnk%');$l.TargetPath=$env:ComSpec;$l.Arguments='/k ""%path%\pip_shell.cmd""';$l.WorkingDirectory='%path%';$l.WindowStyle=1;$l.Save()"
echo:
copy /Y "%install_lnk%" "%path%\"

:: change vs-code settings to set default interpreter and folder to search for environments if not set there already
set "SETTINGS=%APPDATA%\Code\User\settings.json"
set "DEF_INTERP=${env:USERPROFILE}\Documents\python_envs\default_env\Scripts\python.exe"
set "DEF_KERNEL=default_env"
set "VENV_FOLDER=Documents\python_envs"
> "%TEMP%\vscode_merge.py" (
  echo import os, json, re
  echo p = r"%SETTINGS%"
  echo os.makedirs(os.path.dirname(p^), exist_ok=True^)
  echo try:
  echo ^    with open(p, "r", encoding="utf-8"^) as f: d = json.load(f^)
  echo except Exception:
  echo ^    d = {}
  echo if "python.defaultInterpreterPath" not in d:
  echo ^    d["python.defaultInterpreterPath"] = r"%DEF_INTERP%"
  echo v = r"%VENV_FOLDER%"
  echo if not isinstance(d.get("python.venvFolders"^), list^): d["python.venvFolders"] = []
  echo if v not in d["python.venvFolders"]: d["python.venvFolders"].append(v^)
  echo txt = json.dumps(d, indent=2^)
  echo txt = re.sub(r"(\x22python\.venvFolders\x22:\s*)\[\s*(\x22.*?\x22)\s*\]", r"\1[\2]", txt^)
  echo with open(p, "w", encoding="utf-8"^) as f: f.write(txt^)
)
echo:
python "%TEMP%\vscode_merge.py" && echo VS Code settings updated. || echo Failed to update VS Code settings.
echo:

:: --register env with conda to make it findable with apps like Spyder--
:: Path to conda environments.txt:
set conda_list_path=%USERPROFILE%\.conda\environments.txt
:: Create the file if it does not exist:
if not exist "%conda_list_path%" (
    echo Creating conda list %conda_list_path%
    type nul > "%conda_list_path%"
    echo:
)
:: Check if the venv path is already registered:
findstr /C:"%path%" "%conda_list_path%" >nul 2>&1
if %errorlevel%==0 (
    echo Already registered with conda: %path%
    echo:
) else (
    echo Registering %path% with conda
    echo %path%>>"%conda_list_path%"
    echo:
)

:: --- finish ---
echo:
echo:
echo: Code finished. Created shortcut in Desktop ("Install package (%env_name%)"). Press any key to exit.
pause > nul
exit /b 0

@REM #################
@REM ### Functions ###
@REM #################

:fail
  echo:
  echo:
  echo: Error: Failed python environment setup. See errors above. Press any key to exit.
  echo: If this keeps happening, try deleting the environment folder ("%path%"^) and running this script again.
  pause > nul
  exit /b 1

@REM ###################################

:process_args
  IF "%1"=="" GOTO EOF
  IF "%1"=="--path" SET "path=%2" & shift & shift & GOTO process_args
  IF "%1"=="--version" SET "version=%2" & shift & shift & GOTO process_args
  IF "%1"=="--packages" SET "packages=%2" & shift & shift & GOTO process_args
  IF "%paths%"=="" SET "path=%1" & shift & GOTO process_args
  IF "%version%"=="" SET "version=%1" & shift & GOTO process_args
  IF "%packages%"=="" SET "packages=%1" & shift & GOTO process_args
  GOTO EOF

@REM ###################################

:make_absolute_path_if_relative
	SET "OUTPUT=%~f1"
	GOTO :EOF

@REM ###################################

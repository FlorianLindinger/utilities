:: -- Settings --
:: To define the default vs-code environment, set: @SET "environment_path=%USERPROFILE%\Documents\python_envs\default_env"

@SET "python_version=3.13"
@SET "environment_path=%USERPROFILE%\Documents\python_envs\default_env"
@SET "python_packages=ipykernel numpy matplotlib scipy ipywidgets pyqt5 pandas pillow pyyaml tqdm openpyxl pyarrow html5lib pyserial tifffile py7zr numba pyautogui nptdms pywinauto scipy-stubs cupy-cuda12x nvmath-python"

:: -- Execution starts here --

:: print settings
@echo off
echo: --Settings--
echo:
echo: Python version: %python_version%
echo: Environment path: %environment_path%
echo: Python packages: %python_packages%
echo:
echo:

:: derive env name from path
for %%F in ("%environment_path%") do set "env_name=%%~nxF"

:: build full paths for shortcuts
set "install_lnk=%USERPROFILE%\Desktop\Install package (%env_name%).lnk"

:: If Python version x.y not found, try to install
py -%python_version% -c "exit()" >nul 2>&1
IF ERRORLEVEL 1 (
    echo:
    echo: --Installing Python %python_version%--
    echo:
    winget install --id Python.Python.%python_version% -e --force --override "InstallAllUsers=0 Include_launcher=0 Include_pip=1 PrependPath=1 /passive /norestart" --accept-source-agreements --accept-package-agreements
    :: check if sucessful install:
    py -%python_version% -c "exit()" >nul 2>&1 || goto :fail
    echo:
    echo: --Finished installing Python %python_version%--
    echo:
) ELSE (
  echo: --Correct python version already installed--
  echo:
)

:: --- create & activate venv ---
py -%python_version% -m venv "%environment_path%" || goto :fail
call "%environment_path%\Scripts\activate.bat" || goto :fail
echo: --Created and/or activated python environment--

:: --- package installs ---
echo:
echo: --Installing packages--
echo:
python -m pip install --upgrade pip || goto :fail
pip install %python_packages% || goto :fail
echo:
echo: --Finished installing packages--
echo:

:: register the kernel in the system
@REM python -m ipykernel install --prefix "%ProgramData%\jupyter" --name default_env --display-name "%env_name%"
python -m ipykernel install --user --name "%env_name%" --display-name "%env_name%"
echo:
setx JUPYTER_PATH "%PROGRAMDATA%\jupyter;%APPDATA%\jupyter"

:: --- create folders ---
echo:
mkdir "%USERPROFILE%\Documents\Repositories" 

:: create shortcut to install packages in desktop and environment folder
> "%environment_path%\pip_shell.cmd" (
  echo @echo off
  echo call "%%~dp0Scripts\activate.bat"
  echo echo.
  echo echo: Install package into python environment ("%env_name%"^) with command "pip install package_name":
)
powershell -NoProfile -Command "$s=New-Object -ComObject WScript.Shell;$l=$s.CreateShortcut('%install_lnk%');$l.TargetPath=$env:ComSpec;$l.Arguments='/k ""%environment_path%\pip_shell.cmd""';$l.WorkingDirectory='%environment_path%';$l.WindowStyle=1;$l.Save()"
echo:
copy /Y "%install_lnk%" "%environment_path%\"

:: change vs-code settings to set default jupyter kernel and interpreter and folder to search for environments if not set there already
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

  echo if "jupyter.defaultKernel" not in d:
  echo ^    d["jupyter.defaultKernel"] = "%DEF_KERNEL%"

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

:: --- finish ---
echo:
echo:
echo: Code finished. Created shortcut in Desktop ("Install package (%env_name%)"). Press any key to exit.
pause > nul
exit /b 0

:: --- fail ---
:fail
echo:
echo:
echo: Error: Failed python environment setup. See errors above. Press any key to exit.
echo: If this keeps happening, try deleting the environment folder ("%environment_path%"^) and running this script again.
pause > nul
exit /b 1



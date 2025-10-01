@setlocal & @echo off & CALL :process_args
:: ########################
:: ### Default Settings ###
:: ########################

SET "def_path=%USERPROFILE%\Documents\python_envs\jupyter_env"
SET "def_folder=%USERPROFILE%\Documents\python_notebooks"
SET "def_packages=numpy matplotlib scipy ipywidgets pyqt5 pandas pillow pyyaml tqdm openpyxl pyarrow html5lib pyserial tifffile py7zr numba pyautogui nptdms pywinauto scipy-stubs cupy-cuda12x nvmath-python"
SET "def_version=3.13"

:: #############################
:: ### Execution starts here ###
:: #############################

:: define undefined args with default settings
IF "%path%"=="" SET "path=%environment_path%"
IF "%notebooks_path%"=="" SET "notebooks_path=%def_folder%"
IF "%packages%"=="" SET "packages=%def_packages%"
IF "%verion%"=="" SET "version=%def_version%"

:: convert path to absolute if relative
CALL :make_absolute_path_if_relative "%path%" & SET "path=%OUTPUT%"
CALL :make_absolute_path_if_relative "%notebooks_path%" & SET "notebooks_path=%OUTPUT%"

:: print settings
echo: --Settings--
echo:
echo: Environment path: %environment_path%
echo: Notebooks folder: %notebooks_path%
echo: Python version: %python_version%
echo: Python packages: %python_packages%
echo:
echo:

:: derive env name from path
for %%F in ("%environment_path%") do set "env_name=%%~nxF"

:: If Python version x.y not found, try to install
py -%python_version% -c "exit()" >nul 2>&1
IF ERRORLEVEL 1 (
    echo: --Installing Python %python_version%--
    echo:
    :: Include_launcher=1 sometimes is forbidden by organisation windows settings -> "py" instead of "python"
    winget install --id Python.Python.%python_version% -e --force --override "InstallAllUsers=0 Include_launcher=0 Include_pip=1 PrependPath=1 /passive /norestart" --accept-source-agreements --accept-package-agreements
    :: check if sucessful install:
    py -%python_version% -c "exit()" >nul 2>&1 || goto :fail
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
echo: --Installing packages--
echo:
python -m pip install --upgrade pip || goto :fail
pip install %python_packages% || goto :fail
echo: --Finished installing packages--
echo:

:: Jupyter and extensions
echo: --Installing Jupyter and extensions--
echo:
python -m pip install "notebook==6.5.7" "jupyter_contrib_nbextensions==0.7.0" "jupyter_nbextensions_configurator==0.5.0" || goto :fail
python -m jupyter contrib nbextension install --user || goto :fail
python -m jupyter nbextensions_configurator enable --user || goto :fail
python -m jupyter nbextension enable notify/notify
python -m jupyter nbextension enable gist_it/main
python -m jupyter nbextension disable varInspector/main
python -m jupyter nbextension enable autoscroll/main
python -m jupyter nbextension enable codefolding/main
python -m jupyter nbextension enable collapsible_headings/main
python -m jupyter nbextension enable execute_time/ExecuteTime
python -m jupyter nbextension enable go_to_current_running_cell/main
python -m jupyter nbextension enable highlight_selected_word/main
python -m jupyter nbextension enable limit_output/main
python -m jupyter nbextension enable scratchpad/main
python -m jupyter nbextension enable scroll_down/main
python -m jupyter nbextension enable toc2/main
python -m jupyter nbextension enable --section edit codefolding/edit
python -m jupyter nbextension enable --section tree tree-filter/index
python -m jupyter nbextension disable skip-traceback/main
echo: --Finished installing Jupyter and extensions--
echo:

:: register the kernel in the system
python -m ipykernel install --user --name jupyter_env --display-name "%env_name%"
setx JUPYTER_PATH "%PROGRAMDATA%\jupyter;%APPDATA%\jupyter"
echo: 

:: --- create folders ---
mkdir "%USERPROFILE%\Documents\Repositories"
mkdir "%notebooks_path%"
echo: 

:: create Jupyter Notebook shortcut in desktop and environment folder
set "jupyter_lnk=%USERPROFILE%\Desktop\Jupyter Notebook (%env_name%).lnk"
powershell -NoProfile -Command "$s=New-Object -ComObject WScript.Shell;$l=$s.CreateShortcut('%jupyter_lnk%');$l.TargetPath='%environment_path%\Scripts\jupyter-notebook.exe';$l.WorkingDirectory='%notebooks_path%';$l.WindowStyle=7;$l.Save()"
copy /Y "%jupyter_lnk%" "%environment_path%\" 

:: create shortcut to install packages in desktop and environment folder
> "%environment_path%\pip_shell.cmd" (
  echo @echo off
  echo call "%%~dp0Scripts\activate.bat"
  echo echo.
  echo echo: Install package into python environment ("%env_name%"^) with command "pip install package_name":
)
set "install_lnk=%USERPROFILE%\Desktop\Install package (%env_name%).lnk"
powershell -NoProfile -Command "$s=New-Object -ComObject WScript.Shell;$l=$s.CreateShortcut('%install_lnk%');$l.TargetPath=$env:ComSpec;$l.Arguments='/k ""%environment_path%\pip_shell.cmd""';$l.WorkingDirectory='%environment_path%';$l.WindowStyle=1;$l.Save()"
copy /Y "%install_lnk%" "%environment_path%\" 

:: --register env with conda to make it findable with apps like Spyder--
:: Path to conda environments.txt:
set conda_list_path=%USERPROFILE%\.conda\environments.txt
:: Create the file if it does not exist:
if not exist "%conda_list_path%" (
    echo Creating conda list %conda_list_path%
    echo:
    type nul > "%conda_list_path%"
)
:: Check if the venv path is already registered:
findstr /C:"%environment_path%" "%conda_list_path%" >nul 2>&1
if %errorlevel%==0 (
    echo Already registered with conda: %environment_path%
    echo:
) else (
    echo Registering %environment_path% with conda
    echo %environment_path%>>"%conda_list_path%"
    echo:
)

:: --- finish print---
echo:
echo:
echo: Code finished. Created shortcuts in Desktop ("Jupyter Notebook (%env_name%)" ^& "Install package (%env_name%)"). Press any key to exit.
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
  IF "%1"=="--folder" SET "notebooks_path=%2" & shift & shift & GOTO process_args
  IF "%1"=="--packages" SET "packages=%2" & shift & shift & GOTO process_args
  IF "%1"=="--version" SET "version=%2" & shift & shift & GOTO process_args
  IF "%paths%"=="" SET "path=%1" & shift & GOTO process_args
  IF "%notebooks_path%"=="" SET "notebooks_path=%1" & shift & GOTO process_args
  IF "%packages%"=="" SET "packages=%1" & shift & GOTO process_args
  IF "%version%"=="" SET "version=%1" & shift & GOTO process_args
  GOTO EOF

@REM ###################################

:make_absolute_path_if_relative
	SET "OUTPUT=%~f1"
	GOTO :EOF

@REM ###################################

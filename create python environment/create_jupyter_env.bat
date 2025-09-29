:: -- Settings --

@SET "environment_path=%USERPROFILE%\Documents\python_envs\jupyter_env"
@SET "script_path=%USERPROFILE%\Documents\python_notebooks"
@SET "python_packages=numpy matplotlib scipy ipywidgets pyqt5 pandas pillow pyyaml tqdm openpyxl pyarrow html5lib pyserial tifffile py7zr numba pyautogui nptdms pywinauto scipy-stubs cupy-cuda12x nvmath-python"
@SET "python_version=3.13"

:: -- Execution starts here --

:: print settings
@echo off
echo: --Settings--
echo:
echo: Environment path: %environment_path%
echo: Script path: %script_path%
echo: Python version: %python_version%
echo: Python packages: %python_packages%
echo:
echo:

:: derive env name from path
for %%F in ("%environment_path%") do set "env_name=%%~nxF"

:: build full paths for shortcuts
set "jupyter_lnk=%USERPROFILE%\Desktop\Jupyter Notebook (%env_name%).lnk"
set "install_lnk=%USERPROFILE%\Desktop\Install package (%env_name%).lnk"

:: If Python x.y not found, try to install. Ignore winget’s non-upgrade code.
where python%python_version% >nul 2>&1
IF ERRORLEVEL 1 (
    echo:
    echo: --Installing Python %python_version%--
    echo:
  winget install Python.Python.%python_version% --accept-source-agreements --accept-package-agreements ^
    || echo winget reported no upgrade or a non-fatal issue.
    echo:
    echo: --Finished installing Python %python_version%--
    echo:
)
:: Require the interpreter to exist before continuing.
where python%python_version% >nul 2>&1 || goto :fail

:: --- create & activate venv ---
python%python_version% -m venv "%environment_path%" || goto :fail
call "%environment_path%\Scripts\activate.bat" || goto :fail

:: --- package installs ---
echo:
echo: --Installing packages--
echo:
python -m pip install --upgrade pip || goto :fail
pip install %python_packages% || goto :fail
echo:
echo: --Finished installing packages--
echo:

:: Jupyter and extensions
echo:
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
echo:
echo: --Finished installing Jupyter and extensions--
echo:

:: register the kernel in the system
python -m ipykernel install --user --name jupyter_env --display-name "%env_name%"
setx JUPYTER_PATH "%PROGRAMDATA%\jupyter;%APPDATA%\jupyter"
echo: 

:: --- create folders ---
mkdir "%USERPROFILE%\Documents\Repositories"
mkdir "%script_path%"
echo: 

:: create Jupyter Notebook shortcut in desktop and environment folder
powershell -NoProfile -Command "$s=New-Object -ComObject WScript.Shell;$l=$s.CreateShortcut('%jupyter_lnk%');$l.TargetPath='%environment_path%\Scripts\jupyter-notebook.exe';$l.WorkingDirectory='%script_path%';$l.WindowStyle=7;$l.Save()"
copy /Y "%jupyter_lnk%" "%environment_path%\" 

:: create shortcut to install packages in desktop and environment folder
> "%environment_path%\pip_shell.cmd" (
  echo @echo off
  echo call "%%~dp0Scripts\activate.bat"
  echo echo.
  echo echo: Install package into python environment ("%env_name%"^) with command "pip install package_name":
)
powershell -NoProfile -Command "$s=New-Object -ComObject WScript.Shell;$l=$s.CreateShortcut('%install_lnk%');$l.TargetPath=$env:ComSpec;$l.Arguments='/k ""%environment_path%\pip_shell.cmd""';$l.WorkingDirectory='%environment_path%';$l.WindowStyle=1;$l.Save()"
copy /Y "%install_lnk%" "%environment_path%\" 

:: --- finish ---
echo:
echo:
echo: Code finished. Created shortcuts in Desktop ("Jupyter Notebook (%env_name%)" ^& "Install package (%env_name%)"). Press any key to exit.
pause > nul
exit /b 0

:: --- fail ---
:fail
echo:
echo:
echo Error: Failed python environment setup. See errors above. Press any key to exit.
echo: If this keeps happening, try deleting the environment folder ("%environment_path%"^) and running this script again.
pause > nul
exit /b 1

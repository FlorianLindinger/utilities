@setlocal EnableDelayedExpansion & @echo off
REM=r""" <- this is needed for python to ignore the batch part of the code. The first line is ignored via launching with flag "-X" (Python code is on bottom)
CALL :process_args %* || goto :fail
:: Creates or reuses a Python virtual environment, optionally adds Jupyter/Notebook tooling, optionally sets the env as the VS Code default interpreter, installs Python with winget when the requested launcher version is missing, installs uv, installs packages one by one with uv and pip fallback, registers an ipykernel, and creates helper shortcuts.

:: ########################
:: ### Default Settings ###
:: ########################

SET "def_env_path=%USERPROFILE%\Documents\python_envs\default_env"
SET "def_env_root=%USERPROFILE%\Documents\python_envs"
SET "def_folder=%USERPROFILE%\Documents\python_notebooks"
SET "def_version=3"
SET "def_do_jupyter=N"
SET "def_set_vscode_default=Y"
SET "def_register_conda=Y"
SET "def_packages=ipykernel ipympl numpy matplotlib scipy ipywidgets pyqt5 pandas pillow pyyaml tqdm openpyxl pyarrow html5lib pyserial tifffile py7zr numba pyautogui nptdms pywinauto opencv-python scipy-stubs cupy-cuda12x nvmath-python pyside6 pywin32 nuitka"

:: #####################
:: ### Resolve Setup ###
:: #####################

IF "%folder%"=="" SET "folder=%def_folder%"
IF "%packages%"=="" SET "packages=%def_packages%"
IF "%env_name%"=="" (
  IF NOT "%env_path%"=="" for %%F in ("%env_path%") do set "env_name=%%~nxF"
)
IF "%env_name%"=="" SET "env_name=default_env"
IF "%env_path%"=="" SET "env_path=%def_env_root%\%env_name%"
IF "%version%"=="" CALL :prompt_environment_settings || goto :fail
IF "%do_jupyter%"=="" CALL :prompt_environment_settings || goto :fail
IF "%set_vscode_default%"=="" CALL :prompt_environment_settings || goto :fail
IF "%register_conda%"=="" CALL :prompt_environment_settings || goto :fail
IF "%env_path%"=="" SET "env_path=%def_env_root%\%env_name%"
CALL :normalize_yes_no "do_jupyter" || goto :fail
CALL :normalize_yes_no "set_vscode_default" || goto :fail
CALL :normalize_yes_no "register_conda" || goto :fail
CALL :resolve_python_version || goto :fail

CALL :make_absolute_path "%env_path%" || goto :fail
SET "env_path=%OUTPUT%"
CALL :make_absolute_path "%folder%" || goto :fail
SET "folder=%OUTPUT%"

for %%F in ("%env_path%") do set "env_name=%%~nxF"

:: ##########################
:: ### Environment Setup  ###
:: ##########################

echo: --Settings--
echo:
echo: Environment path: %env_path%
echo: Notebooks folder: %folder%
echo: Python version request: %version_request%
echo: Python final release: %version%
echo: Python packages: %packages%
echo: Setup Jupyter: %do_jupyter%
echo: Set as VS Code default: %set_vscode_default%
echo: Register with conda: %register_conda%
echo:
echo:

CALL :ensure_python || goto :fail

IF /I "%do_jupyter%"=="Y" (
  CALL :ensure_python_path || goto :fail
)

:: Create or activate venv.
call "%env_path%\Scripts\activate.bat" > NUL 2>&1 || goto :create_venv
echo: --Environment already exists--
GOTO :skip_venv_creation
:create_venv
py -%launcher_version% -m venv "%env_path%" || goto :fail
echo: --Created python environment--
call "%env_path%\Scripts\activate.bat" || goto :fail
:skip_venv_creation
echo:
echo: --Activated python environment--
echo:

:: Install core packages.
echo: --Installing packages--
echo:
python -m pip install --upgrade pip || goto :fail
CALL :ensure_uv
CALL :install_packages "%packages%" || goto :fail
echo:
echo: --Finished installing packages--
echo:

IF /I "%do_jupyter%"=="Y" (
  CALL :install_jupyter || goto :fail
)

:: Register this environment as a Jupyter kernel.
python -m ipykernel install --user --name "%env_name%" --display-name "%env_name%" >NUL
setx JUPYTER_PATH "%PROGRAMDATA%\jupyter;%APPDATA%\jupyter" >NUL
echo: --Registered kernel with ipykernel--
echo:

mkdir "%USERPROFILE%\Documents\Repositories" 2> NUL
IF /I "%do_jupyter%"=="Y" mkdir "%folder%" 2> NUL

:: Create launch and package-install shortcuts.
IF /I "%do_jupyter%"=="Y" (
  CALL :create_app_shortcut "Jupyter Notebook (%env_name%)" "%env_path%\Scripts\jupyter-notebook.exe" "%folder%" 7 || goto :fail
)

> "%env_path%\pip_shell.cmd" (
  echo @echo off
  echo call "%%~dp0Scripts\activate.bat"
  echo echo.
  echo echo: Install packages into python environment "%env_name%".
  echo echo: Accepted input examples:
  echo echo:   numpy pandas
  echo echo:   pip install numpy pandas
  echo echo:   python -m pip install numpy pandas
  echo echo:   py -m pip install numpy pandas
  echo echo:   uv pip install numpy pandas
  echo echo.
  echo :again
  echo set "install_input="
  echo set /p "install_input=Package(s) or install command: "
  echo for /f "tokens=* delims= " %%%%I in ("%%install_input%%"^) do set "install_input=%%%%I"
  echo if not defined install_input goto again
  echo if /I "%%install_input%%"=="exit" exit /b 0
  echo if /I "%%install_input%%"=="quit" exit /b 0
  echo if /I "%%install_input%%"=="pip install" echo: Add one or more package names. ^& goto again
  echo if /I "%%install_input%%"=="python -m pip install" echo: Add one or more package names. ^& goto again
  echo if /I "%%install_input%%"=="py -m pip install" echo: Add one or more package names. ^& goto again
  echo if /I "%%install_input%%"=="uv pip install" echo: Add one or more package names. ^& goto again
  echo echo %%install_input%% ^| findstr /I /B /C:"pip install " /C:"python -m pip install " /C:"py -m pip install " /C:"uv pip install " ^>nul
  echo if not errorlevel 1 ^(
  echo   %%install_input%%
  echo ^) else ^(
  echo   uv pip install %%install_input%% ^|^| python -m pip install %%install_input%%
  echo ^)
  echo echo.
  echo goto again
)
CALL :create_cmd_shortcut "Install package (%env_name%)" "%env_path%\pip_shell.cmd" "%env_path%" || goto :fail

IF /I "%register_conda%"=="Y" (
  CALL :register_conda_env || goto :fail
) ELSE (
  echo: --Skipped conda environment registration--
)

:: Optionally update VS Code user settings.
IF /I "%set_vscode_default%"=="Y" (
  set "PY_ENV_HELPER_VSCODE_PYTHON=%env_path%\Scripts\python.exe"
  for %%F in ("%env_path%\..") do set "PY_ENV_HELPER_VENV_FOLDER=%%~fF"
  py -x "%~f0"
) ELSE (
  echo: --Skipped VS Code default interpreter update--
)

echo:
echo:
echo: Code finished.
echo: Created environment in "%env_path%".
IF "%jupyter_env_shortcut_created%"=="1" echo: Created shortcut in environment folder ("Jupyter Notebook (%env_name%)") for launching jupyter notebook.
IF "%install_env_shortcut_created%"=="1" echo: Created shortcut in environment folder ("Install package (%env_name%)") for installing packages.
IF "%jupyter_shortcut_created%"=="1" echo: Created shortcut in Desktop ("Jupyter Notebook (%env_name%)") for launching jupyter notebook.
IF "%install_shortcut_created%"=="1" echo: Created shortcut in Desktop ("Install package (%env_name%)") for installing packages.
echo: Press any key to exit.
pause > nul
exit /b 0

:: #################
:: ### Functions ###
:: #################

:fail
  echo:
  echo:
  echo: ERROR: Failed python environment setup (See errors above^).
  echo: If this keeps happening, try deleting the environment folder ("%env_path%"^) and run this script again.
  echo: Press any key to exit.
  pause > nul
  exit /b 1

:process_args
  IF "%~1"=="" GOTO :EOF
  IF "%~1"=="--path" SET "env_path=%~2" & shift & shift & GOTO process_args
  IF "%~1"=="--name" SET "env_name=%~2" & shift & shift & GOTO process_args
  IF "%~1"=="--env-name" SET "env_name=%~2" & shift & shift & GOTO process_args
  IF "%~1"=="--folder" SET "folder=%~2" & shift & shift & GOTO process_args
  IF "%~1"=="--packages" SET "packages=%~2" & shift & shift & GOTO process_args
  IF "%~1"=="--version" SET "version=%~2" & shift & shift & GOTO process_args
  IF "%~1"=="--jupyter" SET "do_jupyter=%~2" & shift & shift & GOTO process_args
  IF "%~1"=="--vscode-default" SET "set_vscode_default=%~2" & shift & shift & GOTO process_args
  IF "%~1"=="--register-conda" SET "register_conda=%~2" & shift & shift & GOTO process_args
  IF "%env_path%"=="" SET "env_path=%~1" & shift & GOTO process_args
  IF "%version%"=="" SET "version=%~1" & shift & GOTO process_args
  IF "%packages%"=="" SET "packages=%~1" & shift & GOTO process_args
  GOTO :EOF

:prompt_environment_settings
  IF "%env_name%"=="" set "env_name=default_env"
  IF "%env_path%"=="" set "env_path=%def_env_root%\%env_name%"
  IF "%folder%"=="" set "folder=%def_folder%"
  IF "%packages%"=="" set "packages=%def_packages%"
  IF "%version%"=="" set "version=%def_version%"
  IF "%do_jupyter%"=="" set "do_jupyter=%def_do_jupyter%"
  IF "%set_vscode_default%"=="" set "set_vscode_default=%def_set_vscode_default%"
  IF "%register_conda%"=="" set "register_conda=%def_register_conda%"
  for /f "tokens=1,* delims==" %%A in ('powershell -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; $form=New-Object System.Windows.Forms.Form; $form.Text='Python environment settings'; $form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedDialog'; $form.MaximizeBox=$false; $form.MinimizeBox=$false; $form.ClientSize=New-Object System.Drawing.Size(640,460); $pathLabel=New-Object System.Windows.Forms.Label; $pathLabel.Text='Environment path:'; $pathLabel.Location=New-Object System.Drawing.Point(12,16); $pathLabel.AutoSize=$true; $form.Controls.Add($pathLabel); $pathText=New-Object System.Windows.Forms.TextBox; $pathText.Location=New-Object System.Drawing.Point(165,13); $pathText.Size=New-Object System.Drawing.Size(430,22); $pathText.Text='%env_path%'; $form.Controls.Add($pathText); $versionLabel=New-Object System.Windows.Forms.Label; $versionLabel.Text='Python version prefix:'; $versionLabel.Location=New-Object System.Drawing.Point(12,50); $versionLabel.AutoSize=$true; $form.Controls.Add($versionLabel); $text=New-Object System.Windows.Forms.TextBox; $text.Location=New-Object System.Drawing.Point(165,47); $text.Size=New-Object System.Drawing.Size(160,22); $text.Text='%version%'; $form.Controls.Add($text); $packagesLabel=New-Object System.Windows.Forms.Label; $packagesLabel.Text='Packages:'; $packagesLabel.Location=New-Object System.Drawing.Point(12,84); $packagesLabel.AutoSize=$true; $form.Controls.Add($packagesLabel); $packagesText=New-Object System.Windows.Forms.TextBox; $packagesText.Location=New-Object System.Drawing.Point(165,81); $packagesText.Size=New-Object System.Drawing.Size(430,135); $packagesText.Multiline=$true; $packagesText.ScrollBars='Vertical'; $packagesText.WordWrap=$true; $packagesText.Text='%packages%'; $form.Controls.Add($packagesText); $v=New-Object System.Windows.Forms.CheckBox; $v.Text='Set as VS Code default interpreter'; $v.Location=New-Object System.Drawing.Point(15,240); $v.Size=New-Object System.Drawing.Size(360,24); $v.Checked=('%set_vscode_default%' -ieq 'Y' -or '%set_vscode_default%' -ieq 'YES'); $form.Controls.Add($v); $c=New-Object System.Windows.Forms.CheckBox; $c.Text='Register environment with conda'; $c.Location=New-Object System.Drawing.Point(15,270); $c.Size=New-Object System.Drawing.Size(360,24); $c.Checked=('%register_conda%' -ieq 'Y' -or '%register_conda%' -ieq 'YES'); $form.Controls.Add($c); $j=New-Object System.Windows.Forms.CheckBox; $j.Text='Install Jupyter Notebook tools and shortcut'; $j.Location=New-Object System.Drawing.Point(15,300); $j.Size=New-Object System.Drawing.Size(360,24); $j.Checked=('%do_jupyter%' -ieq 'Y' -or '%do_jupyter%' -ieq 'YES'); $form.Controls.Add($j); $folderLabel=New-Object System.Windows.Forms.Label; $folderLabel.Text='Jupyter notebook folder:'; $folderLabel.Location=New-Object System.Drawing.Point(12,338); $folderLabel.AutoSize=$true; $form.Controls.Add($folderLabel); $folderText=New-Object System.Windows.Forms.TextBox; $folderText.Location=New-Object System.Drawing.Point(165,335); $folderText.Size=New-Object System.Drawing.Size(430,22); $folderText.Text='%folder%'; $form.Controls.Add($folderText); $ok=New-Object System.Windows.Forms.Button; $ok.Text='OK'; $ok.Location=New-Object System.Drawing.Point(450,410); $ok.DialogResult=[System.Windows.Forms.DialogResult]::OK; $form.AcceptButton=$ok; $form.Controls.Add($ok); $cancel=New-Object System.Windows.Forms.Button; $cancel.Text='Cancel'; $cancel.Location=New-Object System.Drawing.Point(535,410); $cancel.DialogResult=[System.Windows.Forms.DialogResult]::Cancel; $form.CancelButton=$cancel; $form.Controls.Add($cancel); $result=$form.ShowDialog(); if ($result -eq [System.Windows.Forms.DialogResult]::OK) { $ep=$pathText.Text.Trim(); if (-not $ep) { $ep='%def_env_path%' }; $nf=$folderText.Text.Trim(); if (-not $nf) { $nf='%def_folder%' }; $pv=$text.Text.Trim(); if (-not $pv) { $pv='%def_version%' }; $pk=($packagesText.Text -replace '[\r\n\t]+',' ').Trim(); if (-not $pk) { $pk='%def_packages%' }; Write-Output ('env_path=' + $ep); Write-Output ('folder=' + $nf); Write-Output ('version=' + $pv); Write-Output ('packages=' + $pk); Write-Output ('do_jupyter=' + $(if ($j.Checked) { 'Y' } else { 'N' })); Write-Output ('set_vscode_default=' + $(if ($v.Checked) { 'Y' } else { 'N' })); Write-Output ('register_conda=' + $(if ($c.Checked) { 'Y' } else { 'N' })) } else { Write-Output 'env_path=%env_path%'; Write-Output 'folder=%folder%'; Write-Output 'version=%version%'; Write-Output 'packages=%packages%'; Write-Output 'do_jupyter=%do_jupyter%'; Write-Output 'set_vscode_default=%set_vscode_default%'; Write-Output 'register_conda=%register_conda%' }"') do set "%%A=%%B"
  IF "%env_path%"=="" set "env_path=%def_env_path%"
  IF "%folder%"=="" set "folder=%def_folder%"
  IF "%version%"=="" set "version=%def_version%"
  IF "%packages%"=="" set "packages=%def_packages%"
  exit /b 0

:normalize_yes_no
  set "yn_name=%~1"
  call set "yn_value=%%%yn_name%%%"
  IF "%yn_value%"=="" set "yn_value=N"
  IF /I "%yn_value%"=="YES" set "yn_value=Y"
  IF /I "%yn_value%"=="NO" set "yn_value=N"
  IF /I "%yn_value%"=="TRUE" set "yn_value=Y"
  IF /I "%yn_value%"=="FALSE" set "yn_value=N"
  IF /I "%yn_value%"=="1" set "yn_value=Y"
  IF /I "%yn_value%"=="0" set "yn_value=N"
  IF /I "%yn_value%"=="Y" (
    call set "%yn_name%=Y"
    exit /b 0
  )
  IF /I "%yn_value%"=="N" (
    call set "%yn_name%=N"
    exit /b 0
  )
  echo: [Error] %yn_name% must be Y or N.
  exit /b 1

:resolve_python_version
  set "version_request=%version%"
  set "resolved_version="
  set "exact_version_requested=N"
  for /f "tokens=1-3 delims=." %%A in ("%version_request%") do (
    IF NOT "%%C"=="" set "exact_version_requested=Y"
  )
  echo: --Resolving newest compatible Python release for "%version_request%"--
  for /f "delims=" %%V in ('powershell -NoProfile -Command "$prefix='%version_request%'.Trim(); if ($prefix -notmatch '^\d+(\.\d+){0,2}$') { exit 2 }; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $releaseRoot='https://www.python.org/ftp/python/'; $links=(Invoke-WebRequest -UseBasicParsing $releaseRoot).Links; $versions=$links | ForEach-Object href | Where-Object { $_ -match '^\d+\.\d+\.\d+/$' } | ForEach-Object { $_.TrimEnd('/') } | Where-Object { $_ -eq $prefix -or $_.StartsWith($prefix + '.') } | ForEach-Object { [version]$_ } | Sort-Object -Descending; foreach ($v in $versions) { $s=$v.ToString(); $url=$releaseRoot + $s + '/python-' + $s + '-amd64.exe'; try { Invoke-WebRequest -UseBasicParsing -Method Head $url -TimeoutSec 8 | Out-Null; Write-Output $s; exit 0 } catch {} }; exit 3"') do set "resolved_version=%%V"
  IF "%resolved_version%"=="" (
    echo: [Error] Could not resolve newest Python release for "%version_request%" from python.org.
    exit /b 1
  )
  set "version=%resolved_version%"
  for /f "tokens=1,2 delims=." %%A in ("%version%") do set "launcher_version=%%A.%%B"
  echo: Resolved Python %version_request% to %version%.
  echo:
  exit /b 0

:ensure_python
  IF /I "%exact_version_requested%"=="Y" (
    py -%launcher_version% -c "import platform, sys; sys.exit(0 if platform.python_version() == '%version%' else 1)" >nul 2>&1
  ) ELSE (
    py -%launcher_version% -c "import sys" >nul 2>&1
  )
  IF ERRORLEVEL 1 (
    where winget >nul 2>&1
    if errorlevel 1 (
      echo: [Error] Needs winget to install Python %version% automatically. Install Python manually or install winget and re-run.
      exit /b 1
    )
    echo: --Installing Python %version%--
    echo:
    winget install --id Python.Python.%launcher_version% -e --force --source winget --accept-source-agreements --accept-package-agreements --silent --override "InstallAllUsers=0 Include_pip=1 Include_launcher=0 PrependPath=1 SimpleInstall=1 /quiet /norestart"
    IF /I "%exact_version_requested%"=="Y" (
      py -%launcher_version% -c "import platform, sys; sys.exit(0 if platform.python_version() == '%version%' else 1)" >nul 2>&1 || exit /b 1
    ) ELSE (
      py -%launcher_version% -c "import sys" >nul 2>&1 || exit /b 1
    )
    echo:
    echo: --Finished installing Python %version%--
  ) ELSE (
    IF /I "%exact_version_requested%"=="Y" (
      echo: --Exact Python version already installed--
    ) ELSE (
      echo: --Compatible Python %launcher_version% already installed--
    )
  )
  echo:
  exit /b 0

:ensure_python_path
  set "std_py_path=%LocalAppData%\Programs\Python\"
  for /f "tokens=1,2 delims=." %%A in ("%launcher_version%") do set "pyPath=%std_py_path%Python%%A%%B"
  IF NOT EXIST "%pyPath%" (
    echo: [Warning] No Python folder found at "%pyPath%". Therefore can't add it to global Path.
    echo:
    exit /b 0
  )
  for /f "tokens=2,*" %%A in ('reg query HKCU\Environment /v PATH 2^>nul') do set "userpath=%%B"
  IF "%userpath%"=="" set "userpath="
  set "checkPath=%userpath%"
  call set "checkPath=%%checkPath:%pyPath%=%%"
  if "%checkPath%"=="%userpath%" (
    echo Adding python path...
    if "!userpath:~-1!"==";" set "userpath=!userpath:~0,-1!"
    setx PATH "!userpath!;%pyPath%" >NUL
  ) else (
    echo Python path already present.
  )
  echo:
  exit /b 0

:ensure_uv
  echo: --Installing/updating uv--
  python -m pip install --upgrade uv
  if errorlevel 1 echo: [Warning] Failed to install uv. Package installs will use pip.
  echo:
  exit /b 0

:install_packages
  set "failed_packages="
  set "installed_packages="
  for %%P in (%~1) do (
    CALL :print_separator
    echo: Installing %%P ...
    where uv >nul 2>&1
    if errorlevel 1 (
      python -m pip install "%%P"
    ) else (
      uv pip install "%%P"
      if errorlevel 1 (
        echo: [Warning] uv failed to install %%P. Trying pip fallback...
        python -m pip install "%%P"
      )
    )
    if errorlevel 1 (
      echo: [Warning] Failed to install %%P
      set "failed_packages=!failed_packages! %%P"
    ) else (
      set "installed_packages=!installed_packages! %%P"
    )
    CALL :print_separator
  )
  echo:
  IF NOT "!installed_packages!"=="" echo: Installed packages:!installed_packages!
  IF NOT "!failed_packages!"=="" (
    echo: Failed packages:!failed_packages!
    echo: [Error] One or more packages failed to install. The environment was left in place with the successfully installed packages.
    exit /b 1
  )
  exit /b 0

:install_jupyter
  echo: --Installing Jupyter and extensions--
  echo:
  python -m pip install "notebook==6.5.7" "jupyter_contrib_nbextensions==0.7.0" "jupyter_nbextensions_configurator==0.5.0" || exit /b 1
  python -m jupyter contrib nbextension install --user || exit /b 1
  python -m jupyter nbextensions_configurator enable --user || exit /b 1
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
  exit /b 0

:create_cmd_shortcut
  set "shortcut_name=%~1"
  set "shortcut_target=%~2"
  set "shortcut_workdir=%~3"
  set "install_shortcut_created=0"
  set "install_env_shortcut_created=0"
  set "env_lnk=%env_path%\%shortcut_name%.lnk"
  powershell -NoProfile -Command "$s=New-Object -ComObject WScript.Shell;$l=$s.CreateShortcut('%env_lnk%');$l.TargetPath=$env:ComSpec;$l.Arguments='/k ""%shortcut_target%""';$l.WorkingDirectory='%shortcut_workdir%';$l.WindowStyle=1;$l.Save()"
  IF EXIST "%env_lnk%" (
    set "install_env_shortcut_created=1"
  ) ELSE (
    echo: [Warning] Failed to create environment shortcut "%env_lnk%".
  )
  CALL :create_desktop_shortcut "%shortcut_name%" "%shortcut_target%" "%shortcut_workdir%" 1 "cmd" || exit /b 0
  set "install_shortcut_created=1"
  exit /b 0

:create_app_shortcut
  set "shortcut_name=%~1"
  set "shortcut_target=%~2"
  set "shortcut_workdir=%~3"
  set "shortcut_window_style=%~4"
  set "jupyter_shortcut_created=0"
  set "jupyter_env_shortcut_created=0"
  set "env_app_lnk=%env_path%\%shortcut_name%.lnk"
  powershell -NoProfile -Command "$s=New-Object -ComObject WScript.Shell;$l=$s.CreateShortcut('%env_app_lnk%');$l.TargetPath='%shortcut_target%';$l.WorkingDirectory='%shortcut_workdir%';$l.WindowStyle=%shortcut_window_style%;$l.Save()"
  IF EXIST "%env_app_lnk%" (
    set "jupyter_env_shortcut_created=1"
  ) ELSE (
    echo: [Warning] Failed to create environment shortcut "%env_app_lnk%".
  )
  CALL :create_desktop_shortcut "%shortcut_name%" "%shortcut_target%" "%shortcut_workdir%" "%shortcut_window_style%" "app" || exit /b 0
  set "jupyter_shortcut_created=1"
  exit /b 0

:create_desktop_shortcut
  set "shortcut_name=%~1"
  set "shortcut_target=%~2"
  set "shortcut_workdir=%~3"
  set "shortcut_window_style=%~4"
  set "shortcut_type=%~5"
  for /f "delims=" %%D in ('powershell -NoProfile -Command "[Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)"') do set "desktop_path=%%D"
  IF "%desktop_path%"=="" (
    echo: [Warning] Could not determine Desktop folder. Shortcut was not created.
    exit /b 1
  )
  mkdir "%desktop_path%" 2> NUL
  set "desktop_lnk=%desktop_path%\%shortcut_name%.lnk"
  IF "%shortcut_type%"=="cmd" (
    powershell -NoProfile -Command "$s=New-Object -ComObject WScript.Shell;$l=$s.CreateShortcut('%desktop_lnk%');$l.TargetPath=$env:ComSpec;$l.Arguments='/k ""%shortcut_target%""';$l.WorkingDirectory='%shortcut_workdir%';$l.WindowStyle=%shortcut_window_style%;$l.Save()"
  ) ELSE (
    powershell -NoProfile -Command "$s=New-Object -ComObject WScript.Shell;$l=$s.CreateShortcut('%desktop_lnk%');$l.TargetPath='%shortcut_target%';$l.WorkingDirectory='%shortcut_workdir%';$l.WindowStyle=%shortcut_window_style%;$l.Save()"
  )
  IF NOT EXIST "%desktop_lnk%" (
    echo: [Warning] Failed to create Desktop shortcut "%desktop_lnk%".
    exit /b 1
  )
  exit /b 0

:register_conda_env
  set conda_list_path=%USERPROFILE%\.conda\environments.txt
  mkdir "%USERPROFILE%\.conda" 2> NUL
  if not exist "%conda_list_path%" (
    echo Creating conda list %conda_list_path%
    type nul > "%conda_list_path%"
    echo:
  )
  findstr /C:"%env_path%" "%conda_list_path%" >nul 2>&1
  if %errorlevel% EQU 0 (
    echo: --Environment already registered with conda: %env_path%
    echo:
  ) else (
    echo: --Registering environment with conda: %env_path%
    echo %env_path%>>"%conda_list_path%"
    echo:
  )
  exit /b 0

:print_separator
  echo: ============================================================
  exit /b 0

:make_absolute_path
  SET "OUTPUT=%~f1"
  GOTO :EOF

:: this is needed for python to ignore the batch code -> """

##########################################
## Python code for VS Code settings     ##
##########################################

replace_existing = True
import os, re, json, sys

settings = {
    "python.defaultInterpreterPath": os.environ.get(
        "PY_ENV_HELPER_VSCODE_PYTHON",
        os.path.join(os.environ["USERPROFILE"], "Documents", "python_envs", "default_env", "Scripts", "python.exe"),
    ),
    "terminal.integrated.defaultProfile.windows": "Command Prompt",
}

folder_settings = {
    "python.venvFolders": os.environ.get(
        "PY_ENV_HELPER_VENV_FOLDER",
        os.path.join(os.environ["USERPROFILE"], "Documents", "python_envs"),
    )
}

appdata = os.environ["APPDATA"]
path = os.path.join(appdata, "Code", "User", "settings.json")

def read_text(p):
    if not os.path.exists(p) or os.path.getsize(p) == 0:
        return "{\n}\n"
    return open(p, "r", encoding="utf-8").read()

def write_text(p, txt):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(txt)

def set_key_value(jsonc: str, key: str, value_json: str, replace_existing: bool = True) -> str:
    pattern = re.compile(
        rf'^(?P<indent>\s*)"{re.escape(key)}"\s*:\s*(?P<val>[^\r\n]*?)(?P<comma>\s*,?)\s*(?P<cmt>//[^\r\n]*)?$',
        re.M,
    )
    if replace_existing:
        def repl(m):
            cmt = (" " + m.group("cmt")) if m.group("cmt") else ""
            return f'{m.group("indent")}"{key}": {value_json}{m.group("comma") or ""}{cmt}'
        new, n = pattern.subn(repl, jsonc, count=1)
        if n:
            return new
    elif pattern.search(jsonc):
        return jsonc

    ins_pt = jsonc.rfind("}")
    if ins_pt == -1:
        raise RuntimeError("Invalid settings.json: missing closing brace.")
    before = jsonc[:ins_pt].rstrip()
    after = jsonc[ins_pt:]
    prop_lines = [ln for ln in jsonc.splitlines() if re.search(r'^\s*".*?"\s*:', ln)]
    base_indent = re.match(r'^(\s*)', prop_lines[-1]).group(1) if prop_lines else "  "
    prev_non_ws = re.search(r"[^\s]", before[::-1])
    if prev_non_ws and before[::-1][prev_non_ws.start()] not in "{,":
        before += ","
    eol = "\r\n" if "\r\n" in jsonc else "\n"
    return before + f'{eol}{base_indent}"{key}": {value_json}{eol}' + after

def _strip_comments_safe(s: str) -> str:
    out = []
    i = 0
    in_str = esc = in_line = in_block = False
    while i < len(s):
        c = s[i]
        if in_str:
            out.append(c)
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        elif in_line:
            if c in "\r\n":
                in_line = False
                out.append(c)
        elif in_block:
            if c == "*" and i + 1 < len(s) and s[i + 1] == "/":
                in_block = False
                i += 1
        else:
            if c == '"':
                in_str = True
                out.append(c)
            elif c == "/" and i + 1 < len(s) and s[i + 1] == "/":
                in_line = True
                i += 1
            elif c == "/" and i + 1 < len(s) and s[i + 1] == "*":
                in_block = True
                i += 1
            else:
                out.append(c)
        i += 1
    return "".join(out)

def _skip_ws_comments(s: str, i: int) -> int:
    while i < len(s):
        c = s[i]
        if c in " \t\r\n":
            i += 1
            continue
        if c == "/" and i + 1 < len(s) and s[i + 1] == "/":
            i += 2
            while i < len(s) and s[i] not in "\r\n":
                i += 1
            continue
        if c == "/" and i + 1 < len(s) and s[i + 1] == "*":
            i += 2
            while i + 1 < len(s):
                if s[i] == "*" and s[i + 1] == "/":
                    i += 2
                    break
                i += 1
            continue
        break
    return i

def add_to_folder(jsonc: str, key: str, elem: str) -> str:
    m = re.search(rf'"{re.escape(key)}"\s*:', jsonc)
    if not m:
        return set_key_value(jsonc, key, f'["{elem}"]')
    i = _skip_ws_comments(jsonc, m.end())
    if i >= len(jsonc) or jsonc[i] != "[":
        return set_key_value(jsonc, key, f'["{elem}"]')

    lb = i
    i += 1
    depth = 1
    in_str = esc = in_line = in_block = False
    while i < len(jsonc):
        c = jsonc[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        elif in_line:
            if c in "\r\n":
                in_line = False
        elif in_block:
            if c == "*" and i + 1 < len(jsonc) and jsonc[i + 1] == "/":
                in_block = False
                i += 1
        else:
            if c == '"':
                in_str = True
            elif c == "/" and i + 1 < len(jsonc) and jsonc[i + 1] == "/":
                in_line = True
                i += 1
            elif c == "/" and i + 1 < len(jsonc) and jsonc[i + 1] == "*":
                in_block = True
                i += 1
            elif c == "[":
                depth += 1
            elif c == "]":
                depth -= 1
                if depth == 0:
                    rb = i
                    break
        i += 1
    else:
        raise RuntimeError(f"Unclosed array for {key}")

    inner = jsonc[lb + 1 : rb]
    body = re.sub(r',\s*(?=[]}])', '', _strip_comments_safe(inner))
    try:
        arr = json.loads("[" + body + "]")
    except json.JSONDecodeError:
        arr = re.findall(r'"((?:\\.|[^"\\])*)"', body)
    if any(isinstance(x, str) and x == elem for x in arr):
        return jsonc

    if "\n" not in inner and "\r" not in inner:
        return jsonc[: lb + 1] + (inner.rstrip() + (", " if _strip_comments_safe(inner).strip() else "") + f'"{elem}"') + jsonc[rb :]

    eol = "\r\n" if "\r\n" in jsonc else "\n"
    line_start = jsonc.rfind("\n", 0, rb) + 1
    closing_indent = re.match(r"^(\s*)", jsonc[line_start:rb]).group(1)
    lines = inner.splitlines()
    for j in range(len(lines) - 1, -1, -1):
        if _strip_comments_safe(lines[j]).strip():
            if not _strip_comments_safe(lines[j]).rstrip().endswith(","):
                lines[j] = lines[j].rstrip() + ","
            break
    lines.append(f'{closing_indent}  "{elem}"')
    return jsonc[: lb + 1] + eol.join(lines) + jsonc[rb :]

txt = read_text(path)
for setting_key, value in settings.items():
    txt = set_key_value(txt, setting_key, '"' + value.replace('"', '\\"') + '"', replace_existing)
for folder_key, elem in folder_settings.items():
    txt = add_to_folder(txt, folder_key, elem)
write_text(path, txt)
print(" --Updated VS-Code settings--")
sys.exit(0)

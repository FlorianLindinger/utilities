@setlocal EnableDelayedExpansion & @echo off
REM=r""" <- lets Python ignore the batch part of this file.
:: The first line is skipped when this file is launched with `py -x`.
:: The Python code starts near the bottom.
CALL :process_args %* || goto :fail

:: ---------------------------------------------------------------------------
:: Python Environment Helper
:: ---------------------------------------------------------------------------
:: Creates or reuses a Python virtual environment, installs requested packages,
:: optionally installs Jupyter tooling, registers the env as a Jupyter kernel,
:: optionally exposes it to conda-based tools, and can update VS Code settings.
::
:: When VS Code updates are enabled, the script writes:
::   %APPDATA%\Code\User\settings.json
:: It changes this key:
::   python.defaultInterpreterPath

:: ---------------------------------------------------------------------------
:: Command-line flags
:: ---------------------------------------------------------------------------
:: --path PATH              Environment folder path.
:: --packages "PKG PKG"     Space-separated packages to install.
:: --version VERSION        Python version prefix or exact release, e.g. 3, 3.13, 3.13.5.
:: --vscode-default Y|N     Update VS Code user settings listed above.
:: --register-conda Y|N     Add the env path to conda's environments list.
:: --jupyter Y|N            Install Jupyter tools and create a shortcut.
:: --folder PATH            Jupyter notebooks folder.
::
:: If any flag is supplied, the settings dialog is skipped. Any omitted values
:: fall back to the defaults below.

:: ---------------------------------------------------------------------------
:: Defaults
:: ---------------------------------------------------------------------------
:: def_env_path          Full fallback path when no env path is provided.
:: def_folder            Jupyter notebook start folder.
:: def_* checkbox values Default GUI checkbox states.

SET "def_env_path=%USERPROFILE%\Documents\python_envs\default_env"
SET "def_folder=%USERPROFILE%\Documents\python_notebooks"
SET "def_version=3"
SET "def_do_jupyter=N"
SET "def_set_vscode_default=N"
SET "def_register_conda=N"
SET "def_packages=cupy-cuda12x html5lib ipykernel ipympl ipywidgets matplotlib numba nuitka numpy nvmath-python nptdms opencv-python openpyxl pandas pillow py7zr pyarrow pyautogui pyserial pyside6 pywin32 pywinauto pyyaml scipy scipy-stubs tifffile tqdm"

:: ---------------------------------------------------------------------------
:: Resolve configuration
:: ---------------------------------------------------------------------------
:: Merge command-line args, GUI values, and defaults into final settings before
:: touching Python, folders, packages, shortcuts, or editor settings.

IF "%folder%"=="" SET "folder=%def_folder%"
IF "%packages%"=="" SET "packages=%def_packages%"
IF "%env_path%"=="" SET "env_path=%def_env_path%"
IF /I "%skip_settings_dialog%"=="Y" (
  IF "%version%"=="" SET "version=%def_version%"
  IF "%do_jupyter%"=="" SET "do_jupyter=%def_do_jupyter%"
  IF "%set_vscode_default%"=="" SET "set_vscode_default=%def_set_vscode_default%"
  IF "%register_conda%"=="" SET "register_conda=%def_register_conda%"
) ELSE (
  SET "needs_settings_dialog="
  IF "%version%"=="" SET "needs_settings_dialog=Y"
  IF "%do_jupyter%"=="" SET "needs_settings_dialog=Y"
  IF "%set_vscode_default%"=="" SET "needs_settings_dialog=Y"
  IF "%register_conda%"=="" SET "needs_settings_dialog=Y"
  IF "!needs_settings_dialog!"=="Y" (
    CALL :prompt_environment_settings
    IF ERRORLEVEL 2 GOTO :cancelled
    IF ERRORLEVEL 1 GOTO :fail
  )
)
IF "%env_path%"=="" SET "env_path=%def_env_path%"
CALL :normalize_yes_no "do_jupyter" || goto :fail
CALL :normalize_yes_no "set_vscode_default" || goto :fail
CALL :normalize_yes_no "register_conda" || goto :fail
CALL :resolve_python_version || goto :fail

CALL :make_absolute_path "%env_path%" || goto :fail
SET "env_path=%OUTPUT%"
CALL :make_absolute_path "%folder%" || goto :fail
SET "folder=%OUTPUT%"

for %%F in ("%env_path%") do set "env_name=%%~nxF"

:: ---------------------------------------------------------------------------
:: Create and configure environment
:: ---------------------------------------------------------------------------
:: Ensure the requested Python exists, create/activate the venv, install
:: packages, add optional tooling, create shortcuts, and apply integrations.

echo: --Settings--
echo:
echo: Environment path: %env_path%
echo: Python version request: %version_request%
echo: Python final release: %version%
echo: Python packages: %packages%
echo: Update VS Code settings: %set_vscode_default%
echo: Register with conda: %register_conda%
echo: Setup Jupyter: %do_jupyter%
echo: Notebooks folder: %folder%
echo:
echo:

CALL :ensure_python || goto :fail
SET "venv_python_version=%version%"

IF /I "%do_jupyter%"=="Y" (
  CALL :ensure_python_path || goto :fail
)

:: Create and activate venv.
IF EXIST "%env_path%" (
  CALL :existing_env_is_empty
  IF ERRORLEVEL 1 (
    CALL :existing_env_matches_version
    IF ERRORLEVEL 1 (
      CALL :wait_for_existing_env_deletion || goto :fail
      CALL :create_venv || goto :fail
      echo: --Created python environment--
    ) ELSE (
      echo: --Environment already exists with Python %venv_python_version%--
    )
  ) ELSE (
    echo: --Environment folder exists and is empty--
    CALL :create_venv || goto :fail
    echo: --Created python environment--
  )
) ELSE (
  CALL :create_venv || goto :fail
  echo: --Created python environment--
)
call "%env_path%\Scripts\activate.bat" || goto :fail
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

SET "install_shortcut_name=Install package (%env_name%)"
SET "install_cmd_path=%env_path%\%install_shortcut_name%.cmd"
> "!install_cmd_path!" (
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
CALL :create_cmd_shortcut "%install_shortcut_name%" "%install_cmd_path%" "%env_path%" || goto :fail

IF /I "%register_conda%"=="Y" (
  CALL :register_conda_env || goto :fail
)

:: Optionally update VS Code user settings.
IF /I "%set_vscode_default%"=="Y" (
  set "PY_ENV_HELPER_VSCODE_PYTHON=%env_path%\Scripts\python.exe"
  py -x "%~f0"
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

:cancelled
echo:
echo: Setup cancelled.
exit /b 0

:: ---------------------------------------------------------------------------
:: Batch subroutines
:: ---------------------------------------------------------------------------
:: Keep the main flow above readable. Each label exits with a batch errorlevel.

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
  IF "%~1"=="--path" SET "skip_settings_dialog=Y" & SET "env_path=%~2" & shift & shift & GOTO process_args
  IF "%~1"=="--folder" SET "skip_settings_dialog=Y" & SET "folder=%~2" & shift & shift & GOTO process_args
  IF "%~1"=="--packages" SET "skip_settings_dialog=Y" & SET "packages=%~2" & shift & shift & GOTO process_args
  IF "%~1"=="--version" SET "skip_settings_dialog=Y" & SET "version=%~2" & shift & shift & GOTO process_args
  IF "%~1"=="--jupyter" SET "skip_settings_dialog=Y" & SET "do_jupyter=%~2" & shift & shift & GOTO process_args
  IF "%~1"=="--vscode-default" SET "skip_settings_dialog=Y" & SET "set_vscode_default=%~2" & shift & shift & GOTO process_args
  IF "%~1"=="--register-conda" SET "skip_settings_dialog=Y" & SET "register_conda=%~2" & shift & shift & GOTO process_args
  IF "%env_path%"=="" SET "env_path=%~1" & shift & GOTO process_args
  IF "%version%"=="" SET "version=%~1" & shift & GOTO process_args
  IF "%packages%"=="" SET "packages=%~1" & shift & GOTO process_args
  GOTO :EOF

:existing_env_is_empty
  for /f "delims=" %%F in ('dir /a /b "%env_path%" 2^>nul') do exit /b 1
  exit /b 0

:existing_env_matches_version
  IF NOT EXIST "%env_path%\Scripts\python.exe" (
    echo:
    echo: Existing environment folder does not contain Scripts\python.exe.
    exit /b 1
  )
  "%env_path%\Scripts\python.exe" -c "import platform, sys; sys.exit(0 if platform.python_version() == '%version%' else 1)" >nul 2>&1
  IF ERRORLEVEL 1 (
    set "existing_env_python_version="
    CALL :read_python_version "%env_path%\Scripts\python.exe" existing_env_python_version
    IF "!existing_env_python_version!"=="" (
      CALL :read_venv_cfg_version existing_env_python_version
      IF NOT "!existing_env_python_version!"=="" (
        set "existing_env_python_version=!existing_env_python_version! (from pyvenv.cfg; Scripts\python.exe did not run)"
      )
    )
    IF "!existing_env_python_version!"=="" (
      set "existing_env_python_version=unknown (Scripts\python.exe did not run)"
    )
    echo:
    echo: Existing environment Python version does not match version.
    echo:   Environment path: "%env_path%"
    echo:   Existing version:  !existing_env_python_version!
    echo:   Required version:  %version%
    exit /b 1
  )
  exit /b 0

:read_python_version
  set "%~2="
  set "read_python_exe=%~1"
  for /f "tokens=2 delims= " %%V in ('cmd /s /c ""!read_python_exe!" --version" 2^>nul') do set "%~2=%%V"
  set "read_python_exe="
  exit /b 0

:read_venv_cfg_version
  set "%~1="
  IF NOT EXIST "%env_path%\pyvenv.cfg" exit /b 0
  for /f "tokens=1,* delims==" %%A in ('findstr /B /I "version" "%env_path%\pyvenv.cfg" 2^>nul') do (
    set "cfg_key=%%A"
    set "cfg_key=!cfg_key: =!"
    IF /I "!cfg_key!"=="version" (
      set "cfg_value=%%B"
      for /f "tokens=* delims= " %%V in ("!cfg_value!") do set "%~1=%%V"
    )
  )
  exit /b 0

:wait_for_existing_env_deletion
  echo:
  echo: --Environment already exists--
  echo: Environment path:
  echo:   "%env_path%"
  echo:
  echo: Opened the existing environment folder.
  echo: Delete that folder, then press any key here to continue.
  echo: Press Ctrl+C to cancel.
  start "" explorer "%env_path%"
:wait_for_env_delete
  pause > nul
  IF EXIST "%env_path%" (
    echo:
    echo: Environment folder still exists:
    echo:   "%env_path%"
    echo: Delete it, then press any key to check again.
    GOTO wait_for_env_delete
  )
  echo:
  echo: --Environment folder deleted. Continuing--
  echo:
  exit /b 0

:prompt_environment_settings
  IF "%env_path%"=="" set "env_path=%def_env_path%"
  IF "%folder%"=="" set "folder=%def_folder%"
  IF "%packages%"=="" set "packages=%def_packages%"
  IF "%version%"=="" set "version=%def_version%"
  IF "%do_jupyter%"=="" set "do_jupyter=%def_do_jupyter%"
  IF "%set_vscode_default%"=="" set "set_vscode_default=%def_set_vscode_default%"
  IF "%register_conda%"=="" set "register_conda=%def_register_conda%"
  for /f "tokens=1,* delims==" %%A in ('powershell -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; $form=New-Object System.Windows.Forms.Form; $form.Text='Python environment settings'; $form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedDialog'; $form.MaximizeBox=$false; $form.MinimizeBox=$false; $form.ClientSize=New-Object System.Drawing.Size(640,490); $pathLabel=New-Object System.Windows.Forms.Label; $pathLabel.Text='Environment path:'; $pathLabel.Location=New-Object System.Drawing.Point(12,16); $pathLabel.AutoSize=$true; $form.Controls.Add($pathLabel); $pathText=New-Object System.Windows.Forms.TextBox; $pathText.Location=New-Object System.Drawing.Point(250,13); $pathText.Size=New-Object System.Drawing.Size(345,22); $pathText.Text='%env_path%'; $form.Controls.Add($pathText); $versionLabel=New-Object System.Windows.Forms.Label; $versionLabel.Text='Python version (picks newest' + [Environment]::NewLine + 'compatible full release):'; $versionLabel.Location=New-Object System.Drawing.Point(12,47); $versionLabel.Size=New-Object System.Drawing.Size(235,36); $form.Controls.Add($versionLabel); $text=New-Object System.Windows.Forms.TextBox; $text.Location=New-Object System.Drawing.Point(250,53); $text.Size=New-Object System.Drawing.Size(160,22); $text.Text='%version%'; $form.Controls.Add($text); $packagesLabel=New-Object System.Windows.Forms.Label; $packagesLabel.Text='Packages:'; $packagesLabel.Location=New-Object System.Drawing.Point(12,96); $packagesLabel.AutoSize=$true; $form.Controls.Add($packagesLabel); $packagesText=New-Object System.Windows.Forms.TextBox; $packagesText.Location=New-Object System.Drawing.Point(250,93); $packagesText.Size=New-Object System.Drawing.Size(345,135); $packagesText.Multiline=$true; $packagesText.ScrollBars='Vertical'; $packagesText.WordWrap=$true; $packagesText.Text='%packages%'; $form.Controls.Add($packagesText); $v=New-Object System.Windows.Forms.CheckBox; $v.Text='Set VS Code default interpreter'; $v.Location=New-Object System.Drawing.Point(15,250); $v.Size=New-Object System.Drawing.Size(360,24); $v.Checked=('%set_vscode_default%' -ieq 'Y' -or '%set_vscode_default%' -ieq 'YES'); $form.Controls.Add($v); $vs=New-Object System.Windows.Forms.Label; $vs.Text='(Writes python.defaultInterpreterPath in %APPDATA%\Code\User\settings.json)'; $vs.Location=New-Object System.Drawing.Point(35,274); $vs.Size=New-Object System.Drawing.Size(560,34); $form.Controls.Add($vs); $c=New-Object System.Windows.Forms.CheckBox; $c.Text='Register environment with conda'; $c.Location=New-Object System.Drawing.Point(15,315); $c.Size=New-Object System.Drawing.Size(360,24); $c.Checked=('%register_conda%' -ieq 'Y' -or '%register_conda%' -ieq 'YES'); $form.Controls.Add($c); $j=New-Object System.Windows.Forms.CheckBox; $j.Text='Install Jupyter Notebook tools and shortcut'; $j.Location=New-Object System.Drawing.Point(15,345); $j.Size=New-Object System.Drawing.Size(360,24); $j.Checked=('%do_jupyter%' -ieq 'Y' -or '%do_jupyter%' -ieq 'YES'); $form.Controls.Add($j); $folderLabel=New-Object System.Windows.Forms.Label; $folderLabel.Text='Jupyter notebooks folder:'; $folderLabel.Location=New-Object System.Drawing.Point(12,383); $folderLabel.AutoSize=$true; $form.Controls.Add($folderLabel); $folderText=New-Object System.Windows.Forms.TextBox; $folderText.Location=New-Object System.Drawing.Point(165,380); $folderText.Size=New-Object System.Drawing.Size(430,22); $folderText.Text='%folder%'; $form.Controls.Add($folderText); $folderLabel.Enabled=$j.Checked; $folderText.Enabled=$j.Checked; $j.Add_CheckedChanged({ $folderLabel.Enabled=$j.Checked; $folderText.Enabled=$j.Checked }); $ok=New-Object System.Windows.Forms.Button; $ok.Text='Create'; $ok.Location=New-Object System.Drawing.Point(450,440); $ok.DialogResult=[System.Windows.Forms.DialogResult]::OK; $form.AcceptButton=$ok; $form.Controls.Add($ok); $cancel=New-Object System.Windows.Forms.Button; $cancel.Text='Cancel'; $cancel.Location=New-Object System.Drawing.Point(535,440); $cancel.DialogResult=[System.Windows.Forms.DialogResult]::Cancel; $form.CancelButton=$cancel; $form.Controls.Add($cancel); $result=$form.ShowDialog(); if ($result -eq [System.Windows.Forms.DialogResult]::OK) { $ep=$pathText.Text.Trim(); if (-not $ep) { $ep='%def_env_path%' }; $nf=$folderText.Text.Trim(); if (-not $nf) { $nf='%def_folder%' }; $pv=$text.Text.Trim(); if (-not $pv) { $pv='%def_version%' }; $pk=($packagesText.Text -replace '[\r\n\t]+',' ').Trim(); if (-not $pk) { $pk='%def_packages%' }; Write-Output ('env_path=' + $ep); Write-Output ('folder=' + $nf); Write-Output ('version=' + $pv); Write-Output ('packages=' + $pk); Write-Output ('do_jupyter=' + $(if ($j.Checked) { 'Y' } else { 'N' })); Write-Output ('set_vscode_default=' + $(if ($v.Checked) { 'Y' } else { 'N' })); Write-Output ('register_conda=' + $(if ($c.Checked) { 'Y' } else { 'N' })) } else { Write-Output 'cancelled=1' }"') do set "%%A=%%B"
  IF "%cancelled%"=="1" exit /b 2
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
  set "python_exe="
  set "std_py_path=%LocalAppData%\Programs\Python\"
  for /f "tokens=1,2 delims=." %%A in ("%launcher_version%") do set "installed_python_exe=%std_py_path%Python%%A%%B\python.exe"
  IF EXIST "%installed_python_exe%" (
    "%installed_python_exe%" -c "import platform, sys; sys.exit(0 if platform.python_version() == '%version%' else 1)" >nul 2>&1
    IF NOT ERRORLEVEL 1 set "python_exe=%installed_python_exe%"
  )
  IF DEFINED python_exe (
    "%python_exe%" -c "import platform, sys; sys.exit(0 if platform.python_version() == '%version%' else 1)" >nul 2>&1
  ) ELSE (
    py -%launcher_version% -c "import platform, sys; sys.exit(0 if platform.python_version() == '%version%' else 1)" >nul 2>&1
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
    IF EXIST "%installed_python_exe%" (
      "%installed_python_exe%" -c "import platform, sys; sys.exit(0 if platform.python_version() == '%version%' else 1)" >nul 2>&1
      IF NOT ERRORLEVEL 1 set "python_exe=%installed_python_exe%"
    )
    IF DEFINED python_exe (
      "%python_exe%" -c "import platform, sys; sys.exit(0 if platform.python_version() == '%version%' else 1)" >nul 2>&1 || exit /b 1
    ) ELSE (
      py -%launcher_version% -c "import platform, sys; sys.exit(0 if platform.python_version() == '%version%' else 1)" >nul 2>&1 || exit /b 1
    )
    echo:
    echo: --Finished installing Python %version% on computer--
  ) ELSE (
    set "computer_python_version=%version%"
    IF /I "%exact_version_requested%"=="Y" (
      echo: --Exact Python %computer_python_version% already installed on computer--
    ) ELSE (
      echo: --Compatible Python %computer_python_version% already installed on computer--
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

:create_venv
  IF DEFINED python_exe (
    "%python_exe%" -m venv "%env_path%" || exit /b 1
  ) ELSE (
    py -%launcher_version% -m venv "%env_path%" || exit /b 1
  )
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
  powershell -NoProfile -Command "$s=New-Object -ComObject WScript.Shell;$l=$s.CreateShortcut('%env_lnk%');$l.TargetPath=$env:ComSpec;$l.Arguments='/k call ""%shortcut_target%""';$l.WorkingDirectory='%shortcut_workdir%';$l.WindowStyle=1;$l.Save()"
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
    powershell -NoProfile -Command "$s=New-Object -ComObject WScript.Shell;$l=$s.CreateShortcut('%desktop_lnk%');$l.TargetPath=$env:ComSpec;$l.Arguments='/k call ""%shortcut_target%""';$l.WorkingDirectory='%shortcut_workdir%';$l.WindowStyle=%shortcut_window_style%;$l.Save()"
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

:: End the Python raw string that hides the batch code. -> """

# ---------------------------------------------------------------------------
# VS Code settings updater
# ---------------------------------------------------------------------------
# Runs only when the batch section calls `py -x "%~f0"`. It updates the user
# settings JSONC while preserving comments where practical.

replace_existing = True
import os, re, sys

settings = {
    "python.defaultInterpreterPath": os.environ.get(
        "PY_ENV_HELPER_VSCODE_PYTHON",
        os.path.join(os.environ["USERPROFILE"], "Documents", "python_envs", "default_env", "Scripts", "python.exe"),
    ),
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

txt = read_text(path)
for setting_key, value in settings.items():
    txt = set_key_value(txt, setting_key, '"' + value.replace('"', '\\"') + '"', replace_existing)
write_text(path, txt)
print(" --Updated VS Code default interpreter setting--")
sys.exit(0)

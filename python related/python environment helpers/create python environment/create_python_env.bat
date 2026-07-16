@setlocal EnableDelayedExpansion & @echo off
REM=r""" <- lets Python ignore the batch part of this file.
:: The first line is skipped when this file is launched with `py -x`.
:: The Python code starts near the bottom.
CALL :process_args %* || goto :fail

:: ---------------------------------------------------------------------------
:: Python Environment Helper
:: ---------------------------------------------------------------------------
:: Creates or reuses a Python virtual environment, installs requested packages,
:: optionally installs Jupyter notebook kernel support, registers the env as a
:: Jupyter kernel, and can update VS Code settings.
::
:: When VS Code updates are enabled, the script writes:
::   %APPDATA%\Code\User\settings.json
:: It can change these keys:
::   python.defaultInterpreterPath
::   python-envs.globalSearchPaths
:: It also migrates the deprecated python.venvFolders setting.

:: ---------------------------------------------------------------------------
:: Command-line flags
:: ---------------------------------------------------------------------------
:: --path PATH              Environment folder path.
:: --packages "PKG PKG"     Space-separated packages to install.
:: --version VERSION        Python version prefix or exact release, e.g. 3, 3.13, 3.13.5.
:: --vscode-default Y|N     Set VS Code default interpreter.
:: --vscode-search-path Y|N Add the env parent folder to VS Code env search paths.
:: --notebook-support Y|N   Install notebook support: ipykernel ipympl.
:: --desktop-shortcuts Y|N  Copy environment shortcuts to the Desktop.
:: --add-to-path Y|N        Add env and Scripts to user PATH for new terminals.
::
:: If any flag is supplied, the settings dialog is skipped. Any omitted values
:: fall back to the defaults below.

:: ---------------------------------------------------------------------------
:: Defaults
:: ---------------------------------------------------------------------------
:: def_env_path          Full fallback path when no env path is provided.
:: def_* checkbox values Default GUI checkbox states.

SET "def_env_path=%USERPROFILE%\Documents\python_envs\default_env"
SET "def_version=3"
SET "def_install_notebook_support=Y"
SET "def_set_vscode_default=N"
SET "def_set_vscode_search_path=N"
SET "def_create_desktop_shortcuts=Y"
SET "def_add_to_path=N"
SET "validate_jupyter_kernel=N"
SET "def_packages=numpy matplotlib scipy pandas pyyaml pillow tqdm pyarrow openpyxl opencv-python ipywidgets pywin32 pyserial numba pyside6 html5lib rich tifffile pyautogui nuitka py7zr pywinauto nptdms scipy-stubs cupy-cuda12x nvmath-python"

:: ---------------------------------------------------------------------------
:: Resolve configuration
:: ---------------------------------------------------------------------------
:: Merge command-line args, GUI values, and defaults into final settings before
:: touching Python, folders, packages, shortcuts, or editor settings.

IF NOT "%packages_was_set%"=="Y" IF "%packages%"=="" SET "packages=%def_packages%"
IF "%env_path%"=="" SET "env_path=%def_env_path%"
IF /I "%skip_settings_dialog%"=="Y" (
  IF "%version%"=="" SET "version=%def_version%"
  IF "%install_notebook_support%"=="" SET "install_notebook_support=%def_install_notebook_support%"
  IF "%set_vscode_default%"=="" SET "set_vscode_default=%def_set_vscode_default%"
  IF "%set_vscode_search_path%"=="" SET "set_vscode_search_path=%def_set_vscode_search_path%"
  IF "%create_desktop_shortcuts%"=="" SET "create_desktop_shortcuts=%def_create_desktop_shortcuts%"
  IF "%add_to_path%"=="" SET "add_to_path=%def_add_to_path%"
) ELSE (
  SET "needs_settings_dialog="
  IF "%version%"=="" SET "needs_settings_dialog=Y"
  IF "%install_notebook_support%"=="" SET "needs_settings_dialog=Y"
  IF "%set_vscode_default%"=="" SET "needs_settings_dialog=Y"
  IF "%set_vscode_search_path%"=="" SET "needs_settings_dialog=Y"
  IF "%create_desktop_shortcuts%"=="" SET "needs_settings_dialog=Y"
  IF "%add_to_path%"=="" SET "needs_settings_dialog=Y"
  IF "!needs_settings_dialog!"=="Y" (
    CALL :prompt_environment_settings
    IF ERRORLEVEL 2 GOTO :cancelled
    IF ERRORLEVEL 1 GOTO :fail
  )
)
IF "%env_path%"=="" SET "env_path=%def_env_path%"
CALL :normalize_yes_no "install_notebook_support" || goto :fail
CALL :normalize_yes_no "set_vscode_default" || goto :fail
CALL :normalize_yes_no "set_vscode_search_path" || goto :fail
CALL :normalize_yes_no "create_desktop_shortcuts" || goto :fail
CALL :normalize_yes_no "add_to_path" || goto :fail
CALL :resolve_python_version || goto :fail
CALL :print_installed_python_that_would_be_used

CALL :make_absolute_path "%env_path%" || goto :fail
SET "env_path=%OUTPUT%"
for %%F in ("%env_path%\..") do SET "env_parent_path=%%~fF"

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
echo: Python packages: %packages%
echo: Set VS Code default interpreter: %set_vscode_default%
echo: Add VS Code env search path: %set_vscode_search_path%
IF /I "%set_vscode_search_path%"=="Y" echo: VS Code env search path: %env_parent_path%
echo: Install Jupyter notebook support (ipykernel ipympl): %install_notebook_support%
echo: Copy environment shortcuts to Desktop: %create_desktop_shortcuts%
echo: Add environment to user PATH: %add_to_path%
echo:
echo:

SET "venv_python_version=%version%"

:: Create and activate venv.
IF EXIST "%env_path%" (
  CALL :existing_env_is_empty
  IF ERRORLEVEL 1 (
    CALL :existing_env_matches_version
    IF ERRORLEVEL 1 (
      CALL :fail_existing_env_reuse || goto :fail
      CALL :ensure_python || goto :fail
      CALL :create_venv || goto :fail
      echo: --Created python environment--
    ) ELSE (
      echo: --Environment already exists with Python %venv_python_version%--
    )
  ) ELSE (
    echo: --Environment folder exists and is empty--
    CALL :ensure_python || goto :fail
    CALL :create_venv || goto :fail
    echo: --Created python environment--
  )
) ELSE (
  CALL :ensure_python || goto :fail
  CALL :create_venv || goto :fail
  echo: --Created python environment--
)
call "%env_path%\Scripts\activate.bat" || goto :fail
echo:
echo: --Activated python environment--
echo:

mkdir "%USERPROFILE%\Documents\Repositories" 2> NUL

:: Create Python launch and package-install shortcuts.
SET "python_shortcut_name=python (%env_name%)"
CALL :create_python_shortcut "%python_shortcut_name%" "%env_path%\Scripts\python.exe" "%env_path%" || goto :fail

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

IF /I "%add_to_path%"=="Y" (
  CALL :add_env_to_path || goto :fail
)

:: Optionally update VS Code user settings.
set "update_vscode_settings="
IF /I "%set_vscode_default%"=="Y" set "update_vscode_settings=Y"
IF /I "%set_vscode_search_path%"=="Y" set "update_vscode_settings=Y"
IF /I "%update_vscode_settings%"=="Y" (
  set "PY_ENV_HELPER_VSCODE_PYTHON="
  set "PY_ENV_HELPER_VSCODE_SEARCH_PATH="
  IF /I "%set_vscode_default%"=="Y" set "PY_ENV_HELPER_VSCODE_PYTHON=%env_path%\Scripts\python.exe"
  IF /I "%set_vscode_search_path%"=="Y" set "PY_ENV_HELPER_VSCODE_SEARCH_PATH=%env_parent_path%"
  set "PY_ENV_HELPER_ACTION=update_vscode_settings"
  "%env_path%\Scripts\python.exe" -x "%~f0"
  set "PY_ENV_HELPER_ACTION="
) 

:: Install requested packages first. Install and validate Jupyter last so later
:: package installs cannot silently replace one of its runtime dependencies.
set "needs_package_install="
IF NOT "%packages%"=="" set "needs_package_install=Y"
IF /I "%install_notebook_support%"=="Y" set "needs_package_install=Y"
IF /I "%needs_package_install%"=="Y" (
  echo:
  echo: --Preparing package installer--
  echo:
  python -m pip install --upgrade pip
  IF ERRORLEVEL 1 (
    set "pip_upgrade_failed=Y"
    echo: [Warning] Failed to upgrade pip. Continuing with package installation.
  )
  CALL :ensure_uv
  IF NOT "%packages%"=="" (
    echo: --Installing requested packages--
    echo:
    CALL :install_packages "%packages%"
    echo:
    echo: --Finished installing requested packages--
    echo:
  )
  IF /I "%install_notebook_support%"=="Y" CALL :finish_jupyter_setup
) ELSE (
  echo:
  echo: --No package installation requested--
  echo:
)

set "setup_warnings="
IF "%pip_upgrade_failed%"=="Y" (
  echo: [Warning] pip upgrade failed.
  set "setup_warnings=Y"
)
IF NOT "!failed_packages!"=="" (
  echo: [Warning] Failed packages:!failed_packages!
  set "setup_warnings=Y"
)
IF "%jupyter_support_failed%"=="Y" (
  echo: [Warning] Jupyter notebook support install failed.
  set "setup_warnings=Y"
)
IF "%jupyter_kernel_failed%"=="Y" (
  echo: [Warning] Jupyter kernel registration failed.
  set "setup_warnings=Y"
)
IF "%jupyter_kernel_test_failed%"=="Y" (
  echo: [Warning] Jupyter kernel handshake test failed.
  set "setup_warnings=Y"
)
echo:
echo:
IF "%setup_warnings%"=="Y" (
  echo: Setup completed with warnings. Review the warnings above.
) ELSE (
  echo: Setup finished successfully.
)
echo: Created environment in "%env_path%".
IF "%python_env_shortcut_created%"=="1" echo: Created shortcut in environment folder ("python (%env_name%)"^) for launching Python.
IF "%python_desktop_shortcut_created%"=="1" echo: Created shortcut on Desktop ("python (%env_name%)"^) for launching Python.
IF "%install_env_shortcut_created%"=="1" echo: Created shortcut in environment folder ("Install package (%env_name%)"^) for installing packages.
IF "%install_shortcut_created%"=="1" echo: Created shortcut on Desktop ("Install package (%env_name%)") for installing packages.
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
  echo: Fix the error shown above, then run this script again.
  echo: Press any key to exit.
  pause > nul
  exit /b 1

:process_args
  IF "%~1"=="" GOTO :EOF
  IF "%~1"=="--path" (
    SET "skip_settings_dialog=Y"
    SET "env_path=%~2"
    shift
    shift
    GOTO process_args
  )
  IF "%~1"=="--packages" (
    SET "skip_settings_dialog=Y"
    SET "packages_was_set=Y"
    SET "next_arg=%~2"
    IF "!next_arg!"=="" (
      SET "packages="
      shift
    ) ELSE IF "!next_arg:~0,2!"=="--" (
      SET "packages="
      shift
      GOTO process_args
    ) ELSE (
      SET "packages=%~2"
      shift
    )
    shift
    GOTO process_args
  )
  IF "%~1"=="--version" (
    SET "skip_settings_dialog=Y"
    SET "version=%~2"
    shift
    shift
    GOTO process_args
  )
  IF "%~1"=="--notebook-support" (
    SET "skip_settings_dialog=Y"
    SET "install_notebook_support=%~2"
    shift
    shift
    GOTO process_args
  )
  IF "%~1"=="--vscode-default" (
    SET "skip_settings_dialog=Y"
    SET "set_vscode_default=%~2"
    shift
    shift
    GOTO process_args
  )
  IF "%~1"=="--vscode-search-path" (
    SET "skip_settings_dialog=Y"
    SET "set_vscode_search_path=%~2"
    shift
    shift
    GOTO process_args
  )
  IF "%~1"=="--desktop-shortcuts" (
    SET "skip_settings_dialog=Y"
    SET "create_desktop_shortcuts=%~2"
    shift
    shift
    GOTO process_args
  )
  IF "%~1"=="--add-to-path" (
    SET "skip_settings_dialog=Y"
    SET "add_to_path=%~2"
    shift
    shift
    GOTO process_args
  )
  IF "%env_path%"=="" (
    SET "env_path=%~1"
    shift
    GOTO process_args
  )
  IF "%version%"=="" (
    SET "version=%~1"
    shift
    GOTO process_args
  )
  IF "%packages_was_set%"=="" (
    SET "packages_was_set=Y"
    SET "packages=%~1"
    shift
    GOTO process_args
  )
  GOTO :EOF

:existing_env_is_empty
  for /f "delims=" %%F in ('dir /a /b "%env_path%" 2^>nul') do (
    IF /I NOT "%%F"=="_python_env_setup_problem.txt" IF /I NOT "%%F"=="desktop.ini" exit /b 1
  )
  exit /b 0

:existing_env_matches_version
  set "existing_env_problem="
  set "existing_env_python_version="
  set "existing_env_cfg_python_version="
  set "existing_env_warning="
  IF NOT EXIST "%env_path%\Scripts\python.exe" (
    set "existing_env_problem=Existing environment folder does not contain Scripts\python.exe."
    set "existing_env_python_version=unknown"
    set "existing_env_warning=Cannot read the existing environment Python version. The folder might not be a Python virtual environment."
    echo:
    echo: !existing_env_problem!
    echo: !existing_env_warning!
    exit /b 1
  )
  CALL :read_python_version "%env_path%\Scripts\python.exe" existing_env_python_version
  CALL :version_matches_request "!existing_env_python_version!"
  IF NOT ERRORLEVEL 1 (
    set "venv_python_version=!existing_env_python_version!"
    exit /b 0
  )
  IF "!existing_env_python_version!"=="" (
    CALL :read_venv_cfg_version existing_env_cfg_python_version
    CALL :version_matches_request "!existing_env_cfg_python_version!"
    IF NOT ERRORLEVEL 1 (
      set "venv_python_version=!existing_env_cfg_python_version!"
      exit /b 0
    )
    IF NOT "!existing_env_cfg_python_version!"=="" (
      set "existing_env_python_version=!existing_env_cfg_python_version! (from pyvenv.cfg; Scripts\python.exe did not report a version)"
    )
  )
  IF "!existing_env_python_version!"=="" (
    set "existing_env_python_version=unknown"
    set "existing_env_warning=Scripts\python.exe did not report a Python version and pyvenv.cfg did not provide a version. The folder might not be a valid Python virtual environment."
  )
  set "existing_env_problem=Existing environment Python version does not match the requested version."
  echo:
  echo: !existing_env_problem!
  echo:   Environment path: "%env_path%"
  echo:   Existing version:  !existing_env_python_version!
  IF /I "%exact_version_requested%"=="Y" (
    echo:   Required version:  %version%
  ) ELSE (
    echo:   Required version:  Any Python %version_request%.x compatible version
    echo:   New environments use: %version%
  )
  IF NOT "!existing_env_warning!"=="" (
    echo:   Warning: !existing_env_warning!
  )
  exit /b 1

:version_matches_request
  set "actual_version=%~1"
  IF "!actual_version!"=="" exit /b 1
  IF /I "%exact_version_requested%"=="Y" (
    IF "!actual_version!"=="%version%" exit /b 0
    exit /b 1
  )
  set "request_major="
  set "request_minor="
  set "request_patch="
  set "actual_major="
  set "actual_minor="
  set "actual_patch="
  for /f "tokens=1-3 delims=." %%A in ("%version_request%") do (
    set "request_major=%%A"
    set "request_minor=%%B"
    set "request_patch=%%C"
  )
  for /f "tokens=1-3 delims=." %%A in ("!actual_version!") do (
    set "actual_major=%%A"
    set "actual_minor=%%B"
    set "actual_patch=%%C"
  )
  IF "!request_minor!"=="" (
    IF "!actual_major!"=="!request_major!" exit /b 0
    exit /b 1
  )
  IF "!request_patch!"=="" (
    IF "!actual_major!"=="!request_major!" IF "!actual_minor!"=="!request_minor!" exit /b 0
    exit /b 1
  )
  IF "!actual_version!"=="%version_request%" exit /b 0
  exit /b 1

:read_python_version
  set "%~2="
  set "read_python_exe=%~1"
  for /f "tokens=2 delims= " %%V in ('cmd /s /c ""!read_python_exe!" --version" 2^>nul') do set "%~2=%%V"
  set "read_python_exe="
  exit /b 0

:read_launcher_python_version
  set "%~1="
  for /f "tokens=2 delims= " %%V in ('py -%launcher_version% --version 2^>nul') do set "%~1=%%V"
  exit /b 0

:try_python_candidate
  set "candidate_python=%~1"
  IF "!candidate_python!"=="" exit /b 1
  set "candidate_python=!candidate_python:"=!"
  for /f "tokens=* delims= " %%P in ("!candidate_python!") do set "candidate_python=%%P"
  IF "!candidate_python:~0,1!"=="*" set "candidate_python=!candidate_python:~1!"
  for /f "tokens=* delims= " %%P in ("!candidate_python!") do set "candidate_python=%%P"
  IF "!candidate_python:~-1!"=="*" set "candidate_python=!candidate_python:~0,-1!"
  for /f "tokens=* delims= " %%P in ("!candidate_python!") do set "candidate_python=%%P"
  IF EXIST "!candidate_python!" (
    set "candidate_version="
    CALL :read_python_version "!candidate_python!" candidate_version
    IF "!candidate_version!"=="%version%" (
      set "python_exe=!candidate_python!"
      exit /b 0
    )
  )
  exit /b 1

:find_standard_python
  set "python_dir_name="
  for /f "tokens=1,2 delims=." %%A in ("%launcher_version%") do set "python_dir_name=Python%%A%%B"
  CALL :try_python_candidate "%LocalAppData%\Programs\Python\%python_dir_name%\python.exe"
  IF DEFINED python_exe exit /b 0
  CALL :try_python_candidate "%ProgramFiles%\%python_dir_name%\python.exe"
  IF DEFINED python_exe exit /b 0
  IF NOT "%ProgramFiles(x86)%"=="" CALL :try_python_candidate "%ProgramFiles(x86)%\%python_dir_name%\python.exe"
  IF DEFINED python_exe exit /b 0
  IF NOT "%SystemDrive%"=="" CALL :try_python_candidate "%SystemDrive%\%python_dir_name%\python.exe"
  exit /b 0

:find_registered_python
  set "python_exe="
  for /f "tokens=1,* delims= " %%A in ('py -0p 2^>nul') do (
    set "candidate_python=%%B"
    CALL :try_python_candidate "!candidate_python!"
    IF DEFINED python_exe exit /b 0
  )
  exit /b 0

:find_launcher_python
  for /f "delims=" %%P in ('py -%launcher_version% -c "import platform, sys; sys.exit(1) if platform.python_version() != '%version%' else print(sys.executable)" 2^>nul') do (
    CALL :try_python_candidate "%%P"
    IF DEFINED python_exe exit /b 0
  )
  exit /b 0

:find_registry_python
  for %%R in (HKCU\Software\Python\PythonCore HKLM\Software\Python\PythonCore HKCU\Software\WOW6432Node\Python\PythonCore HKLM\Software\WOW6432Node\Python\PythonCore) do (
    for /f "tokens=1,2,* delims= " %%A in ('reg query %%R /s /v ExecutablePath 2^>nul ^| findstr /I /C:"ExecutablePath"') do (
      CALL :try_python_candidate "%%C"
      IF DEFINED python_exe exit /b 0
    )
  )
  exit /b 0

:find_path_python
  for /f "delims=" %%P in ('where.exe python 2^>nul') do (
    CALL :try_python_candidate "%%P"
    IF DEFINED python_exe exit /b 0
  )
  exit /b 0

:find_existing_python
  set "python_exe="
  CALL :find_standard_python
  IF DEFINED python_exe exit /b 0
  CALL :find_registered_python
  IF DEFINED python_exe exit /b 0
  CALL :find_launcher_python
  IF DEFINED python_exe exit /b 0
  CALL :find_registry_python
  IF DEFINED python_exe exit /b 0
  CALL :find_path_python
  exit /b 0

:print_installed_python_that_would_be_used
  set "preview_python_exe="
  set "preview_python_version="
  set "preview_installed_python_exe="
  set "preview_installed_python_version="
  CALL :find_existing_python
  IF DEFINED python_exe (
    set "preview_python_exe=!python_exe!"
    CALL :read_python_version "!preview_python_exe!" preview_python_version
    IF "!preview_python_version!"=="" set "preview_python_version=unknown"
    echo: Installed Python that would be used: !preview_python_version!
    echo:   "!preview_python_exe!"
  ) ELSE (
    set "std_py_path=%LocalAppData%\Programs\Python\"
    for /f "tokens=1,2 delims=." %%A in ("%launcher_version%") do set "preview_installed_python_exe=!std_py_path!Python%%A%%B\python.exe"
    IF EXIST "!preview_installed_python_exe!" (
      CALL :read_python_version "!preview_installed_python_exe!" preview_installed_python_version
      IF "!preview_installed_python_version!"=="" set "preview_installed_python_version=unknown"
      echo: Installed Python in requested version slot: !preview_installed_python_version!
      echo:   "!preview_installed_python_exe!"
      echo: Installed Python that would be used: none found. Required Python is %version%.
    ) ELSE (
      echo: Installed Python that would be used: none found. Python %version% will be installed.
    )
  )
  set "python_exe="
  echo:
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

:fail_existing_env_reuse
  echo:
  echo: --^>Cannot reuse existing environment--
  echo: --^>Delete or empty that folder. Press any button afterwards to continue.
:wait_for_existing_env_reuse
  pause > nul
  IF EXIST "%env_path%" (
    CALL :existing_env_is_empty
    IF ERRORLEVEL 1 (
      echo:
      echo: --^>Folder is still not empty. Delete or empty it, then press any button to check again.
      GOTO wait_for_existing_env_reuse
    )
  )
  echo:
  exit /b 0

:prompt_environment_settings
  IF "%env_path%"=="" set "env_path=%def_env_path%"
  IF "%packages%"=="" set "packages=%def_packages%"
  IF "%version%"=="" set "version=%def_version%"
  IF "%install_notebook_support%"=="" set "install_notebook_support=%def_install_notebook_support%"
  IF "%set_vscode_default%"=="" set "set_vscode_default=%def_set_vscode_default%"
  IF "%set_vscode_search_path%"=="" set "set_vscode_search_path=%def_set_vscode_search_path%"
  IF "%create_desktop_shortcuts%"=="" set "create_desktop_shortcuts=%def_create_desktop_shortcuts%"
  IF "%add_to_path%"=="" set "add_to_path=%def_add_to_path%"
  for /f "tokens=1,* delims==" %%A in ('powershell -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; $form=New-Object System.Windows.Forms.Form; $form.Text='Python environment settings'; $form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedDialog'; $form.MaximizeBox=$false; $form.MinimizeBox=$false; $form.ClientSize=New-Object System.Drawing.Size(640,510); $pathLabel=New-Object System.Windows.Forms.Label; $pathLabel.Text='Environment path:'; $pathLabel.Location=New-Object System.Drawing.Point(12,16); $pathLabel.AutoSize=$true; $form.Controls.Add($pathLabel); $pathText=New-Object System.Windows.Forms.TextBox; $pathText.Location=New-Object System.Drawing.Point(250,13); $pathText.Size=New-Object System.Drawing.Size(345,22); $pathText.Text='%env_path%'; $form.Controls.Add($pathText); $versionLabel=New-Object System.Windows.Forms.Label; $versionLabel.Text='Python version:' + [Environment]::NewLine + '(existing env if compatible, else newest compatible)'; $versionLabel.Location=New-Object System.Drawing.Point(12,47); $versionLabel.Size=New-Object System.Drawing.Size(235,36); $form.Controls.Add($versionLabel); $text=New-Object System.Windows.Forms.TextBox; $text.Location=New-Object System.Drawing.Point(250,53); $text.Size=New-Object System.Drawing.Size(160,22); $text.Text='%version%'; $form.Controls.Add($text); $packagesLabel=New-Object System.Windows.Forms.Label; $packagesLabel.Text='Packages:'; $packagesLabel.Location=New-Object System.Drawing.Point(12,96); $packagesLabel.AutoSize=$true; $form.Controls.Add($packagesLabel); $packagesText=New-Object System.Windows.Forms.TextBox; $packagesText.Location=New-Object System.Drawing.Point(250,93); $packagesText.Size=New-Object System.Drawing.Size(345,135); $packagesText.Multiline=$true; $packagesText.ScrollBars='Vertical'; $packagesText.WordWrap=$true; $packagesText.Text='%packages%'; $form.Controls.Add($packagesText); $v=New-Object System.Windows.Forms.CheckBox; $v.Text='Set VS Code default interpreter'; $v.Location=New-Object System.Drawing.Point(15,250); $v.Size=New-Object System.Drawing.Size(360,24); $v.Checked=('%set_vscode_default%' -ieq 'Y' -or '%set_vscode_default%' -ieq 'YES'); $form.Controls.Add($v); $vs=New-Object System.Windows.Forms.Label; $vs.Text='(Writes python.defaultInterpreterPath in %APPDATA%\Code\User\settings.json)'; $vs.Location=New-Object System.Drawing.Point(35,274); $vs.Size=New-Object System.Drawing.Size(560,34); $form.Controls.Add($vs); $s=New-Object System.Windows.Forms.CheckBox; $s.Text='Set VS Code environment search path'; $s.Location=New-Object System.Drawing.Point(15,315); $s.Size=New-Object System.Drawing.Size(520,24); $s.Checked=('%set_vscode_search_path%' -ieq 'Y' -or '%set_vscode_search_path%' -ieq 'YES'); $form.Controls.Add($s); $ss=New-Object System.Windows.Forms.Label; $ss.Text='(Writes python-envs.globalSearchPaths to the parent folder of the environment)'; $ss.Location=New-Object System.Drawing.Point(35,339); $ss.Size=New-Object System.Drawing.Size(580,34); $form.Controls.Add($ss); $j=New-Object System.Windows.Forms.CheckBox; $j.Text='Install Jupyter notebook support (ipykernel ipympl + dependencies)'; $j.Location=New-Object System.Drawing.Point(15,380); $j.Size=New-Object System.Drawing.Size(610,24); $j.Checked=('%install_notebook_support%' -ieq 'Y' -or '%install_notebook_support%' -ieq 'YES'); $form.Controls.Add($j); $d=New-Object System.Windows.Forms.CheckBox; $d.Text='Copy environment shortcuts to Desktop'; $d.Location=New-Object System.Drawing.Point(15,410); $d.Size=New-Object System.Drawing.Size(520,24); $d.Checked=('%create_desktop_shortcuts%' -ieq 'Y' -or '%create_desktop_shortcuts%' -ieq 'YES'); $form.Controls.Add($d); $p=New-Object System.Windows.Forms.CheckBox; $p.Text='Add environment to user PATH (lets python and pip from this env run in new terminals)'; $p.Location=New-Object System.Drawing.Point(15,440); $p.Size=New-Object System.Drawing.Size(610,24); $p.Checked=('%add_to_path%' -ieq 'Y' -or '%add_to_path%' -ieq 'YES'); $form.Controls.Add($p); $ok=New-Object System.Windows.Forms.Button; $ok.Text='Create'; $ok.Location=New-Object System.Drawing.Point(450,470); $ok.DialogResult=[System.Windows.Forms.DialogResult]::OK; $form.AcceptButton=$ok; $form.Controls.Add($ok); $cancel=New-Object System.Windows.Forms.Button; $cancel.Text='Cancel'; $cancel.Location=New-Object System.Drawing.Point(535,470); $cancel.DialogResult=[System.Windows.Forms.DialogResult]::Cancel; $form.CancelButton=$cancel; $form.Controls.Add($cancel); $result=$form.ShowDialog(); if ($result -eq [System.Windows.Forms.DialogResult]::OK) { $ep=$pathText.Text.Trim(); if (-not $ep) { $ep='%def_env_path%' }; $pv=$text.Text.Trim(); if (-not $pv) { $pv='%def_version%' }; $pk=($packagesText.Text -replace '[\r\n\t]+',' ').Trim(); Write-Output ('env_path=' + $ep); Write-Output ('version=' + $pv); Write-Output ('packages_was_set=Y'); Write-Output ('packages=' + $pk); Write-Output ('install_notebook_support=' + $(if ($j.Checked) { 'Y' } else { 'N' })); Write-Output ('set_vscode_default=' + $(if ($v.Checked) { 'Y' } else { 'N' })); Write-Output ('set_vscode_search_path=' + $(if ($s.Checked) { 'Y' } else { 'N' })); Write-Output ('create_desktop_shortcuts=' + $(if ($d.Checked) { 'Y' } else { 'N' })); Write-Output ('add_to_path=' + $(if ($p.Checked) { 'Y' } else { 'N' })) } else { Write-Output 'cancelled=1' }"') do set "%%A=%%B"
  IF "%cancelled%"=="1" exit /b 2
  IF "%env_path%"=="" set "env_path=%def_env_path%"
  IF "%version%"=="" set "version=%def_version%"
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
  set "newest_available_python_version="
  set "exact_version_requested=N"
  for /f "tokens=1-3 delims=." %%A in ("%version_request%") do (
    IF NOT "%%C"=="" set "exact_version_requested=Y"
  )
  IF /I "%exact_version_requested%"=="Y" (
    echo: --Using exact Python release "%version_request%"--
    set "version=%version_request%"
    for /f "tokens=1,2 delims=." %%A in ("%version%") do set "launcher_version=%%A.%%B"
    echo:
    exit /b 0
  )
  set "existing_env_python_version_for_request="
  IF EXIST "%env_path%\Scripts\python.exe" (
    CALL :read_python_version "%env_path%\Scripts\python.exe" existing_env_python_version_for_request
    CALL :version_matches_request "!existing_env_python_version_for_request!"
    IF NOT ERRORLEVEL 1 (
      set "version=!existing_env_python_version_for_request!"
      for /f "tokens=1,2 delims=." %%A in ("!version!") do set "launcher_version=%%A.%%B"
      echo: --Using existing environment Python !version! for "%version_request%"--
      echo:
      exit /b 0
    )
    IF "!existing_env_python_version_for_request!"=="" (
      CALL :read_venv_cfg_version existing_env_python_version_for_request
      CALL :version_matches_request "!existing_env_python_version_for_request!"
      IF NOT ERRORLEVEL 1 (
        set "version=!existing_env_python_version_for_request!"
        for /f "tokens=1,2 delims=." %%A in ("!version!") do set "launcher_version=%%A.%%B"
        echo: --Using existing environment Python !version! for "%version_request%"--
        echo:
        exit /b 0
      )
    )
  )
  for /f "delims=" %%V in ('powershell -NoProfile -Command "$prefix='%version_request%'.Trim(); if ($prefix -notmatch '^\d+(\.\d+){0,2}$') { exit 0 }; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $releaseRoot='https://www.python.org/ftp/python/'; try { $links=(Invoke-WebRequest -UseBasicParsing $releaseRoot -TimeoutSec 15).Links; $versions=$links | ForEach-Object href | Where-Object { $_ -match '^\d+\.\d+\.\d+/$' } | ForEach-Object { $_.TrimEnd('/') } | Where-Object { $_ -eq $prefix -or $_.StartsWith($prefix + '.') } | ForEach-Object { [version]$_ } | Sort-Object -Descending; foreach ($v in $versions) { $s=$v.ToString(); $url=$releaseRoot + $s + '/python-' + $s + '-amd64.exe'; try { Invoke-WebRequest -UseBasicParsing -Method Head $url -TimeoutSec 8 | Out-Null; Write-Output $s; exit 0 } catch {} } } catch {}; exit 0"') do set "newest_available_python_version=%%V"
  IF NOT "%newest_available_python_version%"=="" (
    echo: Newest available compatible Python release for "%version_request%": %newest_available_python_version%
    echo:
  )
  for /f "delims=" %%V in ('powershell -NoProfile -Command "$prefix='%version_request%'.Trim(); if ($prefix -notmatch '^\d+(\.\d+){0,2}$') { exit 2 }; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $releaseRoot='https://www.python.org/ftp/python/'; $links=(Invoke-WebRequest -UseBasicParsing $releaseRoot).Links; $versions=$links | ForEach-Object href | Where-Object { $_ -match '^\d+\.\d+\.\d+/$' } | ForEach-Object { $_.TrimEnd('/') } | Where-Object { $_ -eq $prefix -or $_.StartsWith($prefix + '.') } | ForEach-Object { [version]$_ } | Sort-Object -Descending; foreach ($v in $versions) { $s=$v.ToString(); $url=$releaseRoot + $s + '/python-' + $s + '-amd64.exe'; try { Invoke-WebRequest -UseBasicParsing -Method Head $url -TimeoutSec 8 | Out-Null; Write-Output $s; exit 0 } catch {} }; exit 3"') do set "resolved_version=%%V"
  IF "%resolved_version%"=="" (
    echo: [Error] Could not resolve newest Python release for "%version_request%" from python.org.
    exit /b 1
  )
  set "version=%resolved_version%"
  for /f "tokens=1,2 delims=." %%A in ("%version%") do set "launcher_version=%%A.%%B"
  exit /b 0

:ensure_python
  set "python_exe="
  set "std_py_path=%LocalAppData%\Programs\Python\"
  for /f "tokens=1,2 delims=." %%A in ("%launcher_version%") do set "installed_python_exe=%std_py_path%Python%%A%%B\python.exe"
  CALL :find_existing_python
  IF NOT DEFINED python_exe (
    IF /I "%exact_version_requested%"=="Y" IF EXIST "%installed_python_exe%" (
      set "installed_python_version="
      CALL :read_python_version "%installed_python_exe%" installed_python_version
      IF NOT "!installed_python_version!"=="%version%" IF NOT "!installed_python_version!"=="" (
        echo:
        echo: [Error] Python %launcher_version% is already installed, but it is !installed_python_version!, not %version%.
        echo:   Existing Python: "%installed_python_exe%"
        echo:
        echo: The python.org installer uses the same Python folder for patch releases of one minor version.
        echo: Uninstall Python !installed_python_version! first if you need exact Python %version%.
        exit /b 1
      )
    )
    echo: --Installing Python %version%--
    echo:
    set "python_installer=%TEMP%\python-%version%-amd64.exe"
    set "python_install_log=%TEMP%\python-%version%-install.log"
    set "python_download_url=https://www.python.org/ftp/python/%version%/python-%version%-amd64.exe"
    echo: Downloading Python installer:
    echo:   !python_download_url!
    echo:   "!python_installer!"
    powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing '!python_download_url!' -OutFile '!python_installer!'" || exit /b 1
    echo:
    echo: Running Python installer silently...
    echo:   Log: "!python_install_log!"
    powershell -NoProfile -Command "$args=@('/quiet','InstallAllUsers=0','InstallLauncherAllUsers=0','Include_pip=1','Include_launcher=1','PrependPath=0','SimpleInstall=1','Include_test=0','/log','!python_install_log!'); $p=Start-Process -FilePath '!python_installer!' -ArgumentList $args -Wait -PassThru; exit $p.ExitCode"
    IF ERRORLEVEL 1 (
      echo: [Error] Python %version% installer failed.
      echo:   Installer log: "!python_install_log!"
      del "!python_installer!" >nul 2>&1
      exit /b 1
    )
    echo: Checking installed Python %version%...
    del "!python_installer!" >nul 2>&1
    CALL :find_existing_python
    IF NOT DEFINED python_exe (
      set "available_python_version="
      IF EXIST "%installed_python_exe%" CALL :read_python_version "%installed_python_exe%" available_python_version
      IF "!available_python_version!"=="" CALL :read_launcher_python_version available_python_version
      IF "!available_python_version!"=="" set "available_python_version=unknown"
      echo:
      echo: [Error] Could not install or find Python %version%.
      echo:   Requested version: %version%
      echo:   Available version: !available_python_version!
      echo:
      echo: The exact python.org installer ran, but Python %version% was not found afterward.
      echo: If another Python %launcher_version% patch release is installed, uninstall it first and re-run this script.
      exit /b 1
    )
    echo:
    echo: --Finished installing Python %version% on computer--
  ) ELSE (
    IF /I "%exact_version_requested%"=="Y" (
      echo: --Exact Python %version% already installed on computer--
    ) ELSE (
      echo: --Compatible Python %version% already installed on computer--
    )
  )
  echo:
  exit /b 0

:create_venv
  del "%env_path%\_python_env_setup_problem.txt" >nul 2>&1
  IF NOT DEFINED python_exe (
    echo: [Error] No verified Python %version% executable path is available for creating the environment.
    exit /b 1
  )
  "%python_exe%" -m venv "%env_path%" || exit /b 1
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
  IF "%~1"=="" (
    echo: No packages requested.
    exit /b 0
  )
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
    echo: [Warning] One or more packages failed to install. Continuing with remaining setup steps.
  )
  exit /b 0

:install_jupyter_support
  set "jupyter_support_failed="
  echo: --Installing Jupyter notebook support (ipykernel ipympl)--
  echo:
  where uv >nul 2>&1
  if errorlevel 1 (
    python -m pip install "ipykernel" "ipympl"
    IF ERRORLEVEL 1 set "jupyter_support_failed=Y"
  ) else (
    uv pip install "ipykernel" "ipympl"
    if errorlevel 1 (
      echo: [Warning] uv failed to install Jupyter notebook support. Trying pip fallback...
      python -m pip install "ipykernel" "ipympl"
      IF ERRORLEVEL 1 set "jupyter_support_failed=Y"
    )
  )
  IF "%jupyter_support_failed%"=="Y" (
    echo:
    echo: [Warning] Failed to install Jupyter notebook support. Continuing with remaining setup steps.
    exit /b 0
  )
  echo:
  echo: --Finished installing Jupyter notebook support--
  echo:
  exit /b 0

:finish_jupyter_setup
  CALL :install_jupyter_support
  IF "%jupyter_support_failed%"=="Y" exit /b 0

  python -m ipykernel install --user --name "%env_name%" --display-name "%env_name%" >NUL
  IF ERRORLEVEL 1 (
    set "jupyter_kernel_failed=Y"
    echo: [Warning] Failed to register kernel with ipykernel.
  ) ELSE (
    echo: --Registered kernel with ipykernel--
  )
  echo:

  IF /I "%validate_jupyter_kernel%"=="Y" (
    echo: --Testing Jupyter kernel handshake--
    set "PY_ENV_HELPER_ACTION=validate_jupyter_kernel"
    "%env_path%\Scripts\python.exe" -x "%~f0"
    set "jupyter_kernel_test_exit_code=!ERRORLEVEL!"
    set "PY_ENV_HELPER_ACTION="
    IF NOT "!jupyter_kernel_test_exit_code!"=="0" (
      set "jupyter_kernel_test_failed=Y"
      echo: [Warning] The installed Jupyter kernel did not complete its startup handshake.
    ) ELSE (
      echo: --Jupyter kernel handshake succeeded--
    )
    echo:
  )
  exit /b 0

:create_python_shortcut
  set "shortcut_name=%~1"
  set "shortcut_target=%~2"
  set "shortcut_workdir=%~3"
  set "python_env_shortcut_created=0"
  set "python_desktop_shortcut_created=0"
  set "python_env_lnk=%env_path%\%shortcut_name%.lnk"
  set "PY_ENV_HELPER_SHORTCUT_PATH=%python_env_lnk%"
  set "PY_ENV_HELPER_SHORTCUT_TARGET=%shortcut_target%"
  set "PY_ENV_HELPER_SHORTCUT_WORKDIR=%shortcut_workdir%"
  powershell -NoProfile -Command "$s=New-Object -ComObject WScript.Shell;$l=$s.CreateShortcut($env:PY_ENV_HELPER_SHORTCUT_PATH);$l.TargetPath=$env:PY_ENV_HELPER_SHORTCUT_TARGET;$l.WorkingDirectory=$env:PY_ENV_HELPER_SHORTCUT_WORKDIR;$l.IconLocation=$env:PY_ENV_HELPER_SHORTCUT_TARGET + ',0';$l.WindowStyle=1;$l.Save()"
  IF EXIST "%python_env_lnk%" (
    set "python_env_shortcut_created=1"
  ) ELSE (
    echo: [Warning] Failed to create environment shortcut "%python_env_lnk%".
  )
  IF /I "%create_desktop_shortcuts%"=="Y" IF EXIST "%python_env_lnk%" (
    set "desktop_path="
    for /f "delims=" %%D in ('powershell -NoProfile -Command "[Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)"') do set "desktop_path=%%D"
    IF "!desktop_path!"=="" (
      echo: [Warning] Could not determine Desktop folder. Python shortcut was not copied.
    ) ELSE (
      copy /Y "%python_env_lnk%" "!desktop_path!\%shortcut_name%.lnk" >nul
      IF EXIST "!desktop_path!\%shortcut_name%.lnk" (
        set "python_desktop_shortcut_created=1"
      ) ELSE (
        echo: [Warning] Failed to copy Python shortcut to Desktop.
      )
    )
  )
  set "PY_ENV_HELPER_SHORTCUT_PATH="
  set "PY_ENV_HELPER_SHORTCUT_TARGET="
  set "PY_ENV_HELPER_SHORTCUT_WORKDIR="
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
  IF /I "%create_desktop_shortcuts%"=="Y" (
    CALL :create_desktop_shortcut "%shortcut_name%" "%shortcut_target%" "%shortcut_workdir%" 1 "cmd" || exit /b 0
    set "install_shortcut_created=1"
  )
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

:add_env_to_path
  set "env_scripts_path=%env_path%\Scripts"
  for /f "tokens=2,*" %%A in ('reg query HKCU\Environment /v PATH 2^>nul') do set "userpath=%%B"
  IF "%userpath%"=="" set "userpath="
  set "new_userpath=%userpath%"
  CALL :append_path_entry "%env_path%"
  CALL :append_path_entry "%env_scripts_path%"
  IF "%new_userpath%"=="%userpath%" (
    echo: --Environment already present in user PATH--
  ) ELSE (
    setx PATH "%new_userpath%" >NUL || exit /b 1
    echo: --Added environment to user PATH--
  )
  echo:
  exit /b 0

:append_path_entry
  set "path_entry=%~1"
  IF "%path_entry%"=="" exit /b 0
  echo:;%new_userpath%;| findstr /I /C:";%path_entry%;" >NUL
  IF ERRORLEVEL 1 (
    IF NOT "%new_userpath%"=="" IF NOT "%new_userpath:~-1%"==";" set "new_userpath=%new_userpath%;"
    set "new_userpath=%new_userpath%%path_entry%"
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
import json, os, re, sys

action = os.environ.get("PY_ENV_HELPER_ACTION", "update_vscode_settings")


def vscode_userprofile_path(p):
    """Use VS Code's portable USERPROFILE variable for paths below the profile."""
    full_path = os.path.normpath(os.path.abspath(p))
    user_profile = os.environ.get("USERPROFILE")
    if user_profile:
        user_profile = os.path.normpath(os.path.abspath(user_profile))
        try:
            inside_profile = os.path.normcase(os.path.commonpath([full_path, user_profile])) == os.path.normcase(user_profile)
        except ValueError:
            inside_profile = False
        if inside_profile:
            relative = os.path.relpath(full_path, user_profile)
            if relative == ".":
                return "${env:USERPROFILE}"
            return "${env:USERPROFILE}" + os.sep + relative
    return full_path

settings = {}

vscode_python = os.environ.get("PY_ENV_HELPER_VSCODE_PYTHON")
if vscode_python:
    settings["python.defaultInterpreterPath"] = vscode_userprofile_path(vscode_python)

vscode_search_path = os.environ.get("PY_ENV_HELPER_VSCODE_SEARCH_PATH")
if vscode_search_path:
    settings["python-envs.globalSearchPaths"] = [vscode_userprofile_path(vscode_search_path)]

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

def set_key_value(jsonc, key, value_json, replace_existing=True):
    pattern = re.compile(
        r'^(?P<indent>\s*)"' + re.escape(key) + r'"\s*:\s*(?P<val>[^\r\n]*?)(?P<comma>\s*,?)\s*(?P<cmt>//[^\r\n]*)?$',
        re.M,
    )
    if replace_existing:
        def repl(m):
            cmt = (" " + m.group("cmt")) if m.group("cmt") else ""
            return '{0}"{1}": {2}{3}{4}'.format(m.group("indent"), key, value_json, m.group("comma") or "", cmt)
        array_pattern = re.compile(
            r'^(?P<indent>\s*)"' + re.escape(key) + r'"\s*:\s*\[[\s\S]*?\](?P<comma>[ \t]*,?)[ \t]*(?P<cmt>//[^\r\n]*)?$',
            re.M,
        )
        new, n = array_pattern.subn(repl, jsonc, count=1)
        if n:
            return new
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
    return before + '{0}{1}"{2}": {3}{0}'.format(eol, base_indent, key, value_json) + after


def has_setting(jsonc, key):
    return re.search(r'^\s*"' + re.escape(key) + r'"\s*:', jsonc, re.M) is not None


def migrate_array_setting(jsonc, old_key, new_key):
    """Rename an obsolete array setting, preserving its formatting and comments."""
    old_key_pattern = re.compile(r'^(?P<indent>\s*)"' + re.escape(old_key) + r'"(?P<suffix>\s*:)', re.M)
    if not old_key_pattern.search(jsonc):
        return jsonc
    if not has_setting(jsonc, new_key):
        return old_key_pattern.sub(
            lambda match: match.group("indent") + '"' + new_key + '"' + match.group("suffix"),
            jsonc,
            count=1,
        )

    # If both settings exist, prefer the supported setting and remove the obsolete duplicate.
    old_array_pattern = re.compile(
        r'^\s*"' + re.escape(old_key) + r'"\s*:\s*\[[\s\S]*?\][ \t]*,?[ \t]*(?://[^\r\n]*)?\r?\n?',
        re.M,
    )
    return old_array_pattern.sub("", jsonc, count=1)


def validate_jupyter_kernel():
    from jupyter_client import KernelManager

    manager = KernelManager(kernel_name="python3")
    client = None
    try:
        # The bundled python3 kernelspec normally says "python". Make the test
        # independent of PATH and guarantee that it checks this environment.
        manager.kernel_spec.argv[0] = sys.executable
        manager.start_kernel()
        client = manager.client()
        client.start_channels()
        client.wait_for_ready(timeout=20)
        print(" --Kernel started and completed the Jupyter handshake--")
    finally:
        if client is not None:
            client.stop_channels()
        if manager.has_kernel:
            manager.shutdown_kernel(now=True)

if action == "validate_jupyter_kernel":
    try:
        validate_jupyter_kernel()
    except Exception as exc:
        print(" [Error] Jupyter kernel handshake failed: {0}: {1}".format(type(exc).__name__, exc))
        sys.exit(1)
    sys.exit(0)

if action != "update_vscode_settings":
    print(" [Error] Unknown embedded Python action: " + action)
    sys.exit(2)

txt = read_text(path)
txt = migrate_array_setting(txt, "python.venvFolders", "python-envs.globalSearchPaths")
for setting_key, value in settings.items():
    txt = set_key_value(txt, setting_key, json.dumps(value), replace_existing)
write_text(path, txt)
print(" --Updated VS Code settings--")
sys.exit(0)

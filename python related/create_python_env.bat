@setlocal EnableDelayedExpansion & @echo off
REM=r""" <- lets Python ignore the batch part of this file.
:: The first line is skipped when this file is launched with `py -x`.
:: The Python code starts near the bottom.
:: The first part is normal batch code which will in the end launch the Python code.

for /F "delims=#" %%E in ('"prompt #$E# & for %%E in (1) do rem"') do set "ESC=%%E"
set "GREEN=!ESC![92m"
set "RED=!ESC![91m"
set "RESET=!ESC![0m"
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
:: Both VS Code options always update user settings, preserving paths exactly.
:: VS Code requires absolute paths for global environment discovery; relative
:: search paths are saved unchanged but may be ignored by the extension.
:: It also migrates the deprecated python.venvFolders setting.

:: ---------------------------------------------------------------------------
:: Command-line flags
:: ---------------------------------------------------------------------------
:: --path PATH              Folder where the virtual environment is created or reused.
::                         If it already contains a compatible environment, it is reused.
::                         The selected packages, Jupyter support, shortcuts, PATH, and
::                         VS Code settings are then applied to that environment.
:: --packages "PKG PKG"     Package names to install into this environment, separated by spaces.
:: --version VERSION        Python version to use. Reuses a compatible installed Python,
::                         or finds or installs the newest compatible release; e.g. 3, 3.13, 3.13.5.
:: --vscode-default Y|N     Make VS Code use this environment by default for Python files.
:: --vscode-search-path Y|N Let VS Code discover environments in this environment folder.
:: --notebook-support Y|N   Install Jupyter support so this environment can run notebooks.
:: --desktop-shortcuts Y|N  Add Desktop shortcuts for opening Python and installing packages here.
:: --add-to-path Y|N        Make this environment the default when you type
::                         `python` or `pip` in newly opened Command Prompt or
::                         PowerShell windows. PATH is Windows' ordered list of
::                         program folders: Windows uses the first matching
::                         program it finds. This puts the env's Scripts folder,
::                         then its root folder, before older Python entries.
::                         It does not affect terminals that are already open,
::                         and it does not change VS Code interpreter settings.
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
SET "def_packages=numpy matplotlib scipy scipy-stubs pandas pyyaml pillow tqdm types-tqdm pyarrow openpyxl opencv-python pywin32 pyserial types-pyserial numba pyside6 html5lib rich scikit-image tifffile pyautogui nuitka pywinauto nptdms py7zr nvmath-python cupy-cuda12x lightwaveexplorer"

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

CALL :make_absolute_path "%env_path%" || goto :fail
SET "env_path=%OUTPUT%"
for %%F in ("%env_path%\..") do SET "env_parent_path=%%~fF"

for %%F in ("%env_path%") do set "env_name=%%~nxF"
IF NOT DEFINED vscode_interpreter_path SET "vscode_interpreter_path=%env_path%\Scripts\python.exe"
IF NOT DEFINED vscode_env_search_path SET "vscode_env_search_path=%env_parent_path%"

:: ---------------------------------------------------------------------------
:: Create and configure environment
:: ---------------------------------------------------------------------------
:: Ensure the requested Python exists, create/activate the venv, install
:: packages, add optional tooling, create shortcuts, and apply integrations.

echo:!GREEN!--Settings--!RESET!
echo:
echo:!GREEN!Environment path: %env_path%!RESET!
echo:!GREEN!Python version request: %version_request%!RESET!
echo:!GREEN!Python packages: %packages%!RESET!
echo:!GREEN!Set VS Code default interpreter: %set_vscode_default%!RESET!
IF /I "%set_vscode_default%"=="Y" echo:!GREEN!  Interpreter path: %vscode_interpreter_path%!RESET!
echo:!GREEN!Add VS Code env search path: %set_vscode_search_path%!RESET!
IF /I "%set_vscode_search_path%"=="Y" echo:!GREEN!VS Code env search path: %vscode_env_search_path%!RESET!
echo:!GREEN!Install Jupyter notebook support (ipykernel ipympl ipywidgets): %install_notebook_support%!RESET!
echo:!GREEN!Copy environment shortcuts to Desktop: %create_desktop_shortcuts%!RESET!
echo:!GREEN!Put environment first in user PATH: %add_to_path%!RESET!
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
      echo:!GREEN!--Created python environment--!RESET!
    ) ELSE (
      echo:!GREEN!--Environment already exists with Python %venv_python_version%--!RESET!
      echo:
    )
  ) ELSE (
    echo:!GREEN!--Environment folder exists and is empty--!RESET!
    CALL :ensure_python || goto :fail
    CALL :create_venv || goto :fail
    echo:!GREEN!--Created python environment--!RESET!
  )
) ELSE (
  CALL :ensure_python || goto :fail
  CALL :create_venv || goto :fail
  echo:!GREEN!--Created python environment--!RESET!
)
:: A reused environment may have activation scripts left over from another path.
:: Verify and invoke its interpreter directly; never fall back to PATH's Python.
SET "env_python=%env_path%\Scripts\python.exe"
CALL :validate_env_python || goto :fail
call "%env_path%\Scripts\activate.bat" || goto :fail
SET "VIRTUAL_ENV=%env_path%"
SET "PATH=%env_path%\Scripts;%PATH%"
:: Keep the default cache on the environment drive so uv can hardlink wheels.
:: An explicitly configured cache directory takes precedence.
IF NOT DEFINED UV_CACHE_DIR SET "UV_CACHE_DIR=%env_parent_path%\.uv-cache"

mkdir "%USERPROFILE%\Documents\Repositories" 2> NUL

:: Create Python launch and package-install shortcuts.
SET "python_shortcut_name=python (%env_name%)"
CALL :create_python_shortcut "%python_shortcut_name%" "%env_path%\Scripts\python.exe" "%env_path%" || goto :fail

SET "install_shortcut_name=Install package (%env_name%)"
SET "install_cmd_path=%env_path%\%install_shortcut_name%.cmd"
> "!install_cmd_path!" (
  echo @echo off
  echo setlocal
  echo set "env_python=%%~dp0Scripts\python.exe"
  echo if not exist "%%env_python%%" exit /b 1
  echo if not defined UV_CACHE_DIR set "UV_CACHE_DIR=%%~dp0..\.uv-cache"
  echo echo.
  echo echo: Install packages into python environment "%env_name%".
  echo echo: Accepted input examples:
  echo echo:   numpy pandas
  echo echo:   install numpy pandas
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
  echo if /I "%%install_input%%"=="install" ^(echo: Add one or more package names. ^& goto again^)
  echo if /I "%%install_input%%"=="pip install" ^(echo: Add one or more package names. ^& goto again^)
  echo if /I "%%install_input%%"=="python -m pip install" ^(echo: Add one or more package names. ^& goto again^)
  echo if /I "%%install_input%%"=="py -m pip install" ^(echo: Add one or more package names. ^& goto again^)
  echo if /I "%%install_input%%"=="uv pip install" ^(echo: Add one or more package names. ^& goto again^)
  echo REM Allow the short, natural-language form: "install numpy pandas".
  echo REM Remove only the leading "install" before sending the package list to uv/pip.
  echo for /f "tokens=1,*" %%%%A in ("%%install_input%%"^) do if /I "%%%%A"=="install" set "install_input=%%%%B"
  echo REM Normalize accepted command prefixes, then always use this environment.
  echo if /I "%%install_input:~0,12%%"=="pip install " set "install_input=%%install_input:~12%%"
  echo if /I "%%install_input:~0,22%%"=="python -m pip install " set "install_input=%%install_input:~22%%"
  echo if /I "%%install_input:~0,18%%"=="py -m pip install " set "install_input=%%install_input:~18%%"
  echo if /I "%%install_input:~0,15%%"=="uv pip install " set "install_input=%%install_input:~15%%"
  echo "%%env_python%%" -m uv pip install --python "%%env_python%%" %%install_input%% ^|^| "%%env_python%%" -m pip install %%install_input%%
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
  IF /I "%set_vscode_default%"=="Y" set "PY_ENV_HELPER_VSCODE_PYTHON=%vscode_interpreter_path%"
  IF /I "%set_vscode_search_path%"=="Y" set "PY_ENV_HELPER_VSCODE_SEARCH_PATH=%vscode_env_search_path%"
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
  echo:!GREEN!--Updating pip--!RESET!
  echo:
  "%env_python%" -m pip install --upgrade pip
  IF ERRORLEVEL 1 (
    set "pip_upgrade_failed=Y"
    CALL :print_red [Warning] Failed to upgrade pip. Continuing with package installation.
  )
  echo:
  CALL :ensure_uv
  IF NOT "%packages%"=="" (
    echo:!GREEN!--Installing requested packages--!RESET!
    echo:
    CALL :install_packages "%packages%"
    echo:
    echo:!GREEN!--Finished installing requested packages--!RESET!
    echo:
  )
  IF /I "%install_notebook_support%"=="Y" CALL :finish_jupyter_setup
) ELSE (
  echo:
  echo:!GREEN!--No package installation requested--!RESET!
  echo:
)

set "setup_warnings="
IF "%pip_upgrade_failed%"=="Y" (
  CALL :print_red [Warning] pip upgrade failed.
  set "setup_warnings=Y"
)
IF NOT "!failed_packages!"=="" (
  CALL :print_red [Warning] Failed packages:!failed_packages!
  set "setup_warnings=Y"
)
IF "%jupyter_support_failed%"=="Y" (
  CALL :print_red [Warning] Jupyter notebook support install failed.
  set "setup_warnings=Y"
)
IF "%jupyter_kernel_failed%"=="Y" (
  CALL :print_red [Warning] Jupyter kernel registration failed.
  set "setup_warnings=Y"
)
IF "%jupyter_kernel_test_failed%"=="Y" (
  CALL :print_red [Warning] Jupyter kernel handshake test failed.
  set "setup_warnings=Y"
)
echo:
echo:
IF "%setup_warnings%"=="Y" (
  CALL :print_red Setup completed with warnings. Review the warnings above.
) ELSE (
  echo:!GREEN!Setup finished successfully.!RESET!
)
echo:!GREEN!Created environment in "%env_path%".!RESET!
IF "%python_env_shortcut_created%"=="1" echo:!GREEN!Created shortcut in environment folder ("python (%env_name%)"^) for launching Python.!RESET!
IF "%python_desktop_shortcut_created%"=="1" echo:!GREEN!Created shortcut on Desktop ("python (%env_name%)"^) for launching Python.!RESET!
IF "%install_env_shortcut_created%"=="1" echo:!GREEN!Created shortcut in environment folder ("Install package (%env_name%)"^) for installing packages.!RESET!
IF "%install_shortcut_created%"=="1" echo:!GREEN!Created shortcut on Desktop ("Install package (%env_name%)") for installing packages.!RESET!
echo:!GREEN!Press any key to exit.!RESET!
pause > nul
exit /b 0

:cancelled
echo:
echo:!GREEN!Setup cancelled.!RESET!
exit /b 0

:: ---------------------------------------------------------------------------
:: Batch subroutines
:: ---------------------------------------------------------------------------
:: Keep the main flow above readable. Each label exits with a batch errorlevel.

:fail
  echo:
  echo:
  echo:!RED!ERROR: Failed python environment setup (See errors above^).!RESET!
  echo:!RED!Fix the error shown above, then run this script again.!RESET!
  echo:!RED!Press any key to exit.!RESET!
  pause > nul
  exit /b 1

:process_args
  IF "%~1"=="" exit /b 0
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
  exit /b 0

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
    CALL :print_red !existing_env_problem!
    CALL :print_red !existing_env_warning!
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
  CALL :print_red !existing_env_problem!
  CALL :print_red   Environment path: "%env_path%"
  CALL :print_red   Existing version:  !existing_env_python_version!
  IF /I "%exact_version_requested%"=="Y" (
    CALL :print_red   Required version:  %version%
  ) ELSE (
    CALL :print_red   Required version:  Any Python %version_request%.x compatible version
    CALL :print_red   New environments use: %version%
  )
  IF NOT "!existing_env_warning!"=="" (
    CALL :print_red   Warning: !existing_env_warning!
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
  CALL :print_red --Cannot reuse existing environment--
  CALL :print_red --Delete or empty that folder. Press any button afterwards to continue.
:wait_for_existing_env_reuse
  pause > nul
  IF EXIST "%env_path%" (
    CALL :existing_env_is_empty
    IF ERRORLEVEL 1 (
      echo:
      CALL :print_red --Folder is still not empty. Delete or empty it, then press any button to check again.
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
  set "PY_ENV_HELPER_SELF=%~f0"
  for /f "tokens=1,* delims==" %%A in ('powershell -NoProfile -Command "$source=Get-Content -LiteralPath $env:PY_ENV_HELPER_SELF -Raw; $dialog=[regex]::Match($source,'(?ms)^# BEGIN ENV SETTINGS\r?\n(.*?)^# END ENV SETTINGS').Groups[1].Value; ([scriptblock]::Create($dialog)).Invoke()"') do set "%%A=%%B"
  set "PY_ENV_HELPER_SELF="
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
  CALL :print_red [Error] %yn_name% must be Y or N.
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
    echo:!GREEN!--Using exact Python release "%version_request%"--!RESET!
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
      exit /b 0
    )
    IF "!existing_env_python_version_for_request!"=="" (
      CALL :read_venv_cfg_version existing_env_python_version_for_request
      CALL :version_matches_request "!existing_env_python_version_for_request!"
      IF NOT ERRORLEVEL 1 (
        set "version=!existing_env_python_version_for_request!"
        for /f "tokens=1,2 delims=." %%A in ("!version!") do set "launcher_version=%%A.%%B"
        exit /b 0
      )
    )
  )
  for /f "delims=" %%V in ('powershell -NoProfile -Command "$prefix='%version_request%'.Trim(); if ($prefix -notmatch '^\d+(\.\d+){0,2}$') { exit 0 }; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $releaseRoot='https://www.python.org/ftp/python/'; try { $links=(Invoke-WebRequest -UseBasicParsing $releaseRoot -TimeoutSec 15).Links; $versions=$links | ForEach-Object href | Where-Object { $_ -match '^\d+\.\d+\.\d+/$' } | ForEach-Object { $_.TrimEnd('/') } | Where-Object { $_ -eq $prefix -or $_.StartsWith($prefix + '.') } | ForEach-Object { [version]$_ } | Sort-Object -Descending; foreach ($v in $versions) { $s=$v.ToString(); $url=$releaseRoot + $s + '/python-' + $s + '-amd64.exe'; try { Invoke-WebRequest -UseBasicParsing -Method Head $url -TimeoutSec 8 | Out-Null; Write-Output $s; exit 0 } catch {} } } catch {}; exit 0"') do set "newest_available_python_version=%%V"
  IF NOT "%newest_available_python_version%"=="" (
    echo:!GREEN!Newest available compatible Python release for "%version_request%": %newest_available_python_version%!RESET!
    echo:
  )
  for /f "delims=" %%V in ('powershell -NoProfile -Command "$prefix='%version_request%'.Trim(); if ($prefix -notmatch '^\d+(\.\d+){0,2}$') { exit 2 }; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $releaseRoot='https://www.python.org/ftp/python/'; $links=(Invoke-WebRequest -UseBasicParsing $releaseRoot).Links; $versions=$links | ForEach-Object href | Where-Object { $_ -match '^\d+\.\d+\.\d+/$' } | ForEach-Object { $_.TrimEnd('/') } | Where-Object { $_ -eq $prefix -or $_.StartsWith($prefix + '.') } | ForEach-Object { [version]$_ } | Sort-Object -Descending; foreach ($v in $versions) { $s=$v.ToString(); $url=$releaseRoot + $s + '/python-' + $s + '-amd64.exe'; try { Invoke-WebRequest -UseBasicParsing -Method Head $url -TimeoutSec 8 | Out-Null; Write-Output $s; exit 0 } catch {} }; exit 3"') do set "resolved_version=%%V"
  IF "%resolved_version%"=="" (
    CALL :print_red [Error] Could not resolve newest Python release for "%version_request%" from python.org.
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
        CALL :print_red [Error] Python %launcher_version% is already installed, but it is !installed_python_version!, not %version%.
        CALL :print_red   Existing Python: "%installed_python_exe%"
        echo:
        CALL :print_red The python.org installer uses the same Python folder for patch releases of one minor version.
        CALL :print_red Uninstall Python !installed_python_version! first if you need exact Python %version%.
        exit /b 1
      )
    )
    echo:!GREEN!--Installing Python %version%--!RESET!
    echo:
    set "python_installer=%TEMP%\python-%version%-amd64.exe"
    set "python_install_log=%TEMP%\python-%version%-install.log"
    set "python_download_url=https://www.python.org/ftp/python/%version%/python-%version%-amd64.exe"
    echo:!GREEN!Downloading Python installer:!RESET!
    echo:!GREEN!  !python_download_url!!RESET!
    echo:!GREEN!  "!python_installer!"!RESET!
    powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing '!python_download_url!' -OutFile '!python_installer!'" || exit /b 1
    echo:
    echo:!GREEN!Running Python installer silently...!RESET!
    echo:!GREEN!  Log: "!python_install_log!"!RESET!
    powershell -NoProfile -Command "$args=@('/quiet','InstallAllUsers=0','InstallLauncherAllUsers=0','Include_pip=1','Include_launcher=1','PrependPath=0','SimpleInstall=1','Include_test=0','/log','!python_install_log!'); $p=Start-Process -FilePath '!python_installer!' -ArgumentList $args -Wait -PassThru; exit $p.ExitCode"
    IF ERRORLEVEL 1 (
      CALL :print_red [Error] Python %version% installer failed.
      CALL :print_red   Installer log: "!python_install_log!"
      del "!python_installer!" >nul 2>&1
      exit /b 1
    )
    echo:!GREEN!Checking installed Python %version%...!RESET!
    del "!python_installer!" >nul 2>&1
    CALL :find_existing_python
    IF NOT DEFINED python_exe (
      set "available_python_version="
      IF EXIST "%installed_python_exe%" CALL :read_python_version "%installed_python_exe%" available_python_version
      IF "!available_python_version!"=="" CALL :read_launcher_python_version available_python_version
      IF "!available_python_version!"=="" set "available_python_version=unknown"
      echo:
      CALL :print_red [Error] Could not install or find Python %version%.
      CALL :print_red   Requested version: %version%
      CALL :print_red   Available version: !available_python_version!
      echo:
      CALL :print_red The exact python.org installer ran, but Python %version% was not found afterward.
      CALL :print_red If another Python %launcher_version% patch release is installed, uninstall it first and re-run this script.
      exit /b 1
    )
    echo:
    echo:!GREEN!--Finished installing Python %version% on computer--!RESET!
  ) ELSE (
    IF /I "%exact_version_requested%"=="Y" (
      echo:!GREEN!--Exact Python %version% already installed on computer--!RESET!
    ) ELSE (
      echo:!GREEN!--Compatible Python %version% already installed on computer--!RESET!
    )
  )
  echo:!GREEN!Python used to create environment: %version%!RESET!
  echo:!GREEN!  "!python_exe!"!RESET!
  echo:
  exit /b 0

:create_venv
  del "%env_path%\_python_env_setup_problem.txt" >nul 2>&1
  IF NOT DEFINED python_exe (
    CALL :print_red [Error] No verified Python %version% executable path is available for creating the environment.
    exit /b 1
  )
  "%python_exe%" -m venv "%env_path%" || exit /b 1
  exit /b 0

:validate_env_python
  "%env_python%" -c "import os, sys; norm = lambda p: os.path.normcase(os.path.realpath(p)); expected = norm(os.environ['env_path']); valid = sys.prefix != sys.base_prefix and norm(sys.prefix) == expected and norm(sys.executable) == norm(os.environ['env_python']); sys.exit(0 if valid else 1)"
  IF ERRORLEVEL 1 (
    CALL :print_red [Error] The selected environment interpreter is unavailable or does not belong to this environment.
    CALL :print_red   Interpreter: "%env_python%"
    CALL :print_red   Recreate the environment at its current path before retrying setup.
    exit /b 1
  )
  exit /b 0

:ensure_uv
  echo:!GREEN!uv cache directory: %UV_CACHE_DIR%!RESET!
  echo:!GREEN!--Installing/updating uv--!RESET!
  echo:
  "%env_python%" -m pip install --upgrade uv
  if errorlevel 1 CALL :print_red [Warning] Failed to install uv. Package installs will use pip.
  echo:
  exit /b 0

:install_packages
  set "failed_packages="
  set "installed_packages="
  IF "%~1"=="" (
    echo:!GREEN!No packages requested.!RESET!
    exit /b 0
  )
  CALL :print_separator
  for %%P in (%~1) do (
    echo:!GREEN!Installing %%P ...!RESET!
    "%env_python%" -m uv --version >nul 2>&1
    if errorlevel 1 (
      "%env_python%" -m pip install "%%P"
    ) else (
      "%env_python%" -m uv pip install --python "%env_python%" "%%P"
      if errorlevel 1 (
        CALL :print_red [Warning] uv failed to install %%P. Trying pip fallback...
        "%env_python%" -m pip install "%%P"
      )
    )
    if errorlevel 1 (
      CALL :print_red [Warning] Failed to install %%P
      set "failed_packages=!failed_packages! %%P"
    ) else (
      set "installed_packages=!installed_packages! %%P"
    )
    CALL :print_separator
  )
  echo:
  IF NOT "!installed_packages!"=="" echo:!GREEN!Installed packages:!installed_packages!!RESET!
  IF NOT "!failed_packages!"=="" (
    CALL :print_red Failed packages:!failed_packages!
    CALL :print_red [Warning] One or more packages failed to install. Continuing with remaining setup steps.
  )
  exit /b 0

:install_jupyter_support
  set "jupyter_support_failed="
  echo:!GREEN!--Installing Jupyter notebook support (ipykernel ipympl ipywidgets)--!RESET!
  echo:
  "%env_python%" -m uv --version >nul 2>&1
  if errorlevel 1 (
    "%env_python%" -m pip install "ipykernel" "ipympl" "ipywidgets"
    IF ERRORLEVEL 1 set "jupyter_support_failed=Y"
  ) else (
    "%env_python%" -m uv pip install --python "%env_python%" "ipykernel" "ipympl" "ipywidgets"
    if errorlevel 1 (
      CALL :print_red [Warning] uv failed to install Jupyter notebook support. Trying pip fallback...
      "%env_python%" -m pip install "ipykernel" "ipympl" "ipywidgets"
      IF ERRORLEVEL 1 set "jupyter_support_failed=Y"
    )
  )
  IF "%jupyter_support_failed%"=="Y" (
    echo:
    CALL :print_red [Warning] Failed to install Jupyter notebook support. Continuing with remaining setup steps.
    exit /b 0
  )
  echo:
  echo:!GREEN!--Finished installing Jupyter notebook support--!RESET!
  echo:
  exit /b 0

:finish_jupyter_setup
  CALL :install_jupyter_support
  IF "%jupyter_support_failed%"=="Y" exit /b 0

  "%env_python%" -m ipykernel install --user --name "%env_name%" --display-name "%env_name%" >NUL
  IF ERRORLEVEL 1 (
    set "jupyter_kernel_failed=Y"
    CALL :print_red [Warning] Failed to register kernel with ipykernel.
  ) ELSE (
    echo:!GREEN!--Registered kernel with ipykernel--!RESET!
  )
  echo:

  IF /I "%validate_jupyter_kernel%"=="Y" (
    echo:!GREEN!--Testing Jupyter kernel handshake--!RESET!
    set "PY_ENV_HELPER_ACTION=validate_jupyter_kernel"
    "%env_path%\Scripts\python.exe" -x "%~f0"
    set "jupyter_kernel_test_exit_code=!ERRORLEVEL!"
    set "PY_ENV_HELPER_ACTION="
    IF NOT "!jupyter_kernel_test_exit_code!"=="0" (
      set "jupyter_kernel_test_failed=Y"
      CALL :print_red [Warning] The installed Jupyter kernel did not complete its startup handshake.
    ) ELSE (
      echo:!GREEN!--Jupyter kernel handshake succeeded--!RESET!
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
    CALL :print_red [Warning] Failed to create environment shortcut "%python_env_lnk%".
  )
  IF /I "%create_desktop_shortcuts%"=="Y" IF EXIST "%python_env_lnk%" (
    set "desktop_path="
    for /f "delims=" %%D in ('powershell -NoProfile -Command "[Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)"') do set "desktop_path=%%D"
    IF "!desktop_path!"=="" (
      CALL :print_red [Warning] Could not determine Desktop folder. Python shortcut was not copied.
    ) ELSE (
      copy /Y "%python_env_lnk%" "!desktop_path!\%shortcut_name%.lnk" >nul
      IF EXIST "!desktop_path!\%shortcut_name%.lnk" (
        set "python_desktop_shortcut_created=1"
      ) ELSE (
        CALL :print_red [Warning] Failed to copy Python shortcut to Desktop.
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
    CALL :print_red [Warning] Failed to create environment shortcut "%env_lnk%".
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
    CALL :print_red [Warning] Could not determine Desktop folder. Shortcut was not created.
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
    CALL :print_red [Warning] Failed to create Desktop shortcut "%desktop_lnk%".
    exit /b 1
  )
  exit /b 0

:add_env_to_path
  set "env_scripts_path=%env_path%\Scripts"
  REM PATH is searched left-to-right. Remove existing copies, then add two
  REM separate entries at the beginning so this environment wins over older
  REM Python installations. SetEnvironmentVariable avoids setx's length limit.
  set "PY_ENV_HELPER_PATH_FIRST=%env_scripts_path%"
  set "PY_ENV_HELPER_PATH_SECOND=%env_path%"
  powershell -NoProfile -Command "$first=$env:PY_ENV_HELPER_PATH_FIRST; $second=$env:PY_ENV_HELPER_PATH_SECOND; $current=[Environment]::GetEnvironmentVariable('Path','User'); $entries=@(); if ($current) { $entries=$current -split ';' | Where-Object { $entry=$_.Trim(); $entry -and -not [string]::Equals($entry,$first,[StringComparison]::OrdinalIgnoreCase) -and -not [string]::Equals($entry,$second,[StringComparison]::OrdinalIgnoreCase) } }; $newPath=(@($first,$second)+$entries) -join ';'; [Environment]::SetEnvironmentVariable('Path',$newPath,'User')" || exit /b 1
  set "PY_ENV_HELPER_PATH_FIRST="
  set "PY_ENV_HELPER_PATH_SECOND="
  echo:!GREEN!--Placed environment at the start of user PATH--!RESET!
  echo:!GREEN!  1. %env_scripts_path%!RESET!
  echo:!GREEN!  2. %env_path%!RESET!
  echo:!GREEN!New terminals will use this environment's Python before older PATH entries.!RESET!
  echo:
  exit /b 0
:print_separator
  echo:!GREEN!============================================================!RESET!
  exit /b 0

:print_red
  echo:!RED!%*!RESET!
  exit /b 0

:make_absolute_path
  SET "OUTPUT=%~f1"
  GOTO :EOF

# BEGIN ENV SETTINGS
Add-Type -AssemblyName System.Windows.Forms;
Add-Type -AssemblyName System.Drawing;
$form=New-Object System.Windows.Forms.Form;
$form.Text='Python environment settings';
$form.StartPosition='CenterScreen';
$form.FormBorderStyle='FixedDialog';
$form.MaximizeBox=$false;
$form.MinimizeBox=$false;
$form.ClientSize=New-Object System.Drawing.Size(640,730);
$pathLabel=New-Object System.Windows.Forms.Label;
$pathLabel.Text='Environment path:' + [Environment]::NewLine + '(Reuses an existing environment' + [Environment]::NewLine + 'at that path when its Python version' + [Environment]::NewLine + 'is compatible.)';
$pathLabel.Location=New-Object System.Drawing.Point(12,16);
$pathLabel.AutoSize=$true;
$form.Controls.Add($pathLabel);
$pathText=New-Object System.Windows.Forms.TextBox;
$pathText.Location=New-Object System.Drawing.Point(250,13);
$pathText.Size=New-Object System.Drawing.Size(345,22);
$pathText.Text=$env:env_path;
$form.Controls.Add($pathText);
$versionLabel=New-Object System.Windows.Forms.Label;
$versionLabel.Text='Python version:' + [Environment]::NewLine + '(existing Python if compatible, else newest compatible)';
$versionLabel.Location=New-Object System.Drawing.Point(12,83);
$versionLabel.Size=New-Object System.Drawing.Size(235,36);
$form.Controls.Add($versionLabel);
$text=New-Object System.Windows.Forms.TextBox;
$text.Location=New-Object System.Drawing.Point(250,89);
$text.Size=New-Object System.Drawing.Size(160,22);
$text.Text=$env:version;
$form.Controls.Add($text);
$packagesLabel=New-Object System.Windows.Forms.Label;
$packagesLabel.Text='Packages:';
$packagesLabel.Location=New-Object System.Drawing.Point(12,132);
$packagesLabel.AutoSize=$true;
$form.Controls.Add($packagesLabel);
$packagesText=New-Object System.Windows.Forms.TextBox;
$packagesText.Location=New-Object System.Drawing.Point(250,129);
$packagesText.Size=New-Object System.Drawing.Size(345,135);
$packagesText.Multiline=$true;
$packagesText.ScrollBars='Vertical';
$packagesText.WordWrap=$true;
$packagesText.Text=$env:packages;
$form.Controls.Add($packagesText);
$v=New-Object System.Windows.Forms.CheckBox;
$v.Text='Set VS Code default interpreter (user settings)';
$v.Location=New-Object System.Drawing.Point(15,286);
$v.Size=New-Object System.Drawing.Size(520,24);
$v.Checked=($env:set_vscode_default -ieq 'Y' -or $env:set_vscode_default -ieq 'YES');
$form.Controls.Add($v);
$interpreterText=New-Object System.Windows.Forms.TextBox;
$interpreterText.Location=New-Object System.Drawing.Point(35,314);
$interpreterText.Size=New-Object System.Drawing.Size(560,22);
$interpreterText.Enabled=$v.Checked;
$form.Controls.Add($interpreterText);
$v.Add_CheckedChanged({ $interpreterText.Enabled=$v.Checked });
$vs=New-Object System.Windows.Forms.Label;
$vs.Text='User settings: %APPDATA%\Code\User\settings.json' + [Environment]::NewLine + '(Interpreter path is saved exactly as entered.)';
$vs.Location=New-Object System.Drawing.Point(35,350);
$vs.Size=New-Object System.Drawing.Size(560,34);
$form.Controls.Add($vs);
$s=New-Object System.Windows.Forms.CheckBox;
$s.Text='Set VS Code environment search path (user settings)';
$s.Location=New-Object System.Drawing.Point(15,391);
$s.Size=New-Object System.Drawing.Size(520,24);
$s.Checked=($env:set_vscode_search_path -ieq 'Y' -or $env:set_vscode_search_path -ieq 'YES');
$form.Controls.Add($s);
$searchText=New-Object System.Windows.Forms.TextBox;
$searchText.Location=New-Object System.Drawing.Point(35,419);
$searchText.Size=New-Object System.Drawing.Size(560,22);
$searchText.Enabled=$s.Checked;
$form.Controls.Add($searchText);
$s.Add_CheckedChanged({ $searchText.Enabled=$s.Checked });
$ss=New-Object System.Windows.Forms.Label;
$ss.Text='User settings: %APPDATA%\Code\User\settings.json' + [Environment]::NewLine + '(Relative values are saved unchanged; VS Code requires absolute search paths.)';
$ss.Location=New-Object System.Drawing.Point(35,455);
$ss.Size=New-Object System.Drawing.Size(580,34);
$form.Controls.Add($ss);
$j=New-Object System.Windows.Forms.CheckBox;
$j.Text='Install Jupyter notebook support (ipykernel ipympl ipywidgets + dependencies)';
$j.Location=New-Object System.Drawing.Point(15,496);
$j.Size=New-Object System.Drawing.Size(610,24);
$j.Checked=($env:install_notebook_support -ieq 'Y' -or $env:install_notebook_support -ieq 'YES');
$form.Controls.Add($j);
$d=New-Object System.Windows.Forms.CheckBox;
$d.Text='Copy environment shortcuts to Desktop';
$d.Location=New-Object System.Drawing.Point(15,526);
$d.Size=New-Object System.Drawing.Size(520,24);
$d.Checked=($env:create_desktop_shortcuts -ieq 'Y' -or $env:create_desktop_shortcuts -ieq 'YES');
$form.Controls.Add($d);
$shortcutHelp=New-Object System.Windows.Forms.Label;
$shortcutHelp.Text='(Creates Desktop shortcuts to launch Python in a terminal and install packages in this environment.)';
$shortcutHelp.Location=New-Object System.Drawing.Point(35,550);
$shortcutHelp.Size=New-Object System.Drawing.Size(560,20);
$form.Controls.Add($shortcutHelp);
$p=New-Object System.Windows.Forms.CheckBox;
$p.Text='Make this environment the default Python in new terminals';
$p.Location=New-Object System.Drawing.Point(15,586);
$p.Size=New-Object System.Drawing.Size(610,24);
$p.Checked=($env:add_to_path -ieq 'Y' -or $env:add_to_path -ieq 'YES');
$form.Controls.Add($p);
$pathHelp=New-Object System.Windows.Forms.Label;
$pathHelp.Text='(PATH is the ordered list Windows uses to find programs. New terminals will use this environment for python and pip before older Python entries. It does not affect terminals already open.)';
$pathHelp.Location=New-Object System.Drawing.Point(35,610);
$pathHelp.Size=New-Object System.Drawing.Size(570,38);
$form.Controls.Add($pathHelp);
$ok=New-Object System.Windows.Forms.Button;
$ok.Text='Create';
$ok.Location=New-Object System.Drawing.Point(450,666);
$ok.DialogResult=[System.Windows.Forms.DialogResult]::OK;
$form.AcceptButton=$ok;
$form.Controls.Add($ok);
$cancel=New-Object System.Windows.Forms.Button;
$cancel.Text='Cancel';
$cancel.Location=New-Object System.Drawing.Point(535,666);
$cancel.DialogResult=[System.Windows.Forms.DialogResult]::Cancel;
$form.CancelButton=$cancel;
$form.Controls.Add($cancel);

$script:lastInterpreterDefault=''
$script:lastSearchDefault=''
$updateVscodePaths={
  $environmentPath=$pathText.Text.Trim()
  if (-not $environmentPath) { $environmentPath=$env:def_env_path }
  try {
    $environmentPath=[IO.Path]::GetFullPath($environmentPath).TrimEnd([char]'\')
    $interpreterDefault=Join-Path $environmentPath 'Scripts\python.exe'
    $searchDefault=[IO.Directory]::GetParent($environmentPath).FullName
    if (-not $interpreterText.Text -or $interpreterText.Text -eq $script:lastInterpreterDefault) { $interpreterText.Text=$interpreterDefault }
    if (-not $searchText.Text -or $searchText.Text -eq $script:lastSearchDefault) { $searchText.Text=$searchDefault }
    $script:lastInterpreterDefault=$interpreterDefault
    $script:lastSearchDefault=$searchDefault
  } catch { }
}
$pathText.Add_TextChanged($updateVscodePaths)
& $updateVscodePaths
$result=$form.ShowDialog();
if ($result -eq [System.Windows.Forms.DialogResult]::OK) { $ep=$pathText.Text.Trim();
if (-not $ep) { $ep=$env:def_env_path };
$pv=$text.Text.Trim();
if (-not $pv) { $pv=$env:def_version };
$pk=($packagesText.Text -replace '[\r\n\t]+',' ').Trim();
Write-Output ('env_path=' + $ep);
Write-Output ('version=' + $pv);
Write-Output ('vscode_interpreter_path=' + $interpreterText.Text.Trim());
Write-Output ('vscode_env_search_path=' + $searchText.Text.Trim());
Write-Output ('packages_was_set=Y');
Write-Output ('packages=' + $pk);
Write-Output ('install_notebook_support=' + $(if ($j.Checked) { 'Y' } else { 'N' }));
Write-Output ('set_vscode_default=' + $(if ($v.Checked) { 'Y' } else { 'N' }));
Write-Output ('set_vscode_search_path=' + $(if ($s.Checked) { 'Y' } else { 'N' }));
Write-Output ('create_desktop_shortcuts=' + $(if ($d.Checked) { 'Y' } else { 'N' }));
Write-Output ('add_to_path=' + $(if ($p.Checked) { 'Y' } else { 'N' })) } else { Write-Output 'cancelled=1' }
# END ENV SETTINGS

:: End the Python raw string that hides the batch code for Python. -> """

# ---------------------------------------------------------------------------
# VS Code settings updater
# ---------------------------------------------------------------------------
# Runs only when the batch section calls `py -x "%~f0"`. It updates the user
# settings JSONC while preserving comments where practical.

replace_existing = True
import json, os, re, sys

RED = "\033[91m"
GREEN = "\033[92m"
RESET = "\033[0m"

action = os.environ.get("PY_ENV_HELPER_ACTION", "update_vscode_settings")


# Preserve exactly what was entered, including relative paths and VS Code variables.
settings = {}
vscode_python = os.environ.get("PY_ENV_HELPER_VSCODE_PYTHON")
if vscode_python:
    settings["python.defaultInterpreterPath"] = vscode_python

vscode_search_path = os.environ.get("PY_ENV_HELPER_VSCODE_SEARCH_PATH")
if vscode_search_path:
    settings["python-envs.globalSearchPaths"] = [vscode_search_path]

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
        print(f"{GREEN} --Kernel started and completed the Jupyter handshake--{RESET}")
    finally:
        if client is not None:
            client.stop_channels()
        if manager.has_kernel:
            manager.shutdown_kernel(now=True)

if action == "validate_jupyter_kernel":
    try:
        validate_jupyter_kernel()
    except Exception as exc:
        print(
            RED
            + " [Error] Jupyter kernel handshake failed: {0}: {1}".format(type(exc).__name__, exc)
            + RESET
        )
        sys.exit(1)
    sys.exit(0)

if action != "update_vscode_settings":
    print(RED + " [Error] Unknown embedded Python action: " + action + RESET)
    sys.exit(2)

if settings:
    txt = read_text(path)
    txt = migrate_array_setting(txt, "python.venvFolders", "python-envs.globalSearchPaths")
    for setting_key, value in settings.items():
        txt = set_key_value(txt, setting_key, json.dumps(value), replace_existing)
    write_text(path, txt)
    print(GREEN + " --Updated VS Code user settings: " + path + "--" + RESET)

sys.exit(0)

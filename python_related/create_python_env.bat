@setlocal EnableExtensions DisableDelayedExpansion & @echo off
REM=r""" <- lets Python ignore the batch part of this file.
:: The first line is skipped when this file is launched with `py -x`.
:: The Python code starts near the bottom.
:: The first part is normal batch code which will in the end launch the Python code.

for /F "delims=#" %%E in ('"prompt #$E# & for %%E in (1) do rem"') do set "ESC=%%E"
set "GREEN=%ESC%[92m"
set "RED=%ESC%[91m"
set "RESET=%ESC%[0m"
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
::   python.venvPath
:: Both VS Code options always update user settings, using absolute paths
:: derived from the environment path.
:: A search path is added to the existing list instead of replacing it.
:: python.venvPath holds only one folder, so it is replaced and the old value is printed.
:: Before any change, a dated copy is saved in the settings_backups folder next to the file.
:: It also moves the deprecated python.venvFolders setting to absolute search paths.
::
:: After installing packages, the exact versions are saved in the environment
:: folder as requirements.lock.txt.

:: ---------------------------------------------------------------------------
:: Command-line flags
:: ---------------------------------------------------------------------------
:: --path PATH              Folder where the virtual environment is created or reused.
::                         If it already contains a compatible environment, it is reused.
::                         The selected packages, Jupyter support, shortcuts, PATH, and
::                         VS Code settings are then applied to that environment.
:: --packages "PKG PKG"     Exact package list instead of the profiles below, separated by spaces,
::                         e.g. "numpy>=2 scipy". Packages that only work on NVIDIA GPUs
::                         are left out when this computer has no NVIDIA GPU.
:: --version VERSION        Python version to use. Reuses the newest compatible installed Python,
::                         otherwise uv installs the newest compatible release; e.g. 3, 3.13, 3.13.5.
:: --vscode-default Y|N     Make VS Code use this environment by default for Python files.
:: --vscode-search-path Y|N Let VS Code discover environments in this environment folder.
:: --notebook-support Y|N   Install the jupyter profile so this environment can run notebooks.
:: --register-kernel Y|N    Register this environment as a Jupyter kernel (needs the jupyter profile).
:: --desktop-python Y|N     Copy the Python shortcut to the Desktop.
:: --desktop-install Y|N    Copy the package terminal shortcut to the Desktop.
:: --desktop-terminal Y|N   Copy the activated terminal shortcut to the Desktop.
:: --start-python Y|N       Copy the Python shortcut to the "Python environments" Start Menu folder.
:: --start-install Y|N      Copy the package terminal shortcut to that Start Menu folder.
:: --start-terminal Y|N     Copy the activated terminal shortcut to that Start Menu folder.
:: --desktop-shortcuts Y|N  Set every Desktop shortcut that has no individual flag.
:: --start-menu-shortcuts Y|N  Set every Start Menu shortcut that has no individual flag.
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

:: Ask Windows for Documents because it can be moved away from the user profile.
for /f "delims=" %%D in ('powershell -NoProfile -Command "[Environment]::GetFolderPath('MyDocuments')"') do SET "documents_path=%%D"
IF NOT DEFINED documents_path SET "documents_path=%USERPROFILE%\Documents"
SET "def_env_path=%documents_path%\python_envs\default_env"
SET "def_version=3"
SET "def_install_notebook_support=Y"
SET "def_set_vscode_default=N"
SET "def_set_vscode_search_path=N"
SET "def_register_kernel=Y"
SET "def_desktop_python=N"
SET "def_desktop_install=Y"
SET "def_desktop_terminal=N"
SET "def_start_python=Y"
SET "def_start_install=Y"
SET "def_start_terminal=Y"
SET "shortcut_flags=desktop_python desktop_install desktop_terminal start_python start_install start_terminal"
SET "def_add_to_path=N"
:: uv release installed when uv is not already available. To update, change the
:: version and copy both hashes from the .sha256 files on that GitHub release.
SET "uv_pinned_version=0.13.7"
SET "uv_sha256_x64=0cdc5b38fe5a8168ed6a25814f5ba43c21d313dd3187314fccb37b7cec46e021"
SET "uv_sha256_arm64=505d9e65e7692bac3ddf98c66754aa26c5050c409c184af30a881a0a72cc85e3"
SET "validate_jupyter_kernel=N"
:: Each profile is one checkbox and editable list in the settings dialog.
:: gpu packages are left out automatically on computers without an NVIDIA GPU.
:: The jupyter profile installs last so later installs cannot replace its dependencies.
SET "def_profile_basic=numpy matplotlib pandas types-python-dateutil pillow tqdm types-tqdm pyyaml types-PyYAML rich pytest platformdirs openpyxl pyarrow py7zr html5lib"
SET "def_profile_science=scipy scipy-stubs numba scikit-learn scikit-image opencv-python h5py tifffile jax"
SET "def_profile_physics=lightwaveexplorer pybaselines chemometrics jcamp binreduce@git+https://gitlab.com/leberwurscht/binreduce.git@b2168ac053b0e7156e913a1cbb0b0c6d3e5532ff pyserial types-pyserial nptdms"
SET "def_profile_gpu=cupy-cuda12x nvmath-python"
SET "def_profile_apps=pyside6 PyQt5 pywin32 types-pywin32 pyautogui types-PyAutoGUI pywinauto nuitka"
SET "def_profile_jupyter=ipykernel ipywidgets ipympl"
SET "def_packages=%def_profile_basic% %def_profile_science% %def_profile_physics% %def_profile_gpu% %def_profile_apps%"

:: ---------------------------------------------------------------------------
:: Resolve configuration
:: ---------------------------------------------------------------------------
:: Merge command-line args, GUI values, and defaults into final settings before
:: touching Python, folders, packages, shortcuts, or editor settings.

IF NOT "%packages_was_set%"=="Y" IF NOT DEFINED packages SET "packages=%def_packages%"
IF "%env_path%"=="" SET "env_path=%def_env_path%"
:: A group flag fills in every shortcut that has no individual flag.
IF DEFINED create_desktop_shortcuts for %%S in (python install terminal) do IF NOT DEFINED desktop_%%S SET "desktop_%%S=%create_desktop_shortcuts%"
IF DEFINED create_start_menu_shortcuts for %%S in (python install terminal) do IF NOT DEFINED start_%%S SET "start_%%S=%create_start_menu_shortcuts%"
IF /I "%skip_settings_dialog%"=="Y" (
  IF "%version%"=="" SET "version=%def_version%"
  IF "%install_notebook_support%"=="" SET "install_notebook_support=%def_install_notebook_support%"
  IF "%set_vscode_default%"=="" SET "set_vscode_default=%def_set_vscode_default%"
  IF "%set_vscode_search_path%"=="" SET "set_vscode_search_path=%def_set_vscode_search_path%"
  for %%S in (%shortcut_flags%) do IF NOT DEFINED %%S CALL SET "%%S=%%def_%%S%%"
  IF "%register_kernel%"=="" SET "register_kernel=%def_register_kernel%"
  IF "%add_to_path%"=="" SET "add_to_path=%def_add_to_path%"
) ELSE (
  SET "needs_settings_dialog="
  IF "%version%"=="" SET "needs_settings_dialog=Y"
  IF "%install_notebook_support%"=="" SET "needs_settings_dialog=Y"
  IF "%set_vscode_default%"=="" SET "needs_settings_dialog=Y"
  IF "%set_vscode_search_path%"=="" SET "needs_settings_dialog=Y"
  for %%S in (%shortcut_flags%) do IF NOT DEFINED %%S SET "needs_settings_dialog=Y"
  IF "%register_kernel%"=="" SET "needs_settings_dialog=Y"
  IF "%add_to_path%"=="" SET "needs_settings_dialog=Y"
  IF DEFINED needs_settings_dialog (
    CALL :prompt_environment_settings
    IF ERRORLEVEL 2 GOTO :cancelled
    IF ERRORLEVEL 1 GOTO :fail
  )
)
IF "%env_path%"=="" SET "env_path=%def_env_path%"
IF NOT DEFINED jupyter_packages SET "jupyter_packages=%def_profile_jupyter%"

:: Arguments and dialog values are read before delayed expansion starts, so "!"
:: in version specifiers such as "numpy!=2.0" survives. Paths are expanded with
:: %%...%% below, where "!" would vanish and "&" would split the command.
IF NOT "%env_path:!=%"=="%env_path%" GOTO invalid_env_path_character
IF NOT "%env_path:&=%"=="%env_path%" GOTO invalid_env_path_character
SETLOCAL EnableDelayedExpansion

CALL :normalize_yes_no "install_notebook_support" || goto :fail
CALL :normalize_yes_no "set_vscode_default" || goto :fail
CALL :normalize_yes_no "set_vscode_search_path" || goto :fail
for %%S in (%shortcut_flags%) do CALL :normalize_yes_no "%%S" || goto :fail
CALL :normalize_yes_no "register_kernel" || goto :fail
CALL :normalize_yes_no "add_to_path" || goto :fail

:: The appended "\." makes %%~f drop a trailing backslash, which would otherwise
:: leave the environment without a folder name.
CALL :make_absolute_path "%env_path%\." || goto :fail
SET "env_path=%OUTPUT%"
for %%F in ("%env_path%\..") do SET "env_parent_path=%%~fF"

for %%F in ("%env_path%") do set "env_name=%%~nxF"
IF "%env_name%"=="" (
  CALL :print_red [Error] The environment path must be a folder, not a drive root: "%env_path%"
  goto :fail
)
IF NOT DEFINED vscode_interpreter_path SET "vscode_interpreter_path=%env_path%\Scripts\python.exe"
IF NOT DEFINED vscode_env_search_path SET "vscode_env_search_path=%env_parent_path%"

:: Keep the default cache on the environment drive so uv can hardlink wheels.
:: An explicitly configured cache directory takes precedence.
IF NOT DEFINED UV_CACHE_DIR SET "UV_CACHE_DIR=%env_parent_path%\.uv-cache"
CALL :use_pip_index_for_uv
CALL :ensure_uv_tool || goto :fail
CALL :resolve_python_version || goto :fail

:: ---------------------------------------------------------------------------
:: Create and configure environment
:: ---------------------------------------------------------------------------
:: Ensure the requested Python exists, create/activate the venv, install
:: packages, add optional tooling, create shortcuts, and apply integrations.

echo:!GREEN!--Settings--!RESET!
echo:
echo:!GREEN!Environment path: %env_path%!RESET!
echo:!GREEN!Python version request: %version_request%!RESET!
echo:!GREEN!Python packages: !packages!!RESET!
echo:!GREEN!Set VS Code default interpreter: %set_vscode_default%!RESET!
IF /I "%set_vscode_default%"=="Y" echo:!GREEN!  Interpreter path: %vscode_interpreter_path%!RESET!
echo:!GREEN!Add VS Code env search path: %set_vscode_search_path%!RESET!
IF /I "%set_vscode_search_path%"=="Y" echo:!GREEN!VS Code env search path: %vscode_env_search_path%!RESET!
echo:!GREEN!Install Jupyter notebook support (!jupyter_packages!): %install_notebook_support%!RESET!
echo:!GREEN!Register Jupyter kernel: %register_kernel%!RESET!
echo:!GREEN!Desktop shortcuts: python=%desktop_python% packages=%desktop_install% terminal=%desktop_terminal%!RESET!
echo:!GREEN!Start Menu shortcuts: python=%start_python% packages=%start_install% terminal=%start_terminal%!RESET!
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
mkdir "%USERPROFILE%\Documents\Repositories" 2> NUL

:: Create Python launch and package-install shortcuts.
CALL :read_python_version "%env_python%" env_python_version
CALL :resolve_shared_shortcut_folders
CALL :resolve_shortcut_label

:: The package terminal is Python, so package specifiers never pass through batch parsing.
set "PY_ENV_HELPER_ACTION=write_package_terminal"
"%env_python%" -x "%~f0" || goto :fail
set "PY_ENV_HELPER_ACTION="

:: A .lnk cannot set a window title, so each shortcut runs a small wrapper script.
SET "python_launcher_name=Python (%shortcut_env_label%)"
SET "python_launcher_cmd=%env_path%\%python_launcher_name%.cmd"
> "%python_launcher_cmd%" echo @echo off
>> "%python_launcher_cmd%" echo title Python - %env_name% - Python !env_python_version!
>> "%python_launcher_cmd%" echo "%%~dp0Scripts\python.exe"
>> "%python_launcher_cmd%" echo if errorlevel 1 pause
CALL :create_launcher python "%python_launcher_name%" "%python_launcher_cmd%" /c "%env_python%"

SET "install_launcher_name=Packages (%shortcut_env_label%)"
SET "install_launcher_cmd=%env_path%\%install_launcher_name%.cmd"
> "%install_launcher_cmd%" echo @echo off
>> "%install_launcher_cmd%" echo title Packages - %env_name% - Python !env_python_version!
>> "%install_launcher_cmd%" echo "%%~dp0Scripts\python.exe" "%%~dp0package_terminal.py"
>> "%install_launcher_cmd%" echo if errorlevel 1 pause
CALL :create_launcher install "%install_launcher_name%" "%install_launcher_cmd%" /c ""

SET "terminal_launcher_name=Terminal (%shortcut_env_label%)"
SET "terminal_launcher_cmd=%env_path%\%terminal_launcher_name%.cmd"
> "%terminal_launcher_cmd%" echo @echo off
>> "%terminal_launcher_cmd%" echo title Terminal - %env_name% - Python !env_python_version!
>> "%terminal_launcher_cmd%" echo if not defined UV_CACHE_DIR set "UV_CACHE_DIR=%%~dp0..\.uv-cache"
>> "%terminal_launcher_cmd%" echo if defined PIP_INDEX_URL if not defined UV_DEFAULT_INDEX set "UV_DEFAULT_INDEX=%%PIP_INDEX_URL%%"
>> "%terminal_launcher_cmd%" echo if not defined UV_DEFAULT_INDEX for /f "delims=" %%%%I in ('"%%~dp0Scripts\python.exe" -m pip config get global.index-url 2^^^>nul') do set "UV_DEFAULT_INDEX=%%%%I"
>> "%terminal_launcher_cmd%" echo call "%%~dp0Scripts\activate.bat"
:: /k keeps this window open at a prompt with the environment active.
CALL :create_launcher terminal "%terminal_launcher_name%" "%terminal_launcher_cmd%" /k ""

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
  IF ERRORLEVEL 1 set "vscode_settings_failed=Y"
  set "PY_ENV_HELPER_ACTION="
) 

:: Install requested packages first. Install and validate Jupyter last so later
:: package installs cannot silently replace one of its runtime dependencies.
set "needs_package_install="
set "package_report_file=%TEMP%\python_env_helper_report_%RANDOM%.txt"
IF DEFINED packages set "needs_package_install=Y"
IF /I "%install_notebook_support%"=="Y" set "needs_package_install=Y"
IF /I "%needs_package_install%"=="Y" (
  echo:
  CALL :ensure_uv
  IF DEFINED packages (
    echo:!GREEN!--Installing requested packages--!RESET!
    echo:
    CALL :install_package_list packages failed_packages
    echo:
    echo:!GREEN!--Finished installing requested packages--!RESET!
    echo:
  )
  IF /I "%install_notebook_support%"=="Y" CALL :finish_jupyter_setup
  CALL :write_lock_file
) ELSE (
  echo:
  echo:!GREEN!--No package installation requested--!RESET!
  echo:
)

set "setup_warnings="
IF "%pip_upgrade_failed%"=="Y" (
  CALL :print_red [Warning] Updating pip or uv failed.
  set "setup_warnings=Y"
)
IF EXIST "!package_report_file!" (
  type "!package_report_file!"
  del "!package_report_file!" >nul 2>&1
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
IF "%vscode_settings_failed%"=="Y" (
  CALL :print_red [Warning] VS Code settings were not updated.
  set "setup_warnings=Y"
)
IF "%lock_file_failed%"=="Y" (
  CALL :print_red [Warning] requirements.lock.txt could not be written.
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
IF DEFINED created_env_shortcuts echo:!GREEN!Shortcuts in environment folder:!created_env_shortcuts!!RESET!
IF DEFINED created_desktop_shortcuts echo:!GREEN!Shortcuts on Desktop:!created_desktop_shortcuts!!RESET!
IF DEFINED created_start_menu_shortcuts echo:!GREEN!Shortcuts in Start Menu folder "Python environments":!created_start_menu_shortcuts!!RESET!
echo:!GREEN!Press any key to exit.!RESET!
pause > nul
exit /b 0

:cancelled
echo:
echo:%GREEN%Setup cancelled.%RESET%
exit /b 0

:: ---------------------------------------------------------------------------
:: Batch subroutines
:: ---------------------------------------------------------------------------
:: Keep the main flow above readable. Each label exits with a batch errorlevel.

:invalid_env_path_character
  echo:%RED%[Error] The environment path cannot contain "!" or "&".%RESET%
  echo:%RED%  Path: "%env_path%"%RESET%
  goto :fail

:: Reached before and after delayed expansion starts, so use %%...%% colors here.
:fail
  echo:
  echo:
  echo:%RED%ERROR: Python environment setup failed (see errors above^).%RESET%
  echo:%RED%Fix the error shown above, then run this script again.%RESET%
  echo:%RED%Press any key to exit.%RESET%
  pause > nul
  exit /b 1

:process_args
  IF "%~1"=="" exit /b 0
  SET "arg_target="
  IF "%~1"=="--path" SET "arg_target=env_path"
  IF "%~1"=="--version" SET "arg_target=version"
  IF "%~1"=="--notebook-support" SET "arg_target=install_notebook_support"
  IF "%~1"=="--vscode-default" SET "arg_target=set_vscode_default"
  IF "%~1"=="--vscode-search-path" SET "arg_target=set_vscode_search_path"
  IF "%~1"=="--desktop-shortcuts" SET "arg_target=create_desktop_shortcuts"
  IF "%~1"=="--start-menu-shortcuts" SET "arg_target=create_start_menu_shortcuts"
  IF "%~1"=="--desktop-python" SET "arg_target=desktop_python"
  IF "%~1"=="--desktop-install" SET "arg_target=desktop_install"
  IF "%~1"=="--desktop-terminal" SET "arg_target=desktop_terminal"
  IF "%~1"=="--start-python" SET "arg_target=start_python"
  IF "%~1"=="--start-install" SET "arg_target=start_install"
  IF "%~1"=="--start-terminal" SET "arg_target=start_terminal"
  IF "%~1"=="--register-kernel" SET "arg_target=register_kernel"
  IF "%~1"=="--add-to-path" SET "arg_target=add_to_path"
  IF NOT DEFINED arg_target GOTO process_args_not_value_flag
  IF NOT "%~2"=="" GOTO process_args_flag_has_text
  :: An explicit "" still selects the default; only a missing argument is an error.
  IF "%2"=="" GOTO process_args_missing_value
  GOTO process_args_store_flag
:process_args_flag_has_text
  SET "arg_value=%~2"
  IF "%arg_value:~0,2%"=="--" GOTO process_args_missing_value
:process_args_store_flag
  SET "skip_settings_dialog=Y"
  SET "%arg_target%=%~2"
  shift
  shift
  GOTO process_args

:process_args_missing_value
  CALL :print_red [Error] %~1 needs a value.
  exit /b 1

:process_args_not_value_flag
  IF NOT "%~1"=="--packages" GOTO process_args_positional
  SET "skip_settings_dialog=Y"
  SET "packages_was_set=Y"
  SET "packages="
  IF "%~2"=="" GOTO process_args_packages_done
  SET "arg_value=%~2"
  IF NOT "%arg_value:~0,2%"=="--" GOTO process_args_store_packages
  :: --packages followed by another flag means "install no packages".
  shift
  GOTO process_args
:process_args_store_packages
  SET "packages=%~2"
:process_args_packages_done
  shift
  shift
  GOTO process_args

:process_args_positional
  SET "arg_value=%~1"
  IF "%arg_value:~0,2%"=="--" (
    CALL :print_red [Error] Unknown option: %~1
    exit /b 1
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

:read_venv_cfg_version
  set "%~1="
  IF NOT EXIST "%env_path%\pyvenv.cfg" exit /b 0
  for /f "tokens=1,* delims==" %%A in ('findstr /B /I "version" "%env_path%\pyvenv.cfg" 2^>nul') do (
    set "cfg_key=%%A"
    set "cfg_key=!cfg_key: =!"
    REM The venv module writes "version"; uv writes "version_info".
    IF /I "!cfg_key!"=="version" set "cfg_is_version=Y"
    IF /I "!cfg_key!"=="version_info" set "cfg_is_version=Y"
    IF "!cfg_is_version!"=="Y" (
      set "cfg_is_version="
      set "cfg_value=%%B"
      for /f "tokens=* delims= " %%V in ("!cfg_value!") do set "%~1=%%V"
    )
  )
  exit /b 0

:fail_existing_env_reuse
  echo:
  CALL :print_red --Cannot reuse existing environment--
  CALL :print_red --Delete or empty that folder. Press any key afterwards to continue.
:wait_for_existing_env_reuse
  pause > nul
  IF EXIST "%env_path%" (
    CALL :existing_env_is_empty
    IF ERRORLEVEL 1 (
      echo:
      CALL :print_red --Folder is still not empty. Delete or empty it, then press any key to check again.
      GOTO wait_for_existing_env_reuse
    )
  )
  echo:
  exit /b 0

:prompt_environment_settings
  IF "%env_path%"=="" set "env_path=%def_env_path%"
  IF NOT DEFINED packages set "packages=%def_packages%"
  IF "%version%"=="" set "version=%def_version%"
  IF "%install_notebook_support%"=="" set "install_notebook_support=%def_install_notebook_support%"
  IF "%set_vscode_default%"=="" set "set_vscode_default=%def_set_vscode_default%"
  IF "%set_vscode_search_path%"=="" set "set_vscode_search_path=%def_set_vscode_search_path%"
  for %%S in (%shortcut_flags%) do IF NOT DEFINED %%S CALL SET "%%S=%%def_%%S%%"
  IF "%register_kernel%"=="" set "register_kernel=%def_register_kernel%"
  IF "%add_to_path%"=="" set "add_to_path=%def_add_to_path%"
  set "PY_ENV_HELPER_SELF=%~f0"
  set "dialog_completed="
  for /f "tokens=1,* delims==" %%A in ('powershell -NoProfile -Command "$source=Get-Content -LiteralPath $env:PY_ENV_HELPER_SELF -Raw; $dialog=[regex]::Match($source,'(?ms)^# BEGIN ENV SETTINGS\r?\n(.*?)^# END ENV SETTINGS').Groups[1].Value; ([scriptblock]::Create($dialog)).Invoke()"') do set "%%A=%%B"
  set "PY_ENV_HELPER_SELF="
  REM Without this check a blocked dialog would silently run the full default setup.
  IF DEFINED dialog_completed GOTO settings_dialog_finished
  CALL :print_red [Error] The settings dialog could not run. PowerShell may be restricted on this computer.
  CALL :print_red Nothing was changed. Pass the settings as flags instead, for example --path and --version.
  exit /b 1
:settings_dialog_finished
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

:: uv ignores pip's settings, so a company package server set up for pip would be
:: bypassed. Later values in pip's own lookup order win, so check those files first.
:: The address can contain a password, so it is never printed or written to a file.
:use_pip_index_for_uv
  IF DEFINED UV_DEFAULT_INDEX exit /b 0
  IF DEFINED UV_INDEX_URL exit /b 0
  for /f "delims=" %%I in ('powershell -NoProfile -Command "if ($env:PIP_INDEX_URL) { $env:PIP_INDEX_URL; exit 0 }; $files=@($env:PIP_CONFIG_FILE,(Join-Path $env:APPDATA 'pip\pip.ini'),(Join-Path $env:USERPROFILE 'pip\pip.ini'),(Join-Path $env:ProgramData 'pip\pip.ini')) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }; foreach ($f in $files) { $section=''; $found=@{}; foreach ($l in Get-Content -LiteralPath $f) { if ($l -match '^\s*\[(.+?)\]') { $section=$Matches[1].ToLower() } elseif ($l -match '^\s*index[-_]url\s*[=:]\s*(\S+)') { $found[$section]=$Matches[1] } }; $url=$found['install']; if (-not $url) { $url=$found['global'] }; if ($url) { $url; exit 0 } }"') do set "UV_DEFAULT_INDEX=%%I"
  IF DEFINED UV_DEFAULT_INDEX echo:!GREEN!Using the package index configured for pip.!RESET!
  exit /b 0

:ensure_uv_tool
  set "uv_exe="
  REM The copy inside the target environment is skipped because setup updates it.
  for /f "delims=" %%U in ('where.exe uv 2^>nul') do (
    IF NOT DEFINED uv_exe IF /I NOT "%%~dpU"=="%env_path%\Scripts\" set "uv_exe=%%U"
  )
  set "uv_install_dir=%USERPROFILE%\.local\bin"
  IF NOT DEFINED uv_exe IF EXIST "%uv_install_dir%\uv.exe" set "uv_exe=%uv_install_dir%\uv.exe"
  IF DEFINED uv_exe (
    echo:!GREEN!Using uv: "!uv_exe!"!RESET!
    echo:
    exit /b 0
  )
  echo:!GREEN!--Installing uv %uv_pinned_version% to "%uv_install_dir%"--!RESET!
  echo:
  REM This script always calls uv by full path, so PATH does not need to change.
  REM The archive is only unpacked after its checksum matches the pinned value.
  set "uv_target=x86_64-pc-windows-msvc"
  set "uv_sha256=%uv_sha256_x64%"
  IF /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "uv_target=aarch64-pc-windows-msvc"
  IF /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "uv_sha256=%uv_sha256_arm64%"
  set "uv_url=https://github.com/astral-sh/uv/releases/download/%uv_pinned_version%/uv-!uv_target!.zip"
  powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $zip=Join-Path $env:TEMP ('uv-' + [guid]::NewGuid() + '.zip'); try { Invoke-WebRequest -UseBasicParsing $env:uv_url -OutFile $zip -ErrorAction Stop; $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash; if ($actual -ine $env:uv_sha256) { [Console]::Error.WriteLine('Checksum mismatch: the downloaded uv archive was not installed.'); exit 2 }; New-Item -ItemType Directory -Force $env:uv_install_dir | Out-Null; Expand-Archive -LiteralPath $zip -DestinationPath $env:uv_install_dir -Force -ErrorAction Stop } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 } finally { Remove-Item -LiteralPath $zip -ErrorAction SilentlyContinue }"
  IF ERRORLEVEL 1 GOTO uv_install_failed
  IF NOT EXIST "%uv_install_dir%\uv.exe" GOTO uv_install_failed
  set "uv_exe=%uv_install_dir%\uv.exe"
  echo:
  exit /b 0

:uv_install_failed
  CALL :print_red [Error] Could not install uv to "%uv_install_dir%".
  CALL :print_red You can install it yourself with: winget install astral-sh.uv
  exit /b 1

:resolve_python_version
  set "version_request=%version%"
  set "exact_version_requested=N"
  for /f "tokens=1-3 delims=." %%A in ("%version_request%") do (
    IF NOT "%%C"=="" set "exact_version_requested=Y"
  )
  set "existing_env_python_version_for_request="
  IF EXIST "%env_path%\Scripts\python.exe" (
    CALL :read_python_version "%env_path%\Scripts\python.exe" existing_env_python_version_for_request
    CALL :version_matches_request "!existing_env_python_version_for_request!"
    IF NOT ERRORLEVEL 1 (
      set "version=!existing_env_python_version_for_request!"
      exit /b 0
    )
    IF "!existing_env_python_version_for_request!"=="" (
      CALL :read_venv_cfg_version existing_env_python_version_for_request
      CALL :version_matches_request "!existing_env_python_version_for_request!"
      IF NOT ERRORLEVEL 1 (
        set "version=!existing_env_python_version_for_request!"
        exit /b 0
      )
    )
  )
  CALL :ensure_python
  exit /b %ERRORLEVEL%

:find_installed_python
  set "python_exe="
  REM uv lists newest first. Stable default builds named python.exe are preferred
  REM over free-threaded builds, pre-releases, and the Python Install Manager aliases.
  for /f "tokens=1,* delims=|" %%A in ('powershell -NoProfile -Command "$arch=if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }; $json=(& $env:uv_exe python list $env:version_request --only-installed --output-format json 2>$null | Out-String); foreach ($p in (ConvertFrom-Json $json)) { if ($p.implementation -eq 'cpython' -and $p.variant -eq 'default' -and $p.arch -eq $arch -and $p.version -match '^\d+\.\d+\.\d+$' -and (Split-Path -Leaf $p.path) -eq 'python.exe' -and (Test-Path -LiteralPath $p.path)) { Write-Output ($p.version + '|' + $p.path); exit 0 } }"') do (
    set "version=%%A"
    set "python_exe=%%B"
  )
  exit /b 0

:ensure_python
  IF DEFINED python_exe exit /b 0
  CALL :find_installed_python
  IF DEFINED python_exe (
    echo:!GREEN!--Compatible Python !version! already installed on computer--!RESET!
  ) ELSE (
    echo:!GREEN!--Installing Python %version_request% with uv--!RESET!
    echo:
    "%uv_exe%" python install "%version_request%"
    IF ERRORLEVEL 1 (
      CALL :print_red [Error] uv could not install Python %version_request%.
      exit /b 1
    )
    CALL :find_installed_python
    IF NOT DEFINED python_exe (
      CALL :print_red [Error] uv finished, but no stable Python matching %version_request% was found.
      exit /b 1
    )
    echo:
    echo:!GREEN!--Finished installing Python !version!--!RESET!
  )
  echo:!GREEN!Python used to create environment: !version!!RESET!
  echo:!GREEN!  "!python_exe!"!RESET!
  echo:
  exit /b 0

:create_venv
  del "%env_path%\_python_env_setup_problem.txt" >nul 2>&1
  IF NOT DEFINED python_exe (
    CALL :print_red [Error] No verified Python %version% executable path is available for creating the environment.
    exit /b 1
  )
  REM --allow-existing keeps a harmless desktop.ini; the folder was already checked as empty.
  "%uv_exe%" venv --python "%python_exe%" --seed --allow-existing "%env_path%" || exit /b 1
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
  echo:!GREEN!--Installing/updating pip and uv in this environment--!RESET!
  echo:
  REM The Install package shortcut uses this environment's own uv, with pip as fallback.
  "%uv_exe%" pip install --python "%env_python%" --upgrade pip uv
  IF ERRORLEVEL 1 (
    set "pip_upgrade_failed=Y"
    CALL :print_red [Warning] Failed to update pip or uv. Package installs may use pip.
  )
  echo:
  exit /b 0

:: %1 names the variable holding the package list; %2 is set to Y if any failed.
:install_package_list
  set "%~2="
  REM Python does the splitting and running: batch cannot pass specifiers such as
  REM numpy^>=2 through FOR without breaking them.
  set "PY_ENV_HELPER_RESULT_FILE=!package_report_file!"
  set "PY_ENV_HELPER_PACKAGE_VAR=%~1"
  set "PY_ENV_HELPER_ACTION=install_packages"
  "%env_python%" -x "%~f0"
  set "install_packages_exit_code=!ERRORLEVEL!"
  set "PY_ENV_HELPER_ACTION="
  IF NOT "!install_packages_exit_code!"=="0" set "%~2=Y"
  REM Exit code 3 means Python already wrote its failures to the report.
  IF NOT "!install_packages_exit_code!"=="0" IF NOT "!install_packages_exit_code!"=="3" >> "!package_report_file!" echo:!RED!The package installer stopped unexpectedly.!RESET!
  exit /b 0

:write_lock_file
  set "PY_ENV_HELPER_ACTION=write_lock_file"
  "%env_python%" -x "%~f0"
  IF ERRORLEVEL 1 set "lock_file_failed=Y"
  set "PY_ENV_HELPER_ACTION="
  exit /b 0

:install_jupyter_support
  set "jupyter_support_failed="
  echo:!GREEN!--Installing Jupyter notebook support (!jupyter_packages!)--!RESET!
  echo:
  CALL :install_package_list jupyter_packages jupyter_failed_packages
  IF DEFINED jupyter_failed_packages set "jupyter_support_failed=Y"
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

  IF /I NOT "%register_kernel%"=="Y" GOTO skip_kernel_registration
  set "PY_ENV_HELPER_ACTION=register_jupyter_kernel"
  "%env_python%" -x "%~f0"
  IF ERRORLEVEL 1 (
    set "jupyter_kernel_failed=Y"
    CALL :print_red [Warning] Failed to register kernel with ipykernel.
  ) ELSE (
    echo:!GREEN!--Registered kernel with ipykernel--!RESET!
  )
  set "PY_ENV_HELPER_ACTION="
  echo:

:skip_kernel_registration
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

:resolve_shared_shortcut_folders
  set "desktop_path="
  set "start_menu_path="
  for /f "delims=" %%D in ('powershell -NoProfile -Command "[Environment]::GetFolderPath('Desktop')"') do set "desktop_path=%%D"
  for /f "delims=" %%D in ('powershell -NoProfile -Command "[Environment]::GetFolderPath('Programs')"') do set "start_menu_path=%%D\Python environments"
  exit /b 0

:resolve_shortcut_label
  set "shortcut_env_label=%env_name%"
  REM Same-named environments in different folders would overwrite each other's
  REM shared shortcuts. Keep the plain name unless another live environment owns it.
  for /f "delims=" %%L in ('powershell -NoProfile -Command "$folders=@($env:desktop_path,$env:start_menu_path) | Where-Object { $_ }; $envFull=[IO.Path]::GetFullPath($env:env_path); $shell=New-Object -ComObject WScript.Shell; $sha=[Security.Cryptography.SHA1]::Create(); $hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($env:env_path.ToLowerInvariant()))) -replace '-','').Substring(0,8).ToLowerInvariant(); $hashed=$env:env_name + ' ' + $hash; foreach ($label in @($env:env_name,$hashed)) { $free=$true; foreach ($folder in $folders) { foreach ($prefix in @('Python','Packages','Terminal')) { $lnk=Join-Path $folder ($prefix + ' (' + $label + ').lnk'); if (Test-Path -LiteralPath $lnk) { $link=$shell.CreateShortcut($lnk); $owner=$link.TargetPath; if ($link.Arguments -match '\x22(.+)\x22') { $owner=$Matches[1] }; if ($owner -and (Test-Path -LiteralPath $owner)) { $ownerDir=Split-Path $owner; if ((Split-Path -Leaf $ownerDir) -ieq 'Scripts') { $ownerDir=Split-Path $ownerDir }; if ([IO.Path]::GetFullPath($ownerDir) -ine $envFull) { $free=$false } } } } }; if ($free) { Write-Output $label; exit 0 } }; Write-Output $hashed"') do set "shortcut_env_label=%%L"
  exit /b 0

:: %1 key used in the desktop_/start_ settings, %2 shortcut name, %3 wrapper script,
:: %4 cmd switch (/c closes when done, /k stays open), %5 optional icon file.
:create_launcher
  set "launcher_name=%~2"
  set "launcher_lnk=%env_path%\%~2.lnk"
  set "launcher_cmd=%~3"
  set "launcher_switch=%~4"
  set "launcher_icon=%~5"
  set "launcher_workdir=%env_path%"
  del "%launcher_lnk%" >nul 2>&1
  powershell -NoProfile -Command "$s=New-Object -ComObject WScript.Shell;$l=$s.CreateShortcut($env:launcher_lnk);$l.TargetPath=$env:ComSpec;$l.Arguments=$env:launcher_switch + ' call ' + [char]34 + $env:launcher_cmd + [char]34;$l.WorkingDirectory=$env:launcher_workdir;if ($env:launcher_icon) { $l.IconLocation=$env:launcher_icon + ',0' };$l.WindowStyle=1;$l.Save()"
  IF NOT EXIST "%launcher_lnk%" (
    CALL :print_red [Warning] Failed to create shortcut "%launcher_lnk%".
    exit /b 0
  )
  set "created_env_shortcuts=!created_env_shortcuts!  %~2"
  IF /I "!desktop_%~1!"=="Y" CALL :copy_launcher "%desktop_path%" created_desktop_shortcuts
  IF /I "!start_%~1!"=="Y" CALL :copy_launcher "%start_menu_path%" created_start_menu_shortcuts
  exit /b 0

:: %1 destination folder, %2 variable collecting the names copied there.
:copy_launcher
  IF "%~1"=="" (
    CALL :print_red [Warning] Could not determine a shortcut folder for "%launcher_name%".
    exit /b 0
  )
  mkdir "%~1" 2> NUL
  REM Deleting first lets a renamed shortcut pick up new capitalization.
  del "%~1\%launcher_name%.lnk" >nul 2>&1
  copy /Y "%launcher_lnk%" "%~1\%launcher_name%.lnk" >nul || (
    CALL :print_red [Warning] Failed to copy "%launcher_name%" to "%~1".
    exit /b 0
  )
  set "%~2=!%~2!  %launcher_name%"
  exit /b 0

:add_env_to_path
  set "env_scripts_path=%env_path%\Scripts"
  REM PATH is searched left-to-right. Remove existing copies, then add two
  REM separate entries at the beginning so this environment wins over older
  REM Python installations. The registry value is edited directly because
  REM GetEnvironmentVariable would permanently expand entries like %%USERPROFILE%%.
  set "PY_ENV_HELPER_PATH_FIRST=%env_scripts_path%"
  set "PY_ENV_HELPER_PATH_SECOND=%env_path%"
  powershell -NoProfile -Command "$first=$env:PY_ENV_HELPER_PATH_FIRST; $second=$env:PY_ENV_HELPER_PATH_SECOND; $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment'); $kind=[Microsoft.Win32.RegistryValueKind]::ExpandString; if ($key.GetValueNames() -contains 'Path') { $kind=$key.GetValueKind('Path') }; $current=[string]$key.GetValue('Path','',[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames); $entries=@($current -split ';' | Where-Object { $entry=$_.Trim().TrimEnd([char]92); $entry -and -not [string]::Equals($entry,$first,[StringComparison]::OrdinalIgnoreCase) -and -not [string]::Equals($entry,$second,[StringComparison]::OrdinalIgnoreCase) }); $key.SetValue('Path',((@($first,$second)+$entries) -join ';'),$kind); $key.Close(); [Environment]::SetEnvironmentVariable('PY_ENV_HELPER_NOTIFY',$null,'User')" || exit /b 1
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
  echo:%RED%%*%RESET%
  exit /b 0

:make_absolute_path
  SET "OUTPUT=%~f1"
  GOTO :EOF

# BEGIN ENV SETTINGS
Add-Type -AssemblyName System.Windows.Forms;
Add-Type -AssemblyName System.Drawing;
[System.Windows.Forms.Application]::EnableVisualStyles();
$form=New-Object System.Windows.Forms.Form;
$form.Text='Python environment settings';
$form.StartPosition='CenterScreen';
$form.FormBorderStyle='FixedDialog';
$form.MaximizeBox=$false;
$form.MinimizeBox=$false;
$form.ClientSize=New-Object System.Drawing.Size(1240,590);
$form.Font=New-Object System.Drawing.Font('Segoe UI',9);
$sectionFont=New-Object System.Drawing.Font('Segoe UI',10,[System.Drawing.FontStyle]::Bold);
# A 2-pixel label with a 3D border is the standard WinForms divider line.
$addLine={ param($x,$y,$width,$height)
  $line=New-Object System.Windows.Forms.Label;
  $line.AutoSize=$false;
  $line.BorderStyle='Fixed3D';
  $line.Location=New-Object System.Drawing.Point($x,$y);
  $line.Size=New-Object System.Drawing.Size($width,$height);
  $form.Controls.Add($line);
};
$addSection={ param($title,$x,$y,$width)
  $header=New-Object System.Windows.Forms.Label;
  $header.Text=$title;
  $header.Font=$sectionFont;
  $header.Location=New-Object System.Drawing.Point($x,$y);
  $header.AutoSize=$true;
  $form.Controls.Add($header);
  & $addLine $x ($y+24) $width 2;
};
& $addSection 'Environment' 12 10 583;
& $addSection 'Packages' 12 154 583;
& $addSection 'VS Code' 620 10 605;
& $addSection 'Shortcuts' 620 156 605;
& $addSection 'Default Python' 620 300 605;
& $addLine 606 10 2 526;
& $addLine 12 544 1213 2;
$pathLabel=New-Object System.Windows.Forms.Label;
$pathLabel.Text='Environment path (an existing environment with a compatible Python is reused):';
$pathLabel.Location=New-Object System.Drawing.Point(12,40);
$pathLabel.AutoSize=$true;
$form.Controls.Add($pathLabel);
$pathText=New-Object System.Windows.Forms.TextBox;
$pathText.Location=New-Object System.Drawing.Point(15,60);
$pathText.Size=New-Object System.Drawing.Size(580,22);
$pathText.Text=$env:env_path;
$form.Controls.Add($pathText);
$versionLabel=New-Object System.Windows.Forms.Label;
$versionLabel.Text='Python version (chooses installed if compatible, else newest compatible):';
$versionLabel.Location=New-Object System.Drawing.Point(12,96);
$versionLabel.Size=New-Object System.Drawing.Size(583,20);
$form.Controls.Add($versionLabel);
$text=New-Object System.Windows.Forms.TextBox;
$text.Location=New-Object System.Drawing.Point(15,116);
$text.Size=New-Object System.Drawing.Size(160,22);
$text.Text=$env:version;
$form.Controls.Add($text);
$profilesHint=New-Object System.Windows.Forms.Label;
$profilesHint.Text='Checked lists are installed. Every list can be edited.';
$profilesHint.Location=New-Object System.Drawing.Point(100,158);
$profilesHint.Size=New-Object System.Drawing.Size(480,18);
$form.Controls.Add($profilesHint);
$profileBoxes=@();
$packagesPreset=($env:packages_was_set -eq 'Y');
$rowY=186;
foreach ($name in @('basic','science','physics','gpu','apps','jupyter')) {
  $box=New-Object System.Windows.Forms.CheckBox;
  $box.Text=$name;
  $box.Location=New-Object System.Drawing.Point(15,($rowY+2));
  $box.Size=New-Object System.Drawing.Size(92,24);
  $field=New-Object System.Windows.Forms.TextBox;
  $field.Location=New-Object System.Drawing.Point(110,$rowY);
  $field.Size=New-Object System.Drawing.Size(485,42);
  $field.Multiline=$true;
  $field.ScrollBars='Vertical';
  $field.WordWrap=$true;
  $field.Text=[Environment]::GetEnvironmentVariable('def_profile_' + $name);
  if ($name -eq 'jupyter') {
    $box.Checked=($env:install_notebook_support -ieq 'Y' -or $env:install_notebook_support -ieq 'YES');
    $j=$box;
    $jupyterField=$field;
  } else {
    $box.Checked=(-not $packagesPreset);
  }
  $field.Enabled=$box.Checked;
  $box.Tag=$field;
  $box.Add_CheckedChanged({ $this.Tag.Enabled=$this.Checked });
  $form.Controls.Add($box);
  $form.Controls.Add($field);
  $profileBoxes+=$box;
  $rowY+=46;
}
$kernelBox=New-Object System.Windows.Forms.CheckBox;
$kernelBox.Text='Register this environment as a Jupyter kernel';
$kernelBox.Location=New-Object System.Drawing.Point(110,460);
$kernelBox.Size=New-Object System.Drawing.Size(485,24);
$kernelBox.Checked=($env:register_kernel -ieq 'Y' -or $env:register_kernel -ieq 'YES');
$kernelBox.Enabled=$j.Checked;
$j.Add_CheckedChanged({ $kernelBox.Enabled=$j.Checked });
$form.Controls.Add($kernelBox);
$extraLabel=New-Object System.Windows.Forms.Label;
$extraLabel.Text='Other:';
$extraLabel.Location=New-Object System.Drawing.Point(12,494);
$extraLabel.AutoSize=$true;
$form.Controls.Add($extraLabel);
$extraText=New-Object System.Windows.Forms.TextBox;
$extraText.Location=New-Object System.Drawing.Point(110,490);
$extraText.Size=New-Object System.Drawing.Size(485,42);
$extraText.Multiline=$true;
$extraText.ScrollBars='Vertical';
$extraText.WordWrap=$true;
if ($packagesPreset) { $extraText.Text=$env:packages };
$form.Controls.Add($extraText);
$v=New-Object System.Windows.Forms.CheckBox;
$v.Text='Use as VS Code default interpreter';
$v.Location=New-Object System.Drawing.Point(620,40);
$v.Size=New-Object System.Drawing.Size(520,24);
$v.Checked=($env:set_vscode_default -ieq 'Y' -or $env:set_vscode_default -ieq 'YES');
$form.Controls.Add($v);
$vs=New-Object System.Windows.Forms.Label;
$vs.Text='Uses the python.exe of this environment. Saved in VS Code user settings.';
$vs.Location=New-Object System.Drawing.Point(640,66);
$vs.Size=New-Object System.Drawing.Size(560,20);
$form.Controls.Add($vs);
$s=New-Object System.Windows.Forms.CheckBox;
$s.Text='Add to VS Code environment search paths';
$s.Location=New-Object System.Drawing.Point(620,96);
$s.Size=New-Object System.Drawing.Size(520,24);
$s.Checked=($env:set_vscode_search_path -ieq 'Y' -or $env:set_vscode_search_path -ieq 'YES');
$form.Controls.Add($s);
$ss=New-Object System.Windows.Forms.Label;
$ss.Text='Adds the parent folder of this environment to the search list and sets python.venvPath.';
$ss.Location=New-Object System.Drawing.Point(640,122);
$ss.Size=New-Object System.Drawing.Size(580,20);
$form.Controls.Add($ss);
$desktopHeader=New-Object System.Windows.Forms.Label;
$desktopHeader.Text='Desktop';
$desktopHeader.Location=New-Object System.Drawing.Point(805,186);
$desktopHeader.AutoSize=$true;
$form.Controls.Add($desktopHeader);
$startHeader=New-Object System.Windows.Forms.Label;
$startHeader.Text='Start Menu';
$startHeader.Location=New-Object System.Drawing.Point(895,186);
$startHeader.AutoSize=$true;
$form.Controls.Add($startHeader);
$shortcutBoxes=@();
$rowY=206;
foreach ($row in @(@('python','Python'),@('install','Package terminal'),@('terminal','Activated terminal'))) {
  $rowLabel=New-Object System.Windows.Forms.Label;
  $rowLabel.Text=$row[1];
  $rowLabel.Location=New-Object System.Drawing.Point(640,($rowY+3));
  $rowLabel.AutoSize=$true;
  $form.Controls.Add($rowLabel);
  foreach ($place in @(@('desktop',820),@('start',915))) {
    $shortcutBox=New-Object System.Windows.Forms.CheckBox;
    $shortcutBox.Name=$place[0] + '_' + $row[0];
    $shortcutBox.Location=New-Object System.Drawing.Point($place[1],$rowY);
    $shortcutBox.Size=New-Object System.Drawing.Size(24,24);
    $shortcutBox.Checked=([Environment]::GetEnvironmentVariable($shortcutBox.Name) -ieq 'Y');
    $form.Controls.Add($shortcutBox);
    $shortcutBoxes+=$shortcutBox;
  }
  $rowY+=24;
}
$p=New-Object System.Windows.Forms.CheckBox;
$p.Text='Make this environment the default Python in new terminals';
$p.Location=New-Object System.Drawing.Point(620,330);
$p.Size=New-Object System.Drawing.Size(600,24);
$p.Checked=($env:add_to_path -ieq 'Y' -or $env:add_to_path -ieq 'YES');
$form.Controls.Add($p);
$pathHelp=New-Object System.Windows.Forms.Label;
$pathHelp.Text='New terminals use this environment for python and pip. Open terminals are unaffected.';
$pathHelp.Location=New-Object System.Drawing.Point(640,356);
$pathHelp.Size=New-Object System.Drawing.Size(570,42);
$form.Controls.Add($pathHelp);
$ok=New-Object System.Windows.Forms.Button;
$ok.Text='Create / Update';
$ok.Size=New-Object System.Drawing.Size(110,23);
$ok.Location=New-Object System.Drawing.Point(1022,556);
$ok.DialogResult=[System.Windows.Forms.DialogResult]::OK;
$form.AcceptButton=$ok;
$form.Controls.Add($ok);
$cancel=New-Object System.Windows.Forms.Button;
$cancel.Text='Cancel';
$cancel.Location=New-Object System.Drawing.Point(1140,556);
$cancel.DialogResult=[System.Windows.Forms.DialogResult]::Cancel;
$form.CancelButton=$cancel;
$form.Controls.Add($cancel);

$result=$form.ShowDialog();
if ($result -eq [System.Windows.Forms.DialogResult]::OK) { $ep=$pathText.Text.Trim();
if (-not $ep) { $ep=$env:def_env_path };
$pv=$text.Text.Trim();
if (-not $pv) { $pv=$env:def_version };
$parts=@();
foreach ($b in $profileBoxes) { if ($b.Checked -and $b.Text -ne 'jupyter') { $parts+=$b.Tag.Text } };
$parts+=$extraText.Text;
$pk=(($parts -join ' ') -replace '\s+',' ').Trim();
Write-Output ('env_path=' + $ep);
Write-Output ('version=' + $pv);
Write-Output ('packages_was_set=Y');
Write-Output ('packages=' + $pk);
Write-Output ('jupyter_packages=' + (($jupyterField.Text -replace '\s+',' ').Trim()));
Write-Output ('register_kernel=' + $(if ($kernelBox.Checked) { 'Y' } else { 'N' }));
foreach ($shortcutBox in $shortcutBoxes) { Write-Output ($shortcutBox.Name + '=' + $(if ($shortcutBox.Checked) { 'Y' } else { 'N' })) };
Write-Output ('install_notebook_support=' + $(if ($j.Checked) { 'Y' } else { 'N' }));
Write-Output ('set_vscode_default=' + $(if ($v.Checked) { 'Y' } else { 'N' }));
Write-Output ('set_vscode_search_path=' + $(if ($s.Checked) { 'Y' } else { 'N' }));
Write-Output ('add_to_path=' + $(if ($p.Checked) { 'Y' } else { 'N' })) } else { Write-Output 'cancelled=1' }
Write-Output 'dialog_completed=1'
# END ENV SETTINGS

:: End the Python raw string that hides the batch code for Python. -> """

# ---------------------------------------------------------------------------
# Embedded helpers
# ---------------------------------------------------------------------------
# Runs only when the batch section calls `python -x "%~f0"`. Package installs
# live here because Python can pass version specifiers without shell quoting,
# and VS Code settings are edited here because they are comment-preserving JSONC.

replace_existing = True
import collections, hashlib, json, os, re, shlex, shutil, subprocess, sys, time
from pathlib import Path

RED = "\033[91m"
GREEN = "\033[92m"
RESET = "\033[0m"

action = os.environ.get("PY_ENV_HELPER_ACTION", "update_vscode_settings")
os.system("")  # Turns on ANSI colors in consoles that start with them disabled.

# These have no CPU code path unless a CPU extra is requested. jax, numba and
# similar packages are deliberately absent because they also run on the CPU.
NVIDIA_ONLY_PACKAGES = re.compile(
    r"^(cupy(-cuda\d+x)?|nvmath-python|pycuda|cudf|cuml|nvidia-.+|onnxruntime-gpu|tensorflow-gpu)$"
)
JsoncMember = collections.namedtuple("JsoncMember", "key key_start value_start value_end")
SETTINGS_BACKUPS_TO_KEEP = 10


def say(message, color=GREEN):
    # Flush so messages stay in order with the output of child installers.
    print(color + message + RESET, flush=True)


# ---- JSONC -----------------------------------------------------------------
# A real scanner instead of regexes: "//" inside a string, trailing comments and
# keys nested under "[python]" all need to be told apart to edit safely.


def jsonc_error(text, index, message):
    return ValueError("settings.json line {0}: {1}".format(text.count("\n", 0, index) + 1, message))


def skip_jsonc_trivia(text, index):
    """Return the next index that is not whitespace, a BOM or a comment."""
    while index < len(text):
        if text[index].isspace() or text[index] == "\ufeff":
            index += 1
        elif text.startswith("//", index):
            newline = text.find("\n", index)
            index = len(text) if newline == -1 else newline + 1
        elif text.startswith("/*", index):
            end = text.find("*/", index + 2)
            if end == -1:
                raise jsonc_error(text, index, "unterminated block comment")
            index = end + 2
        else:
            break
    return index


def skip_jsonc_string(text, index):
    start = index
    index += 1
    while index < len(text):
        if text[index] == "\\":
            index += 2
        elif text[index] == '"':
            return index + 1
        else:
            index += 1
    raise jsonc_error(text, start, "unterminated string")


def skip_jsonc_value(text, index):
    """Return the index just past the value at index, without validating its contents."""
    start = index
    if text[index:index + 1] == '"':
        return skip_jsonc_string(text, index)
    if text[index:index + 1] in ("[", "{"):
        depth = 0
        while True:
            index = skip_jsonc_trivia(text, index)
            if index >= len(text):
                raise jsonc_error(text, start, "unterminated array or object")
            if text[index] == '"':
                index = skip_jsonc_string(text, index)
                continue
            depth += {"[": 1, "{": 1, "]": -1, "}": -1}.get(text[index], 0)
            index += 1
            if depth == 0:
                return index
    while index < len(text) and not text[index].isspace() and text[index] not in ",]}/":
        index += 1
    if index == start:
        raise jsonc_error(text, start, "expected a value")
    return index


def parse_jsonc_root(text):
    """Return the root object's members and the index of its closing brace."""
    index = skip_jsonc_trivia(text, 0)
    if text[index:index + 1] != "{":
        raise jsonc_error(text, index, "the file must contain one object")
    index = skip_jsonc_trivia(text, index + 1)
    members = []
    while True:
        if index >= len(text):
            raise jsonc_error(text, index, "missing closing brace")
        if text[index] == "}":
            return members, index
        if text[index] != '"':
            raise jsonc_error(text, index, "expected a setting name")
        key_start = index
        index = skip_jsonc_string(text, index)
        key = json.loads(text[key_start:index])
        index = skip_jsonc_trivia(text, index)
        if text[index:index + 1] != ":":
            raise jsonc_error(text, index, "expected ':'")
        value_start = skip_jsonc_trivia(text, index + 1)
        value_end = skip_jsonc_value(text, value_start)
        members.append(JsoncMember(key, key_start, value_start, value_end))
        index = skip_jsonc_trivia(text, value_end)
        if text[index:index + 1] == ",":
            index = skip_jsonc_trivia(text, index + 1)
        elif text[index:index + 1] != "}":
            raise jsonc_error(text, index, "expected ',' or '}'")


def find_member(members, key):
    return next((member for member in members if member.key == key), None)


def array_item_spans(text, member):
    spans = []
    index = skip_jsonc_trivia(text, member.value_start + 1)
    while index < member.value_end - 1:
        end = skip_jsonc_value(text, index)
        spans.append((index, end))
        index = skip_jsonc_trivia(text, end)
        if text[index:index + 1] == ",":
            index = skip_jsonc_trivia(text, index + 1)
    return spans


def array_strings(text, member):
    if text[member.value_start] != "[":
        return []
    return [json.loads(text[start:end]) for start, end in array_item_spans(text, member) if text[start] == '"']


def line_indent(text, index, default):
    prefix = text[text.rfind("\n", 0, index) + 1:index]
    return prefix if not prefix.strip() else default


def insert_before_closer(text, last_item_end, close_index, item, item_indent):
    """Add item on its own line before a closing bracket, keeping earlier comments in place."""
    eol = "\r\n" if "\r\n" in text else "\n"
    closer_indent = line_indent(text, close_index, "")
    head = text[:close_index].rstrip()
    if last_item_end is not None:
        after_item = skip_jsonc_trivia(text, last_item_end)
        # The comma goes right after the value, because the text may end in a comment.
        if text[after_item:after_item + 1] != ",":
            head = head[:last_item_end] + "," + head[last_item_end:]
    return head + eol + item_indent + item + eol + closer_indent + text[close_index:]


def set_key_value(jsonc, key, value_json, replace_existing=True):
    members, close_index = parse_jsonc_root(jsonc)
    member = find_member(members, key)
    if member is not None:
        if not replace_existing:
            return jsonc
        return jsonc[:member.value_start] + value_json + jsonc[member.value_end:]
    last = members[-1] if members else None
    indent = line_indent(jsonc, last.key_start, "  ") if last else "  "
    item = "{0}: {1}".format(json.dumps(key), value_json)
    return insert_before_closer(jsonc, last.value_end if last else None, close_index, item, indent)


def same_settings_path(left, right):
    return os.path.normcase(os.path.normpath(left)) == os.path.normcase(os.path.normpath(right))


def add_path_to_array(jsonc, key, path):
    """Add path to a string array setting unless it is already listed."""
    members, _ = parse_jsonc_root(jsonc)
    member = find_member(members, key)
    if member is None or jsonc[member.value_start] != "[":
        return set_key_value(jsonc, key, json.dumps([path]))
    if any(same_settings_path(existing, path) for existing in array_strings(jsonc, member)):
        return jsonc
    spans = array_item_spans(jsonc, member)
    if not spans:
        return jsonc[:member.value_start] + json.dumps([path]) + jsonc[member.value_end:]
    last_start, last_end = spans[-1]
    item = json.dumps(path)
    if "\n" not in jsonc[member.value_start:member.value_end]:
        return jsonc[:last_end] + ", " + item + jsonc[last_end:]
    return insert_before_closer(jsonc, last_end, member.value_end - 1, item, line_indent(jsonc, last_start, "    "))


def remove_member(jsonc, members, member):
    start, end = member.key_start, member.value_end
    after_value = skip_jsonc_trivia(jsonc, end)
    if jsonc[after_value:after_value + 1] == ",":
        end = after_value + 1
    else:
        position = members.index(member)
        if position > 0:
            # Removing the last member would otherwise leave a dangling comma.
            comma = skip_jsonc_trivia(jsonc, members[position - 1].value_end)
            if jsonc[comma:comma + 1] == ",":
                jsonc = jsonc[:comma] + jsonc[comma + 1:]
                start -= 1
                end -= 1
    line_start = jsonc.rfind("\n", 0, start) + 1
    rest_of_line = re.compile(r"[ \t]*(?:\r?\n|\Z)").match(jsonc, end)
    if rest_of_line and not jsonc[line_start:start].strip():
        start, end = line_start, rest_of_line.end()
    return jsonc[:start] + jsonc[end:]


def absolute_venv_folder(folder):
    """Convert a python.venvFolders entry, which VS Code resolves against the home folder."""
    if "${" in folder:
        return folder
    expanded = os.path.expanduser(folder)
    return os.path.normpath(expanded if os.path.isabs(expanded) else os.path.join(os.path.expanduser("~"), expanded))


def migrate_array_setting(jsonc, old_key, new_key):
    """Move an obsolete folder list into the new setting, which needs absolute paths."""
    members, _ = parse_jsonc_root(jsonc)
    old_member = find_member(members, old_key)
    if old_member is None:
        return jsonc
    for folder in array_strings(jsonc, old_member):
        jsonc = add_path_to_array(jsonc, new_key, absolute_venv_folder(folder))
    members, _ = parse_jsonc_root(jsonc)
    return remove_member(jsonc, members, find_member(members, old_key))


def read_text(path):
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return "{\n}\n"
    # newline="" keeps the file's existing line endings.
    with open(path, "r", encoding="utf-8", newline="") as settings_file:
        return settings_file.read()


def write_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as settings_file:
        settings_file.write(text)


def set_venv_path(jsonc, path):
    """Set python.venvPath, the search setting used while Python Environments is turned off."""
    members, _ = parse_jsonc_root(jsonc)
    member = find_member(members, "python.venvPath")
    if member is not None and jsonc[member.value_start] == '"':
        previous = json.loads(jsonc[member.value_start:member.value_end])
        if previous and not same_settings_path(previous, path):
            say(" Replaced python.venvPath, which was: " + previous)
    return set_key_value(jsonc, "python.venvPath", json.dumps(path), replace_existing)


def backup_settings(path):
    """Save a dated copy; an error here stops the update before the file is touched."""
    source = Path(path)
    if not source.exists():
        return
    folder = source.parent / "settings_backups"
    folder.mkdir(exist_ok=True)
    backup = folder / "settings-{0}.json".format(time.strftime("%Y%m%d-%H%M%S"))
    shutil.copy2(source, backup)
    # The dated names sort oldest first.
    for old_backup in sorted(folder.glob("settings-*.json"))[:-SETTINGS_BACKUPS_TO_KEEP]:
        old_backup.unlink()
    say(" Backed up VS Code settings: " + str(backup))


def update_vscode_settings():
    interpreter = os.environ.get("PY_ENV_HELPER_VSCODE_PYTHON")
    search_path = os.environ.get("PY_ENV_HELPER_VSCODE_SEARCH_PATH")
    if not interpreter and not search_path:
        return
    path = os.path.join(os.environ["APPDATA"], "Code", "User", "settings.json")
    original = text = read_text(path)
    text = migrate_array_setting(text, "python.venvFolders", "python-envs.globalSearchPaths")
    if interpreter:
        text = set_key_value(text, "python.defaultInterpreterPath", json.dumps(interpreter), replace_existing)
    if search_path:
        text = add_path_to_array(text, "python-envs.globalSearchPaths", search_path)
        text = set_venv_path(text, search_path)
    if text == original:
        say(" --VS Code user settings were already up to date--")
        return
    backup_settings(path)
    write_text(path, text)
    say(" --Updated VS Code user settings: " + path + "--")


# ---- Packages --------------------------------------------------------------


def split_package_specs(text):
    # No escape character, so backslashes in local wheel paths survive.
    lexer = shlex.shlex(text, posix=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    lexer.escape = ""
    lexer.quotes = '"'
    return list(lexer)


def has_nvidia_gpu():
    try:
        result = subprocess.run(["nvidia-smi", "-L"], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0 and "GPU" in result.stdout


def needs_nvidia_gpu(spec):
    match = re.match(r"[A-Za-z0-9][A-Za-z0-9._-]*", spec)
    if not match or "[cpu" in spec.lower():
        return False
    return NVIDIA_ONLY_PACKAGES.match(re.sub(r"[-_.]+", "-", match.group(0)).lower()) is not None


def nvidia_cuda_major():
    try:
        output = subprocess.run(["nvidia-smi"], capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    # Newer drivers print "CUDA UMD Version" instead of "CUDA Version".
    match = re.search(r"CUDA(?: UMD)? Version:\s*(\d+)", output)
    return int(match.group(1)) if match else None


def choose_cupy_build(specs):
    """Point cupy-cudaNNx at the build this driver supports; newer drivers run CUDA 12 builds."""
    major = nvidia_cuda_major()
    if major is None or major < 11:
        return specs
    wanted = "cupy-cuda11x" if major == 11 else "cupy-cuda12x"
    chosen = []
    for spec in specs:
        replaced = re.sub(r"^cupy[-_.]cuda\d+x", wanted, spec, flags=re.I)
        if replaced.lower() != spec.lower():
            say("Driver supports CUDA {0}, so using {1} instead of {2}.".format(major, replaced, spec))
        chosen.append(replaced)
    return chosen


def select_packages_for_hardware(specs):
    gpu_only = [spec for spec in specs if needs_nvidia_gpu(spec)]
    if not gpu_only:
        return specs
    if has_nvidia_gpu():
        return choose_cupy_build(specs)
    say("No NVIDIA GPU found, so these packages are not needed: " + " ".join(gpu_only))
    return [spec for spec in specs if spec not in gpu_only]


def run_install(specs, use_uv):
    exe = sys.executable
    command = [exe, "-m", "uv", "pip", "install", "--python", exe] if use_uv else [exe, "-m", "pip", "install"]
    return subprocess.call(command + specs) == 0


def install_one_package(spec, use_uv):
    say("=" * 60)
    say("Installing " + spec + " ...")
    if run_install([spec], use_uv):
        return True
    if use_uv:
        say(" [Warning] uv failed to install " + spec + ". Trying pip fallback...", RED)
        return run_install([spec], False)
    return False


def format_python_minors(minors):
    if len(minors) > 1 and minors == list(range(minors[0], minors[-1] + 1)):
        return "3.{0}-3.{1}".format(minors[0], minors[-1])
    return ", ".join("3.{0}".format(minor) for minor in minors)


def classify_failure(spec, use_uv):
    """Return a category and a note for a failed package by reading uv's explanation.

    Unknown wording stays in the plain "failed" category, so a future uv message
    cannot mislabel a package.
    """
    if not use_uv:
        return "failed", ""
    # Wheels only: a package with source code but no wheels would otherwise report a build error.
    command = [sys.executable, "-m", "uv", "pip", "install", "--python", sys.executable, "--dry-run", "--only-binary", ":all:", spec]
    result = subprocess.run(command, capture_output=True, text=True)
    output = result.stdout + result.stderr
    if "was not found in the package registry" in output:
        return "missing", ""
    if "matching Python ABI tag" in output:
        tags = output[output.index("matching Python ABI tag"):]
        hint_start = tags.find("following Python ABI tags")
        minors = sorted({int(minor) for minor in re.findall(r"`cp3(\d+)`", tags[hint_start:])}) if hint_start != -1 else []
        return "python", " (has {0})".format(format_python_minors(minors)) if minors else ""
    requirement = re.search(r"current Python version \([^)]*\) does not satisfy Python(\S+)", output)
    if requirement:
        return "python", " (needs Python {0})".format(requirement.group(1))
    return "failed", ""


def report_failures(specs, use_uv):
    """Show failures grouped by cause and save them for the end-of-setup summary."""
    groups = {"python": [], "missing": [], "failed": []}
    for spec in specs:
        category, note = classify_failure(spec, use_uv)
        groups[category].append(spec + note)
    python_version = "{0}.{1}".format(*sys.version_info[:2])
    lines = []
    if groups["python"]:
        lines.append("Not available for Python {0}: {1}".format(python_version, ", ".join(groups["python"])))
    if groups["missing"]:
        lines.append("Not found on PyPI: " + ", ".join(groups["missing"]))
    if groups["failed"]:
        lines.append("Failed: " + ", ".join(groups["failed"]))
    for line in lines:
        say(line, RED)
    # Appended because setup can install several package lists.
    with open(os.environ["PY_ENV_HELPER_RESULT_FILE"], "a", encoding="utf-8") as report:
        report.writelines(RED + line + RESET + "\n" for line in lines)


def install_packages():
    package_list = os.environ.get(os.environ.get("PY_ENV_HELPER_PACKAGE_VAR", "packages"), "")
    specs = select_packages_for_hardware(split_package_specs(package_list))
    failed = []
    if specs:
        probe = [sys.executable, "-m", "uv", "--version"]
        use_uv = subprocess.call(probe, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0
        # Resolving everything at once keeps one package from changing the
        # dependencies an earlier one was installed with.
        if run_install(specs, use_uv):
            say("Installed packages: " + " ".join(specs))
        else:
            say(" [Warning] Installing all packages together failed. Trying them one by one.", RED)
            failed = [spec for spec in specs if not install_one_package(spec, use_uv)]
            say("=" * 60)
            installed = [spec for spec in specs if spec not in failed]
            if installed:
                say("Installed packages: " + " ".join(installed))
            if failed:
                report_failures(failed, use_uv)
                say(" [Warning] One or more packages failed to install. Continuing with remaining setup steps.", RED)
    # Exit code 3 tells the batch code that the failures are already in the report.
    sys.exit(3 if failed else 0)


def write_package_terminal():
    """Copy the terminal program from the end of this file into the environment."""
    source = Path(__file__).read_text(encoding="ascii")
    match = re.search(r"^# BEGIN PACKAGE TERMINAL\n(.*?)^# END PACKAGE TERMINAL", source, re.M | re.S)
    if match is None:
        raise ValueError("package terminal section is missing")
    (Path(os.environ["env_path"]) / "package_terminal.py").write_text(match.group(1), encoding="utf-8")


def write_lock_file():
    exe = sys.executable
    lock_path = Path(os.environ["env_path"]) / "requirements.lock.txt"
    for command in ([exe, "-m", "uv", "pip", "freeze", "--python", exe], [exe, "-m", "pip", "freeze"]):
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode == 0:
            lock_path.write_text(result.stdout, encoding="utf-8")
            say("Saved installed versions: " + str(lock_path))
            return
    raise RuntimeError(result.stderr.strip() or "freeze failed")


# ---- Jupyter ---------------------------------------------------------------


def kernel_name_is_free(name):
    """Return whether name is unused, stale or already owned by this environment."""
    from jupyter_client.kernelspec import KernelSpecManager, NoSuchKernel

    try:
        spec = KernelSpecManager().get_kernel_spec(name)
    except NoSuchKernel:
        return True
    owner = spec.argv[0] if spec.argv else ""
    if not os.path.exists(owner):
        return True
    return os.path.normcase(os.path.realpath(owner)) == os.path.normcase(os.path.realpath(sys.executable))


def register_jupyter_kernel():
    env_name = os.environ["env_name"]
    env_path = os.environ["env_path"]
    name, display_name = env_name, env_name
    if not kernel_name_is_free(name):
        # Derived from the path, so re-running setup finds this same kernel again.
        fingerprint = hashlib.sha1(env_path.lower().encode("utf-8")).hexdigest()[:8]
        name = "{0}-{1}".format(env_name, fingerprint)
        display_name = "{0} ({1})".format(env_name, Path(env_path).parent.name or env_path)
        say("Kernel name " + env_name + " belongs to another environment. Using " + name + ".")
    command = [sys.executable, "-m", "ipykernel", "install", "--user", "--name", name, "--display-name", display_name]
    subprocess.run(command, stdout=subprocess.DEVNULL, check=True)


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
        say(" --Kernel started and completed the Jupyter handshake--")
    finally:
        if client is not None:
            client.stop_channels()
        if manager.has_kernel:
            manager.shutdown_kernel(now=True)


ACTIONS = {
    "install_packages": install_packages,
    "register_jupyter_kernel": register_jupyter_kernel,
    "update_vscode_settings": update_vscode_settings,
    "validate_jupyter_kernel": validate_jupyter_kernel,
    "write_lock_file": write_lock_file,
    "write_package_terminal": write_package_terminal,
}

if action not in ACTIONS:
    say(" [Error] Unknown embedded Python action: " + action, RED)
    sys.exit(2)

try:
    ACTIONS[action]()
except Exception as exc:
    # Setup continues after a failed optional step, so report instead of a traceback.
    say(" [Error] {0} failed: {1}: {2}".format(action, type(exc).__name__, exc), RED)
    sys.exit(1)

sys.exit(0)


# The section below is never run here. write_package_terminal copies it into
# each environment as package_terminal.py.
# BEGIN PACKAGE TERMINAL
"""Interactive package manager for the virtual environment in this folder."""
import ctypes
import json
import os
import platform
import re
import shlex
import subprocess
import sys
from pathlib import Path

ENV_DIR = Path(__file__).resolve().parent
PYTHON = sys.executable
LOCK_FILE = ENV_DIR / "requirements.lock.txt"
GREEN = "\033[92m"
RED = "\033[91m"
RESET = "\033[0m"

# In bare input these mean a command was intended, not a package. Installing
# them anyway could pull an unrelated PyPI project with that name.
COMMAND_WORDS = {
    "add", "conda", "freeze", "git", "install", "list", "mamba", "npm", "pip", "pip3", "pipenv", "pipx",
    "poetry", "py", "python", "python3", "remove", "run", "show", "sync", "uninstall", "update", "upgrade", "uv",
}
HELP = """
 numpy pandas "scipy<2"   install packages (install ... also works)
 uninstall NAME           remove packages
 update NAME              update packages
 update all               update everything in this environment
 list                     show installed packages
 outdated                 show packages with newer versions
 show NAME                show details about a package
 help                     show this list
 exit                     close this window

 pip, python -m pip and uv pip prefixes are accepted and always use this environment.
"""


def say(message, color=GREEN):
    print(color + message + RESET, flush=True)


def split_input(line):
    # No escape character, so backslashes in local wheel paths survive.
    lexer = shlex.shlex(line, posix=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    lexer.escape = ""
    lexer.quotes = '"'
    return list(lexer)


def strip_tool_prefix(tokens):
    """Remove words like `python -m pip`, leaving the action and its arguments."""
    rest = list(tokens)
    if len(rest) >= 3 and rest[0].lower() in ("python", "python3", "py") and rest[1] == "-m":
        rest = rest[2:]
    if rest and rest[0].lower() == "uv":
        rest = rest[1:]
    if rest and rest[0].lower() in ("pip", "pip3"):
        rest = rest[1:]
    return rest, len(rest) != len(tokens)


def package_name(spec):
    match = re.match(r"[A-Za-z0-9][A-Za-z0-9._-]*", spec)
    return re.sub(r"[-_.]+", "-", match.group(0)).lower() if match else ""


def uv_available():
    probe = [PYTHON, "-m", "uv", "--version"]
    return subprocess.call(probe, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0


def tool_command(verb, specs=()):
    """Return the command and whether it is uv; pip changes uv so uv never replaces itself."""
    if uv_available() and not any(package_name(spec) == "uv" for spec in specs):
        return [PYTHON, "-m", "uv", "pip", verb, "--python", PYTHON], True
    return [PYTHON, "-m", "pip", verb], False


def refresh_lock_file():
    command, _ = tool_command("freeze")
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode == 0:
        LOCK_FILE.write_text(result.stdout, encoding="utf-8")
    else:
        say("Could not update requirements.lock.txt.", RED)


def version_key(version):
    return [int(part) for part in re.findall(r"\d+", version)]


def find_downgrades(preview):
    """Return (name, old, new) for packages a uv dry run would move to an older version."""
    removed, added = {}, {}
    for sign, name, version in re.findall(r"^\s*([-+])\s+([^\s=]+)==(\S+)", preview, re.M):
        (removed if sign == "-" else added)[name] = version
    return [
        (name, removed[name], added[name])
        for name in sorted(removed.keys() & added.keys())
        if version_key(added[name]) < version_key(removed[name])
    ]


def confirm(question):
    try:
        return input(question + " [y/N] ").strip().lower() in ("y", "yes")
    except EOFError:
        return False


def install(args, upgrade=False):
    if not any(not arg.startswith("-") for arg in args):
        say("Add one or more package names.", RED)
        return
    command, is_uv = tool_command("install", args)
    if upgrade:
        command.append("--upgrade")
    if is_uv:
        preview = subprocess.run(command + ["--dry-run"] + args, capture_output=True, text=True)
        output = preview.stdout + preview.stderr
        if preview.returncode != 0:
            print(output)
            say("Nothing was changed.", RED)
            return
        downgrades = find_downgrades(output)
        if downgrades:
            say("This would downgrade:", RED)
            for name, old, new in downgrades:
                say("  {0}: {1} -> {2}".format(name, old, new), RED)
            if not confirm("Continue?"):
                say("Nothing was changed.")
                return
    if subprocess.call(command + args) == 0:
        refresh_lock_file()
    else:
        say("Install failed.", RED)


def uninstall(args):
    if not args:
        say("Add one or more package names.", RED)
        return
    command, is_uv = tool_command("uninstall", args)
    if subprocess.call(command + ([] if is_uv else ["-y"]) + args) == 0:
        refresh_lock_file()
    else:
        say("Uninstall failed.", RED)


def installed_names():
    command, _ = tool_command("list")
    packages = json.loads(subprocess.run(command + ["--format=json"], capture_output=True, text=True, check=True).stdout)
    return [package["name"] for package in packages if not package.get("editable_project_location")]


def update(args):
    if not args:
        say("Add package names, or type: update all", RED)
    elif [arg.lower() for arg in args] != ["all"]:
        install(args, upgrade=True)
    else:
        names = installed_names()
        others = [name for name in names if package_name(name) != "uv"]
        if others:
            install(others, upgrade=True)
        if len(others) != len(names):
            install(["uv"], upgrade=True)


def run_read_only(verb, args):
    command, _ = tool_command(verb)
    subprocess.call(command + args)


def handle(line):
    """Run one line of input and return False when the terminal should close."""
    tokens = split_input(line)
    if not tokens:
        return True
    rest, had_prefix = strip_tool_prefix(tokens)
    if not rest:
        say("Add a command or package names. Type help for options.", RED)
        return True
    verb, args = rest[0].lower(), rest[1:]
    if verb in ("exit", "quit") and not had_prefix and not args:
        return False
    if verb == "help" and not args:
        print(HELP)
    elif verb == "install":
        install(args)
    elif verb in ("uninstall", "remove"):
        uninstall(args)
    elif verb in ("update", "upgrade"):
        update(args)
    elif verb == "outdated":
        run_read_only("list", ["--outdated"] + args)
    elif verb in ("list", "show", "freeze"):
        run_read_only(verb, args)
    elif had_prefix:
        say("Not supported here: " + verb + ". Type help for options.", RED)
    else:
        commands = [token for token in tokens if token.lower() in COMMAND_WORDS]
        if commands:
            say("Looks like a command, so nothing was installed: " + " ".join(commands), RED)
            say("To install a package with that name, type: install " + commands[0], RED)
        else:
            install(tokens)
    return True


def use_pip_index_for_uv():
    """Give uv the index configured for pip; looked up here so no password is saved to a file."""
    if os.environ.get("UV_DEFAULT_INDEX") or os.environ.get("UV_INDEX_URL"):
        return
    index = os.environ.get("PIP_INDEX_URL")
    if not index:
        result = subprocess.run([PYTHON, "-m", "pip", "config", "list"], capture_output=True, text=True)
        settings = dict(re.findall(r"^(global|install)\.index[-_]url='(.*)'$", result.stdout, re.M))
        index = settings.get("install") or settings.get("global")
    if index:
        os.environ["UV_DEFAULT_INDEX"] = index


def main():
    os.system("")  # Turns on ANSI colors in consoles that start with them disabled.
    os.environ.setdefault("UV_CACHE_DIR", str(ENV_DIR.parent / ".uv-cache"))
    use_pip_index_for_uv()
    ctypes.windll.kernel32.SetConsoleTitleW("Packages - {0} - Python {1}".format(ENV_DIR.name, platform.python_version()))
    say("Manage packages in python environment " + ENV_DIR.name)
    print(HELP)
    while True:
        try:
            line = input("Package(s) or command: ")
        except (EOFError, KeyboardInterrupt):
            return
        try:
            if not handle(line):
                return
        except ValueError as exc:
            say("Could not read that input: {0}".format(exc), RED)
        except KeyboardInterrupt:
            say("Cancelled.", RED)


if __name__ == "__main__":
    main()
# END PACKAGE TERMINAL

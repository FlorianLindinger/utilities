:: Description:
:: Installs portable full-version (aka. not embeddable-version) Python (version <py_ver>) at path "<target_dir>\py_dist" with control what subparts get installed (see Usage below). Should work for Python version 3.6-3.14 and likely later versions. Probably needs user to be admin to install.
::
:: Usage:
:: create_portable_python.bat <py_ver> "<target_dir>" <install_tkinter> <install_tests> <install_tools> <install_docs>
:: 
:: Args (all optional):
:: <py_ver>: It picks the most modern python version by default the matches None/x/x.y/x.y.z defined python version.
:: <target_dir>: If not defined it generates in the file folder. It always names the generated python folder py_dist in the <target_dir>.
:: <install_tkinter>/<install_tests>/<install_tools>/<install_docs>: Can be 1/0 for install/no-install of that python sub components. Default 1/1/1/0
::
:: Note:
:: For python 3.11+ the download of for example "python-3.11.0-amd64.zip" is an alternative to the .msi files download from the amd64 folder. Downside is no control over what gets downloaded and installed.

:: =======================
:: ==== Program Start ====
:: =======================

:: dont print commands & make variables local & enable needed features
@echo off & setlocal EnableExtensions EnableDelayedExpansion

:: process args
set "PY_VER=%~1"
set "TARGET_DIR=%~2"
set "install_tkinter=%~3"
set "install_tests=%~4"
set "install_tools=%~5"
set "install_docs=%~6"

:: set default values
if "%install_tkinter%"=="" (
  set "install_tkinter=1"
)
if "%install_tests%"=="" (
  set "install_tests=1"
)
if "%install_tools%"=="" (
  set "install_tools=1"
)
if "%install_docs%"=="" (
  set "install_docs=0"
)

:: exclude not needed files from download:
REM path.msi/appendpath.msi excluded since it is only needed to update global Windows variable PATH which we do not want for portable install:
REM pip.msi excluded from install since it is generally not meant to be installed:
REM launcher.msi excluded from install since a global python launcher is unwanted for portable install:
set "EXCLUDE_FILES=path|appendpath|pip|launcher"
REM tcltk.msi (~11 MB):
if "%install_tkinter%"=="0" ( set "EXCLUDE_FILES=%EXCLUDE_FILES%|tcltk" )
REM test.msi (~31 MB):
if "%install_tests%"=="0" ( set "EXCLUDE_FILES=%EXCLUDE_FILES%|test" ) 
REM tools.msi (~1 MB, and some installation time):
if "%install_tools%"=="0" ( set "EXCLUDE_FILES=%EXCLUDE_FILES%|tools" )
REM doc.msi(~61 MB):
if "%install_docs%"=="0" ( set "EXCLUDE_FILES=%EXCLUDE_FILES%|doc" )

:: make path absolute
CALL :set_abs_path "%TARGET_DIR%" "TARGET_DIR"

:: carefull with DOWNLOAD_FOLDER/PYTHON_FOLDER because it can/will be deleted
:: add "py_dist" for delete safety
set "PYTHON_FOLDER=%TARGET_DIR%\py_dist"
set "DOWNLOAD_FOLDER=%temp%\tmp_python_installation_files"

:: find available python full version compatible with specified input and installation method via amd64 folders and .msi files
set "FULL_VER="
for /f "usebackq delims=" %%A in (`
  powershell -NoLogo -NoProfile -Command ^
    "$arg = '%PY_VER%';" ^
    "switch -Regex ($arg) {" ^
    "  '^\s*$'              { $pat = '^\d+\.\d+\.\d+/$'; break }" ^
    "  '^\d+$'              { $pat = '^'+[regex]::Escape($arg)+'\.\d+\.\d+/$'; break }" ^
    "  '^\d+\.\d+$'         { $pat = '^'+[regex]::Escape($arg)+'\.\d+/$'; break }" ^
    "  '^\d+\.\d+\.\d+$'    { $pat = '^'+[regex]::Escape($arg)+'/$'; break }" ^
    "  default              { $pat = '^$' }" ^
    "}" ^
    "$links = (Invoke-WebRequest 'https://www.python.org/ftp/python/' -UseBasicParsing).Links;" ^
    "$vers = $links | Where-Object href -match $pat | ForEach-Object href | ForEach-Object { $_.TrimEnd('/') } | Sort-Object {[version]$_} -Descending;" ^
    "foreach ($v in $vers) {" ^
    "  $url = 'https://www.python.org/ftp/python/' + $v + '/amd64/';" ^
    "  try {" ^
    "    $r = Invoke-WebRequest -UseBasicParsing -Uri $url -ErrorAction Stop;" ^
    "    if ($r.StatusCode -eq 200) { Write-Output $v; exit 0 }" ^
    "  } catch {}" ^
    "}" ^
    "exit 1"
`) do set "FULL_VER=%%A"
:: abort if fail
if not defined FULL_VER (
    echo [ERROR] Could not determine latest implemented version for specified version (%PY_VER%^) or download method not implemented for this version or no internet connection. This code needs "https://www.python.org/ftp/python/{full-python-version}/amd64/" to exist. Aborting. Press any key to exit.
    PAUSE > NUL
    exit /b 1
)
:: print success
echo Found (msi-install-available) Python version %FULL_VER%

:: define URL based on full version
set "URL=https://www.python.org/ftp/python/%FULL_VER%/amd64/"
ECHO Download URL: %URL%

:: === [START] delete old python folder ==================
:: Skip if folder doesn't exist
if not exist "%PYTHON_FOLDER%\" (
    goto :skip_delete_old 
)
REM Check for Python folder markers
if not exist "%PYTHON_FOLDER%\python.exe" (
    echo [Error] Folder "%PYTHON_FOLDER%" does not appear to be a Python folder. -^> Delete manually after confirming it is a Python folder and restart. Press any key to exit.
    pause > nul
    exit /b 2
)
REM delete folder
rmdir /s /q "%PYTHON_FOLDER%"
if exist "%PYTHON_FOLDER%\" (
    echo [Error] Failed to delete "%PYTHON_FOLDER%". -^> Delete manually after confirming it is a Python folder and restart. Press any key to exit.
    pause > nul
    exit /b 3
) else (
    echo Deleted old python folder.
)
:skip_delete_old
:: === [END] delete old python folder ==================

:: (re)create folders
mkdir "%PYTHON_FOLDER%" > NUL 2>&1
mkdir "%DOWNLOAD_FOLDER%" > NUL 2>&1

:: add .gitignore to folder to prevent git from syncing python distribution
>> "%PYTHON_FOLDER%\.gitignore" (
  echo # Auto added to prevent synchronization of python distribution in git by blacklisting everything with wildcard "*"
  echo *
)

:: download files
powershell -NoLogo -NoProfile -Command ^
  "$base='%URL%';" ^
  "$out='%DOWNLOAD_FOLDER%';" ^
  "$links=(Invoke-WebRequest -Uri $base -UseBasicParsing).Links | Where-Object href -ne $null | ForEach-Object { $_.href } |" ^
  " Where-Object {$_ -notmatch '/$'} |" ^
  " ForEach-Object { if($_ -match '^https?://') {$_} else {$base + $_} } |" ^
  " Where-Object { -not ( ([IO.Path]::GetFileNameWithoutExtension( ([IO.Path]::GetFileNameWithoutExtension($_)) )) -match '(_d|_pdb)$' ) } |" ^
  " Where-Object { $_ -match '\.msi$' } |" ^
  " Where-Object { ([IO.Path]::GetFileName($_)) -notmatch '^(%EXCLUDE_FILES%)\.msi$' };" ^
  "foreach($l in $links){" ^
  "  $n=[IO.Path]::GetFileName($l); $p=Join-Path $out $n;" ^
  "  Write-Host 'Downloading ' $n;" ^
  "  Try{Invoke-WebRequest -Uri $l -OutFile $p -UseBasicParsing}catch{Write-Error $l}" ^
  "}"

:: install python files
pushd "%DOWNLOAD_FOLDER%"
for %%A in (*.msi) do (
  echo Installing %%~nxA
  REM /a option needed to not install paths globally
  msiexec /a "%%~fA" TARGETDIR="%PYTHON_FOLDER%" /qn
  if "%%~nxA"=="test.msi" (
    REM disable line in %PYTHON_FOLDER%\Lib\test\.ruff.toml that causes Ruff error message (line: "extend = "../../.ruff.toml"  # Inherit the project-wide settings"^):
    if exist "%PYTHON_FOLDER%\Lib\test\.ruff.toml" (
      powershell -NoLogo -NoProfile -Command ^
      "(Get-Content '%PYTHON_FOLDER%\Lib\test\.ruff.toml') | ForEach-Object { if ($_ -match '^\s*extend\s*=') { '# ' + $_ } else { $_ } } | Set-Content '%PYTHON_FOLDER%\Lib\test\.ruff.toml'"
    )
  )
  del "%PYTHON_FOLDER%\%%~nxA" > nul
)
popd

:: delete downloads afterwards
if not "%DOWNLOAD_FOLDER%"=="" if exist "%DOWNLOAD_FOLDER%\" (
    rmdir /s /q "%DOWNLOAD_FOLDER%"
)

:: verify installation via existing python.exe
if not exist "%PYTHON_FOLDER%\python.exe" (
  echo [Error] Python installation failed (see above^). Aborting. Press any key to exit.
  PAUSE > NUL
  EXIT /B 4
)

:: verify functioning python.exe
CALL "%PYTHON_FOLDER%\python.exe" -V > Nul || (
  echo [Error] Python not runnable (see above^). Aborting. Press any key to exit.
  PAUSE > NUL
  EXIT /B 5
)

:: add a settings file for pip to avoid warning for portable python not being in a folder mentioned in system variable PATH
> "%PYTHON_FOLDER%\pip.ini" (
  echo [global]
  echo no-warn-script-location = false
)

:: install pip
"%PYTHON_FOLDER%\python.exe" -m ensurepip --upgrade > nul 2>&1
if errorlevel 1 (
  echo [Error] Python not sucessfully installed (see above^). Aborting. Press any key to exit.
  PAUSE > NUL
  EXIT /B 6
)

:: upgrade pip
REM "--ignore-installed" apparently needed for older python versions because too long paths in cache
REM "--progress-bar off" apparently needed for older python versions
"%PYTHON_FOLDER%\python.exe" -m pip install --upgrade pip --ignore-installed --progress-bar off > nul 2>&1
if errorlevel 1 (
  REM retry with no "--progress-bar off" for pip versions before implemented
  "%PYTHON_FOLDER%\python.exe" -m pip install --upgrade pip --ignore-installed > nul
  if errorlevel 1 (
    echo [Error] Python's pip not sucessfully installed (see above^). Aborting. Press any key to exit.
    PAUSE > NUL
    EXIT /B 7
  )
)
:: upgrade pip again because older pips don't manage to fully upgrade in one step
"%PYTHON_FOLDER%\python.exe" -m pip install --upgrade pip > nul
  if errorlevel 1 (
    echo [Error] Python's pip not sucessfully installed (see above^). Aborting. Press any key to exit.
    PAUSE > NUL
    EXIT /B 8
)

:: print success and exit
echo.
echo Sucessfully created portable Python (%FULL_VER%) at "%PYTHON_FOLDER%".
exit /b 0

:: ====================
:: ==== Functions: ====
:: ====================

::::::::::::::::::::::::::::::::::::::::::::::::
:: function that converts relative (to current working directory) path {arg1} to absolute and sets it to variable {arg2}. Works for empty path {arg1} which then sets the current working directory to variable {arg2}. Raises error if {arg2} is missing:
:: Usage:
::    call :set_abs_path "%some_path%" "some_path"
::::::::::::::::::::::::::::::::::::::::::::::::
:set_abs_path
    if "%~2"=="" (
        echo [Error] Second argument is missing for :set_abs_path function in "%~f0". (First argument was "%~1"^). 
        echo Aborting. Press any key to exit.
        pause > nul
        exit /b 1
    )
    if "%~1"=="" (
        set "%~2=%CD%"
    ) else (
	    set "%~2=%~f1"
    )
goto :EOF
:: =================================================

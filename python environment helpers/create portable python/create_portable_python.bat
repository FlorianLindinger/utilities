:: Usage:
:: create_portable_python.bat <py_ver> "<target_dir>" <install_tkinter> <install_tests> <install_docs>
:: 
:: Args (all optional):
:: <py_ver>: It picks the most modern python version by default the matches None/x/x.y/x.y.z defined python version.
:: <target_dir>: If not defined it generates in the file folder. It always names the generated python folder py_dist in the <target_dir>.
:: <install_tkinter>/<install_tests>/<install_docs>: Can be 1/0 for install/no-install of that python sub components. Default 1/1/0

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
set "install_docs=%~5"

:: set default values
if "%install_tkinter%"=="" (
  set "install_tkinter=1"
)
if "%install_tests%"=="" (
  set "install_tests=1"
)
if "%install_docs%"=="" (
  set "install_docs=0"
)

:: exclude not needed files from install:
REM path.msi excluded since it is only needed to update global path which we do not want for portable install:
REM pip.msi excluded from install since it is not meant to be installed
set "exclude_install=path.msi pip.msi" 
REM tcltk.msi (~11 MB):
if "%install_tkinter%"=="0" ( set "exclude_install=%exclude_install% tcltk.msi" )
REM test.msi (~31 MB):
if "%install_tests%"=="0" ( set "exclude_install=%exclude_install% test.msi" ) 
REM doc.msi(~61 MB):
if "%install_docs%"=="0" ( set "exclude_install=%exclude_install% doc.msi" )

:: make path absolute
CALL :make_absolute_path_if_relative "%TARGET_DIR%"
SET "TARGET_DIR=%OUTPUT%"

:: carefull with DOWNLOAD_FOLDER/PYTHON_FOLDER because it can/will be deleted
:: add "py_dist" for delete safety
set "PYTHON_FOLDER=%TARGET_DIR%\py_dist"
set "DOWNLOAD_FOLDER=%PYTHON_FOLDER%\tmp"

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
mkdir "%PYTHON_FOLDER%" > NUL
mkdir "%DOWNLOAD_FOLDER%" > NUL

:: add .gitignore to folder to prevent git from syncing python distribution
>> "%PYTHON_FOLDER%\.gitignore" (
  echo # Auto added to prevent synchronization of python distribution in git by blacklisting everything with wildcard "*"
  echo *
)

:: download files
echo Downloading... (may take a little)
powershell -NoLogo -NoProfile -Command ^
  "$base='%URL%';" ^
  "$out='%DOWNLOAD_FOLDER%';" ^
  "$links=(Invoke-WebRequest -Uri $base).Links | Where-Object href -ne $null | ForEach-Object { $_.href } |" ^
  " Where-Object {$_ -notmatch '/$'} |" ^
  " ForEach-Object { if($_ -match '^https?://') {$_} else {$base + $_} } |" ^
  " Where-Object { -not ( ([IO.Path]::GetFileNameWithoutExtension( ([IO.Path]::GetFileNameWithoutExtension($_)) )) -match '(_d|_pdb)$' ) };" ^
  "foreach($l in $links){$n=[IO.Path]::GetFileName($l);$p=Join-Path $out $n;Try{Invoke-WebRequest -Uri $l -OutFile $p -UseBasicParsing}catch{Write-Error $l}}"

:: install python files that are not in %exclude_install% (via .msi files)
:: (download folder DOWNLOAD_FOLDER can't be install folder PYTHON_FOLDER because problems with msiexec)
pushd "%DOWNLOAD_FOLDER%"
for %%A in (*.msi) do (
  set "skip="
  for %%X in (%exclude_install%) do (
    echo %%~nxA | findstr /i /c:"%%~X" >nul && set "skip=1"
  )
  if not defined skip (
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
  ) else (
    echo Excluding %%~nxA
  )
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

:: update pip
"%PYTHON_FOLDER%\python.exe" -m pip install --upgrade pip > nul
if errorlevel 1 (
  echo [Error] Python not sucessfully installed (see above^). Aborting. Press any key to exit.
  PAUSE > NUL
  EXIT /B 7
)

:: print success and exit
echo.
echo Sucessfully created portable Python (%FULL_VER%) at "%PYTHON_FOLDER%".
exit /b 0

:: ====================
:: ==== Functions: ====
:: ====================

:: =================================================
:: function that makes relative path (relative to current working directory) to :: absolute if not already. Works for empty path (relative) path:
:: Usage:
::    call :make_absolute_path_if_relative "%some_path%"
::    set "abs_path=%output%"
:: =================================================
:make_absolute_path_if_relative
    if "%~1"=="" (
        set "OUTPUT=%CD%"
    ) else (
	    set "OUTPUT=%~f1"
    )
goto :EOF
:: =================================================

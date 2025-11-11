:: check if fully portable

@echo off
setlocal EnableExtensions EnableDelayedExpansion

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
if "%install_tkinter%"=="0" ( set "exclude_install=%exclude_install% tcltk.msi" ) rem (~11 MB)
if "%install_tests%"=="0" ( set "exclude_install=%exclude_install% test.msi" ) rem (~31 MB)
if "%install_docs%"=="0" ( set "exclude_install=%exclude_install% doc.msi" ) rem (~61 MB)

:: make path absolute
CALL :make_absolute_path_if_relative "%TARGET_DIR%"
SET "TARGET_DIR=%OUTPUT%"

:: add "portable_python" for delete safety
set "PYTHON_FOLDER=%TARGET_DIR%\portable_python"
set "TMP_DIR=%TARGET_DIR%\tmp"

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
    echo: [ERROR] Could not determine latest implemented version for specified version (%PY_VER%^) or download method not implemented for this version or no internet connection. This code needs "https://www.python.org/ftp/python/{full-python-version}/amd64/" to exist. Aborting. Press any key to exit.
    PAUSE > NUL
    exit /b 1
)
:: print success
echo: Found (msi-install available) Python version %FULL_VER%

:: define URL based on full version
set "URL=https://www.python.org/ftp/python/%FULL_VER%/amd64/"
ECHO: Download URL: %URL%

:: (re)create tmp file
rmdir /s /q "%TMP_DIR%" > NUL 2>&1
mkdir "%TMP_DIR%"

:: downlaod files
powershell -NoLogo -NoProfile -Command ^
  "$base='%URL%';" ^
  "$out='%TMP_DIR%';" ^
  "$links=(Invoke-WebRequest -Uri $base).Links | Where-Object href -ne $null | ForEach-Object { $_.href } |" ^
  " Where-Object {$_ -notmatch '/$'} |" ^
  " ForEach-Object { if($_ -match '^https?://') {$_} else {$base + $_} } |" ^
  " Where-Object { -not ( ([IO.Path]::GetFileNameWithoutExtension( ([IO.Path]::GetFileNameWithoutExtension($_)) )) -match '(_d|_pdb)$' ) };" ^
  "foreach($l in $links){$n=[IO.Path]::GetFileName($l);$p=Join-Path $out $n;Try{Invoke-WebRequest -Uri $l -OutFile $p -UseBasicParsing}catch{Write-Error $l}}"

:: === [start] delete old python folder ==================

:: Skip if folder doesn't exist
if not exist "%PYTHON_FOLDER%\" (
    goto :skip_delete_old 
)

:: Check for Python folder markers
if not exist "%PYTHON_FOLDER%\python.exe" (
    echo [Error] folder "%PYTHON_FOLDER%" does not appear to be a Python folder. -^> Delete manually after confirming. ^| Aborting. Press any key to exit.
    pause > nul
    exit /b 1
)

:: delete folder
rmdir /s /q "%PYTHON_FOLDER%"
if exist "%PYTHON_FOLDER%\" (
    echo [Error] Failed to delete "%PYTHON_FOLDER%". -^> Delete manually after confirming. ^| Aborting. Press any key to exit.
    pause > nul
    exit /b 1
) else (
    echo Deleted old python folder.
)

:: recreate folder
mkdir "%PYTHON_FOLDER%" > NUL

:skip_delete_old
:: === [END] delete old python folder ==================

:: install python files that are not in %exclude_install% (via .msi files)
pushd "%TMP_DIR%"
for %%A in (*.msi) do (
  set "skip="
  for %%X in (%exclude_install%) do (
    echo %%~nxA | findstr /i /c:"%%~X" >nul && set "skip=1"
  )
  if not defined skip (
    echo Installing %%~nxA
    msiexec /a "%%~fA" TARGETDIR="%PYTHON_FOLDER%" INSTALLDIR="%PYTHON_FOLDER%" /qn
    del /q "%PYTHON_FOLDER%\%%~nxA" 2>nul
  ) else (
    echo [Info] Excluded %%~nxA
  )
)
popd

:: verify functioning %local_python_name%
CALL "%PYTHON_FOLDER%\python.exe" -V > Nul || (
  echo [ERROR] Python not runnable. Aborting. Press any key to exit.
  PAUSE > NUL
  EXIT /B 2
)

:: delete temporariy folder
rmdir /s /q "%TMP_DIR%" > NUL 2>&1

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

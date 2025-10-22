:: check if fully portable

@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: process args
set "PY_VER=%~1"

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
echo: Found working python version %FULL_VER%

:: define URL based on full version
set "URL=https://www.python.org/ftp/python/%FULL_VER%/amd64/"
ECHO: Download URL: %URL%

:: (re)create tmp file
rmdir /s /q tmp > NUL 2>&1
mkdir tmp

:: downlaod files
powershell -NoLogo -NoProfile -Command ^
  "$base='%URL%';" ^
  "$out='tmp';" ^
  "$links=(Invoke-WebRequest -Uri $base).Links | Where-Object href -ne $null | ForEach-Object { $_.href } |" ^
  " Where-Object {$_ -notmatch '/$'} |" ^
  " ForEach-Object { if($_ -match '^https?://') {$_} else {$base + $_} } |" ^
  " Where-Object { -not ( ([IO.Path]::GetFileNameWithoutExtension( ([IO.Path]::GetFileNameWithoutExtension($_)) )) -match '(_d|_pdb)$' ) };" ^
  "foreach($l in $links){$n=[IO.Path]::GetFileName($l);$p=Join-Path $out $n;Try{Invoke-WebRequest -Uri $l -OutFile $p -UseBasicParsing}catch{Write-Error $l}}"

:: (re)create final installation folder
set "TARGET_DIR=portable_python"
CALL :make_absolute_path_if_relative "%TARGET_DIR%"
SET "TARGET_DIR=%OUTPUT%"
rmdir /s /q "%TARGET_DIR%" > NUL 2>&1
mkdir "%TARGET_DIR%" > NUL

:: install python files
pushd tmp
for %%A in (*.msi) do (
  echo: Processing %%~nxA
  msiexec /a "%%~fA" TARGETDIR="%TARGET_DIR%" INSTALLDIR="%TARGET_DIR%" /qn
  del /q "%TARGET_DIR%\%%~nxA" 2>nul
)
popd

:: verify functioning %local_python_name%
CALL "%TARGET_DIR%\python.exe" -V || (
  echo: [ERROR] Python not runnable. Aborting. Press any key to exit.
  PAUSE > NUL
  EXIT /B 2
)

:: delete temporariy folder
rmdir /s /q tmp > NUL 2>&1

:: print success and exit
echo:
echo: Sucessfully created portable Python (%FULL_VER%) at "%TARGET_DIR%". Print any key to exit.
PAUSE > NUL
exit /b 0



:: -------------------------------------------------
:: function that makes relative path (relative to current working directory) to absolute if not already:
:: -------------------------------------------------
:make_absolute_path_if_relative
	SET "OUTPUT=%~f1"
	GOTO :EOF
:: -------------------------------------------------

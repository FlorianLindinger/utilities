@REM ########################
@REM Safe delete to Recycle Bin ONLY if capacity is sufficient.
@REM Usage:  call safer_folder_deletion.bat "C:\path\to\folder" "optional message"
@REM Exit codes: 0=deleted to bin, 1=user abort, 2+=guards/errors
@REM ########################

@ECHO OFF
setlocal EnableExtensions
:: ====================
:: ===== Settings =====
:: ====================
SET "MAX_ALLOWED_FOLDER_SIZE_GB=10"
SET "MIN_DEPTH=3"
set "BLOCK_ANCESTOR_LEVELS=3"   REM refuse target if it is the script dir or ≤3 levels above it
:: ====================
:: ====================

:: ==== get message from args & derive absolut path + drive letter ====
set "abs_path=%~f1"
set "DRIVE=%~d1"
SET "msg=%~2"

:: ==== fallback default message ====
IF "%msg%"=="" SET "msg=[Question] Do you want to move the following folder to the recycling bin: ^"%abs_path%^" ?"

:: ==== check input ====
IF "%abs_path%"=="" CALL :print_e "Folder path is required. Aborting." & exit /b 2
IF NOT EXIST "%abs_path%" CALL :print_e "Folder path does not exist: %abs_path%" & exit /b 3
IF NOT EXIST "%abs_path%\*" CALL :print_e "Input not a folder: %abs_path%" & exit /b 4



PAUSE

@REM rem --- normalize script dir and target dir (no trailing '\') ---
for %%A in ("%~dp0.") do set "SCRIPT_DIR=%%~fA"
for %%A in ("%abs_path%.") do set "TARGET_DIR=%%~fA"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
if "%TARGET_DIR:~-1%"=="\" set "TARGET_DIR=%TARGET_DIR:~0,-1%"


rem prefix test: if SCRIPT_DIR starts with TARGET_DIR + '\', then TARGET is an ancestor
if /I not "%SCRIPT_DIR:%TARGET_DIR%\=%"=="%SCRIPT_DIR%" (
  call :print_e "Refusing to delete ancestor of the script directory: %TARGET_DIR%" & exit /b 99
)







REM --- normalize script and target (no trailing \) ---
for %%A in ("%~dp0.") do set "SCRIPT_DIR=%%~fA"
for %%A in ("%abs_path%.") do set "TARGET_DIR=%%~fA"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
if "%TARGET_DIR:~-1%"=="\" set "TARGET_DIR=%TARGET_DIR:~0,-1%"


REM --- if TARGET is ancestor of SCRIPT, compute depth distance and block when ≤ N ---
set "REL=%SCRIPT_DIR%"
set "PREFIX=%TARGET_DIR%\"
if /I not "%REL:%PREFIX%=%"=="%REL%" (
  REM TARGET is a prefix (ancestor). Count remaining segments in REL after PREFIX.
  set "TAIL=%REL:*%PREFIX%=%"
  set "CNT=0"
  for %%x in (%TAIL:\= %) do set /a CNT+=1
  if %CNT% LEQ %BLOCK_ANCESTOR_LEVELS% (
    call :print_e "Refusing to delete ancestor (%CNT% level(s) up): %TARGET_DIR%" & exit /b 99
  )
)



@REM normalize paths?


:: ----- Block critical locations -----
IF /I "%abs_path%"=="%DRIVE%" CALL :print_e "Can't delete drive root: %abs_path%" & exit /b 6
FOR %%P IN ("%SystemRoot%" "%ProgramFiles%" "%ProgramFiles(x86)%" "%ProgramData%" "%USERPROFILE%") DO (
  IF /I "%%~fP"=="%abs_path%" CALL :print_e "Protected path can't be deleted: %abs_path%" & exit /b 7
)
IF /I "%abs_path%"=="%CD%" CALL :print_e "Current working directory can't be deleted." & exit /b 8
IF /I "%abs_path%"=="%~dp0" CALL :print_e "Script directory can't be deleted." & exit /b 9

:: ----- check minimum depth -----
SET "DEPTH=0"
SET "TMP=%abs_path:\= %"
FOR %%A IN (%TMP%) DO SET /A DEPTH+=1
IF %MIN_DEPTH% GTR 0 IF %DEPTH% LSS %MIN_DEPTH% CALL :print_e "Path depth %DEPTH% is below minimum %MIN_DEPTH% for %abs_path%" & exit /b 10

:: ==== get folder size ====
ECHO: Measuring folder size ...
for /f "usebackq delims=" %%A in (`
  powershell -NoProfile -Command ^
  "$s = Get-ChildItem -LiteralPath '%abs_path%' -Force -Recurse -ErrorAction SilentlyContinue | Measure-Object -Sum Length; [int64]$s.Sum"
`) do set "folder_bytes=%%A"
for /f "usebackq delims=" %%A in (`
  powershell -NoProfile -Command ^
  "[System.Threading.Thread]::CurrentThread.CurrentCulture = 'en-US';" ^
  "$b = %folder_bytes%; " ^
  "if ($b -eq 0) {0} else { [math]::Ceiling(($b / 1GB) * 100) / 100 }"
`) do set "folder_size_GB=%%A"

:: ==== abort for too large size ====
IF %folder_size_GB% GTR %MAX_ALLOWED_FOLDER_SIZE_GB% CALL :print_e "Folder size %folder_size_GB% GB exceeds maximum (%MAX_ALLOWED_FOLDER_SIZE_GB% GB^). Aborting. Consider deleting manually: %abs_path%" & exit /b 12

:: ===== User confirmation =====
echo(
echo %msg%
:ask
ECHO Confirm deletion (Y/N):
SET /P ANSW="":
IF /I "%ANSW%"=="Y" GOTO yes
IF /I "%ANSW%"=="N" GOTO no
ECHO Please enter Y or N:
GOTO ask
:yes
SET "confirmed=1"
GOTO end_ask
:no
SET "confirmed=0"
GOTO end_ask
:end_ask

:: ==== user abort ====
IF "%confirmed%"=="0" CALL :print_e "Folder deletion aborted by user" & exit /b 11

:: ==== send to recycling bin ====
powershell -NoProfile -Command "Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory('%abs_path%',[Microsoft.VisualBasic.FileIO.UIOption]::AllDialogs,[Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)" 2>NUL

:: ==== exit failure =====
IF EXIST "%abs_path%\*" CALL :print_e "Moving folder to Recycle Bin failed" & exit /b 13

:: ==== exit success =====
ECHO Folder successfully moved to Recycle Bin: %abs_path%
exit /b 0

:: ================================
:: ===== Function Definitions =====
:: ================================
REM Prints an formatted error message.
REM Usage: call :print_e "{message}" & exit /b {exit code}
:print_e
setlocal DisableDelayedExpansion
set "full=[ERROR] %~1"
set "tmp=%full%" & set "len=0"
:lenloop
if defined tmp ( set /a len+=1 & call set "tmp=%%tmp:~1%%" & goto :lenloop )
set "bar=" & for /l %%i in (1,1,%len%) do call set "bar=%%bar%%="
echo(
>&2 echo %bar%
>&2 echo %full%
>&2 echo %bar%
echo(
endlocal & GOTO :eof
:: ================================

@ECHO OFF

SET "path=test"
SET "message=test message"

CALL :delete_folder_after_confirmation "%path%" "%message%"



PAUSE


@REM -------------------------------------------------
@REM function that prompt user to confirm if folder at path can be deleted and deletes if and stops program else with a message to the user. First agrument is the path which is to be deleted and the second one is a custom message to the user. If none given it prints ""
@REM -------------------------------------------------
:delete_folder_after_confirmation
	SETLOCAL
	
	SET "folder_path=%~1"
	IF NOT "%~2"=="" (
		SET "message=%~2"
	) ELSE (
		SET "message=Delete folder at folder path: ""%folder_path%""? (recommended after confirmation of correct folder path^):"
	)

	IF "%folder_path%"=="" (
		ECHO: ERROR: Folder path can't be empty for folder that is meant to be deleted!
		ENDLOCAL
		GOTO :EOF
	) 

	IF NOT EXIST "%folder_path%" (
		ECHO: ERROR: Folder path ("%folder_path%"^) does not exist for folder that is meant to be deleted!
		ENDLOCAL
		GOTO :EOF
	) 
	
	ECHO: %message%
	CHOICE /c YN /m Delete? Enter y/n for Yes/No
	IF %ERRORLEVEL%==1 (
		ECHO "%folder_path%"
		@REM RD /S /Q "%folder_path%" &@REM CAREFULL. DELETES EVERYTHING IN THAT FOLDER
	)

	ENDLOCAL
	GOTO :EOF
@REM -------------------------------------------------





@REM safer delete with double confirmation + protected paths
:delete_folder_after_confirmation
setlocal EnableExtensions EnableDelayedExpansion

set "raw=%~1"
set "msg=%~2"

if not defined raw (
  echo [ERR] Folder path is required.
  endlocal & exit /b 2
)

REM normalize to absolute path (no trailing backslash)
for %%A in ("%raw%") do (
  set "FULL=%%~fA"
  set "DRIVE=%%~dA"
)

REM must exist and be a directory
if not exist "!FULL!\*" (
  echo [ERR] Not an existing directory: "!FULL!"
  endlocal & exit /b 3
)

REM PROTECT: drive root, Windows dirs, common system dirs, current dir
set "PROTECT_LIST=!DRIVE!;!SystemRoot!;!WinDir!;%ProgramFiles%;%ProgramFiles(x86)%;%ProgramData%;%USERPROFILE%;%HOMEDRIVE%%HOMEPATH%"

for %%P in (!PROTECT_LIST!) do (
  if /I "%%~fP"=="!FULL!" (
    echo [ABORT] Protected path: "!FULL!"
    endlocal & exit /b 10
  )
)

REM block drive root explicitly
if /I "!FULL!"=="!DRIVE!" (
  echo [ABORT] Refusing to delete drive root: "!FULL!"
  endlocal & exit /b 11
)

REM refuse to delete current working dir or the script's dir
if /I "!FULL!"=="%CD%" (
  echo [ABORT] Refusing to delete the current working directory.
  endlocal & exit /b 12
)
if /I "!FULL!"=="%~dp0" (
  echo [ABORT] Refusing to delete the script's directory.
  endlocal & exit /b 13
)

REM detect reparse point (junction/symlink) and abort
for /f "tokens=* delims=" %%R in ('powershell -NoProfile -Command ^
  "$p='%FULL%'; ([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0"') do set "ISRP=%%R"
if /I "!ISRP!"=="True" (
  echo [ABORT] Target is a reparse point (junction/symlink). Not deleting: "!FULL!"
  endlocal & exit /b 14
)

REM message
if not defined msg (
  set "msg=Delete folder: ""!FULL!"" ?"
)

echo.
echo !msg!
choice /c YN /m "Confirm (Y/N)"
if errorlevel 2 (
  echo [INFO] User cancelled.
  endlocal & exit /b 1
)

REM second confirmation: user must type the exact path
set /p CONFIRM=Type the EXACT full path to delete and press Enter: 
if /I not "!CONFIRM!"=="!FULL!" (
  echo [INFO] Confirmation mismatch. Aborting.
  endlocal & exit /b 1
)

REM final safety pause
echo Last chance: deleting "!FULL!" in 5 seconds... Ctrl+C to cancel.
timeout /t 5 >nul

REM delete
echo Deleting "!FULL!" ...
rd /s /q "!FULL!"
if errorlevel 1 (
  echo [ERR] Failed to delete: "!FULL!"
  endlocal & exit /b 20
)

echo [OK] Deleted: "!FULL!"
endlocal & exit /b 0

@REM ###################################

powershell -NoProfile -Command ^
  "Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory('%FULL%','OnlyErrorDialogs','SendToRecycleBin')"


@REM ###################################


@REM -------------------------------------------------
@REM Safer delete: sends folder to Recycle Bin if possible; warns if likely too big.
@REM Optional: set RECYCLE_QUOTA_PERCENT (default 5) to change the estimated bin quota.
@REM Usage: call :delete_folder_after_confirmation "C:\path\to\folder" "optional message"
@REM -------------------------------------------------
:delete_folder_after_confirmation
setlocal EnableExtensions EnableDelayedExpansion

set "raw=%~1"
set "msg=%~2"

if not defined raw (
  echo [ERR] Folder path is required.
  endlocal & exit /b 2
)

REM Normalize to absolute path (no trailing backslash)
for %%A in ("%raw%") do (
  set "FULL=%%~fA"
  set "DRIVE=%%~dA"
)

REM Must exist and be a directory
if not exist "!FULL!\*" (
  echo [ERR] Not an existing directory: "!FULL!"
  endlocal & exit /b 3
)

REM Protect critical locations
set "PROTECT_LIST=!DRIVE!;!SystemRoot!;!WinDir!;%ProgramFiles%;%ProgramFiles(x86)%;%ProgramData%;%USERPROFILE%;%HOMEDRIVE%%HOMEPATH%"
for %%P in (!PROTECT_LIST!) do (
  if /I "%%~fP"=="!FULL!" (
    echo [ABORT] Protected path: "!FULL!"
    endlocal & exit /b 10
  )
)
if /I "!FULL!"=="!DRIVE!" (
  echo [ABORT] Refusing to delete drive root: "!FULL!"
  endlocal & exit /b 11
)
if /I "!FULL!"=="%CD%" (
  echo [ABORT] Refusing to delete the current working directory.
  endlocal & exit /b 12
)
if /I "!FULL!"=="%~dp0" (
  echo [ABORT] Refusing to delete the script's directory.
  endlocal & exit /b 13
)

REM Block reparse points/junctions (dangerous)
for /f "tokens=* delims=" %%R in ('
  powershell -NoProfile -Command ^
    "$p='%FULL%'; ([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0"
') do set "ISRP=%%R"
if /I "!ISRP!"=="True" (
  echo [ABORT] Target is a reparse point (junction/symlink). Not deleting: "!FULL!"
  endlocal & exit /b 14
)

REM Prompt(s)
if not defined msg set "msg=Delete folder: ""!FULL!"" ?"
echo.
echo !msg!
choice /c YN /m "Confirm (Y/N)"
if errorlevel 2 (
  echo [INFO] User cancelled.
  endlocal & exit /b 1
)

set /p CONFIRM=Type the EXACT full path to delete and press Enter: 
if /I not "!CONFIRM!"=="!FULL!" (
  echo [INFO] Confirmation mismatch. Aborting.
  endlocal & exit /b 1
)

REM ---- Size checks (estimate) ----
if not defined RECYCLE_QUOTA_PERCENT set "RECYCLE_QUOTA_PERCENT=5"

REM Folder size in bytes
for /f "tokens=* delims=" %%S in ('
  powershell -NoProfile -Command ^
    "$p='%FULL%'; $s=Get-ChildItem -LiteralPath $p -Force -Recurse -ErrorAction SilentlyContinue | Measure-Object -Sum Length; ($s.Sum | ForEach-Object {[int64]$_})"
') do set "DIR_BYTES=%%S"
if not defined DIR_BYTES set "DIR_BYTES=0"

REM Drive total size in bytes
for /f "tokens=* delims=" %%T in ('
  powershell -NoProfile -Command ^
    "$d='%DRIVE%'.TrimEnd('\'); (Get-CimInstance Win32_LogicalDisk -Filter ('DeviceID=''{0}''' -f $d)).Size"
') do set "DRV_TOTAL=%%T"

REM Estimate bin quota bytes
for /f "tokens=* delims=" %%Q in ('
  powershell -NoProfile -Command ^
    "[int64]([double]('%RECYCLE_QUOTA_PERCENT%')/100.0 * [double]('%DRV_TOTAL%'))"
') do set "BIN_QUOTA=%%Q"

echo.
echo [INFO] Folder size: !DIR_BYTES! bytes
echo [INFO] Drive total: !DRV_TOTAL! bytes
echo [INFO] Est. Recycle Bin quota: %RECYCLE_QUOTA_PERCENT%%% (= !BIN_QUOTA! bytes)

set "LIKELY_PERMA="
for /f "tokens=* delims=" %%C in ('
  powershell -NoProfile -Command ^
    "([int64]('%DIR_BYTES%') -gt [int64]('%BIN_QUOTA%'))"
') do set "LIKELY_PERMA=%%C"

if /I "!LIKELY_PERMA!"=="True" (
  echo.
  echo [WARN] The folder appears larger than the estimated Recycle Bin quota.
  echo        Windows may purge bin items or **permanently delete** this folder.
  choice /c YN /m "Proceed anyway (Y = try Recycle Bin; N = abort)?"
  if errorlevel 2 (
    echo [INFO] Aborted by user.
    endlocal & exit /b 1
  )
)

echo Last chance: deleting ""!FULL!"" (to Recycle Bin) in 5 seconds... Ctrl+C to cancel.
timeout /t 5 >nul

REM ---- Send to Recycle Bin (Explorer-equivalent) ----
for /f "tokens=* delims=" %%E in ('
  powershell -NoProfile -Command ^
    "Add-Type -AssemblyName Microsoft.VisualBasic; " ^
    "[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(" ^
    "  '%FULL%'," ^
    "  [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs," ^
    "  [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin" ^
    ")"
') do set "PSOUT=%%E"

REM Verify deletion
if exist "!FULL!\*" (
  echo [ERR] Folder still exists. Recycle Bin may have refused the move (too large, wrong volume, permissions).
  echo       Do you want to PERMANENTLY delete it? (Y/N)
  choice /c YN
  if errorlevel 2 (
    echo [INFO] Aborted by user.
    endlocal & exit /b 1
  )
  echo Permanently deleting...
  rd /s /q "!FULL!"
  if errorlevel 1 (
    echo [ERR] Permanent delete failed.
    endlocal & exit /b 20
  )
  echo [OK] Permanently deleted: "!FULL!"
) else (
  echo [OK] Sent to Recycle Bin: "!FULL!"
)

endlocal & exit /b 0

@REM ################################


@REM -------------------------------------------------
@REM Delete to Recycle Bin ONLY if there is enough estimated capacity.
@REM Usage: call :safe_recycle_delete "C:\path\to\folder" "optional message"
@REM Optional: set RECYCLE_QUOTA_PERCENT (default 5)
@REM Exit codes: 0=deleted to bin, 1=user abort/insufficient bin, 2+ = guards/errors
@REM -------------------------------------------------
:safe_recycle_delete
setlocal EnableExtensions EnableDelayedExpansion

set "raw=%~1"
set "msg=%~2"

if not defined raw (
  echo [ERR] Folder path is required.
  endlocal & exit /b 2
)

for %%A in ("%raw%") do (
  set "FULL=%%~fA"
  set "DRIVE=%%~dA"
)

if not exist "!FULL!\*" (
  echo [ERR] Not an existing directory: "!FULL!"
  endlocal & exit /b 3
)

REM --- hard guards (keep yourself safe) ---
if /I "!FULL!"=="!DRIVE!" ( echo [ABORT] Drive root blocked. & endlocal & exit /b 10 )
for %%P in ("%SystemRoot%" "%ProgramFiles%" "%ProgramFiles(x86)%" "%ProgramData%" "%USERPROFILE%") do (
  if /I "%%~fP"=="!FULL!" ( echo [ABORT] Protected path: "!FULL!" & endlocal & exit /b 11 )
)
if /I "!FULL!"=="%CD%"   ( echo [ABORT] Current working dir blocked. & endlocal & exit /b 12 )
if /I "!FULL!"=="%~dp0"  ( echo [ABORT] Script directory blocked. & endlocal & exit /b 13 )
REM block junctions/symlinks
for /f "tokens=* delims=" %%R in ('
  powershell -NoProfile -Command "$p='%FULL%'; ((Get-Item -LiteralPath $p).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0"
') do set "ISRP=%%R"
if /I "!ISRP!"=="True" ( echo [ABORT] Junction/symlink blocked. & endlocal & exit /b 14 )

REM --- prompt user ---
if not defined msg set "msg=Recycle (NOT permanently delete) folder: ""!FULL!"" ?"
echo.
echo !msg!
choice /c YN /m "Confirm (Y/N)"
if errorlevel 2 ( echo [INFO] Aborted by user. & endlocal & exit /b 1 )

REM --- compute sizes (bytes) ---
if not defined RECYCLE_QUOTA_PERCENT set "RECYCLE_QUOTA_PERCENT=5"

REM Folder size
for /f "tokens=* delims=" %%S in ('
  powershell -NoProfile -Command ^
  "$p='%FULL%'; $s=Get-ChildItem -LiteralPath $p -Force -Recurse -ErrorAction SilentlyContinue | Measure-Object -Sum Length; [int64]($s.Sum)"
') do set "DIR_BYTES=%%S"
if not defined DIR_BYTES set "DIR_BYTES=0"

REM Drive total & free
for /f "tokens=* delims=" %%T in ('
  powershell -NoProfile -Command ^
  "$d='%DRIVE%'.TrimEnd('\'); $ld=Get-CimInstance Win32_LogicalDisk -Filter ('DeviceID=''{0}''' -f $d); @([int64]$ld.Size, [int64]$ld.FreeSpace) -join ','"
') do set "DRV=%%T"
for /f "tokens=1,2 delims=," %%a in ("%DRV%") do (
  set "DRV_TOTAL=%%a"
  set "DRV_FREE=%%b"
)

REM Current Recycle Bin usage on this drive
for /f "tokens=* delims=" %%U in ('
  powershell -NoProfile -Command ^
  "$d='%DRIVE%'.TrimEnd('\'); $sid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value; " ^
  "$rb=Join-Path $d '\$Recycle.Bin'; if (Test-Path $rb) {" ^
  "  $sum=(Get-ChildItem -LiteralPath $rb -Force -ErrorAction SilentlyContinue | " ^
  "        Where-Object { $_.PSIsContainer } | " ^
  "        ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Force -Recurse -ErrorAction SilentlyContinue } | " ^
  "        Measure-Object -Sum Length).Sum; [int64]$sum } else { [int64]0 }"
') do set "BIN_USED=%%U"
if not defined BIN_USED set "BIN_USED=0"

REM Estimate quota
for /f "tokens=* delims=" %%Q in ('
  powershell -NoProfile -Command ^
  "[int64]([double]('%RECYCLE_QUOTA_PERCENT%')/100.0 * [double]('%DRV_TOTAL%'))"
') do set "BIN_QUOTA=%%Q"

REM Free room in bin by estimate
for /f "tokens=* delims=" %%F in ('
  powershell -NoProfile -Command ^
  "[int64]('%BIN_QUOTA%') - [int64]('%BIN_USED%')"
') do set "BIN_FREE_EST=%%F"

echo.
echo [INFO] Folder size:         !DIR_BYTES! bytes
echo [INFO] Recycle Bin used:    !BIN_USED! bytes
echo [INFO] Recycle Bin quota:   !BIN_QUOTA! bytes  (%RECYCLE_QUOTA_PERCENT%%% of drive)
echo [INFO] Recycle Bin free est:!BIN_FREE_EST! bytes
echo [INFO] Drive free space:    !DRV_FREE! bytes

REM hard requirement: enough free disk AND enough est. bin free
for /f "tokens=* delims=" %%C in ('
  powershell -NoProfile -Command ^
  "([int64]('%DIR_BYTES%') -le [int64]('%BIN_FREE_EST%')) -and ([int64]('%DIR_BYTES%') -le [int64]('%DRV_FREE%'))"
') do set "CAN_RECYCLE=%%C"

if /I not "!CAN_RECYCLE!"=="True" (
  echo.
  echo [ABORT] Not enough Recycle Bin capacity (or disk free) to safely move this folder.
  echo         -> Please delete manually via Explorer (so you see any prompts) or free up the bin.
  echo         (Tip: increase the bin size for %DRIVE% or empty it, then try again.)
  endlocal & exit /b 1
)

echo Proceeding to send to Recycle Bin…
REM Explorer-equivalent: SendToRecycleBin
for /f "tokens=* delims=" %%E in ('
  powershell -NoProfile -Command ^
  "Add-Type -AssemblyName Microsoft.VisualBasic; " ^
  "[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(" ^
  "  '%FULL%'," ^
  "  [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs," ^
  "  [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin" ^
  ")"
') do set "PSOUT=%%E"

REM Verify (do NOT permanently delete on failure)
if exist "!FULL!\*" (
  echo [ERR] Recycle Bin move did not complete (Windows may have refused).
  echo       No permanent deletion was performed. Please delete manually in Explorer.
  endlocal & exit /b 21
)

echo [OK] Sent to Recycle Bin: "!FULL!"
endlocal & exit /b 0



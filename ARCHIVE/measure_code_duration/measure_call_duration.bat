:: Usage: measure_call_duration.bat <terminal command>
:: Example: measure_call_duration.bat python main.py 
:: Example: measure_call_duration.bat batch_file.bat
:: Warning: For batch files could be that the called batch code needs "exit" instead of "exit \b"

@echo off

if "%~1"=="" (
  echo Usage: %~nx0 ^<terminal command^>
  exit /b 1
)

setlocal
rem --- Console presentation: NO_COLOR disables ANSI; UTILITIES_QUIET hides headings. ---
set "UTIL_UI_ESC="
set "UTIL_UI_INFO="
set "UTIL_UI_OK="
set "UTIL_UI_WARN="
set "UTIL_UI_ERROR="
set "UTIL_UI_RESET="
if not defined NO_COLOR if /I not "%TERM%"=="dumb" for /F "delims=#" %%E in ('"prompt #$E# & for %%E in (1) do rem"') do set "UTIL_UI_ESC=%%E"
if defined UTIL_UI_ESC set "UTIL_UI_INFO=%UTIL_UI_ESC%[96m"
if defined UTIL_UI_ESC set "UTIL_UI_OK=%UTIL_UI_ESC%[92m"
if defined UTIL_UI_ESC set "UTIL_UI_WARN=%UTIL_UI_ESC%[93m"
if defined UTIL_UI_ESC set "UTIL_UI_ERROR=%UTIL_UI_ESC%[91m"
if defined UTIL_UI_ESC set "UTIL_UI_RESET=%UTIL_UI_ESC%[0m"
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%============================================================%UTIL_UI_RESET%
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%  Archive: Measure call duration%UTIL_UI_RESET%
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%============================================================%UTIL_UI_RESET%
rem --- End console presentation. ---

set "ps1=%TEMP%\__timer_run.ps1"

> "%ps1%" echo $sw=[System.Diagnostics.Stopwatch]::StartNew()
>>"%ps1%" echo cmd /c call @args
>>"%ps1%" echo $sw.Stop()
>>"%ps1%" echo [Math]::Round($sw.Elapsed.TotalSeconds,3)
>>"%ps1%" echo exit $LASTEXITCODE

for /f %%t in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%ps1%" %*') do set "elapsed=%%t"
set "ec=%ERRORLEVEL%"
del "%ps1%" >nul 2>&1

echo:%UTIL_UI_INFO%%elapsed% s%UTIL_UI_RESET%
endlocal & exit /b %ec%
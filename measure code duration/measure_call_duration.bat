@echo off
rem Usage: timer.bat <command and args>
rem Example: timer.bat python main.py

if "%~1"=="" (
  echo Usage: %~nx0 ^<command and args^>
  exit /b 1
)

setlocal
set "ps1=%TEMP%\__timer_run.ps1"

> "%ps1%" echo $sw=[System.Diagnostics.Stopwatch]::StartNew()
>>"%ps1%" echo cmd /c @args
>>"%ps1%" echo $sw.Stop()
>>"%ps1%" echo [Math]::Round($sw.Elapsed.TotalSeconds,3)
>>"%ps1%" echo exit $LASTEXITCODE

for /f %%t in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%ps1%" %*') do set "elapsed=%%t"
set "ec=%ERRORLEVEL%"
del "%ps1%" >nul 2>&1

echo %elapsed% s
endlocal & exit /b %ec%
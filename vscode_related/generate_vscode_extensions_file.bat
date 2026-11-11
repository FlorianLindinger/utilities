@echo off
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
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%  Export installed VS Code extensions%UTIL_UI_RESET%
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%============================================================%UTIL_UI_RESET%
rem --- End console presentation. ---


:: Generate output\all_extensions.json from installed extensions
:: Copy the result to a workspace .vscode folder if extension recommendations are wanted there.

set "OUTDIR=%~dp0output"
set "OUTFILE=%OUTDIR%\all_extensions.json"

REM Use PowerShell for JSON formatting.
powershell -NoProfile -ExecutionPolicy Bypass ^
  "$code = (Get-Command code -ErrorAction SilentlyContinue); " ^
  "if(-not $code){ $code = Get-Command code-insiders -ErrorAction SilentlyContinue }; " ^
  "if(-not $code){ Write-Error 'VS Code CLI not found.'; exit 1 }; " ^
  "$exts = & $code.Source --list-extensions; " ^
  "$obj = [ordered]@{ recommendations = $exts }; " ^
  "$json = $obj | ConvertTo-Json -Depth 3 | ForEach-Object { $_ -replace '^\s{8}','  ' -replace '^\s{4}','  ' }; " ^
  "New-Item -ItemType Directory -Force -Path '%OUTDIR%' | Out-Null; " ^
  "Set-Content -Path '%OUTFILE%' -Value $json -Encoding UTF8; " 

if errorlevel 1 (
  echo:%UTIL_UI_ERROR%Failed to generate %OUTFILE%.%UTIL_UI_RESET%
  echo:%UTIL_UI_WARN% Press any key to exit%UTIL_UI_RESET%
  pause > nul
  exit /b 1
) else (
  echo:%UTIL_UI_OK% (Re^)generated %OUTFILE%%UTIL_UI_RESET%
  echo:%UTIL_UI_WARN% Press any key to exit%UTIL_UI_RESET%
  pause > nul
  exit /b 0
)



@echo off
setlocal

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
  echo Failed to generate %OUTFILE%.
  echo: Press any key to exit
  pause > nul
  exit /b 1
) else (
  echo: (Re^)generated %OUTFILE%
  echo: Press any key to exit
  pause > nul
  exit /b 0
)



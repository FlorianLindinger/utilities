@echo off
setlocal

:: Generate .vscode\extensions.json from installed extensions
:: if .vscode is at workspace path, vscode will prompt user to install extensions in that file

set "OUTDIR=.vscode"
set "OUTFILE=%OUTDIR%\extensions.json"

REM Use PowerShell for JSON formatting.
powershell -NoProfile -ExecutionPolicy Bypass ^
  "$code = (Get-Command code -ErrorAction SilentlyContinue); " ^
  "if(-not $code){ $code = Get-Command code-insiders -ErrorAction SilentlyContinue }; " ^
  "if(-not $code){ Write-Error 'VS Code CLI not found.'; exit 1 }; " ^
  "$exts = & $code.Source --list-extensions; " ^
  "$obj = [ordered]@{ recommendations = $exts }; " ^
  "$json = $obj | ConvertTo-Json -Depth 3 | ForEach-Object { $_ -replace '^\s{8}','  ' -replace '^\s{4}','  ' }; " ^
  "New-Item -ItemType Directory -Force -Path '%OUTDIR%' | Out-Null; " ^
  "Set-Content -Path '%OUTFILE%' -Value $json -Encoding UTF8; " ^
  "Write-Host 'Wrote %OUTFILE%'"


if errorlevel 1 (
  echo Failed to generate %OUTFILE%.
  exit /b 1
)

echo Done.
endlocal

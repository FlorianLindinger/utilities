@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Usage: release.bat TAG [--dry-run]
if /I "%~1"=="--help" goto :help
if "%~1"=="/?" goto :help
if "%~1"=="" goto :usage_error
if not "%~3"=="" goto :usage_error
if not "%~2"=="" if /I not "%~2"=="--dry-run" goto :usage_error
set "UTILITIES_RELEASE_SCRIPT=%~f0"
set "UTILITIES_RELEASE_ROOT=%~dp0"
set "UTILITIES_RELEASE_TAG=%~1"
set "UTILITIES_RELEASE_DRY_RUN=%~2"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$text = [IO.File]::ReadAllText($env:UTILITIES_RELEASE_SCRIPT); $payload = ($text -split '(?m)^# POWERSHELL_PAYLOAD\r?$', 2)[1]; & ([scriptblock]::Create($payload))"
exit /b %errorlevel%

:usage_error
echo Usage: release.bat TAG [--dry-run] 1>&2
exit /b 2

:help
echo Usage: release.bat TAG [--dry-run]
echo Example: release.bat v1.0.0
echo Uploads the five current local setup files as GitHub release assets.
echo Targets the current Git commit, which must already exist on GitHub.
echo Requires GitHub CLI: install gh, then run gh auth login.
echo --dry-run validates inputs without contacting GitHub or publishing.
exit /b 0

# POWERSHELL_PAYLOAD
$ErrorActionPreference = 'Stop'
try {
    $root = $env:UTILITIES_RELEASE_ROOT
    $tag = $env:UTILITIES_RELEASE_TAG
    $relativePaths = @(
        'vscode related\good_vscode_settings.json'
        'python related\good_pyrefly_settings.toml'
        'python related\good_Ruff_settings.toml'
        'vscode related\.vscode\extensions.json'
        'python related\create_python_env.bat'
    )
    $sources = @($relativePaths | ForEach-Object { Join-Path $root $_ })
    $missing = @($sources | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missing.Count) {
        throw ('Missing release files:' + [Environment]::NewLine + ($missing -join [Environment]::NewLine))
    }
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { throw 'Git is required.' }
    & git.exe check-ref-format "refs/tags/$tag"
    if ($LASTEXITCODE -ne 0 -or $tag.StartsWith('-')) { throw 'Invalid release tag.' }
    $commit = & git.exe -C $root rev-parse --verify HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read the current Git commit.' }
    Write-Host "Tag: $tag"
    Write-Host "Commit: $commit"
    Write-Host 'Assets (current local contents):'
    $sources | ForEach-Object { Write-Host ('  ' + $_) }
    if ($env:UTILITIES_RELEASE_DRY_RUN -eq '--dry-run') {
        Write-Host 'Dry run complete; nothing published.'
        exit 0
    }
    if (-not (Get-Command gh.exe -ErrorAction SilentlyContinue)) {
        throw 'GitHub CLI is required. Install gh, then run gh auth login.'
    }
    Push-Location -LiteralPath $root
    try {
        & gh.exe auth status --hostname github.com
        if ($LASTEXITCODE -ne 0) { throw 'GitHub authentication failed. Run gh auth login.' }
        $repo = & gh.exe repo view --json nameWithOwner --jq .nameWithOwner
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repo)) { throw 'Cannot resolve the GitHub repository.' }
        # Upload to a draft first so an asset failure cannot publish a partial release.
        & gh.exe release create $tag @sources --repo $repo --target $commit --title $tag --generate-notes --draft
        if ($LASTEXITCODE -ne 0) { throw 'Release creation/upload failed. An existing release was not overwritten; check GitHub for a partial draft.' }
        & gh.exe release edit $tag --repo $repo --draft=false
        if ($LASTEXITCODE -ne 0) { throw 'Assets uploaded, but publishing failed. The release remains a draft.' }
        Write-Host "Published: https://github.com/$repo/releases/tag/$tag"
    }
    finally { Pop-Location }
    exit 0
}
catch {
    [Console]::Error.WriteLine('Release failed: ' + $_.Exception.Message)
    exit 1
}

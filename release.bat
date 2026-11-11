@echo off
setlocal EnableExtensions DisableDelayedExpansion
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
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%  Publish utilities release%UTIL_UI_RESET%
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%============================================================%UTIL_UI_RESET%
rem --- End console presentation. ---

rem Usage: release.bat major^|minor^|vMAJOR.MINOR [--dry-run]
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
echo Usage: release.bat major^|minor^|vMAJOR.MINOR [--dry-run] 1>&2
exit /b 2

:help
echo Usage: release.bat major^|minor^|vMAJOR.MINOR [--dry-run]
echo:%UTIL_UI_INFO%Examples: release.bat minor --dry-run%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%          release.bat major%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%          release.bat v1.2%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%Uploads five local setup files and a freshly exported VS Code profile.%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%Targets the current Git commit, which must already exist on GitHub.%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%Requires GitHub CLI: install gh, then run gh auth login.%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%Bumps use the highest remote version tag; no tags: minor = v0.1, major = v1.0.%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%--dry-run previews without publishing; bumps still read remote Git tags.%UTIL_UI_RESET%
exit /b 0

# POWERSHELL_PAYLOAD
$ErrorActionPreference = 'Stop'
try {
    $infoStyle = @{}
    $successStyle = @{}
    if (-not $env:NO_COLOR -and $env:TERM -ne 'dumb') {
        $infoStyle = @{ ForegroundColor = 'Cyan' }
        $successStyle = @{ ForegroundColor = 'Green' }
    }
    $root = $env:UTILITIES_RELEASE_ROOT
    $tag = $env:UTILITIES_RELEASE_TAG
    $relativePaths = @(
        'vscode_related\output\user_settings.json'
        'python_related\good_pyrefly_settings.toml'
        'python_related\good_Ruff_settings.toml'
        'vscode_related\.vscode\extensions.json'
        'python_related\create_python_env.bat'
    )
    $sources = @($relativePaths | ForEach-Object { Join-Path $root $_ })
    $missing = @($sources | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missing.Count) {
        throw ('Missing release files:' + [Environment]::NewLine + ($missing -join [Environment]::NewLine))
    }
    $profileExporter = Join-Path $root 'vscode_related\helper\export_synced_vscode_profile.py'
    if (-not (Test-Path -LiteralPath $profileExporter -PathType Leaf)) {
        throw "Missing VS Code profile exporter: $profileExporter"
    }
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { throw 'Git is required.' }
    if ($tag -in @('major', 'minor')) {
        $bump = $tag.ToLowerInvariant()
        # Read remote tags instead of relying on an outdated local tag cache.
        $remoteTags = @(& git.exe -C $root ls-remote --tags --refs origin)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read remote tags; version was not bumped.' }
        $versions = @(
            foreach ($line in $remoteTags) {
                # Accept legacy patch tags as a baseline; always emit two-part tags.
                if ($line -match '\srefs/tags/v?([0-9]+)\.([0-9]+)(?:\.[0-9]+)?$') {
                    [pscustomobject]@{ Major = [long]$Matches[1]; Minor = [long]$Matches[2] }
                }
            }
        )
        $latest = $versions | Sort-Object Major, Minor -Descending | Select-Object -First 1
        [long]$major = 0
        [long]$minor = 0
        if ($null -ne $latest) { $major = $latest.Major; $minor = $latest.Minor }
        if ($bump -eq 'major') { $major = [long]($major + 1); $minor = 0 }
        else { $minor = [long]($minor + 1) }
        $tag = "v$major.$minor"
    }
    elseif ($tag -match '^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
        $tag = "v$($Matches[1]).$($Matches[2])"
    }
    else { throw 'Use major, minor, or a two-part version such as v1.2.' }
    & git.exe check-ref-format "refs/tags/$tag"
    if ($LASTEXITCODE -ne 0 -or $tag.StartsWith('-')) { throw 'Invalid release tag.' }
    $commit = & git.exe -C $root rev-parse --verify HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read the current Git commit.' }
    $profileAsset = Join-Path $root 'vscode_related\output\vscode_profile.code-profile'
    if (Get-Command python.exe -ErrorAction SilentlyContinue) {
        & python.exe $profileExporter --output $profileAsset --overwrite
    }
    elseif (Get-Command py.exe -ErrorAction SilentlyContinue) {
        & py.exe -3 $profileExporter --output $profileAsset --overwrite
    }
    else { throw 'Python is required to export the VS Code profile.' }
    if ($LASTEXITCODE -ne 0) { throw 'VS Code profile export failed; release was not created.' }
    $sources += $profileAsset
    Write-Host "Tag: $tag" @infoStyle
    Write-Host "Commit: $commit" @infoStyle
    Write-Host 'Assets (current local contents):' @infoStyle
    $sources | ForEach-Object { Write-Host ('  ' + $_) @infoStyle }
    if ($env:UTILITIES_RELEASE_DRY_RUN -eq '--dry-run') {
        Write-Host 'Dry run complete; nothing published.' @successStyle
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
        Write-Host "Published: https://github.com/$repo/releases/tag/$tag" @successStyle
    }
    finally { Pop-Location }
    exit 0
}
catch {
    [Console]::Error.WriteLine('Release failed: ' + $_.Exception.Message)
    exit 1
}

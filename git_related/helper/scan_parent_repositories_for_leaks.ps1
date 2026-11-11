<#
Scan the parent of utilities for secrets in current files and Git history.

Gitleaks prints findings to the console. Secret values are redacted.
Exit 0 means no findings or errors, 1 means findings, and 2 means a scan error.
If Gitleaks is absent, download a verified Windows release to LocalAppData.
#>

$ErrorActionPreference = 'Stop'
$scanRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$lightwaveExplorer = Join-Path $scanRoot 'LightwaveExplorer'
$exceptionConfig = Join-Path $PSScriptRoot 'gitleaks_lightwaveexplorer.toml'
if (-not (Test-Path -LiteralPath $exceptionConfig -PathType Leaf)) {
    [Console]::Error.WriteLine("Gitleaks exception config is missing: $exceptionConfig")
    exit 2
}
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if ($null -eq $git) {
    [Console]::Error.WriteLine('git.exe was not found on PATH.')
    exit 2
}

function Install-Gitleaks {
    param([Parameter(Mandatory = $true)][string]$Destination)

    # The release asset digest comes from GitHub's release metadata and is
    # checked before the archive is expanded or its executable is run.
    $architecture = switch ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) {
        'X64' { 'x64'; break }
        'X86' { 'x32'; break }
        'Arm64' { 'arm64'; break }
        default { throw 'No Gitleaks release is available for this Windows architecture.' }
    }
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/gitleaks/gitleaks/releases/latest' -Headers @{ 'User-Agent' = 'utilities-gitleaks-scan' } -TimeoutSec 30
    if ($release.tag_name -notmatch '^v(\d+\.\d+\.\d+)$') {
        throw "Unexpected Gitleaks release tag: '$($release.tag_name)'"
    }
    $version = $Matches[1]
    $archiveName = "gitleaks_${version}_windows_${architecture}.zip"
    $asset = @($release.assets | Where-Object { $_.name -eq $archiveName })
    if ($asset.Count -ne 1 -or $asset[0].digest -notmatch '^sha256:[a-fA-F0-9]{64}$') {
        throw "Missing release asset or SHA-256 digest for '$archiveName'."
    }
    if ($asset[0].browser_download_url -notlike "https://github.com/gitleaks/gitleaks/releases/download/$($release.tag_name)/*") {
        throw 'Unexpected Gitleaks release download URL.'
    }

    $tempBase = Join-Path ([IO.Path]::GetTempPath()) ('gitleaks-install-' + [Guid]::NewGuid().ToString('N'))
    $archive = "$tempBase.zip"
    try {
        Write-Host "Gitleaks was not found. Downloading version $version for Windows $architecture..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $asset[0].browser_download_url -OutFile $archive -UseBasicParsing -TimeoutSec 120
        $actualDigest = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        if ($actualDigest -ine $asset[0].digest.Substring(7)) {
            throw "SHA-256 verification failed for '$archiveName'."
        }
        Expand-Archive -LiteralPath $archive -DestinationPath $tempBase
        $executable = Join-Path $tempBase 'gitleaks.exe'
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
            throw "The verified archive does not contain gitleaks.exe."
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
        Move-Item -LiteralPath $executable -Destination $Destination -Force
        Write-Host "Installed Gitleaks at '$Destination'."
    } finally {
        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempBase -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$gitleaks = Join-Path $scanRoot 'gitleaks.exe'
if (-not (Test-Path -LiteralPath $gitleaks -PathType Leaf)) {
    $command = Get-Command gitleaks.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $gitleaks = $command.Source
    } else {
        if (-not $env:LOCALAPPDATA) {
            [Console]::Error.WriteLine('LOCALAPPDATA is unavailable; cannot install Gitleaks for this user.')
            exit 2
        }
        $gitleaks = Join-Path $env:LOCALAPPDATA 'GitleaksRepoScan\gitleaks.exe'
        if (-not (Test-Path -LiteralPath $gitleaks -PathType Leaf)) {
            try {
                Install-Gitleaks -Destination $gitleaks
            } catch {
                [Console]::Error.WriteLine("Could not install Gitleaks: $($_.Exception.Message)")
                exit 2
            }
        }
    }
}

$scanErrors = 0
$scansWithFindings = 0

function Invoke-LeakScan {
    param(
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][string]$Target,
        [string]$ConfigPath
    )

    Push-Location -LiteralPath $Target
    try {
        $options = @('--no-banner', '--no-color', '--redact', '--verbose', '--exit-code=10')
        if ($ConfigPath) { $options += "--config=$ConfigPath" }
        if ($Mode -eq 'git') {
            $logOptions = '--log-opts=--all --reflog'
            & $gitleaks git @options $logOptions .
        } else {
            & $gitleaks dir @options .
        }
        $result = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    if ($result -eq 10) {
        $script:scansWithFindings++
    } elseif ($result -ne 0) {
        $script:scanErrors++
        Write-Warning "Gitleaks $Mode scan failed in '$Target' (exit code $result)."
    }
}

# Inspect directories without descending into .git internals or junctions.
# A .git file marks a worktree, while HEAD plus objects marks a bare repo.
$pending = New-Object 'System.Collections.Generic.Stack[string]'
$pending.Push($scanRoot)
$repositories = New-Object 'System.Collections.Generic.List[string]'
while ($pending.Count -gt 0) {
    $directory = $pending.Pop()
    if (Test-Path -LiteralPath (Join-Path $directory '.git')) {
        $repositories.Add($directory)
    } elseif ((Test-Path -LiteralPath (Join-Path $directory 'HEAD') -PathType Leaf) -and
              (Test-Path -LiteralPath (Join-Path $directory 'objects') -PathType Container)) {
        $isBare = & $git.Source -C $directory rev-parse --is-bare-repository 2>$null
        if ($LASTEXITCODE -eq 0 -and $isBare -eq 'true') {
            $repositories.Add($directory)
        }
    }

    try {
        $children = Get-ChildItem -LiteralPath $directory -Directory -Force -ErrorAction Stop
    } catch {
        $scanErrors++
        Write-Warning "Cannot list '$directory': $($_.Exception.Message)"
        continue
    }
    foreach ($child in $children) {
        if ($child.Name -eq '.git') { continue }
        if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            $scanErrors++
            Write-Warning "Skipped linked directory '$($child.FullName)' during Git discovery."
            continue
        }
        $pending.Push($child.FullName)
    }
}

Write-Host "Scanning current files in '$scanRoot'"
Write-Host 'Secret values are redacted in the findings below.'
Invoke-LeakScan -Mode dir -Target $scanRoot -ConfigPath $exceptionConfig

foreach ($repository in ($repositories | Sort-Object -Unique)) {
    Write-Host "`nScanning all refs and reflogs in '$repository'"
    $config = if ($repository -eq $lightwaveExplorer) { $exceptionConfig } else { $null }
    Invoke-LeakScan -Mode git -Target $repository -ConfigPath $config
}

Write-Host "`nFinished. Git repositories scanned: $($repositories.Count); scans with findings: $scansWithFindings; scan errors: $scanErrors."
if ($scanErrors -gt 0) { exit 2 }
if ($scansWithFindings -gt 0) { exit 1 }
exit 0

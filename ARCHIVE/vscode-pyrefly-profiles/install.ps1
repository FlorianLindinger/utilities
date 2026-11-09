[CmdletBinding()]
param(
    [string]$CodeCommand = 'code',
    [switch]$BuildOnly
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$taskPackage = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'package.json') -Raw | ConvertFrom-Json
$taskIdentifier = "$($taskPackage.publisher).$($taskPackage.name)"
$taskDist = Join-Path $PSScriptRoot 'dist'
[IO.Directory]::CreateDirectory($taskDist) | Out-Null
$taskVsix = Join-Path $taskDist "$taskIdentifier-$($taskPackage.version).vsix"
if (Test-Path -LiteralPath $taskVsix) { Remove-Item -LiteralPath $taskVsix }

function Add-ZipText {
    param($Archive, [string]$Name, [string]$Text)
    $taskEntry = $Archive.CreateEntry($Name)
    $taskWriter = [IO.StreamWriter]::new($taskEntry.Open(), [Text.UTF8Encoding]::new($false))
    try { $taskWriter.Write($Text) } finally { $taskWriter.Dispose() }
}

$taskManifest = @"
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
<Metadata>
<Identity Language="en-US" Id="$($taskPackage.name)" Version="$($taskPackage.version)" Publisher="$($taskPackage.publisher)"/>
<DisplayName>$([Security.SecurityElement]::Escape($taskPackage.displayName))</DisplayName>
<Description xml:space="preserve">$([Security.SecurityElement]::Escape($taskPackage.description))</Description>
<Categories>Other</Categories>
<Properties>
<Property Id="Microsoft.VisualStudio.Code.Engine" Value="$($taskPackage.engines.vscode)"/>
<Property Id="Microsoft.VisualStudio.Code.ExtensionDependencies" Value="$($taskPackage.extensionDependencies -join ',')"/>
</Properties>
</Metadata>
<Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation><Dependencies/>
<Assets>
<Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/>
<Asset Type="Microsoft.VisualStudio.Services.Content.Details" Path="extension/README.md" Addressable="true"/>
</Assets>
</PackageManifest>
"@
$taskContentTypes = '<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="json" ContentType="application/json"/><Default Extension="js" ContentType="application/javascript"/><Default Extension="md" ContentType="text/markdown"/><Default Extension="vsixmanifest" ContentType="text/xml"/></Types>'
$taskArchive = [IO.Compression.ZipFile]::Open($taskVsix, [IO.Compression.ZipArchiveMode]::Create)
try {
    Add-ZipText $taskArchive 'extension.vsixmanifest' $taskManifest
    Add-ZipText $taskArchive '[Content_Types].xml' $taskContentTypes
    foreach ($taskFile in @('package.json', 'extension.js', 'profiles.js', 'README.md')) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $taskArchive, (Join-Path $PSScriptRoot $taskFile), "extension/$taskFile"
        ) | Out-Null
    }
} finally { $taskArchive.Dispose() }
Write-Host "Built: $taskVsix"
if ($BuildOnly) { return }

$taskCode = (Get-Command $CodeCommand -ErrorAction Stop).Source
& $taskCode --install-extension $taskVsix --force
if ($LASTEXITCODE -ne 0) { throw 'Install failed for the Default profile.' }
Write-Host 'Installed in profile: Default'

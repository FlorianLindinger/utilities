param([string]$LiveDumpPath)

$ErrorActionPreference = 'Stop'
$watcher = Join-Path (Split-Path $PSScriptRoot -Parent) 'run_with_crash_log.bat'
$raw = [IO.File]::ReadAllText($watcher)
$payload = $raw.Substring($raw.LastIndexOf('# POWERSHELL PAYLOAD') + '# POWERSHELL PAYLOAD'.Length)
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($payload, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors.Message -join [Environment]::NewLine) }
# Load helpers without launching the watched application or changing shortcuts.
foreach ($function in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([scriptblock]::Create($function.Extent.Text))
}
$checks = 0
function Assert-True([bool]$condition, [string]$message) {
    if (-not $condition) { throw $message }
    $script:checks++
}
$unknown = [pscustomobject]@{ AllocationFailure = $false; Note = 'Not available.' }
foreach ($code in @('0xC0000017', '0xC000012D', '0x8007000E')) {
    Assert-True ((Get-CrashDiagnosis $code $unknown)[0] -eq 'DIAGNOSIS: OUT OF MEMORY / MEMORY ALLOCATION FAILURE') "Missing memory status: $code"
}
foreach ($code in @('0xC0000409', '0xE06D7363', '0xC0000005', '0x00000008', '0x00000001')) {
    Assert-True ((Get-CrashDiagnosis $code $unknown)[0] -eq 'DIAGNOSIS: Cause not determined automatically.') "False OOM diagnosis: $code"
}
$positive = 'VCRUNTIME140!CxxThrowException+0x97' + "`r`n" + '00007ff6`c8465498  ".?AVbad_alloc@std@@"'
Assert-True (Test-DumpAllocationFailure $positive) 'Exception-record-derived bad_alloc not recognized.'
foreach ($text in @('bad allocation', 'unused .?AVbad_alloc@std@@',
    '00007ff6`c8465498  ".?AVbad_alloc@std@@"',
    ($positive.Replace('bad_alloc', 'bad_array_new_length')))) {
    Assert-True (-not (Test-DumpAllocationFailure $text)) 'Unrelated runtime text incorrectly classified.'
}
$failed = Read-DumpMemoryEvidence 'C:\CrashWatch-nonexistent\cdb.exe' 'C:\missing.dmp'
Assert-True (-not $failed.AllocationFailure -and $failed.Note -like 'Dump analysis unavailable:*') 'Missing debugger did not fail gracefully.'

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('CrashWatch-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixture
$savedEnvironment = @{}
$settings = @{
    NORMAL_EXIT_CODES = '0'; EVENT_WAIT_SECONDS = '0'; INCLUDE_EVENT_LOG = '0'
    INCLUDE_DUMPS = '1'; ANALYZE_DUMPS = '1'; DUMP_DIR = $fixture
    CONFIRMED_CRASH_ONLY = '0'; REPORT_DIR = $fixture; OPEN_REPORT = '0'
}
foreach ($name in $settings.Keys) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
    [Environment]::SetEnvironmentVariable($name, $settings[$name])
}
try {
    $reportTail = [scriptblock]::Create($payload.Substring($payload.IndexOf('$normalCodes = @(')))
    $exe = Join-Path $fixture 'Example.exe'
    $scriptFolder = $fixture
    $startedAt = Get-Date
    $finishedAt = Get-Date
    $workingDirectory = $fixture
    $processId = 123
    $launchError = $null
    # A different process's dump must never supply the diagnosis.
    [IO.File]::WriteAllBytes((Join-Path $fixture 'Example.exe.999.dmp'), [byte[]]@())
    $exitCode = -1073740791
    . $reportTail
    $content = Get-Content -LiteralPath $report
    Assert-True ($content[2] -eq 'DIAGNOSIS: Cause not determined automatically.') 'Unknown diagnosis missing from top of report.'
    Assert-True ($content[3] -eq 'Memory check: No recent dump matched this process ID.') 'Another process dump was used.'
    $exitCode = -1073741801 # STATUS_NO_MEMORY, signed process exit code.
    . $reportTail
    $content = Get-Content -LiteralPath $report
    Assert-True ($content[2] -eq 'DIAGNOSIS: OUT OF MEMORY / MEMORY ALLOCATION FAILURE') 'Memory status missing from report top.'
    $before = @(Get-ChildItem -LiteralPath $fixture -Filter '*.txt').Count
    $exitCode = 0
    . $reportTail
    Assert-True (@(Get-ChildItem -LiteralPath $fixture -Filter '*.txt').Count -eq $before) 'Clean exit created a report.'

    if ($LiveDumpPath) {
        $debugger = Find-CrashDebugger
        Assert-True ([bool]$debugger) 'Live test requires an installed Windows SDK debugger.'
        $evidence = Read-DumpMemoryEvidence $debugger $LiveDumpPath
        Assert-True $evidence.AllocationFailure "Real bad_alloc dump not detected: $($evidence.Note)"
        Assert-True ((Get-CrashDiagnosis '0xC0000409' $evidence)[0] -like 'DIAGNOSIS: LIKELY OUT OF MEMORY*') 'Real dump diagnosis missing.'
        $dumpFile = Get-Item -LiteralPath $LiveDumpPath
        if ($dumpFile.Name -notmatch '^(?<app>.+\.exe)\.(?<pid>\d+)\.dmp$') { throw 'Live test requires a standard WER dump filename.' }
        $exe = Join-Path $fixture $Matches.app
        $processId = [uint32]$Matches.pid
        $startedAt = $dumpFile.LastWriteTime.AddMinutes(-1)
        $finishedAt = $dumpFile.LastWriteTime
        $env:DUMP_DIR = $dumpFile.DirectoryName
        $exitCode = -1073740791
        . $reportTail
        $content = Get-Content -LiteralPath $report
        Assert-True ($content[2] -eq 'DIAGNOSIS: LIKELY OUT OF MEMORY / MEMORY ALLOCATION FAILURE') 'Real dump report headline missing.'
        Assert-True ($content[3] -like '*std::bad_alloc*') 'Real dump report evidence missing.'
        $timeout = Read-DumpMemoryEvidence $debugger $LiveDumpPath 1
        Assert-True (-not $timeout.AllocationFailure -and $timeout.Note -like '*timed out*') 'Debugger timeout did not fail gracefully.'
    }
} finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name])
    }
    $resolvedFixture = (Resolve-Path -LiteralPath $fixture).Path
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedFixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolvedFixture -Leaf) -notlike 'CrashWatch-tests-*') { throw 'Unexpected fixture cleanup path.' }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
Write-Output "$checks crash watcher checks passed."

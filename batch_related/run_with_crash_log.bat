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
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%  Application crash watcher%UTIL_UI_RESET%
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%============================================================%UTIL_UI_RESET%
rem --- End console presentation. ---


rem ==============================================================
rem GENERIC CRASH WATCH - SETTINGS (edit these values)
rem ==============================================================
rem Paths may be absolute (C:\Apps\MyApp\MyApp.exe) or relative
rem to THIS .bat file (e.g. .\MyApp.exe or .\bin\MyApp.exe).
rem AUTO selects the only .exe beside THIS .bat (no subfolders).
rem Zero or multiple matches abort with a warning; otherwise specify a path.
rem Quotes go OUTSIDE the name=value pair.
set "APP_EXE=auto"

rem Optional program arguments. Leave empty if none are needed.
rem Example: set "APP_ARGS=--config settings.json"
set "APP_ARGS="

rem Working directory: AUTO = folder containing the .exe.
rem Otherwise use an absolute path or a path relative to this BAT.
set "WORKING_DIR=AUTO"

rem Report directory: absolute path, or relative to this BAT.
rem If it is not writable, use %%LOCALAPPDATA%%\CrashWatch\(appname).
set "REPORT_DIR=.\CrashReports"

rem 1 = open report in Notepad ONLY after unexpected exit;
rem 0 = save report silently.
set "OPEN_REPORT=1"

rem 0 = report every exit code except those in NORMAL_EXIT_CODES.
rem 1 = report only if Windows recorded a related crash event,
rem     a new dump exists, or exit status resembles an NT exception.
rem     Launch failures always produce reports.
rem Recommended: 0 (detects abnormal exits, including taskkill /F).
set "CONFIRMED_CRASH_ONLY=0"

rem Comma-separated normal exit codes, default 0 only.
rem Example: set "NORMAL_EXIT_CODES=0,1"
set "NORMAL_EXIT_CODES=0"

rem Check Windows Application events 1000/1001 (1=yes, 0=no).
set "INCLUDE_EVENT_LOG=1"

rem Check Windows Error Reporting crash dumps (1=yes, 0=no).
rem This does NOT enable Windows crash dump generation.
set "INCLUDE_DUMPS=1"

rem Optional dump folder; AUTO checks the WER registry setting,
rem falling back to %%LOCALAPPDATA%%\CrashDumps.
set "DUMP_DIR=AUTO"

rem Seconds to allow Windows to record a fault after abnormal exit.
set "EVENT_WAIT_SECONDS=3"

rem Native Windows app-starting cursor (1=yes, 0=no).
rem Windows controls its duration and restores it automatically.
set "SHOW_STARTUP_CURSOR=1"
rem Create/update an EXE-named Debug shortcut beside this BAT (1=yes, 0=no).
rem Uses cmd.exe, this BAT, the working directory above, and the EXE icon.
rem Setting 0 leaves any previously created shortcut in place.
set "CREATE_DEBUG_SHORTCUT=1"

rem Group the Debug shortcut and launched windows on the taskbar (1=yes, 0=no).
rem AUTO reads explicit IDs from running windows or EXE shortcuts beside this BAT
rem and in the user's pinned taskbar folder; otherwise uses a stable path-based ID.
rem An explicit ID on a newly launched window is also detected automatically.
rem Set APP_USER_MODEL_ID to an explicit ID to override automatic detection.
rem Fallback grouping applies to instances launched through this watcher only.
set "GROUP_DEBUG_TASKBAR=1"
set "APP_USER_MODEL_ID=AUTO"

rem ==============================================================
rem END SETTINGS. No need to edit below this line.
rem ==============================================================

rem Double-clicking this BAT may cause a momentary console flash.
rem Use Launch_Generic_Crash_Watch_Hidden.vbs to avoid the flash.
if /I "%~1"=="--run-hidden" goto :MONITOR
set "CRASHWATCH_HIDER=%TEMP%\CrashWatch_%RANDOM%_%RANDOM%.vbs"
>"%CRASHWATCH_HIDER%" echo q = Chr(34)
>>"%CRASHWATCH_HIDER%" echo command = "cmd.exe /d /c " ^& q ^& q ^& WScript.Arguments(0) ^& q ^& " --run-hidden" ^& q
>>"%CRASHWATCH_HIDER%" echo CreateObject("WScript.Shell").Run command, 0, False
>>"%CRASHWATCH_HIDER%" echo On Error Resume Next
>>"%CRASHWATCH_HIDER%" echo CreateObject("Scripting.FileSystemObject").DeleteFile WScript.ScriptFullName, True
start "" "%SystemRoot%\System32\wscript.exe" "%CRASHWATCH_HIDER%" "%~f0"
exit /b

:MONITOR
set "CRASHWATCH_BAT=%~f0"
set "CRASHWATCH_BAT_DIR=%~dp0"
powershell.exe -STA -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop';try{$raw=[IO.File]::ReadAllText($env:CRASHWATCH_BAT);$marker='# POWERSHELL PAYLOAD';$pos=$raw.LastIndexOf($marker);if($pos -lt 0){throw 'Missing embedded PowerShell payload'};& ([scriptblock]::Create($raw.Substring($pos+$marker.Length)))}catch{$detail=($_ | Out-String);$message='CrashWatch launcher failed.';try{$log=Join-Path ([IO.Path]::GetTempPath()) ('CrashWatch_launcher_error_'+[guid]::NewGuid().ToString('N')+'.txt');[IO.File]::WriteAllText($log,((Get-Date).ToString('o')+[Environment]::NewLine+$detail));$message+=[Environment]::NewLine+'Details: '+$log}catch{$message+=[Environment]::NewLine+'Could not save error log.'};$message+=[Environment]::NewLine+$detail;try{$shell=New-Object -ComObject WScript.Shell;$null=$shell.Popup($message,0,'CrashWatch launcher error',16)}catch{[Console]::Error.WriteLine($message)};exit 1}"
exit /b

# POWERSHELL PAYLOAD
$ErrorActionPreference = 'Stop'
$scriptFolder = $env:CRASHWATCH_BAT_DIR
$startedAt = Get-Date
$finishedAt = $null
$exe = $null
$workingDirectory = $null
$exitCode = $null
$processId = $null
$launchError = $null

function Resolve-WatchPath([string]$value, [string]$root) {
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    $expanded = [Environment]::ExpandEnvironmentVariables($value.Trim().Trim('"'))
    if ([IO.Path]::IsPathRooted($expanded)) { return [IO.Path]::GetFullPath($expanded) }
    return [IO.Path]::GetFullPath((Join-Path -Path $root -ChildPath $expanded))
}

function Is-Enabled([string]$value) { return $value -eq '1' }

try {
    if ($env:APP_EXE.Trim().Trim('"') -ieq 'auto') {
        $candidates = @(Get-ChildItem -LiteralPath $scriptFolder -Filter '*.exe' -File | Sort-Object Name)
        if ($candidates.Count -ne 1) {
            $names = if ($candidates.Count) { ($candidates.Name -join [Environment]::NewLine) } else { '(none)' }
            throw "APP_EXE=auto requires exactly one .exe beside this BAT. Found $($candidates.Count) in ${scriptFolder}:$([Environment]::NewLine)$names$([Environment]::NewLine)Set APP_EXE to an explicit path to choose an executable."
        }
        $exe = $candidates[0].FullName
    } else {
        $exe = Resolve-WatchPath $env:APP_EXE $scriptFolder
    }
    if (-not $exe) { throw 'APP_EXE setting is empty.' }
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        throw "Executable not found: $exe"
    }
    if ([string]::IsNullOrWhiteSpace($env:WORKING_DIR) -or $env:WORKING_DIR -eq 'AUTO') {
        $workingDirectory = Split-Path -Path $exe -Parent
    } else {
        $workingDirectory = Resolve-WatchPath $env:WORKING_DIR $scriptFolder
    }
    if (-not (Test-Path -LiteralPath $workingDirectory -PathType Container)) {
        throw "Working directory not found: $workingDirectory"
    }
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.ComponentModel;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class CrashWatchTaskbar {
    [StructLayout(LayoutKind.Sequential)]
    struct Key { public Guid format; public uint id; }
    [StructLayout(LayoutKind.Explicit, Size=24)]
    struct Value {
        [FieldOffset(0)] public ushort type;
        [FieldOffset(8)] public IntPtr text;
    }
    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface Store {
        void GetCount(out uint count);
        void GetAt(uint index, out Key key);
        void GetValue(ref Key key, out Value value);
        void SetValue(ref Key key, ref Value value);
        void Commit();
    }
    static Key appIdKey = new Key { format = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), id = 5 };
    static Guid storeId = typeof(Store).GUID;
    [DllImport("shell32.dll", PreserveSig=false)]
    static extern void SHGetPropertyStoreForWindow(IntPtr window, ref Guid iid, out Store store);
    [DllImport("ole32.dll")] static extern int PropVariantClear(ref Value value);
    delegate bool WindowCallback(IntPtr window, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumWindows(WindowCallback callback, IntPtr data);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    public static string Warning;
    public static string SelectedId;

    static string Read(Store store) {
        Value value;
        store.GetValue(ref appIdKey, out value);
        try { return value.type == 31 ? Marshal.PtrToStringUni(value.text) : null; }
        finally { PropVariantClear(ref value); }
    }
    static void Write(Store store, string id) {
        Value value = new Value();
        if (id != null) { value.type = 31; value.text = Marshal.StringToCoTaskMemUni(id); }
        try { store.SetValue(ref appIdKey, ref value); }
        finally { PropVariantClear(ref value); }
    }
    public static string ReadLink(string path) {
        object link = Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("00021401-0000-0000-C000-000000000046")));
        try {
            ((System.Runtime.InteropServices.ComTypes.IPersistFile)link).Load(path, 0);
            return Read((Store)link);
        } finally { Marshal.ReleaseComObject(link); }
    }
    public static void WriteLink(string path, string id) {
        object link = Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("00021401-0000-0000-C000-000000000046")));
        try {
            var file = (System.Runtime.InteropServices.ComTypes.IPersistFile)link;
            file.Load(path, 2);
            Write((Store)link, id);
            file.Save(path, true);
        } finally { Marshal.ReleaseComObject(link); }
    }
    public static string ReadWindow(IntPtr window) {
        Store store;
        SHGetPropertyStoreForWindow(window, ref storeId, out store);
        try { return Read(store); } finally { Marshal.ReleaseComObject(store); }
    }
    public static void WriteWindow(IntPtr window, string id) {
        Store store;
        SHGetPropertyStoreForWindow(window, ref storeId, out store);
        try { Write(store, id); } finally { Marshal.ReleaseComObject(store); }
    }
    public static IntPtr[] Windows(uint pid) {
        var windows = new List<IntPtr>();
        EnumWindows(delegate(IntPtr window, IntPtr data) {
            uint owner; GetWindowThreadProcessId(window, out owner);
            if (owner == pid && IsWindowVisible(window)) windows.Add(window);
            return true;
        }, IntPtr.Zero);
        return windows.ToArray();
    }
    public static string FindExistingId(string exe) {
        foreach (var process in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(exe))) {
            using (process) {
                try {
                    if (!String.Equals(process.MainModule.FileName, exe, StringComparison.OrdinalIgnoreCase)) continue;
                    foreach (var window in Windows((uint)process.Id)) {
                        string id = ReadWindow(window);
                        if (!String.IsNullOrWhiteSpace(id)) return id;
                    }
                } catch { } // Exited/inaccessible processes cannot supply an ID.
            }
        }
        return null;
    }
    public static string FallbackId(string exe) {
        using (var hash = System.Security.Cryptography.SHA256.Create()) {
            byte[] bytes = hash.ComputeHash(Encoding.UTF8.GetBytes(Path.GetFullPath(exe).ToUpperInvariant()));
            return "CrashWatch.App." + BitConverter.ToString(bytes, 0, 16).Replace("-", "");
        }
    }
    public static void Update(uint pid, ref string id, ref bool detect, string link) {
        var windows = Windows(pid);
        // Inspect all windows before writing: an application may set an explicit ID
        // during startup or on a later window. Adopt the first such ID once.
        if (detect) {
            foreach (var window in windows) {
                try {
                    string found = ReadWindow(window);
                    if (!String.IsNullOrWhiteSpace(found) && found != id) {
                        id = found; detect = false;
                        if (!String.IsNullOrEmpty(link)) WriteLink(link, id);
                        break;
                    }
                } catch (Exception error) { Warning = error.Message; }
            }
        }
        SelectedId = id;
        foreach (var window in windows) {
            try { if (ReadWindow(window) != id) WriteWindow(window, id); }
            catch (Exception error) { Warning = error.Message; }
        }
    }
}

public static class CrashWatchNativeLaunch {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct SI {
        public int cb;
        public string reserved, desktop, title;
        public int x,y,cx,cy,charsX,charsY,fill,flags;
        public short show, reservedSize;
        public IntPtr reservedPtr, input, output, error;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct PI { public IntPtr process, thread; public uint pid, tid; }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa,
        IntPtr ta, bool inherit, uint flags, IntPtr env, string dir, ref SI si, out PI pi);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr h);
    public static int Run(string exe, string args, string dir, bool feedback, string appId, bool detectId, string shortcut, out uint pid) {
        var si = new SI();
        si.cb = Marshal.SizeOf(typeof(SI));
        si.flags = feedback ? 0x40 : 0; // STARTF_FORCEONFEEDBACK
        var cmd = new StringBuilder("\"" + exe + "\"");
        if (!String.IsNullOrWhiteSpace(args)) cmd.Append(" " + args);
        PI pi;
        if (!CreateProcessW(exe,cmd,IntPtr.Zero,IntPtr.Zero,false,0,IntPtr.Zero,dir,ref si,out pi))
            throw new Win32Exception(Marshal.GetLastWin32Error());
        pid = pi.pid;
        CloseHandle(pi.thread);
        try {
            uint wait;
            while ((wait = WaitForSingleObject(pi.process,250)) == 258) {
                if (!String.IsNullOrEmpty(appId)) {
                    try { CrashWatchTaskbar.Update(pi.pid, ref appId, ref detectId, shortcut); }
                    catch (Exception error) { CrashWatchTaskbar.Warning = error.Message; }
                }
            }
            if (wait != 0) throw new Win32Exception(Marshal.GetLastWin32Error());
            uint code;
            if (!GetExitCodeProcess(pi.process,out code))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            return unchecked((int)code);
        } finally { CloseHandle(pi.process); }
    }
}
'@
    # Taskbar IDs are independent of the executable icon and shortcut target.
    $taskbarId = $null
    $detectWindowId = $false
    $taskbarShortcut = $null
    if (Is-Enabled $env:GROUP_DEBUG_TASKBAR) {
        if ($env:APP_USER_MODEL_ID -and $env:APP_USER_MODEL_ID -ine 'AUTO') {
            $taskbarId = $env:APP_USER_MODEL_ID.Trim()
            if ([string]::IsNullOrWhiteSpace($taskbarId) -or $taskbarId.Length -gt 128 -or $taskbarId -match '\s') {
                throw 'APP_USER_MODEL_ID must contain 1-128 characters without whitespace.'
            }
        } else {
            $taskbarId = [CrashWatchTaskbar]::FindExistingId($exe)
            if (-not $taskbarId) {
                $linkShell = New-Object -ComObject WScript.Shell
                $linkFolders = @($scriptFolder, (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'))
                $foundIds = @(
                    foreach ($folder in $linkFolders) {
                        foreach ($file in (Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -File -ErrorAction SilentlyContinue)) {
                            try {
                                $candidate = $linkShell.CreateShortcut($file.FullName)
                                if ($candidate.TargetPath -ieq $exe) {
                                    $id = [CrashWatchTaskbar]::ReadLink($file.FullName)
                                    if ($id) { $id }
                                }
                            } catch { } # Unreadable unrelated shortcuts are optional hints.
                        }
                    }
                ) | Sort-Object -Unique
                if (@($foundIds).Count -eq 1) { $taskbarId = @($foundIds)[0] }
            }
            if (-not $taskbarId) {
                $taskbarId = [CrashWatchTaskbar]::FallbackId($exe)
                $detectWindowId = $true
            }
        }
    }
    if (Is-Enabled $env:CREATE_DEBUG_SHORTCUT) {
        try {
            $shortcutPath = Join-Path $scriptFolder ([IO.Path]::GetFileNameWithoutExtension($exe) + ' Debug.lnk')
            $shortcutShell = New-Object -ComObject WScript.Shell
            $shortcut = $shortcutShell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = Join-Path ([Environment]::SystemDirectory) 'cmd.exe'
            $shortcut.Arguments = '/d /c ""' + $env:CRASHWATCH_BAT + '""'
            $shortcut.WorkingDirectory = $workingDirectory
            $shortcut.IconLocation = $exe + ',0'
            $shortcut.Description = 'Launch ' + [IO.Path]::GetFileNameWithoutExtension($exe) + ' with crash logging'
            $shortcut.Save()
            # Clear an old explicit ID when grouping is disabled.
            [CrashWatchTaskbar]::WriteLink($shortcutPath, $taskbarId)
            $taskbarShortcut = $shortcutPath
        } catch {
            # A shortcut failure must not prevent the application from starting.
            $shortcutWarning = "Could not create the Debug shortcut. The application will still start.$([Environment]::NewLine)$($_.Exception.Message)"
            try {
                $warningShell = New-Object -ComObject WScript.Shell
                $null = $warningShell.Popup($shortcutWarning, 0, 'CrashWatch - shortcut warning', 48)
            } catch { Write-Warning $shortcutWarning }
        }
    }
    # Request native startup feedback without changing the system cursor scheme.
    $nativePid = [uint32]0
    $exitCode = [CrashWatchNativeLaunch]::Run($exe, $env:APP_ARGS,
        $workingDirectory, (Is-Enabled $env:SHOW_STARTUP_CURSOR),
        $taskbarId, $detectWindowId, $taskbarShortcut, [ref]$nativePid)
    $processId = $nativePid
    if ([CrashWatchTaskbar]::Warning) {
        try {
            $warningShell = New-Object -ComObject WScript.Shell
            $null = $warningShell.Popup(('Taskbar grouping could not be fully applied: ' + [CrashWatchTaskbar]::Warning), 0, 'CrashWatch - taskbar warning', 48)
        } catch { Write-Warning ('Taskbar grouping: ' + [CrashWatchTaskbar]::Warning) }
    }
} catch {
    $launchError = $_.ToString()
    # Launch/configuration failures always warn, even when OPEN_REPORT=0.
    $warningShell = New-Object -ComObject WScript.Shell
    $null = $warningShell.Popup($launchError, 0, 'CrashWatch - application not started', 48)
} finally {
    $finishedAt = Get-Date
}

$normalCodes = @(
    $env:NORMAL_EXIT_CODES -split ',' | ForEach-Object {
        $parsed = [long]0
        if ([long]::TryParse($_.Trim(), [ref]$parsed)) { $parsed }
    }
)
if ($null -eq $launchError -and $null -ne $exitCode -and $exitCode -in $normalCodes) {
    return  # Clean close (including the X button): nothing saved or shown.
}

$delay = 3
$parsedDelay = 0
if ([int]::TryParse($env:EVENT_WAIT_SECONDS, [ref]$parsedDelay)) {
    $delay = [Math]::Min(60, [Math]::Max(0, $parsedDelay))
}
if ($delay -gt 0) { Start-Sleep -Seconds $delay }

$appFileName = if ($exe) { [IO.Path]::GetFileName($exe) } else { 'Unknown.exe' }
$appName = [IO.Path]::GetFileNameWithoutExtension($appFileName)
$safeName = [regex]::Replace($appName, '[^a-zA-Z0-9_.-]', '_')

$events = @()
if (Is-Enabled $env:INCLUDE_EVENT_LOG) {
    $namePattern = [regex]::Escape($appFileName)
    try {
        $events = @(
            Get-WinEvent -FilterHashtable @{
                LogName   = 'Application'
                Id        = @(1000, 1001)
                StartTime = $startedAt.AddSeconds(-5)
            } -ErrorAction SilentlyContinue |
                Where-Object { $_.Message -match $namePattern } |
                Sort-Object TimeCreated -Descending |
                Select-Object -First 8
        )
    } catch { $events = @() }
}

$dumpFolder = $null
if (Is-Enabled $env:INCLUDE_DUMPS) {
    if ($env:DUMP_DIR -and $env:DUMP_DIR -ne 'AUTO') {
        $dumpFolder = Resolve-WatchPath $env:DUMP_DIR $scriptFolder
    } else {
        $keys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\$appFileName"
            'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps'
        )
        foreach ($key in $keys) {
            try {
                $setting = Get-ItemProperty -LiteralPath $key -Name DumpFolder -ErrorAction Stop
                if ($setting.DumpFolder) {
                    $dumpFolder = [Environment]::ExpandEnvironmentVariables([string]$setting.DumpFolder)
                    break
                }
            } catch { }
        }
        if (-not $dumpFolder) {
            $dumpFolder = Join-Path $env:LOCALAPPDATA 'CrashDumps'
        }
    }
}

$dumps = @()
if ($dumpFolder) {
    try {
        $dumps = @(
            Get-ChildItem -LiteralPath $dumpFolder -Filter "$appFileName*.dmp" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $startedAt.AddSeconds(-5) } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 8
        )
    } catch { $dumps = @() }
}

$hexCode = if ($null -ne $exitCode) {
    '0x{0:X8}' -f ([long]$exitCode -band 4294967295)
} else { '(unavailable)' }
$isExceptionCode = $false
if ($null -ne $exitCode) {
    $unsigned = [long]$exitCode -band 4294967295
    $isExceptionCode = (($unsigned -band 4026531840) -eq 3221225472)
}
$hasWER = ($events.Count -gt 0 -or $dumps.Count -gt 0)
if ((Is-Enabled $env:CONFIRMED_CRASH_ONLY) -and -not $launchError -and -not $hasWER -and -not $isExceptionCode) {
    return
}

$requestedReportDirectory = Resolve-WatchPath $env:REPORT_DIR $scriptFolder
if (-not $requestedReportDirectory) { $requestedReportDirectory = Join-Path $scriptFolder 'CrashReports' }
try {
    New-Item -ItemType Directory -Path $requestedReportDirectory -Force -ErrorAction Stop | Out-Null
    $reportDirectory = $requestedReportDirectory
} catch {
    $reportDirectory = Join-Path (Join-Path $env:LOCALAPPDATA 'CrashWatch') $safeName
    New-Item -ItemType Directory -Path $reportDirectory -Force -ErrorAction Stop | Out-Null
}
$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss_fff'
$report = Join-Path $reportDirectory "${safeName}_unexpected_exit_${timestamp}.txt"
$elapsed = if ($finishedAt) { '{0:N1} seconds' -f ($finishedAt - $startedAt).TotalSeconds } else { 'unknown' }

$reportLines = @(
    "$appFileName - unexpected termination report"
    ('=' * 60)
    "Report created: $((Get-Date).ToString('o'))"
    "Executable: $exe"
    "Arguments: $($env:APP_ARGS)"
    "Working directory: $workingDirectory"
    "Process ID: $processId"
    "Started: $($startedAt.ToString('o'))"
    "Ended: $($finishedAt.ToString('o'))"
    "Elapsed: $elapsed"
    "Exit code (decimal): $exitCode"
    "Exit code (hex): $hexCode"
    "Windows: $([Environment]::OSVersion.VersionString)"
    ''
    'A nonzero exit is not necessarily an application crash.'
    'A forced termination (taskkill /F) may produce no Windows crash event or dump.'
    ''
    'LAUNCH ERROR (if any)'
    $(if ($launchError) { $launchError } else { '(none)' })
    ''
    'WINDOWS APPLICATION EVENT LOG (1000/1001)'
    $(if (-not (Is-Enabled $env:INCLUDE_EVENT_LOG)) { '(disabled)' }
      elseif ($events.Count -eq 0) { '(no matching events found)' }
      else { $events | ForEach-Object { "--- Event $($_.Id), $($_.TimeCreated), $($_.ProviderName) ---`r`n$($_.Message)" } })
    ''
    "CRASH DUMPS (folder: $dumpFolder)"
    $(if (-not (Is-Enabled $env:INCLUDE_DUMPS)) { '(disabled)' }
      elseif ($dumps.Count -eq 0) { '(no recent dumps found)' }
      else { $dumps | ForEach-Object { "{0} ({1:N1} MB)" -f $_.FullName, ($_.Length / 1MB) } })
)
$reportLines | Set-Content -LiteralPath $report -Encoding UTF8
if (Is-Enabled $env:OPEN_REPORT) {
    Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$report`"" | Out-Null
}

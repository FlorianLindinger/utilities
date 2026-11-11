@echo off & setlocal enabledelayedexpansion
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
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%  Archive: Convert batch to exe%UTIL_UI_RESET%
if not defined UTILITIES_QUIET >&2 echo(%UTIL_UI_INFO%============================================================%UTIL_UI_RESET%
rem --- End console presentation. ---


:: ==============================================================================
:: DESCRIPTION: Compiles a Batch file into a standalone EXE. 
::              The script is embedded inside the EXE and extracted at runtime.
:: USAGE: convert_batch_to_exe.bat [batch_path] [icon_path] [output_name]
:: If args are omitted, the script will attempt to auto-detect them in current folder
:: ==============================================================================

:: --- 1. Argument Handling & Auto-Detection ---
set "target_batch=%~1"
set "target_icon=%~2"
set "output_exe=%~3"

:: Auto-detect Batch
if "%target_batch%"=="" (
    set "b_count=0"
    for %%f in (*.bat) do (
        if /i not "%%f"=="%~nx0" (
            set /a b_count+=1
            set "target_batch=%%f"
        )
    )
    if !b_count! equ 1 (
        echo:%UTIL_UI_INFO%[+] Auto-detected Batch: !target_batch!%UTIL_UI_RESET%
    ) else (
        echo:%UTIL_UI_ERROR%[Error] No batch file specified and couldn't auto-detect a unique one.%UTIL_UI_RESET%
        echo:%UTIL_UI_WARN%Press any key to exit.%UTIL_UI_RESET%
        pause > nul
        exit /b 1
    )
)

:: Set default output name
if "%output_exe%"=="" (
    set "output_exe=%~n1.exe"
    if "!output_exe!"==".exe" set "output_exe=!target_batch:~0,-4!.exe"
) else (
    if /i "%output_exe:~-4%" neq ".exe" set "output_exe=%output_exe%.exe"
)

:: Auto-detect Icon
if "%target_icon%"=="" (
    set "i_count=0"
    for %%f in (*.ico) do (
        set /a i_count+=1
        set "target_icon=%%f"
    )
    if !i_count! equ 1 (
        echo:%UTIL_UI_INFO%[+] Auto-detected Icon: !target_icon!%UTIL_UI_RESET%
    ) else (
        echo:%UTIL_UI_ERROR%[Error] No icon file specified and couldn't auto-detect a unique one.%UTIL_UI_RESET%
        echo:%UTIL_UI_WARN%Press any key to exit.%UTIL_UI_RESET%
        pause > nul
        exit /b 1
    )
)

:: --- 2. Setup Paths ---
set "csc_path=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
set "tmp_cs_file=%temp%\embedded_maker_%random%.cs"

if not exist "%csc_path%" (
    echo:%UTIL_UI_ERROR%[!] Error: C# Compiler not found.%UTIL_UI_RESET%
    echo:%UTIL_UI_WARN%Press any key to exit.%UTIL_UI_RESET%
    pause > nul
    exit /b 1
)

:: --- 3. Create Temporary C# Source ---
:: This code extracts the embedded 'Internal.bat' to %TEMP%, runs it, and deletes it.
(
echo using System;
echo using System.IO;
echo using System.Reflection;
echo using System.Diagnostics;
echo class Program {
echo     static void Main^(string[] args^) {
echo         string resName = "Internal.bat";
echo         string tempFile = Path.Combine^(Path.GetTempPath^(^), Path.GetRandomFileName^(^) + ".bat"^);
echo         Assembly assembly = Assembly.GetExecutingAssembly^(^);
echo         using ^(Stream s = assembly.GetManifestResourceStream^(resName^)^)
echo         using ^(FileStream fs = new FileStream^(tempFile, FileMode.Create^)^) {
echo             s.CopyTo^(fs^);
echo         }
echo         ProcessStartInfo psi = new ProcessStartInfo^(tempFile, string.Join^(" ", args^)^);
echo         psi.CreateNoWindow = false;
echo         psi.UseShellExecute = false;
echo         try {
echo             Process p = Process.Start^(psi^);
echo             p.WaitForExit^(^);
echo         } finally {
echo             if ^(File.Exists^(tempFile^)^) File.Delete^(tempFile^);
echo         }
echo     }
echo }
) > "%tmp_cs_file%"

:: --- 4. Compile with Resource Embedding ---
echo.
echo:%UTIL_UI_INFO%===========================================%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%EMBEDDING: %target_batch%%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%ICON:      %target_icon%%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%OUTPUT:    %output_exe%%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%===========================================%UTIL_UI_RESET%
echo:%UTIL_UI_INFO%Compiling standalone binary...%UTIL_UI_RESET%

:: The /resource flag is what actually puts the batch file inside the EXE
"%csc_path%" /out:"!output_exe!" /target:winexe /win32icon:"%target_icon%" /resource:"%target_batch%",Internal.bat "%tmp_cs_file%" /nologo

if %errorlevel% equ 0 (
    echo.
    echo:%UTIL_UI_OK%[Success] Standalone "!output_exe!" created.%UTIL_UI_RESET%
) else (
    echo.
    echo:%UTIL_UI_ERROR%[Error] Compilation failed.%UTIL_UI_RESET%
)

:: --- 5. Cleanup ---
if exist "%tmp_cs_file%" del "%tmp_cs_file%"
echo:%UTIL_UI_WARN%Press any key to exit.%UTIL_UI_RESET%
pause > nul
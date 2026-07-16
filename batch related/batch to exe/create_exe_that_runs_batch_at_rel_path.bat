@echo off & setlocal enabledelayedexpansion

:: ==============================================================================
:: DESCRIPTION: Creates an EXE with a custom icon.
::              The resulting EXE runs the batch file relative to its own 
::              location (or via absolute path if specified).
:: USAGE: create_exe_that_runs_batch_at_rel_path.bat [batch_path] [icon_path] [output_name]
:: If args are omitted, the script will attempt to auto-detect them in current folder
:: ==============================================================================

:: --- 1. Argument Handling & Auto-Detection ---
set "target_batch=%~1"
set "target_icon=%~2"
set "output_exe=%~3"

:: Auto-detect Batch if not provided
if "%target_batch%"=="" (
    set "b_count=0"
    for %%f in (*.bat) do (
        if /i not "%%f"=="%~nx0" (
            set /a b_count+=1
            set "target_batch=%%f"
        )
    )
    if !b_count! equ 1 (
        echo [+] Auto-detected Batch: !target_batch!
    ) else (
        echo [Error] No batch file specified and couldn't auto-detect a unique one.
        echo Press any key to exit.
        pause > nul
        exit /b 1
    )
)

:: Set default output name based on batch name if not provided
if "%output_exe%"=="" (
    set "output_exe=%~n1.exe"
    if "!output_exe!"==".exe" set "output_exe=!target_batch:~0,-4!.exe"
) else (
    if /i "%output_exe:~-4%" neq ".exe" (
        set "output_exe=%output_exe%.exe"
    )
)

:: Auto-detect Icon if not provided
if "%target_icon%"=="" (
    set "i_count=0"
    for %%f in (*.ico) do (
        set /a i_count+=1
        set "target_icon=%%f"
    )
    if !i_count! equ 1 (
        echo [+] Auto-detected Icon: !target_icon!
    ) else (
        echo [Error] No icon file specified and couldn't auto-detect a unique one.
        echo Press any key to exit.
        pause > nul
        exit /b 1
    )
)

:: --- 2. Setup Paths ---
set "csc_path=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
set "tmp_cs_file=%temp%\tmp_launcher_%random%.cs"

if not exist "%csc_path%" (
    echo [!] Error: C# Compiler (csc.exe^) not found. Ensure .NET 4.0+ is installed.
    echo Press any key to exit.
    pause > nul
    exit /b 1
)

:: --- 3. Create Temporary C# Source ---
:: Note: We use @"" strings in C# to handle backslashes in paths correctly.
(
echo using System;
echo using System.Diagnostics;
echo using System.IO;
echo class Program {
echo     static void Main^(^) {
echo         string exePath = AppDomain.CurrentDomain.BaseDirectory;
echo         string batchPath = Path.Combine^(exePath, @"%target_batch%"^);
echo         ProcessStartInfo psi = new ProcessStartInfo^("cmd.exe", "/c \"\"" + batchPath + "\"\""^);
echo         psi.CreateNoWindow = false;
echo         psi.UseShellExecute = false;
echo         try { Process.Start^(psi^); } catch { }
echo     }
echo }
) > "%tmp_cs_file%"

:: --- 4. Compile ---
echo.
echo ===========================================
echo Target: %target_batch%
echo Icon:   %target_icon%
echo Output: %output_exe%
echo ===========================================
echo Compiling...

"%csc_path%" /out:"!output_exe!" /target:winexe /win32icon:"%target_icon%" "%tmp_cs_file%" /nologo

echo ===========================================

if %errorlevel% equ 0 (
    echo.
    echo [Success] "!output_exe!" created successfully.
) else (
    echo.
    echo [Error] Compilation failed. Check if the icon is a valid .ico file.
)

:: --- 5. Cleanup ---
if exist "%tmp_cs_file%" del "%tmp_cs_file%"
echo Press any key to exit.
pause > nul
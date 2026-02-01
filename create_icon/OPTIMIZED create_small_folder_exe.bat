@echo off
setlocal enabledelayedexpansion

:: measure start time
call :count_duration

:: find python file to be compiled
for %%f in ("*.py") do (
    set "python_file=%%f"
    set "file_name=%%~nf"
    echo Compiling to folder for small filesize: !python_file!
    echo.
    goto :found
)
:found

:: set variables
set "ending=.py_small_folder"
set "build_folder_path=%file_name%%ending%.build"
set "tmp_venv_name=%temp%\tmp_venv_for_compilation"
set "tmp_requirements_file=%temp%\tmp_requirements_for_compilation.txt"

:: make build_folder_path absolute for prints
call :set_abs_path "%build_folder_path%" "build_folder_path"

:: create clean virtual environment
echo ====================================================
echo Creating clean virual environment for compilation...
echo.
rmdir /s /q "%tmp_venv_name%" > nul 2>&1  
python -m venv "%tmp_venv_name%"
call "%tmp_venv_name%\Scripts\activate.bat"

:: install needed packages for compilation
echo ============================================
echo Installing pipreqs to find needed packages...
echo.
pip install pipreqs --disable-pip-version-check
mkdir tmp_pipreqs
copy "%python_file%" tmp_pipreqs\
python -m pipreqs.pipreqs tmp_pipreqs --force --savepath "%tmp_requirements_file%"
rmdir /s /q tmp_pipreqs
echo.
echo ==========================================
echo Required packages for code:
echo ==========================================
type "%tmp_requirements_file%"
echo ==========================================
echo.
echo ============================================
echo Installing required packages...
echo.
pip install -r "%tmp_requirements_file%"  --disable-pip-version-check
echo ============================================
echo Installing nuitka (compilation program)...
echo.
pip install nuitka  --disable-pip-version-check

:: compile
echo.
echo ==========
echo Compiling:
echo.
REM MAX OPTIMIZATION FLAGS FOR SMALLEST SIZE:
REM --onefile: Create a single compressed executable file (not a folder)
REM --jobs=%NUMBER_OF_PROCESSORS%: Use multiple jobs to speed up compilation
REM --lto=yes: Link Time Optimization (smaller binary, faster execution)
REM --deployment: Disables safety checks meant for development
REM --python-flag=no_docstrings,no_asserts,-OO: Strip docstrings, asserts, and optimize bytecode
REM --prefer-source-code: Keep some modules as bytecode instead of compiled (smaller)
REM --nofollow-import-to: Don't follow imports to these modules (excludes them from exe)
python -m nuitka ^
--nofollow-import-to=PIL.ImageQt ^
--nofollow-import-to=PIL.ImageShow ^
--nofollow-import-to=PIL.ImageWin ^
--nofollow-import-to=PIL.ImageGrab ^
  --include-module=PIL.PngImagePlugin ^
  --nofollow-import-to=PIL.GifImagePlugin ^
  --nofollow-import-to=PIL.JpegImagePlugin ^
  --nofollow-import-to=PIL.TiffImagePlugin ^
  --nofollow-import-to=PIL.WebPImagePlugin ^
  --nofollow-import-to=PIL.PdfImagePlugin ^
  --nofollow-import-to=PIL.PpmImagePlugin ^
  --nofollow-import-to=PIL.SgiImagePlugin ^
  --nofollow-import-to=PIL.MpegImagePlugin ^
    --nofollow-import-to=PIL.ImageTk ^
  --nofollow-import-to=PIL._tkinter_finder ^
  --nofollow-import-to=PIL._imagingtkinter ^
  --nofollow-import-to=PIL._imagingcms ^
  --nofollow-import-to=PIL.ImageCms ^
    --nofollow-import-to=ssl ^
  --nofollow-import-to=_ssl ^
  --nofollow-import-to=_socket ^
  --nofollow-import-to=socket ^
  --nofollow-import-to=_hashlib ^
  --nofollow-import-to=hashlib ^
  --nofollow-import-to=cryptography ^
  --include-module=PIL.IcoImagePlugin ^
  --nofollow-import-to=PIL.BlpImagePlugin ^
  --nofollow-import-to=PIL.BufrStubImagePlugin ^
  --nofollow-import-to=PIL.CurImagePlugin ^
  --nofollow-import-to=PIL.DcxImagePlugin ^
  --nofollow-import-to=PIL.DdsImagePlugin ^
  --nofollow-import-to=PIL.EpsImagePlugin ^
  --nofollow-import-to=PIL.FitsImagePlugin ^
  --nofollow-import-to=PIL.FliImagePlugin ^
  --nofollow-import-to=PIL.FpxImagePlugin ^
  --nofollow-import-to=PIL.FtexImagePlugin ^
  --nofollow-import-to=PIL.GbrImagePlugin ^
  --nofollow-import-to=PIL.GdImageFile ^
  --nofollow-import-to=PIL.GifImagePlugin ^
  --nofollow-import-to=PIL.GribStubImagePlugin ^
  --nofollow-import-to=PIL.Hdf5StubImagePlugin ^
  --nofollow-import-to=PIL.IcnsImagePlugin ^
  --nofollow-import-to=PIL.ImImagePlugin ^
  --nofollow-import-to=PIL.ImtImagePlugin ^
  --nofollow-import-to=PIL.IptcImagePlugin ^
  --nofollow-import-to=PIL.JpegImagePlugin ^
  --nofollow-import-to=PIL.Jpeg2KImagePlugin ^
  --nofollow-import-to=PIL.McIdasImagePlugin ^
  --nofollow-import-to=PIL.MicImagePlugin ^
  --nofollow-import-to=PIL.MpegImagePlugin ^
  --nofollow-import-to=PIL.MpoImagePlugin ^
  --nofollow-import-to=PIL.MspImagePlugin ^
  --nofollow-import-to=PIL.PalmImagePlugin ^
  --nofollow-import-to=PIL.PcdImagePlugin ^
  --nofollow-import-to=PIL.PcxImagePlugin ^
  --nofollow-import-to=PIL.PdfImagePlugin ^
  --nofollow-import-to=PIL.PixarImagePlugin ^
  --nofollow-import-to=PIL.PpmImagePlugin ^
  --nofollow-import-to=PIL.PsdImagePlugin ^
  --nofollow-import-to=PIL.QoiImagePlugin ^
  --nofollow-import-to=PIL.SgiImagePlugin ^
  --nofollow-import-to=PIL.SpiderImagePlugin ^
  --nofollow-import-to=PIL.SunImagePlugin ^
  --nofollow-import-to=PIL.TgaImagePlugin ^
  --nofollow-import-to=PIL.TiffImagePlugin ^
  --nofollow-import-to=PIL.WebPImagePlugin ^
  --nofollow-import-to=PIL.WmfImagePlugin ^
  --nofollow-import-to=PIL.XbmImagePlugin ^
  --nofollow-import-to=PIL.XpmImagePlugin ^
  --nofollow-import-to=_wmi ^
  --nofollow-import-to=wmi ^
  --nofollow-import-to=_lzma ^
  --nofollow-import-to=lzma ^
  --nofollow-import-to=_bz2 ^
  --nofollow-import-to=bz2 ^
  --include-module=PIL.BmpImagePlugin ^
--nofollow-import-to=unicodedata ^
--nofollow-import-to=_wmi ^
--nofollow-import-to=*.tests ^
--nofollow-import-to=pytest ^
--nofollow-import-to=unittest ^
--nofollow-import-to=IPython ^
--nofollow-import-to=setuptools ^
--nofollow-import-to=distutils ^
--nofollow-import-to=tkinter ^
--nofollow-import-to=email ^
--nofollow-import-to=xml ^
--nofollow-import-to=http ^
--nofollow-import-to=urllib ^
--noinclude-data-files="**/*.pyi" ^
--noinclude-data-files="**/*.dist-info/**" ^
--noinclude-data-files="**/*.egg-info/**" ^
--noinclude-data-files="**/tests/**" ^
--noinclude-data-files="**/__pycache__/**" ^
--lto=yes ^
--deployment ^
--python-flag=no_docstrings,no_asserts,-OO ^
--prefer-source-code ^
--jobs=%NUMBER_OF_PROCESSORS% ^
--assume-yes-for-downloads ^
--output-dir="%build_folder_path%" ^
--output-filename="run.exe" ^
--standalone "%python_file%"
echo.
echo ===========================
echo Compilation over
echo ===========================
echo.

:: print execution duration
call :count_duration "Execution Time:"

:: print end message
echo.
if exist "%build_folder_path%\%file_name%.dist" (
    echo ============================================
    echo EXE folder sucessfully created if no problems above: "%build_folder_path%\%file_name%.dist"
    call :print_size "%build_folder_path%\%file_name%.dist"
    echo =========================================
    echo.
    echo Analyzing folder contents...
    call :analyze_dist_folder "%build_folder_path%\%file_name%.dist"
    echo =========================================
) else (
    echo ============================================
    echo [Error] Compilation failed^! Check output above.
    echo ============================================
    echo Aborting. Press any key to exit
    PAUSE > nul
    exit /b 1
)

:: cleanup temporary files
call deactivate
rmdir /s /q "%tmp_venv_name%" > nul 2>&1  

:: wait for user to press any key and exit
echo.
echo Press any key to exit
PAUSE > nul
exit /b 0

:: ====================
:: ==== FUNCTIONS: ====
:: ====================

::::::::::::::::::::::::::::::::::::::::::::::::
:: function to call twice to get printed the duration between the two calls. Arg for second call gives the text before print of e.g. " 18.2 s" (default "Duration:").
::::::::::::::::::::::::::::::::::::::::::::::::
:count_duration
setlocal enabledelayedexpansion
rem %TIME% ? HH:MM:SScc by removing the comma
set "t=%time:,=%"
rem HH = characters 0 1
set "HH=!t:~0,2!"
rem MM = characters 3 4
set "MM=!t:~3,2!"
rem SS = characters 6 7
set "SS=!t:~6,2!"
rem CC = characters 9 2 (centiseconds)
set "CC=!t:~9,2!"
rem calculate centiseconds since midnight
set /a total=(HH*3600 + MM*60 + SS)*100 + CC
REM set global variable to current time if unset or print time passed since start if already set and reset afterwards
if "%count_time_s_start%"=="" (
    endlocal & set "count_time_s_start=%total%"
) else (
    set /a diff=%total%-%count_time_s_start%
    if !diff! lss 0 set /a diff+=24*60*60*100
    set /a SEC=diff/100
    set /a CS=diff%%100
    if "%~1"=="" ( set "text=Duration:"
    ) else ( set "text=%~1" )
    echo !text! !SEC!.!CS! s
    endlocal & set "count_time_s_start="
)
exit /b 0

:: =============================================

::::::::::::::::::::::::::::::::::::::::::::::::
:: function that prints e.g. "{arg2} 40.0 MB" ({arg2} default: "Size:") for first arg = file or folder path. Converts to approprate GB/MB/...
::::::::::::::::::::::::::::::::::::::::::::::::
:print_size
setlocal enabledelayedexpansion
rem %1 = path to the file or folder
set "item_path=%~1"
if not exist "%item_path%" (
    echo File/Folder not found for size determination: %item_path%
    exit /b 1
)
if "%~2"=="" ( set "text=Size:"
) else ( set "text=%~2" )
FOR /F "usebackq tokens=*" %%G IN (`powershell -ExecutionPolicy Bypass -Command "$Path = '%item_path%'; $Item = Get-Item -LiteralPath $Path; $1MB = 1048576; $1GB = 1073741824; if ($Item.PSIsContainer) { $B = (Get-ChildItem -Recurse -File -LiteralPath $Path | Measure-Object -Sum Length).Sum; } else { $B = $Item.Length; } if (-not $B) { $B = 0 }; if ($B -ge $1GB) { '{0:N1} GB' -f ($B / $1GB) } elseif ($B -ge $1MB) { '{0:N1} MB' -f ($B / $1MB) } else { '{0:N0} Bytes' -f $B }"`) DO (
    echo %text% %%G 
)
endlocal
exit /b 0

:: =============================================

::::::::::::::::::::::::::::::::::::::::::::::::
:: function that converts relative (to current working directory) path {arg1} to absolute and sets it to variable {arg2}. Works for empty path {arg1} which then sets the current working directory to variable {arg2}. Raises error if {arg2} is missing:
:: Usage:
::    call :set_abs_path "%some_path%" "some_path"
::::::::::::::::::::::::::::::::::::::::::::::::
:set_abs_path
    if "%~2"=="" (
        echo [Error] Second argument is missing for :set_abs_path function in "%~f0". (First argument was "%~1"^). 
        echo Aborting. Press any key to exit.
        pause > nul
        exit /b 1
    )
    if "%~1"=="" (
        set "%~2=%CD%"
    ) else (
	    set "%~2=%~f1"
    )
goto :EOF

:: =================================================

::::::::::::::::::::::::::::::::::::::::::::::::
:: function that prints the top 10 largest files/folders inside the dist folder
::::::::::::::::::::::::::::::::::::::::::::::::
:analyze_dist_folder
setlocal
set "dist_path=%~1"
echo.
echo Top 10 space-hogs in distribution:
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$path = '%dist_path%';" ^
    "Get-ChildItem -Path $path | Select-Object Name, @{Name='Size(MB)';Expression={ " ^
    "  if ($_.PSIsContainer) { " ^
    "    $sum = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; " ^
    "    if ($sum) { [Math]::Round($sum / 1MB, 2) } else { 0 } " ^
    "  } else { [Math]::Round($_.Length / 1MB, 2) } " ^
    "}}, @{Name='Type';Expression={ if($_.PSIsContainer){'Folder'}else{'File'} }} | " ^
    "Sort-Object 'Size(MB)' -Descending | Select-Object -First 10 | Format-Table -AutoSize"
endlocal
exit /b 0

:: =================================================

@echo off
setlocal enabledelayedexpansion

:: measure start time
call :count_duration

:: Install Nuitka and Zstandard
echo Installing/Updating Nuitka...
python -m pip install nuitka zstandard --upgrade
echo.

:: Find python file
for %%f in ("*.py") do (
    set "python_file=%%f"
    set "file_name=%%~nf"
    echo Compiling: !python_file!
    echo.
    goto :found
)
:found

:: Delete old exe
if exist "%file_name%.exe" del "%file_name%.exe"

:: --- MAX OPTIMIZATION FLAGS FOR SMALLEST SIZE ---
:: --onefile: Create a single compressed executable file (not a folder)
:: --lto=yes: Link Time Optimization (smaller binary, faster execution)
:: --deployment: Disables safety checks meant for development
:: --python-flag=no_docstrings,no_asserts,-OO: Strip docstrings, asserts, and optimize bytecode
:: --prefer-source-code: Keep some modules as bytecode instead of compiled (smaller)
:: --nofollow-import-to: Don't follow imports to these modules (excludes them from exe)

python -m nuitka ^
  --onefile ^
  --lto=yes ^
  --deployment ^
  --python-flag=no_docstrings,no_asserts,-OO ^
  --prefer-source-code ^
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
  --assume-yes-for-downloads ^
  --remove-output ^
  --output-dir=. ^
  --output-filename="%file_name%_py.exe" ^
  "%python_file%"

:: print end message
echo.
if exist "%file_name%_py.exe" (
    echo ============================================
    echo SUCCESS! Optimized EXE created: %file_name%_py.exe
    echo ============================================
) else (
    echo ============================================
    echo ERROR: Build failed! Check output above.
    echo ============================================
)

:: print execution duration
call :count_duration

:: wait for key press and exit
echo.
echo Press any key to exit
PAUSE > nul

exit /b 0

:: ====================
:: ==== FUNCTIONS: ====
:: ====================

:count_duration
:: call twice to get printed the duration between the two calls
setlocal enabledelayedexpansion
rem %TIME% ? HH:MM:SScc by removing the comma
set "t=%time:,=%"
rem HH = characters 0–1
set "HH=!t:~0,2!"
rem MM = characters 3–4
set "MM=!t:~3,2!"
rem SS = characters 6–7
set "SS=!t:~6,2!"
rem CC = characters 9–2 (centiseconds)
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
    echo Passed Time: !SEC!.!CS! s
    endlocal & set "count_time_s_start="
)
exit /b 0

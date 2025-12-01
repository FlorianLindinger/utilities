@ECHO OFF
:: ===================
:: ==== Test Area ====
:: ===================




EXIT /B
:: ===================

:: ====================
:: ==== Functions: ====
:: ====================

::::::::::::::::::::::::::::::::::::::::::::::::
:: function that makes relative path (relative to current working directory) to :: absolute if not already. Works for empty path (relative) path:
:: Usage:
::    call :make_absolute_path_if_relative "%some_path%"
::    set "abs_path=%output%"
::::::::::::::::::::::::::::::::::::::::::::::::
:make_absolute_path_if_relative
    if "%~1"=="" (
        set "OUTPUT=%CD%"
    ) else (
	    set "OUTPUT=%~f1"
    )
goto :EOF
:: =================================================
:: =================================================


::::::::::::::::::::::::::::::::::::::::::::::::
:: function that prompts user with "Enter y/n for Yes/No" and sets OUTPUT=1 for y and OUTPUT=0 for n.
::::::::::::::::::::::::::::::::::::::::::::::::
:prompt_user
	CHOICE /c YN /m Delete? Enter y/n for Yes/No
	IF %ERRORLEVEL%==1 (
		set "OUTPUT=1"
	) else (
		set "OUTPUT=0"
	)
GOTO :EOF
:: =================================================
:: =================================================

::::::::::::::::::::::::::::::::::::::::::::::::
:: function that sets %OUTPUT% to 1 if input is an integer and 0 else
::::::::::::::::::::::::::::::::::::::::::::::::
:is_integer
SET "val=%~1"
ECHO %val% | FINDSTR /R "^[0-9][0-9]*$" >NUL
IF %ERRORLEVEL%==0 (
	SET "OUTPUT=1"
) ELSE (
	SET "OUTPUT=0"
)
GOTO :EOF
:: =================================================
:: =================================================

::::::::::::::::::::::::::::::::::::::::::::::::
:: function to call twice to get printed the duration between the two calls
::::::::::::::::::::::::::::::::::::::::::::::::
:count_duration
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
:: =================================================
:: =================================================
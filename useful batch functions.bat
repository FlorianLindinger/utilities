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


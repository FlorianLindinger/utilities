@ECHO OFF
:: ===================
:: ==== Test Area ====
:: ===================




EXIT /B
:: ===================

:: ====================
:: ==== Functions: ====
:: ====================

:: =================================================
:: function that makes relative path (relative to current working directory) to :: absolute if not already. Works for empty path (relative) path:
:: Usage:
::    call :make_absolute_path_if_relative "%some_path%"
::    set "abs_path=%output%"
:: =================================================
:make_absolute_path_if_relative
    if "%~1"=="" (
        set "OUTPUT=%CD%"
    ) else (
	    set "OUTPUT=%~f1"
    )
	goto :EOF
:: =================================================
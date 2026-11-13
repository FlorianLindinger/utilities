@echo off
rem Removes the hooks installed from here; hooks that were there before come back.
rem Drop another repository's folder onto this file to use that one instead. NO_PAUSE=1 skips the pause.
call "%~dp0_run.bat" "%~1" uninstall

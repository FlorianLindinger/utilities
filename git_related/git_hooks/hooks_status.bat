@echo off
rem Shows which hooks are installed in the Git repository that contains this folder, and each check's setting.
rem Drop another repository's folder onto this file to use that one instead. NO_PAUSE=1 skips the pause.
call "%~dp0_run.bat" "%~1" status

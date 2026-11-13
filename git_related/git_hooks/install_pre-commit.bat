@echo off
rem Installs the pre-commit hook: secrets, conflict markers, large files, file names, whitespace, ... before each commit.
rem Drop another repository's folder onto this file to use that one instead. NO_PAUSE=1 skips the pause.
call "%~dp0_run.bat" "%~1" install pre-commit

@echo off
rem Installs the commit-msg hook: checks the commit message (length; optionally Conventional Commits).
rem Drop another repository's folder onto this file to use that one instead. NO_PAUSE=1 skips the pause.
call "%~dp0_run.bat" "%~1" install commit-msg

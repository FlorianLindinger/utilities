@echo off
rem Installs the pre-push hook: no force push to main, no fixup!/WIP commits, secrets in pushed commits, optional test command.
rem Drop another repository's folder onto this file to use that one instead. NO_PAUSE=1 skips the pause.
call "%~dp0_run.bat" "%~1" install pre-push

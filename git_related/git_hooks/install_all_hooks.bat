@echo off
rem Installs all hooks (pre-commit, commit-msg, pre-push, post-merge, post-checkout) into the Git repository that contains this folder.
rem Drop another repository's folder onto this file to use that one instead. NO_PAUSE=1 skips the pause.
call "%~dp0_run.bat" "%~1" install

@echo off
rem Installs post-merge and post-checkout: a reminder when a pull or branch switch changed dependency files.
rem Drop another repository's folder onto this file to use that one instead. NO_PAUSE=1 skips the pause.
call "%~dp0_run.bat" "%~1" install post-merge post-checkout

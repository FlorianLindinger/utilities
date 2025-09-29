@REM winget install --id Python.Python.3.13 -e --force ^
@REM   --override "InstallAllUsers=0 Include_launcher=1 PrependPath=1 /passive /norestart"

winget install --id Python.Python.3.13 -e --force --override "InstallAllUsers=0 Include_launcher=0 Include_pip=1 PrependPath=1 /passive /norestart" --accept-source-agreements --accept-package-agreements

py -3.13 -c "exit()"
python3.13 -c "exit()"
PAUSE
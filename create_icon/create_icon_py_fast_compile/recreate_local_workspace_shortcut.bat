@echo off
setlocal

>  create_icon_py_fast_compile_local.bat (
   echo @echo off
   echo setlocal
   echo.
   echo call "%~dp0create_icon_py_fast_compile.exe"
)
exit /b 0

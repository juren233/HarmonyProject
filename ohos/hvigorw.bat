@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "DEFAULT_HVIGORW=E:\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat"

if defined DEVECO_SDK_HOME (
  for %%i in ("%DEVECO_SDK_HOME%\..") do set "DEVECO_HOME=%%~fi"
)

if defined DEVECO_HOME (
  set "HVIGORW_PATH=%DEVECO_HOME%\tools\hvigor\bin\hvigorw.bat"
)

if not defined HVIGORW_PATH (
  set "HVIGORW_PATH=%DEFAULT_HVIGORW%"
)

if not exist "%HVIGORW_PATH%" (
  echo ERROR: hvigorw.bat was not found. Checked "%HVIGORW_PATH%".
  echo Please ensure DevEco Studio tools are installed and DEVECO_SDK_HOME points to the sdk directory.
  exit /b 1
)

call "%HVIGORW_PATH%" %*
exit /b %ERRORLEVEL%

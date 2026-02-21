@echo off
setlocal

set "BASE=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%hello_world.ps1"

set "RC=%errorlevel%"
if %RC% neq 0 (
  echo.
  echo [ERROR] ExitCode=%RC%
)

echo.
pause
exit /b %RC%
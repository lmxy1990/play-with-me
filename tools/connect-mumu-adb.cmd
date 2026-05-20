@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0connect-mumu-adb.ps1"

echo.
pause

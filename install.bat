@echo off
rem Double-click launcher for install-ros2-lyrical.ps1.
rem Extra arguments are passed through, e.g.:  install.bat -SkipTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-ros2-lyrical.ps1" %*
echo.
pause

@echo off
rem Krakenfriends beta safety net: run before launching WoW: Forever (beta only).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore-Journey.ps1" %*
pause

@echo off
rem Launcher for WinampAddAlbums.ps1 (no admin required)
setlocal
set "SCRIPT=%~dp0WinampAddAlbums.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%SCRIPT%" %*
endlocal

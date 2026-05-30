@echo off
rem Launcher: opens GUI to choose which playlists to remove (or all)
setlocal
set "SCRIPT=%~dp0WinampRemovePlaylists.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%SCRIPT%" %*
endlocal

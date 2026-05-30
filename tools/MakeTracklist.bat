@echo off
rem Build a plain-text tracklist from an album folder.
setlocal
set "SCRIPT=%~dp0MakeTracklist.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%SCRIPT%" %*
endlocal

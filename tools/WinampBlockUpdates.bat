@echo off
rem Blocks Winamp "New version available" popup by routing the update host
rem to localhost in the Windows HOSTS file. Requires admin (self-elevates).

setlocal EnableExtensions

rem ---------- self-elevate ----------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList 'elevated' -Verb RunAs"
    exit /b
)

set "HOSTS=%SystemRoot%\System32\drivers\etc\hosts"
set "MARK=# Winamp update block"

echo Working with: %HOSTS%
echo.

findstr /C:"%MARK%" "%HOSTS%" >nul 2>&1
if %errorlevel%==0 (
    echo Already blocked. Nothing to do.
    echo.
    pause
    exit /b
)

rem Backup hosts once
if not exist "%HOSTS%.winampbak" copy /Y "%HOSTS%" "%HOSTS%.winampbak" >nul

>> "%HOSTS%" echo.
>> "%HOSTS%" echo %MARK%
>> "%HOSTS%" echo 127.0.0.1 client.winamp.com
>> "%HOSTS%" echo 127.0.0.1 www.winamp.com
>> "%HOSTS%" echo 127.0.0.1 winamp.com

rem Flush DNS so changes take effect immediately
ipconfig /flushdns >nul

echo Done. Winamp update popup is now blocked.
echo To undo: open "%HOSTS%" as Administrator and remove the four lines after "%MARK%".
echo Backup saved at: %HOSTS%.winampbak
echo.
pause
endlocal

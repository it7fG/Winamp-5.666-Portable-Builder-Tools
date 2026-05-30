@echo off
rem ============================================================
rem  BuildPortable.bat
rem  Double-click launcher for BuildPortable.ps1
rem  (double-clicking a .ps1 only opens it in an editor;
rem   this .bat actually RUNS it)
rem ============================================================
setlocal
set "SCRIPT=%~dp0BuildPortable.ps1"

if not exist "%SCRIPT%" (
    echo ERROR: BuildPortable.ps1 not found next to this .bat
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"

echo.
echo ------------------------------------------------------------
echo  Done. Press any key to close this window.
echo ------------------------------------------------------------
pause >nul
endlocal

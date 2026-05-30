@echo off
rem Removes Winamp update block from HOSTS (admin required).

setlocal EnableExtensions

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList 'elevated' -Verb RunAs"
    exit /b
)

set "HOSTS=%SystemRoot%\System32\drivers\etc\hosts"
set "TMP=%TEMP%\hosts.winamp.tmp"

powershell -NoProfile -Command ^
  "$p='%HOSTS%';" ^
  "$lines = Get-Content -LiteralPath $p -Encoding ASCII;" ^
  "$out = New-Object System.Collections.Generic.List[string];" ^
  "$skip = $false;" ^
  "foreach($l in $lines){" ^
  "  if($l -match '^\s*#\s*Winamp update block'){ $skip = $true; continue }" ^
  "  if($skip){" ^
  "    if($l -match '^\s*127\.0\.0\.1\s+(client\.winamp\.com|www\.winamp\.com|winamp\.com)\s*$'){ continue }" ^
  "    $skip = $false" ^
  "  }" ^
  "  $out.Add($l)" ^
  "}" ^
  "Set-Content -LiteralPath $p -Value $out -Encoding ASCII"

ipconfig /flushdns >nul
echo Unblocked. Winamp update checks restored.
pause
endlocal

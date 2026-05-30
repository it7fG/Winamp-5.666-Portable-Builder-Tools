# BuildPortable.ps1
# Assembles a clean portable Winamp 5.666 distribution from:
#   .\WinampProgram Files\   (copy of C:\Program Files (x86)\Winamp)
#   .\WinampRoaming\         (copy of %APPDATA%\Winamp)
#   .\tools\                 (the utility scripts)
#
# Output: .\dist\Winamp_Portable_5.666\

$ErrorActionPreference = 'Stop'

$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcProg = Join-Path $root 'WinampProgram Files'
$srcRoam = Join-Path $root 'WinampRoaming'
$srcTool = Join-Path $root 'tools'

# In Winamp's portable mode, winamp.ini lives directly next to winamp.exe
# (no paths.ini, no Data\ subfolder). Winamp detects local ini and uses it.
$dist    = Join-Path $root 'dist\Winamp_Portable_5.666'
$dataDir = $dist

# ---------- check required source folders ----------
$required = @(
    @{ Path = $srcProg; Hint = 'copy of  C:\Program Files (x86)\Winamp' },
    @{ Path = $srcRoam; Hint = 'copy of  %APPDATA%\Winamp' },
    @{ Path = $srcTool; Hint = 'the tools\ folder from this repository' }
)
$missing = $required | Where-Object { -not (Test-Path -LiteralPath $_.Path) }
if ($missing) {
    Write-Host ''
    Write-Host 'ERROR: missing required source folder(s) next to this script:' -ForegroundColor Red
    Write-Host ''
    foreach ($m in $missing) {
        Write-Host ('  [MISSING] {0}' -f (Split-Path -Leaf $m.Path)) -ForegroundColor Yellow
        Write-Host ('            put here: {0}' -f $m.Path)
        Write-Host ('            should be: {0}' -f $m.Hint)
        Write-Host ''
    }
    Write-Host 'Fix: copy the folder(s) listed above next to BuildPortable.ps1, then run again.'
    exit 1
}

Write-Host "Source program : $srcProg"
Write-Host "Source roaming : $srcRoam"
Write-Host "Source tools   : $srcTool"
Write-Host "Output         : $dist"
Write-Host ''

# ---------- clean output ----------
if (Test-Path -LiteralPath $dist) { Remove-Item -LiteralPath $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist -Force | Out-Null

# ---------- 1. copy program files ----------
Write-Host '[1/6] Copying program files...'
robocopy "$srcProg" "$dist" /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 `
    /XF unins000.exe unins000.dat unins000.msg paths.ini | Out-Null

# ---------- 2. copy roaming -> Data, sanitized ----------
Write-Host '[2/6] Copying user data (sanitized)...'
New-Item -ItemType Directory -Path $dataDir -Force | Out-Null

$skipFiles = @(
    '_crash.dmp', '_crash.log', 'report.zip',
    'Winamp.m3u', 'Winamp.q1', 'winamp.m3u8', 'gen_jumpex.m3u8',
    'studio.xnf', 'links.xml', 'demo.mp3'
)
# Note: ml media-library files (main.dat/main.idx/recent.idx) are excluded
# below via robocopy /XF, so no separate list is needed here.

# top-level files of Roaming
Get-ChildItem -LiteralPath $srcRoam -File | ForEach-Object {
    if ($skipFiles -contains $_.Name) { return }
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dataDir $_.Name) -Force
}

# Plugins subtree (without ml personal stuff)
$plDst = Join-Path $dataDir 'Plugins'
robocopy "$srcRoam\Plugins" "$plDst" /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 `
    /XF _crash.dmp _crash.log report.zip main.dat main.idx recent.idx ml_pmp_device_*.ini `
    /XD art cache feeds Gracenote | Out-Null

# Empty playlists.xml (UTF-16 LE BOM) and remove all plf*.m3u8
$plPath = Join-Path $plDst 'ml\playlists'
if (Test-Path -LiteralPath $plPath) {
    Get-ChildItem -LiteralPath $plPath -Filter 'plf*.m3u8' -File | Remove-Item -Force
    Get-ChildItem -LiteralPath $plPath -Filter '*.bak'       -File | Remove-Item -Force
    Get-ChildItem -LiteralPath $plPath -Filter '*.backup'    -File | Remove-Item -Force
    $emptyXml = '<?xml version="1.0" encoding="UTF-16"?><playlists playlists="0"></playlists>'
    $enc = New-Object System.Text.UnicodeEncoding($false, $true)
    $pre = $enc.GetPreamble(); $pay = $enc.GetBytes($emptyXml)
    $buf = New-Object byte[] ($pre.Length + $pay.Length)
    [Array]::Copy($pre, 0, $buf, 0, $pre.Length)
    [Array]::Copy($pay, 0, $buf, $pre.Length, $pay.Length)
    [System.IO.File]::WriteAllBytes((Join-Path $plPath 'playlists.xml'), $buf)
} else {
    New-Item -ItemType Directory -Path $plPath -Force | Out-Null
    $emptyXml = '<?xml version="1.0" encoding="UTF-16"?><playlists playlists="0"></playlists>'
    $enc = New-Object System.Text.UnicodeEncoding($false, $true)
    $pre = $enc.GetPreamble(); $pay = $enc.GetBytes($emptyXml)
    $buf = New-Object byte[] ($pre.Length + $pay.Length)
    [Array]::Copy($pre, 0, $buf, 0, $pre.Length)
    [Array]::Copy($pay, 0, $buf, $pre.Length, $pay.Length)
    [System.IO.File]::WriteAllBytes((Join-Path $plPath 'playlists.xml'), $buf)
}

# ---------- 3. sanitize winamp.ini ----------
Write-Host '[3/6] Sanitizing winamp.ini...'
$iniSrc = Join-Path $srcRoam 'winamp.ini'
$iniDst = Join-Path $dataDir 'winamp.ini'
if (Test-Path -LiteralPath $iniSrc) {
    $stripKeys = @(
        'cwd', 'uid', 'uid_ft',
        'newverchk', 'newverchk2', 'newverchk3',
        'wx', 'wy', 'pe_wx', 'pe_wy', 'eq_wx', 'eq_wy',
        'video_wx', 'video_wy', 'alt3_wx', 'alt3_wy', 'prefs_wx', 'prefs_wy',
        'minimized', 'mw_open',
        'Stats', 'ID', 'IsFirstInst',
        'cfg_total_time', 'cfg_dev2',
        'cfg_output_dir', 'cfg_singlefile_output',
        'syncOnConnect_time', 'lastusedencoder'
    )
    $stripSections = @('[Jump To File Extra]')
    $out = New-Object System.Collections.Generic.List[string]
    $skipSection = $false
    foreach ($line in (Get-Content -LiteralPath $iniSrc -Encoding UTF8)) {
        if ($line -match '^\s*\[.+\]\s*$') {
            $skipSection = ($stripSections -contains $line.Trim())
            $out.Add($line); continue
        }
        if ($skipSection) { continue }
        $skip = $false
        foreach ($k in $stripKeys) {
            if ($line -match ('^\s*' + [regex]::Escape($k) + '\s*=')) { $skip = $true; break }
        }
        if (-not $skip) { $out.Add($line) }
    }
    [System.IO.File]::WriteAllLines($iniDst, $out, (New-Object System.Text.UTF8Encoding $false))
}

# ---------- 4. (no paths.ini needed; portable mode is triggered by winamp.ini next to winamp.exe) ----------
Write-Host '[4/6] Portable mode: winamp.ini placed next to winamp.exe (no paths.ini needed).'

# ---------- 5. copy tools ----------
Write-Host '[5/6] Copying tools...'
$toolsDst = Join-Path $dist 'tools'
robocopy "$srcTool" "$toolsDst" /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 `
    /XF '_*.ps1' '_*.bat' '*.bak' | Out-Null

# ---------- 6. write top-level launcher and notice ----------
Write-Host '[6/6] Writing launcher and notice...'
$launcher = @'
@echo off
rem Portable Winamp launcher. Just runs winamp.exe in this folder.
start "" "%~dp0winamp.exe"
'@
[System.IO.File]::WriteAllText((Join-Path $dist 'Winamp.bat'), $launcher, (New-Object System.Text.UTF8Encoding $false))

$notice = @"
Winamp 5.666 Portable + Tools
=============================

Portable means: all settings and playlists are stored INSIDE this folder
(winamp.ini next to winamp.exe, playlists in Plugins\ml\playlists\),
not in your Windows profile.
You can copy/move this whole folder anywhere - even to a USB stick - and
it will keep your settings.

How to run:
  - Just double-click winamp.exe (or Winamp.bat).

Bundled utilities (in the tools\ folder):
  - WinampAddAlbums.bat       : mass-import albums as separate playlists
  - WinampRemovePlaylists.bat : mass-delete playlists
  - WinampBlockUpdates.bat    : block "new version available" popup (system-wide,
                                edits Windows hosts file, requires admin).
                                NOT NEEDED for this portable build - the popup
                                is already disabled in winamp.ini. Use only if
                                you also have the installed Winamp on the same PC.

For full instructions see tools\README.md or tools\README.txt.
"@
[System.IO.File]::WriteAllText((Join-Path $dist 'README.txt'), $notice, (New-Object System.Text.UTF8Encoding $false))

# Disable update check inside the portable winamp.ini (set far-future timestamp)
if (Test-Path -LiteralPath $iniDst) {
    $iniLines = Get-Content -LiteralPath $iniDst -Encoding UTF8
    $hasWinampSection = $false
    $newLines = New-Object System.Collections.Generic.List[string]
    foreach ($l in $iniLines) {
        $newLines.Add($l)
        if ($l -match '^\s*\[Winamp\]\s*$' -and -not $hasWinampSection) {
            $newLines.Add('newverchk=2147483647')
            $newLines.Add('newverchk2=2147483647')
            $newLines.Add('newverchk3=2147483647')
            $newLines.Add('check_ft_startup=0')
            $hasWinampSection = $true
        }
    }
    [System.IO.File]::WriteAllLines($iniDst, $newLines, (New-Object System.Text.UTF8Encoding $false))
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' BUILD COMPLETE' -ForegroundColor Green
Write-Host '============================================================'
Write-Host ''
Write-Host 'Your portable Winamp is here:'
Write-Host ('   {0}' -f $dist) -ForegroundColor Cyan
Write-Host ''
Write-Host 'IMPORTANT - use the tools INSIDE the portable build:'
Write-Host ('   {0}\tools\' -f $dist) -ForegroundColor Cyan
Write-Host '   (NOT the source tools\ folder next to this script!)'
Write-Host ''
Write-Host 'You can now DELETE these source folders - they are no longer needed:'
Write-Host ('   {0}' -f $srcProg) -ForegroundColor Yellow
Write-Host ('   {0}' -f $srcRoam) -ForegroundColor Yellow
Write-Host ('   {0}' -f $srcTool) -ForegroundColor Yellow
Write-Host ''
Write-Host ('Keep only the finished folder: {0}' -f (Split-Path -Leaf $dist))
Write-Host 'Zip that folder if you want to share it.'

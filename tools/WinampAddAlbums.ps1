# WinampAddAlbums.ps1
# Adds each subfolder of a chosen folder as a SEPARATE Winamp playlist (one playlist per album).
# Works with Winamp 5.x. No Python required.

[CmdletBinding()]
param(
    [string]$Folder,
    [switch]$Quiet
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Show-Msg($text, $title = 'Winamp Add Albums', $buttons = 'OK', $icon = 'Information') {
    if ($Quiet) { Write-Host "[MSG] $title :: $text"; return [System.Windows.Forms.DialogResult]::OK }
    return [System.Windows.Forms.MessageBox]::Show($text, $title, $buttons, $icon)
}

# ---------- locate Winamp playlists dir (portable-aware) ----------
function Resolve-WinampInidir([string]$winampDir) {
    $paths = Join-Path $winampDir 'paths.ini'
    if (-not (Test-Path -LiteralPath $paths)) { return $winampDir }
    foreach ($line in (Get-Content -LiteralPath $paths)) {
        if ($line -match '^\s*inidir\s*=\s*(.+?)\s*$') {
            $v = $Matches[1]
            $v = $v.Replace('{0}',  $winampDir)
            $v = $v.Replace('{26}', $env:APPDATA)
            $v = $v.Replace('{35}', $env:LOCALAPPDATA)
            $v = $v.Replace('{5}',  [Environment]::GetFolderPath('MyDocuments'))
            return $v
        }
    }
    return $winampDir
}

function Find-WinampPlaylistsDir {
    $scriptDir = $PSScriptRoot
    if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
    # Walk up from script directory: maybe scripts live inside portable Winamp folder
    $d = $scriptDir
    for ($i = 0; $i -lt 6 -and $d; $i++) {
        if (Test-Path -LiteralPath (Join-Path $d 'winamp.exe')) {
            $ini = Resolve-WinampInidir $d
            $pl  = Join-Path $ini 'Plugins\ml\playlists'
            if (-not (Test-Path -LiteralPath $pl)) { New-Item -ItemType Directory -Path $pl -Force | Out-Null }
            return $pl
        }
        $parent = Split-Path -Parent $d
        if (-not $parent -or $parent -eq $d) { break }
        $d = $parent
    }
    foreach ($c in @(
        (Join-Path $env:APPDATA 'Winamp\Plugins\ml\playlists'),
        'C:\Program Files (x86)\Winamp\Plugins\ml\playlists',
        'C:\Program Files\Winamp\Plugins\ml\playlists'
    )) { if (Test-Path -LiteralPath $c) { return $c } }
    return $null
}

$plDir = Find-WinampPlaylistsDir
if (-not $plDir) {
    Show-Msg "Не найдена папка плейлистов Winamp.`r`nПроверь, что Winamp установлен (или положи скрипты в папку портативного Winamp/tools)." 'Ошибка' OK Error | Out-Null
    exit 1
}

# ---------- ensure Winamp is closed (it overwrites playlists.xml on exit) ----------
while (Get-Process -Name winamp -ErrorAction SilentlyContinue) {
    $r = Show-Msg "Winamp сейчас запущен. Закрой его, иначе изменения будут перезаписаны.`r`nНажми OK после закрытия Winamp." 'Winamp запущен' OKCancel Warning
    if ($r -ne [System.Windows.Forms.DialogResult]::OK) { exit }
    Start-Sleep -Milliseconds 500
}

# ---------- pick root folder ----------
if (-not $Folder) {
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = 'Выбери папку, в которой лежат подпапки с альбомами'
    $fbd.ShowNewFolderButton = $false
    if ($fbd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit }
    $Folder = $fbd.SelectedPath
}
if (-not (Test-Path -LiteralPath $Folder)) {
    Show-Msg "Папка не существует: $Folder" 'Ошибка' OK Error | Out-Null
    exit 1
}

# ---------- audio extensions ----------
$audioExt = @('.mp3','.m4a','.mp4','.flac','.ogg','.oga','.opus','.wma','.wav','.aac','.ape','.wv','.aif','.aiff','.mpc','.tta')

# ---------- helper: get audio duration via Shell ----------
$shell = New-Object -ComObject Shell.Application
$lengthCol = $null
function Get-AudioSeconds([System.IO.FileInfo]$file) {
    try {
        $ns = $shell.Namespace($file.DirectoryName)
        if (-not $ns) { return 0 }
        if ($null -eq $script:lengthCol) {
            for ($i = 0; $i -lt 350; $i++) {
                $name = $ns.GetDetailsOf($null, $i)
                if ($name -eq 'Length' -or $name -eq 'Продолжительность' -or $name -eq 'Длительность') {
                    $script:lengthCol = $i; break
                }
            }
            if ($null -eq $script:lengthCol) { $script:lengthCol = 27 }
        }
        $item = $ns.ParseName($file.Name)
        if (-not $item) { return 0 }
        $dur = $ns.GetDetailsOf($item, $script:lengthCol)
        if ([string]::IsNullOrWhiteSpace($dur)) { return 0 }
        $secs = 0
        foreach ($p in ($dur -split ':')) { $secs = $secs * 60 + [int]$p }
        return $secs
    } catch { return 0 }
}

# ---------- load existing playlists.xml ----------
$xmlPath = Join-Path $plDir 'playlists.xml'
$xml = New-Object System.Xml.XmlDocument
$xml.PreserveWhitespace = $false

if (Test-Path -LiteralPath $xmlPath) {
    $bytes = [System.IO.File]::ReadAllBytes($xmlPath)
    # detect UTF-16 LE BOM
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    } else {
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    try { $xml.LoadXml($text) } catch {
        Show-Msg "Не удалось разобрать playlists.xml: $($_.Exception.Message)" 'Ошибка' OK Error | Out-Null
        exit 1
    }
} else {
    $decl = $xml.CreateXmlDeclaration('1.0','UTF-16',$null)
    $xml.AppendChild($decl) | Out-Null
    $rootEl = $xml.CreateElement('playlists')
    $rootEl.SetAttribute('playlists','0')
    $xml.AppendChild($rootEl) | Out-Null
}

$playlistsNode = $xml.SelectSingleNode('/playlists')

# ---------- backup ----------
if (Test-Path -LiteralPath $xmlPath) {
    Copy-Item -LiteralPath $xmlPath -Destination ($xmlPath + '.bak') -Force
}

# ---------- collect existing plf* filenames to avoid collision ----------
$used = @{}
Get-ChildItem -LiteralPath $plDir -Filter 'plf*.m3u8' -File | ForEach-Object { $used[$_.Name.ToLower()] = $true }

function New-PlfName {
    do {
        $h = ('{0:X}' -f (Get-Random -Minimum 1 -Maximum 0xFFFFFFF))
        $n = "plf$h.m3u8"
    } while ($used.ContainsKey($n.ToLower()))
    $used[$n.ToLower()] = $true
    return $n
}

# ---------- collect existing playlist titles to optionally skip duplicates ----------
$existingTitles = @{}
foreach ($n in $playlistsNode.SelectNodes('playlist')) {
    $existingTitles[$n.GetAttribute('title').ToLower()] = $true
}

# ---------- iterate albums ----------
$albums = Get-ChildItem -LiteralPath $Folder -Directory | Sort-Object Name
if (-not $albums) {
    Show-Msg "В выбранной папке нет подпапок." 'Нет альбомов' OK Warning | Out-Null
    exit
}

$added   = 0
$skipped = 0
$logLines = @()

foreach ($alb in $albums) {
    $tracks = Get-ChildItem -LiteralPath $alb.FullName -File -ErrorAction SilentlyContinue |
              Where-Object { $audioExt -contains $_.Extension.ToLower() } |
              Sort-Object Name
    if (-not $tracks) { $logLines += "пропущено (нет аудио): $($alb.Name)"; continue }

    if ($existingTitles.ContainsKey($alb.Name.ToLower())) {
        $skipped++
        $logLines += "уже существует: $($alb.Name)"
        continue
    }

    $utf8Lines = New-Object System.Collections.Generic.List[string]
    $utf8Lines.Add('#EXTM3U')
    $totalSec = 0
    foreach ($t in $tracks) {
        $sec = Get-AudioSeconds $t
        if ($sec -le 0) { $sec = -1 }
        else { $totalSec += $sec }
        $title = [System.IO.Path]::GetFileNameWithoutExtension($t.Name)
        $utf8Lines.Add("#EXTINF:$sec,$title")
        $utf8Lines.Add($t.FullName)
    }

    $plfName = New-PlfName
    $plfPath = Join-Path $plDir $plfName
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllLines($plfPath, $utf8Lines, $utf8NoBom)

    $node = $xml.CreateElement('playlist')
    $node.SetAttribute('filename', $plfName)
    $node.SetAttribute('title',    $alb.Name)
    $node.SetAttribute('id',       '{' + ([guid]::NewGuid().ToString().ToUpper()) + '}')
    $node.SetAttribute('songs',    $tracks.Count.ToString())
    $node.SetAttribute('seconds',  $totalSec.ToString())
    $playlistsNode.AppendChild($node) | Out-Null
    $existingTitles[$alb.Name.ToLower()] = $true

    $added++
    $logLines += "добавлено: $($alb.Name)  ($($tracks.Count) треков)"
}

$playlistsNode.SetAttribute('playlists', $playlistsNode.SelectNodes('playlist').Count.ToString())

# ---------- save as UTF-16 LE with BOM ----------
$sw = New-Object System.IO.StringWriter
$xws = New-Object System.Xml.XmlWriterSettings
$xws.OmitXmlDeclaration = $true
$xws.Indent = $false
$xw = [System.Xml.XmlWriter]::Create($sw, $xws)
$playlistsNode.WriteTo($xw)
$xw.Flush()
$body = $sw.ToString()
$final = '<?xml version="1.0" encoding="UTF-16"?>' + $body

$enc = New-Object System.Text.UnicodeEncoding($false, $true) # UTF-16 LE + BOM
$preamble = $enc.GetPreamble()
$payload  = $enc.GetBytes($final)
$all = New-Object byte[] ($preamble.Length + $payload.Length)
[Array]::Copy($preamble, 0, $all, 0, $preamble.Length)
[Array]::Copy($payload,  0, $all, $preamble.Length, $payload.Length)
[System.IO.File]::WriteAllBytes($xmlPath, $all)

$summary = "Добавлено альбомов: $added`r`nПропущено (уже есть/без аудио): $skipped`r`n`r`n" + ($logLines -join [Environment]::NewLine)
Show-Msg $summary 'Готово' OK Information | Out-Null

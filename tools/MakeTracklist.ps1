# MakeTracklist.ps1
# Builds a plain-text tracklist from an album folder.
# Input  : a folder with audio files (FLAC/MP3/...)
# Output : <album-folder-name>.txt next to this script.
#
# File-name parsing:
#   "01. Imprintband - Шум воды.flac"   -> "01. Шум воды"
#   "01 - Artist - Title.mp3"            -> "01. Title"
#   "01 Title.mp3"                       -> "01. Title"
#   anything else                        -> "NN. <original name without extension>"

[CmdletBinding()]
param(
    [string]$Folder,
    [switch]$Quiet
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Show-Msg($text, $title = 'Make Tracklist', $buttons = 'OK', $icon = 'Information') {
    if ($Quiet) { Write-Host "[MSG] $title :: $text"; return [System.Windows.Forms.DialogResult]::OK }
    return [System.Windows.Forms.MessageBox]::Show($text, $title, $buttons, $icon)
}

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

# ---------- pick album folder ----------
if (-not $Folder) {
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = 'Выбери папку альбома (с аудиофайлами)'
    $fbd.ShowNewFolderButton = $false
    if ($fbd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit }
    $Folder = $fbd.SelectedPath
}
if (-not (Test-Path -LiteralPath $Folder)) {
    Show-Msg "Папка не найдена:`r`n$Folder" 'Ошибка' OK Error | Out-Null
    exit 1
}

# ---------- gather audio files ----------
$audioExt = @('.mp3','.m4a','.mp4','.flac','.ogg','.oga','.opus','.wma','.wav','.aac','.ape','.wv','.aif','.aiff','.mpc','.tta')
$files = Get-ChildItem -LiteralPath $Folder -File | Where-Object { $audioExt -contains $_.Extension.ToLower() } | Sort-Object Name
if ($files.Count -eq 0) {
    Show-Msg "В папке нет аудиофайлов." 'Пусто' OK Warning | Out-Null
    exit
}

# ---------- helper: read media metadata via Shell ----------
$shell = New-Object -ComObject Shell.Application
$lengthCol  = $null
$bitrateCol = $null
function Get-MediaInfo([System.IO.FileInfo]$file) {
    # Returns precise duration (in seconds, decimal) via System.Media.Duration (100-ns ticks)
    # plus bitrate in kbps.
    $info = @{ Seconds = 0.0; BitrateKbps = 0 }
    try {
        $ns = $shell.Namespace($file.DirectoryName)
        if (-not $ns) { return $info }
        if ($null -eq $script:bitrateCol) {
            for ($i = 0; $i -lt 350; $i++) {
                $cn = $ns.GetDetailsOf($null, $i)
                if ($cn -eq 'Bit rate' -or $cn -eq 'Bitrate' -or $cn -eq 'Скорость в битах' -or $cn -eq 'Битрейт') { $script:bitrateCol = $i; break }
            }
            if ($null -eq $script:bitrateCol) { $script:bitrateCol = 28 }
        }
        $item = $ns.ParseName($file.Name)
        if (-not $item) { return $info }

        # Precise duration in 100-ns ticks (10,000,000 ticks per second)
        try {
            $ticks = $item.ExtendedProperty('System.Media.Duration')
            if ($ticks) { $info.Seconds = [double]$ticks / 10000000.0 }
        } catch {}

        $br = $ns.GetDetailsOf($item, $script:bitrateCol)
        if ($br -match '(\d+)') { $info.BitrateKbps = [int]$Matches[1] }
    } catch {}
    return $info
}

# ---------- parse names ----------
$lines = New-Object System.Collections.Generic.List[string]
$autoNum = 0
foreach ($f in $files) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $num = $null
    $title = $null

    # Try: "NN. Artist - Title", "NN - Artist - Title", "NN. Title", "NN Title", "NN.Title" (no space)
    if ($name -match '^\s*(\d+)[.\-_)\s]+(.+)$') {
        $num   = $Matches[1]
        $rest  = $Matches[2].Trim()
        # If "Artist - Title" pattern, drop everything up to the FIRST " - " (or " – ")
        if ($rest -match '^\s*(.+?)\s+[-\u2013\u2014]\s+(.+)$') {
            $title = $Matches[2].Trim()
        } else {
            $title = $rest
        }
    } else {
        # No leading number — assign sequential
        $autoNum++
        $num = '{0:D2}' -f $autoNum
        # Still try to strip "Artist - "
        if ($name -match '^\s*(.+?)\s+[-\u2013\u2014]\s+(.+)$') {
            $title = $Matches[2].Trim()
        } else {
            $title = $name.Trim()
        }
    }

    # Normalize number to 2 digits if it's purely numeric and shorter than 2
    if ($num -match '^\d+$' -and $num.Length -lt 2) { $num = '{0:D2}' -f [int]$num }

    $lines.Add(('{0}. {1}' -f $num, $title))
}

# ---------- gather album-level info: bitrate (first file), total duration, total size ----------
$firstInfo = Get-MediaInfo $files[0]
[double]$totalSecs = 0.0
foreach ($f in $files) {
    $i = Get-MediaInfo $f
    $totalSecs += [double]$i.Seconds
}
$totalBytes = (Get-ChildItem -LiteralPath $Folder -File -Recurse | Measure-Object Length -Sum).Sum

# format duration as H:MM:SS or MM:SS (round total to nearest second, like Windows)
function Format-Duration([double]$s) {
    $total = [int][math]::Floor($s)
    $h     = [int][math]::Floor($total / 3600)
    $m     = [int][math]::Floor(($total % 3600) / 60)
    $sec   = [int]($total % 60)
    if ($h -gt 0) { return ('{0}:{1:D2}:{2:D2}' -f $h, $m, $sec) }
    return ('{0}:{1:D2}' -f $m, $sec)
}

# format size like Windows Properties: "118 МБ (124 516 173 байт)"
# Windows truncates MB downward to whole megabytes.
function Format-Size([long]$bytes) {
    $mb = [int][math]::Floor($bytes / 1MB)
    # group bytes by thousands with regular space (matches Russian Windows visual)
    $grouped = ('{0:N0}' -f $bytes) -replace ',', ' '
    return ('{0} МБ ({1} байт)' -f $mb, $grouped)
}

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add('')
$summary.Add('---')
$summary.Add(('Битрейт:           {0} kbps' -f $firstInfo.BitrateKbps))
$summary.Add(('Продолжительность: {0}' -f (Format-Duration $totalSecs)))
$summary.Add(('Размер:            {0}' -f (Format-Size $totalBytes)))
$lines.AddRange([string[]]$summary.ToArray())

# ---------- write output next to this script ----------
$albumName = Split-Path -Leaf $Folder
# sanitize filename
$invalid = [System.IO.Path]::GetInvalidFileNameChars()
$safeName = -join ($albumName.ToCharArray() | ForEach-Object { if ($invalid -contains $_) { '_' } else { $_ } })
$outFile = Join-Path $scriptDir ($safeName + '.txt')

$enc = New-Object System.Text.UTF8Encoding($true)  # UTF-8 with BOM, for Notepad
[System.IO.File]::WriteAllLines($outFile, $lines, $enc)

Show-Msg ("Готово.`r`n`r`nТреков: {0}`r`nФайл: {1}" -f $files.Count, $outFile) 'Готово' OK Information | Out-Null

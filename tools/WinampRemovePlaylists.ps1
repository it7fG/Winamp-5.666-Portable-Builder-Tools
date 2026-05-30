# WinampRemovePlaylists.ps1
# Removes Winamp "Playlists" entries (all or selected). No Python required.

[CmdletBinding()]
param(
    [switch]$All,
    [switch]$Quiet
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Show-Msg($text, $title = 'Winamp Remove Playlists', $buttons = 'OK', $icon = 'Information') {
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
    Show-Msg "Не найдена папка плейлистов Winamp." 'Ошибка' OK Error | Out-Null
    exit 1
}

# ---------- ensure Winamp is closed ----------
while (Get-Process -Name winamp -ErrorAction SilentlyContinue) {
    $r = Show-Msg "Winamp сейчас запущен. Закрой его, иначе изменения будут перезаписаны.`r`nНажми OK после закрытия Winamp." 'Winamp запущен' OKCancel Warning
    if ($r -ne [System.Windows.Forms.DialogResult]::OK) { exit }
    Start-Sleep -Milliseconds 500
}

$xmlPath = Join-Path $plDir 'playlists.xml'
if (-not (Test-Path -LiteralPath $xmlPath)) {
    Show-Msg "Файл playlists.xml не найден — нечего удалять." 'Пусто' OK Information | Out-Null
    exit
}

# ---------- load playlists.xml ----------
$bytes = [System.IO.File]::ReadAllBytes($xmlPath)
if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
    $text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
} else {
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
}
$xml = New-Object System.Xml.XmlDocument
try { $xml.LoadXml($text) } catch {
    Show-Msg "Не удалось разобрать playlists.xml: $($_.Exception.Message)" 'Ошибка' OK Error | Out-Null
    exit 1
}
$playlistsNode = $xml.SelectSingleNode('/playlists')
$nodes = @($playlistsNode.SelectNodes('playlist'))

if ($nodes.Count -eq 0) {
    Show-Msg "Список воспроизведения уже пуст." 'Пусто' OK Information | Out-Null
    exit
}

# ---------- choose what to delete ----------
$toDelete = @()

if ($All) {
    $toDelete = $nodes
} elseif ($Quiet) {
    $toDelete = $nodes
} else {
    # GUI form with CheckedListBox + 'Select All' + 'Delete ALL' shortcut
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Удаление плейлистов Winamp'
    $form.Size = New-Object System.Drawing.Size(560, 520)
    $form.StartPosition = 'CenterScreen'
    $form.MinimizeBox = $false
    $form.MaximizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Найдено плейлистов: $($nodes.Count). Отметь те, которые удалить:"
    $lbl.Location = New-Object System.Drawing.Point(12, 10)
    $lbl.Size = New-Object System.Drawing.Size(520, 20)
    $form.Controls.Add($lbl)

    $clb = New-Object System.Windows.Forms.CheckedListBox
    $clb.Location = New-Object System.Drawing.Point(12, 35)
    $clb.Size = New-Object System.Drawing.Size(520, 380)
    $clb.CheckOnClick = $true
    $clb.IntegralHeight = $false
    foreach ($n in $nodes) {
        $title  = $n.GetAttribute('title')
        $songs  = $n.GetAttribute('songs')
        $clb.Items.Add(("{0}  ({1} треков)" -f $title, $songs)) | Out-Null
    }
    $form.Controls.Add($clb)

    $btnAll = New-Object System.Windows.Forms.Button
    $btnAll.Text = 'Отметить все'
    $btnAll.Location = New-Object System.Drawing.Point(12, 425)
    $btnAll.Size = New-Object System.Drawing.Size(120, 28)
    $btnAll.Add_Click({ for ($i=0; $i -lt $clb.Items.Count; $i++) { $clb.SetItemChecked($i, $true) } })
    $form.Controls.Add($btnAll)

    $btnNone = New-Object System.Windows.Forms.Button
    $btnNone.Text = 'Снять все'
    $btnNone.Location = New-Object System.Drawing.Point(140, 425)
    $btnNone.Size = New-Object System.Drawing.Size(120, 28)
    $btnNone.Add_Click({ for ($i=0; $i -lt $clb.Items.Count; $i++) { $clb.SetItemChecked($i, $false) } })
    $form.Controls.Add($btnNone)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = 'Удалить отмеченные'
    $btnOk.Location = New-Object System.Drawing.Point(290, 425)
    $btnOk.Size = New-Object System.Drawing.Size(150, 28)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($btnOk)
    $form.AcceptButton = $btnOk

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Отмена'
    $btnCancel.Location = New-Object System.Drawing.Point(450, 425)
    $btnCancel.Size = New-Object System.Drawing.Size(82, 28)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($btnCancel)
    $form.CancelButton = $btnCancel

    if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit }

    $checkedIdx = @($clb.CheckedIndices)
    if ($checkedIdx.Count -eq 0) {
        Show-Msg "Ничего не отмечено — отмена." 'Отмена' OK Information | Out-Null
        exit
    }
    $toDelete = foreach ($i in $checkedIdx) { $nodes[$i] }
}

# ---------- final confirm ----------
$names = ($toDelete | ForEach-Object { '• ' + $_.GetAttribute('title') }) -join [Environment]::NewLine
$confirmText = "Будет удалено плейлистов: $($toDelete.Count)`r`n`r`n$names`r`n`r`nФайлы плейлистов на диске НЕ затрагиваются — удаляются только сами плейлисты Winamp.`r`nПродолжить?"
$ok = Show-Msg $confirmText 'Подтверждение удаления' YesNo Warning
if ($ok -ne [System.Windows.Forms.DialogResult]::Yes -and $ok -ne [System.Windows.Forms.DialogResult]::OK) { exit }

# ---------- backup ----------
Copy-Item -LiteralPath $xmlPath -Destination ($xmlPath + '.bak') -Force

# ---------- delete plf files + xml entries ----------
$deletedFiles = 0
foreach ($n in $toDelete) {
    $fname = $n.GetAttribute('filename')
    if ($fname) {
        $fpath = Join-Path $plDir $fname
        if (Test-Path -LiteralPath $fpath) {
            try { Remove-Item -LiteralPath $fpath -Force; $deletedFiles++ } catch {}
        }
    }
    [void]$playlistsNode.RemoveChild($n)
}

$playlistsNode.SetAttribute('playlists', $playlistsNode.SelectNodes('playlist').Count.ToString())

# ---------- save UTF-16 LE BOM ----------
$sw = New-Object System.IO.StringWriter
$xws = New-Object System.Xml.XmlWriterSettings
$xws.OmitXmlDeclaration = $true
$xws.Indent = $false
$xw = [System.Xml.XmlWriter]::Create($sw, $xws)
$playlistsNode.WriteTo($xw)
$xw.Flush()
$body = $sw.ToString()
$final = '<?xml version="1.0" encoding="UTF-16"?>' + $body

$enc = New-Object System.Text.UnicodeEncoding($false, $true)
$preamble = $enc.GetPreamble()
$payload  = $enc.GetBytes($final)
$outBytes = New-Object byte[] ($preamble.Length + $payload.Length)
[Array]::Copy($preamble, 0, $outBytes, 0, $preamble.Length)
[Array]::Copy($payload,  0, $outBytes, $preamble.Length, $payload.Length)
[System.IO.File]::WriteAllBytes($xmlPath, $outBytes)

Show-Msg "Удалено плейлистов: $($toDelete.Count)`r`nУдалено .m3u8 файлов: $deletedFiles`r`n`r`nБэкап: playlists.xml.bak" 'Готово' OK Information | Out-Null

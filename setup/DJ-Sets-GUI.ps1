. (Join-Path $PSScriptRoot 'DJ-Sets-Logging.ps1')
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$ErrorActionPreference = 'Stop'
$core = Join-Path $PSScriptRoot 'DJ-Sets-Download.ps1'
. $core -LibraryOnly -ToolRoot $PSScriptRoot
foreach ($exe in @($yt, $ffmpeg, $probe, $deno)) {
    if (!(Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Programm fehlt: $exe" }
}
$jobs = Join-Path $MusicRoot '.dj-set-downloads'
[void][IO.Directory]::CreateDirectory($config)
$lockPath = Join-Path $config 'dj-set-downloader.lock'
Assert-SafePath $lockPath
Assert-SafePath $archive
$lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')

$settingsPath = Join-Path $config 'dj-set-gui.json'
$settings = @{ MusicRoot = $MusicRoot; Playlist = $true; Theme = 'System' }
$settingsWarning = ''
if ([IO.File]::Exists($settingsPath)) {
    try {
        $saved = [IO.File]::ReadAllText($settingsPath, $utf8) | ConvertFrom-Json
        if ($saved.MusicRoot -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)') { throw 'Ungültiger Musikordner.' }
        $settings.MusicRoot = [IO.Path]::GetFullPath($saved.MusicRoot)
        if ($saved.Playlist -is [bool]) { $settings.Playlist = $saved.Playlist }
        if ($saved.Theme -in @('Hell','Dunkel','System')) { $settings.Theme = $saved.Theme }
    } catch { $settingsWarning = 'Einstellungen konnten nicht geladen werden. Standardwerte sind aktiv.' }
}

$aliasPath = Join-Path $config 'dj-set-aliases.json'
$aliases = [Collections.Generic.List[object]]::new()
if ([IO.File]::Exists($aliasPath)) {
    try {
        foreach ($entry in @(([IO.File]::ReadAllText($aliasPath, $utf8) | ConvertFrom-Json))) {
            if ($entry.Alias -and $entry.Name) { $aliases.Add($entry) }
        }
    } catch { $settingsWarning = 'Die DJ-Aliasse konnten nicht geladen werden.' }
}

function Set-WindowTheme($Window) {
    $dark = $settings.Theme -eq 'Dunkel'
    if ($settings.Theme -eq 'System') {
        $personalize = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction SilentlyContinue
        $dark = $null -ne $personalize -and $personalize.AppsUseLightTheme -eq 0
    }
    if (!$dark) { return }
    $background = [Drawing.Color]::FromArgb(29,34,41)
    $surface = [Drawing.Color]::FromArgb(42,49,58)
    $text = [Drawing.Color]::FromArgb(236,240,244)
    $selection = [Drawing.Color]::FromArgb(20,99,108)
    function Set-ControlTheme($Control) {
        $Control.BackColor = $background
        $Control.ForeColor = $text
        if ($Control -is [Windows.Forms.DataGridView]) {
            $Control.BackgroundColor = $background
            $Control.GridColor = $surface
            $Control.EnableHeadersVisualStyles = $false
            $Control.ColumnHeadersDefaultCellStyle.BackColor = $surface
            $Control.ColumnHeadersDefaultCellStyle.ForeColor = $text
            $Control.DefaultCellStyle.BackColor = $background
            $Control.DefaultCellStyle.ForeColor = $text
            $Control.DefaultCellStyle.SelectionBackColor = $selection
            $Control.DefaultCellStyle.SelectionForeColor = $text
            $Control.AlternatingRowsDefaultCellStyle.BackColor = $surface
            foreach ($column in $Control.Columns) {
                if ($column -is [Windows.Forms.DataGridViewComboBoxColumn]) { $column.FlatStyle = 'Flat' }
            }
        } elseif ($Control -is [Windows.Forms.Button] -or $Control -is [Windows.Forms.ComboBox]) {
            $Control.FlatStyle = 'Flat'
            $Control.BackColor = if ($Control -eq $download -or $Control -eq $preview) { $selection } else { $surface }
            if ($Control -is [Windows.Forms.Button] -and $Control.Text) {
                $Control.UseVisualStyleBackColor = $false
                $Control.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(105,121,135)
                $Control.Add_Paint({
                    param($sender,$eventArgs)
                    if ($sender.Enabled) { return }
                    $area = [Drawing.Rectangle]::Inflate($sender.ClientRectangle,-2,-2)
                    $eventArgs.Graphics.FillRectangle([Drawing.Brushes]::DarkSlateGray,$area)
                    [Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics,$sender.Text,$sender.Font,$area,
                        [Drawing.Color]::FromArgb(213,224,229),
                        [Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, SingleLine')
                })
            }
        } elseif ($Control -is [Windows.Forms.TextBox]) { $Control.BackColor = $surface }
        if ($Control -is [Windows.Forms.MenuStrip]) {
            foreach ($item in $Control.Items) {
                $item.ForeColor = $text
                $item.BackColor = $background
                foreach ($child in $item.DropDownItems) {
                    $child.ForeColor = $text
                    $child.BackColor = $surface
                }
            }
        }
        foreach ($child in $Control.Controls) { Set-ControlTheme $child }
    }
    Set-ControlTheme $Window
}

$form = [Windows.Forms.Form]@{
    Text = 'Plattenkoffer'; Width = 1160; Height = 730; MinimumSize = [Drawing.Size]::new(770, 530)
    StartPosition = 'CenterScreen'; Font = [Drawing.Font]::new('Segoe UI', 10)
}
$layout = [Windows.Forms.TableLayoutPanel]@{ Dock = 'Fill'; RowCount = 7; ColumnCount = 1; Padding = [Windows.Forms.Padding]::new(0,0,0,12) }
foreach ($size in @(124, 44, 42, 0, 32, 130, 26)) {
    if ($size) { [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', $size)) }
    else { [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent', 100)) }
}
$form.BackColor = [Drawing.Color]::FromArgb(242,246,248)
$iconPath = Join-Path $PSScriptRoot 'SetArchiv.ico'
if ([IO.File]::Exists($iconPath)) { $form.Icon = [Drawing.Icon]::new($iconPath) }
$form.Controls.Add($layout)
$bannerPath = Join-Path $PSScriptRoot 'plattenkoffer-banner.png'
if ([IO.File]::Exists($bannerPath)) {
    $sourceImage = [Drawing.Image]::FromFile($bannerPath)
    try { $bannerImage = [Drawing.Bitmap]::new($sourceImage) }
    finally { $sourceImage.Dispose() }
    $banner = [Windows.Forms.PictureBox]@{
        Dock='Fill'; Margin=[Windows.Forms.Padding]::new(0)
        AccessibleName='Plattenkoffer und Plattenspieler'
    }
    $form.Add_Disposed({ $bannerImage.Dispose() })
    $banner.Add_Paint({
        param($sender, $eventArgs)
        $width = $sender.ClientSize.Width
        if (!$width -or !$sender.ClientSize.Height) { return }
        $sourceHeight = [Math]::Min($bannerImage.Height, [int]($sender.ClientSize.Height * $bannerImage.Width / $width))
        if (!$sourceHeight) { return }
        $top = [int](($bannerImage.Height - $sourceHeight) * 0.63)
        $source = [Drawing.Rectangle]::new(0,$top,$bannerImage.Width,$sourceHeight)
        $eventArgs.Graphics.InterpolationMode = 'HighQualityBicubic'
        $eventArgs.Graphics.DrawImage($bannerImage,$sender.ClientRectangle,$source,[Drawing.GraphicsUnit]::Pixel)
    })
    $layout.Controls.Add($banner, 0, 0)
    $layout.Add_SizeChanged({
        $layout.RowStyles[0].Height = [Math]::Min(240,[int]($layout.ClientSize.Width * 0.20))
        $banner.Invalidate()
    })
    $layout.RowStyles[0].Height = [Math]::Min(240,[int]($layout.ClientSize.Width * 0.20))
} else { $layout.RowStyles[0].Height = 0 }
$header = [Windows.Forms.TableLayoutPanel]@{ Dock = 'Fill'; ColumnCount = 4 }
[void]$header.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute', 108))
[void]$header.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 100))
[void]$header.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute', 145))
[void]$header.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute', 145))
$link = [Windows.Forms.TextBox]@{ Dock = 'Fill'; AccessibleName = 'YouTube-Link' }
$playlist = [Windows.Forms.CheckBox]@{ Text = 'Ganze Playlist'; AutoSize = $true; Checked = $settings.Playlist }
$preview = [Windows.Forms.Button]@{ Text = 'Vorschau laden'; Dock = 'Fill' }
$linkLabel = [Windows.Forms.Label]@{ Text='YouTube-Link'; Dock='Fill'; TextAlign='TopLeft'; Padding=[Windows.Forms.Padding]::new(0,5,0,0) }
$header.Controls.Add($linkLabel, 0, 0)
$header.Controls.Add($link, 1, 0)
$header.Controls.Add($playlist, 2, 0)
$header.Controls.Add($preview, 3, 0)
$layout.Controls.Add($header, 0, 1)
$bar = [Windows.Forms.FlowLayoutPanel]@{ Dock = 'Fill' }
$download = [Windows.Forms.Button]@{ Text = 'Download starten'; AutoSize = $true; Enabled = $false }
$bulk = [Windows.Forms.Button]@{ Text = 'DJ für markierte Zeilen'; AutoSize = $true; Enabled = $false }
$folder = [Windows.Forms.ToolStripMenuItem]@{ Text = 'Musikordner öffnen'; AutoSize = $true }
$options = [Windows.Forms.ToolStripMenuItem]@{ Text = 'Einstellungen'; AutoSize = $true }
$stop = [Windows.Forms.Button]@{ Text = 'Nach diesem Set stoppen'; AutoSize = $true; Enabled = $false }
$resume = [Windows.Forms.ToolStripMenuItem]@{ Text = 'Warteschlange fortsetzen'; AutoSize = $true; Enabled = $false }
$retry = [Windows.Forms.ToolStripMenuItem]@{ Text = 'Fehlgeschlagene erneut versuchen'; AutoSize = $true; Enabled = $false }
$import = [Windows.Forms.ToolStripMenuItem]@{ Text = 'MP3s importieren'; AutoSize = $true }
$library = [Windows.Forms.ToolStripMenuItem]@{ Text = 'Bibliothek'; AutoSize = $true }
$menu = [Windows.Forms.MenuStrip]@{ Dock = 'Top' }
$fileMenu = [Windows.Forms.ToolStripMenuItem]@{ Text = '&Datei' }
$fileMenu.DropDownItems.AddRange(@($library, $import, $folder))
$queueMenu = [Windows.Forms.ToolStripMenuItem]@{ Text = '&Warteschlange' }
$queueMenu.DropDownItems.AddRange(@($resume, $retry))
$helpMenu = [Windows.Forms.ToolStripMenuItem]@{ Text = '&Hilfe' }
$diagnose = [Windows.Forms.ToolStripMenuItem]@{ Text = 'Diagnose' }
[void]$helpMenu.DropDownItems.Add($diagnose)
$about = [Windows.Forms.ToolStripMenuItem]@{ Text='Über Plattenkoffer' }
$about.Add_Click({
    [void][Windows.Forms.MessageBox]::Show($form, "Plattenkoffer`r`nEntwickler: Mindgamer", 'Über Plattenkoffer', 'OK', 'Information')
})
[void]$helpMenu.DropDownItems.Add($about)
function Open-SupportPage {
    try { Start-Process -FilePath 'https://ko-fi.com/mindgamer49330' }
    catch {
        [void][Windows.Forms.MessageBox]::Show($form, 'Die Ko-fi-Seite konnte nicht geöffnet werden.', 'Plattenkoffer unterstützen')
    }
}
$supportMenu = [Windows.Forms.ToolStripMenuItem]@{ Text='Plattenkoffer unterstützen …' }
$supportMenu.Add_Click({ Open-SupportPage })
[void]$helpMenu.DropDownItems.Add($supportMenu)
$menu.Items.AddRange(@($fileMenu, $queueMenu, $options, $helpMenu))
$form.Controls.Add($menu)
$form.MainMenuStrip = $menu
foreach ($button in @($download, $preview)) {
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = [Drawing.Color]::FromArgb(16, 104, 95)
    $button.ForeColor = [Drawing.Color]::White
}
$libraryShortcut = [Windows.Forms.Button]@{ Width=46; Height=34; AccessibleName='Bibliothek öffnen' }
$libraryShortcut.Add_Paint({
    param($sender,$eventArgs)
    $canvas = $eventArgs.Graphics
    $canvas.SmoothingMode = 'AntiAlias'
    # Open flight-case lid and record, then the front panel in the foreground.
    $canvas.FillRectangle([Drawing.Brushes]::DimGray,7,3,32,15)
    $canvas.DrawRectangle([Drawing.Pens]::Silver,7,3,32,15)
    $canvas.FillEllipse([Drawing.Brushes]::Black,13,4,20,20)
    $canvas.DrawEllipse([Drawing.Pens]::Gray,15,6,16,16)
    $canvas.FillEllipse([Drawing.Brushes]::MediumTurquoise,20,11,6,6)
    $canvas.FillRectangle([Drawing.Brushes]::DarkSlateGray,6,16,34,13)
    $canvas.DrawRectangle([Drawing.Pens]::Silver,6,16,34,13)
    $canvas.FillRectangle([Drawing.Brushes]::Silver,9,16,4,5)
    $canvas.FillRectangle([Drawing.Brushes]::Silver,33,16,4,5)
    $canvas.DrawRectangle([Drawing.Pens]::Silver,19,22,8,4)
})
$libraryTip = [Windows.Forms.ToolTip]::new()
$libraryTip.SetToolTip($libraryShortcut,'Bibliothek öffnen')
$libraryShortcut.Add_Click({ Show-Library $settings.MusicRoot })
$download.Add_Paint({
    param($sender, $eventArgs)
    if ($sender.Enabled) { return }
    $area = [Drawing.Rectangle]::Inflate($sender.ClientRectangle, -2, -2)
    $eventArgs.Graphics.FillRectangle([Drawing.Brushes]::DimGray, $area)
    [Windows.Forms.TextRenderer]::DrawText(
        $eventArgs.Graphics, $sender.Text, $sender.Font, $area, [Drawing.Color]::White,
        [Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, SingleLine'
    )
})
$supportButton = [Windows.Forms.Button]@{
    Text='♥'; Width=38; Height=34; AccessibleName='Plattenkoffer auf Ko-fi unterstützen'
}
$libraryTip.SetToolTip($supportButton,'Plattenkoffer auf Ko-fi unterstützen')
$supportButton.Add_Click({ Open-SupportPage })
$bar.Controls.AddRange(@($download, $stop, $bulk, $libraryShortcut, $supportButton))
$layout.Controls.Add($bar, 0, 2)
$grid = [Windows.Forms.DataGridView]@{
    Dock = 'Fill'; AllowUserToAddRows = $false; AllowUserToDeleteRows = $false; RowHeadersVisible = $false
    MultiSelect = $true; SelectionMode = 'FullRowSelect'; BackgroundColor = [Drawing.Color]::White
}
$grid.EnableHeadersVisualStyles = $false
$grid.ColumnHeadersDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(22,39,55)
$grid.ColumnHeadersDefaultCellStyle.ForeColor = [Drawing.Color]::White
$grid.AlternatingRowsDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(240,247,248)
$grid.RowTemplate.Height = 28
$check = [Windows.Forms.DataGridViewCheckBoxColumn]@{ Name = 'Selected'; HeaderText = 'Laden'; Width = 60 }
[void]$grid.Columns.Add($check)
foreach ($spec in @(@('Artist','Künstler',15),@('Title','Titel',19),@('Original','Originaltitel',23),@('Status','Status',12),@('Target','Zielordner',31))) {
    $column = [Windows.Forms.DataGridViewTextBoxColumn]@{
        Name = $spec[0]; HeaderText = $spec[1]; AutoSizeMode = 'Fill'; FillWeight = $spec[2]
        ReadOnly = $spec[0] -in @('Original','Status','Target'); SortMode = 'NotSortable'
    }
    [void]$grid.Columns.Add($column)
}
$layout.Controls.Add($grid, 0, 3)
$typeColumn = [Windows.Forms.DataGridViewComboBoxColumn]@{ Name='Type'; HeaderText='Typ'; Width=85 }
$typeColumn.Items.AddRange(@('Track','Set'))
[void]$grid.Columns.Add($typeColumn)
$status = [Windows.Forms.Label]@{ Dock = 'Fill'; Text = 'YouTube-Link einfügen und Vorschau laden.'; TextAlign = 'MiddleLeft' }
$layout.Controls.Add($status, 0, 4)
$footer = [Windows.Forms.TableLayoutPanel]@{ Dock = 'Fill'; RowCount = 2; ColumnCount = 1 }
[void]$footer.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 22))
[void]$footer.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent', 100))
$progress = [Windows.Forms.ProgressBar]@{ Dock = 'Fill' }
$log = [Windows.Forms.TextBox]@{ Dock = 'Fill'; Multiline = $true; ReadOnly = $true; ScrollBars = 'Vertical' }
$footer.Controls.Add($progress, 0, 0)
$footer.Controls.Add($log, 0, 1)
$layout.Controls.Add($footer, 0, 5)
$destination = [Windows.Forms.Label]@{
    Dock = 'Fill'; AutoEllipsis = $true; Text = "Downloadordner: $($settings.MusicRoot)"
}
$layout.Controls.Add($destination, 0, 6)
foreach ($control in @($header,$bar,$grid,$status,$footer,$destination)) { $control.Margin = [Windows.Forms.Padding]::new(12,3,12,3) }
if ($settingsWarning) { $status.Text = $settingsWarning }

function Ask-DJ($Caption, $Prompt, $Value, [bool]$MaySkip, $Owner = $form) {
    $dialog = [Windows.Forms.Form]@{
        Text = $Caption; ClientSize = [Drawing.Size]::new(610, 175); StartPosition = 'CenterParent'
        FormBorderStyle = 'FixedDialog'; MinimizeBox = $false; MaximizeBox = $false; Font = $form.Font
    }
    $label = [Windows.Forms.Label]@{ Text = $Prompt; Left = 12; Top = 12; Width = 585; Height = 65 }
    $inputBox = [Windows.Forms.TextBox]@{ Text = $Value; Left = 12; Top = 82; Width = 585; AccessibleName = 'DJ' }
    $ok = [Windows.Forms.Button]@{ Text = 'Bestätigen'; Left = 260; Top = 123; Width = 104; Height = 30 }
    $skip = [Windows.Forms.Button]@{ Text = 'Überspringen'; Left = 372; Top = 123; Width = 111; Height = 30; Visible = $MaySkip; DialogResult = 'Ignore' }
    $back = [Windows.Forms.Button]@{ Text = 'Zurück'; Left = 491; Top = 123; Width = 106; Height = 30; DialogResult = 'Cancel' }
    $ok.Add_Click({ if ($inputBox.Text.Trim()) { $dialog.DialogResult = 'OK' } })
    $dialog.Controls.AddRange(@($label, $inputBox, $ok, $skip, $back))
    $dialog.AcceptButton = $ok
    $dialog.CancelButton = $back
    $dialog.ActiveControl = $inputBox
    try {
        Set-WindowTheme $dialog
        $result = $dialog.ShowDialog($Owner)
        [pscustomobject]@{ Result = $result; Artist = $inputBox.Text.Trim() }
    } finally { $dialog.Dispose() }
}

$state = @{ Worker = $null; Handle = $null; Output = $null; Mode = ''; LogIndex = 0; InfoIndex = 0; WarnIndex = 0; Loading = $false }
$queueFile = Join-Path $config 'dj-set-queue.json'
$pending = [Collections.Generic.List[object]]::new()
if ([IO.File]::Exists($queueFile)) {
    try {
        foreach ($entry in ([IO.File]::ReadAllText($queueFile, $utf8) | ConvertFrom-Json)) {
            if ($entry -and $entry.Id -cmatch '^[a-zA-Z0-9_-]{11}$') { $pending.Add($entry) }
        }
    } catch { $status.Text = 'Die gespeicherte Warteschlange konnte nicht gelesen werden.' }
}
function Update-QueueButtons {
    $resume.Enabled = !$state.Worker -and @($pending | Where-Object { !$_.Failed }).Count -gt 0
    $retry.Enabled = !$state.Worker -and @($pending | Where-Object Failed).Count -gt 0
}
function Save-Queue {
    Write-AtomicText $queueFile (ConvertTo-Json -InputObject ($pending.ToArray()) -Depth 4)
}
Update-QueueButtons

$timer = [Windows.Forms.Timer]@{ Interval = 120 }
$workerCode = {
    param($File, $Mode, $Value, $Playlist, $Destination, $Aliases, $StopSignal)
    $ErrorActionPreference = 'Stop'
    . $File -LibraryOnly -ToolRoot (Split-Path -Parent $File) -MusicRoot $Destination
    $jobs = Join-Path $MusicRoot '.dj-set-downloads'
    $archiveIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ([IO.File]::Exists($archive)) {
        foreach ($line in [IO.File]::ReadLines($archive, $utf8)) { [void]$archiveIds.Add($line.Trim()) }
    }
    if ($Mode -eq 'Preview') {
        foreach ($row in (Get-Preview $Value $Playlist $Aliases)) {
            $row | Add-Member NoteProperty Archived ($archiveIds.Contains("youtube $($row.Id)"))
            [pscustomobject]@{ Kind = 'Preview'; Row = $row }
        }
        return
    }
    foreach ($row in $Value) {
        if ($StopSignal.IsSet) { break }
        [pscustomobject]@{ Kind = 'Start'; Id = $row.Id }
        try {
            $savedPath = $null
            Save-Set $row | ForEach-Object {
                if ($_ -is [string]) { [pscustomobject]@{ Kind = 'Log'; Text = $_ } }
                else { $savedPath = $_.SavedSetPath }
            }
            [pscustomobject]@{ Kind = 'Done'; Id = $row.Id; State = 'Archiviert'; Path = $savedPath }
        } catch {
            [pscustomobject]@{ Kind = 'Log'; Text = $_.Exception.Message }
            [pscustomobject]@{ Kind = 'Done'; Id = $row.Id; State = 'Fehler – erneut versuchen' }
        }
    }
}
function Start-Worker($Mode, $Value, $IsPlaylist) {
    $state.Mode = $Mode
    $state.StopSignal = [Threading.ManualResetEventSlim]::new($false)
    $state.LogIndex = $state.InfoIndex = $state.WarnIndex = $state.Errors = 0
    $state.Output = [Management.Automation.PSDataCollection[psobject]]::new()
    $inputData = [Management.Automation.PSDataCollection[psobject]]::new()
    $inputData.Complete()
    $state.Worker = [PowerShell]::Create()
    [void]$state.Worker.AddScript($workerCode.ToString()).AddArgument($core).AddArgument($Mode).AddArgument($Value).AddArgument($IsPlaylist).AddArgument($settings.MusicRoot).AddArgument($aliases.ToArray()).AddArgument($state.StopSignal)
    # Windows PowerShell 5.1 needs reflection to invoke the generic overload.
    $method = [PowerShell].GetMethods() | Where-Object {
        $_.Name -eq 'BeginInvoke' -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 2
    } | Select-Object -First 1
    try {
        $state.Handle = $method.MakeGenericMethod([psobject], [psobject]).Invoke($state.Worker, @($inputData, $state.Output))
    } catch {
        $state.Worker.Dispose()
        $state.Worker = $null
        throw
    }
    $preview.Enabled = $download.Enabled = $bulk.Enabled = $grid.Enabled = $link.Enabled = $playlist.Enabled = $false
    $diagnose.Enabled = $import.Enabled = $options.Enabled = $false
    $stop.Enabled = $Mode -eq 'Download'
    Update-QueueButtons
    $timer.Start()
}
function Add-Log([string]$Line) {
    if ($log.TextLength -gt 40000) { $log.Clear() }
    $log.AppendText($Line + [Environment]::NewLine)
}
function Update-Targets {
    $reserved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $grid.Rows) {
        if (!$item.Tag -or $item.Tag.Archived) { continue }
        $artist = ([string]$item.Cells['Artist'].Value).Trim()
        $title = ([string]$item.Cells['Title'].Value).Trim()
        if (!$title) { $title = $item.Tag.Original }
        $target = if ($artist) {
            Get-SetTarget $settings.MusicRoot @{ Id = $item.Tag.Id; Artist = $artist; Title = $title; Type = $item.Cells['Type'].Value } $reserved
        } else { '' }
        $item.Cells['Target'].Value = $item.Cells['Target'].ToolTipText = $target
        if ($target -and $item.Cells['Selected'].Value) { [void]$reserved.Add($target) }
    }
}

$timer.Add_Tick({
    $worker = $state.Worker
    while ($state.InfoIndex -lt $worker.Streams.Information.Count) {
        Add-Log ([string]$worker.Streams.Information[$state.InfoIndex++].MessageData)
    }
    while ($state.WarnIndex -lt $worker.Streams.Warning.Count) {
        Add-Log $worker.Streams.Warning[$state.WarnIndex++].Message
    }
    while ($state.LogIndex -lt $state.Output.Count) {
        $message = $state.Output[$state.LogIndex++]
        switch ($message.Kind) {
            'Preview' {
                $row = $message.Row
                $label = if ($row.Archived) { 'Archiviert' } elseif ($row.Review) { 'DJ prüfen' } else { 'Bereit' }
                $state.Loading = $true
                try {
                    $index = $grid.Rows.Add(!$row.Archived, $row.Artist, $row.Title, $row.Original, $label, '', $row.Type)
                    $grid.Rows[$index].Tag = $row
                    if ($row.Archived) { $grid.Rows[$index].ReadOnly = $true }
                } finally { $state.Loading = $false }
            }
            'Start' {
                $item = $state.ById[$message.Id]
                $item.Cells['Status'].Value = 'Lädt …'
                $status.Text = "Set $($state.Completed + 1) von $($state.Total) · $($item.Tag.Title)"
                $progress.Style = 'Marquee'
            }
            'Log' {
                if ($message.Text -match '\[download\]\s+(\d+(?:\.\d+)?)%') {
                    $progress.Style = 'Continuous'
                    $percent = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
                    $progress.Value = [Math]::Min(100, [int]$percent)
                }
                Add-Log $message.Text
            }
            'Done' {
                $item = $state.ById[$message.Id]
                $item.Cells['Status'].Value = $message.State
                if ($message.State -eq 'Archiviert') {
                    $item.Tag.Archived = $true
                    if ($message.Path) {
                        $item.Cells['Target'].Value = $message.Path
                        $item.Cells['Target'].ToolTipText = $message.Path
                    } else { $item.Cells['Target'].Value = $null }
                    $item.Cells['Selected'].Value = $false
                    $item.ReadOnly = $true
                } else {
                    $state.Errors++
                    Write-AppError 'Download' ("Video {0}: Set konnte nicht gespeichert werden." -f $message.Id)
                }
                $entry = $pending | Where-Object { $_.Id -ceq $message.Id } | Select-Object -First 1
                if ($entry) {
                    if ($message.State -eq 'Archiviert') { [void]$pending.Remove($entry) }
                    else { $entry.Failed = $true }
                    try { Save-Queue } catch { Add-Log "Warteschlange konnte nicht aktualisiert werden: $($_.Exception.Message)" }
                }
                $state.Completed++
                $progress.Style = 'Continuous'
                $progress.Value = 100
            }
        }
    }
    if (!$state.Handle.IsCompleted -or $state.LogIndex -lt $state.Output.Count) { return }
    $timer.Stop()
    $diagnose.Enabled = $import.Enabled = $options.Enabled = $true
    $failure = $false
    try { [void]$worker.EndInvoke($state.Handle) } catch { Add-Log $_.Exception.Message; $failure = $true; Write-AppError $state.Mode "Hintergrundvorgang fehlgeschlagen (Code $($_.Exception.HResult))." }
    foreach ($errorRecord in $worker.Streams.Error) { Add-Log $errorRecord.ToString() }
    $stopped = $state.Mode -eq 'Download' -and $state.StopSignal.IsSet -and $state.Completed -lt $state.Total
    $state.StopSignal.Dispose()
    $stop.Enabled = $false
    $worker.Dispose()
    $state.Worker = $null
    Update-QueueButtons
    $progress.Style = 'Continuous'
    $preview.Enabled = $grid.Enabled = $link.Enabled = $playlist.Enabled = $true
    $available = @($grid.Rows | Where-Object { !$_.Tag.Archived }).Count -gt 0
    $download.Enabled = $bulk.Enabled = $available
    Update-Targets
    $status.Text = if ($failure) { 'Vorgang fehlgeschlagen. Details stehen unten.' }
        elseif ($state.Mode -eq 'Preview') { "$($grid.Rows.Count) Einträge · DJ und Set-Titel lassen sich direkt bearbeiten." }
        elseif ($stopped) { "Gestoppt · $($state.Total - $state.Completed) Sets offen · $($state.Errors) Fehler" }
        else { "$($state.Completed - $state.Errors) von $($state.Total) Sets gespeichert · $($state.Errors) Fehler" }
})
function Find-ArchivedSet($Root, $Id) {
    foreach ($entry in (Get-LibrarySets $Root)) {
        $info = Join-Path $entry.Path 'info.json'
        if (![IO.File]::Exists($info)) { continue }
        try { $metadata = Get-Content -LiteralPath $info -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { continue }
        if ($metadata.id -ceq $Id) { return $entry.Path }
    }
}
$grid.Add_CellDoubleClick({
    param($sender, $eventArgs)
    if ($eventArgs.RowIndex -lt 0) { return }
    $item = $grid.Rows[$eventArgs.RowIndex]
    if (!$item.Tag.Archived) { return }
    $path = [string]$item.Cells['Target'].Value
    if (!$path -or ![IO.Directory]::Exists($path)) {
        $path = Find-ArchivedSet $settings.MusicRoot $item.Tag.Id
    }
    if (!$path) {
        $status.Text = 'Der archivierte Set-Ordner wurde im aktuellen Downloadordner nicht gefunden.'
        return
    }
    $item.Cells['Target'].Value = $item.Cells['Target'].ToolTipText = $path
    try { Start-Process explorer.exe ('"{0}"' -f $path) }
    catch { $status.Text = $_.Exception.Message }
})
$grid.Add_CurrentCellDirtyStateChanged({
    if ($grid.IsCurrentCellDirty -and $grid.CurrentCell.OwningColumn.Name -in @('Selected','Type')) {
        [void]$grid.CommitEdit('Commit')
    }
})
$grid.Add_CellValueChanged({
    param($sender, $eventArgs)
    if ($state.Loading -or $eventArgs.RowIndex -lt 0 -or $eventArgs.ColumnIndex -notin @(0, 1, 2, 6)) { return }
    $item = $grid.Rows[$eventArgs.RowIndex]
    if (!$item.Tag -or $item.Tag.Archived) { return }
    if ($eventArgs.ColumnIndex -eq 1) {
        $item.Tag.Review = !([string]$item.Cells['Artist'].Value).Trim()
        $item.Cells['Status'].Value = if ($item.Tag.Review) { 'DJ prüfen' } else { 'Bereit' }
    }
    if (!$state.Worker) { Update-Targets }
})
$preview.Add_Click({
    $url = $link.Text.Trim()
    $uri = $null
    if (![uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http','https') -or
        $uri.Host -notmatch '^(?:[a-z0-9-]+\.)*youtube\.com$|^(?:www\.)?youtu\.be$') {
        $status.Text = 'Bitte einen vollständigen YouTube-Link eingeben.'
        return
    }
    $isPlaylist = $uri.AbsolutePath.TrimEnd('/') -eq '/playlist' -or ($playlist.Checked -and $uri.Query -match '[?&]list=')
    if (!$isPlaylist -and $uri.AbsolutePath -notmatch '^/(watch|shorts/[^/]+|live/[^/]+|embed/[^/]+|[^/]{11})/?$') {
        $status.Text = 'Bitte einen Video- oder Playlist-Link eingeben.'
        return
    }
    $download.Enabled = $bulk.Enabled = $false
    $grid.Rows.Clear()
    $log.Clear()
    $status.Text = 'Vorschau wird geladen …'
    $progress.Style = 'Marquee'
    try { Start-Worker 'Preview' $url $isPlaylist }
    catch { $progress.Style = 'Continuous'; $status.Text = $_.Exception.Message }
})
$bulk.Add_Click({
    [void]$grid.EndEdit()
    $items = @($grid.SelectedRows | Where-Object { !$_.Tag.Archived })
    if (!$items.Count) { $status.Text = 'Markiere zuerst die gewünschten Zeilen.'; return }
    $answer = Ask-DJ 'DJ zuweisen' "Name für $($items.Count) markierte Einträge" '' $false
    if ($answer.Result -eq 'OK') {
        foreach ($item in $items) { $item.Cells['Artist'].Value = $answer.Artist }
    }
})
$download.Add_Click({
    [void]$grid.EndEdit()
    $selected = @($grid.Rows | Where-Object { $_.Cells['Selected'].Value -and !$_.Tag.Archived })
    $state.ById = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $queue = @(foreach ($item in $selected) {
        $row = $item.Tag
        $row.Type = $item.Cells['Type'].Value
        $row.Artist = ([string]$item.Cells['Artist'].Value).Trim()
        $row.Title = ([string]$item.Cells['Title'].Value).Trim()
        if (!$row.Title) { $row.Title = $row.Original }
        if ($row.Review -or !$row.Artist) {
            $answer = Ask-DJ 'DJ prüfen' $row.Original $row.Artist $true
            if ($answer.Result -eq 'Ignore') { $item.Cells['Selected'].Value = $false; continue }
            if ($answer.Result -ne 'OK') { $status.Text = 'Downloadstart abgebrochen.'; return }
            $row.Artist = $item.Cells['Artist'].Value = $answer.Artist
            $row.Review = $false
            $item.Cells['Status'].Value = 'Bereit'
        }
        $state.ById.Add($row.Id, $item)
        $row
    })
    if (!$queue.Count) { $status.Text = 'Keine Sets zum Download ausgewählt.'; return }
    $state.Total = $queue.Count
    $state.Completed = 0
    $progress.Value = 0
    try {
        foreach ($row in $queue) {
            $old = $pending | Where-Object { $_.Id -ceq $row.Id } | Select-Object -First 1
            if ($old) { [void]$pending.Remove($old) }
            $pending.Add([pscustomobject]@{
                Id = $row.Id; Artist = $row.Artist; Title = $row.Title; Original = $row.Original; Type = $row.Type; Failed = $false
            })
        }
        Save-Queue
        Start-Worker 'Download' $queue $false
    } catch { Update-QueueButtons; $status.Text = $_.Exception.Message }
})
$stop.Add_Click({
    $state.StopSignal.Set()
    $stop.Enabled = $false
    Add-Log 'Stopp angefordert. Das laufende Set wird fertig verarbeitet.'
})
function Show-SavedQueue([bool]$Failed) {
    $entries = @($pending | Where-Object { [bool]$_.Failed -eq $Failed })
    if (!$entries.Count) { return }
    if ($grid.IsCurrentCellInEditMode) { [void]$grid.EndEdit() }
    $grid.Rows.Clear()
    $state.Loading = $true
    try {
        foreach ($entry in $entries) {
            $label = if ($entry.Failed) { 'Fehler – erneut versuchen' } else { 'Bereit' }
            $index = $grid.Rows.Add($true, $entry.Artist, $entry.Title, $entry.Original, $label, '', $(if ($entry.Type -eq 'Track') { 'Track' } else { 'Set' }))
            $grid.Rows[$index].Tag = [pscustomobject]@{
                Id = $entry.Id; Artist = $entry.Artist; Title = $entry.Title; Original = $entry.Original
                Type = $entry.Type; Review = !$entry.Artist; Archived = $false
            }
        }
    } finally { $state.Loading = $false }
    Update-Targets
    $download.Enabled = $bulk.Enabled = $true
    $status.Text = "$($entries.Count) Sets geladen. Auswahl prüfen und auf Download starten klicken."
}
$resume.Add_Click({ Show-SavedQueue $false })
$retry.Add_Click({ Show-SavedQueue $true })

function Save-ConfigurationBackup([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Assert-SafePath $Path
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $zip = [IO.Compression.ZipFile]::Open($temporary, 'Create')
        try {
            foreach ($name in @('dj-set-gui.json','downloaded.txt','dj-set-queue.json','dj-set-aliases.json')) {
                $source = Join-Path $config $name
                Assert-SafePath $source
                if ([IO.File]::Exists($source)) {
                    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $source, "config/$name")
                } elseif ($name -eq 'dj-set-gui.json') {
                    $writer = [IO.StreamWriter]::new($zip.CreateEntry("config/$name").Open(), $utf8)
                    try { $writer.Write((ConvertTo-Json -InputObject $settings)) } finally { $writer.Dispose() }
                }
            }
        } finally { $zip.Dispose() }
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally { [IO.File]::Delete($temporary) }
}

function Restore-ConfigurationBackup([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Assert-SafePath $Path
    $names = @('dj-set-gui.json','downloaded.txt','dj-set-queue.json','dj-set-aliases.json')
    $data = @{}
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.Name
            if ($name -cnotin $names -or $entry.FullName -cne "config/$name" -or $data.ContainsKey($name) -or $entry.Length -gt 16MB) {
                throw 'Ungültiger Eintrag in der Konfigurationssicherung.'
            }
            $reader = [IO.StreamReader]::new($entry.Open(), [Text.UTF8Encoding]::new($false,$true))
            try { $data[$name] = $reader.ReadToEnd() } finally { $reader.Dispose() }
            if ($name.EndsWith('.json')) { $null = ConvertFrom-Json -InputObject $data[$name] }
        }
    } finally { $zip.Dispose() }
    if (!$data.ContainsKey('dj-set-gui.json')) { throw 'Die Einstellungen fehlen im ZIP.' }
    $saved = ConvertFrom-Json -InputObject $data['dj-set-gui.json']
    if ($saved.MusicRoot -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)' -or $saved.Playlist -isnot [bool]) {
        throw 'Ungültige Einstellungen im ZIP.'
    }
    $previous = @{}
    foreach ($name in $names) {
        $target = Join-Path $config $name
        Assert-SafePath $target
        if ([IO.File]::Exists($target)) { $previous[$name] = [IO.File]::ReadAllText($target,$utf8) }
    }
    $backup = Join-Path (Split-Path -Parent $config) ("Vor-Wiederherstellung-$([guid]::NewGuid()).zip")
    Save-ConfigurationBackup $backup
    $changed = [Collections.Generic.List[string]]::new()
    try {
        foreach ($name in $names) {
            $target = Join-Path $config $name
            if ($data.ContainsKey($name)) { Write-AtomicText $target $data[$name] }
            else { [IO.File]::Delete($target) }
            $changed.Add($name)
        }
    } catch {
        $failure = $_
        try {
            foreach ($name in $changed) {
                $target = Join-Path $config $name
                if ($previous.ContainsKey($name)) { Write-AtomicText $target $previous[$name] }
                else { [IO.File]::Delete($target) }
            }
        } catch { throw "Rückgängig fehlgeschlagen. Sicherung: $backup. $($_.Exception.Message)" }
        throw $failure
    }
    return $backup
}

$options.Add_Click({
    $dialog = [Windows.Forms.Form]@{
        Text = 'Einstellungen'; ClientSize = [Drawing.Size]::new(650, 270)
        StartPosition = 'CenterParent'; FormBorderStyle = 'FixedDialog'
        MinimizeBox = $false; MaximizeBox = $false; Font = $form.Font
    }
    $label = [Windows.Forms.Label]@{ Text = 'Downloadordner'; Left = 12; Top = 12; AutoSize = $true }
    $pathBox = [Windows.Forms.TextBox]@{ Text = $settings.MusicRoot; Left = 12; Top = 39; Width = 495 }
    $browse = [Windows.Forms.Button]@{ Text = 'Durchsuchen …'; Left = 515; Top = 36; Width = 123; Height = 30 }
    $defaultPlaylist = [Windows.Forms.CheckBox]@{
        Text = 'Ganze Playlist beim Start vorauswählen'; Left = 12; Top = 79
        AutoSize = $true; Checked = $settings.Playlist
    }
    $hint = [Windows.Forms.Label]@{
        Text = 'Der neue Ordner gilt für künftige Downloads.'; Left = 12; Top = 111; AutoSize = $true
    }
    $themeLabel = [Windows.Forms.Label]@{ Text='Darstellung'; Left=12; Top=145; AutoSize=$true }
    $theme = [Windows.Forms.ComboBox]@{ Left=123; Top=141; Width=160; DropDownStyle='DropDownList'; AccessibleName='Darstellung' }
    $theme.Items.AddRange(@('System','Hell','Dunkel'))
    $theme.SelectedItem = $settings.Theme
    $save = [Windows.Forms.Button]@{ Text = 'Speichern'; Left = 407; Top = 222; Width = 110; Height = 32 }
    $cancel = [Windows.Forms.Button]@{ Text = 'Abbrechen'; Left = 525; Top = 222; Width = 113; Height = 32; DialogResult = 'Cancel' }
    $browse.Add_Click({
        $picker = [Windows.Forms.FolderBrowserDialog]@{ Description = 'Downloadordner auswählen'; SelectedPath = $pathBox.Text }
        try {
            if ($picker.ShowDialog($dialog) -eq 'OK') { $pathBox.Text = $picker.SelectedPath }
        } finally { $picker.Dispose() }
    })
    $save.Add_Click({
        try {
            $path = $pathBox.Text.Trim()
            if ($path -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)') { throw 'Bitte einen vollständigen Ordnerpfad eingeben.' }
            $path = [IO.Path]::GetFullPath($path)
            Assert-SafePath $path
            [void][IO.Directory]::CreateDirectory($path)
            $newSettings = @{ MusicRoot = $path; Playlist = $defaultPlaylist.Checked; Theme = [string]$theme.SelectedItem }
            Write-AtomicText $settingsPath (ConvertTo-Json -InputObject $newSettings)
            $settings.MusicRoot = $path
            $settings.Playlist = $defaultPlaylist.Checked
            $playlist.Checked = $settings.Playlist
            $destination.Text = "Downloadordner: $path"
            Update-Targets
            if ($settings.Theme -ne $newSettings.Theme) {
                $settings.Theme = $newSettings.Theme
                [void][Windows.Forms.MessageBox]::Show($dialog,'Die Darstellung wird beim nächsten Start übernommen.','Darstellung')
            }
            $dialog.DialogResult = 'OK'
        } catch { [void][Windows.Forms.MessageBox]::Show($dialog, $_.Exception.Message, 'Einstellungen') }
    })
    $backup = [Windows.Forms.Button]@{ Text = 'Konfiguration sichern …'; Left = 12; Top = 182; AutoSize = $true; Height = 32 }
    $backup.Add_Click({
        $picker = [Windows.Forms.SaveFileDialog]@{
            Filter = 'ZIP-Archiv (*.zip)|*.zip'; DefaultExt = 'zip'
            FileName = "Plattenkoffer-Konfiguration-$(Get-Date -Format yyyy-MM-dd).zip"
        }
        try {
            if ($picker.ShowDialog($dialog) -ne 'OK') { return }
            Save-ConfigurationBackup $picker.FileName
            [void][Windows.Forms.MessageBox]::Show($dialog, 'Die gespeicherte Konfiguration wurde gesichert.', 'Konfiguration sichern')
        } catch { [void][Windows.Forms.MessageBox]::Show($dialog, $_.Exception.Message, 'Konfiguration sichern') }
        finally { $picker.Dispose() }
    })
    $restore = [Windows.Forms.Button]@{ Text='Konfiguration wiederherstellen …'; Left=220; Top=182; Height=32; AutoSize=$true }
    $restore.Add_Click({
        $picker = [Windows.Forms.OpenFileDialog]@{ Filter='ZIP-Archiv (*.zip)|*.zip' }
        try {
            if ($picker.ShowDialog($dialog) -ne 'OK') { return }
            if ([Windows.Forms.MessageBox]::Show($dialog,'Das ZIP ersetzt die aktuelle Konfiguration und Plattenkoffer wird danach geschlossen. Fortfahren?','Konfiguration wiederherstellen','YesNo','Question','Button2') -ne 'Yes') { return }
            $previous = Restore-ConfigurationBackup $picker.FileName
            [void][Windows.Forms.MessageBox]::Show($dialog,"Bitte Plattenkoffer neu starten. Vorherige Konfiguration: $previous",'Konfiguration wiederherstellen')
            $dialog.DialogResult = 'Retry'
        } catch { [void][Windows.Forms.MessageBox]::Show($dialog,$_.Exception.Message,'Konfiguration wiederherstellen') }
        finally { $picker.Dispose() }
    })
    $dialog.Controls.AddRange(@($label, $pathBox, $browse, $defaultPlaylist, $hint, $themeLabel, $theme, $backup, $restore, $save, $cancel))
    $dialog.AcceptButton = $save
    $dialog.CancelButton = $cancel
    Set-WindowTheme $dialog
    try { if ($dialog.ShowDialog($form) -eq 'Retry') { $form.Close() } } finally { $dialog.Dispose() }
})
$folder.Add_Click({
    if ([IO.Directory]::Exists($settings.MusicRoot)) {
        Start-Process explorer.exe ('"{0}"' -f $settings.MusicRoot)
    } else { $status.Text = 'Der Downloadordner ist derzeit nicht erreichbar.' }
})
function Show-LocalImport([string[]]$Paths) {
    $dialog = [Windows.Forms.Form]@{ Text='Lokale MP3s einsortieren'; Width=1040; Height=470; StartPosition='CenterParent'; Font=$form.Font }
    $table = [Windows.Forms.DataGridView]@{
        Dock='Fill'; AllowUserToAddRows=$false; AllowUserToDeleteRows=$false; RowHeadersVisible=$false
        AutoSizeColumnsMode='Fill'
    }
    foreach ($name in @('Datei','DJ','Set-Titel','Zielordner')) {
        $column = [Windows.Forms.DataGridViewTextBoxColumn]@{
            Name=$name; HeaderText=$name; ReadOnly=$name -in @('Datei','Zielordner'); SortMode='NotSortable'
        }
        [void]$table.Columns.Add($column)
    }
    function Refresh-ImportTargets {
        foreach ($row in $table.Rows) {
            $artist = ([string]$row.Cells['DJ'].Value).Trim()
            $title = ([string]$row.Cells['Set-Titel'].Value).Trim()
            $target = if ($artist -and $title) {
                Join-Path (Join-Path (Join-Path $settings.MusicRoot (Safe-Name $artist)) 'Sets') (Safe-Name $title)
            } else { '' }
            $row.Cells['Zielordner'].Value = $row.Cells['Zielordner'].ToolTipText = $target
        }
    }
    foreach ($path in ($Paths | Sort-Object -Unique)) {
        $file = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if (!$file -or $file.PSIsContainer -or $file.Extension -ne '.mp3') { continue }
        $name = ($file.BaseName -replace '(?i)\s*[-_ ]?\s*\(?\b(?:part|teil|pt\.?|cd)\s*\d+\)?\s*$','').Trim()
        $artist = ''
        if ($name -match '^(.+?)\s+(?:@|at|-|–|—|_)\s+(.+)$') {
            $artist = $Matches[1].Trim()
            $name = $Matches[2].Trim()
        }
        $index = $table.Rows.Add($file.Name, $artist, $name, '')
        $table.Rows[$index].Tag = $file.FullName
    }
    if (!$table.Rows.Count) { $dialog.Dispose(); $status.Text = 'Keine MP3-Dateien ausgewählt.'; return }
    Refresh-ImportTargets
    $table.Add_CellValueChanged({
        param($sender, $eventArgs)
        if ($eventArgs.RowIndex -ge 0 -and $eventArgs.ColumnIndex -in @(1,2)) { Refresh-ImportTargets }
    })
    $actions = [Windows.Forms.FlowLayoutPanel]@{ Dock='Bottom'; Height=46 }
    $commit = [Windows.Forms.Button]@{ Text='Dateien verschieben'; AutoSize=$true }
    $cancel = [Windows.Forms.Button]@{ Text='Schließen'; AutoSize=$true; DialogResult='Cancel' }
    $hint = [Windows.Forms.Label]@{ Text='Gleicher DJ und Set-Titel gruppieren mehrere Teile.'; AutoSize=$true; Margin=[Windows.Forms.Padding]::new(8,8,0,0) }
    $actions.Controls.AddRange(@($commit,$cancel,$hint))
    $dialog.Controls.Add($table)
    $dialog.Controls.Add($actions)
    $dialog.CancelButton = $cancel
    $commit.Add_Click({
        [void]$table.EndEdit()
        Refresh-ImportTargets
        try {
            $reserved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            $plan = @(foreach ($row in $table.Rows) {
                $dir = [string]$row.Cells['Zielordner'].Value
                if (!$dir) { throw 'Bitte für jede Datei DJ und Set-Titel eingeben.' }
                $source = [string]$row.Tag
                $target = Join-Path $dir ([IO.Path]::GetFileName($source))
                Assert-SafePath $source
                Assert-SafePath $target
                $same = [string]::Equals($source,$target,[StringComparison]::OrdinalIgnoreCase)
                if (![IO.File]::Exists($source)) { throw "Datei fehlt: $source" }
                if (!$reserved.Add($target) -or (!$same -and (Test-Path -LiteralPath $target))) {
                    throw "Dateiname am Ziel bereits belegt: $target"
                }
                [pscustomobject]@{ Row=$row; Source=$source; Target=$target; Directory=$dir; Same=$same }
            })
            foreach ($move in $plan) {
                if (!$move.Same) {
                    [void][IO.Directory]::CreateDirectory($move.Directory)
                    [IO.File]::Move($move.Source,$move.Target)
                    $move.Row.Tag = $move.Target
                }
            }
            $status.Text = "$($plan.Count) MP3-Dateien einsortiert."
            $dialog.DialogResult = 'OK'
        } catch { [void][Windows.Forms.MessageBox]::Show($dialog, $_.Exception.Message, 'MP3-Import') }
    })
    Set-WindowTheme $dialog
    try { [void]$dialog.ShowDialog($form) } finally { $dialog.Dispose() }
}
$import.Add_Click({
    $picker = [Windows.Forms.OpenFileDialog]@{ Filter='MP3-Dateien (*.mp3)|*.mp3'; Multiselect=$true }
    try { if ($picker.ShowDialog($form) -eq 'OK') { Show-LocalImport $picker.FileNames } }
    finally { $picker.Dispose() }
})
foreach ($dropSurface in @($form,$grid)) {
    $dropSurface.AllowDrop = $true
    $dropSurface.Add_DragEnter({
        param($sender,$eventArgs)
        if (!$state.Worker -and $eventArgs.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
            $eventArgs.Effect = 'Move'
        }
    })
    $dropSurface.Add_DragDrop({
        param($sender,$eventArgs)
        if (!$state.Worker -and $eventArgs.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
            Show-LocalImport ($eventArgs.Data.GetData([Windows.Forms.DataFormats]::FileDrop))
        }
    })
}

function Get-SetAudio([string]$Path) {
    Get-ChildItem -LiteralPath $Path -File | Where-Object Extension -in @('.mp3','.opus','.m4a','.aac','.flac','.wav','.ogg','.webm') |
        Sort-Object @{ Expression = {
            [regex]::Replace($_.Name, '[0-9]+', { param($number) $number.Value.PadLeft(20, '0') })
        } }, Name
}

function Show-SetPlayback($Owner, [string]$Path) {
    Assert-SafePath $Path
    $tracks = @(Get-SetAudio $Path)
    if (!$tracks.Count) { throw 'Keine Audiodateien gefunden.' }
    $player = Join-Path $PSScriptRoot 'bin\ffplay.exe'
    Assert-SafePath $player
    $window = [Windows.Forms.Form]@{
        Text = 'Plattenkoffer – Wiedergabe'; ClientSize = [Drawing.Size]::new(552, 230)
        StartPosition = 'CenterParent'; Font = $form.Font
    }
    $trackLabel = [Windows.Forms.Label]@{ Left=12; Top=10; Width=525; Height=48 }
    $position = [Windows.Forms.TrackBar]@{ Left=10; Top=60; Width=525; TickStyle='None'; AccessibleName='Position im aktuellen Teil' }
    $time = [Windows.Forms.Label]@{ Left=12; Top=102; Width=520; Height=24 }
    $pause = [Windows.Forms.Button]@{ Text='Pause'; Left=12; Top=145; Width=115 }
    $stopPlayback = [Windows.Forms.Button]@{ Text='Stoppen'; Left=135; Top=145; Width=90 }
    $volumeLabel = [Windows.Forms.Label]@{ Text='Lautstärke'; Left=265; Top=145; AutoSize=$true }
    $volume = [Windows.Forms.TrackBar]@{ Left=350; Top=138; Width=185; Maximum=100; TickStyle='None'; AccessibleName='Lautstärke' }
    $volume.Value = 80
    $window.Controls.AddRange(@($trackLabel,$position,$time,$pause,$stopPlayback,$volumeLabel,$volume))
    $playback = @{ Index=0; Process=$null; Error=''; Offset=0.0; Duration=0.0; Paused=$false; Clock=[Diagnostics.Stopwatch]::new() }
    $poll = [Windows.Forms.Timer]@{ Interval=200 }
    function Stop-Track {
        $playback.Clock.Stop()
        if ($playback.Process) {
            try { if (!$playback.Process.HasExited) { $playback.Process.Kill(); $playback.Process.WaitForExit(1500) | Out-Null } }
            catch [InvalidOperationException] {}
            finally { $playback.Process.Dispose(); $playback.Process=$null }
        }
    }
    function Start-Track {
        Stop-Track
        $offset = $playback.Offset.ToString('0.###',[Globalization.CultureInfo]::InvariantCulture)
        $playback.Process = Start-Process -FilePath $player -ArgumentList (
            '-nodisp -autoexit -loglevel error -ss {0} -volume {1} -i "{2}"' -f $offset,$volume.Value,$tracks[$playback.Index].FullName
        ) -WindowStyle Hidden -PassThru
        $playback.Clock.Restart()
    }
    function Load-Track {
        $track = $tracks[$playback.Index]
        Assert-SafePath $track.FullName
        $seconds = & $probe -v error -show_entries format=duration -of 'csv=p=0' $track.FullName
        $duration = 0.0
        $known = $LASTEXITCODE -eq 0 -and [double]::TryParse([string]$seconds,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$duration) -and $duration -gt 0 -and $duration -lt [int]::MaxValue
        $playback.Duration = if ($known) { $duration } else { 0.0 }
        $position.Enabled = $known
        $position.Value = 0
        $position.Maximum = [Math]::Max(1,[int][Math]::Ceiling($playback.Duration))
        $playback.Offset = 0.0
        $trackLabel.Text = "Teil $($playback.Index + 1) von $($tracks.Count)`r`n$($track.Name)"
        Start-Track
    }
    function Invoke-PlaybackAction([scriptblock]$Action) {
        try { & $Action }
        catch { $playback.Error = $_.Exception.Message; $window.Close() }
    }
    $poll.Add_Tick({
        Invoke-PlaybackAction {
            if ($playback.Process -and $playback.Process.HasExited) {
                $code = $playback.Process.ExitCode
                Stop-Track
                if ($code -ne 0) { throw "Wiedergabe fehlgeschlagen (Code $code)." }
                $playback.Index++
                if ($playback.Index -ge $tracks.Count) { $window.Close(); return }
                Load-Track
            }
            $elapsed = $playback.Offset + $(if ($playback.Paused) { 0 } else { $playback.Clock.Elapsed.TotalSeconds })
            if ($position.Enabled -and !$position.Capture) { $position.Value = [Math]::Min($position.Maximum,[int][Math]::Floor($elapsed)) }
            $time.Text = '{0:hh\:mm\:ss} / {1}' -f [timespan]::FromSeconds($elapsed), $(if ($position.Enabled) { [timespan]::FromSeconds($playback.Duration).ToString('hh\:mm\:ss') } else { '–' })
        }
    })
    $pause.Add_Click({
        Invoke-PlaybackAction {
            if ($playback.Paused) {
                Start-Track
                $playback.Paused=$false
                $pause.Text='Pause'
            } else {
                $playback.Offset += $playback.Clock.Elapsed.TotalSeconds
                Stop-Track
                $playback.Paused=$true
                $pause.Text='Fortsetzen'
            }
        }
    })
    $seek = {
        Invoke-PlaybackAction {
            $playback.Offset = [Math]::Min($position.Value,[Math]::Max(0,$playback.Duration - 0.05))
            if (!$playback.Paused) { Start-Track }
        }
    }
    $position.Add_MouseUp($seek)
    $position.Add_KeyUp($seek)
    $changeVolume = {
        if (!$playback.Paused) {
            Invoke-PlaybackAction {
                $playback.Offset += $playback.Clock.Elapsed.TotalSeconds
                Start-Track
            }
        }
    }
    $volume.Add_MouseUp($changeVolume)
    $volume.Add_KeyUp($changeVolume)
    $stopPlayback.Add_Click({ $window.Close() })
    $window.Add_Shown({ Invoke-PlaybackAction { Load-Track; $poll.Start() } })
    Set-WindowTheme $window
    try { [void]$window.ShowDialog($Owner) }
    finally { $poll.Dispose(); Stop-Track; $window.Dispose() }
    if ($playback.Error) { throw $playback.Error }
}

function Get-LibrarySets([string]$Root) {
    foreach ($artist in (Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name)) {
        foreach ($type in @('Sets','Tracks')) {
            $category = Join-Path $artist.FullName $type
            if (![IO.Directory]::Exists($category)) { continue }
            foreach ($entry in (Get-ChildItem -LiteralPath $category -Directory | Sort-Object Name)) {
                if (Get-SetAudio $entry.FullName | Select-Object -First 1) {
                    [pscustomobject]@{ Artist=$artist.Name; Title=$entry.Name; Path=$entry.FullName; Type=$type }
                }
            }
        }
    }
}

function Export-LibrarySet($SetPath, $Root, $Mode, [int]$Bitrate) {
    Assert-SafePath $SetPath
    $tracks = @(Get-SetAudio $SetPath)
    foreach ($track in $tracks) { Assert-SafePath $track.FullName }
    if (!$tracks.Count) { throw 'Keine Audiodateien im Set gefunden.' }
    $rootPath = [IO.Path]::GetFullPath($Root)
    Assert-SafePath $rootPath
    [void][IO.Directory]::CreateDirectory($rootPath)
    $name = Safe-Name (Split-Path -Leaf $SetPath)
    $target = Join-Path $rootPath $name
    for ($n = 2; (Test-Path -LiteralPath $target); $n++) { $target = Join-Path $rootPath "$name ($n)" }
    $temp = Join-Path $rootPath ('.dj-export-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($temp)
    try {
        if ($Mode -eq 'Join' -and $tracks.Count -gt 1) {
            # Normalize each input to PCM before joining, including mixed codecs and sample rates.
            $parts = @(for ($i = 0; $i -lt $tracks.Count; $i++) {
                $part = "part-$i.wav"
                & $ffmpeg -nostdin -v error -i $tracks[$i].FullName -map 0:a:0 -ac 2 -ar 48000 -c:a pcm_s16le (Join-Path $temp $part)
                if ($LASTEXITCODE -ne 0) { throw "FFmpeg konnte Teil $($i + 1) nicht lesen." }
                $part
            })
            $list = Join-Path $temp 'parts.txt'
            [IO.File]::WriteAllLines($list, [string[]]@($parts | ForEach-Object { "file '$_'" }), $utf8)
            & $ffmpeg -nostdin -v error -f concat -safe 1 -i $list -c:a libmp3lame -b:a "${Bitrate}k" (Join-Path $temp "$name.mp3")
            if ($LASTEXITCODE -ne 0) { throw 'FFmpeg konnte die Teile nicht zusammenfügen.' }
            foreach ($part in $parts) { [IO.File]::Delete((Join-Path $temp $part)) }
            [IO.File]::Delete($list)
        } else {
            for ($i = 0; $i -lt $tracks.Count; $i++) {
                $track = $tracks[$i]
                $extension = if ($Mode -eq 'Copy') { $track.Extension } else { '.mp3' }
                $filename = if ($tracks.Count -gt 1) { '{0:D2} - {1}{2}' -f ($i + 1), (Safe-Name $track.BaseName), $extension }
                    else { (Safe-Name $track.BaseName) + $extension }
                $output = Join-Path $temp $filename
                if ($Mode -eq 'Copy') { [IO.File]::Copy($track.FullName, $output) }
                else {
                    & $ffmpeg -nostdin -v error -i $track.FullName -map 0:a:0 -c:a libmp3lame -b:a "${Bitrate}k" $output
                    if ($LASTEXITCODE -ne 0) { throw "MP3-Export fehlgeschlagen: $($track.Name)" }
                }
            }
        }
        [IO.Directory]::Move($temp, $target)
        $target
    } finally {
        if ([IO.Directory]::Exists($temp)) {
            foreach ($file in [IO.Directory]::GetFiles($temp)) { [IO.File]::Delete($file) }
            [IO.Directory]::Delete($temp)
        }
    }
}

function Show-SetExport($Owner, $SetPath) {
    $dialog = [Windows.Forms.Form]@{
        Text = 'Set exportieren'; ClientSize = [Drawing.Size]::new(610, 235); StartPosition = 'CenterParent'
        FormBorderStyle = 'FixedDialog'; MinimizeBox = $false; MaximizeBox = $false; Font = $form.Font
    }
    $label = [Windows.Forms.Label]@{ Text='Zielordner'; Left=12; Top=12; AutoSize=$true }
    $path = [Windows.Forms.TextBox]@{ Left=12; Top=37; Width=460 }
    $browse = [Windows.Forms.Button]@{ Text='Durchsuchen …'; Left=480; Top=34; Width=118; Height=30 }
    $format = [Windows.Forms.ComboBox]@{ Left=12; Top=78; Width=345; DropDownStyle='DropDownList'; AccessibleName='Exportformat' }
    $format.Items.AddRange(@('Originalkopie (nummerierte Teile)', 'MP3 (nummerierte Teile)', 'Eine durchgehende MP3'))
    $rate = [Windows.Forms.ComboBox]@{ Left=375; Top=78; Width=145; DropDownStyle='DropDownList'; AccessibleName='MP3-Bitrate' }
    $rate.Items.AddRange(@('128 kbit/s','192 kbit/s','256 kbit/s','320 kbit/s'))
    $rate.SelectedIndex = 2
    $format.Add_SelectedIndexChanged({ $rate.Enabled = $format.SelectedIndex -gt 0 })
    $format.SelectedIndex = 0
    $feedback = [Windows.Forms.Label]@{ Left=12; Top=122; Width=585; Height=60; Text='Der Export wird in einem eigenen Set-Ordner abgelegt.' }
    $start = [Windows.Forms.Button]@{ Text='Exportieren'; Left=360; Top=190; Width=115; Height=32 }
    $close = [Windows.Forms.Button]@{ Text='Schließen'; Left=483; Top=190; Width=115; Height=32; DialogResult='Cancel' }
    $browse.Add_Click({
        $picker = [Windows.Forms.FolderBrowserDialog]@{ Description='Exportziel auswählen' }
        try { if ($picker.ShowDialog($dialog) -eq 'OK') { $path.Text = $picker.SelectedPath } }
        finally { $picker.Dispose() }
    })
    $export = @{ Worker=$null; Handle=$null }
    $refresh = [Windows.Forms.Timer]@{ Interval=150 }
    $refresh.Add_Tick({
        if (!$export.Handle.IsCompleted) { return }
        $refresh.Stop()
        try {
            $result = $export.Worker.EndInvoke($export.Handle)
            $feedback.Text = "Export fertig: $($result[-1])"
        } catch { $feedback.Text = $_.Exception.Message; Write-AppError 'Export' "Export fehlgeschlagen (Code $($_.Exception.HResult))." }
        finally {
            $export.Worker.Dispose()
            $export.Worker = $null
            $start.Enabled = $close.Enabled = $true
        }
    })
    $start.Add_Click({
        try {
            $root = $path.Text.Trim()
            if ($root -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)') { throw 'Bitte einen vollständigen Zielordner auswählen.' }
            $export.Worker = [PowerShell]::Create()
            $script = 'param($ffmpeg,$utf8,$SetPath,$Root,$Mode,$Bitrate); $ErrorActionPreference = "Stop";'
            foreach ($fn in @('Safe-Name','Assert-SafePath','Get-SetAudio','Export-LibrarySet')) {
                $script += "function $fn { $((Get-Command $fn).Definition) }`n"
            }
            $script += 'Export-LibrarySet $SetPath $Root $Mode $Bitrate'
            $mode = @('Copy','MP3','Join')[$format.SelectedIndex]
            $bitrate = @(128,192,256,320)[$rate.SelectedIndex]
            [void]$export.Worker.AddScript($script).AddArgument($ffmpeg).AddArgument($utf8).AddArgument($SetPath).AddArgument($root).AddArgument($mode).AddArgument($bitrate)
            $export.Handle = $export.Worker.BeginInvoke()
            $start.Enabled = $close.Enabled = $false
            $feedback.Text = 'Export läuft …'
            $refresh.Start()
        } catch {
            if ($export.Worker) { $export.Worker.Dispose(); $export.Worker = $null }
            $feedback.Text = $_.Exception.Message
        }
    })
    $dialog.Add_FormClosing({ param($sender,$eventArgs) if ($export.Worker) { $eventArgs.Cancel = $true } })
    $dialog.Controls.AddRange(@($label,$path,$browse,$format,$rate,$feedback,$start,$close))
    $dialog.CancelButton = $close
    Set-WindowTheme $dialog
    try { [void]$dialog.ShowDialog($Owner) } finally { $refresh.Dispose(); $dialog.Dispose() }
}


function Get-EditedSetPath($Root, $Artist, $Title, $Source) {
    if (!$Artist.Trim() -or !$Title.Trim()) { return }
    Join-Path (Join-Path (Join-Path $Root (Safe-Name $Artist)) (Split-Path -Leaf (Split-Path -Parent $Source))) (Safe-Name $Title)
}

function Move-LibrarySet($Root, $Source, $Target) {
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    foreach ($path in @($Source, $Target)) {
        Assert-SafePath $path
        if (![IO.Path]::GetFullPath($path).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Der Set-Ordner liegt außerhalb der Bibliothek.'
        }
        for ($parent = $path; $parent.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase); $parent = [IO.Path]::GetDirectoryName($parent)) {
            if ((Test-Path -LiteralPath $parent) -and ((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Der Pfad enthält eine Ordnerverknüpfung: $parent"
            }
        }
    }
    if ([string]::Equals($Source, $Target, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    if (Test-Path -LiteralPath $Target) { throw 'Der Zielordner ist bereits belegt. Bitte einen anderen Titel wählen.' }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Target))
    [IO.Directory]::Move($Source, $Target)
    return $true
}

function Edit-LibrarySet($Owner, $Root, $Source, $Artist, $Title) {
    $editDialog = [Windows.Forms.Form]@{
        Text='Set bearbeiten'; ClientSize=[Drawing.Size]::new(640,245); StartPosition='CenterParent'
        FormBorderStyle='FixedDialog'; MinimizeBox=$false; MaximizeBox=$false; Font=$form.Font
    }
    $djLabel = [Windows.Forms.Label]@{ Text='DJ'; Left=12; Top=12; AutoSize=$true }
    $dj = [Windows.Forms.TextBox]@{ Text=$Artist; Left=12; Top=35; Width=615; AccessibleName='DJ' }
    $titleLabel = [Windows.Forms.Label]@{ Text='Set-Titel'; Left=12; Top=70; AutoSize=$true }
    $titleBox = [Windows.Forms.TextBox]@{ Text=$Title; Left=12; Top=93; Width=615; AccessibleName='Set-Titel' }
    $targetBox = [Windows.Forms.TextBox]@{ Left=12; Top=150; Width=615; ReadOnly=$true; AccessibleName='Zielordner' }
    $targetLabel = [Windows.Forms.Label]@{ Text='Zielordner'; Left=12; Top=127; AutoSize=$true }
    $save = [Windows.Forms.Button]@{ Text='Speichern'; Left=388; Top=197; Width=115; Height=32 }
    $cancel = [Windows.Forms.Button]@{ Text='Abbrechen'; Left=512; Top=197; Width=115; Height=32; DialogResult='Cancel' }
    $refreshTarget = {
        $targetBox.Text = [string](Get-EditedSetPath $Root $dj.Text $titleBox.Text $Source)
        $save.Enabled = [bool]$targetBox.Text
    }
    $dj.Add_TextChanged($refreshTarget)
    $titleBox.Add_TextChanged($refreshTarget)
    & $refreshTarget
    $save.Add_Click({
        try {
            if (Move-LibrarySet $Root $Source $targetBox.Text) { $editDialog.DialogResult = 'OK' }
            else { [void][Windows.Forms.MessageBox]::Show($editDialog, 'Der Zielordner entspricht dem bisherigen Ordner.', 'Set bearbeiten') }
        } catch { [void][Windows.Forms.MessageBox]::Show($editDialog, $_.Exception.Message, 'Set bearbeiten') }
    })
    $editDialog.Controls.AddRange(@($djLabel,$dj,$titleLabel,$titleBox,$targetLabel,$targetBox,$save,$cancel))
    $editDialog.AcceptButton = $save
    $editDialog.CancelButton = $cancel
    try {
        Set-WindowTheme $editDialog
        if ($editDialog.ShowDialog($Owner) -eq 'OK') { return $targetBox.Text }
    } finally { $editDialog.Dispose() }
}

function Show-Library([string]$Root) {
     $libraryData = @{ Entries = @() }
    $dialog = [Windows.Forms.Form]@{
        Text = 'Bibliothek'; Width = 1000; Height = 620; MinimumSize = [Drawing.Size]::new(640, 380)
        StartPosition = 'CenterParent'; Font = $form.Font
    }
    $panel = [Windows.Forms.TableLayoutPanel]@{ Dock = 'Fill'; RowCount = 4; ColumnCount = 1; Padding = [Windows.Forms.Padding]::new(12) }
    foreach ($height in @(25, 34, 0, 39)) {
        $style = if ($height) { [Windows.Forms.RowStyle]::new('Absolute', $height) }
            else { [Windows.Forms.RowStyle]::new('Percent', 100) }
        [void]$panel.RowStyles.Add($style)
    }
    $label = [Windows.Forms.Label]@{ Dock = 'Fill'; Text = 'Künstler oder Titel suchen' }
    $search = [Windows.Forms.TextBox]@{ Dock = 'Fill'; AccessibleName = $label.Text }
    $table = [Windows.Forms.DataGridView]@{
        Dock = 'Fill'; ReadOnly = $true; AllowUserToAddRows = $false; AllowUserToDeleteRows = $false
        RowHeadersVisible = $false; MultiSelect = $false; SelectionMode = 'FullRowSelect'
        AutoSizeColumnsMode = 'Fill'; BackgroundColor = [Drawing.Color]::White
    }
    foreach ($column in @(@('Künstler',22), @('Titel',31), @('Ordner',36), @('Typ',11))) {
        [void]$table.Columns.Add([Windows.Forms.DataGridViewTextBoxColumn]@{
            HeaderText = $column[0]; FillWeight = $column[1]; SortMode = 'NotSortable'
        })
    }
    $count = [Windows.Forms.Label]@{ Dock = 'Fill'; TextAlign = 'MiddleLeft' }
    $panel.Controls.Add($label, 0, 0)
    $filter = [Windows.Forms.ComboBox]@{ Dock='Right'; Width=125; DropDownStyle='DropDownList'; AccessibleName='Aufnahmetyp filtern' }
    $filter.Items.AddRange(@('Alle','Tracks','Sets'))
    $filter.SelectedIndex = 0
    $searchBar = [Windows.Forms.Panel]@{ Dock='Fill' }
    $searchBar.Controls.Add($search)
    $searchBar.Controls.Add($filter)
    $panel.Controls.Add($searchBar, 0, 1)
    $panel.Controls.Add($table, 0, 2)
    $bottom = [Windows.Forms.FlowLayoutPanel]@{ Dock = 'Fill'; WrapContents = $false }
    $play = [Windows.Forms.Button]@{ Text = 'Abspielen'; AutoSize = $true; Enabled = $false }
    $count.Dock = 'None'
    $count.AutoSize = $true
    $count.Margin = [Windows.Forms.Padding]::new(8,6,0,0)
    $exportButton = [Windows.Forms.Button]@{ Text='Exportieren …'; AutoSize=$true; Enabled=$false }
    $editButton = [Windows.Forms.Button]@{ Text='Eintrag bearbeiten …'; AutoSize=$true; Enabled=$false }
    $bottom.Controls.AddRange(@($play, $exportButton, $editButton, $count))
    $editButton.Add_Click({
        $row = $table.CurrentRow
        if (!$row) { return }
        $newPath = Edit-LibrarySet $dialog $Root ([string]$row.Cells[2].Value) ([string]$row.Cells[0].Value) ([string]$row.Cells[1].Value)
        if ($newPath) {
            $libraryData.Entries = @(Get-LibrarySets $Root)
            Update-LibraryResults
            $count.Text = "Set verschoben: $newPath"
        }
    })
    $exportButton.Add_Click({
        if ($table.CurrentRow) { Show-SetExport $dialog ([string]$table.CurrentRow.Cells[2].Value) }
    })
    $panel.Controls.Add($bottom, 0, 3)
    $table.Add_SelectionChanged({ $exportButton.Enabled = $play.Enabled = $null -ne $table.CurrentRow
        $editButton.Enabled = $play.Enabled -and !$state.Worker })
    $play.Add_Click({
        if (!$table.CurrentRow) { return }
        try {
            $path = [string]$table.CurrentRow.Cells[2].Value
            Show-SetPlayback $dialog $path
        } catch { $count.Text = $_.Exception.Message }
    })
    $dialog.Controls.Add($panel)
    $dialog.ActiveControl = $search
    try {
        $libraryData.Entries = @(Get-LibrarySets $Root)
        function Update-LibraryResults {
            $query = $search.Text.Trim()
            $compare = [Globalization.CultureInfo]::CurrentCulture.CompareInfo
            $options = [Globalization.CompareOptions]'IgnoreCase, IgnoreNonSpace'
            $table.Rows.Clear()
            foreach ($entry in $libraryData.Entries) {
                if ($filter.SelectedIndex -gt 0 -and $entry.Type -ne $filter.SelectedItem) { continue }
                if ($query -and $compare.IndexOf($entry.Artist, $query, $options) -lt 0 -and
                    $compare.IndexOf($entry.Title, $query, $options) -lt 0) { continue }
                $index = $table.Rows.Add($entry.Artist, $entry.Title, $entry.Path, $(if ($entry.Type -eq 'Tracks') { 'Track' } else { 'Set' }))
                $table.Rows[$index].Cells[2].ToolTipText = $entry.Path
            }
            $count.Text = "$($table.Rows.Count) von $($libraryData.Entries.Count) Einträge · Doppelklick öffnet den Ordner"
        }
        $filter.Add_SelectedIndexChanged({ Update-LibraryResults })
        $search.Add_TextChanged({ Update-LibraryResults })
        $table.Add_CellDoubleClick({
            param($sender, $eventArgs)
            if ($eventArgs.RowIndex -lt 0) { return }
            $path = [string]$table.Rows[$eventArgs.RowIndex].Cells[2].Value
            if (![IO.Directory]::Exists($path)) {
                $count.Text = 'Der Set-Ordner ist derzeit nicht erreichbar.'
                return
            }
            try { Start-Process explorer.exe ('"{0}"' -f $path) }
            catch { $count.Text = $_.Exception.Message }
        })
        Update-LibraryResults
        Set-WindowTheme $dialog
        [void]$dialog.ShowDialog($form)
    } catch { $status.Text = "Bibliothek konnte nicht geöffnet werden: $($_.Exception.Message)" }
    finally { $dialog.Dispose() }
}
$library.Add_Click({ Show-Library $settings.MusicRoot })

function Show-Diagnostics {
    $diag = [Windows.Forms.Form]@{
        Text='Diagnose'; Width=820; Height=560; StartPosition='CenterParent'; Font=$form.Font
    }
    $report = [Windows.Forms.TextBox]@{
        Dock='Fill'; Multiline=$true; ReadOnly=$true; ScrollBars='Both'; WordWrap=$false
        Text='Werkzeugversionen und Update-Status'
    }
    $buttons = [Windows.Forms.FlowLayoutPanel]@{ Dock='Bottom'; Height=44 }
    $checkVersions = [Windows.Forms.Button]@{ Text='Versionen prüfen'; AutoSize=$true }
    $update = [Windows.Forms.Button]@{ Text='yt-dlp aktualisieren'; AutoSize=$true }
    $copy = [Windows.Forms.Button]@{ Text='Fehlerdetails kopieren'; AutoSize=$true }
    $openLogs = [Windows.Forms.Button]@{ Text='Logordner öffnen'; AutoSize=$true }
    $openLogs.Add_Click({
        try {
            [void][IO.Directory]::CreateDirectory($logDirectory)
            Start-Process explorer.exe ('"{0}"' -f $logDirectory)
        } catch { [void][Windows.Forms.MessageBox]::Show($diag,$_.Exception.Message,'Logordner öffnen') }
    })
    $updateFfmpeg = [Windows.Forms.Button]@{ Text='FFmpeg + ffprobe aktualisieren'; AutoSize=$true }
    $updateDeno = [Windows.Forms.Button]@{ Text='Deno aktualisieren'; AutoSize=$true }
    $buttons.Height = 74
    $buttons.Controls.AddRange(@($checkVersions,$update,$updateFfmpeg,$updateDeno,$copy,$openLogs))
    $diag.Controls.Add($report)
    $diag.Controls.Add($buttons)
    $job = @{ Worker=$null; Handle=$null; Versions=@() }
    $watcher = [Windows.Forms.Timer]@{ Interval=150 }
    $watcher.Add_Tick({
        if (!$job.Handle.IsCompleted) { return }
        $watcher.Stop()
        try {
            $lines = @($job.Worker.EndInvoke($job.Handle) | ForEach-Object { [string]$_ })
            $job.Versions = @(foreach ($line in $lines) {
                if ($line -match '^(yt-dlp|FFmpeg|ffprobe|Deno): (?:ffmpeg version |ffprobe version |deno )?([0-9][0-9A-Za-z.+_-]*)') {
                    "$($Matches[1]): $($Matches[2])"
                }
            })
            foreach ($line in $lines) {
                if ($line -match '^Update-Rückgabecode: (-?\d+)$' -and $Matches[1] -ne '0') {
                    Write-AppError 'Update' ("yt-dlp-Update fehlgeschlagen (Rückgabecode {0})." -f $Matches[1])
                }
            }
            $report.AppendText(($lines -join "`r`n") + "`r`n")
        }
        catch { $report.AppendText($_.Exception.Message + "`r`n"); if ($job.Updating) { Write-AppError 'Update' "$($job.Updating)-Update konnte nicht ausgeführt werden." } }
        finally {
            $job.Worker.Dispose()
            $job.Worker = $null
            $checkVersions.Enabled = $update.Enabled = $updateFfmpeg.Enabled = $updateDeno.Enabled = $true
        }
    })
    function Start-Diagnostic([string]$InstallUpdate) {
        $job.Updating = $InstallUpdate
        try {
            $job.Worker = [PowerShell]::Create()
            [void]$job.Worker.AddScript({
                param($Yt,$Ffmpeg,$Deno,$InstallUpdate,$Core)
                if ($InstallUpdate) {
                    $root = Split-Path -Parent $Core
                    . $Core -LibraryOnly -ToolRoot $root
                    . (Join-Path $root 'DJ-Sets-YtUpdate.ps1')
                    if ($InstallUpdate -eq 'yt-dlp') { Update-YtDlpPackage $root }
                    else {
                        . (Join-Path $root 'DJ-Sets-AudioUpdate.ps1')
                        Update-AudioTool $root $InstallUpdate
                    }
                }
                foreach ($tool in @(@('yt-dlp',$Yt,'--version'),@('FFmpeg',$Ffmpeg,'-version'),@('ffprobe',(Join-Path (Split-Path -Parent $Ffmpeg) 'ffprobe.exe'),'-version'),@('Deno',$Deno,'--version'))) {
                    $name,$exe,$argument = $tool
                    if (![IO.File]::Exists($exe)) { "$name fehlt: $exe"; continue }
                    $lines = @(& $exe $argument 2>&1)
                    $code = $LASTEXITCODE
                    if ($code -ne 0) { "$name (Code ${code}): $($lines -join ' ')" }
                    elseif ($lines.Count) { "${name}: $($lines[0])" }
                    else { "${name}: keine Versionsausgabe" }
                }
            }.ToString()).AddArgument($yt).AddArgument($ffmpeg).AddArgument($deno).AddArgument($InstallUpdate).AddArgument($core)
            $job.Handle = $job.Worker.BeginInvoke()
            $checkVersions.Enabled = $update.Enabled = $updateFfmpeg.Enabled = $updateDeno.Enabled = $false
            $report.AppendText("`r`n" + $(if ($InstallUpdate) {"$InstallUpdate-Update läuft …"} else {'Versionsprüfung …'}) + "`r`n")
            $watcher.Start()
        } catch {
            if ($job.Worker) { $job.Worker.Dispose(); $job.Worker = $null }
            $report.AppendText($_.Exception.Message + "`r`n")
        }
    }
    $checkVersions.Add_Click({ Start-Diagnostic '' })
    $update.Add_Click({ Start-Diagnostic 'yt-dlp' })
    $updateFfmpeg.Add_Click({ Start-Diagnostic 'FFmpeg' })
    $updateDeno.Add_Click({ Start-Diagnostic 'Deno' })
    $copy.Add_Click({
        try { [Windows.Forms.Clipboard]::SetText((($job.Versions + '' + 'Letzte Fehler' + (Get-AppErrors)) -join "`r`n")) }
        catch { [void][Windows.Forms.MessageBox]::Show($diag,$_.Exception.Message,'Diagnose kopieren') }
    })
    $diag.Add_FormClosing({ param($sender,$eventArgs) if ($job.Worker) { $eventArgs.Cancel=$true } })
    try {
        Start-Diagnostic ''
        Set-WindowTheme $diag
        [void]$diag.ShowDialog($form)
    } finally { $watcher.Dispose(); $diag.Dispose() }
}
$diagnose.Add_Click({ Show-Diagnostics })

$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($state.Worker) { $eventArgs.Cancel = $true; $status.Text = 'Ein Vorgang läuft noch. Das Fenster kann danach geschlossen werden.' }
})
Set-WindowTheme $form
try { [void]$form.ShowDialog() } finally { $timer.Dispose(); $form.Dispose(); $lock.Dispose() }













































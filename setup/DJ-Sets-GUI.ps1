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
$appVersion = $null
$updateSignerHash = ''
$versionFile = Join-Path $PSScriptRoot 'plattenkoffer.ini'
if ([IO.File]::Exists($versionFile)) {
    $versionLine = Select-String -LiteralPath $versionFile -Pattern '^Version=(\d+\.\d+\.\d+)$' | Select-Object -First 1
    if ($versionLine) { $appVersion = [version]$versionLine.Matches[0].Groups[1].Value }
    $signerLine = Select-String -LiteralPath $versionFile -Pattern '^UpdateSignerHash=([0-9A-Fa-f]{64})$' | Select-Object -First 1
    if ($signerLine) { $updateSignerHash = $signerLine.Matches[0].Groups[1].Value }
}
$versionLabel = if ($appVersion) { "Version $appVersion" } else { 'Entwicklungsstand' }
$localLibraryPath = Join-Path $config 'dj-set-local-library.json'
$audioExtensions = @('.mp3','.opus','.m4a','.aac','.flac','.wav','.ogg','.webm')
$settings = @{ MusicRoot = $MusicRoot; Theme = 'System' }
. (Join-Path $PSScriptRoot 'DJ-Sets-Personalization.ps1')
$preferenceDefaults=Get-PkDefaultPreferences
foreach ($key in $preferenceDefaults.Keys) { $settings[$key]=$preferenceDefaults[$key] }
$libraryView = @{ IsCover = $true; ShowCollection = $null; OpenPage = $null; Diagnostic = @{ Worker=$null; Handle=$null; Report=''; Status='' } }
$settingsWarning = ''
if ([IO.File]::Exists($settingsPath)) {
    try {
        $saved = [IO.File]::ReadAllText($settingsPath, $utf8) | ConvertFrom-Json
        if ($saved.MusicRoot -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)') { throw 'Ungültiger Musikordner.' }
        $settings.MusicRoot = [IO.Path]::GetFullPath($saved.MusicRoot)
        if ($saved.Theme -in @('Hell','Dunkel','System')) { $settings.Theme = $saved.Theme }
        foreach ($key in $preferenceDefaults.Keys) {
            if ($saved.PSObject.Properties[$key]) {
                try { $settings=Merge-PkPreferences $settings ([pscustomobject]@{$key=$saved.$key}) }
                catch { $settingsWarning='Einzelne Einstellungen wurden auf Standardwerte zurückgesetzt.' }
            }
        }
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
$header = [Windows.Forms.TableLayoutPanel]@{ Dock = 'Fill'; ColumnCount = 4; RowCount = 3 }
[void]$header.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 27))
[void]$header.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent', 100))
[void]$header.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute', 34))
[void]$header.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute', 108))
[void]$header.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 100))
[void]$header.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute', 0))
[void]$header.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute', 46))
$iconFont = [Drawing.Font]::new('Segoe MDL2 Assets', 15)
$form.Add_Disposed({ $iconFont.Dispose() })
$actionTips = [Windows.Forms.ToolTip]::new()
$form.Add_Disposed({ $actionTips.Dispose() })
function Set-ActionIcon($Button, [int]$Glyph, [string]$Caption) {
    $Button.Font = $iconFont
    $Button.Text = [string][char]$Glyph
    $Button.AccessibleName = $Caption
    $actionTips.SetToolTip($Button, $Caption)
}
$link = [Windows.Forms.TextBox]@{ Dock = 'Fill'; Multiline = $true; ScrollBars = 'Vertical'; AccessibleName = 'YouTube-Links, einer pro Zeile' }
$layout.RowStyles[1].Height = 139
$preview = [Windows.Forms.Button]@{ Anchor='Top,Left'; Width=40; Height=32 }
Set-ActionIcon $preview 0xE8A5 'Vorschau laden'
$youtubeHeading = [Windows.Forms.Label]@{ Text='YouTube'; Dock='Fill'; TextAlign='MiddleLeft'; Padding=[Windows.Forms.Padding]::new(30,0,0,0) }
$youtubeHeading.Add_Paint({
    param($sender,$eventArgs)
    $graphics = $eventArgs.Graphics
    $graphics.FillRectangle([Drawing.Brushes]::Red, 2, 4, 22, 15)
    $graphics.FillPolygon([Drawing.Brushes]::White, [Drawing.Point[]]@(
        [Drawing.Point]::new(10,7), [Drawing.Point]::new(10,16), [Drawing.Point]::new(17,11)
    ))
})
$linkLabel = [Windows.Forms.Label]@{ Text="Links`nEiner pro Zeile"; Dock='Fill'; Padding=[Windows.Forms.Padding]::new(0,5,0,0) }
$header.Controls.Add($youtubeHeading, 0, 0)
$header.SetColumnSpan($youtubeHeading, 4)
$header.Controls.Add($linkLabel, 0, 1)
$header.Controls.Add($link, 1, 1)
$header.SetColumnSpan($link, 2)
$header.Controls.Add($preview, 3, 1)
$searchLabel = [Windows.Forms.Label]@{ Text='Suche'; Dock='Fill'; Padding=[Windows.Forms.Padding]::new(0,5,0,0) }
$youtubeSearch = [Windows.Forms.TextBox]@{ Dock='Fill'; AccessibleName='YouTube-Suchbegriff'; MaxLength=200 }
$searchYouTube = [Windows.Forms.Button]@{ Dock='Fill' }
Set-ActionIcon $searchYouTube 0xE721 'Auf YouTube suchen'
$header.Controls.Add($searchLabel, 0, 2)
$header.Controls.Add($youtubeSearch, 1, 2)
$header.SetColumnSpan($youtubeSearch, 2)
$header.Controls.Add($searchYouTube, 3, 2)
$layout.Controls.Add($header, 0, 1)
$bar = [Windows.Forms.FlowLayoutPanel]@{ Dock = 'Fill' }
$download = [Windows.Forms.Button]@{ Width=40; Height=34; Enabled=$false }
Set-ActionIcon $download 0xE896 'Download starten'
$folder = [Windows.Forms.ToolStripMenuItem]@{ Text = 'Musikordner öffnen'; AutoSize = $true }
$form.Text = "Plattenkoffer · $versionLabel"
$options = [Windows.Forms.ToolStripMenuItem]@{ Text = 'Einstellungen'; AutoSize = $true }
$preferences = [Windows.Forms.ToolStripMenuItem]@{ Text = 'Programmeinstellungen …' }
$checkUpdate = [Windows.Forms.ToolStripMenuItem]@{ Text = 'Nach Updates suchen …'; Enabled = [bool]$appVersion }
$updateNotice = [Windows.Forms.ToolStripMenuItem]@{ Visible = $false }
$stop = [Windows.Forms.Button]@{ Width=40; Height=34; Enabled=$false }
Set-ActionIcon $stop 0xE71A 'Nach diesem Set stoppen'
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
    if ($libraryView.OpenPage -and (& $libraryView.OpenPage 'about')) { return }
    [void][Windows.Forms.MessageBox]::Show($form, "Plattenkoffer`r`n$versionLabel`r`nEntwickler: Mindgamer", 'Über Plattenkoffer', 'OK', 'Information')
})
$options.DropDownItems.Add($preferences) | Out-Null
$helpMenu.DropDownItems.AddRange(@($checkUpdate,$about))
function Open-SupportPage {
    try { Start-Process -FilePath 'https://ko-fi.com/mindgamer49330' }
    catch {
        [void][Windows.Forms.MessageBox]::Show($form, 'Die Ko-fi-Seite konnte nicht geöffnet werden.', 'Plattenkoffer unterstützen')
    }
}
$supportMenu = [Windows.Forms.ToolStripMenuItem]@{ Text='Plattenkoffer unterstützen …' }
$supportMenu.Add_Click({ Open-SupportPage })
[void]$helpMenu.DropDownItems.Add($supportMenu)
$menu.Items.AddRange(@($fileMenu, $queueMenu, $options, $helpMenu, $updateNotice))
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
$libraryShortcut.Add_Click({ if ($libraryView.ShowCollection) { & $libraryView.ShowCollection } })
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
$heartImage = [Drawing.Bitmap]::new(30, 28)
$heartCanvas = [Drawing.Graphics]::FromImage($heartImage)
$heartShape = [Drawing.Drawing2D.GraphicsPath]::new()
$heartBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(235,53,73))
try {
    $heartCanvas.SmoothingMode = 'AntiAlias'
    $heartShape.AddBezier(15,25, 13,22, 1,15, 1,8)
    $heartShape.AddBezier(1,8, 1,0, 11,0, 15,6)
    $heartShape.AddBezier(15,6, 19,0, 29,0, 29,8)
    $heartShape.AddBezier(29,8, 29,15, 17,22, 15,25)
    $heartShape.CloseFigure()
    $heartCanvas.FillPath($heartBrush,$heartShape)
} finally { $heartBrush.Dispose(); $heartShape.Dispose(); $heartCanvas.Dispose() }
$supportButton = [Windows.Forms.Button]@{
    Dock='Fill'; Image=$heartImage; ImageAlign='MiddleCenter'; AccessibleName='Plattenkoffer auf Ko-fi unterstützen'
}
$supportButton.Add_Disposed({ $heartImage.Dispose() })
$libraryTip.SetToolTip($supportButton,'Plattenkoffer auf Ko-fi unterstützen')
$supportButton.Add_Click({ Open-SupportPage })
$bar.Controls.AddRange(@($download, $stop, $libraryShortcut))
$actionRow = [Windows.Forms.TableLayoutPanel]@{ Dock='Fill'; ColumnCount=2; RowCount=1 }
[void]$actionRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 100))
[void]$actionRow.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute', 54))
$actionRow.Controls.Add($bar, 0, 0)
$actionRow.Controls.Add($supportButton, 1, 0)
$layout.Controls.Add($actionRow, 0, 2)
$layout.RowStyles[2].Height = 50
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
foreach ($control in @($header,$actionRow,$grid,$status,$footer,$destination)) { $control.Margin = [Windows.Forms.Padding]::new(12,3,12,3) }
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
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($linkItem in $Value) {
            if ($StopSignal.IsSet) { break }
            try {
                foreach ($row in (Get-Preview $linkItem.Url $linkItem.Playlist $Aliases)) {
                    if (!$seen.Add($row.Id)) { continue }
                    if ($linkItem.Search) { $row.Selected = $false }
                    $row | Add-Member NoteProperty Archived ($archiveIds.Contains("youtube $($row.Id)"))
                    [pscustomobject]@{ Kind = 'Preview'; Row = $row }
                }
            } catch {
                Write-Warning "$($linkItem.Url): $($_.Exception.Message)"
            }
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
    if ($web.Health.Worker) { throw 'Ein Bibliothekspflege-Vorgang läuft noch.' }
    if ($libraryView.Diagnostic.Worker) { throw 'Ein Diagnosevorgang läuft noch.' }
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
    $preview.Enabled = $download.Enabled = $grid.Enabled = $link.Enabled = $false
    $youtubeSearch.Enabled = $searchYouTube.Enabled = $false
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
                    $index = $grid.Rows.Add(($row.Selected -and !$row.Archived), $row.Artist, $row.Title, $row.Original, $label, '', $row.Type)
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
    $preview.Enabled = $grid.Enabled = $link.Enabled = $true
    $youtubeSearch.Enabled = $searchYouTube.Enabled = $true
    $available = @($grid.Rows | Where-Object { !$_.Tag.Archived }).Count -gt 0
    $download.Enabled = $available
    Update-Targets
    $status.Text = if ($failure) { 'Vorgang fehlgeschlagen. Details stehen unten.' }
        elseif ($state.Mode -eq 'Preview') { "$($grid.Rows.Count) Einträge · DJ und Set-Titel lassen sich direkt bearbeiten." }
        elseif ($stopped) { "Gestoppt · $($state.Total - $state.Completed) Sets offen · $($state.Errors) Fehler" }
        else { "$($state.Completed - $state.Errors) von $($state.Total) Sets gespeichert · $($state.Errors) Fehler" }
})
function Find-ArchivedSet($Root, $Id) {
    foreach ($entry in (Get-LibrarySets $Root)) {
        if ($entry.External) { continue }
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
function Show-YouTubePreview($Requests, [string]$Message) {
    if ($state.Worker) { return }
    $download.Enabled = $false
    $grid.Rows.Clear()
    $log.Clear()
    $status.Text = $Message
    $progress.Style = 'Marquee'
    try { Start-Worker 'Preview' $Requests $false }
    catch {
        $progress.Style = 'Continuous'
        $status.Text = $_.Exception.Message
    }
}
$searchYouTube.Add_Click({
    $query = $youtubeSearch.Text.Trim()
    if (!$query) { $status.Text = 'Bitte einen YouTube-Suchbegriff eingeben.'; return }
    Show-YouTubePreview @([pscustomobject]@{ Url = "ytsearch15:$query"; Playlist = $true; Search = $true }) 'YouTube wird durchsucht …'
})
$youtubeSearch.Add_KeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.KeyCode -eq 'Enter') {
        $eventArgs.SuppressKeyPress = $true
        $searchYouTube.PerformClick()
    }
})
function Select-PlaylistImport([string]$Url, [bool]$PlaylistOnly) {
    if ($null -ne $script:WebPlaylistChoice) {
        if ($script:WebPlaylistChoice) { return 'Playlist' }
        if ($PlaylistOnly) { return 'Skip' }
        return 'Video'
    }
    $window = [Windows.Forms.Form]@{
        Text='YouTube-Playlist'; ClientSize=[Drawing.Size]::new(520,160); StartPosition='CenterParent'
        FormBorderStyle='FixedDialog'; MinimizeBox=$false; MaximizeBox=$false; Font=$form.Font
    }
    $source = [Windows.Forms.TextBox]@{ Text=$Url; Left=12; Top=12; Width=496; ReadOnly=$true; AccessibleName='YouTube-Link' }
    $whole = [Windows.Forms.CheckBox]@{ Text='Ganze Playlist laden'; Checked=$PlaylistOnly; Left=12; Top=48; AutoSize=$true }
    $hintText = if ($PlaylistOnly) { 'Ohne Haken wird dieser Link übersprungen.' } else { 'Ohne Haken wird nur das verlinkte Video geladen.' }
    $hint = [Windows.Forms.Label]@{ Text=$hintText; Left=12; Top=77; AutoSize=$true }
    $ok = [Windows.Forms.Button]@{ Text='Weiter'; Left=280; Top=115; Width=108; Height=30; DialogResult='OK' }
    $cancel = [Windows.Forms.Button]@{ Text='Abbrechen'; Left=400; Top=115; Width=108; Height=30; DialogResult='Cancel' }
    $window.Controls.AddRange(@($source,$whole,$hint,$ok,$cancel))
    $window.AcceptButton = $ok
    $window.CancelButton = $cancel
    try {
        Set-WindowTheme $window
        if ($window.ShowDialog($form) -ne 'OK') { return 'Cancel' }
        if ($whole.Checked) { return 'Playlist' }
        if ($PlaylistOnly) { return 'Skip' }
        'Video'
    } finally { $window.Dispose() }
}

$preview.Add_Click({
    $links = @($link.Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
    if (!$links.Count) { $status.Text = 'Bitte mindestens einen YouTube-Link eingeben.'; return }
    $requests = @(foreach ($url in $links) {
    $uri = $null
    if (![uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http','https') -or
        $uri.Host -notmatch '^(?:[a-z0-9-]+\.)*youtube\.com$|^(?:www\.)?youtu\.be$') {
        $status.Text = 'Bitte einen vollständigen YouTube-Link eingeben.'
        return
    }
    $playlistOnly = $uri.AbsolutePath.TrimEnd('/') -eq '/playlist'
    if ((!$playlistOnly -and $uri.AbsolutePath -notmatch '^/(watch|shorts/[^/]+|live/[^/]+|embed/[^/]+|[^/]{11})/?$') -or
        ($playlistOnly -and $uri.Query -notmatch '[?&]list=[^&]+')) {
        $status.Text = 'Bitte einen Video- oder Playlist-Link eingeben.'
        return
    }
    [pscustomobject]@{ Url = $url; HasPlaylist = $uri.Query -match '[?&]list=[^&]+'; PlaylistOnly = $playlistOnly }
    })
    if ($requests.Count -ne $links.Count) { return }
    $previewRequests = [Collections.Generic.List[object]]::new()
    foreach ($request in $requests) {
        $choice = if ($request.HasPlaylist) { Select-PlaylistImport $request.Url $request.PlaylistOnly } else { 'Video' }
        if ($choice -eq 'Cancel') { return }
        if ($choice -ne 'Skip') { $previewRequests.Add([pscustomobject]@{ Url=$request.Url; Playlist=$choice -eq 'Playlist' }) }
    }
    if (!$previewRequests.Count) { $status.Text = 'Keine Links für die Vorschau ausgewählt.'; return }
    Show-YouTubePreview $previewRequests.ToArray() 'Vorschau wird geladen …'
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
    $download.Enabled = $true
    $status.Text = "$($entries.Count) Sets geladen. Auswahl prüfen und auf Download starten klicken."
}
$resume.Add_Click({ Show-SavedQueue $false })
$retry.Add_Click({ Show-SavedQueue $true })

function Get-PkBackupFiles([string]$Root) {
    foreach ($name in @('dj-set-gui.json','downloaded.txt','dj-set-queue.json','dj-set-aliases.json','dj-set-local-library.json','dj-set-library-state.json','set-resume.json','health-options.json')) {
        $source=Join-Path $config $name
        if ([IO.File]::Exists($source)) { [pscustomobject]@{Name="config/$name";Path=$source} }
    }
    foreach ($file in (Get-ChildItem -LiteralPath $config -File)) {
        if ($file.Name -cmatch '^(?:tracklist-[0-9A-F]{64}\.json|cover-[0-9A-F]{64}\.jpg)$') {
            [pscustomobject]@{Name="config/$($file.Name)";Path=$file.FullName}
        }
    }
    if ([IO.Directory]::Exists($Root)) {
        Assert-SafePath $Root
        foreach ($artist in (Get-ChildItem -LiteralPath $Root -Directory)) {
            Assert-SafePath $artist.FullName
            foreach ($type in @('Sets','Tracks')) {
                $category=Join-Path $artist.FullName $type
                Assert-SafePath $category
                if (![IO.Directory]::Exists($category)) { continue }
                foreach ($folder in (Get-ChildItem -LiteralPath $category -Directory)) {
                    Assert-SafePath $folder.FullName
                    foreach ($name in @('plattenkoffer-tracklist.json','plattenkoffer-cover.jpg','plattenkoffer.json')) {
                        $source=Join-Path $folder.FullName $name
                        if ([IO.File]::Exists($source)) {
                            [pscustomobject]@{Name="library/$($artist.Name)/$type/$($folder.Name)/$name";Path=$source}
                        }
                    }
                }
            }
        }
    }
}

function Write-PkBackupBytes([string]$Path,[byte[]]$Bytes) {
    Assert-SafePath $Path
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $temporary="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllBytes($temporary,$Bytes)
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary,$Path,[NullString]::Value) }
        else { [IO.File]::Move($temporary,$Path) }
    } finally { [IO.File]::Delete($temporary) }
}

function Save-ConfigurationBackup([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Assert-SafePath $Path
    $temporary="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $zip=[IO.Compression.ZipFile]::Open($temporary,'Create')
        try {
            $writer=[IO.StreamWriter]::new($zip.CreateEntry('backup-format.json').Open(),$utf8)
            try { $writer.Write('{"version":2}') } finally { $writer.Dispose() }
            $files=@(Get-PkBackupFiles $settings.MusicRoot)
            $total=0L
            if ($files.Count -gt 49998) { throw 'Zu viele Dateien für eine Sicherung.' }
            foreach ($file in $files) {
                Assert-SafePath $file.Path
                $length=[IO.FileInfo]::new($file.Path).Length
                $total+=$length
                if ($length -gt 20MB -or $total -gt 511MB) { throw "Datei oder Gesamtumfang zu groß für die Sicherung: $($file.Path)" }
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file.Path,$file.Name)
            }
            if ('config/dj-set-gui.json' -notin $files.Name) {
                $writer=[IO.StreamWriter]::new($zip.CreateEntry('config/dj-set-gui.json').Open(),$utf8)
                try { $writer.Write((ConvertTo-Json -InputObject $settings)) } finally { $writer.Dispose() }
            }
        } finally { $zip.Dispose() }
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary,$Path,[NullString]::Value) }
        else { [IO.File]::Move($temporary,$Path) }
    } finally { [IO.File]::Delete($temporary) }
}

function Restore-ConfigurationBackup([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Assert-SafePath $Path
    $names=@('dj-set-gui.json','downloaded.txt','dj-set-queue.json','dj-set-aliases.json','dj-set-local-library.json','dj-set-library-state.json')
    $data=@{}
    $zip=[IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $total=0L
        foreach ($entry in $zip.Entries) {
            $name=$entry.FullName
            $allowed=$name -ceq 'backup-format.json' -or
                ($name.StartsWith('config/') -and ($entry.Name -cin $names -or $entry.Name -cin @('set-resume.json','health-options.json') -or
                $entry.Name -cmatch '^(?:tracklist-[0-9A-F]{64}\.json|cover-[0-9A-F]{64}\.jpg)$') -and $name -ceq "config/$($entry.Name)") -or
                $name -cmatch '^library/[^/\\:]+/(?:Sets|Tracks)/[^/\\:]+/plattenkoffer(?:-tracklist\.json|-cover\.jpg|\.json)$'
            $total+=$entry.Length
            if (!$allowed -or $data.ContainsKey($name) -or $entry.Length -gt 20MB -or $total -gt 512MB -or $data.Count -ge 50000) {
                throw 'Ungültiger oder zu großer Eintrag in der Sicherung.'
            }
            $stream=$entry.Open()
            $memory=[IO.MemoryStream]::new()
            try { $stream.CopyTo($memory); $bytes=$memory.ToArray() }
            finally { $stream.Dispose(); $memory.Dispose() }
            if ($name.EndsWith('.json')) { $null=ConvertFrom-Json -InputObject $utf8.GetString($bytes) }
            $data[$name]=$bytes
        }
    } finally { $zip.Dispose() }
    if (!$data.ContainsKey('config/dj-set-gui.json')) { throw 'Die Einstellungen fehlen im ZIP.' }
    $modern=$data.ContainsKey('backup-format.json')
    if ($modern -and (ConvertFrom-Json $utf8.GetString($data['backup-format.json'])).version -ne 2) { throw 'Unbekannte Sicherungsversion.' }
    if (!$modern -and @($data.Keys | Where-Object { $_ -notin @($names | ForEach-Object {"config/$_"}) }).Count) {
        throw 'Die Formatangabe der Sicherung fehlt.'
    }
    $saved=ConvertFrom-Json $utf8.GetString($data['config/dj-set-gui.json'])
    if ($saved.MusicRoot -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)') { throw 'Ungültige Einstellungen im ZIP.' }
    $root=[IO.Path]::GetFullPath($saved.MusicRoot).TrimEnd('\','/')+'\'
    Assert-SafePath $root
    $targets=@{}
    foreach ($name in $data.Keys) {
        if ($name -eq 'backup-format.json') { continue }
        if ($name.StartsWith('config/')) { $target=Join-Path $config $name.Substring(7) }
        else {
            $relative=$name.Substring(8)
            foreach ($part in $relative.Split('/')) {
                if ($part -in @('.','..') -or $part.TrimEnd(' ','.') -cne $part -or $part.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
                    throw 'Ungültiger Sammlungspfad im ZIP.'
                }
            }
            $target=[IO.Path]::GetFullPath((Join-Path $root $relative))
            if (!$target.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'Ungültiger Sammlungspfad im ZIP.' }
        }
        Assert-SafePath $target
        if ($targets.ContainsKey($target)) { throw 'Doppeltes Sicherungsziel.' }
        $targets[$target]=$data[$name]
    }
    # Old ZIPs replace only their original six config files. New optional data is preserved.
    foreach ($name in $names) {
        $target=Join-Path $config $name
        if (!$targets.ContainsKey($target)) { $targets[$target]=$null }
    }
    $previous=@{}
    foreach ($target in $targets.Keys) {
        Assert-SafePath $target
        $previous[$target]=if ([IO.File]::Exists($target)) { ,([IO.File]::ReadAllBytes($target)) } else { $null }
    }
    $backup=Join-Path (Split-Path -Parent $config) ("Vor-Wiederherstellung-$([guid]::NewGuid()).zip")
    Save-ConfigurationBackup $backup
    $changed=[Collections.Generic.List[string]]::new()
    try {
        foreach ($target in $targets.Keys) {
            $changed.Add($target)
            if ($null -ne $targets[$target]) { Write-PkBackupBytes $target $targets[$target] }
            else { [IO.File]::Delete($target) }
        }
    } catch {
        $failure=$_
        try {
            foreach ($target in $changed) {
                if ($null -ne $previous[$target]) { Write-PkBackupBytes $target $previous[$target] }
                else { [IO.File]::Delete($target) }
            }
        } catch { throw "Rückgängig fehlgeschlagen. Sicherung: $backup. $($_.Exception.Message)" }
        throw $failure
    }
    return $backup
}
$preferences.Add_Click({
    if ($libraryView.OpenPage -and (& $libraryView.OpenPage 'settings')) { return }
    $dialog = [Windows.Forms.Form]@{
        Text = 'Einstellungen'; ClientSize = [Drawing.Size]::new(660, 295)
        StartPosition = 'CenterParent'; FormBorderStyle = 'FixedDialog'
        MinimizeBox = $false; MaximizeBox = $false; Font = $form.Font
    }
    $label = [Windows.Forms.Label]@{ Text = 'Downloadordner'; Left = 12; Top = 12; AutoSize = $true }
    $pathBox = [Windows.Forms.TextBox]@{ Text = $settings.MusicRoot; Left = 12; Top = 39; Width = 495 }
    $browse = [Windows.Forms.Button]@{ Text = 'Durchsuchen …'; Left = 515; Top = 36; Width = 123; Height = 30 }
    $hint = [Windows.Forms.Label]@{
        Text = 'Der neue Ordner gilt für künftige Downloads.'; Left = 12; Top = 77; AutoSize = $true
    }
    $themeLabel = [Windows.Forms.Label]@{ Text='Farbschema'; Left=12; Top=16; AutoSize=$true }
    $theme = [Windows.Forms.ComboBox]@{ Left=123; Top=12; Width=160; DropDownStyle='DropDownList'; AccessibleName='Farbschema' }
    $theme.Items.AddRange(@('System','Hell','Dunkel'))
    $theme.SelectedItem = $settings.Theme
    $save = [Windows.Forms.Button]@{ Text = 'OK'; Left = 420; Top = 250; Width = 110; Height = 32 }
    $cancel = [Windows.Forms.Button]@{ Text = 'Abbrechen'; Left = 535; Top = 250; Width = 113; Height = 32; DialogResult = 'Cancel' }
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
            $newSettings = $settings.Clone()
            $newSettings.MusicRoot=$path; $newSettings.Theme=[string]$theme.SelectedItem
            Write-AtomicText $settingsPath (ConvertTo-Json -InputObject $newSettings)
            $settings.MusicRoot = $path
            $destination.Text = "Downloadordner: $path"
            Update-Targets
            if ($settings.Theme -ne $newSettings.Theme) {
                $settings.Theme = $newSettings.Theme
                [void][Windows.Forms.MessageBox]::Show($dialog,'Die Darstellung wird beim nächsten Start übernommen.','Darstellung')
            }
            $dialog.DialogResult = 'OK'
        } catch { [void][Windows.Forms.MessageBox]::Show($dialog, $_.Exception.Message, 'Einstellungen') }
    })
    $backup = [Windows.Forms.Button]@{ Text = 'Konfiguration sichern …'; Left = 12; Top = 48; AutoSize = $true; Height = 32 }
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
    $restore = [Windows.Forms.Button]@{ Text='Konfiguration wiederherstellen …'; Left=12; Top=90; Height=32; AutoSize=$true }
    $restore.Add_Click({
        $picker = [Windows.Forms.OpenFileDialog]@{ Filter='ZIP-Archiv (*.zip)|*.zip' }
        try {
            if ($picker.ShowDialog($dialog) -ne 'OK') { return }
            if ([Windows.Forms.MessageBox]::Show($dialog,'Das ZIP ersetzt die Konfiguration und stellt enthaltene Tracklisten, eigene Cover und Fortsetzungspositionen wieder her. Sammlungsdaten werden in den im ZIP gespeicherten Musikordner geschrieben. Audiodateien sind nicht enthalten. Vorher wird eine Sicherung angelegt. Plattenkoffer wird danach geschlossen. Fortfahren?','Konfiguration wiederherstellen','YesNo','Question','Button2') -ne 'Yes') { return }
            $previous = Restore-ConfigurationBackup $picker.FileName
            [void][Windows.Forms.MessageBox]::Show($dialog,"Bitte Plattenkoffer neu starten. Vorherige Konfiguration: $previous",'Konfiguration wiederherstellen')
            $dialog.DialogResult = 'Retry'
        } catch { [void][Windows.Forms.MessageBox]::Show($dialog,$_.Exception.Message,'Konfiguration wiederherstellen') }
        finally { $picker.Dispose() }
    })
    $tabs = [Windows.Forms.TabControl]@{ Left=8; Top=8; Width=644; Height=229 }
    $downloadsTab = [Windows.Forms.TabPage]@{ Text='Downloads' }
    $appearanceTab = [Windows.Forms.TabPage]@{ Text='Darstellung' }
    $backupTab = [Windows.Forms.TabPage]@{ Text='Sicherung' }
    $backupLabel = [Windows.Forms.Label]@{ Text='ZIP mit Einstellungen, Fortsetzungspositionen, Tracklisten und eigenen Covern. Ohne Audio.'; Left=12; Top=16; AutoSize=$true }
    $pathBox.Width = 480
    $pathBox.AccessibleName = 'Downloadordner'
    $browse.Left = 503
    $downloadsTab.Controls.AddRange(@($label,$pathBox,$browse,$hint))
    $appearanceTab.Controls.AddRange(@($themeLabel,$theme))
    $backupTab.Controls.AddRange(@($backupLabel,$backup,$restore))
    $tabs.TabPages.AddRange(@($downloadsTab,$appearanceTab,$backupTab))
    $dialog.Controls.AddRange(@($tabs,$save,$cancel))
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
    $copyFiles = [Windows.Forms.Button]@{ Text='Dateien kopieren'; AutoSize=$true }
    $commit = [Windows.Forms.Button]@{ Text='Dateien verschieben'; AutoSize=$true }
    $cancel = [Windows.Forms.Button]@{ Text='Schließen'; AutoSize=$true; DialogResult='Cancel' }
    $hint = [Windows.Forms.Label]@{ Text='Gleicher DJ und Set-Titel gruppieren mehrere Teile.'; AutoSize=$true; Margin=[Windows.Forms.Padding]::new(8,8,0,0) }
    $actions.Controls.AddRange(@($copyFiles,$commit,$cancel,$hint))
    $dialog.Controls.Add($table)
    $dialog.Controls.Add($actions)
    $dialog.CancelButton = $cancel
    $importFiles = {
        param($sender,$eventArgs)
        $copy = $sender -eq $copyFiles
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
                    if ($copy) {
                        $temporary = Join-Path $move.Directory ('.import-' + [guid]::NewGuid().ToString('N') + '.tmp')
                        try {
                            [IO.File]::Copy($move.Source,$temporary)
                            [IO.File]::Move($temporary,$move.Target)
                        } finally { [IO.File]::Delete($temporary) }
                    } else { [IO.File]::Move($move.Source,$move.Target) }
                    $move.Row.Tag = $move.Target
                }
            }
            $status.Text = "$($plan.Count) MP3-Dateien einsortiert."
            $dialog.DialogResult = 'OK'
        } catch { [void][Windows.Forms.MessageBox]::Show($dialog, $_.Exception.Message, 'MP3-Import') }
    }
    $copyFiles.Add_Click($importFiles)
    $commit.Add_Click($importFiles)
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
    if ([IO.File]::Exists($Path)) {
        Get-Item -LiteralPath $Path
        return
    }
    Get-ChildItem -LiteralPath $Path -File | Where-Object { $_.Extension -in @('.mp3','.opus','.m4a','.aac','.flac','.wav','.ogg','.webm') -and $_.BaseName -notmatch '(?i)(?:^audio_repaired$|\.tmp(?:\.|$)|\.pk-health-)' } |
        Sort-Object @{ Expression = {
            [regex]::Replace($_.Name, '[0-9]+', { param($number) $number.Value.PadLeft(20, '0') })
        } }, Name
}

function Get-LibraryDisplayTitle($Entry) {
    $original = [string]$Entry.Title
    if ($Entry.Type -ne 'Sets') { return $original }
    $manual = ([string]$Entry.SetNameOverride).Trim()
    if ($manual) { return $manual }
    $artist = ([string]$Entry.Artist).Trim()
    $venue = ([string]$Entry.Event).Trim()
    if (!$venue) { $venue = ([string]$Entry.Location).Trim() }
    $when = ([string]$Entry.Year).Trim()
    $date = [datetime]::MinValue
    if ([datetime]::TryParseExact([string]$Entry.Date,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)) {
        $when = $date.ToString('dd.MM.yyyy',[Globalization.CultureInfo]::InvariantCulture)
    }
    $parts = @($artist,$venue,$when) | Where-Object { $_ }
    if ($parts) { return ($parts -join ' · ') }
    $original
}

function Get-LibrarySets([string]$Root) {
    $artists = if ([IO.Directory]::Exists($Root)) { Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name }
    foreach ($artist in $artists) {
        foreach ($type in @('Sets','Tracks')) {
            $category = Join-Path $artist.FullName $type
            if (![IO.Directory]::Exists($category)) { continue }
            foreach ($entry in (Get-ChildItem -LiteralPath $category -Directory | Sort-Object Name)) {
                if (Get-SetAudio $entry.FullName | Select-Object -First 1) {
                    $item = [pscustomobject]@{ Artist=$artist.Name; Title=$entry.Name; Path=$entry.FullName; Type=$type; Series=''; Event=''; Location=''; External=$false }
                    $metadataPath = Join-Path $entry.FullName 'plattenkoffer.json'
                    if ([IO.File]::Exists($metadataPath)) {
                        try {
                            $metadata = [IO.File]::ReadAllText($metadataPath, $utf8) | ConvertFrom-Json
                            foreach ($field in @('Artist','Title','Series','Event','Location','Album','Year','Label','Version','Genre','Date','SetNameOverride')) {
                                if ($metadata.$field -is [string]) { $item | Add-Member NoteProperty $field $metadata.$field -Force }
                            }
                            if ($metadata.MetadataSources) { $item | Add-Member NoteProperty MetadataSources $metadata.MetadataSources }
                        } catch { Write-Warning "Einordnung konnte nicht gelesen werden: $metadataPath" }
                    }
                    $item
                }
            }
        }
    }
    Read-LocalLibrary
}

function Read-LocalLibrary {
    if ([IO.File]::Exists($localLibraryPath)) {
        $savedEntries = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($localLibraryPath, $utf8))
        foreach ($entry in $savedEntries) {
            if ($entry) { $entry }
        }
    }
}

function Save-LocalLibrary($Entries) {
    Write-AtomicText $localLibraryPath (ConvertTo-Json -InputObject @($Entries) -Depth 6)
}

function Add-LocalLibraryFiles([string]$Root, [string[]]$Paths) {
    $entries = @(Read-LocalLibrary)
    $known = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $entries) { [void]$known.Add($item.Path) }
    $added = @(foreach ($path in $Paths) {
        Assert-SafePath $path
        $file = Get-Item -LiteralPath $path
        $recordingFolder = $file.Directory
        if ($recordingFolder -and $recordingFolder.Parent -and $recordingFolder.Parent.Name -in @('Sets','Tracks') -and
            $recordingFolder.Parent.Parent -and $recordingFolder.Parent.Parent.Parent -and
            $recordingFolder.Parent.Parent.Parent.FullName -eq [IO.Path]::GetFullPath($Root).TrimEnd('\')) { continue }
        if (!$file.PSIsContainer -and $file.Extension -in $audioExtensions -and $known.Add($file.FullName)) {
            [pscustomobject]@{ Artist=''; Title=$file.BaseName; Path=$file.FullName; Type='Tracks'; Series=''; Event=''; Location=''; External=$true }
        }
    })
    if ($added.Count) { Save-LocalLibrary ($entries + $added) }
    $added.Count
}

function Edit-LibraryMetadata($Owner, $Entry) {
    $window = [Windows.Forms.Form]@{
        Text='Einordnung bearbeiten'; ClientSize=[Drawing.Size]::new(540, 290); StartPosition='CenterParent'
        FormBorderStyle='FixedDialog'; MinimizeBox=$false; MaximizeBox=$false; Font=$form.Font
    }
    $inputs = @{}
    $fields = [ordered]@{ Artist='DJs (mit Komma trennen)'; Title='Titel'; Series='Set-Reihe'; Event='Veranstaltung'; Location='Location' }
    $top = 14
    foreach ($field in $fields.Keys) {
        $caption = $fields[$field]
        $window.Controls.Add([Windows.Forms.Label]@{ Text=$caption; Left=12; Top=$top; Width=180; Height=25 })
        $inputs[$field] = [Windows.Forms.TextBox]@{ Text=[string]$Entry.$field; Left=195; Top=$top; Width=330; AccessibleName=$caption }
        $window.Controls.Add($inputs[$field])
        $top += 38
    }
    $typeBox = [Windows.Forms.ComboBox]@{ Left=195; Top=$top; Width=330; DropDownStyle='DropDownList'; AccessibleName='Typ' }
    $typeBox.Items.AddRange(@('Tracks','Sets'))
    $typeBox.SelectedItem = $Entry.Type
    $typeBox.Enabled = $Entry.External
    $window.Controls.Add([Windows.Forms.Label]@{ Text='Typ'; Left=12; Top=$top; Width=180 })
    $save = [Windows.Forms.Button]@{ Text='Speichern'; Left=280; Top=248; Width=115; Height=30 }
    $cancel = [Windows.Forms.Button]@{ Text='Abbrechen'; Left=410; Top=248; Width=115; Height=30; DialogResult='Cancel' }
    $window.Controls.AddRange(@($typeBox,$save,$cancel))
    $window.AcceptButton = $save
    $window.CancelButton = $cancel
    $save.Add_Click({
        if (!$inputs.Title.Text.Trim()) { $inputs.Title.Focus(); return }
        try {
            $metadata = [ordered]@{}
            foreach ($field in $fields.Keys) { $metadata[$field] = $inputs[$field].Text.Trim() }
            foreach ($field in @('Album','Year','Label','Version','Genre','Date','SetNameOverride','MetadataSources')) {
                if ($Entry.PSObject.Properties[$field]) { $metadata[$field]=$Entry.$field }
            }
            if ($Entry.External) {
                $metadata.Path = $Entry.Path
                $metadata.Type = [string]$typeBox.SelectedItem
                $metadata.External = $true
                $entries = @(Read-LocalLibrary | ForEach-Object {
                    if ($_.Path -eq $Entry.Path) { [pscustomobject]$metadata } else { $_ }
                })
                Save-LocalLibrary $entries
            } else {
                Write-AtomicText (Join-Path $Entry.Path 'plattenkoffer.json') (ConvertTo-Json $metadata -Depth 6)
            }
            $window.DialogResult = 'OK'
        } catch { [void][Windows.Forms.MessageBox]::Show($window, $_.Exception.Message, 'Einordnung bearbeiten') }
    })
    try {
        Set-WindowTheme $window
        $window.ShowDialog($Owner) -eq 'OK'
    } finally { $window.Dispose() }
}

function Export-LibrarySet($SetPath, $Root, $Mode, [int]$Bitrate) {
    Assert-SafePath $SetPath
    $tracks = @(Get-SetAudio $SetPath)
    foreach ($track in $tracks) { Assert-SafePath $track.FullName }
    if (!$tracks.Count) { throw 'Keine Audiodateien im Set gefunden.' }
    $rootPath = [IO.Path]::GetFullPath($Root)
    Assert-SafePath $rootPath
    [void][IO.Directory]::CreateDirectory($rootPath)
    $name = Safe-Name $(if ([IO.File]::Exists($SetPath)) { [IO.Path]::GetFileNameWithoutExtension($SetPath) } else { Split-Path -Leaf $SetPath })
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

function Show-SetExport($Owner, [string[]]$SetPaths) {
    $dialog = [Windows.Forms.Form]@{
        Text = 'Auf Gerät exportieren'; ClientSize = [Drawing.Size]::new(610, 235); StartPosition = 'CenterParent'
        FormBorderStyle = 'FixedDialog'; MinimizeBox = $false; MaximizeBox = $false; Font = $form.Font
    }
    $label = [Windows.Forms.Label]@{ Text='USB-Stick oder Zielordner'; Left=12; Top=12; AutoSize=$true }
    $path = [Windows.Forms.TextBox]@{ Left=12; Top=37; Width=460 }
    $browse = [Windows.Forms.Button]@{ Text='Durchsuchen …'; Left=480; Top=34; Width=118; Height=30 }
    $format = [Windows.Forms.ComboBox]@{ Left=12; Top=78; Width=345; DropDownStyle='DropDownList'; AccessibleName='Exportformat' }
    $format.Items.AddRange(@('Originalkopie (nummerierte Teile)', 'MP3 (nummerierte Teile)', 'Eine durchgehende MP3'))
    $rate = [Windows.Forms.ComboBox]@{ Left=375; Top=78; Width=145; DropDownStyle='DropDownList'; AccessibleName='MP3-Bitrate' }
    $rate.Items.AddRange(@('128 kbit/s','192 kbit/s','256 kbit/s','320 kbit/s'))
    $rate.SelectedIndex = 2
    $format.Add_SelectedIndexChanged({ $rate.Enabled = $format.SelectedIndex -gt 0 })
    $format.SelectedIndex = 0
    $feedback = [Windows.Forms.Label]@{ Left=12; Top=122; Width=585; Height=60; Text="$($SetPaths.Count) ausgewählte Einträge. Jeder Eintrag erhält einen eigenen Ordner." }
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
            $feedback.Text = "$($result.Count) Einträge exportiert nach $($export.Root)."
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
            $script = 'param($ffmpeg,$utf8,$SetPaths,$Root,$Mode,$Bitrate); $ErrorActionPreference = "Stop";'
            foreach ($fn in @('Safe-Name','Assert-SafePath','Get-SetAudio','Export-LibrarySet')) {
                $script += "function $fn { $((Get-Command $fn).Definition) }`n"
            }
            $script += 'foreach ($path in $SetPaths) { $destination = Export-LibrarySet $path $Root $Mode $Bitrate; $destination }'
            $mode = @('Copy','MP3','Join')[$format.SelectedIndex]
            $bitrate = @(128,192,256,320)[$rate.SelectedIndex]
            [void]$export.Worker.AddScript($script).AddArgument($ffmpeg).AddArgument($utf8).AddArgument($SetPaths).AddArgument($root).AddArgument($mode).AddArgument($bitrate)
            $export.Root = $root
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
    $targetLabel = [Windows.Forms.Label]@{ Text='USB-Stick oder Zielordner'; Left=12; Top=127; AutoSize=$true }
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

function Show-Library {
    $libraryData = @{ Entries = @(); Page = 0 }
    $pageSize = 24
    $coverImages = [Collections.Generic.List[Drawing.Image]]::new()
    $dialog = $form
    $graphite = [Drawing.Color]::FromArgb(27,26,24)
    $surface = [Drawing.Color]::FromArgb(39,36,32)
    $ink = [Drawing.Color]::FromArgb(249,235,217)
    $mutedInk = [Drawing.Color]::FromArgb(205,188,171)
    $accent = [Drawing.Color]::FromArgb(170,73,38)
    $shell = [Windows.Forms.TableLayoutPanel]@{ Dock='Fill'; ColumnCount=2; RowCount=2; BackColor=$graphite }
    [void]$shell.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',172))
    [void]$shell.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100))
    [void]$shell.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',100))
    [void]$shell.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',72))
    $sidebar = [Windows.Forms.FlowLayoutPanel]@{ Dock='Fill'; FlowDirection='TopDown'; WrapContents=$false; Padding=[Windows.Forms.Padding]::new(10,18,10,0); Margin=[Windows.Forms.Padding]::new(0); BackColor=[Drawing.Color]::FromArgb(21,20,18) }
    $brandFont = [Drawing.Font]::new($form.Font.FontFamily, 15, [Drawing.FontStyle]::Bold)
    $brand = [Windows.Forms.Label]@{ Text='Plattenkoffer'; Font=$brandFont; Width=148; Height=54; ForeColor=$ink }
    $sidebar.Controls.Add($brand)
    $navigation = [ordered]@{}
    foreach ($name in @('Sammlung','Sets','Tracks','Downloads','Einstellungen','Hilfe')) {
        $button = [Windows.Forms.Button]@{ Text=$name; Width=146; Height=36; TextAlign='MiddleLeft'; FlatStyle='Flat'; ForeColor=$ink; BackColor=$sidebar.BackColor }
        $button.FlatAppearance.BorderSize=0
        $navigation[$name]=$button
        $sidebar.Controls.Add($button)
    }
    $shell.Controls.Add($sidebar,0,0)
    $sidebarUpdate = [Windows.Forms.Button]@{ Text='Update verfügbar …'; Width=146; Height=36; FlatStyle='Flat'; ForeColor=$ink; BackColor=$accent; Visible=$false }
    $sidebar.Controls.Add($sidebarUpdate)
    $sidebarUpdate.Add_Click({ $updateNotice.PerformClick() })
    $updateNotice.Add_TextChanged({ $sidebarUpdate.Visible=[bool]$updateCheck.Version })
    $playerBar = [Windows.Forms.TableLayoutPanel]@{ Dock='Fill'; ColumnCount=6; RowCount=2; Padding=[Windows.Forms.Padding]::new(12,6,12,2); Margin=[Windows.Forms.Padding]::new(0); BackColor=$surface }
    [void]$playerBar.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',32))
    foreach ($width in @(46,46,112)) { [void]$playerBar.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',$width)) }
    [void]$playerBar.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',68))
    [void]$playerBar.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',108))
    $nowPlaying = [Windows.Forms.Label]@{ Text='Keine Wiedergabe'; Dock='Fill'; TextAlign='MiddleLeft'; ForeColor=$ink; AutoEllipsis=$true }
    $transport = [Windows.Forms.Button]@{ Dock='Fill'; Enabled=$false }
    $endPlayback = [Windows.Forms.Button]@{ Dock='Fill'; Enabled=$false }
    Set-ActionIcon $transport 0xE768 'Wiedergabe fortsetzen'
    Set-ActionIcon $endPlayback 0xE71A 'Wiedergabe stoppen'
    foreach ($control in @($transport,$endPlayback)) { $control.FlatStyle='Flat'; $control.BackColor=$graphite; $control.ForeColor=$ink }
    $elapsedLabel = [Windows.Forms.Label]@{ Text='–'; Dock='Fill'; TextAlign='MiddleCenter'; ForeColor=$mutedInk }
    $seekBar = [Windows.Forms.TrackBar]@{ Dock='Fill'; TickStyle='None'; Enabled=$false; AccessibleName='Wiedergabeposition' }
    $playerBar.Controls.Add($nowPlaying,0,0)
    $playerBar.SetRowSpan($nowPlaying,2)
    $playerBar.Controls.Add($transport,1,0)
    $playerBar.SetRowSpan($transport,2)
    $playerBar.Controls.Add($endPlayback,2,0)
    $playerBar.SetRowSpan($endPlayback,2)
    $playerBar.Controls.Add($elapsedLabel,3,0)
    $playerBar.SetRowSpan($elapsedLabel,2)
    $playerBar.Controls.Add($seekBar,4,0)
    $playerBar.SetRowSpan($seekBar,2)
    $volume = [Windows.Forms.TrackBar]@{ Dock='Fill'; TickStyle='None'; Maximum=100; AccessibleName='Lautstärke' }
    $volume.Value = $settings.StartVolume
    $playerBar.Controls.Add($volume,5,0)
    $playerBar.SetRowSpan($volume,2)
    $actionTips.SetToolTip($volume,'Lautstärke')
    $shell.Controls.Add($playerBar,0,1)
    $shell.SetColumnSpan($playerBar,2)
    $audio = @{ Process=$null; Tracks=@(); Index=0; Offset=0.0; Duration=0.0; Clock=[Diagnostics.Stopwatch]::new(); Title='' }
    $audioTimer = [Windows.Forms.Timer]@{ Interval=200 }
    function Stop-LibraryAudioProcess {
        $audio.Clock.Stop()
        if ($audio.Process) {
            try { if (!$audio.Process.HasExited) { $audio.Process.Kill(); [void]$audio.Process.WaitForExit(1500) } }
            catch [InvalidOperationException] {}
            finally { $audio.Process.Dispose(); $audio.Process=$null }
        }
    }
    function Stop-LibraryPlayback {
        Stop-LibraryAudioProcess
        $audioTimer.Stop()
        $audio.Tracks=@()
        $transport.Enabled=$endPlayback.Enabled=$seekBar.Enabled=$false
        $seekBar.Value=0
        $elapsedLabel.Text='–'
        $nowPlaying.Text='Keine Wiedergabe'
        Set-ActionIcon $transport 0xE768 'Wiedergabe fortsetzen'
    }
    function Resume-LibraryAudio {
        $player = Join-Path $PSScriptRoot 'bin\ffplay.exe'
        Assert-SafePath $player
        if (![IO.File]::Exists($player)) { throw 'ffplay fehlt. Bitte Plattenkoffer mit Setup reparieren.' }
        Stop-LibraryAudioProcess
        $timeOffset = $audio.Offset.ToString('0.###',[Globalization.CultureInfo]::InvariantCulture)
        $arguments = '-nodisp -autoexit -loglevel error -ss {0} -volume {1} -i "{2}"' -f $timeOffset,$volume.Value,$audio.Tracks[$audio.Index].FullName
        $audio.Process = Start-Process -FilePath $player -ArgumentList $arguments -WindowStyle Hidden -PassThru
        $audio.Clock.Restart()
        Set-ActionIcon $transport 0xE769 'Pause'
    }
    function Open-LibraryAudioPart([double]$InitialOffset=0) {
        $track = $audio.Tracks[$audio.Index]
        Assert-SafePath $track.FullName
        $seconds = & $probe -v error -show_entries format=duration -of 'csv=p=0' $track.FullName
        $duration = 0.0
        $known = $LASTEXITCODE -eq 0 -and [double]::TryParse([string]$seconds,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$duration) -and $duration -gt 0 -and $duration -lt [int]::MaxValue
        $audio.Duration = if ($known) { $duration } else { 0.0 }
        $audio.Offset=if ($known -and $InitialOffset -ge $duration) { 0.0 } else { [Math]::Max(0.0,$InitialOffset) }
        $seekBar.Value=0
        $seekBar.Maximum=[Math]::Max(1,[int][Math]::Ceiling($audio.Duration))
        $seekBar.Enabled=$known
        $nowPlaying.Text=if ($audio.Tracks.Count -gt 1) { "$($audio.Title) · Teil $($audio.Index+1)/$($audio.Tracks.Count)" } else { $audio.Title }
        Resume-LibraryAudio
    }
    function Start-LibraryPlayback([string]$Path,[string]$Title,[int]$Part=0,[double]$Offset=0) {
        Assert-SafePath $Path
        $tracks = @(Get-SetAudio $Path)
        if (!$tracks.Count) { throw 'Keine Audiodateien gefunden.' }
        if ($Part -lt 0 -or $Part -ge $tracks.Count) { throw 'Dieser Teil des Sets ist nicht verfügbar.' }
        Stop-LibraryPlayback
        $audio.Tracks=$tracks
        $audio.Index=$Part
        $audio.Title=$Title
        try { Open-LibraryAudioPart $Offset }
        catch { Stop-LibraryPlayback; throw }
        $transport.Enabled=$endPlayback.Enabled=$true
        $audioTimer.Start()
    }
    function Invoke-LibraryAudioAction([scriptblock]$Action) {
        try { & $Action }
        catch { Stop-LibraryPlayback; $nowPlaying.Text=$_.Exception.Message }
    }
    $audioTimer.Add_Tick({
        Invoke-LibraryAudioAction {
            if ($audio.Process -and $audio.Process.HasExited) {
                if ($audio.Process.ExitCode -ne 0) { throw "Wiedergabe fehlgeschlagen (Code $($audio.Process.ExitCode))." }
                $audio.Index++
                if ($audio.Index -ge $audio.Tracks.Count) {
                    Save-WebSetPosition -Forget
                    Stop-LibraryPlayback
                    [void](Step-WebPlaybackQueue -Automatic)
                    return
                }
                Open-LibraryAudioPart
            }
            $elapsed=$audio.Offset + $(if ($audio.Process) { $audio.Clock.Elapsed.TotalSeconds } else { 0 })
            if ($seekBar.Enabled -and !$seekBar.Capture) { $seekBar.Value=[Math]::Min($seekBar.Maximum,[int][Math]::Floor($elapsed)) }
            $elapsedLabel.Text='{0:hh\:mm\:ss} / {1}' -f [timespan]::FromSeconds($elapsed),$(if ($seekBar.Enabled) { [timespan]::FromSeconds($audio.Duration).ToString('hh\:mm\:ss') } else { '–' })
        }
    })
    $transport.Add_Click({
        Invoke-LibraryAudioAction {
            if ($audio.Process) {
                $audio.Offset += $audio.Clock.Elapsed.TotalSeconds
                Stop-LibraryAudioProcess
                Set-ActionIcon $transport 0xE768 'Wiedergabe fortsetzen'
            } else { Resume-LibraryAudio }
        }
    })
    $seekAction = {
        Invoke-LibraryAudioAction {
            $audio.Offset=[Math]::Min($seekBar.Value,[Math]::Max(0,$audio.Duration-0.05))
            if ($audio.Process) { Resume-LibraryAudio }
        }
    }
    $seekBar.Add_MouseUp($seekAction)
    $seekBar.Add_KeyUp($seekAction)
    $volumeChangedAction = {
        if ($audio.Process) {
            Invoke-LibraryAudioAction {
                $audio.Offset += $audio.Clock.Elapsed.TotalSeconds
                Resume-LibraryAudio
            }
        }
    }
    $volume.Add_MouseUp($volumeChangedAction)
    $volume.Add_KeyUp($volumeChangedAction)
    $endPlayback.Add_Click({ if ($web.Queue) { $web.Queue.Paths=@() }; Stop-LibraryPlayback })
    $panel = [Windows.Forms.TableLayoutPanel]@{ Dock = 'Fill'; RowCount = 5; ColumnCount = 1; Padding = [Windows.Forms.Padding]::new(12) }
    foreach ($height in @(56, 1, 56, 0, 43)) {
        $style = if ($height) { [Windows.Forms.RowStyle]::new('Absolute', $height) }
            else { [Windows.Forms.RowStyle]::new('Percent', 100) }
        [void]$panel.RowStyles.Add($style)
    }
    $label = [Windows.Forms.Label]@{ Dock='Fill'; Text='Sammlung'; TextAlign='MiddleLeft' }
    $headingFont = [Drawing.Font]::new($form.Font.FontFamily, 23, [Drawing.FontStyle]::Bold)
    $label.Font = $headingFont
    $search = [Windows.Forms.TextBox]@{ Dock='Fill'; BorderStyle='None'; AccessibleName = 'Sammlung durchsuchen' }
    $table = [Windows.Forms.DataGridView]@{
        Dock = 'Fill'; ReadOnly = $true; AllowUserToAddRows = $false; AllowUserToDeleteRows = $false
        RowHeadersVisible = $false; MultiSelect = $true; SelectionMode = 'FullRowSelect'
        AutoSizeColumnsMode = 'Fill'; BackgroundColor = [Drawing.Color]::White
    }
    foreach ($column in @(@('DJs',18), @('Titel',27), @('Pfad',12), @('Typ',8), @('Set-Reihe',12), @('Veranstaltung',13), @('Location',10))) {
        [void]$table.Columns.Add([Windows.Forms.DataGridViewTextBoxColumn]@{
            HeaderText = $column[0]; FillWeight = $column[1]; SortMode = 'Automatic'
        })
    }
    $table.Columns[2].Visible = $false
    $count = [Windows.Forms.Label]@{ Dock = 'Fill'; TextAlign = 'MiddleLeft' }
    $top = [Windows.Forms.TableLayoutPanel]@{ Dock='Fill'; ColumnCount=6; RowCount=1 }
    [void]$top.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',100))
    [void]$top.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',187))
    [void]$top.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100))
    foreach ($width in @(72,72,126,44)) { [void]$top.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',$width)) }
    $coverView = [Windows.Forms.Button]@{ Text='Cover'; Dock='Fill' }
    $listView = [Windows.Forms.Button]@{ Text='Liste'; Dock='Fill' }
    $add = [Windows.Forms.Button]@{ Text='+ Hinzufügen'; Dock='Fill' }
    $top.Controls.Add($label,0,0)
    $top.Controls.Add($coverView,2,0)
    $top.Controls.Add($listView,3,0)
    $top.Controls.Add($add,4,0)
    $support = [Windows.Forms.Button]@{ Dock='Fill'; Image=$heartImage; FlatStyle='Flat'; AccessibleName='Plattenkoffer unterstützen' }
    $support.Add_Click({ Open-SupportPage })
    $actionTips.SetToolTip($support,'Plattenkoffer auf Ko-fi unterstützen')
    $top.Controls.Add($support,5,0)
    $panel.Controls.Add($top, 0, 0)
    $filter = [Windows.Forms.ComboBox]@{ Dock='Right'; Width=125; DropDownStyle='DropDownList'; AccessibleName='Aufnahmetyp filtern' }
    $filter.Items.AddRange(@('Alle','Tracks','Sets'))
    $filter.SelectedIndex = 0
    $searchBar = [Windows.Forms.Panel]@{ Dock='Fill'; Margin=[Windows.Forms.Padding]::new(4,8,4,8); Padding=[Windows.Forms.Padding]::new(10,9,10,0) }
    $searchBar.Controls.Add($search)
    $searchCaption = [Windows.Forms.Label]@{ Text='Suche'; Dock='Left'; Width=48; ForeColor=$mutedInk }
    $searchBar.Controls.Add($searchCaption)
    $actionTips.SetToolTip($search,'Sammlung durchsuchen')
    if ($search.PSObject.Properties['PlaceholderText']) { $search.PlaceholderText = 'Sammlung durchsuchen …' }
    $top.Controls.Add($searchBar,1,0)
    $filterBar = [Windows.Forms.TableLayoutPanel]@{ Dock='Fill'; ColumnCount=4; RowCount=2 }
    $fieldFilters = [ordered]@{}
    $filterFields = [ordered]@{ Artist='DJ'; Series='Set-Reihe'; Event='Veranstaltung'; Location='Location' }
    $columnIndex = 0
    foreach ($field in $filterFields.Keys) {
        [void]$filterBar.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent', 25))
        $caption = $filterFields[$field]
        $fieldFilters[$field] = [Windows.Forms.TextBox]@{ Dock='Top'; BorderStyle='None'; AccessibleName="$caption filtern" }
        $filterBar.Controls.Add([Windows.Forms.Label]@{ Text=$caption; AutoSize=$true }, $columnIndex, 0)
        $inputSurface = [Windows.Forms.Panel]@{ Dock='Top'; Height=28; Padding=[Windows.Forms.Padding]::new(8,5,8,0) }
        $inputSurface.Controls.Add($fieldFilters[$field])
        $filterBar.Controls.Add($inputSurface, $columnIndex, 1)
        $columnIndex++
    }
    $panel.Controls.Add($filterBar, 0, 2)
    $content = [Windows.Forms.Panel]@{ Dock='Fill' }
    $covers = [Windows.Forms.FlowLayoutPanel]@{ Dock='Fill'; AutoScroll=$true; WrapContents=$true }
    $detail = [Windows.Forms.Label]@{ Dock='Right'; Width=188; Padding=[Windows.Forms.Padding]::new(12,15,6,0); ForeColor=$ink; BackColor=$surface }
    $content.Controls.AddRange(@($table,$covers,$detail))
    $panel.Controls.Add($content, 0, 3)
    $bottom = [Windows.Forms.FlowLayoutPanel]@{ Dock = 'Fill'; WrapContents = $true }
    $play = [Windows.Forms.Button]@{ Width=40; Height=30; Enabled=$false }
    Set-ActionIcon $play 0xE768 'Abspielen'
    $count.Dock = 'None'
    $count.AutoSize = $true
    $count.Margin = [Windows.Forms.Padding]::new(8,6,0,0)
    $exportButton = [Windows.Forms.Button]@{ Text='Auf Gerät exportieren …'; AutoSize=$true; Enabled=$false }
    $editButton = [Windows.Forms.Button]@{ Text='Einordnung bearbeiten …'; AutoSize=$true; Enabled=$false }
    $moveButton = [Windows.Forms.Button]@{ Text='Ordner umbenennen …'; AutoSize=$true; Enabled=$false }
    $previousPage = [Windows.Forms.Button]@{ Text='‹'; Width=34; Height=30; AccessibleName='Vorherige Cover-Seite' }
    $nextPage = [Windows.Forms.Button]@{ Text='›'; Width=34; Height=30; AccessibleName='Nächste Cover-Seite' }
    $bottom.Controls.AddRange(@($play, $exportButton, $editButton, $moveButton, $previousPage, $nextPage, $count))
    $addMenu = [Windows.Forms.ContextMenuStrip]::new()
    $helpActions = [Windows.Forms.ContextMenuStrip]::new()
    $helpActions.Items.Add('Über Plattenkoffer').Add_Click({ $about.PerformClick() })
    $helpActions.Items.Add('Nach Updates suchen …').Add_Click({ $checkUpdate.PerformClick() })
    $helpActions.Items.Add('Diagnose').Add_Click({ if (!$state.Worker) { $diagnose.PerformClick() } })
    $navigation.Hilfe.Add_Click({ $helpActions.Show($navigation.Hilfe,[Drawing.Point]::new($navigation.Hilfe.Width,0)) })
    $youtube = $addMenu.Items.Add('YouTube-Suche oder Links …')
    $files = $addMenu.Items.Add('Dateien verknüpfen …')
    $folders = $addMenu.Items.Add('Ordner einlesen …')
    $copyLocal = $addMenu.Items.Add('MP3s kopieren oder verschieben …')
    $add.Add_Click({ $addMenu.Show($add, [Drawing.Point]::new(0,$add.Height)) })
    $youtube.Add_Click({ Show-DownloadView; $youtubeSearch.Focus() })
    $copyLocal.Add_Click({ if (!$state.Worker) { $import.PerformClick(); Update-LibraryResults -Reload } })
    $editButton.Add_Click({
        if ($table.CurrentRow -and (Edit-LibraryMetadata $dialog $table.CurrentRow.Tag)) {
            $libraryData.Entries = @(Get-LibrarySets $settings.MusicRoot)
            Update-LibraryResults
        }
    })
    $moveButton.Add_Click({
        $row = $table.CurrentRow
        if (!$row -or $row.Tag.External) { return }
        $newPath = Edit-LibrarySet $dialog $settings.MusicRoot ([string]$row.Cells[2].Value) (Split-Path -Leaf (Split-Path -Parent (Split-Path -Parent $row.Tag.Path))) (Split-Path -Leaf $row.Tag.Path)
        if ($newPath) {
            $libraryData.Entries = @(Get-LibrarySets $settings.MusicRoot)
            Update-LibraryResults
            $count.Text = "Set verschoben: $newPath"
        }
    })
    $files.Add_Click({
        $patterns = ($audioExtensions | ForEach-Object { "*$_" }) -join ';'
        $picker = [Windows.Forms.OpenFileDialog]@{ Title='Musikdateien am vorhandenen Speicherort aufnehmen'; Filter="Audiodateien|$patterns"; Multiselect=$true }
        try {
            if ($picker.ShowDialog($dialog) -ne 'OK') { return }
            $added = Add-LocalLibraryFiles $settings.MusicRoot $picker.FileNames
            $libraryData.Entries = @(Get-LibrarySets $settings.MusicRoot)
            Update-LibraryResults
            $count.Text = "$added Dateien verknüpft."
        } catch { $count.Text = $_.Exception.Message }
        finally { $picker.Dispose() }
    })
    $folders.Add_Click({
        $picker = [Windows.Forms.FolderBrowserDialog]@{ Description='Musikordner mit Unterordnern einlesen'; ShowNewFolderButton=$false }
        try {
            if ($picker.ShowDialog($dialog) -ne 'OK') { return }
            $paths = @(Get-ChildItem -LiteralPath $picker.SelectedPath -File -Recurse |
                Where-Object Extension -in $audioExtensions | ForEach-Object FullName)
            $added = Add-LocalLibraryFiles $settings.MusicRoot $paths
            $libraryData.Entries = @(Get-LibrarySets $settings.MusicRoot)
            Update-LibraryResults
            $count.Text = "$added Dateien verknüpft."
        } catch { $count.Text = $_.Exception.Message }
        finally { $picker.Dispose() }
    })
    $exportButton.Add_Click({
        $selectedPaths = @($table.SelectedRows | Sort-Object Index | ForEach-Object { [string]$_.Cells[2].Value })
        if ($selectedPaths.Count) { Show-SetExport $dialog $selectedPaths }
    })
    $panel.Controls.Add($bottom, 0, 4)
    $table.Add_SelectionChanged({ $exportButton.Enabled = $table.SelectedRows.Count -gt 0
        $play.Enabled = $table.SelectedRows.Count -eq 1
        $editButton.Enabled = $play.Enabled -and !$state.Worker
        $moveButton.Enabled = $editButton.Enabled -and $table.CurrentRow -and !$table.CurrentRow.Tag.External
        $entry = $table.CurrentRow.Tag
        $detail.Text = if ($entry) { @($entry.Title,$entry.Artist,'',$entry.Series,$entry.Event,$entry.Location) -join "`r`n" } else { 'Wähle einen Eintrag aus.' }
    })
    $play.Add_Click({
        if (!$table.CurrentRow) { return }
        try {
            $path = [string]$table.CurrentRow.Cells[2].Value
            Start-LibraryPlayback $path ([string]$table.CurrentRow.Tag.Title)
        } catch { $count.Text = $_.Exception.Message }
    })
    $body = [Windows.Forms.Panel]@{ Dock='Fill'; Margin=[Windows.Forms.Padding]::new(0); BackColor=$graphite }
    $shell.Controls.Add($body,1,0)
    $body.Controls.Add($layout)
    $body.Controls.Add($panel)
    $dialog.Controls.Add($shell)
    $shell.BringToFront()
    $menu.BringToFront()
    $dialog.ActiveControl = $search
    try {

        function Clear-LibraryCovers {
            foreach ($card in @($covers.Controls)) { $card.Dispose() }
            foreach ($image in $coverImages) { $image.Dispose() }
            $coverImages.Clear()
        }
        function Update-CoverView {
            $covers.SuspendLayout()
            try {
                Clear-LibraryCovers
                $table.Visible = !$libraryView.IsCover
                $covers.Visible = $libraryView.IsCover
                $detail.Visible = !$libraryView.IsCover
                $coverView.Enabled = !$libraryView.IsCover
                $listView.Enabled = $libraryView.IsCover
                $previousPage.Visible = $nextPage.Visible = $libraryView.IsCover
                $lastPage = [Math]::Max(0,[Math]::Ceiling($table.Rows.Count / $pageSize) - 1)
                $libraryData.Page = [int][Math]::Min($libraryData.Page,$lastPage)
                $previousPage.Enabled = $libraryData.Page -gt 0
                $nextPage.Enabled = $libraryData.Page -lt $lastPage
                if (!$libraryView.IsCover) { return }
                if (!$table.Rows.Count) {
                    $covers.Controls.Add([Windows.Forms.Label]@{ Text='Keine passenden Einträge.'; AutoSize=$true; ForeColor=$dialog.ForeColor })
                    return
                }
                $first = $libraryData.Page * $pageSize
                $limit = [Math]::Min($table.Rows.Count, $first + $pageSize)
                for ($index = $first; $index -lt $limit; $index++) {
                    $row = $table.Rows[$index]
                    $entry = $row.Tag
                    $card = [Windows.Forms.Button]@{
                        Width=178; Height=206; Margin=[Windows.Forms.Padding]::new(6)
                        Text="$($row.Cells[1].Value)`n$($entry.Artist)"; Tag=$row; TextAlign='BottomLeft'; ImageAlign='TopCenter'
                        FlatStyle='Flat'; BackColor=$content.BackColor; ForeColor=$dialog.ForeColor
                    }
                    $card.FlatAppearance.BorderSize=0
                    $artwork = [Drawing.Bitmap]::new(156,144)
                    $imageCanvas = [Drawing.Graphics]::FromImage($artwork)
                    try {
                        $imageCanvas.Clear([Drawing.Color]::FromArgb(49,40,35))
                        $imageCanvas.FillEllipse([Drawing.Brushes]::Black,36,14,84,84)
                        $imageCanvas.FillEllipse([Drawing.Brushes]::Coral,68,46,20,20)
                        if (!$entry.External) {
                            foreach ($name in @('cover.jpg','cover.jpeg','cover.png','cover.webp','cover.avif')) {
                                $coverPath = Join-Path $entry.Path $name
                                if (![IO.File]::Exists($coverPath)) { continue }
                                try {
                                    $convertedCover = $null
                                    try {
                                        Assert-SafePath $coverPath
                                        $imagePath = $coverPath
                                        if ($name -in @('cover.webp','cover.avif')) {
                                            $convertedCover = Join-Path ([IO.Path]::GetTempPath()) ("pk-cover-$([guid]::NewGuid().ToString('N')).png")
                                            & $ffmpeg -nostdin -loglevel quiet -i $coverPath -vf 'scale=320:-1' -frames:v 1 $convertedCover
                                            if ($LASTEXITCODE -ne 0) { continue }
                                            $imagePath = $convertedCover
                                        }
                                        $sourceImage = [Drawing.Image]::FromFile($imagePath)
                                        try {
                                            $scale = [Math]::Max(156 / $sourceImage.Width, 144 / $sourceImage.Height)
                                            $width = [int]($sourceImage.Width * $scale)
                                            $height = [int]($sourceImage.Height * $scale)
                                            $imageCanvas.DrawImage($sourceImage,[int]((156-$width)/2),[int]((144-$height)/2),$width,$height)
                                        } finally { $sourceImage.Dispose() }
                                    } finally { if ($convertedCover) { [IO.File]::Delete($convertedCover) } }
                                    break
                                } catch { Write-Verbose "Cover konnte nicht gelesen werden: $coverPath" }
                            }
                        }
                    } finally { $imageCanvas.Dispose() }
                    $card.Image = $artwork
                    $coverImages.Add($artwork)
                    $card.Add_Click({
                        param($sender,$eventArgs)
                        $table.ClearSelection()
                        $table.CurrentCell = $sender.Tag.Cells[1]
                        $sender.Tag.Selected = $true
                        foreach ($item in $covers.Controls) { $item.FlatAppearance.BorderSize=0 }
                        $sender.FlatAppearance.BorderSize=1
                        $sender.FlatAppearance.BorderColor = [Drawing.Color]::Coral
                        $count.Text = [string]$sender.Tag.Cells[1].Value
                    })
                    $covers.Controls.Add($card)
                }
            } finally { $covers.ResumeLayout() }
        }
        function Update-LibraryResults([switch]$Reload) {
            if ($Reload) { $libraryData.Entries = @(Get-LibrarySets $settings.MusicRoot) }
            if ($web.Ready) { if ($Reload) { Send-WebLibrary }; return }
            if ($web.Initializing) { return }
            $query = $search.Text.Trim()
            $compare = [Globalization.CultureInfo]::CurrentCulture.CompareInfo
            $options = [Globalization.CompareOptions]'IgnoreCase, IgnoreNonSpace'
            $table.Rows.Clear()
            foreach ($entry in $libraryData.Entries) {
                if ($filter.SelectedIndex -gt 0 -and $entry.Type -ne $filter.SelectedItem) { continue }
                $displayTitle = Get-LibraryDisplayTitle $entry
                $searchText = @($entry.Artist, $displayTitle, $entry.Title, $entry.Series, $entry.Event, $entry.Location) -join ' '
                if ($query -and $compare.IndexOf($searchText, $query, $options) -lt 0) { continue }
                $matchesFields = $true
                foreach ($field in $fieldFilters.Keys) {
                    if ($compare.IndexOf([string]$entry.$field, $fieldFilters[$field].Text.Trim(), $options) -lt 0) {
                        $matchesFields = $false
                        break
                    }
                }
                if (!$matchesFields) { continue }
                $typeLabel = if ($entry.Type -eq 'Tracks') { 'Track' } else { 'Set' }
                $row = [Windows.Forms.DataGridViewRow]::new()
                $row.CreateCells($table, @($entry.Artist, $displayTitle, $entry.Path, $typeLabel, $entry.Series, $entry.Event, $entry.Location))
                $row.Tag = $entry
                $row.Cells[1].ToolTipText = $entry.Path
                [void]$table.Rows.Add($row)
            }
            $count.Text = "$($table.Rows.Count) von $($libraryData.Entries.Count) Einträge · Doppelklick öffnet den Ordner"
            $libraryData.Page = 0
            Update-CoverView
        }
        $coverView.Add_Click({ $libraryView.IsCover = $true; Update-CoverView })
        $listView.Add_Click({ $libraryView.IsCover = $false; Update-CoverView })
        $previousPage.Add_Click({ $libraryData.Page--; Update-CoverView })
        $nextPage.Add_Click({ $libraryData.Page++; Update-CoverView })
        $filter.Add_SelectedIndexChanged({ Update-LibraryResults })
        $search.Add_TextChanged({ Update-LibraryResults })
        foreach ($inputBox in $fieldFilters.Values) { $inputBox.Add_TextChanged({ Update-LibraryResults }) }
        $table.Add_CellDoubleClick({
            param($sender, $eventArgs)
            if ($eventArgs.RowIndex -lt 0) { return }
            $path = [string]$table.Rows[$eventArgs.RowIndex].Cells[2].Value
            if ([IO.File]::Exists($path)) { $path = Split-Path -Parent $path }
            if (![IO.Directory]::Exists($path)) {
                $count.Text = 'Der Set-Ordner ist derzeit nicht erreichbar.'
                return
            }
            try { Start-Process explorer.exe ('"{0}"' -f $path) }
            catch { $count.Text = $_.Exception.Message }
        })
        function Show-CollectionView {
            $layout.Hide()
            $panel.Show()
            $panel.BringToFront()
            foreach ($name in @('Sammlung','Sets','Tracks','Downloads')) { $navigation[$name].BackColor=$sidebar.BackColor }
            $active = if ($filter.SelectedIndex -eq 0) { 'Sammlung' } else { [string]$filter.SelectedItem }
            $navigation[$active].BackColor=$accent
            $label.Text=$active
            Update-LibraryResults -Reload
            if ($web.Ready) {
                $web.Control.Show()
                $web.Control.BringToFront()
                $web.PlayerState=''
                Send-WebPlayer
            }
        }
        function Show-DownloadView {
            if ($web.Control) { $web.Control.Hide() }
            $panel.Hide()
            $layout.Show()
            $layout.BringToFront()
            foreach ($name in @('Sammlung','Sets','Tracks')) { $navigation[$name].BackColor=$sidebar.BackColor }
            $navigation.Downloads.BackColor=$accent
        }
        $libraryView.ShowCollection = { Show-CollectionView }
        $navigation.Sammlung.Add_Click({ $filter.SelectedIndex=0; Show-CollectionView })
        $navigation.Sets.Add_Click({ $filter.SelectedItem='Sets'; Show-CollectionView })
        $navigation.Tracks.Add_Click({ $filter.SelectedItem='Tracks'; Show-CollectionView })
        $navigation.Downloads.Add_Click({ Show-DownloadView })
        $navigation.Einstellungen.Add_Click({ if (!$state.Worker) { $preferences.PerformClick(); Show-CollectionView } })
        $layout.RowStyles[0].Height=0
        if ($banner) { $banner.Hide() }
        Set-WindowTheme $panel
        function Set-CollectionColors($Control) {
            $Control.ForeColor=$ink
            if ($Control -is [Windows.Forms.Button] -or $Control -is [Windows.Forms.TextBox]) {
                $Control.BackColor=$surface
                if ($Control -is [Windows.Forms.Button]) { $Control.FlatAppearance.BorderSize=0 }
            } else { $Control.BackColor=$graphite }
            foreach ($child in $Control.Controls) { Set-CollectionColors $child }
        }
        Set-CollectionColors $panel
        $searchBar.BackColor=$surface
        $searchCaption.BackColor=$surface
        foreach ($control in $filterBar.Controls) {
            if ($control -is [Windows.Forms.Panel]) { $control.BackColor=$surface }
        }
        $panel.BackColor=$graphite
        $panel.ForeColor=$ink
        $content.BackColor=$graphite
        $covers.BackColor=$graphite
        $label.ForeColor=$ink
        $table.BackgroundColor=$graphite
        $table.DefaultCellStyle.BackColor=$graphite
        $table.DefaultCellStyle.ForeColor=$ink
        $table.DefaultCellStyle.SelectionBackColor=$accent
        $table.BorderStyle='None'
        $table.GridColor=$surface
        $table.CellBorderStyle='SingleHorizontal'
        $table.RowTemplate.Height=36
        $table.ColumnHeadersDefaultCellStyle.BackColor=$surface
        $table.ColumnHeadersDefaultCellStyle.ForeColor=$ink
        $add.FlatStyle = 'Flat'
        $add.BackColor = $accent
        $add.ForeColor = [Drawing.Color]::White
        $web = @{
            Control=$null; Ready=$false; Entries=@{}; PlayerState=''; DownloadState=''; DownloadsOpen=$false
            Commands=[Collections.Generic.Queue[object]]::new(); Dispatching=$false
            Export=@{Worker=$null;Handle=$null}
            Conversion=@{Worker=$null;Handle=$null;Files=@();Status='';Report=''}
            TransitionScan=@{Worker=$null;Handle=$null;Id='';Titles=@()}
            Metadata=@{Worker=$null;Handle=$null;Id='';Candidates=@{};Proposals=@{};LastRequest=[datetime]::MinValue}
            Initializing=[IO.File]::Exists((Join-Path $PSScriptRoot 'Microsoft.Web.WebView2.Core.dll'))
        }
        $resumePositionsPath=Join-Path $config 'set-resume.json'
        $web.Resume=@{}
        $web.NextResumeSave=[datetime]::UtcNow
        if ([IO.File]::Exists($resumePositionsPath)) {
            try {
                Assert-SafePath $resumePositionsPath
                $positions=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($resumePositionsPath,$utf8))
                foreach ($property in $positions.PSObject.Properties) { $web.Resume[$property.Name]=$property.Value }
            } catch { Write-Verbose $_.Exception.Message }
        }
        . (Join-Path $PSScriptRoot 'DJ-Sets-WebCollection.ps1')
        . (Join-Path $PSScriptRoot 'DJ-Sets-Covers.ps1')
        . (Join-Path $PSScriptRoot 'DJ-Sets-Convert.ps1')
        . (Join-Path $PSScriptRoot 'DJ-Sets-Tracklist.ps1')
        . (Join-Path $PSScriptRoot 'DJ-Sets-Transitions.ps1')
        . (Join-Path $PSScriptRoot 'DJ-Sets-Metadata.ps1')
        . (Join-Path $PSScriptRoot 'DJ-Sets-LibraryActions.ps1')
        . (Join-Path $PSScriptRoot 'DJ-Sets-Health.ps1')
        . (Join-Path $PSScriptRoot 'DJ-Sets-HealthRepair.ps1')
        . (Join-Path $PSScriptRoot 'DJ-Sets-HealthWeb.ps1')
        Initialize-WebHealth
        $libraryStatePath=Join-Path $config 'dj-set-library-state.json'
        Initialize-PkLibraryState
        $libraryView.OpenPage = {
            param($Page)
            if (!$web.Ready) { return $false }
            if ($Page -ne 'about') { Send-WebCollectionMessage @{type='page';page=$Page} }
            Invoke-WebCollectionCommand @{command=$Page}
            return $true
        }
        $webTimer = [Windows.Forms.Timer]@{ Interval=150 }
        $webTimer.Add_Tick({
            if ($web.Dispatching) { return }
            $web.Dispatching=$true
            try {
                for ($messageIndex=0; $web.Commands.Count -and $messageIndex -lt 12; $messageIndex++) {
                    Invoke-WebCollectionCommand ($web.Commands.Dequeue())
                }
                Send-WebPlayer
                if ([datetime]::UtcNow -ge $web.NextResumeSave) {
                    Save-WebSetPosition
                    $web.NextResumeSave=[datetime]::UtcNow.AddSeconds(8)
                }
                Send-WebDownloads
                Complete-WebDiagnostic
                Complete-WebExport
                Complete-WebConversion
                Complete-WebTransitionScan
                Complete-WebMetadata
                Complete-WebHealth
            } catch {
                [void][Windows.Forms.MessageBox]::Show($form,$_.Exception.Message,'Plattenkoffer')
            } finally { $web.Dispatching=$false }
        })
        $webTimer.Start()
        $form.Add_Shown({ Initialize-WebCollection })
        $updateNotice.Add_TextChanged({ Send-WebCollectionMessage @{type='update'; available=[bool]$updateCheck.Version} })
        Show-CollectionView
        [void]$form.ShowDialog()
    }
    finally {
        if ($webTimer) { $webTimer.Dispose() }
        if ($web.Export.Worker) { $web.Export.Worker.Dispose() }
        if ($web.Conversion.Worker) { $web.Conversion.Worker.Dispose() }
        if ($web.TransitionScan.Worker) { $web.TransitionScan.Worker.Dispose() }
        if ($web.Metadata.Worker) { $web.Metadata.Worker.Dispose() }
        if ($web.Health.Worker) { $web.Health.Control.Cancel=$true; $web.Health.Worker.Dispose() }
        if ($libraryView.Diagnostic.Worker) { $libraryView.Diagnostic.Worker.Dispose() }
        if (Get-Command Clear-LibraryCovers -CommandType Function -ErrorAction SilentlyContinue) { Clear-LibraryCovers }
        if (Get-Command Save-WebSetPosition -CommandType Function -ErrorAction SilentlyContinue) { Save-WebSetPosition }
        Stop-LibraryPlayback
        $audioTimer.Dispose()
        $addMenu.Dispose(); $helpActions.Dispose(); $headingFont.Dispose(); $brandFont.Dispose()
    }
}
$library.Add_Click({ if ($libraryView.ShowCollection) { & $libraryView.ShowCollection } })

$diagnosticWorker = {
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
}

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
            [void]$job.Worker.AddScript($diagnosticWorker.ToString()).AddArgument($yt).AddArgument($ffmpeg).AddArgument($deno).AddArgument($InstallUpdate).AddArgument($core)
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
$diagnose.Add_Click({
    if ($libraryView.OpenPage -and (& $libraryView.OpenPage 'diagnostics')) { return }
    Show-Diagnostics
})

$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($state.Worker -or $libraryView.Diagnostic.Worker -or $web.Export.Worker -or $web.Conversion.Worker -or $web.TransitionScan.Worker -or $web.Health.Worker) { $eventArgs.Cancel = $true; $status.Text = 'Ein Vorgang läuft noch. Das Fenster kann danach geschlossen werden.' }
})
Set-WindowTheme $form
$updateCheck = @{ Worker=$null; Handle=$null; Manual=$false; Url=''; AssetUrl=''; Version=$null; Installer=''; Phase='Check' }
$updateScript = Join-Path $PSScriptRoot 'DJ-Sets-AppUpdate.ps1'
$updateTimer = [Windows.Forms.Timer]@{ Interval=250 }
function Start-UpdateCheck([bool]$Manual) {
    if (!$appVersion -or $updateCheck.Worker) { return }
    $updateCheck.Manual = $Manual
    $updateCheck.Phase = 'Check'
    $updateCheck.Worker = [PowerShell]::Create()
    try {
        [void]$updateCheck.Worker.AddScript({
            $ErrorActionPreference = 'Stop'
            Invoke-RestMethod -Uri 'https://api.github.com/repos/GosuMind/Plattenkoffer/releases/latest' -UserAgent 'Plattenkoffer' -TimeoutSec 8
        }.ToString())
        $updateCheck.Handle = $updateCheck.Worker.BeginInvoke()
        $checkUpdate.Enabled = $false
        $updateTimer.Start()
    } catch {
        $updateCheck.Worker.Dispose()
        $updateCheck.Worker = $null
    }
}

$updateTimer.Add_Tick({
    if (!$updateCheck.Handle.IsCompleted) { return }
    if ($updateCheck.Phase -eq 'Download' -and ($state.Worker -or $libraryView.Diagnostic.Worker -or $web.Export.Worker -or $web.Conversion.Worker -or $web.TransitionScan.Worker -or $web.Health.Worker)) {
        $updateNotice.Text = 'Update wartet auf laufenden Vorgang …'
        return
    }
    $updateTimer.Stop()
    if ($updateCheck.Phase -eq 'Download') {
        try {
            $null = $updateCheck.Worker.EndInvoke($updateCheck.Handle)
            $arguments = ('-NoProfile -STA -ExecutionPolicy RemoteSigned -File "{0}" -Installer "{1}" -Version {2} -SignerHash {3} -AppProcessId {4}' -f
                $updateScript, $updateCheck.Installer, $updateCheck.Version, $updateSignerHash, $PID)
            Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WindowStyle Hidden
            $form.Close()
        } catch {
            [IO.File]::Delete($updateCheck.Installer)
            $updateNotice.Text = 'Jetzt aktualisieren …'
            $updateNotice.Enabled = $true
            [void][Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'Plattenkoffer-Update', 'OK', 'Error')
        } finally {
            $updateCheck.Worker.Dispose()
            $updateCheck.Worker = $null
            $checkUpdate.Enabled = $true
        }
        return
    }
    $message = 'Keine neuere Veröffentlichung mit Setup-Datei gefunden.'
    try {
        $release = $updateCheck.Worker.EndInvoke($updateCheck.Handle) | Select-Object -First 1
        $tag = [string]$release.tag_name
        if (!$release.draft -and !$release.prerelease -and $tag -cmatch '^v?(\d+\.\d+\.\d+)$') {
            $availableVersion = [version]$Matches[1]
            $assetName = "Plattenkoffer-Setup-$availableVersion.exe"
            $asset = $release.assets | Where-Object { $_.name -ceq $assetName } | Select-Object -First 1
            if ($availableVersion -gt $appVersion -and $asset) {
                $updateCheck.Url = "https://github.com/GosuMind/Plattenkoffer/releases/tag/$tag"
                $updateCheck.AssetUrl = "https://github.com/GosuMind/Plattenkoffer/releases/download/$tag/$assetName"
                $updateCheck.Version = $availableVersion
                $updateNotice.Text = if ($updateSignerHash) { "Jetzt auf $availableVersion aktualisieren …" } else { "Update $availableVersion verfügbar …" }
                $updateNotice.Visible = $true
                $message = "Plattenkoffer $availableVersion ist verfügbar."
            }
        }
    } catch { $message = 'Die Update-Suche ist gerade nicht erreichbar.' }
    finally {
        $updateCheck.Worker.Dispose()
        $updateCheck.Worker = $null
        $checkUpdate.Enabled = $true
    }
    if ($updateCheck.Manual) {
        [void][Windows.Forms.MessageBox]::Show($form, $message, 'Plattenkoffer-Updates')
    }
})
$checkUpdate.Add_Click({ Start-UpdateCheck $true })
$updateNotice.Add_Click({
    if ($updateCheck.Worker) { return }
    if (!$updateSignerHash) {
        try { Start-Process -FilePath $updateCheck.Url }
        catch { [void][Windows.Forms.MessageBox]::Show($form, 'Die Release-Seite konnte nicht geöffnet werden.', 'Plattenkoffer-Updates') }
        return
    }
    if ([Windows.Forms.MessageBox]::Show($form, "Plattenkoffer $($updateCheck.Version) installieren? Die App startet nach dem Update neu.",
        'Plattenkoffer-Update', 'YesNo', 'Question') -ne 'Yes') { return }
    try {
        $stage = Join-Path $config ('update-' + [guid]::NewGuid().ToString('N'))
        Assert-SafePath $stage
        [void][IO.Directory]::CreateDirectory($stage)
        $updateCheck.Installer = Join-Path $stage "Plattenkoffer-Setup-$($updateCheck.Version).exe"
        $updateCheck.Phase = 'Download'
        $updateCheck.Worker = [PowerShell]::Create()
        [void]$updateCheck.Worker.AddScript({
            param($Url, $InstallerPath, $ExpectedVersion, $ExpectedSigner, $Helper)
            $ErrorActionPreference = 'Stop'
            $ProgressPreference = 'SilentlyContinue'
            . $Helper
            Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $InstallerPath -TimeoutSec 120
            Test-AppUpdateInstaller $InstallerPath $ExpectedVersion $ExpectedSigner
        }.ToString()).AddArgument($updateCheck.AssetUrl).AddArgument($updateCheck.Installer).AddArgument(
            $updateCheck.Version).AddArgument($updateSignerHash).AddArgument($updateScript)
        $updateCheck.Handle = $updateCheck.Worker.BeginInvoke()
        $updateNotice.Text = 'Update wird geladen und geprüft …'
        $updateNotice.Enabled = $checkUpdate.Enabled = $false
        $updateTimer.Start()
    } catch {
        if ($updateCheck.Worker) { $updateCheck.Worker.Dispose(); $updateCheck.Worker = $null }
        [void][Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'Plattenkoffer-Update', 'OK', 'Error')
    }
})
$form.Add_Shown({
    Start-UpdateCheck $false
})
try { Show-Library } finally {
    $updateTimer.Dispose()
    if ($updateCheck.Worker) { $updateCheck.Worker.Dispose() }
    $timer.Dispose(); $form.Dispose(); $lock.Dispose()
}

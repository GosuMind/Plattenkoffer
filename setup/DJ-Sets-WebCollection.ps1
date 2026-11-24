# The collection host runs inside the main form's message loop.
function Send-WebCollectionMessage($Payload) {
    if ($web.Ready -and $web.Control -and !$web.Control.IsDisposed) {
        $web.Control.CoreWebView2.PostWebMessageAsJson((ConvertTo-Json -InputObject $Payload -Depth 5 -Compress))
    }
}

function Send-WebLibrary {
    if (!$web.Ready) { return }
    $web.Entries.Clear()
    $records = @(foreach ($entry in $libraryData.Entries) {
        $algorithm=[Security.Cryptography.SHA256]::Create()
        try { $id=[BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($entry.Path))).Replace('-','') }
        finally { $algorithm.Dispose() }
        $web.Entries[$id] = $entry
        @{
            id=$id; title=(Get-LibraryDisplayTitle $entry); originalTitle=[string]$entry.Title; artist=[string]$entry.Artist
            series=[string]$entry.Series; event=[string]$entry.Event; place=[string]$entry.Location
            album=[string]$entry.Album; year=[string]$entry.Year; date=[string]$entry.Date
            label=[string]$entry.Label; version=[string]$entry.Version
            genre=[string]$entry.Genre
            favorite=$entry.Path -in $web.LibraryState.Favorites
            kind=$(if ($entry.Type -eq 'Tracks') { 'Track' } else { 'Set' })
            external=[bool]$entry.External; hasCover=$true
            hasDescription=(!$entry.External -and [IO.File]::Exists((Join-Path $entry.Path 'info.json')))
        }
    })
    Send-WebCollectionMessage @{ type='collection'; entries=$records }
    Send-WebPlaylists
    Send-WebCollectionMessage @{ type='update'; available=[bool]$updateCheck.Version }
}

function Send-WebPlayer {
    if (!$web.Ready -or !$web.Control.Visible) { return }
    $stateKey = "$($nowPlaying.Text)|$($elapsedLabel.Text)|$($seekBar.Value)|$($audio.Process -ne $null)|$($transport.Enabled)|$($web.Queue.Paths.Count)|$($web.Queue.Index)"
    if ($web.PlayerState -ceq $stateKey) { return }
    $web.PlayerState = $stateKey
    Send-WebCollectionMessage @{
        type='player'; title=$nowPlaying.Text; time=$elapsedLabel.Text
        position=$seekBar.Value; duration=$(if ($seekBar.Enabled) { $seekBar.Maximum } else { 0 })
        playing=[bool]$audio.Process; active=$transport.Enabled; id=$web.PlayingId
        canPrevious=$web.Queue.Paths.Count -gt 1; canNext=$web.Queue.Paths.Count -gt 1
    }
}

function Send-WebDownloads {
    if (!$web.Ready -or !$web.DownloadsOpen) { return }
    $rows = @(foreach ($row in $grid.Rows) {
        @{
            id=[string]$row.Tag.Id; selected=[bool]$row.Cells['Selected'].Value
            artist=[string]$row.Cells['Artist'].Value; title=[string]$row.Cells['Title'].Value
            kind=[string]$row.Cells['Type'].Value; status=[string]$row.Cells['Status'].Value
            archived=[bool]$row.Tag.Archived
        }
    })
    $payload = @{
        type='downloads'; status=$status.Text; busy=[bool]$state.Worker; rows=$rows
        log=$log.Text.Substring([Math]::Max(0,$log.TextLength-8000))
        percent=$(if ($progress.Style -ne 'Marquee') { $progress.Value } else { $null })
        actions=@{ download=$download.Enabled; 'cancel-download'=$stop.Enabled; 'resume-queue'=$resume.Enabled; 'retry-queue'=$retry.Enabled }
    }
    $json = ConvertTo-Json -InputObject $payload -Depth 5 -Compress
    if ($web.DownloadState -cne $json) {
        $web.DownloadState=$json
        $web.Control.CoreWebView2.PostWebMessageAsJson($json)
    }
}

function Send-WebCover($Entry,[string]$Id) {
    $custom = Get-PkCustomCover $Entry $Id
    Assert-SafePath $custom
    if ([IO.File]::Exists($custom)) {
        if ([IO.FileInfo]::new($custom).Length -gt 8MB) { throw 'Das gespeicherte Cover ist zu groß.' }
        $encoded=[Convert]::ToBase64String([IO.File]::ReadAllBytes($custom))
        Send-WebCollectionMessage @{type='cover';id=$Id;image="data:image/jpeg;base64,$encoded"}
        return
    }
    if ($Entry.External) { Send-WebCollectionMessage @{type='cover';id=$Id;image=''}; return }
    $formats = [ordered]@{'jpg'='jpeg';'jpeg'='jpeg';'png'='png';'webp'='webp';'avif'='avif'}
    foreach ($extension in $formats.Keys) {
        $path = Join-Path $Entry.Path "cover.$extension"
        if (![IO.File]::Exists($path)) { continue }
        Assert-SafePath $path
        if ([IO.FileInfo]::new($path).Length -gt 8MB) { continue }
        $mime = $formats[$extension]
        $encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
        Send-WebCollectionMessage @{ type='cover'; id=$Id; image="data:image/$mime;base64,$encoded" }
        return
    }
    Send-WebCollectionMessage @{type='cover';id=$Id;image=''}
}

function Save-WebSetPosition([switch]$Forget) {
    if (!$Forget -and $settings.ContainsKey('ResumeSets') -and !$settings.ResumeSets) { return }
    $id=$web.PlayingId
    if (!$id -or !$web.SetPlaying) { return }
    try {
        if ($Forget) {
            $web.Resume.Remove($id)
        } elseif ($transport.Enabled) {
            $position=$audio.Offset + $(if ($audio.Process) { $audio.Clock.Elapsed.TotalSeconds } else { 0 })
            $second=[int][Math]::Floor([Math]::Max(0.0,[double]$position))
            $previous=$web.Resume[$id]
            if ($previous -and $previous.part -eq $audio.Index -and $previous.second -eq $second) { return }
            $web.Resume[$id]=@{part=$audio.Index;second=$second}
        } else { return }
        Write-AtomicText $resumePositionsPath (ConvertTo-Json -InputObject $web.Resume -Depth 4)
    } catch { Write-Verbose $_.Exception.Message }
}

function Send-WebSettings([string]$Message, [switch]$Values) {
    $payload = @{ type='settings'; status=$Message }
    if ($Values) {
        $payload.folder=$settings.MusicRoot; $payload.theme=$settings.Theme
        $prefs=@{}
        foreach ($key in (Get-PkDefaultPreferences).Keys) { $prefs[$key]=$settings[$key] }
        $payload.preferences=$prefs
    }
    Send-WebCollectionMessage $payload
}

function Save-WebSettings($Message) {
    if ($state.Worker) { Send-WebSettings 'Warte, bis der laufende Download beendet ist.'; return }
    try {
        if ($Message.folder -isnot [string] -or $Message.folder -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)' -or
            $Message.theme -notin @('System','Hell','Dunkel')) { throw 'Bitte einen vollständigen Ordnerpfad und ein gültiges Farbschema wählen.' }
        $path=[IO.Path]::GetFullPath($Message.folder)
        Assert-SafePath $path
        [void][IO.Directory]::CreateDirectory($path)
        $next=Merge-PkPreferences $settings $Message.preferences
        $next.MusicRoot=$path; $next.Theme=$Message.theme
        Write-AtomicText $settingsPath (ConvertTo-Json $next)
        Apply-PkPreferences $next
        $destination.Text="Downloadordner: $path"
        Update-Targets
        Update-LibraryResults -Reload
        Send-WebSettings 'Einstellungen gespeichert.' -Values
    } catch { Send-WebSettings $_.Exception.Message }
}

function Open-WebSettingsPicker([string]$Action) {
    if ($Action -eq 'browse') {
        $picker=[Windows.Forms.FolderBrowserDialog]@{Description='Downloadordner auswählen';SelectedPath=$settings.MusicRoot}
    } elseif ($Action -eq 'backup') {
        $picker=[Windows.Forms.SaveFileDialog]@{Filter='ZIP-Archiv (*.zip)|*.zip';DefaultExt='zip';FileName="Plattenkoffer-Konfiguration-$(Get-Date -Format yyyy-MM-dd).zip"}
    } else {
        if ($state.Worker -or $libraryView.Diagnostic.Worker) { Send-WebSettings 'Warte, bis der laufende Vorgang beendet ist.'; return }
        $picker=[Windows.Forms.OpenFileDialog]@{Filter='ZIP-Archiv (*.zip)|*.zip'}
    }
    try {
        if ($picker.ShowDialog($form) -ne 'OK') { return }
        switch ($Action) {
            'browse' { Send-WebCollectionMessage @{type='settings';folder=$picker.SelectedPath;status='Ordner ausgewählt. Speichern übernimmt die Änderung.'} }
            'backup' { Save-ConfigurationBackup $picker.FileName; Send-WebSettings 'Konfiguration gesichert.' }
            'restore' {
                $backup=Restore-ConfigurationBackup $picker.FileName
                [void][Windows.Forms.MessageBox]::Show($form,"Konfiguration wiederhergestellt. Bitte Plattenkoffer neu starten.`r`nVorherige Konfiguration: $backup",'Plattenkoffer')
                $form.Close()
            }
        }
    } catch { Send-WebSettings $_.Exception.Message }
    finally { $picker.Dispose() }
}

function Send-WebDiagnostic {
    $job=$libraryView.Diagnostic
    Send-WebCollectionMessage @{type='diagnostics';report=$job.Report;status=$job.Status;busy=[bool]$job.Worker}
}

function Start-WebDiagnostic([string]$Tool) {
    $job=$libraryView.Diagnostic
    if ($job.Worker) { return }
    if ($state.Worker -or $web.Conversion.Worker -or $web.TransitionScan.Worker -or $updateCheck.Phase -eq 'Download' -and $updateCheck.Worker) {
        $job.Status='Warte, bis der laufende Vorgang beendet ist.'
        Send-WebDiagnostic
        return
    }
    try {
        $job.Worker=[PowerShell]::Create()
        [void]$job.Worker.AddScript($diagnosticWorker.ToString()).AddArgument($yt).AddArgument($ffmpeg).AddArgument($deno).AddArgument($Tool).AddArgument($core)
        $job.Handle=$job.Worker.BeginInvoke()
        $job.Status=if ($Tool) { "$Tool wird aktualisiert …" } else { 'Versionen werden geprüft …' }
    } catch {
        if ($job.Worker) { $job.Worker.Dispose(); $job.Worker=$null }
        $job.Status=$_.Exception.Message
    }
    Send-WebDiagnostic
}

function Complete-WebDiagnostic {
    $job=$libraryView.Diagnostic
    if (!$job.Worker -or !$job.Handle.IsCompleted) { return }
    try {
        $report=@($job.Worker.EndInvoke($job.Handle) | ForEach-Object { [string]$_ })
        $errors=@($job.Worker.Streams.Error | ForEach-Object { $_.ToString() })
        $job.Report=($report+$errors) -join "`r`n"
        $job.Status=if ($errors.Count -or ($report -match '^Update-Rückgabecode: .*: [1-9]')) { 'Der Vorgang meldet Fehler. Siehe Werkzeugbericht.' } else { 'Vorgang abgeschlossen.' }
    } catch {
        $job.Report=$_.Exception.Message
        $job.Status='Der Vorgang ist fehlgeschlagen.'
    } finally { $job.Worker.Dispose(); $job.Worker=$null }
    Send-WebDiagnostic
}

function Send-WebEntryDialog($Entry,[string]$Id,[string]$Action) {
    $title = $null
    $fields = @()
    $submit = 'Speichern'
    switch ($Action) {
        'edit' {
            $title = 'Einordnung bearbeiten'
            $labels = [ordered]@{Title='Tracktitel';Artist='DJs';SetNameOverride='Eigener Set-Name (optional)';Album='Album';Year='Jahr';Label='Label';Version='Version / Remix';Genre='Genre';Date='Aufnahmedatum (JJJJ-MM-TT)';Series='Set-Reihe';Event='Veranstaltung';Location='Location'}
            $fields = @(foreach ($key in $labels.Keys) {
                $only = if ($key -in @('Title','Album','Label','Version')) { 'Tracks' } elseif ($key -in @('SetNameOverride','Date','Series','Event','Location')) { 'Sets' } else { '' }
                @{name=$key;label=$labels[$key];value=[string]$Entry.$key;required=$key -eq 'Title';only=$only}
            })
            $fields += @{name='Type';label='Typ';value=$Entry.Type;options=@('Sets','Tracks');disabled=!$Entry.External}
        }
        'move' {
            $title='Ordner umbenennen'
            $artist=Split-Path -Leaf (Split-Path -Parent (Split-Path -Parent $Entry.Path))
            $fields=@(
                @{name='Artist';label='DJ-Ordner';value=$artist;required=$true},
                @{name='Title';label='Eintragsordner';value=(Split-Path -Leaf $Entry.Path);required=$true}
            )
        }
        'export' {
            $title='Auf Gerät exportieren'
            $submit='Exportieren'
            $fields=@(
                @{name='destination';label='USB-Stick oder Zielordner';required=$true},
                @{name='mode';label='Format';value='Originalkopie';options=@('Originalkopie','MP3-Teile','Durchgehende MP3')},
                @{name='bitrate';label='MP3-Bitrate (kbit/s)';value='256';options=@('128','192','256','320')}
            )
        }
        'about' { $title="Plattenkoffer · $versionLabel"; $submit='Schließen' }
    }
    Send-WebCollectionMessage @{type='entry-dialog';action=$Action;id=$Id;title=$title;submit=$submit;fields=$fields}
}

function Send-WebEntryStatus([string]$Message,[switch]$Close) {
    Send-WebCollectionMessage @{type='entry-status';status=$Message;close=[bool]$Close;busy=[bool]$web.Export.Worker}
}

function Save-WebEntry($Entry,$Values) {
    if ($state.Worker) { throw 'Warte, bis der laufende Download beendet ist.' }
    $metadata=[ordered]@{}
    foreach ($key in @('Title','Artist','Album','Year','Label','Version','Genre','Date','Series','Event','Location','SetNameOverride')) {
        $metadata[$key]=if ($Values.PSObject.Properties[$key]) { ([string]$Values.$key).Trim() } else { [string]$Entry.$key }
    }
    if (!$metadata.Title) { throw 'Bitte einen Titel eingeben.' }
    if ($Values.PSObject.Properties['Year'] -and $metadata.Year -and $metadata.Year -notmatch '^[1-9][0-9]{3}$') { throw 'Bitte ein vierstelliges Jahr eingeben.' }
    if ($Values.PSObject.Properties['Date'] -and $metadata.Date) {
        $dateValue = [datetime]::MinValue
        if (![datetime]::TryParseExact($metadata.Date,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$dateValue)) {
            throw 'Bitte ein gültiges Datum im Format JJJJ-MM-TT eingeben.'
        }
        $metadata.Year=$dateValue.ToString('yyyy',[Globalization.CultureInfo]::InvariantCulture)
    }
    $sources=[ordered]@{}
    $sourceValues=if ($Values.PSObject.Properties['MetadataSources']) { $Values.MetadataSources } else { $Entry.MetadataSources }
    foreach ($property in $sourceValues.PSObject.Properties) {
        if ($property.Name -in @('Album','Year','Label','Version','Genre') -and $property.Value.Value -ceq $metadata[$property.Name]) {
            $sources[$property.Name]=$property.Value
        }
    }
    if ($sources.Count) { $metadata.MetadataSources=[pscustomobject]$sources }
    Assert-SafePath $Entry.Path
    if ($Entry.External) {
        if ($Values.Type -notin @('Sets','Tracks')) { throw 'Bitte einen gültigen Typ auswählen.' }
        $metadata.Path=$Entry.Path
        $metadata.Type=[string]$Values.Type
        $metadata.External=$true
        $entries=@(Read-LocalLibrary | ForEach-Object {
            if ($_.Path -eq $Entry.Path) { [pscustomobject]$metadata } else { $_ }
        })
        Save-LocalLibrary $entries
    } else {
        if (![IO.Directory]::Exists($Entry.Path)) { throw 'Der Eintragsordner ist nicht erreichbar.' }
        Write-AtomicText (Join-Path $Entry.Path 'plattenkoffer.json') (ConvertTo-Json $metadata -Depth 6)
    }
    Update-LibraryResults -Reload
    Send-WebEntryStatus '' -Close
}

function Start-WebExport($Entry,$Values) {
    if ($web.Export.Worker) { return }
    $root=[string]$Values.destination
    if ($root -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)') { throw 'Bitte einen vollständigen Zielordner auswählen.' }
    $mode=@{'Originalkopie'='Copy';'MP3-Teile'='MP3';'Durchgehende MP3'='Join'}[[string]$Values.mode]
    if (!$mode) { throw 'Bitte ein Exportformat auswählen.' }
    $bitrate=256
    if ($mode -ne 'Copy') {
        if ($Values.bitrate -notin @('128','192','256','320')) { throw 'Bitte eine gültige MP3-Bitrate auswählen.' }
        $bitrate=[int]$Values.bitrate
    }
    $worker=[PowerShell]::Create()
    try {
        $script='param($ffmpeg,$utf8,$Source,$Root,$Mode,$Bitrate); $ErrorActionPreference="Stop";'
        foreach ($fn in @('Safe-Name','Assert-SafePath','Get-SetAudio','Export-LibrarySet')) {
            $script += "function $fn { $((Get-Command $fn).Definition) };"
        }
        $script += 'Export-LibrarySet $Source $Root $Mode $Bitrate'
        [void]$worker.AddScript($script).AddArgument($ffmpeg).AddArgument($utf8).AddArgument($Entry.Path).AddArgument($root).AddArgument($mode).AddArgument($bitrate)
        $web.Export.Handle=$worker.BeginInvoke()
        $web.Export.Worker=$worker
        Send-WebEntryStatus 'Export läuft …'
    } catch { $worker.Dispose(); throw }
}

function Complete-WebExport {
    $job=$web.Export
    if (!$job.Worker -or !$job.Handle.IsCompleted) { return }
    try {
        $result=$job.Worker.EndInvoke($job.Handle)
        $message="Exportiert nach $($result[-1])."
    } catch { $message=$_.Exception.Message }
    finally { $job.Worker.Dispose(); $job.Worker=$null }
    Send-WebEntryStatus $message
}

function Invoke-WebCollectionCommand($Message) {
    if ($Message.command -eq 'health' -or $Message.command -like 'health-*') { Invoke-WebHealth $Message;return }
    if($web.Health.Worker -and $web.Health.Operation -in @('repair','restore') -and $Message.command -in @('play','toggle','seek','playlist-play','player-next','player-previous')){throw 'Während einer Reparatur oder Wiederherstellung bleibt die Wiedergabe gestoppt.'}
    if ($web.Health.Worker -and $Message.command -in @('download','convert-start','metadata-apply','delete-confirm','cover-save','cover-reset','edit-submit','move-submit','settings-save','settings-restore','diagnose-yt','diagnose-ffmpeg','diagnose-deno')) {
        throw 'Zuerst die laufende Bibliothekspflege beenden.'
    }
    $entry = $null
    if ($Message.id -is [string]) { $entry = $web.Entries[$Message.id] }
    if ($Message.command -in @('favorite','playlist-create','playlist-rename','playlist-delete','playlist-add','playlist-remove','playlist-order')) {
        Invoke-WebPlaylistCommand $Message
        return
    }
    if ($Message.command -in @('delete-preview','delete-confirm','delete-cancel')) {
        Invoke-WebLibraryDelete $Message
        return
    }
    if ($Message.command -in @('metadata-open','metadata-search','metadata-select','metadata-source','metadata-apply')) {
        Invoke-WebMetadata $entry $Message
        return
    }
    if ($Message.command -in @('cover-edit','cover-choose','cover-save','cover-reset')) {
        if ($entry) { Invoke-WebCoverEdit $entry $Message }
        return
    }
    if ($Message.command -in @('tracklist-open','tracklist-add','tracklist-import','tracklist-description','tracklist-remove','tracklist-time','tracklist-jump','tracklist-scan','tracklist-confirm','tracklist-preview')) {
        try { Invoke-WebTracklist $entry $Message }
        catch { Send-WebCollectionMessage @{type='tracklist';id=$Message.id;status=$_.Exception.Message} }
        return
    }
    switch ($Message.command) {
        'convert' { Send-WebConversion }
        'convert-files' { Select-ConversionFiles }
        'convert-folder' { Select-ConversionFolder }
        'convert-start' { Start-WebConversion $Message.values }
        'audio-info' {
            if (!$entry) { return }
            $summary = 'Dateityp und Audioqualität nicht verfügbar'
            try {
                $parts = @(Get-SetAudio $entry.Path)
                if ($parts.Count) {
                    $file = $parts[0]
                    Assert-SafePath $file.FullName
                    $json = & $probe -v error -select_streams a:0 -show_entries 'stream=codec_name,bit_rate,sample_rate' -of json -- $file.FullName
                    if ($LASTEXITCODE -eq 0) {
                        $stream = (ConvertFrom-Json -InputObject ($json -join "`n")).streams | Select-Object -First 1
                        $info = @($file.Extension.TrimStart('.').ToUpperInvariant())
                        if ($stream.codec_name -and $stream.codec_name -ine $info[0]) { $info += $stream.codec_name.ToUpperInvariant() }
                        if ($stream.bit_rate -match '^[0-9]+$') { $info += "$([Math]::Round([double]$stream.bit_rate/1000)) kbit/s" }
                        if ($stream.sample_rate -match '^[0-9]+$') { $info += "$([double]$stream.sample_rate/1000) kHz" }
                        if ($parts.Count -gt 1) { $info += 'Erster Teil' }
                        $summary = $info -join ' · '
                    }
                }
            } catch { Write-Verbose $_.Exception.Message }
            Send-WebCollectionMessage @{type='audio-info';id=$Message.id;text=$summary}
        }
        'ready' {
            $web.Initializing=$false
            $web.Ready=$true
            $web.Control.Show()
            $web.Control.BringToFront()
            $web.PlayerState=''
            Send-WebLibrary
            Send-WebPlayer
            Send-WebSettings '' -Values
        }
        'cover' { if ($entry) { Send-WebCover $entry $Message.id } }
        'play' {
            Start-WebPlaybackQueue $Message
        }
        'playlist-play' { Start-WebPlaybackQueue $Message }
        'player-next' { [void](Step-WebPlaybackQueue 1) }
        'player-previous' { [void](Step-WebPlaybackQueue -1) }
        'mini-player' { Set-WebMiniPlayer (![bool]$web.Mini) }
        'preferences-change' { try { Save-PkPreferences $Message.values } catch { Send-WebSettings $_.Exception.Message } }
        'toggle' { $transport.PerformClick() }
        'stop' { Save-WebSetPosition; $web.Queue.Paths=@(); Stop-LibraryPlayback }
        'seek' {
            if ($seekBar.Enabled -and ($Message.position -is [int] -or $Message.position -is [long])) {
                $seekBar.Value=[int][Math]::Max(0,[Math]::Min($seekBar.Maximum,$Message.position))
                & $seekAction
            }
        }
        'volume' {
            if (($Message.value -is [int] -or $Message.value -is [long]) -and $Message.value -ge 0 -and $Message.value -le 100) {
                $volume.Value=[int]$Message.value
                & $volumeChangedAction
            }
        }
        'downloads' {
            $web.DownloadsOpen=$true
            $web.DownloadState=''
            $panel.Hide()
            $layout.Show()
        }
        'refresh' { $web.DownloadsOpen=$false; Update-LibraryResults -Reload }
        'search-youtube' {
            if (!$state.Worker -and $Message.value -is [string] -and $Message.value.Length -le 200) {
                $youtubeSearch.Text=$Message.value
                $searchYouTube.PerformClick()
            }
        }
        'preview-links' {
            if (!$state.Worker -and $Message.value -is [string] -and $Message.value.Length -le 16000) {
                $link.Text=$Message.value
                $script:WebPlaylistChoice = $Message.playlist -eq $true
                try { $preview.PerformClick() }
                finally { $script:WebPlaylistChoice = $null }
            }
        }
        'edit-preview' {
            if ($state.Worker -or $Message.id -isnot [string]) { return }
            foreach ($row in $grid.Rows) {
                if ($row.Tag.Id -cne $Message.id -or $row.ReadOnly) { continue }
                switch ($Message.field) {
                    'selected' { if ($Message.value -is [bool]) { $row.Cells['Selected'].Value=$Message.value } }
                    'artist' { if ($Message.value -is [string] -and $Message.value.Length -le 300) { $row.Cells['Artist'].Value=$Message.value } }
                    'title' { if ($Message.value -is [string] -and $Message.value.Length -le 300) { $row.Cells['Title'].Value=$Message.value } }
                    'kind' { if ($Message.value -in @('Set','Track')) { $row.Cells['Type'].Value=$Message.value } }
                }
                break
            }
        }
        'download' { Start-WebDownloadReview }
        'download-review-submit' { Confirm-WebDownloadReview $Message }
        'cancel-download' { $stop.PerformClick() }
        'resume-queue' { $resume.PerformClick() }
        'retry-queue' { $retry.PerformClick() }
        'files' { $files.PerformClick() }
        'folders' { $folders.PerformClick() }
        'copy' { if (!$state.Worker) { $import.PerformClick(); Update-LibraryResults -Reload } }
        'settings' { Send-WebSettings '' -Values }
        'settings-save' { Save-WebSettings $Message }
        'settings-browse' { Open-WebSettingsPicker 'browse' }
        'settings-backup' { Open-WebSettingsPicker 'backup' }
        'settings-restore' { Open-WebSettingsPicker 'restore' }
        'about' { Send-WebEntryDialog $null '' 'about' }
        'about-submit' { Send-WebEntryStatus '' -Close }
        'check-updates' { $checkUpdate.PerformClick() }
        'diagnostics' { Send-WebDiagnostic; if (!$libraryView.Diagnostic.Report) { Start-WebDiagnostic '' } }
        'diagnose-check' { Start-WebDiagnostic '' }
        'diagnose-yt' { Start-WebDiagnostic 'yt-dlp' }
        'diagnose-ffmpeg' { Start-WebDiagnostic 'FFmpeg' }
        'diagnose-deno' { Start-WebDiagnostic 'Deno' }
        'diagnose-copy' { [Windows.Forms.Clipboard]::SetText((@($libraryView.Diagnostic.Report,'','Letzte Fehler') + @(Get-AppErrors)) -join "`r`n") }
        'diagnose-logs' { [void][IO.Directory]::CreateDirectory($logDirectory); Start-Process explorer.exe ('"{0}"' -f $logDirectory) }
        'support' { Open-SupportPage }
        'update' { $updateNotice.PerformClick() }
        'edit' { if ($entry) { Send-WebEntryDialog $entry $Message.id 'edit' } }
        'set-name-preview' {
            if ($entry -and ($entry.Type -eq 'Sets' -or $entry.External)) {
                $draft = @{Type='Sets';Title=$entry.Title}
                foreach ($key in @('Artist','Event','Location','Date','Year','SetNameOverride')) {
                    $draft[$key] = if ($Message.values.PSObject.Properties[$key]) { [string]$Message.values.$key } else { [string]$entry.$key }
                }
                Send-WebCollectionMessage @{type='set-name-preview';id=$Message.id;revision=$Message.revision;title=(Get-LibraryDisplayTitle $draft)}
            }
        }
        'edit-submit' { if ($entry) { try { Save-WebEntry $entry $Message.values } catch { Send-WebEntryStatus $_.Exception.Message } } }
        'export' { if ($entry) { Send-WebEntryDialog $entry $Message.id 'export' } }
        'export-browse' {
            $picker=[Windows.Forms.FolderBrowserDialog]@{Description='Exportziel auswählen'}
            try {
                if ($picker.ShowDialog($form) -eq 'OK') {
                    Send-WebCollectionMessage @{type='entry-status';destination=$picker.SelectedPath}
                }
            } finally { $picker.Dispose() }
        }
        'export-submit' { if ($entry) { try { Start-WebExport $entry $Message.values } catch { Send-WebEntryStatus $_.Exception.Message } } }
        'folder' {
            if ($entry) {
                $folderPath = if ($entry.External) { Split-Path -Parent $entry.Path } else { $entry.Path }
                if ([IO.Directory]::Exists($folderPath)) { Start-Process explorer.exe ('"{0}"' -f $folderPath) }
            }
        }
        'move' {
            if ($entry -and !$entry.External) { Send-WebEntryDialog $entry $Message.id 'move' }
        }
        'move-submit' {
            if ($entry -and !$entry.External) {
                try {
                    if ($state.Worker) { throw 'Warte, bis der laufende Download beendet ist.' }
                    $target=Get-EditedSetPath $settings.MusicRoot ([string]$Message.values.Artist) ([string]$Message.values.Title) $entry.Path
                    if (!$target) { throw 'Bitte DJ-Ordner und Eintragsordner eingeben.' }
                    if (!(Move-LibrarySet $settings.MusicRoot $entry.Path $target)) { throw 'Der Zielordner entspricht dem bisherigen Ordner.' }
                    Update-PkLibraryReferences $entry.Path $target
                    Update-LibraryResults -Reload
                    Send-WebEntryStatus '' -Close
                } catch { Send-WebEntryStatus $_.Exception.Message }
            }
        }
    }
}

function Initialize-WebCollection {
    $corePath = Join-Path $PSScriptRoot 'Microsoft.Web.WebView2.Core.dll'
    if (![IO.File]::Exists($corePath)) { return }
    try {
        Add-Type -Path $corePath
        Add-Type -Path (Join-Path $PSScriptRoot 'Microsoft.Web.WebView2.WinForms.dll')
        $browser = [Microsoft.Web.WebView2.WinForms.WebView2]::new()
        $web.Control = $browser
        $browser.Dock='Fill'
        $browser.DefaultBackgroundColor=[Drawing.Color]::FromArgb(28,27,25)
        $creation = [Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties]::new()
        $creation.UserDataFolder = Join-Path $config 'WebView2'
        $browser.CreationProperties=$creation
        $form.Controls.Add($browser)
        $browser.BringToFront()
        $browser.Add_CoreWebView2InitializationCompleted({
            param($sender,$eventArgs)
            if (!$eventArgs.IsSuccess) {
                Write-AppError 'WebView2' 'Die neue Sammlung konnte nicht initialisiert werden.'
                $web.Initializing=$false
                $sender.Hide()
                Update-LibraryResults
                return
            }
            $coreView=$sender.CoreWebView2
            $coreView.Settings.AreDevToolsEnabled=$false
            $coreView.Settings.AreDefaultContextMenusEnabled=$false
            $coreView.Settings.AreHostObjectsAllowed=$false
            $coreView.SetVirtualHostNameToFolderMapping('plattenkoffer.local',(Join-Path $PSScriptRoot 'ui'),'Deny')
            $coreView.Add_NewWindowRequested({ param($source,$eventArgs) $eventArgs.Handled=$true })
            $coreView.Add_NavigationStarting({
                param($source,$eventArgs)
                $eventArgs.Cancel=$eventArgs.Uri -cne 'https://plattenkoffer.local/index.html'
            })
            $coreView.Add_WebMessageReceived({
                param($source,$eventArgs)
                if ($eventArgs.Source -cne 'https://plattenkoffer.local/index.html' -or $eventArgs.WebMessageAsJson.Length -gt 160000) { return }
                try {
                    $message=ConvertFrom-Json -InputObject $eventArgs.WebMessageAsJson
                    if ($message.command -is [string] -and $web.Commands.Count -lt 512) { $web.Commands.Enqueue($message) }
                } catch {
                    [void][Windows.Forms.MessageBox]::Show($form,$_.Exception.Message,'Plattenkoffer')
                }
            })
            $coreView.Navigate('https://plattenkoffer.local/index.html')
        })
        $null=$browser.EnsureCoreWebView2Async()
    } catch {
        Write-AppError 'WebView2' 'Die neue Sammlung konnte nicht gestartet werden.'
        $web.Initializing=$false
        if ($web.Control) { $web.Control.Hide() }
        Update-LibraryResults
    }
}

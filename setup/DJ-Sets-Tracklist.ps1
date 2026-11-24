function ConvertFrom-PkTracklist([string]$Text,[switch]$AllowUntimed) {
    foreach ($line in ($Text -split '\r?\n')) {
        $seconds=$null
        $label=$line.Trim()
        if ($line -match '^\s*[\[(]?(?<stamp>\d{1,5}:\d{2}(?::\d{2})?)[\])]?(?:\s|[-–—])+?(?<name>.+?)\s*$') {
            $parts=@($Matches.stamp.Split(':') | ForEach-Object { [int]$_ })
            if ($parts[-1] -ge 60 -or ($parts.Count -eq 3 -and $parts[1] -ge 60)) { continue }
            $label=$Matches.name.Trim().TrimStart([char[]]'-–—').Trim()
            $seconds=$parts[-2]*60+$parts[-1]
            if ($parts.Count -eq 3) { $seconds+=$parts[0]*3600 }
        } elseif ($AllowUntimed) {
            $label=$label -replace '^\d+\s*[.)]\s+',''
        } else { continue }
        if (!$label) { continue }
        $names = $label -split '\s+[-–—]\s+',2
        if ($names.Count -eq 2) {
            [pscustomobject]@{second=$seconds;artist=$names[0];title=$names[1]}
        } else { [pscustomobject]@{second=$seconds;artist='';title=$label} }
    }
}

function Get-PkTracklistPath($Entry,[string]$Id) {
    Assert-SafePath $Entry.Path
    if (!$Entry.External) {
        if (![IO.Directory]::Exists($Entry.Path)) { throw 'Der Set-Ordner ist nicht erreichbar.' }
        return (Join-Path $Entry.Path 'plattenkoffer-tracklist.json')
    }
    if ($Id -cnotmatch '^[0-9A-F]{64}$') { throw 'Ungültiger Sammlungseintrag.' }
    Join-Path $config "tracklist-$Id.json"
}

function Get-PkSetAudioDuration($File) {
    Assert-SafePath $File.FullName
    $raw = & $probe -v error -show_entries format=duration -of 'csv=p=0' -- $File.FullName
    $seconds = 0.0
    if ($LASTEXITCODE -ne 0 -or ![double]::TryParse([string]$raw,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$seconds) -or
        $seconds -le 0 -or [double]::IsNaN($seconds) -or [double]::IsInfinity($seconds)) {
        throw "Die Dauer von $($File.Name) konnte nicht ermittelt werden."
    }
    $seconds
}

function Invoke-WebTracklist($Entry,$Message) {
    if (!$Entry -or $Entry.Type -ne 'Sets') { return }
    $path=Get-PkTracklistPath $Entry $Message.id
    Assert-SafePath $path
    $rows=@()
    if ([IO.File]::Exists($path)) {
        $saved=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path,$utf8))
        $rows=@(foreach ($row in $saved) { if ($row) { $row } })
    }
    $changed=$false
    $status=''
    switch ($Message.command) {
        'tracklist-scan' { Start-WebTransitionScan $Entry $Message; return }
        'tracklist-confirm' {
            if (@($Message.rows).Count -gt 200) { throw 'Zu viele Trackzeilen.' }
            $last=-1
            $added=@(foreach ($line in $Message.rows) {
                if ($null -ne $line.second) {
                    if ($line.second -isnot [int] -or $line.second -le $last) { throw 'Bitte aufsteigende und eindeutige Timecodes eingeben.' }
                    $last=$line.second
                }
                $title=([string]$line.title).Trim()
                if (!$title) { $title='Unbekannt' }
                $artist=([string]$line.artist).Trim()
                if (!($rows | Where-Object { $_.second -eq $line.second -and $_.artist -eq $artist -and $_.title -eq $title })) {
                    [pscustomobject]@{second=$line.second;artist=$artist;title=$title}
                }
            })
            $rows+=$added
            $changed=$added.Count -gt 0
            $status="$($added.Count) Tracklisteneinträge übernommen."
        }
        'tracklist-add' {
            if (!$transport.Enabled -or $web.PlayingId -cne $Message.id) { throw 'Spiele dieses Set zuerst im Player ab.' }
            $position=$audio.Offset + $(if ($audio.Process) { $audio.Clock.Elapsed.TotalSeconds } else { 0 })
            for ($i=0;$i -lt $audio.Index;$i++) { $position += Get-PkSetAudioDuration $audio.Tracks[$i] }
            $title=([string]$Message.title).Trim()
            if (!$title) { $title='Unbekannt' }
            $rows+= [pscustomobject]@{second=[int][Math]::Floor($position);artist=([string]$Message.artist).Trim();title=$title}
            $changed=$true
        }
        {$_ -in @('tracklist-import','tracklist-description')} {
            $source=[string]$Message.text
            if ($Message.command -eq 'tracklist-description') {
                if ($Entry.External) { throw 'Für dieses Set liegt keine gespeicherte YouTube-Beschreibung vor.' }
                $info=Join-Path $Entry.Path 'info.json'
                Assert-SafePath $info
                if (![IO.File]::Exists($info)) { throw 'Für dieses Set liegt keine gespeicherte YouTube-Beschreibung vor.' }
                $source=[string](ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($info,$utf8))).description
            }
            $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($row in $rows) { [void]$seen.Add("$($row.second)|$($row.artist)|$($row.title)") }
            $new=@(ConvertFrom-PkTracklist $source -AllowUntimed:($Message.command -eq 'tracklist-import'))
            $added=@($new | Where-Object { $seen.Add("$($_.second)|$($_.artist)|$($_.title)") })
            $rows+=$added
            $changed=$added.Count -gt 0
            $status=if ($new.Count) { "$($added.Count) Einträge ergänzt." } else { 'Keine Zeilen mit Timecodes erkannt. Beispiel: 12:34 Interpret – Titel.' }
        }
        'tracklist-time' {
            if ($Message.index -isnot [int] -or $Message.index -lt 0 -or $Message.index -ge $rows.Count) { return }
            if ($null -ne $Message.second) {
                if ($Message.second -isnot [int] -or $Message.second -lt 0) { throw 'Ungültiger Timecode.' }
                $duration=0.0
                foreach ($file in @(Get-SetAudio $Entry.Path)) { $duration+=Get-PkSetAudioDuration $file }
                if ($Message.second -ge $duration) { throw 'Dieser Timecode liegt hinter dem Ende des Sets.' }
            }
            $rows[$Message.index].second=$Message.second
            $changed=$true
            $status='Trackliste gespeichert.'
        }
        'tracklist-remove' {
            if ($Message.index -is [int] -and $Message.index -ge 0 -and $Message.index -lt $rows.Count) {
                $rows=@(for ($i=0;$i -lt $rows.Count;$i++) { if ($i -ne $Message.index) { $rows[$i] } })
                $changed=$true
            }
        }
        {$_ -in @('tracklist-jump','tracklist-preview')} {
            if ($Message.command -eq 'tracklist-preview') {
                if ($Message.second -isnot [int] -or $Message.second -lt 0) { return }
                $offset=[Math]::Max(0,$Message.second-5)
            } else {
                if ($Message.index -isnot [int] -or $Message.index -lt 0 -or $Message.index -ge $rows.Count) { return }
                if ($null -eq $rows[$Message.index].second) { return }
                $offset=[double]$rows[$Message.index].second
            }
            $tracks=@(Get-SetAudio $Entry.Path)
            for ($i=0;$i -lt $tracks.Count;$i++) {
                $duration=Get-PkSetAudioDuration $tracks[$i]
                if ($offset -lt $duration) {
                    Save-WebSetPosition
                    Start-LibraryPlayback $Entry.Path (Get-LibraryDisplayTitle $Entry) $i $offset
                    $web.PlayingId=$Message.id
                    $web.SetPlaying=$true
                    $web.PlayerState=''
                    return
                }
                $offset-=$duration
            }
            throw 'Dieser Timecode liegt hinter dem Ende des Sets.'
        }
    }
    if ($changed) {
        $rows=@($rows | Where-Object { $null -ne $_.second } | Sort-Object second)+@($rows | Where-Object { $null -eq $_.second })
        Write-AtomicText $path (ConvertTo-Json -InputObject $rows -Depth 3)
    }
    Send-WebCollectionMessage @{type='tracklist';id=$Message.id;rows=$rows;status=$status}
}

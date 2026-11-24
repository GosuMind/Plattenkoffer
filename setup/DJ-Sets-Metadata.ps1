# Public MusicBrainz metadata only. Audio files are never opened by this module.
function Invoke-PkMusicBrainz([string]$Resource) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    for ($attempt=0; $attempt -lt 3; $attempt++) {
        $wait = 1100 - ([datetime]::UtcNow - $script:MusicBrainzLastRequest).TotalMilliseconds
        if ($wait -gt 0) { Start-Sleep -Milliseconds ([int][Math]::Ceiling($wait)) }
        $script:MusicBrainzLastRequest = [datetime]::UtcNow
        try {
            return Invoke-RestMethod -Uri ("https://musicbrainz.org/ws/2/" + $Resource) -TimeoutSec 20 `
                -UserAgent 'Plattenkoffer/0.4.7 (https://github.com/GosuMind/Plattenkoffer)'
        } catch {
            Write-Verbose $_.Exception.Message
            $statusCode = [int]$_.Exception.Response.StatusCode
            if ($attempt -eq 2 -or $statusCode -notin @(429,502,503,504)) {
                throw 'MusicBrainz ist gerade nicht erreichbar oder begrenzt die Anfragen. Bitte später erneut versuchen.'
            }
            Start-Sleep -Seconds (2 * ($attempt + 1))
        }
    }
}

function Find-PkMetadata([string]$Artist, [string]$Title) {
    # Quote literal user input so Lucene operators in names stay literal.
    $artistQuery = $Artist.Replace('\','\\').Replace('"','\"')
    $titleQuery = $Title.Replace('\','\\').Replace('"','\"')
    $query = [uri]::EscapeDataString(('recording:"{0}" AND artist:"{1}"' -f $titleQuery,$artistQuery))
    $response = Invoke-PkMusicBrainz "recording?query=$query&limit=10&fmt=json"
    $seen = [Collections.Generic.HashSet[string]]::new()
    foreach ($recording in $response.recordings) {
        foreach ($release in @($recording.releases | Select-Object -First 5)) {
            if ($recording.id -notmatch '^[a-f0-9-]{36}$' -or $release.id -notmatch '^[a-f0-9-]{36}$') { continue }
            $key = "$($recording.id)/$($release.id)"
            if (!$seen.Add($key)) { continue }
            [pscustomobject]@{
                Key=$key; RecordingId=$recording.id; ReleaseId=$release.id
                Title=[string]$recording.title
                Artist=(@($recording.'artist-credit' | ForEach-Object { $_.name + $_.joinphrase }) -join '')
                Album=[string]$release.title; Date=[string]$release.date
                Country=[string]$release.country; Status=[string]$release.status
                Format=(@($release.media | ForEach-Object { $_.format } | Where-Object { $_ } | Select-Object -Unique) -join ' / ')
                Comment=[string]$recording.disambiguation
                Source="https://musicbrainz.org/release/$($release.id)"
            }
        }
    }
}

function Get-PkMetadataProposal($Candidate) {
    $release = Invoke-PkMusicBrainz "release/$($Candidate.ReleaseId)?inc=labels+genres+release-groups&fmt=json"
    # A recording comment is free text, so only use it as a version when it
    # explicitly identifies a mix/edit/version. Unknown versions remain empty.
    $version = ''
    $titles = @($Candidate.Title, $Candidate.Comment)
    foreach ($title in $titles) {
        if ($title -match '(?i)[(\[]([^\]\)]*\b(?:mix|remix|edit|version|dub|instrumental|remaster(?:ed)?)\b[^\]\)]*)[)\]]') {
            $version = $Matches[1]; break
        }
    }
    if (!$version -and $Candidate.Comment -match '(?i)\b(?:mix|remix|edit|version|dub|instrumental|remaster(?:ed)?)\b') {
        $version = $Candidate.Comment
    }
    $year = if ($release.date -match '^([1-9][0-9]{3})(?:-|$)') { $Matches[1] } else { '' }
    $genres=@($release.genres | Where-Object { $_.count -gt 0 })
    $genreSource=$Candidate.Source
    $notice=''
    if (!$genres.Count) {
        try {
            $recording=Invoke-PkMusicBrainz "recording/$($Candidate.RecordingId)?inc=genres&fmt=json"
            $genres=@($recording.genres | Where-Object { $_.count -gt 0 })
            $genreSource="https://musicbrainz.org/recording/$($Candidate.RecordingId)"
        } catch { $notice='Das Genre konnte gerade nicht abgefragt werden.' }
    }
    $groupId=[string]$release.'release-group'.id
    if (!$genres.Count -and $groupId -match '^[a-f0-9-]{36}$') {
        try {
            $group=Invoke-PkMusicBrainz "release-group/$($groupId)?inc=genres&fmt=json"
            $genres=@($group.genres | Where-Object { $_.count -gt 0 })
            $genreSource="https://musicbrainz.org/release-group/$groupId"
            if ($genres.Count) { $notice='' }
        } catch { $notice='Das Genre konnte gerade nicht abgefragt werden.' }
    }
    [pscustomobject]@{
        Album=[string]$release.title; Year=[string]$year; Version=$version
        Label=(@($release.'label-info' | ForEach-Object { $_.label.name } | Where-Object { $_ } | Select-Object -Unique) -join ' / ')
        Genre=(@($genres | Sort-Object count -Descending | ForEach-Object { $_.name } | Select-Object -Unique) -join ', ')
        GenreSource=$genreSource; Notice=$notice
    }
}

function Send-PkMetadataState([string]$Status, [switch]$Busy) {
    $job = $web.Metadata
    Send-WebCollectionMessage @{type='metadata-status';id=$job.Id;status=$Status;busy=[bool]$Busy}
}

function Start-PkMetadataRequest([string]$Operation, $Candidate, [string]$Artist, [string]$Title) {
    $job = $web.Metadata
    if ($job.Worker) { Send-PkMetadataState 'Die laufende Suche wird noch abgeschlossen.' -Busy; return }
    if ($Operation -eq 'search') { $job.Candidates=@{}; $job.Proposals=@{} }
    $job.Operation=$Operation
    $job.Key=if ($Candidate) { $Candidate.Key } else { '' }
    $job.Worker=[PowerShell]::Create()
    try {
        [void]$job.Worker.AddScript({
            param($Module,$Operation,$Candidate,$Artist,$Title,$LastRequest)
            $ErrorActionPreference='Stop'
            . $Module
            $script:MusicBrainzLastRequest=$LastRequest
            if ($Operation -eq 'search') { Find-PkMetadata $Artist $Title }
            else { Get-PkMetadataProposal $Candidate }
        }.ToString()).AddArgument((Join-Path $PSScriptRoot 'DJ-Sets-Metadata.ps1')).AddArgument($Operation).AddArgument($Candidate).AddArgument($Artist).AddArgument($Title).AddArgument($job.LastRequest)
        $job.Handle=$job.Worker.BeginInvoke()
        Send-PkMetadataState 'MusicBrainz wird abgefragt …' -Busy
    } catch {
        $job.Worker.Dispose(); $job.Worker=$null
        Send-PkMetadataState $_.Exception.Message
    }
}

function Complete-WebMetadata {
    $job = $web.Metadata
    if (!$job.Worker -or !$job.Handle.IsCompleted) { return }
    try {
        $results = @($job.Worker.EndInvoke($job.Handle))
        if ($job.Worker.Streams.Error.Count) { throw $job.Worker.Streams.Error[0] }
        if ($job.Operation -eq 'search') {
            foreach ($candidate in $results) { $job.Candidates[$candidate.Key]=$candidate }
            Send-WebCollectionMessage @{type='metadata-results';id=$job.Id;candidates=$results}
            $status = if ($results.Count) { 'Wähle die passende Veröffentlichung für die Vorschau.' } else { 'Keine Veröffentlichung gefunden. Prüfe Künstler und Titel oder versuche eine andere Schreibweise.' }
        } else {
            if (!$results.Count) { throw 'Für diese Veröffentlichung sind keine Angaben verfügbar.' }
            $job.Proposals[$job.Key]=$results[0]
            Send-WebCollectionMessage @{type='metadata-proposal';id=$job.Id;key=$job.Key;values=$results[0];source=$job.Candidates[$job.Key].Source}
            $status=('Prüfe die Angaben. Markiere die Felder, die du übernehmen möchtest. '+$results[0].Notice).Trim()
        }
        Send-PkMetadataState $status
    } catch { Send-PkMetadataState ($_.Exception.GetBaseException().Message) }
    finally {
        $job.Worker.Dispose(); $job.Worker=$null
        # Enforce spacing across separate runspaces, including failed requests.
        $job.LastRequest=[datetime]::UtcNow
    }
}

function Invoke-WebMetadata($Entry, $Message) {
    $job=$web.Metadata
    if (!$Entry -or $Entry.Type -ne 'Tracks') { return }
    if ($Message.command -eq 'metadata-open') {
        if ($job.Worker) {
            Send-WebCollectionMessage @{type='metadata-status';id=$Message.id;status='Eine andere Metadatensuche läuft noch. Bitte gleich erneut öffnen.';busy=$false}
            return
        }
        $job.Id=$Message.id; $job.Candidates=@{}; $job.Proposals=@{}
        Send-WebCollectionMessage @{type='metadata-open';id=$Message.id;artist=[string]$Entry.Artist;title=[string]$Entry.Title}
        return
    }
    if ($job.Id -cne $Message.id) { return }
    try {
        switch ($Message.command) {
            'metadata-search' {
                if ($Message.artist -isnot [string] -or $Message.title -isnot [string] -or
                    !$Message.artist.Trim() -or !$Message.title.Trim() -or $Message.artist.Length -gt 300 -or $Message.title.Length -gt 300) {
                    throw 'Bitte Künstler und Tracktitel eingeben (jeweils höchstens 300 Zeichen).'
                }
                Start-PkMetadataRequest 'search' $null $Message.artist.Trim() $Message.title.Trim()
            }
            'metadata-select' {
                if ($Message.key -isnot [string] -or !$job.Candidates.ContainsKey($Message.key)) { throw 'Bitte erneut suchen und einen Treffer auswählen.' }
                if ($job.Proposals.ContainsKey($Message.key)) {
                    Send-WebCollectionMessage @{type='metadata-proposal';id=$job.Id;key=$Message.key;values=$job.Proposals[$Message.key];source=$job.Candidates[$Message.key].Source}
                } else { Start-PkMetadataRequest 'proposal' $job.Candidates[$Message.key] '' '' }
            }
            'metadata-source' {
                if ($Message.key -is [string] -and $job.Candidates.ContainsKey($Message.key)) {
                    $url=$job.Candidates[$Message.key].Source
                    if ($Message.field -eq 'Genre' -and $job.Proposals.ContainsKey($Message.key)) { $url=$job.Proposals[$Message.key].GenreSource }
                    Start-Process $url
                }
            }
            'metadata-apply' {
                if ($job.Worker -or $Message.key -isnot [string] -or !$job.Proposals.ContainsKey($Message.key)) { throw 'Bitte zuerst die Vorschau laden.' }
                $values=[ordered]@{Type=$Entry.Type}
                $sources=[ordered]@{}
                foreach ($property in $Entry.MetadataSources.PSObject.Properties) { $sources[$property.Name]=$property.Value }
                foreach ($field in @($Message.fields)) {
                    if ($field -notin @('Album','Year','Label','Version','Genre')) { throw 'Unbekanntes Metadatenfeld.' }
                    $value=[string]$job.Proposals[$Message.key].$field
                    if (!$value) { continue }
                    $values[$field]=$value
                    $sources[$field]=[pscustomobject]@{Provider='MusicBrainz';Url=$job.Candidates[$Message.key].Source;RecordingId=$job.Candidates[$Message.key].RecordingId;Value=$value}
                    if ($field -eq 'Genre') {
                        $sources[$field].Url=$job.Proposals[$Message.key].GenreSource
                        $sources[$field] | Add-Member NoteProperty License 'CC BY-NC-SA 3.0'
                    }
                }
                if ($values.Count -eq 1) { throw 'Bitte mindestens ein verfügbares Feld markieren.' }
                $values.MetadataSources=[pscustomobject]$sources
                Save-WebEntry $Entry ([pscustomobject]$values)
                Send-WebCollectionMessage @{type='metadata-saved';id=$job.Id}
            }
        }
    } catch { Send-PkMetadataState $_.Exception.Message }
}

# Library Health 1.0. Local, dependency-free services shared by the GUI and tests.
function Get-PkHealthFields {
    [ordered]@{Artist='artist';Title='title';Album='album';AlbumArtist='album_artist';Version='version';Label='publisher';Genre='genre';Year='date';Date='release_date';Series='series';Event='event';Location='location';TrackNumber='track';SourceUrl='purl';VideoId='video_id';ISRC='isrc'}
}
. (Join-Path $PSScriptRoot 'DJ-Sets-HealthSemantic.ps1')
. (Join-Path $PSScriptRoot 'DJ-Sets-HealthJson.ps1')
. (Join-Path $PSScriptRoot 'DJ-Sets-HealthReports.ps1')
. (Join-Path $PSScriptRoot 'DJ-Sets-HealthCover.ps1')
. (Join-Path $PSScriptRoot 'DJ-Sets-HealthVdj.ps1')
. (Join-Path $PSScriptRoot 'DJ-Sets-HealthQuarantine.ps1')

function Get-PkHealthTagKeys([string]$Field) {
    switch($Field){
        AlbumArtist {@('album_artist','albumartist')}
        Label {@('publisher','label','organization')}
        Year {@('date','year')}
        Version {@('version','remix')}
        SourceUrl {@('purl','source')}
        TrackNumber {@('track','tracknumber')}
        default {@((Get-PkHealthFields)[$Field])}
    }
}

function ConvertTo-PkHealthArgument([string]$Value) {
    # CommandLineToArgvW escaping; never invoke a shell or interpolate a command.
    '"'+([regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1'))+'"'
}

function Invoke-PkHealthTool([string]$Tool,[string[]]$Arguments,$Control,[int]$TimeoutSeconds=180) {
    Assert-SafePath $Tool
    if (![IO.File]::Exists($Tool)) { throw "Werkzeug fehlt: $Tool" }
    if ($Control -and $Control.Cancel) { throw [OperationCanceledException]::new('Vorgang abgebrochen.') }
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$Tool; $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $start.StandardOutputEncoding=[Text.UTF8Encoding]::new($false,$true)
    $start.StandardErrorEncoding=[Text.UTF8Encoding]::new($false,$true)
    # Health processing is local. Do not let media open remote URLs implicitly.
    $localArguments=@('-protocol_whitelist','file,pipe')+$Arguments
    if($start.PSObject.Properties['ArgumentList']){foreach($argument in $localArguments){[void]$start.ArgumentList.Add([string]$argument)}}
    else{$start.Arguments=($localArguments | ForEach-Object { ConvertTo-PkHealthArgument $_ }) -join ' '}
    $process=[Diagnostics.Process]::new();$process.StartInfo=$start
    try {
        [void]$process.Start();$output=$process.StandardOutput.ReadToEndAsync();$errors=$process.StandardError.ReadToEndAsync()
        $clock=[Diagnostics.Stopwatch]::StartNew()
        while (!$process.WaitForExit(100)) {
            if (($Control -and $Control.Cancel) -or $clock.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
                $process.Kill();$process.WaitForExit()
                if ($Control -and $Control.Cancel) { throw [OperationCanceledException]::new('Vorgang abgebrochen.') }
                throw 'Zeitlimit des Audiowerkzeugs überschritten.'
            }
        }
        try{$text=$output.GetAwaiter().GetResult();$errorText=$errors.GetAwaiter().GetResult()}
        catch{throw [IO.InvalidDataException]::new('TOOL_ENCODING_ERROR: Werkzeugausgabe konnte nicht strikt als UTF-8 gelesen werden. Musikdatei nicht als beschädigt bewertet.', $_.Exception)}
        if ($process.ExitCode -ne 0) { throw "Audiowerkzeug meldet Fehler $($process.ExitCode): $($errorText.Substring(0,[Math]::Min(1200,$errorText.Length)))" }
        $text
    } finally { $process.Dispose() }
}

function Write-PkHealthJson([string]$Path,$Value) {
    Assert-SafePath $Path
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $temp="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temp,(ConvertTo-Json -InputObject $Value -Depth 60),[Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp,$Path,[NullString]::Value) }
        else { [IO.File]::Move($temp,$Path) }
    } finally { [IO.File]::Delete($temp) }
}

function Protect-PkHealthAuditValue($Value) {
    if($null -eq $Value){return $null}
    if($Value -is [string]){
        return [regex]::Replace($Value,'(?i)([?&](?:access_token|refresh_token|token|api[_-]?key|password|secret|signature|authorization)=)[^&#\s]+','$1[REDACTED]')
    }
    if($Value -is [Collections.IDictionary]){
        $result=@{};foreach($key in $Value.Keys){if($key -match '(?i)^(?:password|token|access_token|refresh_token|api[_-]?key|secret|authorization)$'){$result[$key]='[REDACTED]'}else{$result[$key]=Protect-PkHealthAuditValue $Value[$key]}};return $result
    }
    if($Value -is [array]){return ,@($Value|ForEach-Object{Protect-PkHealthAuditValue $_})}
    if($Value -is [ValueType]){return $Value}
    $result=@{};foreach($p in $Value.PSObject.Properties){if($p.Name -match '(?i)^(?:password|token|access_token|refresh_token|api[_-]?key|secret|authorization)$'){$result[$p.Name]='[REDACTED]'}else{$result[$p.Name]=Protect-PkHealthAuditValue $p.Value}};$result
}

function Write-PkHealthAudit([string]$Path,$Value) { Write-PkHealthJson $Path (Protect-PkHealthAuditValue $Value) }

function Read-PkHealthJson([string]$Path,[long]$MaxBytes=16MB) {
    Assert-SafePath $Path
    if ([IO.FileInfo]::new($Path).Length -gt $MaxBytes) { throw 'JSON-Datei ist zu groß.' }
    $value=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path,[Text.UTF8Encoding]::new($false,$true)))
    if (!$value -or $value -is [array] -or $value -is [string] -or $value -is [ValueType]) { throw 'JSON-Objekt erwartet.' }
    $value
}

function Get-PkHealthFileHash([string]$Path) {
    Assert-SafePath $Path
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-PkHealthBackupUsage($Options) {
    $bytes=0L
    if(![IO.Directory]::Exists($Options.BackupRoot)){return $bytes}
    $stack=[Collections.Generic.Stack[string]]::new();$stack.Push($Options.BackupRoot)
    while($stack.Count){
        $path=$stack.Pop();Assert-SafePath $path
        foreach($item in Get-ChildItem -LiteralPath $path -Force){
            Assert-SafePath $item.FullName
            if($item.PSIsContainer){$stack.Push($item.FullName)}else{$bytes+=$item.Length}
        }
    }
    $bytes
}

function Get-PkHealthId([string]$Path) {
    $hash=[Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Path).ToUpperInvariant()))).Replace('-','') }
    finally { $hash.Dispose() }
}

function Assert-PkHealthScope([string]$Path,[string]$Root) {
    $full=[IO.Path]::GetFullPath($Path);$base=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')+'\'
    if (!$full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) { throw 'Pfad liegt außerhalb der freigegebenen Bibliothek.' }
    Assert-SafePath $full
    if ($full.IndexOf(':',2) -ge 0) { throw 'Alternative Datenströme sind nicht erlaubt.' }
    $full
}

function Assert-PkHealthOptions($Options,[switch]$Writing) {
    Assert-SafePath $Options.Root
    if (![IO.Directory]::Exists($Options.Root)) { throw 'Bibliotheksordner ist nicht erreichbar.' }
    foreach ($tool in @($Options.Probe,$Options.FFmpeg)) {
        Assert-SafePath $tool
        if (![IO.File]::Exists($tool)) { throw "Werkzeug fehlt: $tool" }
    }
    foreach ($path in @($Options.Storage,$Options.BackupRoot,$Options.QuarantineRoot,$Options.CoverRoot)|Where-Object {$_}) {
        Assert-SafePath $path
        $full=[IO.Path]::GetFullPath($path).TrimEnd('\')+'\'
        $root=[IO.Path]::GetFullPath($Options.Root).TrimEnd('\')+'\'
        if ($full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or $root.StartsWith($full,[StringComparison]::OrdinalIgnoreCase)) {
                throw 'Berichte, Backups, Quarantäne und Cover-Arbeitsordner müssen getrennt von der Musikbibliothek liegen.'
        }
    }
}

function Get-PkHealthProbe([string]$Path,$Options,$Control) {
    Assert-SafePath $Path
    $json=Invoke-PkHealthTool $Options.Probe @('-v','error','-show_format','-show_streams','-show_data_hash','sha256','-of','json','--',$Path) $Control
    $result=ConvertFrom-Json -InputObject $json
    if (!@($result.streams | Where-Object codec_type -eq 'audio').Count) { throw 'Keine Audiospur gefunden.' }
    $result
}

function Get-PkHealthAudioHashes([string]$Path,$Options,$Control) {
    # One hash for every encoded audio stream, not the container or decoded PCM.
    $result=Invoke-PkHealthTool $Options.FFmpeg @('-v','error','-nostdin','-i',$Path,'-map','0:a','-c','copy','-f','streamhash','-hash','sha256','-') $Control 3600
    $hashes=@($result -split '\r?\n' | Where-Object { $_ -match '^\d+,a,SHA256=[a-fA-F0-9]{64}$' })
    if (!$hashes.Count) { throw 'Audio-Prüfsumme konnte nicht ermittelt werden.' }
    ,$hashes
}

function Get-PkHealthTags($Probe) {
    $all=@{}
    foreach ($source in @($Probe.format)+@($Probe.streams | Where-Object codec_type -eq 'audio')) {
        foreach ($property in $source.tags.PSObject.Properties) {
            $key=$property.Name.ToLowerInvariant();$value=[string]$property.Value
            if ($value.Trim()) { $all[$key]=$value.Trim() }
        }
    }
    $values=@{}
    foreach ($field in (Get-PkHealthFields).Keys) {
        $keys=@(Get-PkHealthTagKeys $field)
        $values[$field]=''
        foreach ($key in $keys) { if ($all[$key]) { $values[$field]=$all[$key];break } }
    }
    $values
}

function Get-PkHealthFolder([string]$Path,[string]$Root) {
    $directory=[IO.DirectoryInfo]::new([IO.Path]::GetDirectoryName($Path))
    if ($directory.Parent -and $directory.Parent.Name -in @('Tracks','Sets') -and $directory.Parent.Parent) {
        return @{Artist=$directory.Parent.Parent.Name;Title=$directory.Name;Kind=$(if($directory.Parent.Name -eq 'Sets'){'Set'}else{'Track'});Valid=$true}
    }
    @{Artist='';Title='';Kind='Unknown';Valid=$false}
}

function Get-PkHealthSidecars([string]$Path) {
    $folder=[IO.Path]::GetDirectoryName($Path)
    @('plattenkoffer.json','info.json','plattenkoffer-cover.jpg','cover.jpg','cover.jpeg','cover.png','cover.webp','cover.avif') | ForEach-Object {
        $candidate=Join-Path $folder $_
        if ([IO.File]::Exists($candidate)) { Assert-SafePath $candidate; Get-Item -LiteralPath $candidate }
    }
}

function Get-PkHealthStamp([string]$Path) {
    Assert-SafePath $Path
    $file=Get-Item -LiteralPath $Path
    $stamp="$($file.Length):$($file.LastWriteTimeUtc.Ticks)"
    foreach ($item in @(Get-PkHealthSidecars $Path)) { $stamp+="|$($item.Name):$($item.Length):$($item.LastWriteTimeUtc.Ticks)" }
    $stamp
}

function Resolve-PkHealthMetadata($Tags,$Pk,$Info,$Folder,$Options) {
    $proposals=@{};$evidence=@{};$confidence=@{};$conflicts=[Collections.Generic.List[string]]::new()
    $fields=Get-PkHealthFields
    $videoArtist='';$videoTitle=''
    if ($Folder.Kind -eq 'Track' -and $Info.title -match '^(.+?)\s+[-–—]\s+(.+)$') {
        $videoArtist=$Matches[1].Trim();$videoTitle=$Matches[2].Trim()
        $suffixes=if ($Options.VideoSuffixes) { @($Options.VideoSuffixes) } else { @('Official Video','Official Audio','Music Video','Lyrics Video','HD','HQ','4K') }
        foreach ($suffix in $suffixes) {
            $videoTitle=($videoTitle -replace ('(?i)\s*[\[(]\s*'+[regex]::Escape($suffix)+'\s*[\])]\s*$'),'').Trim()
        }
    }
    foreach ($field in $fields.Keys) {
        $candidates=[Collections.Generic.List[object]]::new()
        $confirmed=$field -in @($Pk.HealthConfirmedFields)
        if ($confirmed -and $Pk.$field -is [string] -and $Pk.$field.Trim()) { $candidates.Add(@{Source='Plattenkoffer · bestätigt';Value=$Pk.$field;Confidence='VERIFIED'}) }
        if ($Tags[$field]) { $candidates.Add(@{Source='Audio-Tags';Value=$Tags[$field];Confidence='HIGH_CONFIDENCE'}) }
        if (!$confirmed -and $Pk.$field -is [string] -and $Pk.$field.Trim()) { $candidates.Add(@{Source='Plattenkoffer';Value=$Pk.$field;Confidence='HIGH_CONFIDENCE'}) }
        if ($field -in @('Artist','Title') -and $Folder.Valid) { $candidates.Add(@{Source='Ordnerstruktur';Value=$Folder[$field];Confidence='MEDIUM_CONFIDENCE'}) }
        $infoKey=switch ($field) { Artist {'artist'} Title {'track'} Year {'release_year'} Label {'publisher'} SourceUrl {'webpage_url'} VideoId {'id'} default {$fields[$field]} }
        if ($Info.$infoKey -and $Info.$infoKey -isnot [array]) { $candidates.Add(@{Source='info.json';Value=[string]$Info.$infoKey;Confidence='MEDIUM_CONFIDENCE'}) }
        if ($field -eq 'Artist' -and $videoArtist) { $candidates.Add(@{Source='Videotitel';Value=$videoArtist;Confidence='LOW_CONFIDENCE'}) }
        if ($field -eq 'Title' -and $videoTitle) { $candidates.Add(@{Source='Videotitel';Value=$videoTitle;Confidence='LOW_CONFIDENCE'}) }
        $evidence[$field]=@($candidates.ToArray())
        $values=@($candidates | ForEach-Object { $_.Value.Trim().ToLowerInvariant() } | Select-Object -Unique)
        $different=$false
        if($candidates.Count -gt 1){foreach($candidate in $candidates){if(!(Test-PkHealthFieldEquivalent $field $candidates[0].Value $candidate.Value $Pk)){$different=$true}}}
        if ($different) { $conflicts.Add($field) }
        $confidence[$field]=if($different){'CONFLICT'}elseif($candidates.Count){$candidates[0].Confidence}else{'LOW_CONFIDENCE'}
        $choice=if ($candidates.Count) { $candidates[0].Value } else { '' }
        # Keep the existing full audio title when JSON stores its remix separately.
        if($field -eq 'Title' -and $Tags.Title -and (Test-PkHealthTitleVariant $Tags.Title $Pk)){$choice=$Tags.Title}
        $proposals[$field]=[string]$choice
    }
    @{Values=$proposals;Evidence=$evidence;Confidence=$confidence;Conflicts=@($conflicts.ToArray())}
}

function Get-PkHealthRecord([string]$Path,$Options,$Control) {
    $null=Assert-PkHealthScope $Path $Options.Root
    $file=Get-Item -LiteralPath $Path
    $folder=Get-PkHealthFolder $Path $Options.Root
    $codes=[Collections.Generic.List[string]]::new();$notes=[Collections.Generic.List[string]]::new()
    $record=@{Id=(Get-PkHealthId $Path);Path=$Path;Kind=$folder.Kind;Size=$file.Length;Stamp=(Get-PkHealthStamp $Path);ResolverSignature=('2|'+(@($Options.VideoSuffixes) -join '|'));ScannedAt=[datetime]::UtcNow.ToString('o');Codes=@();Notes=@();Tags=@{};Pk=$null;Info=$null;Covers=@();EmbeddedCover=$false;Integrity='UNTESTED';Repairable=$false;FileHash='';AudioHashes=@()}
    if (!$folder.Valid) { $codes.Add('INVALID_PATH') }
    if ($file.BaseName -match '^(audio|source|download)(\.\d+)?$') { $codes.Add('GENERIC_FILENAME') }
    foreach ($item in @(@{Name='plattenkoffer.json';Key='Pk'},@{Name='info.json';Key='Info'})) {
        $jsonPath=Join-Path $file.DirectoryName $item.Name
        if (![IO.File]::Exists($jsonPath)) { if ($item.Key -eq 'Pk') { $codes.Add('MISSING_JSON') };continue }
        try {
            $json=Read-PkHealthJson $jsonPath
            if ($item.Key -eq 'Pk') {
                foreach ($field in (Get-PkHealthFields).Keys) { if ($null -ne $json.$field -and $json.$field -isnot [string]) { throw "Ungültiges Feld: $field" } }
                if ($json.MetadataSources -and ($json.MetadataSources -is [string] -or $json.MetadataSources -is [array])) { throw 'Ungültige Metadatenquellen.' }
                if ($json.HealthSchemaVersion -and $json.HealthSchemaVersion -ne 1) { throw 'Nicht unterstützte Health-Schemaversion.' }
            }
            # Reports contain only supported metadata, not arbitrary source descriptions,
            # private custom JSON fields or credentials. Repair rereads the complete JSON.
            $public=@{}
            if($item.Key -eq 'Pk'){
                $part=@($json.Parts|Where-Object {$_.FileName -ceq $file.Name})|Select-Object -First 1
                foreach($field in (Get-PkHealthFields).Keys){if($json.$field){$public[$field]=[string]$json.$field}}
                if($part){foreach($field in (Get-PkHealthFields).Keys){if($null -ne $part.Tags.$field){$public[$field]=[string]$part.Tags.$field}}}
                $public.HealthConfirmedFields=@(foreach($field in (Get-PkHealthFields).Keys){$proof=if($part.MetadataSources.$field){$part.MetadataSources.$field}else{$json.MetadataSources.$field};if($proof.ConfirmedAt -or $proof.Provider -match '^(Manuell|Manual)$'){$field}})
            }else{
                foreach($field in @('title','track','artist','album','album_artist','release_year','publisher','genre','webpage_url','id','isrc','version','series','event','location','tracknumber','release_date')){if($json.$field -is [string] -or $json.$field -is [ValueType]){$public[$field]=$json.$field}}
            }
            $record[$item.Key]=[pscustomobject]$public
        } catch { if ('INVALID_JSON' -notin $codes) { $codes.Add('INVALID_JSON') };$notes.Add("$($item.Name): $($_.Exception.Message)") }
    }
    try {
        $probeResult=Get-PkHealthProbe $Path $Options $Control
        $record.Probe=$probeResult;$record.Tags=Get-PkHealthTags $probeResult
        $streams=@($probeResult.streams | Where-Object codec_type -eq 'audio');$stream=$streams[0]
        $record.Codec=[string]$stream.codec_name;$record.Container=[string]$probeResult.format.format_name
        $record.Duration=[double]::Parse([string]$probeResult.format.duration,[Globalization.CultureInfo]::InvariantCulture)
        $record.SampleRate=[string]$stream.sample_rate;$record.Channels=[int]$stream.channels
        $record.Bitrate=[string]$(if($stream.bit_rate){$stream.bit_rate}else{$probeResult.format.bit_rate})
        $record.Lossless=($stream.codec_name -match '^(flac|alac|pcm_|wavpack|ape)')
        foreach ($field in @('Artist','Title')) { if (!$record.Tags[$field]) { $codes.Add("MISSING_$($field.ToUpperInvariant())") } }
        foreach ($field in $record.Tags.Keys) { if ($record.Tags[$field] -match '[\x00-\x08\x0B\x0C\x0E-\x1F]' -or $record.Tags[$field].Length -gt 2000) { if ('INVALID_TAG' -notin $codes) {$codes.Add('INVALID_TAG')} } }
        $record.EmbeddedCover=@($probeResult.streams | Where-Object { $_.disposition.attached_pic -eq 1 }).Count -gt 0
        if (!$record.EmbeddedCover) { $codes.Add('EMBEDDED_COVER_MISSING') }
        # Only separately tested container/codec combinations are enabled for writing.
        $record.Repairable=($streams.Count -eq 1 -and (($file.Extension -ieq '.opus' -and $stream.codec_name -eq 'opus' -and $record.Container -match 'ogg') -or ($file.Extension -ieq '.m4a' -and $stream.codec_name -eq 'aac' -and $record.Container -match 'mov|mp4')))
        if (!$record.Repairable) { $codes.Add('UNSUPPORTED_FORMAT') }
        $record.FileHash=Get-PkHealthFileHash $Path
        $record.AudioHashes=Get-PkHealthAudioHashes $Path $Options $Control
        $record.Integrity='PACKETS_CHECKED'
        if ($Options.Deep) {
            $null=Invoke-PkHealthTool $Options.FFmpeg @('-v','error','-xerror','-err_detect','explode','-nostdin','-i',$Path,'-map','0:a','-f','null','-') $Control 14400
            $record.Integrity='DECODE_CHECKED'
        }
        if ($record.Duration -le 0 -or !$stream.sample_rate -or !$stream.channels) { throw 'Ungültige Audioparameter.' }
    } catch {
        if ($Control -and $Control.Cancel) { throw }
        if($_.Exception.Message -match 'TOOL_ENCODING_ERROR'){$codes.Add('TOOL_ENCODING_ERROR');$record.Integrity='UNTESTED'}else{$codes.Add('AUDIO_ERROR');$record.Integrity='FAILED'}
        $record.Repairable=$false;$notes.Add($_.Exception.Message)
    }
    $covers=@(foreach ($cover in @(Get-PkHealthSidecars $Path | Where-Object Extension -in @('.jpg','.jpeg','.png','.webp','.avif'))) {
        $image=@{Path=$cover.FullName;Size=$cover.Length;Valid=$false;Width=0;Height=0}
        try {
            if ($cover.Length -gt 20MB) { throw 'Cover ist größer als 20 MB.' }
            $raw=Invoke-PkHealthTool $Options.Probe @('-v','error','-show_entries','stream=width,height','-of','json','--',$cover.FullName) $Control
            $picture=(ConvertFrom-Json $raw).streams | Select-Object -First 1
            if (!$picture.width -or !$picture.height -or [long]$picture.width*$picture.height -gt 40000000) { throw 'Ungültige Coverabmessungen.' }
            $image.Valid=$true;$image.Width=$picture.width;$image.Height=$picture.height
        } catch { if ($Control -and $Control.Cancel) {throw};if($_.Exception.Message -match 'TOOL_ENCODING_ERROR'){if('TOOL_ENCODING_ERROR' -notin $codes){$codes.Add('TOOL_ENCODING_ERROR')}}elseif ('INVALID_COVER' -notin $codes) {$codes.Add('INVALID_COVER')} }
        $image
    })
    $record.Covers=$covers
    if (!$covers.Count -and !$record.EmbeddedCover) { $codes.Add('MISSING_COVER') }
    $record.Resolved=Resolve-PkHealthMetadata $record.Tags $record.Pk $record.Info $folder $Options
    foreach ($field in @('Artist','Title','Album','Year','Genre','Label','Version')) {
        if ($record.Pk.$field -and $record.Tags[$field] -and !(Test-PkHealthFieldEquivalent $field $record.Pk.$field $record.Tags[$field] $record.Pk)) { if ('JSON_MISMATCH' -notin $codes) {$codes.Add('JSON_MISMATCH')} }
    }
    $record.MetadataStatus=Get-PkHealthMetadataStatus $record.Tags $record.Pk;$codes.Add($record.MetadataStatus)
    if('MISSING_ARTIST' -in $codes -or 'MISSING_TITLE' -in $codes){$codes.Add('AUDIO_METADATA_MISSING')}
    if('INVALID_TAG' -in $codes){$codes.Add('AUDIO_METADATA_INVALID')}
    if($record.MetadataStatus -eq 'METADATA_CONFLICT'){$codes.Add('AUDIO_METADATA_CONFLICT')}
    foreach($field in @('Artist','Title','Album','Version','Genre','Label')){if(Test-PkHealthSuspiciousUnicode ([string]$record.Tags[$field])){if('UNICODE_REVIEW_REQUIRED' -notin $codes){$codes.Add('UNICODE_REVIEW_REQUIRED');$notes.Add('Verdächtige Zeichenfolge: Quellen prüfen. Keine automatische Zeichenersetzung.')}}}
    if ($record.Resolved.Conflicts.Count) { $codes.Add('TAG_MISMATCH');$codes.Add('MANUAL_REVIEW') }
    $record.Codes=@($codes.ToArray() | Select-Object -Unique);$record.Notes=@($notes.ToArray())
    $record
}

function Get-PkHealthFiles($Options,$Control,$Warnings) {
    $stack=[Collections.Generic.Stack[string]]::new();$stack.Push($Options.Root)
    while ($stack.Count) {
        if ($Control -and $Control.Cancel) { return }
        $directory=$stack.Pop()
        try {
            Assert-SafePath $directory
            foreach ($item in (Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { $Warnings.Add("Verknüpfung übersprungen: $($item.FullName)");continue }
                if ($item.PSIsContainer) {
                    if ($item.Name -match '^(\.dj-set-downloads|\.pk-health.*|.*backup.*|.*repair.*|test-.*|temp|tmp|\$RECYCLE\.BIN|System Volume Information)$') { continue }
                    $stack.Push($item.FullName)
                } elseif ($item.Extension -in @('.opus','.m4a','.webm','.mp3','.flac','.ogg','.wav','.aac','.aiff','.alac')) {
                    if ($item.BaseName -match '(?i)(?:^audio_repaired$|\.tmp(?:\.|$)|\.part$|\.pk-health-|\.bak$|^source$)') { continue }
                    $item.FullName
                }
            }
        } catch { $Warnings.Add("Nicht gelesen: $directory. $($_.Exception.Message)") }
    }
}

function Update-PkHealthDuplicates($Records) {
    foreach ($record in $Records) { $record.Codes=@($record.Codes | Where-Object {$_ -notin @('DUPLICATE_AUDIO','POSSIBLE_DUPLICATE','HEALTHY')});$record.DuplicateOf=@() }
    foreach ($group in @($Records | Where-Object { $_.FileHash } | Group-Object { $_.FileHash } | Where-Object Count -gt 1)+@($Records | Where-Object { $_.AudioHashes.Count } | Group-Object { $_.AudioHashes -join '|' } | Where-Object Count -gt 1)) {
        foreach ($record in $group.Group) {
            if ('DUPLICATE_AUDIO' -notin $record.Codes) { $record.Codes+= 'DUPLICATE_AUDIO' }
            $record.DuplicateOf=@($group.Group | Where-Object { $_.Path -ne $record.Path } | ForEach-Object { $_.Path })
        }
    }
    foreach ($group in @($Records | Where-Object { $_.Tags.Artist -and $_.Tags.Title } | Group-Object { "$($_.Tags.Artist)|$($_.Tags.Title)|$($_.Tags.Version)|$($_.Tags.Album)" } | Where-Object Count -gt 1)) {
        foreach ($record in $group.Group) {
            if (@($group.Group | Where-Object { $_.Path -ne $record.Path -and [Math]::Abs($_.Duration-$record.Duration) -le 2 }).Count -and 'DUPLICATE_AUDIO' -notin $record.Codes) { $record.Codes+='POSSIBLE_DUPLICATE' }
        }
    }
    foreach ($record in $Records) {
        $problems=@(Get-PkHealthIssueCodes $record.Codes)
        if (!$problems.Count -and $record.Integrity -eq 'DECODE_CHECKED') { $record.Codes+='HEALTHY' }
    }
}

function Invoke-PkHealthScan($Options,$Control,[switch]$Incremental) {
    Assert-PkHealthOptions $Options
    $reportPath=Join-Path $Options.Storage 'scan.json'
    $checkpointRoot=Join-Path $Options.Storage 'scan-checkpoints'
    $old=@{}
    if ($Incremental -and [IO.File]::Exists($reportPath)) {
        try { $saved=Read-PkHealthJson $reportPath 256MB; if ($saved.Root -ieq $Options.Root) { foreach ($r in $saved.Records) { $old[$r.Path]=$r } } } catch { }
    }
    $warnings=[Collections.Generic.List[string]]::new()
    $files=@(Get-PkHealthFiles $Options $Control $warnings)
    $records=[Collections.Generic.List[object]]::new()
    $report=@{SchemaVersion=1;Id=[guid]::NewGuid().ToString('N');Root=$Options.Root;StartedAt=[datetime]::UtcNow.ToString('o');EndedAt='';State='SCANNING';Deep=[bool]$Options.Deep;Total=$files.Count;Records=@();Warnings=@()}
    $index=0
    foreach ($file in $files) {
        if ($Control -and $Control.Cancel) { break }
        if ($Control) { $Control.Current=$file;$Control.Done=$index;$Control.Total=$files.Count }
        try {
            $cached=$old[$file]
            $checkpoint=Join-Path $checkpointRoot ((Get-PkHealthId $file)+'.json')
            if($Incremental -and [IO.File]::Exists($checkpoint)){
                try{$savedRecord=Read-PkHealthJson $checkpoint;if($savedRecord.Path -ieq $file){$cached=$savedRecord}}catch{}
            }
            if ($cached -and $cached.ResolverSignature -ceq ('2|'+(@($Options.VideoSuffixes) -join '|')) -and $cached.Stamp -ceq (Get-PkHealthStamp $file) -and (!$Options.Deep -or $cached.Integrity -eq 'DECODE_CHECKED') -and $cached.Integrity -ne 'FAILED') {
                # Normalize deserialized objects so updates use the same mutable representation.
                $record=@{};foreach($p in $cached.PSObject.Properties){$record[$p.Name]=$p.Value}
            } else { $record=Get-PkHealthRecord $file $Options $Control }
            $records.Add($record)
            Write-PkHealthAudit $checkpoint $record
        } catch {
            if ($Control -and $Control.Cancel) { break }
            $records.Add(@{Id=(Get-PkHealthId $file);Path=$file;Kind='Unknown';Size=0;Stamp='';Codes=@('AUDIO_ERROR');Notes=@($_.Exception.Message);Integrity='FAILED';Repairable=$false;Tags=@{};FileHash='';AudioHashes=@();Covers=@()})
        }
        $index++;$report.Records=@($records.ToArray());$report.Warnings=@($warnings.ToArray())
        # Individual checkpoints survive discovery cancellation and partial report replacement.
        if($index % 20 -eq 0 -or $index -eq $files.Count){Write-PkHealthAudit $reportPath $report}
    }
    $report.Records=@($records.ToArray());$report.Warnings=@($warnings.ToArray())
    foreach($record in $report.Records){
        try{
            if($record.Stamp -and $record.Stamp -cne (Get-PkHealthStamp $record.Path)){
                $record.Codes=@($record.Codes)+@('MANUAL_REVIEW');$record.Integrity='STALE';$record.Repairable=$false
                $warnings.Add("Während des Scans geändert, erneut prüfen: $($record.Path)")
            }
        }catch{$warnings.Add("Nach dem Scan nicht mehr erreichbar: $($record.Path)");$record.Integrity='STALE';$record.Repairable=$false}
    }
    $report.Warnings=@($warnings.ToArray())
    Update-PkHealthDuplicates $report.Records
    $report.State=if ($Control -and $Control.Cancel) {'CANCELLED'} elseif ($warnings.Count) {'COMPLETED_WITH_WARNINGS'} else {'COMPLETED'}
    $report.EndedAt=[datetime]::UtcNow.ToString('o')
    Write-PkHealthAudit $reportPath $report
    $report
}

function Get-PkHealthSummary($Report) {
    $records=@($Report.Records);$fully=@($records | Where-Object Integrity -eq 'DECODE_CHECKED')
    $healthy=@($fully | Where-Object {'HEALTHY' -in $_.Codes}).Count
    $summary=@{Files=$records.Count;Tracks=@($records|Where-Object Kind -eq 'Track').Count;Sets=@($records|Where-Object Kind -eq 'Set').Count;Bytes=($records|ForEach-Object {[long]$_.Size}|Measure-Object -Sum).Sum;FullyChecked=$fully.Count;Healthy=$healthy;NeedsReview=@($records|Where-Object {@(Get-PkHealthIssueCodes $_.Codes).Count}).Count;AudioErrors=@($records|Where-Object {'AUDIO_ERROR' -in $_.Codes}).Count;Score=$(if($fully.Count){[Math]::Round(100*$healthy/$fully.Count,1)}else{$null});MissingTags=@($records|Where-Object {'MISSING_ARTIST' -in $_.Codes -or 'MISSING_TITLE' -in $_.Codes}).Count;MissingJson=@($records|Where-Object {'MISSING_JSON' -in $_.Codes}).Count;MissingCovers=@($records|Where-Object {'MISSING_COVER' -in $_.Codes}).Count;Conflicts=@($records|Where-Object {'TAG_MISMATCH' -in $_.Codes}).Count;Duplicates=@($records|Where-Object {'DUPLICATE_AUDIO' -in $_.Codes -or 'POSSIBLE_DUPLICATE' -in $_.Codes}).Count}
    $summary.SemanticMatches=@($records|Where-Object {'METADATA_SEMANTIC_MATCH' -in $_.Codes}).Count
    $summary
}

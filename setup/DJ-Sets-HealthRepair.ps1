function ConvertTo-PkHealthMap($Object) {
    $map=@{}
    if ($Object -is [Collections.IDictionary]) { foreach($key in $Object.Keys){$map[$key]=$Object[$key]} }
    elseif ($Object) { foreach($p in $Object.PSObject.Properties){$map[$p.Name]=$p.Value} }
    $map
}

function New-PkHealthPlan($Options,$Report,$Requests) {
    Assert-PkHealthOptions $Options -Writing
    if (!$Report -or $Report.Root -ine $Options.Root) { throw 'Zuerst die aktuelle Bibliothek scannen.' }
    $items=[Collections.Generic.List[object]]::new();$bytes=0L
    foreach ($request in $Requests) {
        $record=$Report.Records | Where-Object { $_.Id -ceq $request.Id } | Select-Object -First 1
        if (!$record) { throw 'Unbekannter Scan-Eintrag.' }
        $path=Assert-PkHealthScope $record.Path $Options.Root
        if ($record.Integrity -eq 'FAILED' -or 'INVALID_JSON' -in $record.Codes) { throw 'Audio- oder JSON-Fehler bitte zuerst manuell klären.' }
        $changes=ConvertTo-PkHealthMap $request.Changes
        if (!$changes.Count -and !$request.Json -and !$request.CoverPath) {
            foreach ($field in @('Artist','Title')) {
                if (!$record.Tags.$field -and $record.Resolved.Values.$field -and $field -notin $record.Resolved.Conflicts) { $changes[$field]=$record.Resolved.Values.$field }
            }
        }
        $fields=Get-PkHealthFields
        foreach ($field in @($changes.Keys)) {
            if ($field -cnotin $fields.Keys -or $changes[$field] -isnot [string] -or $changes[$field].Length -gt 2000 -or $changes[$field] -match '[\x00-\x1F]') { throw 'Ungültige Metadatenänderung.' }
            if ($field -in @('Artist','Title') -and !$changes[$field].Trim()) { throw 'Interpret und Titel dürfen nicht geleert werden.' }
            if ([string]$record.Tags.$field -ceq $changes[$field] -and [string]$record.Pk.$field -ceq $changes[$field]) { $changes.Remove($field) }
        }
        if (!$changes.Count -and !$request.Json -and !$request.CoverPath) { continue }
        if ($changes.Count -and !$record.Repairable) { throw 'Dieses Format ist nur lesend freigegeben.' }
        if ((Get-PkHealthFileHash $path) -cne $record.FileHash -or (Get-PkHealthStamp $path) -cne $record.Stamp) { throw 'Datei seit dem Scan geändert. Bitte erneut scannen.' }
        $cover=$null
        if ($request.CoverPath) {
            Assert-SafePath $request.CoverPath
            if (![IO.File]::Exists($request.CoverPath) -or [IO.FileInfo]::new($request.CoverPath).Length -gt 20MB) { throw 'Cover fehlt oder ist zu groß.' }
            if([IO.Path]::GetExtension($request.CoverPath) -notin @('.jpg','.jpeg','.png','.webp')){throw 'Coverformat nicht freigegeben.'}
            $raw=Invoke-PkHealthTool $Options.Probe @('-v','error','-show_entries','stream=width,height','-of','json','--',$request.CoverPath) $null
            $image=(ConvertFrom-Json $raw).streams|Select-Object -First 1
            if(!$image.width -or !$image.height -or [long]$image.width*$image.height -gt 40000000){throw 'Ungültige Coverabmessungen.'}
            $cover=@{Path=[IO.Path]::GetFullPath($request.CoverPath);Hash=(Get-PkHealthFileHash $request.CoverPath)}
        }
        $originals=@(Get-Item -LiteralPath $path)+@(Get-PkHealthSidecars $path)
        $estimate=($originals | Measure-Object Length -Sum).Sum;$bytes+=$estimate
        $items.Add(@{Id=$record.Id;Path=$path;FileHash=$record.FileHash;Stamp=$record.Stamp;Before=$record.Tags;Changes=$changes;Sources=$record.Resolved.Evidence;Conflicts=@($record.Resolved.Conflicts);Json=[bool]$request.Json;Cover=$cover;EstimatedBytes=$estimate;State='AWAITING_APPROVAL'})
    }
    if (!$items.Count) { throw 'Keine eindeutigen oder ausgewählten Änderungen. Eintrag bearbeiten oder JSON-Rekonstruktion auswählen.' }
    if($Options.BackupLimitGB -gt 0 -and (Get-PkHealthBackupUsage $Options)+$bytes -gt [double]$Options.BackupLimitGB*1GB){throw 'Das konfigurierte Backup-Speicherlimit würde überschritten. Vorhandene Backups werden nicht automatisch gelöscht.'}
    $plan=@{SchemaVersion=1;Id=[guid]::NewGuid().ToString('N');Root=$Options.Root;CreatedAt=[datetime]::UtcNow.ToString('o');State='AWAITING_APPROVAL';EstimatedBytes=$bytes;Items=@($items.ToArray());Results=@()}
    Write-PkHealthAudit (Join-Path $Options.Storage "plan-$($plan.Id).json") $plan
    $plan
}

function Assert-PkHealthSpace([string]$Path,[long]$Required) {
    $volume=[IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path))
    if ($volume -match '^[A-Za-z]:\\$') {
        $drive=[IO.DriveInfo]::new($volume)
        if ($drive.AvailableFreeSpace -lt $Required+32MB) { throw "Nicht genügend Speicherplatz auf $volume" }
    } else { throw 'Reparaturen auf Netzwerkpfaden sind noch nicht freigegeben.' }
}

function Assert-PkHealthEquivalent($Before,$After,[string[]]$BeforeHashes,[string[]]$AfterHashes) {
    if (($BeforeHashes -join '|') -cne ($AfterHashes -join '|')) { throw 'Audiohash verändert. Reparatur wird verworfen.' }
    $beforeStreams=@($Before.streams);$afterStreams=@($After.streams)
    if ($beforeStreams.Count -ne $afterStreams.Count) { throw 'Anzahl der Streams verändert.' }
    for ($i=0;$i -lt $beforeStreams.Count;$i++) {
        foreach ($key in @('codec_type','codec_name','profile','sample_rate','channels','channel_layout','width','height','pix_fmt')) {
            if ([string]$beforeStreams[$i].$key -cne [string]$afterStreams[$i].$key) { throw "Streamparameter verändert: $key" }
        }
        if ([int]$beforeStreams[$i].disposition.attached_pic -ne [int]$afterStreams[$i].disposition.attached_pic) { throw 'Eingebettetes Cover verändert.' }
    }
    $culture=[Globalization.CultureInfo]::InvariantCulture
    $duration1=[double]::Parse([string]$Before.format.duration,$culture);$duration2=[double]::Parse([string]$After.format.duration,$culture)
    if ([Math]::Abs($duration1-$duration2) -gt .05) { throw 'Audiodauer verändert.' }
}

function Assert-PkHealthWrittenTags($Before,$After,$Changes) {
    foreach ($field in (Get-PkHealthFields).Keys) {
        $expected=if ($Changes.ContainsKey($field)) { $Changes[$field] } else { $Before[$field] }
        if ([string]$After[$field] -cne [string]$expected) { throw "Tag-Prüfung fehlgeschlagen: $field" }
    }
}

function Get-PkHealthBackupManifest([string]$BackupDirectory,$Options) {
    $base=[IO.Path]::GetFullPath($Options.BackupRoot).TrimEnd('\')+'\'
    $directory=[IO.Path]::GetFullPath($BackupDirectory)
    if (!$directory.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) { throw 'Ungültiger Backup-Pfad.' }
    Assert-SafePath $directory
    $manifest=Read-PkHealthJson (Join-Path $directory 'repair.json')
    if ($manifest.SchemaVersion -ne 1 -or $manifest.Root -ine $Options.Root) { throw 'Backup gehört nicht zur freigegebenen Bibliothek.' }
    foreach ($file in $manifest.Files) {
        $null=Assert-PkHealthScope $file.Path $Options.Root
        if ($file.BackupName -cnotmatch '^original-\d{3}\.bin$') { throw 'Ungültiger Backup-Eintrag.' }
        $backup=Join-Path $directory $file.BackupName
        if ((Get-PkHealthFileHash $backup) -cne $file.Hash) { throw 'Backup-Prüfsumme stimmt nicht.' }
    }
    foreach($file in $manifest.Created){
        $null=Assert-PkHealthScope $file.Path $Options.Root
        if([IO.Path]::GetFileName($file.Path) -cnotin @('plattenkoffer.json','plattenkoffer-cover.jpg') -or [IO.Path]::GetDirectoryName($file.Path) -ine [IO.Path]::GetDirectoryName($manifest.Path)){throw 'Ungültige neue Begleitdatei im Backup.'}
    }
    $manifest
}

function Invoke-PkHealthRepairItem($Options,$Item,[string]$PlanId,$Control) {
    $path=Assert-PkHealthScope $Item.Path $Options.Root
    $directory=Join-Path (Join-Path $Options.BackupRoot $PlanId) $Item.Id
    Assert-SafePath $directory
    if ([IO.File]::Exists((Join-Path $directory 'repair.json'))) { throw 'Diese Reparatur wurde bereits begonnen. Zuerst Protokoll und Wiederherstellung prüfen.' }
    if ((Get-PkHealthFileHash $path) -cne $Item.FileHash -or (Get-PkHealthStamp $path) -cne $Item.Stamp) { throw 'Datei oder Begleitdaten seit der Vorschau geändert.' }
    $changes=ConvertTo-PkHealthMap $Item.Changes
    $beforeProbe=Get-PkHealthProbe $path $Options $Control
    $beforeTags=Get-PkHealthTags $beforeProbe
    $beforeHashes=Get-PkHealthAudioHashes $path $Options $Control
    $null=Invoke-PkHealthTool $Options.FFmpeg @('-v','error','-xerror','-err_detect','explode','-nostdin','-i',$path,'-map','0:a','-f','null','-') $Control 14400
    $fresh=Get-PkHealthRecord $path $Options $Control
    if ($changes.Count -and !$fresh.Repairable) { throw 'Format ist nicht schreibend freigegeben.' }
    if ('INVALID_JSON' -in $fresh.Codes -or 'AUDIO_ERROR' -in $fresh.Codes) { throw 'Die Datei ist nicht sicher reparierbar.' }
    Assert-PkHealthSpace $Options.BackupRoot ([long]$Item.EstimatedBytes*2)
    if($Options.BackupLimitGB -gt 0 -and (Get-PkHealthBackupUsage $Options)+[long]$Item.EstimatedBytes -gt [double]$Options.BackupLimitGB*1GB){throw 'Backup-Speicherlimit erreicht.'}
    Assert-PkHealthSpace $path ([long][IO.FileInfo]::new($path).Length*2)
    if ($Item.Cover -and (Get-PkHealthFileHash $Item.Cover.Path) -cne $Item.Cover.Hash) { throw 'Cover seit der Vorschau geändert.' }
    $jsonPath=Join-Path ([IO.Path]::GetDirectoryName($path)) 'plattenkoffer.json'
    $coverPath=Join-Path ([IO.Path]::GetDirectoryName($path)) 'plattenkoffer-cover.jpg'
    $temp=Join-Path ([IO.Path]::GetDirectoryName($path)) ('.pk-health-'+[guid]::NewGuid().ToString('N')+[IO.Path]::GetExtension($path))
    $coverTemp=$temp+'.jpg'
    $manifest=@{SchemaVersion=1;PlanId=$PlanId;Id=$Item.Id;Root=$Options.Root;Path=$path;State='BACKUP_CREATED';StartedAt=[datetime]::UtcNow.ToString('o');EndedAt='';Files=@();Created=@();Changes=$changes;Sources=$Item.Sources;AudioBefore=$beforeHashes;AudioAfter=@();FileBefore=$Item.FileHash;FileAfter='';BeforeTags=$beforeTags;AfterTags=@{};Error='';Method='FFmpeg Stream Copy';Temp=$temp}
    $touched=[Collections.Generic.List[string]]::new();$lock=$null
    try {
        [void][IO.Directory]::CreateDirectory($directory)
        $lock=[IO.File]::Open($path,'Open','Read','Read')
        $files=@(Get-Item -LiteralPath $path)+@(Get-PkHealthSidecars $path)
        for ($i=0;$i -lt $files.Count;$i++) {
            $file=$files[$i];Assert-SafePath $file.FullName
            $name='original-{0:D3}.bin' -f $i;$backup=Join-Path $directory $name
            $hash=Get-PkHealthFileHash $file.FullName
            [IO.File]::Copy($file.FullName,$backup,$false)
            if ((Get-PkHealthFileHash $backup) -cne $hash) { throw 'Backup konnte nicht verifiziert werden.' }
            $manifest.Files+=@{Path=$file.FullName;BackupName=$name;Hash=$hash;AfterHash=$hash;Length=$file.Length;LastWriteUtc=$file.LastWriteTimeUtc.ToString('o')}
        }
        foreach ($target in @($jsonPath)+@($(if($Item.Cover){$coverPath}))) {
            if ($target -and ![IO.File]::Exists($target)) { $manifest.Created+=@{Path=$target;AfterHash=''} }
        }
        $journal=Join-Path $directory 'repair.json'
        Write-PkHealthAudit $journal $manifest
        $manifest.State='REPAIR_RUNNING';Write-PkHealthAudit $journal $manifest
        if ($changes.Count) {
            $args=@('-v','error','-nostdin','-n','-i',$path,'-map','0','-map_metadata','0','-c','copy')
            foreach ($field in $changes.Keys) {
                foreach($tag in @(Get-PkHealthTagKeys $field)){
                $args+=@('-metadata',"$tag=$($changes[$field])")
                # Ogg stores audio tags on the stream. Set both locations explicitly.
                $args+=@('-metadata:s:a:0',"$tag=$($changes[$field])")
                }
            }
            $args+= $temp
            $null=Invoke-PkHealthTool $Options.FFmpeg $args $Control 3600
            $manifest.State='VALIDATING';Write-PkHealthAudit $journal $manifest
            $afterProbe=Get-PkHealthProbe $temp $Options $Control
            $afterHashes=Get-PkHealthAudioHashes $temp $Options $Control
            Assert-PkHealthEquivalent $beforeProbe $afterProbe $beforeHashes $afterHashes
            if(@($beforeProbe.streams|Where-Object {$_.codec_type -ne 'audio'}).Count){
                $beforeStreams=Invoke-PkHealthTool $Options.FFmpeg @('-v','error','-nostdin','-i',$path,'-map','0','-c','copy','-f','streamhash','-hash','sha256','-') $Control 3600
                $afterStreams=Invoke-PkHealthTool $Options.FFmpeg @('-v','error','-nostdin','-i',$temp,'-map','0','-c','copy','-f','streamhash','-hash','sha256','-') $Control 3600
                if($beforeStreams.Trim() -cne $afterStreams.Trim()){throw 'Zusätzliche Streams oder eingebettetes Cover verändert.'}
            }
            $afterTags=Get-PkHealthTags $afterProbe
            Assert-PkHealthWrittenTags $beforeTags $afterTags $changes
            $manifest.AudioAfter=$afterHashes;$manifest.AfterTags=$afterTags;$manifest.FileAfter=Get-PkHealthFileHash $temp
        } else { $manifest.AudioAfter=$beforeHashes;$manifest.AfterTags=$beforeTags;$manifest.FileAfter=$Item.FileHash }
        if ($Item.Cover) {
            $null=Invoke-PkHealthTool $Options.FFmpeg @('-v','error','-nostdin','-n','-i',$Item.Cover.Path,'-frames:v','1','-q:v','2',$coverTemp) $Control
            $raw=Invoke-PkHealthTool $Options.Probe @('-v','error','-show_entries','stream=width,height','-of','json','--',$coverTemp) $Control
            $image=(ConvertFrom-Json $raw).streams | Select-Object -First 1
            if (!$image.width -or !$image.height -or [long]$image.width*$image.height -gt 40000000) { throw 'Ungültiges Cover.' }
        }
        $pk=if ([IO.File]::Exists($jsonPath)) { Read-PkHealthJson $jsonPath } else { [pscustomobject]@{} }
        $sources=ConvertTo-PkHealthMap $pk.MetadataSources
        $confirmed=[datetime]::UtcNow.ToString('o')
        foreach ($field in $changes.Keys) {
            $pk | Add-Member NoteProperty $field $changes[$field] -Force
            $sources[$field]=@{Provider='Plattenkoffer Health';OriginalValue=[string]$beforeTags[$field];ProposedValue=$changes[$field];Value=$changes[$field];ConfirmedAt=$confirmed;Confidence='VERIFIED';Manual=$true;Evidence=$Item.Sources.$field}
        }
        if ($Item.Json -or ![IO.File]::Exists($jsonPath)) {
            foreach ($field in (Get-PkHealthFields).Keys) {
                if (!$pk.PSObject.Properties[$field] -and $beforeTags[$field]) {
                    $pk | Add-Member NoteProperty $field $beforeTags[$field]
                    $sources[$field]=@{Provider='Audio-Tags';Value=$beforeTags[$field];ConfirmedAt=$confirmed;Confidence='VERIFIED';Manual=$true}
                }
            }
        }
        $pk | Add-Member NoteProperty MetadataSources ([pscustomobject]$sources) -Force
        $pk | Add-Member NoteProperty HealthSchemaVersion 1 -Force
        $jsonBytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json $pk -Depth 60))
        # Record expected post-images before any replacement, for crash-safe restore preview.
        foreach ($file in $manifest.Files) {
            if ($file.Path -ieq $path) { $file.AfterHash=$manifest.FileAfter }
        }
        $hash=[Security.Cryptography.SHA256]::Create()
        try { $jsonHash=[BitConverter]::ToString($hash.ComputeHash($jsonBytes)).Replace('-','') } finally { $hash.Dispose() }
        foreach ($file in @($manifest.Files)+@($manifest.Created)) {
            if ($file.Path -ieq $jsonPath) { $file.AfterHash=$jsonHash }
            if ($Item.Cover -and $file.Path -ieq $coverPath) { $file.AfterHash=Get-PkHealthFileHash $coverTemp }
        }
        $manifest.State='COMMITTING';Write-PkHealthAudit $journal $manifest
        if ($Control -and $Control.Cancel) { throw [OperationCanceledException]::new('Vorgang abgebrochen.') }
        if ((Get-PkHealthFileHash $path) -cne $Item.FileHash -or (Get-PkHealthStamp $path) -cne $Item.Stamp) { throw 'Original wurde während der Reparatur verändert.' }
        $lock.Dispose();$lock=$null
        if ($changes.Count) { $touched.Add($path);[IO.File]::Replace($temp,$path,[NullString]::Value) }
        $touched.Add($jsonPath);Write-PkHealthBytes $jsonPath $jsonBytes
        if ($Item.Cover) { $touched.Add($coverPath);Write-PkHealthBytes $coverPath ([IO.File]::ReadAllBytes($coverTemp)) }
        $finalProbe=Get-PkHealthProbe $path $Options $null
        $finalHashes=Get-PkHealthAudioHashes $path $Options $null
        Assert-PkHealthEquivalent $beforeProbe $finalProbe $beforeHashes $finalHashes
        Assert-PkHealthWrittenTags $beforeTags (Get-PkHealthTags $finalProbe) $changes
        foreach ($file in $manifest.Files) { $file.AfterHash=Get-PkHealthFileHash $file.Path }
        foreach ($file in $manifest.Created) { $file.AfterHash=Get-PkHealthFileHash $file.Path }
        $manifest.State='COMMITTED';$manifest.EndedAt=[datetime]::UtcNow.ToString('o');Write-PkHealthAudit $journal $manifest
    } catch {
        $failure=$_.Exception.Message
        if ($lock) { $lock.Dispose();$lock=$null }
        try {
            foreach ($target in $touched) {
                $original=$manifest.Files | Where-Object { $_.Path -ieq $target } | Select-Object -First 1
                if ($original) { Write-PkHealthFile $target (Join-Path $directory $original.BackupName) }
                else { [IO.File]::Delete($target) }
            }
            $manifest.State=if($touched.Count){'ROLLED_BACK'}else{'FAILED'}
        } catch { $manifest.State='ROLLBACK_REQUIRED';$failure+=" Rücksetzen fehlgeschlagen: $($_.Exception.Message)" }
        $manifest.Error=$failure;$manifest.EndedAt=[datetime]::UtcNow.ToString('o')
        if ([IO.Directory]::Exists($directory)) { Write-PkHealthAudit (Join-Path $directory 'repair.json') $manifest }
    } finally {
        if ($lock) { $lock.Dispose() }
        foreach ($temporary in @($temp,$coverTemp)) { if ([IO.File]::Exists($temporary)) { Assert-SafePath $temporary;[IO.File]::Delete($temporary) } }
    }
    $manifest
}

function Write-PkHealthBytes([string]$Path,[byte[]]$Bytes) {
    Assert-SafePath $Path
    $temp="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllBytes($temp,$Bytes)
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp,$Path,[NullString]::Value) } else { [IO.File]::Move($temp,$Path) }
    } finally { [IO.File]::Delete($temp) }
}

function Write-PkHealthFile([string]$Path,[string]$Source) {
    Assert-SafePath $Path;Assert-SafePath $Source
    $temp="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try{
        [IO.File]::Copy($Source,$temp,$false)
        if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,[NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
    }finally{[IO.File]::Delete($temp)}
}

function Invoke-PkHealthPlan($Options,$Plan,$Control) {
    Assert-PkHealthOptions $Options -Writing
    if ($Plan.State -ne 'APPROVED' -or $Plan.Root -ine $Options.Root) { throw 'Ein ausdrücklich freigegebener Plan ist erforderlich.' }
    $results=[Collections.Generic.List[object]]::new()
    foreach ($item in $Plan.Items) {
        if ($Control -and $Control.Cancel) { break }
        if ($Control) { $Control.Current=$item.Path;$Control.Done=$results.Count;$Control.Total=@($Plan.Items).Count }
        try { $result=Invoke-PkHealthRepairItem $Options $item $Plan.Id $Control }
        catch { $result=@{Id=$item.Id;Path=$item.Path;State='FAILED';Error=$_.Exception.Message} }
        $results.Add($result)
        $Plan.Results=@($results.ToArray())
        Write-PkHealthAudit (Join-Path $Options.Storage "plan-$($Plan.Id).json") $Plan
    }
    $Plan.State=if($Control -and $Control.Cancel){'CANCELLED'}else{'COMPLETED'}
    $Plan.Results=@($results.ToArray());Write-PkHealthAudit (Join-Path $Options.Storage "plan-$($Plan.Id).json") $Plan
    $Plan
}

function Get-PkHealthRestorePreview($Options,[string[]]$Directories) {
    $items=@(foreach ($directory in $Directories) {
        $manifest=Get-PkHealthBackupManifest $directory $Options
        if ($manifest.State -in @('RESTORED','FAILED','ROLLED_BACK')) { continue }
        foreach ($file in $manifest.Files) {
            $current=if ([IO.File]::Exists($file.Path)) {Get-PkHealthFileHash $file.Path}else{''}
            if ($current -cne $file.Hash -and $current -cne $file.AfterHash) { throw "Datei nach der Reparatur verändert oder Zustand unklar: $($file.Path). Automatisches Zurücksetzen gesperrt." }
        }
        foreach ($file in $manifest.Created) {
            $null=Assert-PkHealthScope $file.Path $Options.Root
            if ([IO.File]::Exists($file.Path) -and (!$file.AfterHash -or (Get-PkHealthFileHash $file.Path) -cne $file.AfterHash)) { throw 'Neue Begleitdatei wurde verändert oder Zustand ist unklar.' }
        }
        @{Directory=$directory;Manifest=$manifest}
    })
    if (!$items.Count) { throw 'Keine wiederherstellbare Reparatur ausgewählt.' }
    @{Id=[guid]::NewGuid().ToString('N');Root=$Options.Root;State='AWAITING_APPROVAL';Items=$items}
}

function Invoke-PkHealthRestore($Options,$Preview,$Control) {
    if ($Preview.State -ne 'APPROVED') { throw 'Wiederherstellung muss freigegeben werden.' }
    $validated=Get-PkHealthRestorePreview $Options @($Preview.Items | ForEach-Object { $_.Directory })
    $completed=0
    foreach ($item in $validated.Items) {
        if ($Control -and $Control.Cancel) { break }
        $manifest=$item.Manifest
        if ($Control) { $Control.Current=$manifest.Path }
        $manifest.State='RESTORE_RUNNING';Write-PkHealthAudit (Join-Path $item.Directory 'repair.json') $manifest
        try {
        foreach ($file in $manifest.Files) {
            Write-PkHealthFile $file.Path (Join-Path $item.Directory $file.BackupName)
            if ((Get-PkHealthFileHash $file.Path) -cne $file.Hash) { throw 'Wiederherstellungsprüfung fehlgeschlagen.' }
            if($file.LastWriteUtc){[IO.File]::SetLastWriteTimeUtc($file.Path,[datetime]::Parse($file.LastWriteUtc).ToUniversalTime())}
        }
        foreach ($file in $manifest.Created) { Assert-SafePath $file.Path;[IO.File]::Delete($file.Path) }
        $manifest.State='RESTORED';$manifest | Add-Member NoteProperty RestoredAt ([datetime]::UtcNow.ToString('o')) -Force
        Write-PkHealthAudit (Join-Path $item.Directory 'repair.json') $manifest
        $completed++
        } catch {
            $manifest.State='RESTORE_FAILED';$manifest.Error=$_.Exception.Message;Write-PkHealthAudit (Join-Path $item.Directory 'repair.json') $manifest;throw
        }
    }
    @{State=$(if($Control -and $Control.Cancel){'CANCELLED'}else{'RESTORED'});Count=$completed}
}

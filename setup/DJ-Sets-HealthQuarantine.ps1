function New-PkQuarantinePlan($Options,$Report,[string[]]$Ids,[string[]]$References,$Control) {
    if(!$Options.QuarantineRoot){throw 'Quarantäneordner konfigurieren.'}
    Assert-PkHealthOptions $Options
    $items=@(foreach($id in @($Ids|Select-Object -Unique)){
        $record=$Report.Records|Where-Object {$_.Id -ceq $id}|Select-Object -First 1
        if(!$record -or 'DUPLICATE_AUDIO' -notin $record.Codes){throw 'Nur bestätigte identische Audioduplikate können hier archiviert werden.'}
        $null=Assert-PkHealthScope $record.Path $Options.Root
        if((Get-PkHealthFileHash $record.Path) -cne $record.FileHash){throw 'Datei seit dem Scan geändert.'}
        $keeper=$Report.Records|Where-Object {$_.Id -notin $Ids -and $_.Path -in $record.DuplicateOf -and [IO.File]::Exists($_.Path)}|Sort-Object @{Expression={if($_.Pk){1}else{0}}} -Descending|Select-Object -First 1
        if(!$keeper){throw 'Mindestens eine identische Datei muss in der Bibliothek bleiben.'}
        $null=Assert-PkHealthScope $keeper.Path $Options.Root
        $keeperHash=Get-PkHealthFileHash $keeper.Path
        if((Get-PkHealthAudioHashes $keeper.Path $Options $Control) -join '|' -cne ($record.AudioHashes -join '|') -or (Get-PkHealthFileHash $keeper.Path) -cne $keeperHash){throw 'Die vorgeschlagene Behaltensdatei ist nicht mehr identisch.'}
        $own=@($References|Where-Object {$_ -ieq $record.Path -or $_ -ieq [IO.Path]::GetDirectoryName($record.Path)})
        if($own.Count){throw 'Die Datei wird von einer PK-Playlist oder den Favoriten referenziert. Verweise zuerst in PK ändern.'}
        $external=@()
        if($Options.VdjDatabase -and [IO.File]::Exists($Options.VdjDatabase)){
            $database=Read-PkVdjDatabase $Options.VdjDatabase
            if(@($database.Songs|Where-Object {$_.GetAttribute('FilePath') -ieq $record.Path}).Count){$external+= 'VirtualDJ-Datenbank: '+$Options.VdjDatabase}
        }
        @{Id=$id;Path=$record.Path;Hash=$record.FileHash;Bytes=$record.Size;Keeper=$keeper.Path;KeeperHash=$keeperHash;AudioHashes=@($record.AudioHashes);References=$external}
    })
    if(!$items.Count){throw 'Keine Dateien ausgewählt.'}
    $plan=@{Type='QUARANTINE';Id=[guid]::NewGuid().ToString('N');Root=$Options.Root;State='AWAITING_APPROVAL';Items=$items;CreatedAt=[datetime]::UtcNow.ToString('o')}
    Write-PkHealthAudit (Join-Path $Options.Storage "quarantine-plan-$($plan.Id).json") $plan;$plan
}
function Invoke-PkQuarantinePlan($Options,$Plan,$Control) {
    Assert-PkHealthOptions $Options
    if($Plan.State -ne 'APPROVED' -or !$Plan.ExternalReferencesReviewed -or $Plan.Root -ine $Options.Root){throw 'Archivierung und externe Referenzprüfung müssen ausdrücklich freigegeben werden.'}
    $results=@(foreach($item in $Plan.Items){
        if($Control -and $Control.Cancel){break}
        $source=Assert-PkHealthScope $item.Path $Options.Root
        $directory=Join-Path $Options.QuarantineRoot "$($Plan.Id)/$($item.Id)";$backupDir=Join-Path $Options.BackupRoot "quarantine/$($Plan.Id)/$($item.Id)"
        foreach($path in @($directory,$backupDir)){Assert-SafePath $path;if([IO.Directory]::Exists($path)){throw 'Archivierung wurde bereits begonnen.'}}
        if((Get-PkHealthFileHash $source) -cne $item.Hash -or (Get-PkHealthFileHash $item.Keeper) -cne $item.KeeperHash){throw 'Duplikat oder Behaltensdatei seit der Vorschau verändert.'}
        if((Get-PkHealthAudioHashes $item.Keeper $Options $Control) -join '|' -cne ($item.AudioHashes -join '|')){throw 'Die verbleibende Datei enthält andere Audiodaten.'}
        Assert-PkHealthSpace $Options.QuarantineRoot ($item.Bytes*2);Assert-PkHealthSpace $Options.BackupRoot ($item.Bytes*2)
        if($Options.BackupLimitGB -gt 0 -and (Get-PkHealthBackupUsage $Options)+$item.Bytes -gt $Options.BackupLimitGB*1GB){throw 'Backup-Limit erreicht.'}
        [void][IO.Directory]::CreateDirectory($directory);[void][IO.Directory]::CreateDirectory($backupDir)
        $payload=Join-Path $directory 'original.bin';$backup=Join-Path $backupDir 'original.bin';$journal=Join-Path $directory 'quarantine.json'
        $result=@{Type='QUARANTINE';Id=$item.Id;JobId=$Plan.Id;Root=$Options.Root;Path=$source;Hash=$item.Hash;Keeper=$item.Keeper;Payload=$payload;Backup=$backup;References=$item.References;State='BACKUP_CREATED';StartedAt=[datetime]::UtcNow.ToString('o');Error=''}
        $deleted=$false;$lock=$null;$stage=$source+'.pk-quarantine-'+$Plan.Id+'.bak'
        Assert-SafePath $stage;if([IO.File]::Exists($stage)){throw 'Archivierungs-Zwischenstand existiert bereits.'};$result.Stage=$stage
        try{
            $lock=[IO.File]::Open($source,'Open','Read','Read')
            [IO.File]::Copy($source,$backup,$false);[IO.File]::Copy($source,$payload,$false)
            if((Get-PkHealthFileHash $backup) -cne $item.Hash -or (Get-PkHealthFileHash $payload) -cne $item.Hash){throw 'Archivkopien nicht verifiziert.'}
            Write-PkHealthAudit $journal $result
            if($Control -and $Control.Cancel){throw [OperationCanceledException]::new('Abgebrochen.')}
            if((Get-PkHealthFileHash $source) -cne $item.Hash -or (Get-PkHealthFileHash $item.Keeper) -cne $item.KeeperHash){throw 'Datei inzwischen verändert.'}
            $lock.Dispose();$lock=$null
            $result.State='COMMITTING';Write-PkHealthAudit $journal $result
            [IO.File]::Move($source,$stage);$deleted=$true
            if((Get-PkHealthFileHash $stage) -cne $item.Hash){throw 'Datei unmittelbar vor der Archivierung verändert.'}
            [IO.File]::Delete($stage);$result.State='COMMITTED';$result.EndedAt=[datetime]::UtcNow.ToString('o');Write-PkHealthAudit $journal $result
        }catch{
            if($lock){$lock.Dispose();$lock=$null};$result.Error=$_.Exception.Message
            if($deleted){try{
                if([IO.File]::Exists($source)){throw 'Originalpfad inzwischen belegt. Zwischenstand und Backup bleiben erhalten.'}
                if([IO.File]::Exists($stage)){[IO.File]::Move($stage,$source)}else{[IO.File]::Copy($backup,$source,$false)}
                $result.State='ROLLED_BACK'
            }catch{$result.State='ROLLBACK_REQUIRED';$result.Error+=' '+$_.Exception.Message}}else{$result.State='FAILED'}
            Write-PkHealthAudit $journal $result
        }finally{if($lock){$lock.Dispose()}}
        $result
    })
    @{Type='QUARANTINE';State=$(if($Control -and $Control.Cancel){'CANCELLED'}else{'COMPLETED'});Results=$results}
}
function Get-PkQuarantineRestorePreview($Options,[string]$Id) {
    if($Id -cnotmatch '^[a-f0-9]{32}/[A-F0-9]{64}$'){throw 'Ungültige Quarantäne-ID.'}
    $directory=Join-Path $Options.QuarantineRoot $Id;$manifest=Read-PkHealthJson (Join-Path $directory 'quarantine.json')
    $null=Assert-PkHealthScope $manifest.Path $Options.Root
    $payload=Join-Path $directory 'original.bin'
    if($manifest.Type -ne 'QUARANTINE' -or $manifest.Root -ine $Options.Root -or $manifest.State -notin @('COMMITTED','COMMITTING','ROLLBACK_REQUIRED') -or (Get-PkHealthFileHash $payload) -cne $manifest.Hash){throw 'Archiv nicht sicher wiederherstellbar.'}
    if([IO.File]::Exists($manifest.Path) -and (Get-PkHealthFileHash $manifest.Path) -cne $manifest.Hash){throw 'Am Originalpfad existiert bereits eine fremde Datei. Sie wird nicht überschrieben.'}
    $stage=$manifest.Path+'.pk-quarantine-'+$Id.Split('/')[0]+'.bak'
    if([IO.File]::Exists($stage)){Assert-SafePath $stage;if((Get-PkHealthFileHash $stage) -cne $manifest.Hash){throw 'Unklarer Archivierungs-Zwischenstand: keine automatische Überschreibung.'}}
    @{Type='QUARANTINE_RESTORE';Id=[guid]::NewGuid().ToString('N');ArchiveId=$Id;Path=$manifest.Path;Hash=$manifest.Hash;State='AWAITING_APPROVAL'}
}
function Invoke-PkQuarantineRestore($Options,$Preview) {
    if($Preview.State -ne 'APPROVED'){throw 'Wiederherstellung nicht freigegeben.'}
    $validated=Get-PkQuarantineRestorePreview $Options $Preview.ArchiveId
    if($validated.Hash -cne $Preview.Hash){throw 'Archiv seit der Vorschau geändert.'}
    $directory=Join-Path $Options.QuarantineRoot $Preview.ArchiveId;$payload=Join-Path $directory 'original.bin'
    Assert-SafePath $Preview.Path;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Preview.Path))
    # FileMode.CreateNew semantics prevent any unexpected overwrite at the destination.
    if(![IO.File]::Exists($Preview.Path)){[IO.File]::Copy($payload,$Preview.Path,$false)}
    if((Get-PkHealthFileHash $Preview.Path) -cne $Preview.Hash){throw 'Wiederhergestellte Datei stimmt nicht mit dem Original überein.'}
    $manifest=Read-PkHealthJson (Join-Path $directory 'quarantine.json');$manifest.State='RESTORED';Write-PkHealthAudit (Join-Path $directory 'quarantine.json') $manifest
    $stage=$Preview.Path+'.pk-quarantine-'+$Preview.ArchiveId.Split('/')[0]+'.bak'
    if([IO.File]::Exists($stage) -and (Get-PkHealthFileHash $stage) -ceq $Preview.Hash){Assert-SafePath $stage;[IO.File]::Delete($stage)}
    @{Type='QUARANTINE';State='RESTORED';Path=$Preview.Path}
}

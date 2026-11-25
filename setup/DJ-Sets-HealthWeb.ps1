function Initialize-WebHealth {
    $web.Health=@{Worker=$null;Handle=$null;Control=$null;Operation='';Report=$null;Plan=$null;Restore=$null;Status='Noch kein Scan. Musikdateien werden beim Scan nicht verändert.';LastProgress='';Dirty=$false}
    $localRoot=Split-Path -Parent $config
    $web.Health.Mode='simple';$web.Health.Detail=''
    $web.Health.Options=@{Root=$settings.MusicRoot;Probe=$probe;FFmpeg=$ffmpeg;Storage=(Join-Path $localRoot 'health');BackupRoot=(Join-Path $localRoot 'health-backups');BackupLimitGB=20;Deep=$false;VideoSuffixes=@('Official Video','Official Audio','Music Video','Lyrics Video','HD','HQ','4K')}
    $path=Join-Path $config 'health-options.json'
    $web.Health.SpecialPlan=$null;$web.Health.SpecialRestore=$null;$web.Health.Vdj=$null;$web.Health.Candidates=@();$web.Health.CoverRecovery=$null
    $web.Health.Options.VdjDatabase='';$web.Health.Options.QuarantineRoot=Join-Path $localRoot 'health-quarantine';$web.Health.Options.CoverRoot=Join-Path $localRoot 'health-covers'
    if ([IO.File]::Exists($path)) {
        try {
            $saved=Read-PkHealthJson $path
            if($saved.Mode -in @('simple','advanced')){$web.Health.Mode=$saved.Mode}
            if($saved.Dirty -is [bool]){$web.Health.Dirty=$saved.Dirty}
            foreach($key in @('Root','Probe','FFmpeg','Storage','BackupRoot','VideoSuffixes','VdjDatabase','QuarantineRoot','CoverRoot')){if($saved.$key){$web.Health.Options[$key]=$saved.$key}}
            if($saved.Deep -is [bool]){$web.Health.Options.Deep=$saved.Deep}
            if($null -ne $saved.BackupLimitGB){$web.Health.Options.BackupLimitGB=[double]$saved.BackupLimitGB}
        } catch { $web.Health.Status='Gespeicherte Pflege-Einstellungen konnten nicht gelesen werden.' }
    }
    $path=Join-Path $web.Health.Options.Storage 'scan.json'
    if ([IO.File]::Exists($path)) { try { $report=Read-PkHealthJson $path 256MB;if($report.Root -ieq $web.Health.Options.Root){$web.Health.Report=$report;$web.Health.Status="Gespeicherte Prüfergebnisse geladen: $(@($report.Records).Count) Dateien."} } catch { $web.Health.Status='Scanbericht konnte nicht gelesen werden. Erneuter Scan erforderlich.' } }
}

function Send-WebHealth {
    $job=$web.Health
    $readable=@{}
    foreach($key in @('Storage','BackupRoot','QuarantineRoot')){
        try{if($job.Options[$key]){Assert-SafePath $job.Options[$key];$readable[$key]=$true}}catch{Set-WebHealthError $_.Exception.Message}
    }
    $payload=@{type='health';busy=[bool]$job.Worker;operation=$job.Operation;status=$job.Status;options=$job.Options;summary=$null;rows=@();backups=@();plans=@();lastScan='';scanState='';warnings=@();dirty=[bool]$job.Dirty}
    $payload.mode=$job.Mode;$payload.detail=$job.Detail
    if ($job.Control) { $payload.progress=@{done=$job.Control.Done;total=$job.Control.Total;current=$job.Control.Current;phase=$job.Control.Phase;step=$job.Control.Step;filePercent=$job.Control.FilePercent} }
    $payload.vdj=$job.Vdj;$payload.candidates=@($job.Candidates);$payload.vdjBackups=@();$payload.quarantine=@()
    if(!$job.Worker){
        $vdjRoot=Join-Path $job.Options.BackupRoot 'vdj'
        if($readable.BackupRoot -and [IO.Directory]::Exists($vdjRoot)){foreach($folder in Get-ChildItem -LiteralPath $vdjRoot -Directory|Where-Object Name -match '^[a-f0-9]{32}$'){try{$m=Read-PkHealthJson (Join-Path $folder.FullName 'repair.json');$payload.vdjBackups+=@{id=$folder.Name;path=$m.Path;state=$m.State;date=$m.StartedAt}}catch{}}}
        if($readable.QuarantineRoot -and [IO.Directory]::Exists($job.Options.QuarantineRoot)){foreach($folder in Get-ChildItem -LiteralPath $job.Options.QuarantineRoot -Directory|Where-Object Name -match '^[a-f0-9]{32}$'){Assert-SafePath $folder.FullName;foreach($file in Get-ChildItem -LiteralPath $folder.FullName -Directory|Where-Object Name -match '^[A-F0-9]{64}$'){try{$m=Read-PkHealthJson (Join-Path $file.FullName 'quarantine.json');$payload.quarantine+=@{id="$($folder.Name)/$($file.Name)";path=$m.Path;keeper=$m.Keeper;state=$m.State;date=$m.StartedAt}}catch{}}}}
    }
    if ($job.Report) {
        $payload.summary=Get-PkHealthSummary $job.Report
        $payload.lastScan=$job.Report.EndedAt;$payload.scanState=$job.Report.State;$payload.warnings=@($job.Report.Warnings)
        $payload.rows=@(foreach($record in $job.Report.Records){
            @{id=$record.Id;path=$record.Path;kind=$record.Kind;tags=$record.Tags;codes=@($record.Codes);notes=@($record.Notes);codec=$record.Codec;container=$record.Container;duration=$record.Duration;bitrate=$record.Bitrate;rate=$record.SampleRate;channels=$record.Channels;size=$record.Size;lossless=$record.Lossless;integrity=$record.Integrity;repairable=$record.Repairable;coverCount=@($record.Covers).Count;embeddedCover=[bool]$record.EmbeddedCover;duplicates=@($record.DuplicateOf)}
        })
    }
    # Index journal headers only; no VirtualDJ database access and no executable content.
    if (!$job.Worker -and $readable.BackupRoot -and [IO.Directory]::Exists($job.Options.BackupRoot)) {
        $payload.backupBytes=Get-PkHealthBackupUsage $job.Options
        foreach ($folder in (Get-ChildItem -LiteralPath $job.Options.BackupRoot -Directory | Where-Object Name -match '^[0-9a-f]{32}$')) {
            Assert-SafePath $folder.FullName
            foreach ($item in (Get-ChildItem -LiteralPath $folder.FullName -Directory | Where-Object Name -match '^[0-9A-F]{64}$')) {
                try {
                    $manifest=Read-PkHealthJson (Join-Path $item.FullName 'repair.json')
                    $payload.backups+=@{id="$($folder.Name)/$($item.Name)";plan=$folder.Name;path=$manifest.Path;state=$manifest.State;date=$manifest.StartedAt;error=$manifest.Error}
                } catch { }
            }
        }
    }
    if (!$job.Worker -and $readable.Storage -and [IO.Directory]::Exists($job.Options.Storage)) {
        foreach ($file in (Get-ChildItem -LiteralPath $job.Options.Storage -Filter 'plan-*.json' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 30)) {
            try {
                $plan=Read-PkHealthJson $file.FullName
                $payload.plans+=@{id=$plan.Id;state=$plan.State;date=$plan.CreatedAt;count=@($plan.Items).Count;success=@($plan.Results|Where-Object State -eq 'COMMITTED').Count;failed=@($plan.Results|Where-Object State -in @('FAILED','ROLLED_BACK','ROLLBACK_REQUIRED')).Count}
            } catch { }
        }
    }
    # Health evidence can be deeper than ordinary collection records.
    $dates=@(@($payload.backups)+@($payload.vdjBackups)+@($payload.quarantine)|Where-Object {$_.state -notin @('FAILED','ROLLBACK_REQUIRED')}|ForEach-Object {$_.date}|Where-Object {$_}|Sort-Object -Descending)
    $payload.activity=@{Open=@($payload.plans|Where-Object {$_.state -in @('AWAITING_APPROVAL','APPROVED','REPAIR_RUNNING','CANCELLED')}).Count+$(if($job.SpecialPlan){1}else{0});Successful=(@($payload.plans|ForEach-Object {$_.success})|Measure-Object -Sum).Sum+@($payload.vdjBackups|Where-Object {$_.state -eq 'COMMITTED'}).Count+@($payload.quarantine|Where-Object {$_.state -eq 'COMMITTED'}).Count;LastBackup=$(if($dates.Count){$dates[0]}else{''})}
    if($web.Ready){$web.Control.CoreWebView2.PostWebMessageAsJson((ConvertTo-Json $payload -Depth 20 -Compress))}
}

function Start-WebHealthJob([string]$Operation,$Argument) {
    $job=$web.Health
    if ($job.Worker -or $state.Worker -or $libraryView.Diagnostic.Worker -or $web.Conversion.Worker -or $web.Export.Worker -or $web.TransitionScan.Worker -or ($updateCheck.Worker -and $updateCheck.Phase -eq 'Download')) { throw 'Zuerst den laufenden Vorgang beenden.' }
    if ($Operation -in @('repair','restore','vdj-repair','vdj-restore','quarantine','quarantine-restore') -and $transport.Enabled) { throw 'Vor Änderungen bitte die Wiedergabe stoppen.' }
    $job.Control=[hashtable]::Synchronized(@{Cancel=$false;Done=0;Total=0;Current='';Phase='preparing';Step='Prüfung wird vorbereitet …'})
    $job.Detail='';$job.Operation=$Operation;$job.LastProgress='';$job.Status='Prüfung wird vorbereitet …'
    Send-WebCollectionMessage @{type='health-progress';busy=$true;phase='preparing';status=$job.Status}
    $script={
        param($Directory,$Options,$Operation,$Argument,$Report,$Control)
        $ErrorActionPreference='Stop'
        . (Join-Path $Directory 'DJ-Sets-Download.ps1') -LibraryOnly -ToolRoot $Directory
        . (Join-Path $Directory 'DJ-Sets-Health.ps1')
        . (Join-Path $Directory 'DJ-Sets-HealthRepair.ps1')
        Assert-PkHealthOptions $Options
        switch($Operation){
            scan { Invoke-PkHealthScan $Options $Control -Incremental:([bool]$Argument) }
            plan { New-PkHealthPlan $Options $Report $Argument }
            repair { Invoke-PkHealthPlan $Options $Argument $Control }
            'restore-preview' { Get-PkHealthRestorePreview $Options $Argument }
            restore { Invoke-PkHealthRestore $Options $Argument $Control }
            'vdj-detect' { @{Candidates=@(Find-PkVdjDatabases $Options)} }
            'vdj-scan' { Invoke-PkVdjAnalysis $Options $Report $Control }
            'vdj-plan' { New-PkVdjPlan $Options $Argument.Analysis $Argument.Indices }
            'vdj-repair' { Invoke-PkVdjRepair $Options $Argument $Control }
            'vdj-restore-preview' { Get-PkVdjRestorePreview $Options $Argument }
            'vdj-restore' { Invoke-PkVdjRestore $Options $Argument }
            'quarantine-plan' { New-PkQuarantinePlan $Options $Report $Argument.Ids $Argument.References $Control }
            quarantine { Invoke-PkQuarantinePlan $Options $Argument $Control }
            'quarantine-restore-preview' { Get-PkQuarantineRestorePreview $Options $Argument }
            'quarantine-restore' { Invoke-PkQuarantineRestore $Options $Argument }
            'cover-recovery' { Get-PkHealthCoverRecovery $Options $Argument $Control }
        }
    }.ToString()
    try {
        $job.Worker=[PowerShell]::Create()
        [void]$job.Worker.AddScript($script).AddArgument($PSScriptRoot).AddArgument((@{}+$job.Options)).AddArgument($Operation).AddArgument($Argument).AddArgument($job.Report).AddArgument($job.Control)
        $job.Handle=$job.Worker.BeginInvoke()
    } catch {if($job.Worker){$job.Worker.Dispose();$job.Worker=$null};throw}
    Send-WebHealth
}

function Complete-WebHealth {
    $job=$web.Health
    if (!$job.Worker) {return}
    if (!$job.Handle.IsCompleted) {
        $progress="$($job.Control.Done)|$($job.Control.Total)|$($job.Control.Current)|$($job.Control.Phase)|$($job.Control.Step)|$($job.Control.FilePercent)"
        if($progress -cne $job.LastProgress){
            $job.LastProgress=$progress
            $job.Status=if($job.Control.Cancel){'Abbruch angefordert …'}elseif($job.Control.Phase -eq 'discovery'){'Musikdateien werden gesucht …'}elseif($job.Control.Phase -eq 'preparing'){'Prüfung wird vorbereitet …'}else{'Prüfung läuft …'}
            Send-WebCollectionMessage @{type='health-progress';busy=$true;done=$job.Control.Done;total=$job.Control.Total;current=$job.Control.Current;phase=$job.Control.Phase;step=$job.Control.Step;filePercent=$job.Control.FilePercent;status=$job.Status}
        }
        return
    }
    $operation=$job.Operation
    try {
        $result=@($job.Worker.EndInvoke($job.Handle)) | Select-Object -Last 1
        if($job.Worker.Streams.Error.Count){throw $job.Worker.Streams.Error[0]}
        if($job.Control.Cancel -and $operation -in @('plan','vdj-plan','quarantine-plan','vdj-scan','cover-recovery','vdj-restore-preview','quarantine-restore-preview')){throw 'Vorgang abgebrochen. Keine neue Freigabevorlage übernommen.'}
        switch($operation){
            scan {$job.Report=$result;$job.Plan=$null;$job.Dirty=$false;$count=@($result.Records).Count;$job.Status=if($result.State -eq 'CANCELLED'){"Prüfung abgebrochen. $count Dateien als Teilergebnis gespeichert."}elseif(!$result.Total){'Keine unterstützten Musikdateien gefunden.'}else{"Prüfung abgeschlossen. $count Dateien geprüft."};if(@($result.Warnings).Count){$job.Status+=' Einige Ordner oder Dateien konnten nicht vollständig geprüft werden. Hinweise beachten.'}}
            plan {$job.Plan=$result;$job.Status='Reparaturvorschau erstellt. Noch keine Musikdatei verändert.'}
            repair {$job.Plan=$null;$job.Dirty=$true;$job.Status="Reparatur beendet. $(@($result.Results|Where-Object State -eq 'COMMITTED').Count) erfolgreich, $(@($result.Results|Where-Object State -ne 'COMMITTED').Count) nicht übernommen. Ergebnisprotokolle prüfen und neu scannen.";Update-LibraryResults -Reload}
            'restore-preview' {$job.Restore=$result;$job.Status='Backups und aktueller Dateizustand geprüft. Wiederherstellung noch nicht ausgeführt.'}
            restore {$job.Restore=$null;$job.Dirty=$true;$job.Status="Wiederherstellung $($result.State). $($result.Count) Reparaturen zurückgesetzt. Bitte neu scannen.";Update-LibraryResults -Reload}
            'vdj-detect' {$job.Candidates=@($result.Candidates);$job.Status='Datenbankkandidaten erkannt. Gewünschte Datenbank selbst auswählen und Einstellungen speichern.'}
            'vdj-scan' {$job.Vdj=$result;$job.Status='VirtualDJ lesend analysiert. Nur fehlende oder ungültige Author-/Title-Werte sind Reparaturkandidaten.'}
            'vdj-plan' {$job.SpecialPlan=$result;$job.Status='VirtualDJ-Reparaturvorschau erstellt.'}
            'quarantine-plan' {$job.SpecialPlan=$result;$job.Status='Quarantänevorschau erstellt. PK-Verweise geprüft; externe Verweise vor Freigabe prüfen.'}
            'vdj-repair' {$job.SpecialPlan=$null;$job.Status="VirtualDJ-Datenbank: $($result.State). $($result.Error)";$job.Vdj=$null}
            quarantine {$job.SpecialPlan=$null;$job.Dirty=$true;$job.Status='Archivierung beendet. Quarantäne und Protokolle prüfen; Bibliothek erneut scannen.';Update-LibraryResults -Reload}
            'vdj-restore-preview' {$job.SpecialRestore=$result;$job.Status='Datenbankwiederherstellung geprüft.'}
            'quarantine-restore-preview' {$job.SpecialRestore=$result;$job.Status='Quarantänewiederherstellung geprüft.'}
            'vdj-restore' {$job.SpecialRestore=$null;$job.Vdj=$null;$job.Status='VirtualDJ-Datenbank wiederhergestellt.'}
            'quarantine-restore' {$job.SpecialRestore=$null;$job.Dirty=$true;$job.Status='Archivierte Audiodatei wiederhergestellt. Erneut scannen.';Update-LibraryResults -Reload}
            'cover-recovery' {$job.CoverRecovery=$result;$job.Status='Coverquelle vorbereitet. Noch keine Sammlungsdatei verändert.'}
        }
    } catch {Set-WebHealthError $_.Exception.Message}
    finally {$job.Worker.Dispose();$job.Worker=$null;$job.Handle=$null;try{Save-WebHealthOptions}catch{Set-WebHealthError $_.Exception.Message}}
    Send-WebHealth
    if($operation -eq 'plan' -and $job.Plan){
        $payload=@{type='health-plan';id=$job.Plan.Id;bytes=$job.Plan.EstimatedBytes;items=@($job.Plan.Items)}
        $web.Control.CoreWebView2.PostWebMessageAsJson((ConvertTo-Json $payload -Depth 20 -Compress))
    }
    if($operation -eq 'restore-preview' -and $job.Restore){Send-WebCollectionMessage @{type='health-restore-preview';id=$job.Restore.Id;paths=@($job.Restore.Items|ForEach-Object {$_.Manifest.Path})}}
    if($operation -in @('vdj-plan','quarantine-plan') -and $job.SpecialPlan){$web.Control.CoreWebView2.PostWebMessageAsJson((ConvertTo-Json @{type='health-special-plan';plan=$job.SpecialPlan} -Depth 20 -Compress))}
    if($operation -in @('vdj-restore-preview','quarantine-restore-preview') -and $job.SpecialRestore){Send-WebCollectionMessage @{type='health-special-restore';preview=$job.SpecialRestore}}
    if($operation -eq 'cover-recovery' -and $job.CoverRecovery){Send-WebCollectionMessage @{type='health-cover-recovered';cover=$job.CoverRecovery;image=(Get-PkHealthCoverPreview $job.CoverRecovery.Path)}}
}

function Invoke-WebHealth($Message) {
    $job=$web.Health
    try {
        switch($Message.command){
            health {Send-WebHealth}
            'health-mode' {if($Message.mode -in @('simple','advanced')){$job.Mode=$Message.mode;Save-WebHealthOptions};Send-WebHealth}
            'health-folder' {
                if($job.Worker){throw 'Zuerst die laufende Prüfung beenden.'}
                $picker=[Windows.Forms.FolderBrowserDialog]@{Description='Musikordner für die Bibliothekspflege wählen';SelectedPath=$job.Options.Root}
                try{if($picker.ShowDialog($form) -eq 'OK'){Assert-SafePath $picker.SelectedPath;$job.Options.Root=$picker.SelectedPath;$job.Report=$null;$job.Dirty=$false;Save-WebHealthOptions;$job.Status='Musikordner ausgewählt. Sammlung prüfen.'}}finally{$picker.Dispose()};Send-WebHealth
            }
            'health-options' {
                if($job.Worker){throw 'Während eines Vorgangs können Einstellungen nicht geändert werden.'}
                $next=@{}+$job.Options
                foreach($key in @('Root','Probe','FFmpeg','Storage','BackupRoot','QuarantineRoot','CoverRoot')) {
                    if($Message.values.$key -isnot [string] -or ![IO.Path]::IsPathRooted($Message.values.$key)){throw 'Bitte vollständige absolute Pfade angeben.'}
                    $next[$key]=[IO.Path]::GetFullPath($Message.values.$key)
                }
                $next.VideoSuffixes=@(([string]$Message.values.VideoSuffixes -split ',')|ForEach-Object {$_.Trim()}|Where-Object {$_})
                $limit=0
                if(![int]::TryParse([string]$Message.values.BackupLimitGB,[ref]$limit) -or $limit -lt 0 -or $limit -gt 100000){throw 'Backup-Limit zwischen 0 und 100000 GB angeben. 0 bedeutet unbegrenzt.'}
                $next.BackupLimitGB=$limit
                if($Message.values.VdjDatabase){Assert-SafePath $Message.values.VdjDatabase;$next.VdjDatabase=[IO.Path]::GetFullPath($Message.values.VdjDatabase)}else{$next.VdjDatabase=''}
                Assert-PkHealthOptions $next
                $saved=@{}+$next;$saved.Mode=$job.Mode;$saved.Dirty=($job.Dirty -and $next.Root -ieq $job.Options.Root);Write-PkHealthJson (Join-Path $config 'health-options.json') $saved
                if($next.Root -ine $job.Options.Root){$job.Report=$null;$job.Dirty=$false}
                $job.Options=$next;$job.Plan=$null;$job.Restore=$null;$job.SpecialPlan=$null;$job.SpecialRestore=$null;$job.Vdj=$null;$job.Status='Pflege-Einstellungen gespeichert.';Send-WebHealth
            }
            'health-scan' {if($job.Worker){throw 'Zuerst den laufenden Vorgang beenden.'};$job.Options.Deep=[bool]$Message.deep;Save-WebHealthOptions;Start-WebHealthJob 'scan' ([bool]$Message.incremental)}
            'health-cancel' {if($job.Control){$job.Control.Cancel=$true};$job.Status='Abbruch angefordert. Bereits abgeschlossene Dateien bleiben protokolliert.';Send-WebHealth}
            'health-resume-plan' {
                if($Message.id -cnotmatch '^[a-f0-9]{32}$'){throw 'Ungültige Auftrags-ID.'}
                if($job.Dirty){throw 'Vor Wiederaufnahme bitte neu scannen.'}
                $old=Read-PkHealthJson (Join-Path $job.Options.Storage "plan-$($Message.id).json")
                if($old.Root -ine $job.Options.Root){throw 'Auftrag gehört zu einer anderen Bibliothek.'}
                $done=@($old.Results | Where-Object {$_.State -eq 'COMMITTED'} | ForEach-Object {$_.Id})
                $requests=@(foreach($item in $old.Items){if($item.Id -notin $done){@{Id=$item.Id;Changes=$item.Changes;Json=$item.Json;CoverPath=$item.Cover.Path}}})
                if(!$requests.Count){throw 'Alle Dateien dieses Auftrags sind bereits erfolgreich abgeschlossen.'}
                $job.Plan=$null;Start-WebHealthJob 'plan' $requests
            }
            'health-record' {
                $record=$job.Report.Records|Where-Object Id -ceq $Message.id|Select-Object -First 1
                if(!$record){throw 'Eintrag nicht gefunden.'}
                $payload=@{type='health-record';record=$record}
                $web.Control.CoreWebView2.PostWebMessageAsJson((ConvertTo-Json $payload -Depth 20 -Compress))
            }
            'health-cover-preview' {
                $record=$job.Report.Records|Where-Object Id -ceq $Message.id|Select-Object -First 1
                $image=@($record.Covers) | Select-Object -Skip ([int]$Message.index) -First 1
                if(!$image -or !$image.Valid){throw 'Kein lesbares Cover.'}
                $null=Assert-PkHealthScope $image.Path $job.Options.Root
                if([IO.FileInfo]::new($image.Path).Length -gt 8MB){throw 'Cover ist zu groß für die Vorschau.'}
                $extension=[IO.Path]::GetExtension($image.Path).TrimStart('.');if($extension -eq 'jpg'){$extension='jpeg'}
                Send-WebCollectionMessage @{type='health-cover';image="data:image/$extension;base64,$([Convert]::ToBase64String([IO.File]::ReadAllBytes($image.Path)))"}
            }
            'health-cover-choose' {
                if($job.Worker){throw 'Zuerst Vorgang beenden.'}
                $picker=[Windows.Forms.OpenFileDialog]@{Filter='Cover (*.jpg;*.jpeg;*.png;*.webp)|*.jpg;*.jpeg;*.png;*.webp'}
                try{if($picker.ShowDialog($form) -eq 'OK'){Assert-SafePath $picker.FileName;Send-WebCollectionMessage @{type='health-cover-chosen';id=$Message.id;path=$picker.FileName;image=(Get-PkHealthCoverPreview $picker.FileName)}}}finally{$picker.Dispose()}
            }
            'health-plan' {
                if($job.Dirty){throw 'Nach Änderungen bitte neu scannen.'}
                foreach($request in @($Message.requests)){
                    $origin=if($request.CoverOrigin -eq 'KI-generiert'){'KI-generiert'}else{'Manueller Coverimport'}
                    if($job.CoverRecovery -and $job.CoverRecovery.Path -ieq $request.CoverPath -and (Get-PkHealthFileHash $request.CoverPath) -ceq $job.CoverRecovery.Hash){$origin=$job.CoverRecovery.Origin}
                    if($request -is [hashtable]){$request.CoverOrigin=$origin}else{$request|Add-Member NoteProperty CoverOrigin $origin -Force}
                }
                $job.Plan=$null;Start-WebHealthJob 'plan' @($Message.requests)
            }
            'health-vdj-detect' {Start-WebHealthJob 'vdj-detect' $null}
            'health-vdj-analyze' {Start-WebHealthJob 'vdj-scan' $null}
            'health-vdj-plan' {$job.SpecialPlan=$null;Start-WebHealthJob 'vdj-plan' @{Analysis=$job.Vdj;Indices=@($Message.indices)}}
            'health-quarantine-plan' {
                if($job.Dirty){throw 'Vor Archivierung bitte neu scannen.'}
                if($web.LibraryStateError){throw 'PK-Verweise konnten nicht gelesen werden.'}
                $references=@($web.LibraryState.Favorites)+@($web.LibraryState.Playlists|ForEach-Object {$_.Paths})
                $job.SpecialPlan=$null;Start-WebHealthJob 'quarantine-plan' @{Ids=@($Message.ids);References=$references}
            }
            'health-special-approve' {
                $plan=$job.SpecialPlan
                if(!$plan -or $Message.token -cne $plan.Id -or $Message.approved -ne $true){throw 'Passende ausdrückliche Freigabe erforderlich.'}
                $operation=if($plan.Type -eq 'VDJ'){'vdj-repair'}elseif($plan.Type -eq 'QUARANTINE'){'quarantine'}else{throw 'Unbekannter Reparaturtyp.'}
                if($plan.Type -eq 'QUARANTINE'){$plan.ExternalReferencesReviewed=($Message.referencesReviewed -eq $true);if(!$plan.ExternalReferencesReviewed){throw 'Externe Referenzen zuerst prüfen und bestätigen.'}}
                $plan.State='APPROVED';$job.SpecialPlan=$null;Start-WebHealthJob $operation $plan
            }
            'health-vdj-restore-preview' {$job.SpecialRestore=$null;Start-WebHealthJob 'vdj-restore-preview' $Message.id}
            'health-quarantine-restore-preview' {$job.SpecialRestore=$null;Start-WebHealthJob 'quarantine-restore-preview' $Message.id}
            'health-special-restore-approve' {
                $preview=$job.SpecialRestore
                if(!$preview -or $Message.token -cne $preview.Id -or $Message.approved -ne $true){throw 'Passende Wiederherstellungsfreigabe erforderlich.'}
                $operation=if($preview.Type -eq 'VDJ_RESTORE'){'vdj-restore'}elseif($preview.Type -eq 'QUARANTINE_RESTORE'){'quarantine-restore'}else{throw 'Unbekannte Wiederherstellung.'}
                $preview.State='APPROVED';$job.SpecialRestore=$null;Start-WebHealthJob $operation $preview
            }
            'health-cover-recover' {
                $record=$job.Report.Records|Where-Object {$_.Id -ceq $Message.id}|Select-Object -First 1
                if(!$record){throw 'Eintrag nicht gefunden.'}
                Start-WebHealthJob 'cover-recovery' $record
            }
            'health-approve' {
                if(!$job.Plan -or $Message.token -cne $job.Plan.Id -or $Message.approved -ne $true){throw 'Gültige ausdrückliche Freigabe erforderlich.'}
                $plan=$job.Plan;$plan.State='APPROVED';$job.Plan=$null
                Start-WebHealthJob 'repair' $plan
            }
            'health-restore-preview' {
                $directories=@(foreach($id in @($Message.ids)){
                    if($id -cnotmatch '^[a-f0-9]{32}/[A-F0-9]{64}$'){throw 'Ungültige Reparatur-ID.'}
                    Join-Path $job.Options.BackupRoot $id
                })
                $job.Restore=$null;Start-WebHealthJob 'restore-preview' $directories
            }
            'health-restore-approve' {
                if(!$job.Restore -or $Message.token -cne $job.Restore.Id -or $Message.approved -ne $true){throw 'Wiederherstellung muss ausdrücklich bestätigt werden.'}
                $restore=$job.Restore;$restore.State='APPROVED';$job.Restore=$null;Start-WebHealthJob 'restore' $restore
            }
            'health-export' {
                if(!$job.Report){throw 'Noch kein Bericht.'}
                $picker=[Windows.Forms.SaveFileDialog]@{Filter='JSON (*.json)|*.json|CSV (*.csv)|*.csv';FileName='Plattenkoffer-Health.json'}
                try {
                    if($picker.ShowDialog($form) -eq 'OK') {
                        Assert-SafePath $picker.FileName
                        if($picker.FilterIndex -eq 2){
                            $job.Report.Records | ForEach-Object {[pscustomobject]@{Path=$_.Path;Artist=$_.Tags.Artist;Title=$_.Tags.Title;Codes=($_.Codes -join ';');Codec=$_.Codec;Integrity=$_.Integrity;FileHash=$_.FileHash;AudioHashes=($_.AudioHashes -join ';')}} | Export-Csv -LiteralPath $picker.FileName -NoTypeInformation -Encoding UTF8
                        }else{Write-PkHealthAudit $picker.FileName $job.Report}
                        $job.Status='Scanbericht exportiert.';Send-WebHealth
                    }
                }finally{$picker.Dispose()}
            }
            'health-reports' {Assert-SafePath $job.Options.Storage;[void][IO.Directory]::CreateDirectory($job.Options.Storage);Start-Process explorer.exe -ArgumentList ('"'+$job.Options.Storage+'"')}
            'health-import-reference' {
                $picker=[Windows.Forms.OpenFileDialog]@{Filter='Referenzberichte / Sicherungen (*.csv;*.xml)|*.csv;*.xml'}
                try{if($picker.ShowDialog($form) -eq 'OK'){
                    Assert-SafePath $picker.FileName
                    if([IO.Path]::GetExtension($picker.FileName) -ieq '.xml'){
                        $database=Read-PkVdjDatabase $picker.FileName
                        $text="Lesende Referenzsicherung: $($picker.FileName)`r`nVersion $($database.Version), $($database.Songs.Count) Einträge, SHA-256 $($database.Hash).`r`nOhne verifiziertes Vorher-/Nachher-Journal keine automatische Wiederherstellung auf die aktive Datenbank."
                    }else{
                        if([IO.FileInfo]::new($picker.FileName).Length -gt 16MB){throw 'Bericht zu groß.'}
                        $rows=@(Import-Csv -LiteralPath $picker.FileName -Delimiter ';' -Encoding UTF8)
                        if(!$rows.Count -or 'Path' -notin $rows[0].PSObject.Properties.Name -or 'OldArtist' -notin $rows[0].PSObject.Properties.Name -or 'NewTitle' -notin $rows[0].PSObject.Properties.Name){throw 'Kein eindeutig erkanntes VDJ-v1.3-Referenzformat.'}
                        $text="Lesender VDJ-v1.3-Referenzbericht: $($picker.FileName)`r`n$($rows.Count) Datensätze. Keine Änderungen ausgeführt.`r`n"+($rows|Select-Object Path,OldArtist,OldTitle,NewArtist,NewTitle,Status|Format-Table -Wrap|Out-String -Width 160)
                    }
                    Send-WebCollectionMessage @{type='health-reference-report';text=$text}
                }}finally{$picker.Dispose()}
            }
            'health-export-repairs' {
                if($job.Worker){throw 'Zuerst den laufenden Vorgang beenden.'}
                $records=@(Get-PkHealthAllJournals $job.Options)
                $picker=[Windows.Forms.SaveFileDialog]@{Filter='JSON (*.json)|*.json|CSV (*.csv)|*.csv';FileName='Plattenkoffer-Reparaturen.json'}
                try{if($picker.ShowDialog($form) -eq 'OK'){
                    Assert-SafePath $picker.FileName
                    if($picker.FilterIndex -eq 2){
                        $records|ForEach-Object {ConvertTo-PkHealthRepairCsv $_}|Export-Csv -LiteralPath $picker.FileName -NoTypeInformation -Encoding UTF8
                    }else{Write-PkHealthAudit $picker.FileName @{SchemaVersion=1;Repairs=$records}}
                    $job.Status='Reparaturberichte exportiert.';Send-WebHealth
                }}finally{$picker.Dispose()}
            }
        }
    }catch{Set-WebHealthError $_.Exception.Message;Send-WebHealth}
}

function Set-WebHealthError([string]$Detail) {
    $web.Health.Detail=$Detail
    $web.Health.Status=if(![IO.Directory]::Exists($web.Health.Options.Root)){'Der Musikordner ist nicht erreichbar. Bitte „Ordner ändern“ wählen und einen erreichbaren Musikordner angeben.'}elseif(![IO.File]::Exists($web.Health.Options.Probe) -or ![IO.File]::Exists($web.Health.Options.FFmpeg)){'Ein Prüfprogramm fehlt. Unter Erweitert → Ordner, Werkzeuge und Scanoptionen die Programmpfade korrigieren.'}elseif($Detail -match 'Verknüpfung|Pfad|Ordner|path'){'Ein gewählter Pfad kann nicht sicher verwendet werden. Unter Erweitert → Ordner, Werkzeuge und Scanoptionen einen lokalen Ordner ohne Verknüpfung wählen.'}else{'Die Prüfung konnte nicht abgeschlossen werden. Bitte Diagnose öffnen, Ursache prüfen und erneut versuchen. '+$(if($Detail -match 'laufenden Vorgang|Wiedergabe'){$Detail}else{''})}
    if(Get-Command Write-AppError -ErrorAction SilentlyContinue){Write-AppError 'Bibliothekspflege' $Detail}
}

function Save-WebHealthOptions {
    $saved=@{}+$web.Health.Options;$saved.Mode=$web.Health.Mode;$saved.Dirty=[bool]$web.Health.Dirty
    Write-PkHealthJson (Join-Path $config 'health-options.json') $saved
}

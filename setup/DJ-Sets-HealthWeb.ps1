function Initialize-WebHealth {
    $web.Health=@{Worker=$null;Handle=$null;Control=$null;Operation='';Report=$null;Plan=$null;Restore=$null;Status='Noch kein Scan. Musikdateien werden beim Scan nicht verändert.';LastProgress='';Dirty=$false}
    $web.Health.Options=@{Root=$settings.MusicRoot;Probe=$probe;FFmpeg=$ffmpeg;Storage=(Join-Path (Split-Path -Parent $config) 'health');BackupRoot=(Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Plattenkoffer-Backups');BackupLimitGB=20;Deep=$false;VideoSuffixes=@('Official Video','Official Audio','Music Video','Lyrics Video','HD','HQ','4K')}
    $path=Join-Path $config 'health-options.json'
    if ([IO.File]::Exists($path)) {
        try {
            $saved=Read-PkHealthJson $path
            foreach($key in @('Root','Probe','FFmpeg','Storage','BackupRoot','VideoSuffixes')){if($saved.$key){$web.Health.Options[$key]=$saved.$key}}
            if($null -ne $saved.BackupLimitGB){$web.Health.Options.BackupLimitGB=[double]$saved.BackupLimitGB}
        } catch { $web.Health.Status='Gespeicherte Pflege-Einstellungen konnten nicht gelesen werden.' }
    }
    $path=Join-Path $web.Health.Options.Storage 'scan.json'
    if ([IO.File]::Exists($path)) { try { $report=Read-PkHealthJson $path 256MB;if($report.Root -ieq $web.Health.Options.Root){$web.Health.Report=$report} } catch { $web.Health.Status='Scanbericht konnte nicht gelesen werden. Erneuter Scan erforderlich.' } }
}

function Send-WebHealth {
    $job=$web.Health
    $payload=@{type='health';busy=[bool]$job.Worker;operation=$job.Operation;status=$job.Status;options=$job.Options;summary=$null;rows=@();backups=@();plans=@();lastScan='';scanState='';warnings=@();dirty=[bool]$job.Dirty}
    if ($job.Control) { $payload.progress=@{done=$job.Control.Done;total=$job.Control.Total;current=$job.Control.Current} }
    if ($job.Report) {
        $payload.summary=Get-PkHealthSummary $job.Report
        $payload.lastScan=$job.Report.EndedAt;$payload.scanState=$job.Report.State;$payload.warnings=@($job.Report.Warnings)
        $payload.rows=@(foreach($record in $job.Report.Records){
            @{id=$record.Id;path=$record.Path;kind=$record.Kind;tags=$record.Tags;codes=@($record.Codes);notes=@($record.Notes);codec=$record.Codec;container=$record.Container;duration=$record.Duration;bitrate=$record.Bitrate;rate=$record.SampleRate;channels=$record.Channels;size=$record.Size;lossless=$record.Lossless;integrity=$record.Integrity;repairable=$record.Repairable;coverCount=@($record.Covers).Count;embeddedCover=[bool]$record.EmbeddedCover;duplicates=@($record.DuplicateOf)}
        })
    }
    # Index journal headers only; no VirtualDJ database access and no executable content.
    if (!$job.Worker -and [IO.Directory]::Exists($job.Options.BackupRoot)) {
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
    if (!$job.Worker -and [IO.Directory]::Exists($job.Options.Storage)) {
        foreach ($file in (Get-ChildItem -LiteralPath $job.Options.Storage -Filter 'plan-*.json' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 30)) {
            try {
                $plan=Read-PkHealthJson $file.FullName
                $payload.plans+=@{id=$plan.Id;state=$plan.State;date=$plan.CreatedAt;count=@($plan.Items).Count;success=@($plan.Results|Where-Object State -eq 'COMMITTED').Count;failed=@($plan.Results|Where-Object State -in @('FAILED','ROLLED_BACK','ROLLBACK_REQUIRED')).Count}
            } catch { }
        }
    }
    # Health evidence can be deeper than ordinary collection records.
    if($web.Ready){$web.Control.CoreWebView2.PostWebMessageAsJson((ConvertTo-Json $payload -Depth 20 -Compress))}
}

function Start-WebHealthJob([string]$Operation,$Argument) {
    $job=$web.Health
    if ($job.Worker -or $state.Worker -or $libraryView.Diagnostic.Worker -or $web.Conversion.Worker -or $web.Export.Worker -or $web.TransitionScan.Worker -or ($updateCheck.Worker -and $updateCheck.Phase -eq 'Download')) { throw 'Zuerst den laufenden Vorgang beenden.' }
    if ($Operation -in @('repair','restore') -and $transport.Enabled) { throw 'Vor Änderungen bitte die Wiedergabe stoppen.' }
    Assert-PkHealthOptions $job.Options
    $job.Control=[hashtable]::Synchronized(@{Cancel=$false;Done=0;Total=0;Current=''})
    $job.Operation=$Operation;$job.LastProgress='';$job.Status='Vorgang wird gestartet …'
    $script={
        param($Directory,$Options,$Operation,$Argument,$Report,$Control)
        $ErrorActionPreference='Stop'
        . (Join-Path $Directory 'DJ-Sets-Download.ps1') -LibraryOnly -ToolRoot $Directory
        . (Join-Path $Directory 'DJ-Sets-Health.ps1')
        . (Join-Path $Directory 'DJ-Sets-HealthRepair.ps1')
        switch($Operation){
            scan { Invoke-PkHealthScan $Options $Control -Incremental:([bool]$Argument) }
            plan { New-PkHealthPlan $Options $Report $Argument }
            repair { Invoke-PkHealthPlan $Options $Argument $Control }
            'restore-preview' { Get-PkHealthRestorePreview $Options $Argument }
            restore { Invoke-PkHealthRestore $Options $Argument $Control }
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
        $progress="$($job.Control.Done)|$($job.Control.Total)|$($job.Control.Current)"
        if($progress -cne $job.LastProgress){
            $job.LastProgress=$progress
            Send-WebCollectionMessage @{type='health-progress';done=$job.Control.Done;total=$job.Control.Total;current=$job.Control.Current;status=$(if($job.Control.Cancel){'Abbruch angefordert …'}else{'Vorgang läuft …'})}
        }
        return
    }
    $operation=$job.Operation
    try {
        $result=@($job.Worker.EndInvoke($job.Handle)) | Select-Object -Last 1
        if($job.Worker.Streams.Error.Count){throw $job.Worker.Streams.Error[0]}
        switch($operation){
            scan {$job.Report=$result;$job.Plan=$null;$job.Dirty=$false;$job.Status="Scan $($result.State). $(@($result.Records).Count) Dateien geprüft."}
            plan {$job.Plan=$result;$job.Status='Reparaturvorschau erstellt. Noch keine Musikdatei verändert.'}
            repair {$job.Plan=$null;$job.Dirty=$true;$job.Status="Reparatur beendet. $(@($result.Results|Where-Object State -eq 'COMMITTED').Count) erfolgreich, $(@($result.Results|Where-Object State -ne 'COMMITTED').Count) nicht übernommen. Ergebnisprotokolle prüfen und neu scannen.";Update-LibraryResults -Reload}
            'restore-preview' {$job.Restore=$result;$job.Status='Backups und aktueller Dateizustand geprüft. Wiederherstellung noch nicht ausgeführt.'}
            restore {$job.Restore=$null;$job.Dirty=$true;$job.Status="Wiederherstellung $($result.State). $($result.Count) Reparaturen zurückgesetzt. Bitte neu scannen.";Update-LibraryResults -Reload}
        }
    } catch {$job.Status=$_.Exception.Message}
    finally {$job.Worker.Dispose();$job.Worker=$null;$job.Handle=$null}
    Send-WebHealth
    if($operation -eq 'plan' -and $job.Plan){
        $payload=@{type='health-plan';id=$job.Plan.Id;bytes=$job.Plan.EstimatedBytes;items=@($job.Plan.Items)}
        $web.Control.CoreWebView2.PostWebMessageAsJson((ConvertTo-Json $payload -Depth 20 -Compress))
    }
    if($operation -eq 'restore-preview' -and $job.Restore){Send-WebCollectionMessage @{type='health-restore-preview';id=$job.Restore.Id;paths=@($job.Restore.Items|ForEach-Object {$_.Manifest.Path})}}
}

function Invoke-WebHealth($Message) {
    $job=$web.Health
    try {
        switch($Message.command){
            health {Send-WebHealth}
            'health-options' {
                if($job.Worker){throw 'Während eines Vorgangs können Einstellungen nicht geändert werden.'}
                $next=@{}+$job.Options
                foreach($key in @('Root','Probe','FFmpeg','Storage','BackupRoot')) {
                    if($Message.values.$key -isnot [string] -or ![IO.Path]::IsPathRooted($Message.values.$key)){throw 'Bitte vollständige absolute Pfade angeben.'}
                    $next[$key]=[IO.Path]::GetFullPath($Message.values.$key)
                }
                $next.VideoSuffixes=@(([string]$Message.values.VideoSuffixes -split ',')|ForEach-Object {$_.Trim()}|Where-Object {$_})
                $limit=0
                if(![int]::TryParse([string]$Message.values.BackupLimitGB,[ref]$limit) -or $limit -lt 0 -or $limit -gt 100000){throw 'Backup-Limit zwischen 0 und 100000 GB angeben. 0 bedeutet unbegrenzt.'}
                $next.BackupLimitGB=$limit
                Assert-PkHealthOptions $next
                Write-PkHealthJson (Join-Path $config 'health-options.json') $next
                if($next.Root -ine $job.Options.Root){$job.Report=$null;$job.Dirty=$false}
                $job.Options=$next;$job.Plan=$null;$job.Restore=$null;$job.Status='Pflege-Einstellungen gespeichert.';Send-WebHealth
            }
            'health-scan' {$job.Options.Deep=[bool]$Message.deep;Start-WebHealthJob 'scan' ([bool]$Message.incremental)}
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
                try{if($picker.ShowDialog($form) -eq 'OK'){Assert-SafePath $picker.FileName;Send-WebCollectionMessage @{type='health-cover-chosen';path=$picker.FileName}}}finally{$picker.Dispose()}
            }
            'health-plan' {if($job.Dirty){throw 'Nach Änderungen bitte neu scannen.'};$job.Plan=$null;Start-WebHealthJob 'plan' @($Message.requests)}
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
            'health-export-repairs' {
                if($job.Worker){throw 'Zuerst den laufenden Vorgang beenden.'}
                $records=@(foreach($plan in @(Get-ChildItem -LiteralPath $job.Options.BackupRoot -Directory -ErrorAction SilentlyContinue|Where-Object Name -match '^[a-f0-9]{32}$')){
                    Assert-SafePath $plan.FullName
                    foreach($folder in (Get-ChildItem -LiteralPath $plan.FullName -Directory|Where-Object Name -match '^[A-F0-9]{64}$')){
                        $path=Join-Path $folder.FullName 'repair.json'
                        if([IO.File]::Exists($path)){Read-PkHealthJson $path}
                    }
                })
                $picker=[Windows.Forms.SaveFileDialog]@{Filter='JSON (*.json)|*.json|CSV (*.csv)|*.csv';FileName='Plattenkoffer-Reparaturen.json'}
                try{if($picker.ShowDialog($form) -eq 'OK'){
                    Assert-SafePath $picker.FileName
                    if($picker.FilterIndex -eq 2){
                        $records|ForEach-Object{[pscustomobject]@{PlanId=$_.PlanId;Id=$_.Id;Path=$_.Path;State=$_.State;Method=$_.Method;StartedAt=$_.StartedAt;EndedAt=$_.EndedAt;FileBefore=$_.FileBefore;FileAfter=$_.FileAfter;AudioBefore=($_.AudioBefore -join ';');AudioAfter=($_.AudioAfter -join ';');Changes=(ConvertTo-Json (Protect-PkHealthAuditValue $_.Changes) -Compress);Error=$_.Error}}|Export-Csv -LiteralPath $picker.FileName -NoTypeInformation -Encoding UTF8
                    }else{Write-PkHealthAudit $picker.FileName @{SchemaVersion=1;Repairs=$records}}
                    $job.Status='Reparaturberichte exportiert.';Send-WebHealth
                }}finally{$picker.Dispose()}
            }
        }
    }catch{$job.Status=$_.Exception.Message;Send-WebHealth}
}

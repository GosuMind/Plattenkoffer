function Read-PkHealthJournal([string]$Path) {
    $record=Read-PkHealthJson $Path;$record|Add-Member NoteProperty JournalPath $Path -Force;$record
}
function ConvertTo-PkHealthRepairCsv($Record) {
    [pscustomobject]@{Type=$(if($Record.Type){$Record.Type}else{'AUDIO'});JobId=$(if($Record.PlanId){$Record.PlanId}elseif($Record.JobId){$Record.JobId}else{$Record.Id});Id=$Record.Id;Path=$Record.Path;State=$Record.State;Method=$Record.Method;StartedAt=$Record.StartedAt;EndedAt=$Record.EndedAt;FileBefore=$(if($Record.FileBefore){$Record.FileBefore}elseif($Record.BeforeHash){$Record.BeforeHash}else{$Record.Hash});FileAfter=$(if($Record.FileAfter){$Record.FileAfter}else{$Record.AfterHash});AudioBefore=($Record.AudioBefore -join ';');AudioAfter=($Record.AudioAfter -join ';');Changes=(ConvertTo-Json (Protect-PkHealthAuditValue $(if($Record.Items){$Record.Items}else{$Record.Changes})) -Depth 15 -Compress);JournalPath=$Record.JournalPath;Backup=$Record.Backup;Error=$Record.Error}
}
function Get-PkHealthAllJournals($Options) {
    if([IO.Directory]::Exists($Options.BackupRoot)){
        foreach($folder in Get-ChildItem -LiteralPath $Options.BackupRoot -Directory|Where-Object Name -match '^[a-f0-9]{32}$'){
            Assert-SafePath $folder.FullName
            foreach($entry in Get-ChildItem -LiteralPath $folder.FullName -Directory|Where-Object Name -match '^[A-F0-9]{64}$'){
                $path=Join-Path $entry.FullName 'repair.json';if([IO.File]::Exists($path)){Read-PkHealthJournal $path}
            }
        }
        $vdj=Join-Path $Options.BackupRoot 'vdj'
        if([IO.Directory]::Exists($vdj)){Assert-SafePath $vdj;foreach($folder in Get-ChildItem -LiteralPath $vdj -Directory|Where-Object Name -match '^[a-f0-9]{32}$'){$path=Join-Path $folder.FullName 'repair.json';if([IO.File]::Exists($path)){Read-PkHealthJournal $path}}}
    }
    if($Options.QuarantineRoot -and [IO.Directory]::Exists($Options.QuarantineRoot)){
        Assert-SafePath $Options.QuarantineRoot
        foreach($folder in Get-ChildItem -LiteralPath $Options.QuarantineRoot -Directory|Where-Object Name -match '^[a-f0-9]{32}$'){
            Assert-SafePath $folder.FullName
            foreach($entry in Get-ChildItem -LiteralPath $folder.FullName -Directory|Where-Object Name -match '^[A-F0-9]{64}$'){$path=Join-Path $entry.FullName 'quarantine.json';if([IO.File]::Exists($path)){Read-PkHealthJournal $path}}
        }
    }
}

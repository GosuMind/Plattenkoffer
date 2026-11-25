# Version-scoped VirtualDJ 2026 DOM workaround. No regex editing of XML content.
function Test-PkVdjRunning {
    @(Get-Process -ErrorAction Stop | Where-Object {$_.ProcessName -match '^virtualdj'}).Count -gt 0
}
function Assert-PkVdjClosed {
    if(Test-PkVdjRunning){throw 'VirtualDJ vollständig schließen, bevor die Datenbank repariert oder wiederhergestellt wird.'}
}
function Read-PkVdjDatabase([string]$Path) {
    Assert-SafePath $Path
    if([IO.FileInfo]::new($Path).Length -gt 256MB){throw 'VirtualDJ-Datenbank ist zu groß.'}
    $bytes=[IO.File]::ReadAllBytes($Path)
    if($bytes.Length -gt 256MB){throw 'VirtualDJ-Datenbank ist zu groß.'}
    $bom=$bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf
    $offset=if($bom){3}else{0}
    $algorithm=[Security.Cryptography.SHA256]::Create()
    try{$byteHash=[BitConverter]::ToString($algorithm.ComputeHash($bytes)).Replace('-','')}finally{$algorithm.Dispose()}
    $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes,$offset,$bytes.Length-$offset)
    $document=[Xml.XmlDocument]::new();$document.PreserveWhitespace=$true;$document.XmlResolver=$null
    $reader=[Xml.XmlTextReader]::new([IO.StringReader]::new($text));$reader.DtdProcessing='Prohibit';$reader.XmlResolver=$null;$reader.Normalization=$false
    try{$document.Load($reader)}finally{$reader.Dispose()}
    if($document.DocumentElement.Name -cne 'VirtualDJ_Database'){throw 'Keine erkannte VirtualDJ-Datenbank.'}
    $version=$document.DocumentElement.GetAttribute('Version')
    $supported=$version -ceq '2026' -and !$document.DocumentElement.NamespaceURI
    if($document.FirstChild -is [Xml.XmlDeclaration] -and $document.FirstChild.Encoding -and $document.FirstChild.Encoding -ine 'utf-8'){$supported=$false}
    $songs=@($document.DocumentElement.SelectNodes('./Song'))
    $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($song in $songs){
        if(!$song.HasAttribute('FilePath') -or @($song.SelectNodes('./Tags')).Count -gt 1 -or @($song.ChildNodes|Where-Object {$_.NodeType -eq 'Element' -and $_.NamespaceURI}).Count -or !$paths.Add($song.GetAttribute('FilePath'))){$supported=$false}
    }
    if((Get-PkHealthFileHash $Path) -cne $byteHash){throw 'Datenbank während des Lesens verändert. Analyse wiederholen.'}
    @{Path=[IO.Path]::GetFullPath($Path);Document=$document;Bom=$bom;CRLF=$text.Contains("`r`n");Version=$version;Writable=$supported;Songs=$songs;Hash=$byteHash}
}
function Write-PkVdjXml($Database,[Xml.XmlDocument]$Document,[string]$Path) {
    Assert-SafePath $Path
    $settings=[Xml.XmlWriterSettings]::new();$settings.Encoding=[Text.UTF8Encoding]::new([bool]$Database.Bom);$settings.Indent=$false
    $settings.NewLineHandling=[Xml.NewLineHandling]::None;$settings.NewLineChars=if($Database.CRLF){"`r`n"}else{"`n"}
    $settings.OmitXmlDeclaration=$true
    $writer=[Xml.XmlWriter]::Create($Path,$settings)
    try{foreach($node in $Document.ChildNodes){if($node -is [Xml.XmlDeclaration]){$writer.WriteRaw($node.OuterXml)}else{$node.WriteTo($writer)}}}finally{$writer.Dispose()}
    $loaded=Read-PkVdjDatabase $Path
    if($loaded.Bom -ne $Database.Bom -or $loaded.Document.OuterXml -cne $Document.OuterXml){throw 'VirtualDJ-XML wurde beim Schreiben verändert.'}
    $loaded
}
function Find-PkVdjDatabases($Options) {
    $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($path in @($Options.VdjDatabase,(Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'VirtualDJ/database.xml'))){if($path){[void]$paths.Add($path)}}
    foreach($homePath in @($env:OneDrive,$env:OneDriveConsumer,$env:OneDriveCommercial)){
        if($homePath){[void]$paths.Add((Join-Path $homePath 'Documents/VirtualDJ/database.xml'))}
    }
    foreach($appPath in @($env:APPDATA,$env:LOCALAPPDATA)){if($appPath){[void]$paths.Add((Join-Path $appPath 'VirtualDJ/database.xml'))}}
    foreach($drive in [IO.DriveInfo]::GetDrives()){
        if($drive.IsReady -and $drive.DriveType -in @('Fixed','Removable')){[void]$paths.Add((Join-Path $drive.RootDirectory.FullName 'VirtualDJ/database.xml'))}
    }
    foreach($path in $paths){
        if(![IO.File]::Exists($path)){continue}
        try{
            $database=Read-PkVdjDatabase $path;$base=[IO.Path]::GetFullPath($Options.Root).TrimEnd('\')+'\'
            $matches=@($database.Songs|Where-Object {$_.GetAttribute('FilePath').StartsWith($base,[StringComparison]::OrdinalIgnoreCase)}).Count
            @{Path=$database.Path;Version=$database.Version;Entries=$database.Songs.Count;LibraryMatches=$matches;Writable=$database.Writable;Hash=$database.Hash}
        }catch{@{Path=$path;Version='unbekannt';Entries=0;LibraryMatches=0;Writable=$false;Error=$_.Exception.Message}}
    }
}
function Test-PkVdjInvalidValue([string]$Value,[string]$Field,[string]$Path) {
    !$Value.Trim() -or $Value -match '[\x00-\x1f]' -or $Value.Contains([string][char]0xfffd) -or ($Field -eq 'Title' -and $Value -match '^(audio|source|download)$')
}
function Invoke-PkVdjAnalysis($Options,$Report,$Control) {
    if(!$Options.VdjDatabase){throw 'Eine Datenbank ausdrücklich auswählen und Pflege-Einstellungen speichern.'}
    $database=Read-PkVdjDatabase $Options.VdjDatabase
    if(!$Report -or $Report.Root -ine $Options.Root){throw 'Zuerst die gewählte Musikbibliothek scannen.'}
    $known=@{};foreach($record in $Report.Records){$known[$record.Path]=$record}
    $found=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $rows=[Collections.Generic.List[object]]::new();$index=0;$base=[IO.Path]::GetFullPath($Options.Root).TrimEnd('\')+'\'
    foreach($song in $database.Songs){
        if($Control -and $Control.Cancel){throw [OperationCanceledException]::new('VirtualDJ-Analyse abgebrochen.')}
        $path=$song.GetAttribute('FilePath');$row=@{Index=$index;Path=$path;Codes=@();Audio=@{};Current=@{};Changes=@{};Writable=$false}
        if($Control){$Control.Current=$path;$Control.Done=$index;$Control.Total=$database.Songs.Count}
        $index++
        if(!$path.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){continue}
        $tags=$song.SelectSingleNode('./Tags')
        $row.Current=@{Author=$(if($tags){$tags.GetAttribute('Author')}else{''});Title=$(if($tags){$tags.GetAttribute('Title')}else{''})}
        if(![IO.File]::Exists($path)){$row.Codes+= 'VDJ_DATABASE_ORPHAN_ENTRY';$rows.Add($row);continue}
        if(!$known.ContainsKey($path)){$row.Codes+='VDJ_TAG_COMPATIBILITY_REVIEW';$rows.Add($row);continue}
        [void]$found.Add($path)
        try{
            $null=Assert-PkHealthScope $path $Options.Root
            $sourceHash=Get-PkHealthFileHash $path
            $audio=Get-PkHealthTags (Get-PkHealthProbe $path $Options $Control)
            if((Get-PkHealthFileHash $path) -cne $sourceHash){throw 'Audioquelle während des Lesens verändert.'}
            $row.Audio=$audio;$row.AudioFileHash=$sourceHash
            foreach($pair in @(@('Artist','Author'),@('Title','Title'))){
                $field=$pair[0];$attribute=$pair[1];$current=[string]$row.Current[$attribute];$value=[string]$audio[$field]
                if(!$value -or (Test-PkHealthSuspiciousUnicode $value)){$row.Codes+='AUDIO_METADATA_MISSING';continue}
                if(Test-PkVdjInvalidValue $current $attribute $path){$row.Changes[$attribute]=$value;$row.Codes+= $(if(!$current){'VDJ_METADATA_MISSING'}else{'VDJ_METADATA_STALE'})}
                elseif(!(Test-PkHealthFieldEquivalent $field $current $value $known[$path].Pk)){$row.Codes+='VDJ_METADATA_CONFLICT'}
            }
            $row.Writable=$database.Writable -and $row.Changes.Count -gt 0 -and 'VDJ_METADATA_CONFLICT' -notin $row.Codes -and 'AUDIO_METADATA_MISSING' -notin $row.Codes
        }catch{if($Control -and $Control.Cancel){throw};$row.Codes+='VDJ_TAG_COMPATIBILITY_REVIEW';$row.Error=$_.Exception.Message}
        $row.Codes=@($row.Codes|Select-Object -Unique);$rows.Add($row)
    }
    foreach($record in $Report.Records){if(!$found.Contains($record.Path)){$rows.Add(@{Index=-1;Path=$record.Path;Codes=@('VDJ_DATABASE_MISSING_ENTRY');Changes=@{};Current=@{};Audio=$record.Tags;Writable=$false})}}
    $result=@{Type='VDJ';Id=[guid]::NewGuid().ToString('N');Database=$database.Path;DatabaseHash=$database.Hash;Version=$database.Version;Writable=$database.Writable;Entries=$database.Songs.Count;Root=$Options.Root;Rows=@($rows.ToArray());ScannedAt=[datetime]::UtcNow.ToString('o')}
    Write-PkHealthAudit (Join-Path $Options.Storage 'vdj-scan.json') $result;$result
}
function New-PkVdjPlan($Options,$Analysis,[int[]]$Indices) {
    if(!$Analysis -or !$Analysis.Writable -or $Analysis.Database -ine $Options.VdjDatabase -or $Analysis.Root -ine $Options.Root){throw 'Keine schreibend freigegebene VirtualDJ-2026-Analyse vorhanden.'}
    $database=Read-PkVdjDatabase $Options.VdjDatabase
    if($database.Hash -cne $Analysis.DatabaseHash){throw 'Datenbank seit der Analyse geändert.'}
    $items=@(foreach($index in @($Indices|Select-Object -Unique)){
        $row=$Analysis.Rows|Where-Object {$_.Index -eq $index -and $_.Writable}|Select-Object -First 1
        if(!$row){throw 'Eintrag ist nicht zur automatischen Datenbankkorrektur freigegeben.'}
        $song=$database.Songs[$index];$tag=$song.SelectSingleNode('./Tags');$before=@{}
        if($song.GetAttribute('FilePath') -cne $row.Path){throw 'Song-Zuordnung seit der Analyse verändert.'}
        foreach($key in $row.Changes.Keys){$before[$key]=@{Present=($tag -and $tag.HasAttribute($key));Value=$(if($tag){$tag.GetAttribute($key)}else{''})}}
        @{Index=$index;Path=$row.Path;AudioFileHash=$row.AudioFileHash;Before=$before;Changes=$row.Changes;TagsExisted=($null -ne $tag)}
    })
    if(!$items.Count){throw 'Keine reparierbaren VirtualDJ-Einträge ausgewählt.'}
    $plan=@{Type='VDJ';Id=[guid]::NewGuid().ToString('N');Root=$Options.Root;Database=$database.Path;DatabaseHash=$database.Hash;Version=$database.Version;State='AWAITING_APPROVAL';Items=$items;CreatedAt=[datetime]::UtcNow.ToString('o');Bytes=[IO.FileInfo]::new($database.Path).Length}
    Write-PkHealthAudit (Join-Path $Options.Storage "vdj-plan-$($plan.Id).json") $plan;$plan
}
function Assert-PkVdjAllowedChanges($Original,$Changed,$Items) {
    if($Original.Songs.Count -ne $Changed.Songs.Count){throw 'Anzahl der VirtualDJ-Einträge verändert.'}
    $compare=[Xml.XmlDocument]$Changed.Document.CloneNode($true)
    $songs=@($compare.DocumentElement.SelectNodes('./Song'))
    for($i=0;$i -lt $songs.Count;$i++){if($songs[$i].GetAttribute('FilePath') -cne $Original.Songs[$i].GetAttribute('FilePath')){throw 'Reihenfolge oder Dateipfade verändert.'}}
    foreach($item in $Items){
        $tag=$songs[$item.Index].SelectSingleNode('./Tags')
        foreach($key in $item.Changes.Keys){
            if($key -cnotin @('Author','Title') -or !$tag -or $tag.GetAttribute($key) -cne $item.Changes[$key]){throw 'VirtualDJ-Änderung nicht korrekt geschrieben.'}
            if($item.Before[$key].Present){$tag.SetAttribute($key,$item.Before[$key].Value)}else{$tag.RemoveAttribute($key)}
        }
        if(!$item.TagsExisted){[void]$songs[$item.Index].RemoveChild($tag)}
    }
    if($compare.OuterXml -cne $Original.Document.OuterXml){throw 'XML-Inhaltsvergleich fehlgeschlagen: nicht freigegebene Daten verändert.'}
}
function Invoke-PkVdjRepair($Options,$Plan,$Control) {
    Assert-PkVdjClosed
    if($Plan.State -ne 'APPROVED' -or $Plan.Database -ine $Options.VdjDatabase -or $Plan.Root -ine $Options.Root){throw 'Passende ausdrückliche Datenbankfreigabe fehlt.'}
    $original=Read-PkVdjDatabase $Plan.Database
    if(!$original.Writable -or $original.Hash -cne $Plan.DatabaseHash){throw 'Datenbankversion oder Dateistand nicht freigegeben.'}
    foreach($item in $Plan.Items){$null=Assert-PkHealthScope $item.Path $Options.Root;if((Get-PkHealthFileHash $item.Path) -cne $item.AudioFileHash){throw 'Audiodatei seit der Vorschau geändert.'}}
    Assert-PkHealthSpace $Options.BackupRoot ($Plan.Bytes*3)
    $directory=Join-Path $Options.BackupRoot "vdj/$($Plan.Id)";Assert-SafePath $directory
    if([IO.Directory]::Exists($directory)){throw 'Dieser Datenbankauftrag wurde bereits begonnen.'}
    [void][IO.Directory]::CreateDirectory($directory)
    $backup=Join-Path $directory 'database.xml';$journal=Join-Path $directory 'repair.json'
    $temp=$Plan.Database+'.pk-vdj-'+$Plan.Id+'.tmp';$swap=$Plan.Database+'.pk-vdj-'+$Plan.Id+'.bak'
    foreach($path in @($temp,$swap)){Assert-SafePath $path;if([IO.File]::Exists($path)){throw 'Temporäres Datenbankziel existiert bereits.'}}
    $result=@{Type='VDJ';Id=$Plan.Id;Root=$Options.Root;Path=$Plan.Database;State='BACKUP_CREATED';BeforeHash=$original.Hash;AfterHash='';Backup=$backup;Swap=$swap;Items=$Plan.Items;StartedAt=[datetime]::UtcNow.ToString('o');EndedAt='';Error=''}
    $lock=$null;$changed=$false
    try{
        $lock=[IO.File]::Open($Plan.Database,'Open','Read','Read')
        [IO.File]::Copy($Plan.Database,$backup,$false)
        if((Get-PkHealthFileHash $backup) -cne $original.Hash){throw 'Datenbankbackup nicht verifiziert.'}
        Write-PkHealthAudit $journal $result
        $working=[Xml.XmlDocument]$original.Document.CloneNode($true);$songs=@($working.DocumentElement.SelectNodes('./Song'))
        foreach($item in $Plan.Items){
            if($Control -and $Control.Cancel){throw [OperationCanceledException]::new('Abgebrochen.')}
            $tag=$songs[$item.Index].SelectSingleNode('./Tags')
            if(!$tag){$tag=$working.CreateElement('Tags');[void]$songs[$item.Index].PrependChild($tag)}
            foreach($key in $item.Changes.Keys){if($key -cnotin @('Author','Title')){throw 'Nicht erlaubtes VirtualDJ-Feld.'};$tag.SetAttribute($key,$item.Changes[$key])}
        }
        $loaded=Write-PkVdjXml $original $working $temp
        Assert-PkVdjAllowedChanges $original $loaded $Plan.Items
        $result.AfterHash=$loaded.Hash;$result.State='COMMITTING';Write-PkHealthAudit $journal $result
        Assert-PkVdjClosed
        foreach($item in $Plan.Items){if((Get-PkHealthFileHash $item.Path) -cne $item.AudioFileHash){throw 'Audioquelle während der Datenbankkorrektur verändert.'}}
        if((Get-PkHealthFileHash $Plan.Database) -cne $original.Hash){throw 'Datenbank während der Reparatur verändert.'}
        if($Control -and $Control.Cancel){throw [OperationCanceledException]::new('Abgebrochen.')}
        $lock.Dispose();$lock=$null
        [IO.File]::Replace($temp,$Plan.Database,$swap);$changed=$true
        $final=Read-PkVdjDatabase $Plan.Database;Assert-PkVdjAllowedChanges $original $final $Plan.Items
        if($final.Hash -cne $result.AfterHash -or (Get-PkHealthFileHash $swap) -cne $original.Hash){throw 'Datenbankaustausch nicht verifiziert.'}
        $result.State='COMMITTED'
    }catch{
        if($lock){$lock.Dispose();$lock=$null}
        $result.Error=$_.Exception.Message
        if($changed){try{
            # Preserve the exact pre-swap image, including a concurrent last-moment change.
            $restoreSource=if([IO.File]::Exists($swap)){$swap}else{$backup};$restoreHash=Get-PkHealthFileHash $restoreSource
            Write-PkHealthFile $Plan.Database $restoreSource
            if((Get-PkHealthFileHash $Plan.Database) -cne $restoreHash){throw 'Originalhash abweichend.'};$result.State='ROLLED_BACK'
        }catch{$result.State='ROLLBACK_REQUIRED';$result.Error+=' '+$_.Exception.Message}}
        else{$result.State='FAILED'}
    }finally{if($lock){$lock.Dispose()};if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
    $result.EndedAt=[datetime]::UtcNow.ToString('o');Write-PkHealthAudit $journal $result;$result
}
function Get-PkVdjRestorePreview($Options,[string]$Id) {
    if($Id -cnotmatch '^[a-f0-9]{32}$'){throw 'Ungültige Datenbanksicherungs-ID.'}
    Assert-PkVdjClosed
    $directory=Join-Path $Options.BackupRoot "vdj/$Id";$manifest=Read-PkHealthJson (Join-Path $directory 'repair.json')
    $backup=Join-Path $directory 'database.xml'
    if($manifest.Type -ne 'VDJ' -or $manifest.Path -ine $Options.VdjDatabase -or $manifest.Root -ine $Options.Root -or (Get-PkHealthFileHash $backup) -cne $manifest.BeforeHash){throw 'Datenbanksicherung ist nicht gültig.'}
    $null=Read-PkVdjDatabase $backup
    $current=Get-PkHealthFileHash $manifest.Path
    if($current -cne $manifest.AfterHash -and $current -cne $manifest.BeforeHash){throw 'VirtualDJ-Datenbank nach der Reparatur verändert. Automatisches Zurücksetzen gesperrt.'}
    @{Type='VDJ_RESTORE';Id=[guid]::NewGuid().ToString('N');BackupId=$Id;Path=$manifest.Path;CurrentHash=$current;State='AWAITING_APPROVAL'}
}
function Invoke-PkVdjRestore($Options,$Preview) {
    if($Preview.State -ne 'APPROVED'){throw 'Wiederherstellung muss bestätigt werden.'}
    $validated=Get-PkVdjRestorePreview $Options $Preview.BackupId
    if($validated.CurrentHash -cne $Preview.CurrentHash){throw 'Datenbank seit der Wiederherstellungsvorschau geändert.'}
    $directory=Join-Path $Options.BackupRoot "vdj/$($Preview.BackupId)";$manifest=Read-PkHealthJson (Join-Path $directory 'repair.json')
    Write-PkHealthFile $manifest.Path (Join-Path $directory 'database.xml')
    if((Get-PkHealthFileHash $manifest.Path) -cne $manifest.BeforeHash){throw 'Datenbankwiederherstellung fehlgeschlagen.'}
    $manifest.State='RESTORED';Write-PkHealthAudit (Join-Path $directory 'repair.json') $manifest
    @{State='RESTORED';Type='VDJ';Path=$manifest.Path}
}

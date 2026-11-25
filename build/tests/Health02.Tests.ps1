param([string]$FFmpeg='D:\YT-DLP\bin\ffmpeg.exe',[string]$Probe='D:\YT-DLP\bin\ffprobe.exe')
$ErrorActionPreference='Stop'
$project=Split-Path -Parent (Split-Path -Parent $PSScriptRoot);$tools=@{FFmpeg=$FFmpeg;Probe=$Probe}
. "$project/setup/DJ-Sets-Download.ps1" -LibraryOnly -ToolRoot (Split-Path -Parent (Split-Path -Parent $FFmpeg))
. "$project/setup/DJ-Sets-HealthRepair.ps1"
$FFmpeg=$tools.FFmpeg;$Probe=$tools.Probe
function Assert($Value,[string]$Message){if(!$Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert $failed $Message}
$cases=@(
 @('Mahogany [Original Mix]','Mahogany','Version','Original Mix'),@('Fathom [Dubstep]','Fathom','Genre','Dubstep'),
 @('Basar - Sascha Braemer Edit','Basar','Version','Sascha Braemer Edit'),@("Fallen Vex'd Remix",'Fallen','Version',"Vex'd Remix"),
 @('Marka - Exit Records','Marka','Label','Exit Records'),@('Closer (Original Mix)','Closer','Version','Original Mix'),
 @('No Holds Barred (Excision Remix)','No Holds Barred','Version','Excision Remix'),@('She [Subfusc Remix]','She','Version','Subfusc Remix'),
 @('Howling (Âme Remix)','Howling','Version','Âme Remix'))
foreach($case in $cases){$pk=@{Artist='Artist';Title=$case[1]};$pk[$case[2]]=$case[3];Assert ((Get-PkHealthMetadataStatus @{Artist='Artist';Title=$case[0]} $pk) -eq 'METADATA_SEMANTIC_MATCH') ('Semantic mismatch '+$case[0])}
Assert ((Get-PkHealthMetadataStatus @{Artist='Artist';Title='Howling (Other Remix)'} @{Artist='Artist';Title='Howling';Version='Âme Remix'}) -eq 'METADATA_CONFLICT') 'Wrong remix accepted'
foreach($name in @('Âme','Lumï','Sven Väth','Trentemøller','Björn Torwellen','Groß-Gerau','Täglich Brot',"Nico's Deep Sea Edit")){Assert (!(Test-PkHealthSuspiciousUnicode $name)) ('Legitimate Unicode rejected '+$name)}
Assert (Test-PkHealthSuspiciousUnicode 'Sven VÃ¤th') 'Mojibake not marked for review'
$nfd='Sven Va'+[char]0x0308+'th';Assert (Test-PkHealthFieldEquivalent 'Artist' $nfd 'Sven Väth' $null) 'NFC comparison failed'
$test=Join-Path $project ('work/health02-'+[guid]::NewGuid().ToString('N'))
$options=@{Root=(Join-Path $test 'Musik');Storage=(Join-Path $test 'reports');BackupRoot=(Join-Path $test 'backups');QuarantineRoot=(Join-Path $test 'quarantine');CoverRoot=(Join-Path $test 'covers');FFmpeg=$FFmpeg;Probe=$Probe;Deep=$true}
$folder=Join-Path $options.Root "Âme & Friends/Tracks/Move (Nico's Deep Sea Edit) [A], ö";[void][IO.Directory]::CreateDirectory($folder)
$audio=Join-Path $folder 'audio.m4a'
$null=Invoke-PkHealthTool $FFmpeg @('-v','error','-nostdin','-f','lavfi','-i','sine=frequency=440:duration=1','-c:a','aac','-metadata','artist=Âme & Friends','-metadata',"title=Move (Nico's Deep Sea Edit)",$audio) $null
Write-PkHealthJson (Join-Path $folder 'plattenkoffer.json') @{Artist='Âme & Friends';Title='Move';Version="Nico's Deep Sea Edit"}
$report=Invoke-PkHealthScan $options $null
Assert ('METADATA_SEMANTIC_MATCH' -in $report.Records[0].Codes -and 'JSON_MISMATCH' -notin $report.Records[0].Codes) 'Scanner ignored semantic result'
$audioOriginal=Get-PkHealthFileHash $audio
foreach($name in @('Âme','Lumï','Sven Väth','Trentemøller','Björn Torwellen','Groß-Gerau','Täglich Brot',"Nico's Deep Sea Edit")){
 $target=Join-Path $test ([guid]::NewGuid().ToString('N')+'.m4a')
 $null=Invoke-PkHealthTool $FFmpeg @('-v','error','-nostdin','-i',$audio,'-c','copy','-metadata',"artist=$name",$target) $null
 Assert ((Get-PkHealthTags (Get-PkHealthProbe $target $options $null)).Artist -ceq $name) ('Native UTF-8 failed '+$name)
}
$encodingTool=Join-Path $test 'invalid-encoding.exe'
Add-Type -TypeDefinition 'public class EncodingFixture { public static void Main() { System.Console.OpenStandardOutput().WriteByte(255); } }' -OutputAssembly $encodingTool -OutputType ConsoleApplication
$badOptions=@{}+$options;$badOptions.Probe=$encodingTool
$encodingRecord=Get-PkHealthRecord $audio $badOptions $null
Assert ('TOOL_ENCODING_ERROR' -in $encodingRecord.Codes -and 'AUDIO_ERROR' -notin $encodingRecord.Codes) 'Own decoding error misclassified as corrupt audio'
# Build a native DOM fixture, including unknown elements, attributes, cues and order.
$document=[Xml.XmlDocument]::new();[void]$document.AppendChild($document.CreateXmlDeclaration('1.0','UTF-8',$null));$element=$document.CreateElement('VirtualDJ_Database');$element.SetAttribute('Version','2026');[void]$document.AppendChild($element)
foreach($path in @($audio,(Join-Path $options.Root 'missing.mp3'),'C:\Outside\other.mp3')){
 $song=$document.CreateElement('Song');$song.SetAttribute('FilePath',$path);$song.SetAttribute('FileSize','123');$song.SetAttribute('Custom','keep');[void]$element.AppendChild($song)
 $tags=$document.CreateElement('Tags');$tags.SetAttribute('Flag','1');[void]$song.AppendChild($tags)
 foreach($name in @('Infos','Scan','Poi','Unknown')){$n=$document.CreateElement($name);$n.SetAttribute('Bpm','116.00');$n.SetAttribute('Cue','1.2');$n.SetAttribute('Label','ä & ö');[void]$song.AppendChild($n)}
}
$xml=$document.OuterXml.Replace('?><','?>'+"`r`n"+'<').Replace('<Song',"`r`n  <Song").Replace("Nico's",'Nico&apos;s')
function Test-PkVdjRunning{return $false}
foreach($bom in @($true,$false)){
 $database=Join-Path $test ('database-'+$bom+'.xml');[IO.File]::WriteAllText($database,$xml,[Text.UTF8Encoding]::new($bom));$options.VdjDatabase=$database
 $before=Get-PkHealthFileHash $database;$read=Read-PkVdjDatabase $database;Assert ($read.Bom -eq $bom -and $read.Writable) 'BOM or version detection failed'
 $analysis=Invoke-PkVdjAnalysis $options $report $null
 Assert ($analysis.Entries -eq 3 -and $analysis.Rows[0].Writable) 'VDJ analysis failed'
 Assert ('VDJ_DATABASE_ORPHAN_ENTRY' -in $analysis.Rows[1].Codes) 'Orphan not recognized'
 $plan=New-PkVdjPlan $options $analysis @(0)
 Reject {Invoke-PkVdjRepair $options $plan $null} 'Unapproved VDJ repair accepted'
 $plan.State='APPROVED';$result=Invoke-PkVdjRepair $options $plan $null
 Assert ($result.State -eq 'COMMITTED') ('VDJ repair failed '+$result.Error)
 $after=Read-PkVdjDatabase $database;Assert ($after.Bom -eq $bom) 'BOM changed'
 Assert ($after.Songs[0].Tags.Author -ceq 'Âme & Friends') 'Unicode Author wrong'
 Assert ($after.Songs[0].Tags.Flag -eq '1' -and $after.Songs[0].Poi.Cue -eq '1.2') 'DJ analysis data changed'
 Assert (![IO.File]::ReadAllText($database).Contains('?>&#xD;')) 'Invalid root entity serialization'
 Assert ([IO.File]::ReadAllText($database).Contains("`r`n")) 'CRLF lost'
 $tampered=Read-PkVdjDatabase $database;$tampered.Songs[0].Scan.SetAttribute('Bpm','999')
 Reject {Assert-PkVdjAllowedChanges $read $tampered $plan.Items} 'Changed BPM accepted'
 $restore=Get-PkVdjRestorePreview $options $plan.Id;$restore.State='APPROVED';$null=Invoke-PkVdjRestore $options $restore
 Assert ((Get-PkHealthFileHash $database) -ceq $before) 'VDJ restore not byte-exact'
 $analysis=Invoke-PkVdjAnalysis $options $report $null;$stale=New-PkVdjPlan $options $analysis @(0);[IO.File]::AppendAllText($database,' ');$stale.State='APPROVED'
 Reject {Invoke-PkVdjRepair $options $stale $null} 'Changed database accepted'
 [IO.File]::WriteAllText($database,$xml,[Text.UTF8Encoding]::new($bom))
 $analysis=Invoke-PkVdjAnalysis $options $report $null;$lockedPlan=New-PkVdjPlan $options $analysis @(0);$lockedPlan.State='APPROVED';$lock=[IO.File]::Open($database,'Open','Read','None')
 try{Reject {Invoke-PkVdjRepair $options $lockedPlan $null} 'Locked database accepted'}finally{$lock.Dispose()}
}
Assert ((Get-PkHealthFileHash $audio) -ceq $audioOriginal) 'VDJ repair changed audio'
# Fail the post-swap validation and verify rollback, not just pre-commit rejection.
$database=$options.VdjDatabase;$originalDbHash=Get-PkHealthFileHash $database
$analysis=Invoke-PkVdjAnalysis $options $report $null;$faultPlan=New-PkVdjPlan $options $analysis @(0);$faultPlan.State='APPROVED'
$compare=(Get-Command Assert-PkVdjAllowedChanges).ScriptBlock;$script:comparisons=0
function Assert-PkVdjAllowedChanges($Original,$Changed,$Items){$script:comparisons++;if($script:comparisons -eq 2){throw 'Injected post-swap failure'};& $compare $Original $Changed $Items}
$fault=Invoke-PkVdjRepair $options $faultPlan $null
Assert ($fault.State -eq 'ROLLED_BACK' -and (Get-PkHealthFileHash $database) -ceq $originalDbHash) 'VDJ post-swap rollback failed'
Set-Item Function:Assert-PkVdjAllowedChanges $compare
$analysis=Invoke-PkVdjAnalysis $options $report $null;$invalidPlan=New-PkVdjPlan $options $analysis @(0);$invalidPlan.State='APPROVED'
$xmlWriter=(Get-Command Write-PkVdjXml).ScriptBlock
function Write-PkVdjXml($Database,$Document,$Path){[IO.File]::WriteAllText($Path,'<?xml version="1.0"?>&#xD;<VirtualDJ_Database/>');Read-PkVdjDatabase $Path}
$invalidTemp=Invoke-PkVdjRepair $options $invalidPlan $null
Assert ($invalidTemp.State -eq 'FAILED' -and (Get-PkHealthFileHash $database) -ceq $originalDbHash) 'Invalid temporary XML affected original'
Set-Item Function:Write-PkVdjXml $xmlWriter
$analysis=Invoke-PkVdjAnalysis $options $report $null;$readOnlyPlan=New-PkVdjPlan $options $analysis @(0);$readOnlyPlan.State='APPROVED'
[IO.File]::SetAttributes($database,[IO.FileAttributes]::ReadOnly)
try{$readOnlyResult=Invoke-PkVdjRepair $options $readOnlyPlan $null;Assert ($readOnlyResult.State -eq 'FAILED' -and (Get-PkHealthFileHash $database) -ceq $originalDbHash) 'Read-only database not protected'}finally{[IO.File]::SetAttributes($database,[IO.FileAttributes]::Normal)}
$unknown=Join-Path $test 'unknown.xml';[IO.File]::WriteAllText($unknown,$xml.Replace('Version="2026"','Version="2027"'),[Text.UTF8Encoding]::new($false));Assert (!(Read-PkVdjDatabase $unknown).Writable) 'Unknown VDJ version writable'
$invalid=Join-Path $test 'invalid.xml';[IO.File]::WriteAllText($invalid,'<?xml version="1.0"?>&#xD;<VirtualDJ_Database/>');Reject {Read-PkVdjDatabase $invalid} 'Invalid XML accepted'
function Test-PkVdjRunning{return $true}
Reject {Assert-PkVdjClosed} 'Running VDJ not blocked'
function Test-PkVdjRunning{return $false}
# MP3 JPEG embedding uses the existing transaction and restores byte-exact originals.
$mp3Folder=Join-Path $options.Root 'DJ/Sets/Multipart';[void][IO.Directory]::CreateDirectory($mp3Folder)
$mp3=Join-Path $mp3Folder 'part-1.mp3';$jpeg=Join-Path $test 'cover.jpg'
$null=Invoke-PkHealthTool $FFmpeg @('-v','error','-nostdin','-i',$audio,'-c:a','libmp3lame','-metadata','artist=DJ','-metadata','title=Multipart',$mp3) $null
$null=Invoke-PkHealthTool $FFmpeg @('-v','error','-nostdin','-f','lavfi','-i','color=c=green:s=1000x1000','-frames:v','1','-threads','1',$jpeg) $null
$mp3Hash=Get-PkHealthFileHash $mp3;$report=Invoke-PkHealthScan $options $null;$record=$report.Records|Where-Object Path -eq $mp3
$plan=New-PkHealthPlan $options $report @(@{Id=$record.Id;CoverPath=$jpeg;EmbedCover=$true;CoverOrigin='KI-generiert';Json=$true});$plan.State='APPROVED';$done=Invoke-PkHealthPlan $options $plan $null
Assert ($done.Results[0].State -eq 'COMMITTED') ('MP3 cover failed '+$done.Results[0].Error)
Assert (@((Get-PkHealthProbe $mp3 $options $null).streams|Where-Object {$_.disposition.attached_pic -eq 1 -and $_.codec_name -eq 'mjpeg'}).Count -eq 1) 'MP3 JPEG not embedded'
Assert ((Read-PkHealthJson (Join-Path $mp3Folder 'plattenkoffer.json')).MetadataSources.Cover.Provider -eq 'KI-generiert') 'Cover provenance lost'
$coverRecord=Get-PkHealthRecord $mp3 $options $null;$recovered=Get-PkHealthCoverRecovery $options $coverRecord $null
Assert ($recovered.Origin -eq 'Eingebettetes Originalcover' -and [IO.File]::Exists($recovered.Path)) 'Embedded-first cover recovery failed'
$preview=Get-PkHealthRestorePreview $options @((Join-Path (Join-Path $options.BackupRoot $plan.Id) $record.Id));$preview.State='APPROVED';$null=Invoke-PkHealthRestore $options $preview $null
Assert ((Get-PkHealthFileHash $mp3) -ceq $mp3Hash) 'MP3 restoration not exact'
# Two set parts share an external cover and JSON but keep individual audio tags.
$part2=Join-Path $mp3Folder 'part-2.mp3'
$null=Invoke-PkHealthTool $FFmpeg @('-v','error','-nostdin','-i',$mp3,'-c','copy','-metadata','title=Multipart Part 2',$part2) $null
$part2Hash=Get-PkHealthFileHash $part2;$report=Invoke-PkHealthScan $options $null
$partRecords=@($report.Records|Where-Object {$_.Path -in @($mp3,$part2)})
$multi=New-PkHealthPlan $options $report @($partRecords|ForEach-Object {@{Id=$_.Id;CoverPath=$jpeg;EmbedCover=$true;Json=$true;CoverOrigin='KI-generiert'}});$multi.State='APPROVED';$multiDone=Invoke-PkHealthPlan $options $multi $null
Assert (@($multiDone.Results|Where-Object State -eq 'COMMITTED').Count -eq 2) ('Multipart batch failed '+($multiDone.Results.Error -join ';'))
$shared=Read-PkHealthJson (Join-Path $mp3Folder 'plattenkoffer.json');Assert ($shared.Title -eq 'Multipart' -and $shared.Parts.Count -eq 2) 'Multipart JSON recovery lost set structure'
$multiRestore=Get-PkHealthRestorePreview $options @($partRecords|ForEach-Object {Join-Path (Join-Path $options.BackupRoot $multi.Id) $_.Id});$multiRestore.State='APPROVED';$null=Invoke-PkHealthRestore $options $multiRestore $null
Assert ((Get-PkHealthFileHash $part2) -ceq $part2Hash -and (Get-PkHealthFileHash $mp3) -ceq $mp3Hash -and ![IO.File]::Exists((Join-Path $mp3Folder 'plattenkoffer.json'))) 'Multipart job restore failed'
# Audio-identical duplicate with different filename can be archived and restored.
$copy=Join-Path $mp3Folder 'part-copy.mp3';[IO.File]::Copy($mp3,$copy);$report=Invoke-PkHealthScan $options $null;$duplicate=$report.Records|Where-Object Path -eq $copy
Reject {New-PkQuarantinePlan $options $report @($duplicate.Id) @($mp3Folder)} 'Playlist reference ignored'
$options.VdjDatabase='';$qplan=New-PkQuarantinePlan $options $report @($duplicate.Id) @();$qplan.ExternalReferencesReviewed=$true;$qplan.State='APPROVED'
$archived=Invoke-PkQuarantinePlan $options $qplan $null;Assert ($archived.Results[0].State -eq 'COMMITTED' -and ![IO.File]::Exists($copy) -and [IO.File]::Exists($mp3)) 'Quarantine failed'
$qrestore=Get-PkQuarantineRestorePreview $options ($qplan.Id+'/'+$duplicate.Id);$qrestore.State='APPROVED';$null=Invoke-PkQuarantineRestore $options $qrestore
Assert ((Get-PkHealthFileHash $copy) -ceq $mp3Hash) 'Quarantine restoration not exact'
$report=Invoke-PkHealthScan $options $null;$qcrash=New-PkQuarantinePlan $options $report @($duplicate.Id) @();$qcrash.State='APPROVED';$qcrash.ExternalReferencesReviewed=$true;$null=Invoke-PkQuarantinePlan $options $qcrash $null
$qdir=Join-Path $options.QuarantineRoot ($qcrash.Id+'/'+$duplicate.Id);$m=Read-PkHealthJson (Join-Path $qdir 'quarantine.json');$m.State='COMMITTING';Write-PkHealthJson (Join-Path $qdir 'quarantine.json') $m
[IO.File]::Copy((Join-Path $qdir 'original.bin'),$m.Stage,$false)
$recover=Get-PkQuarantineRestorePreview $options ($qcrash.Id+'/'+$duplicate.Id);$recover.State='APPROVED';$null=Invoke-PkQuarantineRestore $options $recover
Assert ((Get-PkHealthFileHash $copy) -ceq $mp3Hash -and ![IO.File]::Exists($m.Stage)) 'Interrupted quarantine recovery failed'
'PASS: all 9 semantic cases, true conflicts, Unicode/NFC, UTF-8 native calls, VDJ DOM repair and exact restore, entities/BOM/CRLF, locked/stale/version/process gates, preserved cues/BPM/unknown XML, MP3 cover and quarantine.'
"Fixtures: $test"

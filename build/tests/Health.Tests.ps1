param([string]$FFmpeg='D:\YT-DLP\bin\ffmpeg.exe',[string]$Probe='D:\YT-DLP\bin\ffprobe.exe')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$toolPaths=@{FFmpeg=$FFmpeg;Probe=$Probe}
. "$root/setup/DJ-Sets-Download.ps1" -LibraryOnly -ToolRoot (Split-Path -Parent (Split-Path -Parent $FFmpeg))
$FFmpeg=$toolPaths.FFmpeg;$Probe=$toolPaths.Probe
. "$root/setup/DJ-Sets-Health.ps1"
. "$root/setup/DJ-Sets-HealthRepair.ps1"
$test=Join-Path $root ('work/health-tests-'+[guid]::NewGuid().ToString('N'))
$music=Join-Path $test 'Musik'
$options=@{Root=$music;Storage=(Join-Path $test 'reports');BackupRoot=(Join-Path $test 'backups');FFmpeg=$FFmpeg;Probe=$Probe;Deep=$true}
$control=[hashtable]::Synchronized(@{Cancel=$false;Current='';Done=0;Total=0})
function Assert($Value,[string]$Message){if(!$Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Assert $failed $Message}
foreach($name in @('WHTKD/Tracks/Say To Me','Künstler & Sonderzeichen/Tracks/Club (Extended Mix)','Other/Tracks/Duplicate','DJ/ Sets/Ignore')){[void][IO.Directory]::CreateDirectory((Join-Path $music $name))}
$opus=Join-Path $music 'WHTKD/Tracks/Say To Me/audio.opus'
$aac=Join-Path $music 'Künstler & Sonderzeichen/Tracks/Club (Extended Mix)/audio.m4a'
$null=Invoke-PkHealthTool $FFmpeg @('-v','error','-nostdin','-f','lavfi','-i','sine=frequency=440:duration=1','-c:a','libopus',$opus) $control
$null=Invoke-PkHealthTool $FFmpeg @('-v','error','-nostdin','-f','lavfi','-i','sine=frequency=660:duration=1','-c:a','aac','-metadata','artist=Künstler & Sonderzeichen','-metadata','title=Club (Extended Mix)','-metadata','album=Remove me','-metadata','comment=Keep me',$aac) $control
$info=Join-Path ([IO.Path]::GetDirectoryName($opus)) 'info.json'
Write-PkHealthJson $info @{title='WHTKD - Say To Me (Official Video)';uploader='Never the artist';id='CYoPOJCeJvU'}
$pk=Join-Path ([IO.Path]::GetDirectoryName($aac)) 'plattenkoffer.json'
Write-PkHealthJson $pk @{Artist='Künstler & Sonderzeichen';Title='Club (Extended Mix)';Custom=@{Keep='unchanged'};MetadataSources=@{Year=@{Provider='Manual';Value='2001'}}}
$duplicate=Join-Path $music 'Other/Tracks/Duplicate/duplicate.opus';[IO.File]::Copy($opus,$duplicate)
$testDuplicate=Join-Path ([IO.Path]::GetDirectoryName($opus)) 'audio_repaired.opus';[IO.File]::Copy($opus,$testDuplicate)
$original=Get-PkHealthFileHash $opus;$aacOriginal=Get-PkHealthFileHash $aac;$infoHash=Get-PkHealthFileHash $info
$report=Invoke-PkHealthScan $options $control
Assert ($report.Records.Count -eq 3) 'Test duplicate was not excluded'
Assert ((Get-PkHealthFileHash $opus) -ceq $original) 'Read-only scan changed audio'
$op=$report.Records|Where-Object Path -eq $opus
Assert ('MISSING_ARTIST' -in $op.Codes) 'Missing tags not detected'
Assert ($op.Resolved.Values.Artist -eq 'WHTKD' -and $op.Resolved.Values.Title -eq 'Say To Me') 'Folder reconstruction failed'
Assert ('DUPLICATE_AUDIO' -in $op.Codes) 'Encoded duplicate not detected'
Assert ('DUPLICATE_AUDIO' -notin ($report.Records|Where-Object Path -eq $aac).Codes) 'Different audio incorrectly grouped as duplicate'
Assert ((Get-PkHealthSummary $report).Files -eq 3 -and (Get-PkHealthSummary $report).Bytes -gt 0) 'Live dashboard summary failed'
Assert ($op.Integrity -eq 'DECODE_CHECKED') 'Deep decode not performed'
Assert ('Artist' -notin $op.Resolved.Conflicts) 'Uploader used as artist'
$tagged=$report.Records|Where-Object Path -eq $aac
Assert ('MISSING_ARTIST' -notin $tagged.Codes -and 'MISSING_TITLE' -notin $tagged.Codes) 'Valid tags marked missing'
Assert ($tagged.Resolved.Values.Title -eq 'Club (Extended Mix)') 'Musical suffix removed'
$plan=New-PkHealthPlan $options $report @(@{Id=$op.Id;Changes=@{Artist='WHTKD';Title='Say To Me'};Json=$true},@{Id=$tagged.Id;Changes=@{Genre='House';Album=''};Json=$true})
Reject {Invoke-PkHealthPlan $options $plan $control} 'Unapproved plan accepted'
$plan.State='APPROVED';$done=Invoke-PkHealthPlan $options $plan $control
foreach($result in $done.Results){Assert ($result.State -eq 'COMMITTED') ("Repair failed: "+$result.Error)}
Assert ((Get-PkHealthFileHash $opus) -cne $original) 'Tags not written'
Assert ((Get-PkHealthFileHash $info) -ceq $infoHash) 'Source JSON changed'
Assert ((Read-PkHealthJson $pk).Custom.Keep -eq 'unchanged') 'Unknown JSON fields lost'
Assert ((Read-PkHealthJson $pk).MetadataSources.Year.Value -eq '2001') 'Unknown provenance lost'
Assert ((Get-PkHealthTags (Get-PkHealthProbe $aac $options $control)).Genre -eq 'House') 'M4A tags missing'
Assert (!(Get-PkHealthTags (Get-PkHealthProbe $aac $options $control)).Album) 'Clearing optional metadata failed'
Assert ((Get-PkHealthTags (Get-PkHealthProbe $opus $options $control)).Title -eq 'Say To Me') 'Opus tags missing'
$directories=@($done.Results|ForEach-Object {Join-Path (Join-Path $options.BackupRoot $plan.Id) $_.Id})
$preview=Get-PkHealthRestorePreview $options $directories
Reject {Invoke-PkHealthRestore $options $preview $control} 'Unapproved restore accepted'
$preview.State='APPROVED';$restored=Invoke-PkHealthRestore $options $preview $control
Assert ((Get-PkHealthFileHash $opus) -ceq $original) 'Opus restore not byte-exact'
Assert ((Get-PkHealthFileHash $aac) -ceq $aacOriginal) 'AAC restore not byte-exact'
Assert (![IO.File]::Exists((Join-Path ([IO.Path]::GetDirectoryName($opus)) 'plattenkoffer.json'))) 'Created JSON not removed on restore'
Reject {Assert-PkHealthScope (Join-Path $test 'outside.opus') $music} 'Out-of-scope path accepted'
$bad=@{}+$options;$bad.BackupRoot=Join-Path $music 'backups'
Reject {Assert-PkHealthOptions $bad} 'Backups in music accepted'
$bad=@{}+$options;$bad.Probe=Join-Path $test 'absent.exe'
Reject {Assert-PkHealthOptions $bad} 'Missing tool accepted'
$stale=New-PkHealthPlan $options (Invoke-PkHealthScan $options $control) @(@{Id=$op.Id;Changes=@{Artist='WHTKD';Title='Say To Me'}})
[IO.File]::AppendAllText($info,' ')
$stale.State='APPROVED';$failed=Invoke-PkHealthPlan $options $stale $control
Assert ($failed.Results[0].State -eq 'FAILED') 'Stale sidecar not rejected'
Assert ((Get-PkHealthFileHash $opus) -ceq $original) 'Stale plan changed original'
# Force a failure after replacement and confirm complete rollback of audio and JSON.
$report=Invoke-PkHealthScan $options $control
$rollbackPlan=New-PkHealthPlan $options $report @(@{Id=$op.Id;Changes=@{Artist='WHTKD';Title='Say To Me'}})
$validator=(Get-Command Assert-PkHealthWrittenTags).ScriptBlock
$script:validations=0
function Assert-PkHealthWrittenTags($Before,$After,$Changes){$script:validations++;if($script:validations -eq 2){throw 'Injected final validation failure'};& $validator $Before $After $Changes}
$rollbackPlan.State='APPROVED';$rollback=Invoke-PkHealthPlan $options $rollbackPlan $control
Assert ($rollback.Results[0].State -eq 'ROLLED_BACK') 'Committed validation failure did not roll back'
Assert ((Get-PkHealthFileHash $opus) -ceq $original) 'Rollback lost original audio'
Assert (![IO.File]::Exists((Join-Path ([IO.Path]::GetDirectoryName($opus)) 'plattenkoffer.json'))) 'Rollback left created JSON'
Set-Item Function:Assert-PkHealthWrittenTags $validator
# Changed audio hashes and changed streams must fail independently.
$probeResult=Get-PkHealthProbe $opus $options $control
Reject {Assert-PkHealthEquivalent $probeResult $probeResult @('one') @('two')} 'Changed audio hash accepted'
# Crash journal at COMMITTING can restore originals using recorded post-images.
$crashPlan=New-PkHealthPlan $options $report @(@{Id=$op.Id;Changes=@{Artist='WHTKD';Title='Say To Me'}})
$crashPlan.State='APPROVED';$committed=Invoke-PkHealthPlan $options $crashPlan $control
$crashDir=Join-Path (Join-Path $options.BackupRoot $crashPlan.Id) $op.Id
$journal=Read-PkHealthJson (Join-Path $crashDir 'repair.json');$journal.State='COMMITTING';Write-PkHealthJson (Join-Path $crashDir 'repair.json') $journal
$recover=Get-PkHealthRestorePreview $options @($crashDir);$recover.State='APPROVED';$null=Invoke-PkHealthRestore $options $recover $control
Assert ((Get-PkHealthFileHash $opus) -ceq $original) 'Interrupted commit recovery failed'
# Publish a staged download only after tags, JSON, audiohash and decode validation.
$stage=Join-Path $test 'download-stage';[void][IO.Directory]::CreateDirectory($stage)
$cover=Join-Path $test 'cover.jpg'
$null=Invoke-PkHealthTool $FFmpeg @('-v','error','-nostdin','-f','lavfi','-i','color=c=red:s=32x32','-frames:v','1','-threads','1',$cover) $control
$temp=Join-Path $test 'download.tmp.opus'
$row=@{Id='CYoPOJCeJvU';Artist='WHTKD';Title='Say "To Me" & $neverExecute';Type='Track'}
Complete-PkDownloadPayload $row $opus $temp $stage $info $cover
Assert ((Get-PkHealthTags (Get-PkHealthProbe (Join-Path $stage 'audio.opus') $options $control)).Title -ceq $row.Title) 'Argument escaping or download validation failed'
Assert ((Read-PkHealthJson (Join-Path $stage 'plattenkoffer.json')).Artist -eq 'WHTKD') 'Download JSON missing'
Reject {Complete-PkDownloadPayload @{Id='CYoPOJCeJvU';Artist='';Title='No artist'} $opus $temp $stage $info $cover} 'Download missing mandatory artist accepted'
# Audit metadata excludes secrets while original source files remain unchanged.
$audit=Join-Path $test 'audit.json';Write-PkHealthAudit $audit @{Token='do-not-log';Url='https://example.org/?api_key=do-not-log&x=1'}
Assert (![IO.File]::ReadAllText($audit).Contains('do-not-log')) 'Credentials in audit'
$incremental=Invoke-PkHealthScan $options $control -Incremental
Assert ($incremental.Records.Count -eq 3) 'Incremental resume lost files'
# Validate preservation of an existing embedded M4A cover and an opt-in external cover.
$embedFolder=Join-Path $music 'Embed/Tracks/Picture';[void][IO.Directory]::CreateDirectory($embedFolder)
$embed=Join-Path $embedFolder 'audio.m4a'
$null=Invoke-PkHealthTool $FFmpeg @('-v','error','-nostdin','-i',$aac,'-i',$cover,'-map','0:a','-map','1:v','-c','copy','-disposition:v:0','attached_pic',$embed) $control
$embedOriginal=Get-PkHealthFileHash $embed
$embedReport=Invoke-PkHealthScan $options $control
$entry=$embedReport.Records|Where-Object Path -eq $embed
Assert $entry.EmbeddedCover 'Embedded cover not detected'
$embedPlan=New-PkHealthPlan $options $embedReport @(@{Id=$entry.Id;Changes=@{Genre='Techno'};CoverPath=$cover;Json=$true})
$embedPlan.State='APPROVED';$embedDone=Invoke-PkHealthPlan $options $embedPlan $control
Assert ($embedDone.Results[0].State -eq 'COMMITTED') ("Embedded cover repair failed: "+$embedDone.Results[0].Error)
Assert ([IO.File]::Exists((Join-Path $embedFolder 'plattenkoffer-cover.jpg'))) 'Chosen cover missing'
$coverRestore=Get-PkHealthRestorePreview $options @((Join-Path (Join-Path $options.BackupRoot $embedPlan.Id) $entry.Id));$coverRestore.State='APPROVED';$null=Invoke-PkHealthRestore $options $coverRestore $control
Assert ((Get-PkHealthFileHash $embed) -ceq $embedOriginal) 'Embedded cover restore not exact'
Assert (![IO.File]::Exists((Join-Path $embedFolder 'plattenkoffer-cover.jpg'))) 'New external cover not undone'
# Negative classifications are distinct from metadata problems.
$brokenFolder=Join-Path $music 'Broken/Tracks/Invalid';[void][IO.Directory]::CreateDirectory($brokenFolder)
$broken=Join-Path $brokenFolder 'broken.mp3';[IO.File]::WriteAllText($broken,'not audio')
[IO.File]::WriteAllText((Join-Path $brokenFolder 'plattenkoffer.json'),'{invalid')
$readonlyFolder=Join-Path $music 'Lossless/Tracks/Read only';[void][IO.Directory]::CreateDirectory($readonlyFolder)
$flac=Join-Path $readonlyFolder 'audio.flac'
$null=Invoke-PkHealthTool $FFmpeg @('-v','error','-nostdin','-i',$opus,'-c:a','flac',$flac) $control
$negative=Invoke-PkHealthScan $options $control
$brokenRecord=$negative.Records|Where-Object Path -eq $broken
Assert ('AUDIO_ERROR' -in $brokenRecord.Codes -and 'INVALID_JSON' -in $brokenRecord.Codes) 'Broken audio / JSON not classified'
$flacRecord=$negative.Records|Where-Object Path -eq $flac
Assert (!$flacRecord.Repairable -and 'UNSUPPORTED_FORMAT' -in $flacRecord.Codes -and $flacRecord.Lossless) 'FLAC write gate failed'
Reject {New-PkHealthPlan $options $negative @(@{Id=$flacRecord.Id;Changes=@{Artist='No write'}})} 'Unvalidated format writable'
# A sharing violation must never replace a locked original.
$lockedPlan=New-PkHealthPlan $options $negative @(@{Id=$op.Id;Changes=@{Artist='WHTKD';Title='Say To Me'}})
$locked=[IO.File]::Open($opus,'Open','Read','None')
try{$lockedPlan.State='APPROVED';$lockedDone=Invoke-PkHealthPlan $options $lockedPlan $control;Assert ($lockedDone.Results[0].State -eq 'FAILED') 'Locked audio was changed'}finally{$locked.Dispose()}
Assert ((Get-PkHealthFileHash $opus) -ceq $original) 'Locked original changed'
$control.Cancel=$true
Reject {Invoke-PkHealthTool $FFmpeg @('-version') $control} 'Cancellation ignored'
'PASS: recursive read-only scan, Opus/AAC stream copy and audiohash, source evidence, duplicate exclusion, deep integrity, approval, verified backups, exact restore, JSON preservation, stale plan and unsafe path rejection.'
"Fixtures: $test"

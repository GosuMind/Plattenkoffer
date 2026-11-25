param([string]$FFmpeg='D:\YT-DLP\bin\ffmpeg.exe',[string]$Probe='D:\YT-DLP\bin\ffprobe.exe')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$toolPaths=@{FFmpeg=$FFmpeg;Probe=$Probe}
. "$root/setup/DJ-Sets-Download.ps1" -LibraryOnly -ToolRoot (Split-Path -Parent (Split-Path -Parent $FFmpeg))
$FFmpeg=$toolPaths.FFmpeg;$Probe=$toolPaths.Probe
. "$root/setup/DJ-Sets-HealthRepair.ps1"
. "$root/setup/DJ-Sets-HealthWeb.ps1"
$fixtures=Get-ChildItem "$root/work" -Directory -Filter 'health-tests-*'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
if(!$fixtures){throw 'Run Health.Tests.ps1 first.'}
$config=Join-Path $fixtures.FullName 'gui-config';[void][IO.Directory]::CreateDirectory($config)
$settings=@{MusicRoot=(Join-Path $fixtures.FullName 'Musik')}
$web=@{Ready=$true;Conversion=@{};Export=@{};TransitionScan=@{}}
$state=@{};$libraryView=@{Diagnostic=@{}};$transport=@{Enabled=$false}
$script:messages=[Collections.Generic.List[object]]::new()
$core=[pscustomobject]@{}
$core|Add-Member ScriptMethod PostWebMessageAsJson {param($json)$script:messages.Add((ConvertFrom-Json $json))}
$web.Control=[pscustomobject]@{CoreWebView2=$core}
function Send-WebCollectionMessage($Value){$script:messages.Add([pscustomobject]$Value)}
function Update-LibraryResults{param([switch]$Reload)}
Initialize-WebHealth
$web.Health.Options=@{Root=$settings.MusicRoot;FFmpeg=$FFmpeg;Probe=$Probe;Storage=(Join-Path $fixtures.FullName 'reports');BackupRoot=(Join-Path $fixtures.FullName 'backups');Deep=$false}
$web.Health.Report=Read-PkHealthJson (Join-Path $web.Health.Options.Storage 'scan.json')
function Finish {
 $deadline=[datetime]::UtcNow.AddSeconds(40)
 while($web.Health.Worker -and [datetime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 30;Complete-WebHealth}
 if($web.Health.Worker){throw 'Background operation timed out'}
}
Send-WebHealth
if($messages[-1].summary.Files -ne @($web.Health.Report.Records).Count){throw 'Live bridge summary failed'}
Invoke-WebHealth @{command='health-record';id=$web.Health.Report.Records[0].Id}
if($messages[-1].type -ne 'health-record'){throw 'Record bridge failed'}
Start-WebHealthJob 'scan' $true;Finish
if(!$web.Health.Report -or $web.Health.Report.State -ne 'COMPLETED'){throw $web.Health.Status}
$op=$web.Health.Report.Records|Where-Object {$_.Path -like '*WHTKD*audio.opus'}|Select-Object -First 1
Invoke-WebHealth @{command='health-plan';requests=@(@{Id=$op.Id;Changes=@{Artist='WHTKD';Title='Say To Me'};Json=$true})};Finish
if(!$web.Health.Plan){throw $web.Health.Status}
$id=$web.Health.Plan.Id
Invoke-WebHealth @{command='health-approve';token='wrong';approved=$true}
if($web.Health.Worker){throw 'Wrong approval token started repair'}
Invoke-WebHealth @{command='health-approve';token=$id;approved=$true};Finish
if(!$web.Health.Dirty){throw $web.Health.Status}
$directory=Join-Path (Join-Path $web.Health.Options.BackupRoot $id) $op.Id
Invoke-WebHealth @{command='health-restore-preview';ids=@("$id/$($op.Id)")};Finish
if(!$web.Health.Restore){throw $web.Health.Status}
Invoke-WebHealth @{command='health-restore-approve';token=$web.Health.Restore.Id;approved=$true};Finish
if((Read-PkHealthJson (Join-Path $directory 'repair.json')).State -ne 'RESTORED'){throw $web.Health.Status}
$fixture02=Get-ChildItem "$root/work" -Directory -Filter 'health02-*'|Where-Object {[IO.File]::Exists((Join-Path $_.FullName 'reports/scan.json'))}|Sort-Object LastWriteTime -Descending|Select-Object -First 1
if($fixture02){
    $base=$fixture02.FullName
    $web.Health.Options=@{Root=(Join-Path $base 'Musik');FFmpeg=$FFmpeg;Probe=$Probe;Storage=(Join-Path $base 'reports');BackupRoot=(Join-Path $base 'backups');QuarantineRoot=(Join-Path $base 'quarantine');CoverRoot=(Join-Path $base 'covers');VdjDatabase=(Join-Path $base 'database-True.xml');Deep=$false}
    $web.Health.Report=Read-PkHealthJson (Join-Path $base 'reports/scan.json')
    $dbHash=Get-PkHealthFileHash $web.Health.Options.VdjDatabase
    Invoke-WebHealth @{command='health-vdj-analyze'};Finish
    if(!$web.Health.Vdj -or !$web.Health.Vdj.Writable){throw $web.Health.Status}
    Invoke-WebHealth @{command='health-vdj-plan';indices=@(0)};Finish
    if(!$web.Health.SpecialPlan -or $web.Health.SpecialPlan.Type -ne 'VDJ'){throw $web.Health.Status}
    Invoke-WebHealth @{command='health-special-approve';token='wrong';approved=$true}
    if($web.Health.Worker){throw 'Wrong special approval token accepted'}
    if((Get-PkHealthFileHash $web.Health.Options.VdjDatabase) -cne $dbHash){throw 'Read-only VDJ background operations changed database'}
}
Invoke-WebHealth @{command='health-mode';mode='advanced'}
$web.Health.Dirty=$true;Save-WebHealthOptions
$savedRoot=$web.Health.Options.Root
Initialize-WebHealth
if($web.Health.Mode -ne 'advanced' -or !$web.Health.Dirty -or $web.Health.Options.Root -ine $savedRoot -or !$web.Health.Report){throw 'Saved view, rescan marker, paths or report did not reload'}
$validProbe=$web.Health.Options.Probe
$web.Health.Options.Probe=Join-Path $fixtures.FullName 'missing-probe.exe'
Invoke-WebHealth @{command='health-scan';deep=$false;incremental=$false};Finish
if($web.Health.Status -notmatch 'Prüfprogramm fehlt' -or !$web.Health.Detail -or $messages[-1].busy){throw 'Missing tool did not produce actionable idle state'}
$web.Health.Options.Probe=$validProbe;Save-WebHealthOptions
'PASS: real GUI controller, background runspaces, scan serialization, approval token checks, repair and restore bridge, saved mode/report/rescan marker and actionable tool error.'

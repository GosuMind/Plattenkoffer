$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root
$testRoot=Join-Path $root ('work/health-installer-'+[guid]::NewGuid().ToString('N'))
$app=Join-Path $testRoot 'app'
[void][IO.Directory]::CreateDirectory((Join-Path $app '_internal'))
[void][IO.Directory]::CreateDirectory((Join-Path $app 'bin'))
foreach($name in @('yt-dlp.exe','bin/ffmpeg.exe','bin/ffprobe.exe','bin/ffplay.exe','bin/deno.exe')){[IO.File]::WriteAllText((Join-Path $app $name),'Isolated setup dependency fixture')}
$compiler=Join-Path $root 'work/inno-build/compiler/ISCC.exe'
& $compiler '/Qp' '/DIsolatedTest' ("/O$testRoot") '/FUsage-Installer-Test' (Join-Path $root 'setup/SetArchiv.iss')
if($LASTEXITCODE){throw 'Isolated installer build failed'}
$setup=Join-Path $testRoot 'Usage-Installer-Test.exe'
$arguments=@('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-','/TASKS=""',('/DIR="'+$app+'"'))
$blocked=Start-Process -FilePath $setup -WindowStyle Hidden -ArgumentList ($arguments+('/LOG="'+(Join-Path $testRoot 'blocked.log')+'"')) -Wait -PassThru
if($blocked.ExitCode -eq 0){throw 'Fresh silent install bypassed acknowledgement'}
if(Test-Path (Join-Path $app 'plattenkoffer.ini')){throw 'Install wrote app before acknowledgement'}
$blockedLog=Get-Content (Join-Path $testRoot 'blocked.log') -Raw
if($blockedLog -notmatch 'interaktiv starten'){throw 'Missing explanation in setup failure'}
$ack=Join-Path $app 'nutzungshinweis-bestaetigt.ini'
[IO.File]::WriteAllText($ack,"[Nutzungshinweis]`r`nVersion=2026-11-21.1`r`nZeitpunkt=2026-11-21 12:00:00`r`n",[Text.Encoding]::ASCII)
$accepted=Start-Process -FilePath $setup -WindowStyle Hidden -ArgumentList ($arguments+('/LOG="'+(Join-Path $testRoot 'accepted.log')+'"')) -Wait -PassThru
if($accepted.ExitCode -ne 0){throw "Acknowledged update failed: $($accepted.ExitCode). See $testRoot"}
$notice=[IO.File]::ReadAllText((Join-Path $app 'Nutzungshinweis.txt'))
if($notice -notmatch 'ausschließlich für rechtmäßige Nutzung' -or $notice -notmatch 'technischer Schutzmaßnahmen'){throw 'Installed notice incomplete'}
if([IO.File]::ReadAllText($ack) -notmatch 'Zeitpunkt=2026-11-21 12:00:00'){throw 'Silent update changed original acknowledgement time'}
$expected=(Select-String -LiteralPath (Join-Path $root 'setup/SetArchiv.iss') -Pattern '^#define AppVersion "(\d+\.\d+\.\d+)"$').Matches[0].Groups[1].Value
if((Get-Content (Join-Path $app 'plattenkoffer.ini') -Raw) -notmatch ('Version='+[regex]::Escape($expected))){throw 'Wrong installed version'}
foreach($name in @('DJ-Sets-Health.ps1','DJ-Sets-HealthRepair.ps1','DJ-Sets-HealthWeb.ps1','DJ-Sets-HealthVdj.ps1','DJ-Sets-HealthSemantic.ps1','DJ-Sets-HealthQuarantine.ps1','DJ-Sets-HealthCover.ps1','DJ-Sets-HealthJson.ps1','DJ-Sets-HealthReports.ps1','DJ-Sets-DownloadValidation.ps1','ui/health.js','ui/health02.js')){
 if(!(Test-Path -LiteralPath (Join-Path $app $name))){throw "Missing installed module: $name"}
}
'Installer OK: fresh silent installation blocked, acknowledged update succeeds, full notice and timestamp installed'

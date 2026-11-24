param([string]$FFmpeg,[string]$Probe,[switch]$DownloadTools,[switch]$SkipUI)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if($DownloadTools){
    $cache=Join-Path $root 'work/health-ci-tools';[void][IO.Directory]::CreateDirectory($cache)
    $archive=Join-Path $cache 'ffmpeg.zip'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/GyanD/codexffmpeg/releases/download/9.0.2/ffmpeg-9.0.2-essentials_build.zip' -OutFile $archive
    if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -cne '60F467265B1E312373DBCD92200C2618A74850F98D3D078E94296BB3FA2047BA'){throw 'FFmpeg-Paketprüfung fehlgeschlagen.'}
    Expand-Archive -LiteralPath $archive -DestinationPath $cache -Force
    $FFmpeg=Join-Path $cache 'ffmpeg-9.0.2-essentials_build/bin/ffmpeg.exe';$Probe=Join-Path $cache 'ffmpeg-9.0.2-essentials_build/bin/ffprobe.exe'
}
if(!$FFmpeg -or !$Probe){throw 'FFmpeg und FFprobe mit absoluten Pfaden übergeben oder -DownloadTools verwenden.'}
$powershell=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
foreach($test in @('Health.Tests.ps1','Health.Web.Tests.ps1')){
    & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "tests/$test") -FFmpeg $FFmpeg -Probe $Probe
    if($LASTEXITCODE){throw "Test fehlgeschlagen: $test"}
}
if(!$SkipUI){
    & node (Join-Path $PSScriptRoot 'tests/Health.UI.cjs')
    if($LASTEXITCODE){throw 'Health-UI-Test fehlgeschlagen.'}
}

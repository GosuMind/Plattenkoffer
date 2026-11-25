function Convert-PkAudioFile([string]$Source,[string]$Root,[string]$Extension,[string[]]$Options) {
    Assert-SafePath $Source
    Assert-SafePath $Root
    [void][IO.Directory]::CreateDirectory($Root)
    $stem=[IO.Path]::GetFileNameWithoutExtension($Source)
    $target=Join-Path $Root "$stem.$Extension"
    for ($suffix=2; (Test-Path -LiteralPath $target); $suffix++) {
        $target=Join-Path $Root "$stem ($suffix).$Extension"
    }
    $temporary=Join-Path $Root ('.pk-convert-' + [guid]::NewGuid().ToString('N') + ".$Extension")
    try {
        & $ffmpeg -nostdin -v error -n -i $Source -map 0:a:0 @Options $temporary
        if ($LASTEXITCODE -ne 0 -or ![IO.File]::Exists($temporary)) {
            throw 'FFmpeg konnte die Audiospur mit diesen Einstellungen nicht umwandeln.'
        }
        [IO.File]::Move($temporary,$target)
        $target
    } finally { [IO.File]::Delete($temporary) }
}

function Send-WebConversion($Values=@{}) {
    $job=$web.Conversion
    $payload=@{type='convert';busy=[bool]$job.Worker;status=$job.Status;report=$job.Report;files=@($job.Files | ForEach-Object { [IO.Path]::GetFileName($_) })}
    foreach ($key in $Values.Keys) { $payload[$key]=$Values[$key] }
    Send-WebCollectionMessage $payload
}

function Select-ConversionFiles {
    if ($web.Conversion.Worker) { return }
    $picker=[Windows.Forms.OpenFileDialog]@{ Title='Audioquellen auswählen'; Multiselect=$true; Filter='Audiodateien|*.mp3;*.flac;*.wav;*.aif;*.aiff;*.aac;*.m4a;*.opus;*.ogg;*.wma;*.webm;*.mp4;*.mkv|Alle Dateien|*.*' }
    try {
        if ($picker.ShowDialog($form) -eq 'OK') {
            $web.Conversion.Files=@($picker.FileNames | Select-Object -Unique)
            $web.Conversion.Report=''
            $web.Conversion.Status="$($web.Conversion.Files.Count) Dateien ausgewählt."
            Send-WebConversion
        }
    } finally { $picker.Dispose() }
}

function Select-ConversionFolder {
    if ($web.Conversion.Worker) { return }
    $picker=[Windows.Forms.FolderBrowserDialog]@{ Description='Zielordner für die umgewandelten Dateien auswählen' }
    try {
        if ($picker.ShowDialog($form) -eq 'OK') { Send-WebConversion @{destination=$picker.SelectedPath} }
    } finally { $picker.Dispose() }
}

function Start-WebConversion($Values) {
    $job=$web.Conversion
    if ($job.Worker) { return }
    try {
        if ($libraryView.Diagnostic.Worker) { throw 'Warte, bis der Diagnosevorgang beendet ist.' }
        if (!$job.Files.Count) { throw 'Bitte zuerst Audiodateien auswählen.' }
        $destination=[string]$Values.destination
        if ($destination -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)') { throw 'Bitte einen vollständigen Zielordner angeben.' }
        $root=[IO.Path]::GetFullPath($destination)
        Assert-SafePath $root
        $formats=@{
            MP3=@('mp3','libmp3lame',$true); FLAC=@('flac','flac',$false); WAV=@('wav','pcm_s24le',$false)
            AIFF=@('aiff','pcm_s24be',$false); 'M4A (AAC)'=@('m4a','aac',$true); 'M4A (ALAC)'=@('m4a','alac',$false)
            Opus=@('opus','libopus',$true); 'OGG (Vorbis)'=@('ogg','libvorbis',$true)
        }
        $format=$formats[[string]$Values.format]
        if (!$format) { throw 'Bitte ein Zielformat auswählen.' }
        $extension,$codec,$lossy=$format
        $options=@('-c:a',$codec)
        if ($lossy) {
            if ($Values.bitrate -notin @('64','96','128','160','192','256','320')) { throw 'Bitte eine gültige Bitrate wählen.' }
            $options+=@('-b:a',"$($Values.bitrate)k")
        }
        if ($Values.rate) {
            if ($Values.rate -notin @('44100','48000','96000') -or ($codec -eq 'libopus' -and $Values.rate -ne '48000') -or ($codec -eq 'libmp3lame' -and $Values.rate -eq '96000')) {
                throw 'Die Abtastrate wird für dieses Zielformat nicht angeboten.'
            }
            $options+=@('-ar',[string]$Values.rate)
        }
        if ($Values.channels) {
            if ($Values.channels -notin @('1','2')) { throw 'Bitte Mono, Stereo oder Automatisch wählen.' }
            $options+=@('-ac',[string]$Values.channels)
        }
        $script='param($ffmpeg,$Sources,$Root,$Extension,$Options); $ErrorActionPreference="Stop";'
        foreach ($fn in @('Assert-SafePath','Convert-PkAudioFile')) { $script+="function $fn { $((Get-Command $fn).Definition) };" }
        $script+=@'
foreach ($source in $Sources) {
    try {
        $target=Convert-PkAudioFile $source $Root $Extension $Options
        [pscustomobject]@{Success=$true;Text=$target}
    } catch { [pscustomobject]@{Success=$false;Text=([IO.Path]::GetFileName($source)+': '+$_.Exception.Message)} }
}
'@
        $job.Worker=[PowerShell]::Create()
        [void]$job.Worker.AddScript($script).AddArgument($ffmpeg).AddArgument($job.Files).AddArgument($root).AddArgument($extension).AddArgument($options)
        $job.Handle=$job.Worker.BeginInvoke()
        $job.Status='Dateien werden umgewandelt …'
        $job.Report=''
    } catch {
        if ($job.Worker) { $job.Worker.Dispose(); $job.Worker=$null }
        $job.Status=$_.Exception.Message
    }
    Send-WebConversion
}

function Complete-WebConversion {
    $job=$web.Conversion
    if (!$job.Worker -or !$job.Handle.IsCompleted) { return }
    try {
        $results=@($job.Worker.EndInvoke($job.Handle))
        $success=@($results | Where-Object Success).Count
        $job.Status="$success von $($job.Files.Count) Dateien umgewandelt."
        $job.Report=($results | ForEach-Object Text) -join "`r`n"
    } catch { $job.Status=$_.Exception.Message }
    finally { $job.Worker.Dispose(); $job.Worker=$null }
    Send-WebConversion
}

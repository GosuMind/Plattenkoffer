function Find-PkTransitionCandidates([string[]]$Files,[int]$Limit) {
    $culture=[Globalization.CultureInfo]::InvariantCulture
    $frames=[Collections.Generic.List[object]]::new()
    $base=0.0
    foreach ($file in $Files) {
        Assert-SafePath $file
        $duration=Get-PkSetAudioDuration (Get-Item -LiteralPath $file)
        $sample=$null
        $filter='aformat=channel_layouts=mono,aresample=8000,asetnsamples=n=16000:p=0,astats=metadata=1:reset=1:measure_perchannel=Zero_crossings_rate:measure_overall=RMS_level,ametadata=mode=print:file=-'
        $lines=& $ffmpeg -hide_banner -nostdin -loglevel error -i $file -map 0:a:0 -af $filter -f null NUL
        if ($LASTEXITCODE -ne 0) { throw "Audiodatei konnte nicht analysiert werden: $([IO.Path]::GetFileName($file))" }
        foreach ($line in $lines) {
            if ($line -match 'pts_time:([0-9.eE+-]+)') {
                $sample=@{Second=$base+[double]::Parse($Matches[1],$culture);Rms=-75.0;Cross=0.0}
                $frames.Add($sample)
            } elseif ($sample -and $line -match '^lavfi\.astats\.Overall\.RMS_level=([0-9.eE+-]+)$') {
                $sample.Rms=[Math]::Max(-75.0,[double]::Parse($Matches[1],$culture))
            } elseif ($sample -and $line -match '^lavfi\.astats\.1\.Zero_crossings_rate=([0-9.eE+-]+)$') {
                $sample.Cross=[double]::Parse($Matches[1],$culture)
            }
        }
        $base+=$duration
    }
    # Compare the immediate change with the sustained change on both sides.
    $raw=@(for ($i=12; $i -le $frames.Count-12; $i++) {
        $nearLeft=$frames[($i-3)..($i-1)]
        $nearRight=$frames[$i..($i+2)]
        $farLeft=$frames[($i-12)..($i-7)]
        $farRight=$frames[($i+6)..($i+11)]
        $score=0.0
        foreach ($feature in @('Rms','Cross')) {
            $near=($nearRight | ForEach-Object { $_[$feature] } | Measure-Object -Average).Average-($nearLeft | ForEach-Object { $_[$feature] } | Measure-Object -Average).Average
            $far=($farRight | ForEach-Object { $_[$feature] } | Measure-Object -Average).Average-($farLeft | ForEach-Object { $_[$feature] } | Measure-Object -Average).Average
            if ($near*$far -gt 0) {
                $weight=if ($feature -eq 'Rms') { 1/16 } else { 18 }
                $score+=$weight*[Math]::Min([Math]::Abs($near),[Math]::Abs($far))
            }
        }
        if ($score -ge 0.45) { [pscustomobject]@{second=[int][Math]::Round($frames[$i].Second);score=$score} }
    })
    $chosen=[Collections.Generic.List[object]]::new()
    $gap=[Math]::Max(8.0,[Math]::Min(45.0,$base/($Limit+1)/4))
    if ($Limit -gt 0) {
        foreach ($candidate in ($raw | Sort-Object score -Descending)) {
            if ($chosen | Where-Object { [Math]::Abs($_.second-$candidate.second) -lt $gap }) { continue }
            $chosen.Add($candidate)
            if ($chosen.Count -ge $Limit) { break }
        }
    }
    [pscustomobject]@{duration=[int][Math]::Ceiling($base);points=@($chosen.ToArray() | Sort-Object second | ForEach-Object second)}
}

function Start-WebTransitionScan($Entry,$Message) {
    $job=$web.TransitionScan
    if ($job.Worker) { throw 'Ein Set wird bereits gescannt.' }
    if ($libraryView.Diagnostic.Worker) { throw 'Warte, bis die Diagnose beendet ist.' }
    $files=@(Get-SetAudio $Entry.Path | ForEach-Object FullName)
    if (!$files.Count) { throw 'Keine Audiodateien im Set gefunden.' }
    $titles=@(([string]$Message.text -split '\r?\n') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($titles.Count -gt 200) { throw 'Bitte höchstens 200 Trackzeilen eingeben.' }
    $limit=60
    $script='param($ffmpeg,$probe,$Files,$Limit); $ErrorActionPreference="Stop";'
    foreach ($name in @('Assert-SafePath','Get-PkSetAudioDuration','Find-PkTransitionCandidates')) {
        $script+="function $name { $((Get-Command $name).Definition) };"
    }
    $script+='Find-PkTransitionCandidates $Files $Limit'
    $job.Id=$Message.id
    $job.Titles=$titles
    try {
        $job.Worker=[PowerShell]::Create()
        [void]$job.Worker.AddScript($script).AddArgument($ffmpeg).AddArgument($probe).AddArgument($files).AddArgument($limit)
        $job.Handle=$job.Worker.BeginInvoke()
    } catch { if ($job.Worker) { $job.Worker.Dispose();$job.Worker=$null }; throw }
    Send-WebCollectionMessage @{type='tracklist-scan';id=$job.Id;busy=$true;status='Set wird lokal gescannt …'}
}

function Complete-WebTransitionScan {
    $job=$web.TransitionScan
    if (!$job.Worker -or !$job.Handle.IsCompleted) { return }
    $response=@{type='tracklist-scan';id=$job.Id;busy=$false}
    try {
        $result=$job.Worker.EndInvoke($job.Handle) | Select-Object -Last 1
        $points=@(0)+@($result.points)
        $labels=@(if ($job.Titles.Count) { $job.Titles } else { $points | ForEach-Object { 'Unbekannt' } })
        $response.rows=@(for ($i=0;$i -lt $labels.Count;$i++) {
            $label=$labels[$i] -replace '^\d+\s*[.)]\s+',''
            $names=$label -split '\s+[-–—]\s+',2
            @{second=$(if (!$job.Titles.Count) { $points[$i] } else { $null })
              artist=$(if ($names.Count -eq 2) { $names[0] } else { '' });title=$names[-1]}
        })
        $response.points=$points
        $response.duration=$result.duration
        $response.status=if ($job.Titles.Count) { 'Wähle für jeden Track einen Zeitvorschlag oder gib seine Startzeit ein.' } else { 'Vorschläge bitte vorhören. Fehlende Zeiten kannst du ergänzen.' }
    } catch { $response.status=$_.Exception.Message }
    finally { $job.Worker.Dispose();$job.Worker=$null }
    Send-WebCollectionMessage $response
}

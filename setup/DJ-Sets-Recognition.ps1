function Get-RecognitionSamples {
    param(
        [Parameter(Mandatory)][double]$Duration,
        [ValidateSet('Track', 'Position', 'Set')][string]$Mode = 'Track',
        [double]$Position = 0
    )

    if ([double]::IsNaN($Duration) -or [double]::IsInfinity($Duration) -or $Duration -le 0) {
        throw 'Die Aufnahme hat keine bekannte Dauer.'
    }
    $length = [Math]::Min(12, $Duration)
    $lastStart = $Duration - $length
    switch ($Mode) {
        'Track' {
            [pscustomobject]@{ Start = [Math]::Min($lastStart, $Duration / 3); Length = $length }
        }
        'Position' {
            if ([double]::IsNaN($Position) -or $Position -lt 0 -or $Position -ge $Duration) {
                throw 'Die Wiedergabeposition liegt ausserhalb der Aufnahme.'
            }
            $start = [Math]::Min($lastStart, [Math]::Max(0, $Position - $length / 2))
            [pscustomobject]@{ Start = $start; Length = $length }
        }
        'Set' {
            for ($start = 0; $start -lt $lastStart; $start += 24) {
                [pscustomobject]@{ Start = $start; Length = $length }
            }
            [pscustomobject]@{ Start = $lastStart; Length = $length }
        }
    }
}

function Export-RecognitionSample {
    param(
        [Parameter(Mandatory)][string]$FFmpeg,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)]$Sample
    )

    $culture = [Globalization.CultureInfo]::InvariantCulture
    $start = ([double]$Sample.Start).ToString('0.######', $culture)
    $length = ([double]$Sample.Length).ToString('0.######', $culture)
    & $FFmpeg -nostdin -v error -n -ss $start -i $Source -t $length -map 0:a:0 -ac 1 -ar 44100 -c:a libmp3lame -b:a 96k -f mp3 $Destination
    if ($LASTEXITCODE -ne 0) { throw 'Der Audioausschnitt konnte nicht erstellt werden.' }
}

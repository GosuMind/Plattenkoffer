$logDirectory = Join-Path $env:LOCALAPPDATA 'SetArchiv\logs'
$errorLog = Join-Path $logDirectory 'fehler.log'

function Write-AppError([string]$Area, [string]$Detail) {
    try {
        [void][IO.Directory]::CreateDirectory($logDirectory)
        $guard = [IO.File]::Open((Join-Path $logDirectory 'write.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
        try {
            $encoding = [Text.UTF8Encoding]::new($false)
            $line = '{0:yyyy-MM-dd HH:mm:ss zzz} [{1}] {2}' -f [datetimeoffset]::Now, $Area, $Detail
            $line += [Environment]::NewLine
            if ([IO.File]::Exists($errorLog) -and ([IO.FileInfo]::new($errorLog).Length + $encoding.GetByteCount($line)) -ge 1MB) {
                $older = Join-Path $logDirectory 'fehler.alt.log'
                if ([IO.File]::Exists($older)) { [IO.File]::Replace($errorLog, $older, [NullString]::Value) }
                else { [IO.File]::Move($errorLog, $older) }
            }
            [IO.File]::AppendAllText($errorLog, $line, $encoding)
        } finally { $guard.Dispose() }
    } catch { Write-Warning 'Fehlerprotokoll konnte nicht geschrieben werden.' }
}

function Get-AppErrors {
    $recent = @(foreach ($name in 'fehler.alt.log', 'fehler.log') {
        $path = Join-Path $logDirectory $name
        if ([IO.File]::Exists($path)) { Get-Content -LiteralPath $path -Encoding UTF8 -Tail 30 }
    })
    if ($recent.Count) { ($recent | Select-Object -Last 30) -join [Environment]::NewLine }
    else { 'Keine protokollierten Fehler.' }
}



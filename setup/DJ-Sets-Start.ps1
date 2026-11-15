$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'DJ-Sets-Logging.ps1')
    & (Join-Path $PSScriptRoot 'DJ-Sets-GUI.ps1')
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    $message = $_.Exception.Message
    $cause = $_.Exception.GetBaseException()
    if ($cause -is [IO.IOException] -and ($cause.HResult -band 65535) -in @(32,33) -and
        $cause.Message -like '*dj-set-downloader.lock*') {
        $message = 'Der DJ-Set Downloader läuft bereits. Wechsle über die Taskleiste zum offenen Fenster oder schließe es vor einem Neustart.'
    }
    if (Get-Command Write-AppError -ErrorAction SilentlyContinue) {
        Write-AppError 'Start' ("Programmstart fehlgeschlagen ({0}, Code {1})." -f $cause.GetType().Name, $cause.HResult)
    }
    [void][Windows.Forms.MessageBox]::Show($message, 'DJ-Set Downloader')
    exit 1
}


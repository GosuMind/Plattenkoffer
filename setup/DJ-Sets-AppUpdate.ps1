param([string]$Installer, [string]$Version, [string]$SignerHash, [int]$AppProcessId)

function Test-AppUpdateInstaller([string]$Path, [version]$ExpectedVersion, [string]$ExpectedSigner) {
    if ($ExpectedSigner -notmatch '\A[0-9A-Fa-f]{64}\z') { throw 'Für diese Installation ist kein Update-Herausgeber hinterlegt.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or !$signature.SignerCertificate -or !$signature.TimeStamperCertificate) {
        throw 'Das Setup hat keine gültige Signatur mit Zeitstempel.'
    }
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try { $actualSigner = [BitConverter]::ToString($sha256.ComputeHash($signature.SignerCertificate.RawData)).Replace('-', '') }
    finally { $sha256.Dispose() }
    if ($actualSigner -ne $ExpectedSigner) { throw 'Das Setup stammt von einem anderen Herausgeberzertifikat.' }
    $file = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    if ($file.FileMajorPart -ne $ExpectedVersion.Major -or $file.FileMinorPart -ne $ExpectedVersion.Minor -or
        $file.FileBuildPart -ne $ExpectedVersion.Build -or $file.FilePrivatePart -ne 0) {
        throw 'Die signierte Setup-Version entspricht nicht der angebotenen Version.'
    }
}

function Install-AppUpdate([string]$SetupPath, [string]$AppDirectory) {
    $acknowledgement=Join-Path $env:LOCALAPPDATA 'SetArchiv\config\nutzungshinweis-bestaetigt.ini'
    $hasAcknowledgement=[IO.File]::Exists($acknowledgement) -and
        ([IO.File]::ReadAllText($acknowledgement) -match '(?m)^Version=2026-11-21\.1\s*$')
    $arguments = @('/NORESTART', '/NOCLOSEAPPLICATIONS',
        '/NORESTARTAPPLICATIONS', '/MERGETASKS="!migrate"', ('/DIR="{0}"' -f $AppDirectory),
        ('/LOG="{0}"' -f (Join-Path (Split-Path -Parent $SetupPath) 'install.log')))
    if ($hasAcknowledgement) { $arguments=@('/VERYSILENT','/SUPPRESSMSGBOXES')+$arguments }
    $windowStyle=if ($hasAcknowledgement) { 'Hidden' } else { 'Normal' }
    $setup = Start-Process -FilePath $SetupPath -ArgumentList $arguments -WindowStyle $windowStyle -PassThru -Wait
    if ($setup.ExitCode -ne 0) { throw "Setup meldet Fehlercode $($setup.ExitCode)." }
}

function Restart-Plattenkoffer([string]$AppDirectory) {
    $launcher = Join-Path $AppDirectory 'DJ-Sets-Start.ps1'
    $arguments = '-NoProfile -STA -ExecutionPolicy RemoteSigned -File "{0}"' -f $launcher
    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -WorkingDirectory $AppDirectory -ArgumentList $arguments
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    $closed = $false
    $failure = ''
    try {
        $app = Get-Process -Id $AppProcessId -ErrorAction SilentlyContinue
        if ($app -and !$app.WaitForExit(30000)) { throw 'Plattenkoffer wurde nicht rechtzeitig geschlossen.' }
        $closed = $true
        Test-AppUpdateInstaller $Installer ([version]$Version) $SignerHash
        Install-AppUpdate $Installer $PSScriptRoot
        [IO.File]::Delete($Installer)
    } catch { $failure = $_.Exception.Message }
    if ($closed) {
        try { Restart-Plattenkoffer $PSScriptRoot }
        catch { $failure += ' Plattenkoffer bitte über das Startmenü öffnen.' }
    }
    if ($failure) {
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show($failure, 'Plattenkoffer-Update', 'OK', 'Error')
        exit 1
    }
}

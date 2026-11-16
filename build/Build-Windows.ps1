param([string]$Compiler)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $root 'setup/SetArchiv.iss'
$output = Join-Path $root 'release'
[void][IO.Directory]::CreateDirectory($output)
if (!$Compiler) {
    $cache = Join-Path $root 'work/inno-build'
    [void][IO.Directory]::CreateDirectory($cache)
    $download = Join-Path $cache 'innosetup-6.7.4.exe'
    Invoke-WebRequest -Uri 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_4/innosetup-6.7.4.exe' -OutFile $download
    if ((Get-FileHash -LiteralPath $download).Hash -ne 'A549929319F9120716677C685535CA4671E4B937B5FDC87E2585F32D8EB30E8C') {
        throw 'Die SHA-256-Prüfsumme des Inno-Setup-Downloads stimmt nicht.'
    }
    $installDir = Join-Path $cache 'compiler'
    $process = Start-Process -FilePath $download -WindowStyle Hidden -Wait -PassThru -ArgumentList (
        '/PORTABLE=1 /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="{0}"' -f $installDir
    )
    if ($process.ExitCode) { throw "Inno Setup konnte nicht eingerichtet werden (Code $($process.ExitCode))." }
    $Compiler = Join-Path $installDir 'ISCC.exe'
}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'setup') -Filter '*.ps1' -File) {
    $tokens = $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
}
$entry = Select-String -LiteralPath $installer -Pattern '^OutputBaseFilename=([A-Za-z0-9.-]+)-\{#AppVersion\}$'
if (!$entry) { throw 'Der Installer-Dateiname fehlt.' }
$version = Select-String -LiteralPath $installer -Pattern '^#define AppVersion "(\d+\.\d+\.\d+)"$'
if (!$version) { throw 'Die Installer-Version fehlt.' }
if ($version.Matches[0].Groups[1].Value -notmatch '^(0|[1-9][0-9]*)\.[0-9]\.[0-9]$') {
    throw 'Die zweite und dritte Stelle der Versionsnummer müssen zwischen 0 und 9 liegen. Auf 0.2.9 folgt 0.3.0.'
}
$name = '{0}-{1}.exe' -f $entry.Matches[0].Groups[1].Value, $version.Matches[0].Groups[1].Value
$compilerArguments = @('/Qp', "/O$output")
$webViewRoot = Join-Path $root 'work/webview2'
$webViewPackage = Join-Path $webViewRoot 'package'
$webViewFiles = @('lib/net462/Microsoft.Web.WebView2.Core.dll','lib/net462/Microsoft.Web.WebView2.WinForms.dll','runtimes/win-x64/native/WebView2Loader.dll')
if ($webViewFiles | Where-Object { !(Test-Path -LiteralPath (Join-Path $webViewPackage $_) -PathType Leaf) }) {
    [void][IO.Directory]::CreateDirectory($webViewRoot)
    $webViewArchive = Join-Path $webViewRoot 'webview2.zip'
    Invoke-WebRequest -Uri 'https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/1.0.3485.44/microsoft.web.webview2.1.0.3485.44.nupkg' -OutFile $webViewArchive
    if ((Get-FileHash -LiteralPath $webViewArchive).Hash -ne 'BC09150B179246AC90189649B13BE8E6B11B3AC200E817E18DF106E1F3CF489E') {
        throw 'Die SHA-256-Prüfsumme des WebView2-SDK stimmt nicht.'
    }
    Expand-Archive -LiteralPath $webViewArchive -DestinationPath $webViewPackage -Force
}
$bootstrapper = Join-Path $webViewRoot 'MicrosoftEdgeWebview2Setup.exe'
if (!(Test-Path -LiteralPath $bootstrapper -PathType Leaf)) {
    Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' -OutFile $bootstrapper
}
$bootstrapperSignature = Get-AuthenticodeSignature -LiteralPath $bootstrapper
if ($bootstrapperSignature.Status -ne 'Valid' -or $bootstrapperSignature.SignerCertificate.Subject -notmatch '^CN=Microsoft Corporation(?:,|$)') {
    throw 'Der WebView2-Installer hat keine gültige Microsoft-Signatur.'
}
if ($env:PK_UPDATE_SIGNER_SHA256) {
    if ($env:PK_UPDATE_SIGNER_SHA256 -notmatch '\A[0-9A-Fa-f]{64}\z') { throw 'Ungültiger SHA-256-Fingerabdruck für den Update-Herausgeber.' }
    $compilerArguments += "/DUpdateSignerHash=$env:PK_UPDATE_SIGNER_SHA256"
}
& $Compiler @compilerArguments $installer
if ($LASTEXITCODE) { throw "Installer-Build fehlgeschlagen (Code $LASTEXITCODE)." }
$hash = (Get-FileHash -LiteralPath (Join-Path $output $name)).Hash
Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Value "$hash  $name" -Encoding Ascii

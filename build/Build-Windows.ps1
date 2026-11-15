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
$entry = Select-String -LiteralPath $installer -Pattern '^OutputBaseFilename=([A-Za-z0-9.-]+)$'
if (!$entry) { throw 'Der Installer-Dateiname fehlt.' }
$name = $entry.Matches[0].Groups[1].Value + '.exe'
& $Compiler /Qp "/O$output" $installer
if ($LASTEXITCODE) { throw "Installer-Build fehlgeschlagen (Code $LASTEXITCODE)." }
$hash = (Get-FileHash -LiteralPath (Join-Path $output $name)).Hash
Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Value "$hash  $name" -Encoding Ascii

function Update-YtDlpPackage([string]$Root) {
    $ErrorActionPreference = 'Stop'
    $api = 'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest'
    $release = Invoke-RestMethod -Uri $api -TimeoutSec 30
    $tag = [string]$release.tag_name
    $asset = @($release.assets | Where-Object name -eq 'yt-dlp_win.zip')
    if ($tag -notmatch '^\d{4}\.\d{2}\.\d{2}(?:\.\d+)?$' -or $asset.Count -ne 1 -or
        $asset[0].digest -notmatch '^sha256:([a-fA-F0-9]{64})$') {
        throw 'Das offizielle Release enthält keine verwendbare SHA-256-Prüfsumme.'
    }
    $expected = $Matches[1]
    $backupRoot = Join-Path $Root 'Sicherungen'
    Assert-SafePath $backupRoot
    $job = Join-Path $Root ('.yt-dlp-update-' + [guid]::NewGuid().ToString('N'))
    $null = [IO.Directory]::CreateDirectory($job)
    try {
        $zip = Join-Path $job 'yt-dlp_win.zip'
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/yt-dlp/yt-dlp/releases/download/$tag/yt-dlp_win.zip" -OutFile $zip -TimeoutSec 180
        if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $expected) {
            throw 'SHA-256 stimmt nicht. Die installierte Version wurde nicht verändert.'
        }
        $package = Join-Path $job 'package'
        Expand-Archive -LiteralPath $zip -DestinationPath $package
        $names = @('yt-dlp.exe', '_internal')
        foreach ($base in @($Root, $package)) {
            $exe = Join-Path $base $names[0]
            $internal = Join-Path $base $names[1]
            Assert-SafePath $exe
            Assert-SafePath $internal
            if (![IO.File]::Exists($exe) -or ![IO.Directory]::Exists($internal)) {
                throw "Das Windows-Paket ist unvollständig: $base"
            }
        }
        $current = & (Join-Path $Root 'yt-dlp.exe') --ignore-config --version
        if ($LASTEXITCODE -ne 0) { $current = '' }

        if ($current -match '^\d+(\.\d+){2,3}$' -and [version]$current -gt [version]$tag) {
            throw "Die installierte Version $current ist neuer als $tag."
        }
        $backup = Join-Path $backupRoot ('yt-dlp-' + (Get-Date -Format yyyyMMdd-HHmmss-fff))
        $null = [IO.Directory]::CreateDirectory($backup)
        $saved = [Collections.Generic.List[string]]::new()
        $activated = [Collections.Generic.List[string]]::new()
        try {
            foreach ($name in $names) {
                Move-Item -LiteralPath (Join-Path $Root $name) -Destination (Join-Path $backup $name)
                $saved.Add($name)
            }
            foreach ($name in $names) {
                Move-Item -LiteralPath (Join-Path $package $name) -Destination (Join-Path $Root $name)
                $activated.Add($name)
            }
            $version = & (Join-Path $Root 'yt-dlp.exe') --ignore-config --version
            if ($LASTEXITCODE -ne 0 -or $version -ne $tag) { throw 'Die neue Version konnte nicht geprüft werden.' }
        } catch {
            $failure = $_
            try {
                foreach ($name in $activated) {
                    Move-Item -LiteralPath (Join-Path $Root $name) -Destination (Join-Path $package $name)
                }
                foreach ($name in $saved) {
                    Move-Item -LiteralPath (Join-Path $backup $name) -Destination (Join-Path $Root $name)
                }
            } catch { throw "Wiederherstellung fehlgeschlagen. Sicherung: $backup. $($_.Exception.Message)" }
            throw $failure
        }
        "yt-dlp $tag installiert. Sicherung: $backup"
    } finally {
        if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($job)) -eq [IO.Path]::GetFullPath($Root).TrimEnd('\')) {
            Assert-SafePath $job
            Remove-Item -LiteralPath $job -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}


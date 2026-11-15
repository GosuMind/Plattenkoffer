function Update-AudioTool([string]$Root, [ValidateSet('FFmpeg','Deno')][string]$Tool) {
    $ErrorActionPreference = 'Stop'
    if ($Tool -eq 'FFmpeg') {
        $url = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
        $checksum = (Invoke-WebRequest -UseBasicParsing -Uri "$url.sha256" -TimeoutSec 30).Content.Trim()
        if ($checksum -notmatch '^[a-fA-F0-9]{64}$') { throw 'Ungültige SHA-256-Prüfsumme für FFmpeg.' }
        $names = @('ffmpeg.exe','ffprobe.exe')
        $versionArg = '-version'
    } else {
        $release = Invoke-RestMethod 'https://api.github.com/repos/denoland/deno/releases/latest' -TimeoutSec 30
        $tag = [string]$release.tag_name
        $asset = @($release.assets | Where-Object name -eq 'deno-x86_64-pc-windows-msvc.zip')
        if ($tag -notmatch '^v\d+\.\d+\.\d+$' -or $asset.Count -ne 1 -or $asset[0].digest -notmatch '^sha256:([a-fA-F0-9]{64})$') {
            throw 'Deno-Release ohne gültige SHA-256-Prüfsumme.'
        }
        $checksum = $Matches[1]
        $url = "https://github.com/denoland/deno/releases/download/$tag/deno-x86_64-pc-windows-msvc.zip"
        $names = @('deno.exe')
        $versionArg = '--version'
    }
    $binPath = Join-Path $Root 'bin'
    $backupRoot = Join-Path $Root 'Sicherungen'
    Assert-SafePath $backupRoot
    $job = Join-Path $Root ('.tool-update-' + [guid]::NewGuid().ToString('N'))
    Assert-SafePath $job
    [void][IO.Directory]::CreateDirectory($job)
    try {
        $zip = Join-Path $job 'release.zip'
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip -TimeoutSec 180
        if ((Get-FileHash -LiteralPath $zip).Hash -ne $checksum) { throw "SHA-256 stimmt nicht für $Tool." }
        $package = Join-Path $job 'package'
        Expand-Archive -LiteralPath $zip -DestinationPath $package
        $files = [ordered]@{}
        $changed = $false
        foreach ($name in $names) {
            $candidates = @(Get-ChildItem -LiteralPath $package -Recurse -File -Filter $name)
            if ($candidates.Count -ne 1) { throw "Im Paket fehlt eine eindeutige Datei: $name" }
            $target = Join-Path $binPath $name
            Assert-SafePath $target
            Assert-SafePath $candidates[0].FullName
            $files[$target] = $candidates[0].FullName
            if ((Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath $files[$target]).Hash) { $changed = $true }
        }
        if (!$changed) { return "$Tool ist bereits aktuell." }
        $backup = Join-Path $backupRoot ("$Tool-" + (Get-Date -Format yyyyMMdd-HHmmss-fff))
        Assert-SafePath $backup
        [void][IO.Directory]::CreateDirectory($backup)
        $installed = [Collections.Generic.List[string]]::new()
        try {
            foreach ($target in $files.Keys) {
                [IO.File]::Replace($files[$target], $target, (Join-Path $backup ([IO.Path]::GetFileName($target))))
                $installed.Add($target)
            }
            foreach ($target in $files.Keys) {
                $lines = @(& $target $versionArg)
                if ($LASTEXITCODE -ne 0 -or !$lines.Count) { throw "Versionsprüfung fehlgeschlagen: $target" }
                if ($Tool -eq 'Deno' -and $lines[0] -notmatch ('^deno ' + [regex]::Escape($tag.Substring(1)) + '(?:\s|$)')) {
                    throw 'Die Deno-Version stimmt nicht mit dem Release überein.'
                }
            }
        } catch {
            $failure = $_
            foreach ($target in $installed) {
                $old = Join-Path $backup ([IO.Path]::GetFileName($target))
                [IO.File]::Copy($old, $files[$target])
                [IO.File]::Replace($files[$target], $target, [NullString]::Value)
            }
            throw $failure
        }
        "$Tool aktualisiert. Sicherung: $backup"
    } finally {
        if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($job)) -eq [IO.Path]::GetFullPath($Root).TrimEnd('\')) {
            Assert-SafePath $job
            Remove-Item -LiteralPath $job -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

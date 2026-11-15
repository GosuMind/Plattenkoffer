param(
    [Parameter(Mandatory)][ValidateSet('yt-dlp','Deno','FFmpeg')][string]$Tool,
    [Parameter(Mandatory)][string]$File,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$Sha256,
    [string]$ProbeFile,
    [string]$ProbeSha256
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DJ-Sets-Download.ps1') -LibraryOnly -ToolRoot $PSScriptRoot
$updates = [ordered]@{}
switch ($Tool) {
    'yt-dlp' { $updates[$yt] = @($File,$Sha256) }
    'Deno' { $updates[$deno] = @($File,$Sha256) }
    'FFmpeg' {
        if (!$ProbeFile -or $ProbeSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Für FFmpeg sind auch ffprobe und dessen SHA-256 erforderlich.' }
        $updates[$ffmpeg] = @($File,$Sha256)
        $updates[$probe] = @($ProbeFile,$ProbeSha256)
    }
}
$lockPath = Join-Path $config 'dj-set-downloader.lock'
Assert-SafePath $lockPath
$lock = [IO.File]::Open($lockPath,'OpenOrCreate','ReadWrite','None')
$staged = [ordered]@{}
$installed = [Collections.Generic.List[string]]::new()
$stamp = [guid]::NewGuid().ToString('N')
try {
    foreach ($target in $updates.Keys) {
        Assert-SafePath $target
        $source,$expected = $updates[$target]
        Assert-SafePath $source
        $stage = "$target.$stamp.new"
        $staged[$target] = $stage
        [IO.File]::Copy((Resolve-Path -LiteralPath $source).Path,$stage)
        if ((Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash -ne $expected) { throw "SHA-256 stimmt nicht: $source" }
    }
    foreach ($target in $staged.Keys) {
        [IO.File]::Replace($staged[$target],$target,"$target.$stamp.bak")
        $installed.Add($target)
    }
} catch {
    foreach ($target in $installed) { [IO.File]::Replace("$target.$stamp.bak",$target,[NullString]::Value) }
    throw
} finally {
    foreach ($stage in $staged.Values) { [IO.File]::Delete($stage) }
    $lock.Dispose()
}
Write-Output "$Tool aktualisiert. Sicherungskennung: $stamp"

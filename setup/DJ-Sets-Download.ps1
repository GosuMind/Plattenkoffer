param(
    [string]$ToolRoot = 'D:\YT-DLP',
    [string]$MusicRoot = ([Environment]::GetFolderPath('MyMusic')), [switch]$LibraryOnly
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$yt = Join-Path $ToolRoot 'yt-dlp.exe'
$bin = Join-Path $ToolRoot 'bin'
$ffmpeg = Join-Path $bin 'ffmpeg.exe'
$probe = Join-Path $bin 'ffprobe.exe'
$deno = Join-Path $bin 'deno.exe'
$config = Join-Path $env:LOCALAPPDATA 'SetArchiv\config'
$archive = Join-Path $config 'downloaded.txt'
$common = @('--ignore-config', '--encoding', 'utf-8', '--ffmpeg-location', $bin,
    '--js-runtimes', "deno:$deno")
$utf8 = [Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'DJ-Sets-Health.ps1')
. (Join-Path $PSScriptRoot 'DJ-Sets-DownloadValidation.ps1')

function Assert-SafePath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    for ($current = $full; $current; $current = [IO.Path]::GetDirectoryName($current)) {
        try { $attributes = [IO.File]::GetAttributes($current) }
        catch [IO.FileNotFoundException] { continue }
        catch [IO.DirectoryNotFoundException] { continue }
        if ($attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Der Pfad enthält eine Verknüpfung: $current"
        }
    }
}

function Write-AtomicText($Path, $Value) {
    Assert-SafePath $Path
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($temp, $Value, $utf8)
    try {
        if ([IO.File]::Exists($Path)) {
            [IO.File]::Replace($temp, $Path, [NullString]::Value)
        } else {
            [IO.File]::Move($temp, $Path)
        }
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
}

function Safe-Name([string]$Value) {
    $name = ($Value -replace '[<>:"/\\|?*\x00-\x1f]', '_' -replace '\s+', ' ').Trim(' ', '.')
    if ($name.Length -gt 70) {
        $name = $name.Substring(0, 70).TrimEnd(' ', '.')
        if ($name -and [char]::IsHighSurrogate($name[$name.Length - 1])) { $name = $name.Substring(0, $name.Length - 1) }
        $name = $name.TrimEnd(' ', '.')
    }
    if (!$name) { return 'Unbekannt' }
    if ($name -match '^(CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[1-9¹²³]|LPT[1-9¹²³]) *(\.|$)') {
        return "_$name"
    }
    return $name
}

function Get-Preview($Url, $Playlist, $Aliases) {
    [string[]]$mode = @(if ($Playlist) { @('--yes-playlist', '--flat-playlist') } else { '--no-playlist' })
    $errorFile = [IO.Path]::GetTempFileName()
    $previousPreference = $ErrorActionPreference
    try {
        # Windows PowerShell treats native stderr warnings as errors.
        $ErrorActionPreference = 'Continue'
        $PSNativeCommandUseErrorActionPreference = $false
        $json = & $yt @common @mode --ignore-errors --skip-download --dump-json -- $Url 2> $errorFile
        $exitCode = $LASTEXITCODE
        $diagnostics = [IO.File]::ReadAllText($errorFile)
    } finally {
        $ErrorActionPreference = $previousPreference
        [IO.File]::Delete($errorFile)
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in $json) {
        $item = ConvertFrom-Json -InputObject $line
        if ($item.id -cnotmatch '^[a-zA-Z0-9_-]{11}$') { continue }
        # YouTube IDs are case-sensitive.
        if (!$seen.Add($item.id)) { continue }
        $title = [string]$item.title
        if (!$title -or $title -match '^\[(Private|Deleted|Unavailable) video\]$' -or
            $item.availability -in @('private','premium_only','subscriber_only','needs_auth','unavailable')) { continue }
        $artist = [string]$item.artist
        $source = 'YouTube-Metadaten'
        $review = !$artist
        if (!$artist) {
            $known = [ordered]@{
                'Sven Väth' = 'Sven\s+V[äa]th'
                'Pascal F.E.O.S' = 'Pascal\s+F\.?\s*E\.?\s*O\.?\s*S\.?'
                'DJ Dag' = 'DJ\s+Dag'
                'Ulli Brenner' = 'Ulli\s+Brenner'
                'DJ Taucher' = '(?:DJ\s+)?Taucher'
                'Torsten Fenslau' = 'Torsten\s+Fenslau'
                'Mark Spoon' = 'Mark\s+Spoon'
            }
            $custom = [ordered]@{}
            foreach ($alias in $Aliases) {
                $pattern = [regex]::Escape($alias.Alias)
                if ($custom.Contains($alias.Name)) { $pattern = "$pattern|$($custom[$alias.Name])" }
                $custom[$alias.Name] = $pattern
            }
            $names = @(foreach ($name in $custom.Keys) {
                $match = [regex]::Match($title, "(?i)(?<![\p{L}\p{N}])(?:$($custom[$name]))(?![\p{L}\p{N}])")
                if ($match.Success) { [pscustomobject]@{ Name = $name; Index = $match.Index } }
            })
            $customPositions = @($names | ForEach-Object Index)
            $names += @(foreach ($name in $known.Keys) {
                $match = [regex]::Match($title, "(?i)(?<![\p{L}\p{N}])(?:$($known[$name]))(?![\p{L}\p{N}])")
                if ($match.Success -and $match.Index -notin $customPositions) { [pscustomobject]@{ Name = $name; Index = $match.Index } }
            })
            if ($names.Count -and $title -notmatch '(?i)\b(tribute|widmung|gedenken|in memory of)\b') {
                $artist = ($names | Sort-Object Index | ForEach-Object Name | Select-Object -Unique) -join ' & '
                $source = 'DJ-Namen im Videotitel'
                $review = ($names.Name | Select-Object -Unique | Measure-Object).Count -gt 1
            } elseif ($title -match '^(.+?)\s+(?:[-–—|@]|at\b|live\b)\s+\S' -and
                $Matches[1] -notmatch '(?i)\b(clubnight|tribute|maximal|hessentag|special|recording|tapes?)\b' -and
                $title -notmatch '(?i)\b(tribute|widmung|gedenken|in memory of)\b') {
                $artist = $Matches[1].Trim()
                $source = 'Vorschlag aus Videotitel'
            } else {
                $artist = ''
                $source = 'DJ unklar'
            }
        }
        if ($artist -and $title -match '^(.+?)\s+[-–—|]\s+(.+)$' -and $Matches[1].Trim() -eq $artist) {
            $title = $Matches[2].Trim()
        }
        [pscustomobject]@{
            Id = $item.id; Artist = $artist; Title = $title; Original = $item.title
            Type = if ($item.duration -gt 0 -and $item.duration -le 900 -and $item.title -notmatch '(?i)\b(?:DJ set|clubnight|live set|boiler room)\b') { 'Track' } else { 'Set' }
            Source = $source; Selected = $true; Review = $review
        }
    }
    if ($diagnostics.Trim()) { Write-Warning $diagnostics.Trim() }
    if ($exitCode -ne 0) {
        Write-Warning "YouTube lieferte die Vorschau nur teilweise oder gar nicht (Code $exitCode)."
    }
}

function Edit-Preview($Rows) {
    while ($true) {
        Write-Host ''
        for ($i = 0; $i -lt $Rows.Count; $i++) {
            $row = $Rows[$i]
            $status = if ($archiveIds.Contains("youtube $($row.Id)")) { 'archiviert' }
                elseif (!$row.Selected) { 'ausgelassen' } elseif ($row.Review) { 'DJ prüfen' } else { 'bereit' }
            Write-Host ("{0,3}. [{1}] {2} / {3} ({4})" -f ($i + 1), $status,
                (Safe-Name $row.Artist), (Safe-Name $row.Title), $row.Source)
            if ($row.Original -ne $row.Title) { Write-Host "     Original: $($row.Original)" }
        }
        $action = (Read-Host '[D]ownload, [K]ünstler, [T]itel, [A]uswahl umschalten, [Enter] zurück').Trim()
        if (!$action) { return $false }
        if ($action -eq 'd') {
            foreach ($row in $Rows) {
                if (!$row.Selected -or !$row.Review -or $archiveIds.Contains("youtube $($row.Id)")) { continue }
                Write-Host $row.Original
                $answer = (Read-Host "DJ [$($row.Artist)] eingeben, Enter bestätigt einen Vorschlag, - überspringt").Trim()
                if ($answer -eq '-') { $row.Selected = $false; continue }
                if ($answer) { $row.Artist = $answer }
                if (!$row.Artist) { Write-Warning 'Bitte DJ eingeben oder das Set überspringen.'; break }
                $row.Review = $false
            }
            if (!($Rows | Where-Object { $_.Selected -and $_.Review -and !$archiveIds.Contains("youtube $($_.Id)") })) { return $true }
            continue
        }
        if ($action -notin @('k', 't', 'a')) { continue }
        $selection = (Read-Host 'Zeilennummern (z. B. 1,3-5 oder * für alle)').Trim()
        $indices = [Collections.Generic.HashSet[int]]::new()
        $valid = $true
        if ($selection -eq '*') {
            foreach ($n in 1..$Rows.Count) { [void]$indices.Add($n) }
        } else {
            foreach ($part in ($selection -split ',')) {
                if ($part.Trim() -notmatch '^(\d{1,9})(?:\s*-\s*(\d{1,9}))?$') {
                    $valid = $false
                    break
                }
                $first = [int]$Matches[1]
                $last = if ($Matches[2]) { [int]$Matches[2] } else { $first }
                if ($first -lt 1 -or $last -lt $first -or $last -gt $Rows.Count) {
                    $valid = $false
                    break
                }
                foreach ($n in $first..$last) { [void]$indices.Add($n) }
            }
        }
        if (!$valid -or !$indices.Count) { Write-Warning 'Ungültige Auswahl.'; continue }
        $value = if ($action -eq 'k') { (Read-Host 'Neuer Künstler').Trim() }
            elseif ($action -eq 't') { (Read-Host 'Neuer Set-Titel').Trim() }
        if ($action -ne 'a' -and !$value) { continue }
        foreach ($n in $indices) {
            $row = $Rows[$n - 1]
            switch ($action) {
                'k' { $row.Artist = $value; $row.Source = 'manuell'; $row.Review = $false }
                't' { $row.Title = $value }
                'a' { $row.Selected = !$row.Selected }
            }
        }
    }
}

function Get-SetTarget($Root, $Row, $Reserved) {
    $id = $Row.Id
    $category = if ($Row.Type -eq 'Track') { 'Tracks' } else { 'Sets' }
    $parent = Join-Path (Join-Path $Root (Safe-Name $Row.Artist)) $category
    $title = Safe-Name $Row.Title
    $target = Join-Path $parent $title
    if ((Test-Path -LiteralPath $target) -or ($Reserved -and $Reserved.Contains($target))) {
        $target = Join-Path $parent "$title [$id]"
        $suffix = 2
        while ((Test-Path -LiteralPath $target) -or ($Reserved -and $Reserved.Contains($target))) {
            $target = Join-Path $parent "$title [$id] ($suffix)"
            $suffix++
        }
    }
    return $target
}

function Save-Set($Row) {
    $id = $Row.Id
    if ($id -cnotmatch '^[a-zA-Z0-9_-]{11}$') { throw 'Ungültige YouTube-ID.' }
    $key = "youtube $id"
    if ($archiveIds.Contains($key)) { return }
    # Work on the same volume as the library so publishing is a directory rename.
    $idFolder = '{0}-{1}' -f $id, [BitConverter]::ToString([Text.Encoding]::ASCII.GetBytes($id))
    $job = Join-Path $jobs $idFolder
    $payload = Join-Path $job 'set'
    $journal = Join-Path $job 'target.txt'
    Assert-SafePath $job
    foreach ($entry in (Get-ChildItem -LiteralPath $job -Force -ErrorAction SilentlyContinue)) {
        Assert-SafePath $entry.FullName
    }
    [void][IO.Directory]::CreateDirectory($job)
    $published = $false
    if ([IO.File]::Exists($journal) -and ![IO.Directory]::Exists($payload)) {
        $previous = [IO.File]::ReadAllText($journal, $utf8)
        $null=Assert-PkHealthScope $previous $MusicRoot
        Assert-SafePath $previous
        $previousInfo = Join-Path $previous 'info.json'
        if ([IO.File]::Exists($previousInfo)) {
            $published = (Get-Content -LiteralPath $previousInfo -Raw -Encoding UTF8 | ConvertFrom-Json).id -ceq $id
        }
    }
    if ($published) { $target = $previous }
    if (!$published) {
        $target = Get-SetTarget $MusicRoot $Row
        Assert-SafePath $target
        $parent = Split-Path -Parent $target
        [void][IO.Directory]::CreateDirectory($payload)
        Write-AtomicText $journal $target
        Write-Host "Download: $($Row.Artist) / $($Row.Title)"
        $info = Join-Path $job 'source.info.json'
        $images = @('jpg', 'jpeg', 'png', 'webp', 'avif') | ForEach-Object { Join-Path $job "source.$_" }
        $cover = $images | Where-Object { [IO.File]::Exists($_) -and [IO.FileInfo]::new($_).Length -gt 0 } |
            Select-Object -First 1
        $ready = Join-Path $job 'downloaded.txt'
        if (![IO.File]::Exists($ready) -or ![IO.File]::Exists($info) -or !$cover) {
            $template = (Join-Path $job 'source').Replace('%', '%%') + '.%(ext)s'
            $format = 'bestaudio[acodec=opus]/bestaudio[acodec^=mp4a]/bestaudio[acodec=aac]'
            & $yt @common --no-playlist --format $format --continue --no-overwrites --no-mtime `
                --retries 10 --fragment-retries 10 --abort-on-unavailable-fragments `
                --write-info-json --write-thumbnail --newline --output $template -- "https://www.youtube.com/watch?v=$id"
            if ($LASTEXITCODE -ne 0) { throw "yt-dlp meldete Fehlercode $LASTEXITCODE." }
            $cover = $images | Where-Object { [IO.File]::Exists($_) -and [IO.FileInfo]::new($_).Length -gt 0 } |
                Select-Object -First 1
            if (![IO.File]::Exists($info) -or !$cover) { throw 'Cover oder info.json fehlt.' }
            Write-AtomicText $ready $key
        }
        $metadata = Get-Content -LiteralPath $info -Encoding UTF8 -Raw | ConvertFrom-Json
        if ($metadata.id -cne $id -or $metadata.ext -notin @('webm', 'm4a', 'mp4', 'aac', 'opus', 'ogg')) {
            throw 'Die gespeicherten Metadaten passen nicht zur Audiodatei.'
        }
        $source = Join-Path $job "source.$($metadata.ext)"
        $codec = & $probe -v error -select_streams a:0 -show_entries stream=codec_name -of 'csv=p=0' $source
        if ($LASTEXITCODE -ne 0 -or $codec -notin @('opus', 'aac')) { throw 'Audiospur konnte nicht geprüft werden.' }
        $extension = if ($codec -eq 'opus') { 'opus' } else { 'm4a' }
        $audioTemp = Join-Path $job "audio.tmp.$extension"
        Get-ChildItem -LiteralPath $payload -File | Where-Object { $_.Name -in @("audio.opus", "audio.m4a", "info.json", "cover.jpg", "cover.jpeg", "cover.png", "cover.webp", "cover.avif") } | Remove-Item
        Complete-PkDownloadPayload $Row $source $audioTemp $payload $info $cover
        [void][IO.Directory]::CreateDirectory($parent)
        [IO.Directory]::Move($payload, $target)
        Write-Host "Gespeichert: $target" -ForegroundColor Green
    }
    Assert-PkPublishedDownload $target $Row
    $existing = if ([IO.File]::Exists($archive)) { [IO.File]::ReadAllText($archive, $utf8).TrimEnd("`r", "`n") }
    $lines = if ($existing) { "$existing`r`n$key`r`n" } else { "$key`r`n" }
    Write-AtomicText $archive $lines
    [void]$archiveIds.Add($key)
    try {
        # Delete only the files owned by this job. Leave anything unexpected alone.
        foreach ($name in @('target.txt', 'downloaded.txt', 'audio.tmp.opus', 'audio.tmp.m4a',
                'source.info.json', 'source.webm', 'source.m4a', 'source.mp4', 'source.aac',
                'source.opus', 'source.ogg', 'source.jpg', 'source.jpeg', 'source.png', 'source.webp', 'source.avif')) {
            [IO.File]::Delete((Join-Path $job $name))
        }
        [IO.Directory]::Delete($job, $false)
    } catch {
        Write-Warning "Arbeitsordner blieb erhalten: $job"
    }
    [pscustomobject]@{ SavedSetPath = $target }
}

if ($LibraryOnly) { return }

foreach ($exe in @($yt, $ffmpeg, $probe, $deno)) {
    if (![IO.File]::Exists($exe)) { throw "Programm fehlt: $exe" }
}
$ToolRoot = [IO.Path]::GetFullPath($ToolRoot)
$MusicRoot = [IO.Path]::GetFullPath($MusicRoot)
Assert-SafePath $archive
[void][IO.Directory]::CreateDirectory($config)
$jobs = Join-Path $MusicRoot '.dj-set-downloads'
$lockPath = Join-Path $config 'dj-set-downloader.lock'
try {
    Assert-SafePath $lockPath
    $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
} catch {
    throw "Das Archiv konnte nicht exklusiv geöffnet werden: $lockPath"
}
try {
    $archiveIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ([IO.File]::Exists($archive)) {
        foreach ($line in [IO.File]::ReadLines($archive, $utf8)) { [void]$archiveIds.Add($line.Trim()) }
    }
    while ($true) {
        $link = (Read-Host 'YouTube-Link (Enter beendet)').Trim().Trim('"', "'")
        if (!$link) { break }
        $uri = $null
        if ($link -notmatch '^https?://' -or ![uri]::TryCreate($link, [UriKind]::Absolute, [ref]$uri) -or
            $uri.Host -notmatch '^(?:[a-z0-9-]+\.)*youtube\.com$|^(?:www\.)?youtu\.be$') {
            Write-Warning 'Bitte einen vollständigen YouTube-Link eingeben.'
            continue
        }
        $playlist = $uri.Query -match '(?:[?&])list=[^&]+' -or $uri.AbsolutePath -eq '/playlist'
        if ($playlist -and $uri.AbsolutePath -ne '/playlist') {
            $playlist = (Read-Host 'Ganze Playlist laden? [J/n]') -ne 'n'
        }
        if (!$playlist -and $uri.AbsolutePath -notmatch '^/(watch|shorts/[^/]+|live/[^/]+|embed/[^/]+|[^/]{11})/?$') {
            Write-Warning 'Bitte einen Video- oder Playlist-Link eingeben.'
            continue
        }
        try {
            $rows = @(Get-Preview $link $playlist)
            if (!$rows.Count) { Write-Warning 'Keine verfügbaren Videos gefunden.'; continue }
            if (Edit-Preview $rows) {
                foreach ($row in $rows) {
                    if (!$row.Selected) { continue }
                    try { Save-Set $row | Where-Object { $_ -is [string] } } catch {
                        Write-Warning "Set $($row.Id): $($_.Exception.Message) Erneut mit demselben Link versuchen."
                    }
                }
            }
        } catch {
            Write-Warning $_.Exception.Message
        }
    }
} finally {
    $lock.Dispose()
}












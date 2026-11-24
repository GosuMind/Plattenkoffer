function Get-PkDefaultPreferences {
    @{TileSize=180;Accent='Rost';Density='Normal';FontScale=100;ShowDetails=$true;DefaultView='auto';Sort='artist';StartVolume=80;ResumeSets=$true;AutoNext=$false;Shuffle=$false;Repeat='off';MiniTopMost=$true}
}

function Merge-PkPreferences($Base,$Values) {
    $result=$Base.Clone()
    $choices=@{Accent=@('Rost','Türkis','Blau','Violett');Density=@('Normal','Kompakt');DefaultView=@('auto','cover','list');Sort=@('artist','title','year');Repeat=@('off','all','one')}
    $ranges=@{TileSize=@(96,420);FontScale=@(90,125);StartVolume=@(0,100)}
    $booleans=@('ShowDetails','ResumeSets','AutoNext','Shuffle','MiniTopMost')
    foreach ($property in $Values.PSObject.Properties) {
        $key=$property.Name; $value=$property.Value
        if ($choices.ContainsKey($key)) {
            if ($value -notin $choices[$key]) { throw "Ungültige Einstellung: $key" }
        } elseif ($ranges.ContainsKey($key)) {
            $number=0
            if (![int]::TryParse([string]$value,[ref]$number) -or $number -lt $ranges[$key][0] -or $number -gt $ranges[$key][1]) { throw "Ungültiger Wert: $key" }
            $value=$number
        } elseif ($key -in $booleans) {
            if ($value -isnot [bool]) { throw "Ungültiger Schalter: $key" }
        } else { throw "Unbekannte Einstellung: $key" }
        $result[$key]=$value
    }
    $result
}

function Save-PkPreferences($Values) {
    $next=Merge-PkPreferences $settings $Values
    Write-AtomicText $settingsPath (ConvertTo-Json $next)
    Apply-PkPreferences $next
    Send-WebSettings '' -Values
}

function Apply-PkPreferences($Next) {
    $volumeChanged=$Next.StartVolume -ne $settings.StartVolume
    $themeChanged=$Next.Theme -ne $settings.Theme
    foreach ($key in $Next.Keys) { $settings[$key]=$Next[$key] }
    if ($volumeChanged -and $volume) { $volume.Value=$settings.StartVolume; & $volumeChangedAction }
    if ($web.Mini) { $form.TopMost=$settings.MiniTopMost }
    if ($themeChanged -and $form) { Set-WindowTheme $form }
}

function Initialize-PkLibraryState {
    $web.LibraryState=[pscustomobject]@{Favorites=@();Playlists=@()}
    $web.Queue=@{Paths=@();Index=0;Auto=$false}
    if (![IO.File]::Exists($libraryStatePath)) { return }
    try {
        Assert-SafePath $libraryStatePath
        $saved=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($libraryStatePath,$utf8))
        $ids=[Collections.Generic.HashSet[string]]::new()
        $lists=@(foreach ($list in $saved.Playlists) {
            if ($list.Id -notmatch '^[a-f0-9]{32}$' -or !$ids.Add($list.Id) -or $list.Name -isnot [string] -or !$list.Name.Trim()) { throw 'Ungültige Playlist-Datei.' }
            [pscustomobject]@{Id=$list.Id;Name=$list.Name;Paths=@($list.Paths | Where-Object { $_ -is [string] -and $_ } | Select-Object -Unique)}
        })
        $web.LibraryState=[pscustomobject]@{Favorites=@($saved.Favorites | Where-Object { $_ -is [string] -and $_ } | Select-Object -Unique);Playlists=$lists}
    } catch { $web.LibraryStateError='Favoriten und Playlisten konnten nicht geladen werden. Die vorhandene Datei wurde beibehalten.' }
}

function Send-WebPlaylists {
    $paths=@{}
    foreach ($id in $web.Entries.Keys) { $paths[$web.Entries[$id].Path]=$id }
    $lists=@(foreach ($list in $web.LibraryState.Playlists) {
        $items=@(foreach ($path in $list.Paths) {
            $id=$paths[$path]
            @{id=$id;title=$(if ($id) { Get-LibraryDisplayTitle $web.Entries[$id] } else { [IO.Path]::GetFileName($path) });missing=!$id}
        })
        @{id=$list.Id;name=$list.Name;items=$items}
    })
    Send-WebCollectionMessage @{type='playlists';lists=$lists;status=[string]$web.LibraryStateError}
}

function Save-PkLibraryState($Next) {
    if ($web.LibraryStateError) { throw $web.LibraryStateError }
    Write-AtomicText $libraryStatePath (ConvertTo-Json $Next -Depth 6)
    $web.LibraryState=$Next
    Send-WebLibrary
}

function Update-PkLibraryReferences([string]$OldPath,[string]$NewPath) {
    if (!$web.LibraryState -or $web.LibraryStateError) { return }
    $next=ConvertFrom-Json -InputObject (ConvertTo-Json $web.LibraryState -Depth 6)
    $next.Favorites=@(foreach ($path in $next.Favorites) {
        if ($path -ieq $OldPath) { if ($NewPath) { $NewPath } } else { $path }
    })
    foreach ($list in $next.Playlists) {
        $list.Paths=@(foreach ($path in $list.Paths) {
            if ($path -ieq $OldPath) { if ($NewPath) { $NewPath } } else { $path }
        })
    }
    Write-AtomicText $libraryStatePath (ConvertTo-Json $next -Depth 6)
    $web.LibraryState=$next
    $web.Queue.Paths=@(foreach ($path in $web.Queue.Paths) {
        if ($path -ieq $OldPath) { if ($NewPath) { $NewPath } } else { $path }
    })
}

function Invoke-WebPlaylistCommand($Message) {
    try {
        $next=ConvertFrom-Json -InputObject (ConvertTo-Json $web.LibraryState -Depth 6)
        if ($Message.command -eq 'favorite') {
            $entry=$web.Entries[[string]$Message.id]
            if (!$entry -or $Message.value -isnot [bool]) { return }
            $next.Favorites=@($next.Favorites | Where-Object { $_ -ine $entry.Path })
            if ($Message.value) { $next.Favorites+=,$entry.Path }
        } else {
            $list=$next.Playlists | Where-Object { $_.Id -ceq $Message.playlistId } | Select-Object -First 1
            if ($Message.command -in @('playlist-create','playlist-rename')) {
                if ($Message.name -isnot [string] -or !$Message.name.Trim() -or $Message.name.Length -gt 100) { throw 'Bitte einen Playlistnamen mit höchstens 100 Zeichen eingeben.' }
            }
            if ($Message.command -ne 'playlist-create' -and !$list) { throw 'Diese Playlist ist nicht mehr vorhanden.' }
            switch ($Message.command) {
                'playlist-create' { $next.Playlists+=,[pscustomobject]@{Id=[guid]::NewGuid().ToString('N');Name=$Message.name.Trim();Paths=@()} }
                'playlist-rename' { $list.Name=$Message.name.Trim() }
                'playlist-delete' { $next.Playlists=@($next.Playlists | Where-Object { $_.Id -cne $list.Id }) }
                'playlist-add' {
                    foreach ($id in @($Message.ids)) {
                        $entry=$web.Entries[[string]$id]
                        if (!$entry) { throw 'Ein ausgewählter Titel ist nicht mehr vorhanden.' }
                        if ($entry.Path -notin $list.Paths) { $list.Paths+=,$entry.Path }
                    }
                }
                'playlist-remove' {
                    if ($Message.index -isnot [int] -or $Message.index -lt 0 -or $Message.index -ge $list.Paths.Count) { throw 'Ungültiger Playlist-Eintrag.' }
                    $list.Paths=@(for ($index=0;$index -lt $list.Paths.Count;$index++) { if ($index -ne $Message.index) { $list.Paths[$index] } })
                }
                'playlist-order' {
                    $index=$Message.index
                    if ($index -isnot [int] -or $Message.direction -notin @(-1,1) -or $index -lt 0 -or $index -ge $list.Paths.Count) { throw 'Ungültige Reihenfolge.' }
                    $target=$index+[int]$Message.direction
                    if ($target -lt 0 -or $target -ge $list.Paths.Count) { return }
                    $value=$list.Paths[$index];$list.Paths[$index]=$list.Paths[$target];$list.Paths[$target]=$value
                }
            }
        }
        Save-PkLibraryState $next
    } catch { Send-WebCollectionMessage @{type='playlist-status';status=$_.Exception.GetBaseException().Message} }
}

function Set-WebMiniPlayer([bool]$Enabled) {
    if ($Enabled -eq [bool]$web.Mini) { return }
    if ($Enabled) {
        $web.FullWindow=@{Bounds=$form.Bounds;State=$form.WindowState;Minimum=$form.MinimumSize;TopMost=$form.TopMost;Menu=$menu.Visible}
        if ($form.WindowState -ne 'Normal') { $web.FullWindow.Bounds=$form.RestoreBounds }
        $form.WindowState='Normal'
        $form.MinimumSize=[Drawing.Size]::new(440,165)
        $form.Size=[Drawing.Size]::new(620,180)
        $form.TopMost=$settings.MiniTopMost
        $menu.Hide()
    } else {
        $form.MinimumSize=$web.FullWindow.Minimum
        $form.Bounds=$web.FullWindow.Bounds
        $form.TopMost=$web.FullWindow.TopMost
        $form.WindowState=$web.FullWindow.State
        $menu.Visible=$web.FullWindow.Menu
    }
    $web.Mini=$Enabled
    Send-WebCollectionMessage @{type='mini';enabled=$Enabled}
}

function Start-WebEntryPlayback($Entry,[string]$Id,[bool]$FromStart) {
    Save-WebSetPosition
    $resume=$web.Resume[$Id]
    if ($settings.ResumeSets -and $Entry.Type -eq 'Sets' -and $resume -and !$FromStart) {
        try { Start-LibraryPlayback $Entry.Path (Get-LibraryDisplayTitle $Entry) $resume.part $resume.second }
        catch { Start-LibraryPlayback $Entry.Path (Get-LibraryDisplayTitle $Entry) }
    } else { Start-LibraryPlayback $Entry.Path (Get-LibraryDisplayTitle $Entry) }
    $web.PlayingId=$Id; $web.SetPlaying=$Entry.Type -eq 'Sets'; $web.PlayerState=''
}

function Start-WebPlaybackQueue($Message) {
    try {
        $entry=$web.Entries[[string]$Message.id]
        $list=$web.LibraryState.Playlists | Where-Object { $_.Id -ceq $Message.playlistId } | Select-Object -First 1
        $paths=if ($list) { @($list.Paths) } elseif ($settings.AutoNext) { @($Message.ids | ForEach-Object { $web.Entries[[string]$_].Path } | Where-Object { $_ }) } else { @() }
        if (!$entry -and $list) {
            foreach ($path in $list.Paths) {
                $entry=$web.Entries.Values | Where-Object { $_.Path -ieq $path } | Select-Object -First 1
                if ($entry) { break }
            }
        }
        if (!$entry) { throw 'Kein verfügbarer Titel ausgewählt.' }
        if ($settings.Shuffle -and !$Message.id -and $list) {
            $available=@($web.Entries.Values | Where-Object { $_.Path -in $paths })
            if ($available.Count) { $entry=$available | Get-Random }
        }
        if (!$paths.Count) { $paths=@($entry.Path) }
        if ($settings.Shuffle) { $paths=@($entry.Path)+@($paths | Where-Object { $_ -ine $entry.Path } | Sort-Object { Get-Random }) }
        $index=[array]::IndexOf($paths,$entry.Path)
        if ($index -lt 0) { $paths=@($entry.Path)+$paths;$index=0 }
        Start-WebEntryPlayback $entry ([string]($web.Entries.Keys | Where-Object { $web.Entries[$_].Path -ieq $entry.Path } | Select-Object -First 1)) ([bool]$Message.fromStart)
        $web.Queue=@{Paths=$paths;Index=$index;Auto=[bool]($list -or $settings.AutoNext)}
        $web.PlayerState=''
    } catch { Send-WebCollectionMessage @{type='library-status';status=$_.Exception.GetBaseException().Message} }
}

function Step-WebPlaybackQueue([int]$Direction=1,[switch]$Automatic) {
    $queue=$web.Queue
    if (!$queue.Paths.Count -or ($Automatic -and !$queue.Auto -and $settings.Repeat -eq 'off')) { return $false }
    $index=$queue.Index
    for ($attempt=0;$attempt -lt $queue.Paths.Count;$attempt++) {
        if (!($Automatic -and $settings.Repeat -eq 'one' -and $attempt -eq 0)) { $index+=$Direction }
        if ($index -ge $queue.Paths.Count -or $index -lt 0) {
            if ($settings.Repeat -ne 'all') { return $false }
            $index=($index+$queue.Paths.Count)%$queue.Paths.Count
        }
        $path=$queue.Paths[$index]
        $id=$web.Entries.Keys | Where-Object { $web.Entries[$_].Path -ieq $path } | Select-Object -First 1
        if (!$id) { continue }
        try {
            $fromStart=$Automatic -and $path -ieq $queue.Paths[$queue.Index]
            Start-WebEntryPlayback $web.Entries[$id] $id $fromStart
            $queue.Index=$index
            return $true
        } catch { Write-Verbose $_.Exception.Message }
    }
    return $false
}

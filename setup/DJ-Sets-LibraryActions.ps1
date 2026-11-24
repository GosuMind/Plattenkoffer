function Start-WebDownloadReview {
    if ($state.Worker) { return }
    foreach ($row in $grid.Rows) {
        if ($row.Tag.Archived -or !$row.Cells['Selected'].Value) { continue }
        if ($row.Tag.Review -or !([string]$row.Cells['Artist'].Value).Trim()) {
            $web.DownloadReviewId=$row.Tag.Id
            Send-WebCollectionMessage @{type='download-review';id=$row.Tag.Id;title=[string]$row.Tag.Original;artist=[string]$row.Cells['Artist'].Value}
            return
        }
    }
    $web.DownloadReviewId=$null
    Send-WebCollectionMessage @{type='download-review-close'}
    $download.PerformClick()
}

function Confirm-WebDownloadReview($Message) {
    if ($state.Worker -or $Message.id -cne $web.DownloadReviewId) { return }
    foreach ($row in $grid.Rows) {
        if ($row.Tag.Id -cne $Message.id -or $row.Tag.Archived -or !$row.Cells['Selected'].Value) { continue }
        if ($Message.skip -eq $true) { $row.Cells['Selected'].Value=$false }
        else {
            if ($Message.artist -isnot [string] -or !$Message.artist.Trim() -or $Message.artist.Length -gt 300) { return }
            $row.Cells['Artist'].Value=$Message.artist.Trim()
            $row.Tag.Review=$false
            $row.Cells['Status'].Value='Bereit'
        }
        $web.DownloadReviewId=$null
        Start-WebDownloadReview
        return
    }
    $web.DownloadReviewId=$null
    Send-WebCollectionMessage @{type='download-review-close'}
}

function Move-PkItemToRecycleBin([string]$Path, [bool]$Directory) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    if ($Directory) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($Path,'OnlyErrorDialogs','SendToRecycleBin','ThrowException')
    } else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($Path,'OnlyErrorDialogs','SendToRecycleBin','ThrowException')
    }
}

function Invoke-WebLibraryDelete($Message) {
    try {
        if ($Message.command -eq 'delete-cancel') { $web.DeletePending=$null; return }
        if ($state.Worker -or $web.Export.Worker -or $web.Conversion.Worker -or $web.TransitionScan.Worker) {
            throw 'Warte, bis der laufende Download, Export oder die Umwandlung beendet ist.'
        }
        if ($Message.command -eq 'delete-preview') {
            $web.DeletePending=$null
            $ids=@($Message.ids | Select-Object -Unique)
            if (!$ids.Count) { throw 'Wähle mindestens einen Eintrag.' }
            $items=@(foreach ($id in $ids) {
                if ($id -isnot [string] -or !$web.Entries.ContainsKey($id)) { throw 'Die Auswahl ist nicht mehr aktuell. Bitte erneut auswählen.' }
                $entry=$web.Entries[$id]
                @{Id=$id;Path=[string]$entry.Path;External=[bool]$entry.External;Title=(Get-LibraryDisplayTitle $entry)}
            })
            $token=[guid]::NewGuid().ToString('N')
            $web.DeletePending=@{Token=$token;Items=$items}
            Send-WebCollectionMessage @{type='delete-preview';token=$token;items=@($items | ForEach-Object { @{id=$_.Id;title=$_.Title;external=$_.External} })}
            return
        }
        $pendingDelete=$web.DeletePending
        if (!$pendingDelete -or $Message.token -cne $pendingDelete.Token) { throw 'Bitte die Löschvorschau erneut öffnen.' }
        $web.DeletePending=$null
        $deleted=[Collections.Generic.List[string]]::new()
        $failures=[Collections.Generic.List[string]]::new()
        foreach ($item in $pendingDelete.Items) {
            try {
                $entry=$web.Entries[$item.Id]
                if (!$entry -or $entry.Path -cne $item.Path -or [bool]$entry.External -ne $item.External) { throw 'Der Eintrag wurde seit der Vorschau geändert.' }
                $path=[IO.Path]::GetFullPath($item.Path)
                Assert-SafePath $path
                if (!$entry.External) {
                    # Only recycle a recording directory directly below Artist/Tracks or Artist/Sets.
                    $category=[IO.Directory]::GetParent($path)
                    $root=[IO.Path]::GetFullPath($settings.MusicRoot).TrimEnd('\','/')
                    if (!$category -or !$category.Parent -or !$category.Parent.Parent -or
                        $category.Name -cne $entry.Type -or $category.Parent.Parent.FullName.TrimEnd('\','/') -ine $root) {
                        throw 'Der Eintragsordner liegt außerhalb der vorgesehenen Sammlungsstruktur.'
                    }
                }
                if ($web.PlayingId -ceq $item.Id) {
                    Stop-LibraryPlayback
                    $web.PlayingId=$null; $web.SetPlaying=$false; $web.PlayerState=''
                }
                if ($entry.External) {
                    if ($Message.originals -eq $true -and [IO.File]::Exists($path)) { Move-PkItemToRecycleBin $path $false }
                    $remaining=@(Read-LocalLibrary | Where-Object { $_.Path -cne $item.Path })
                    Save-LocalLibrary $remaining
                } elseif ([IO.Directory]::Exists($path)) {
                    Move-PkItemToRecycleBin $path $true
                }
                $web.Resume.Remove($item.Id)
                Update-PkLibraryReferences $item.Path ''
                $deleted.Add($item.Id)
            } catch { $failures.Add(("{0}: {1}" -f $item.Title,$_.Exception.GetBaseException().Message)) }
        }
        Update-LibraryResults -Reload
        $status="{0} von {1} Einträgen gelöscht." -f $deleted.Count,$pendingDelete.Items.Count
        if ($failures.Count) { $status+="`n"+($failures -join "`n") }
        Send-WebCollectionMessage @{type='delete-result';deleted=$deleted.ToArray();status=$status;failed=$failures.Count}
    } catch { Send-WebCollectionMessage @{type='delete-status';status=$_.Exception.GetBaseException().Message} }
}

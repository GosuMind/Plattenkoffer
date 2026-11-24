function Get-PkCustomCover($Entry,[string]$Id) {
    if ($Entry.External) {
        if ($Id -cnotmatch '^[0-9A-F]{64}$') { throw 'Ungültiger Sammlungseintrag.' }
        return (Join-Path $config "cover-$Id.jpg")
    }
    Assert-SafePath $Entry.Path
    if (![IO.Directory]::Exists($Entry.Path)) { throw 'Der Eintragsordner ist nicht erreichbar.' }
    Join-Path $Entry.Path 'plattenkoffer-cover.jpg'
}

function Read-PkCoverImage([string]$File) {
    Assert-SafePath $File
    if ([IO.FileInfo]::new($File).Length -gt 20MB) { throw 'Das Bild darf höchstens 20 MB groß sein.' }
    $image=[Drawing.Image]::FromFile($File)
    try {
        if ([long]$image.Width * $image.Height -gt 40000000) { throw 'Das Bild hat zu viele Pixel.' }
        $side=[Math]::Min($image.Width,$image.Height)
        $bitmap=[Drawing.Bitmap]::new(512,512)
        try {
            $canvas=[Drawing.Graphics]::FromImage($bitmap)
            try {
                $canvas.Clear([Drawing.Color]::FromArgb(37,35,31))
                $canvas.InterpolationMode='HighQualityBicubic'
                $canvas.DrawImage($image,[Drawing.Rectangle]::new(0,0,512,512),[int](($image.Width-$side)/2),[int](($image.Height-$side)/2),$side,$side,[Drawing.GraphicsUnit]::Pixel)
            } finally { $canvas.Dispose() }
            $stream=[IO.MemoryStream]::new()
            try {
                $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Jpeg)
                [Convert]::ToBase64String($stream.ToArray())
            } finally { $stream.Dispose() }
        } finally { $bitmap.Dispose() }
    } finally { $image.Dispose() }
}

function Invoke-WebCoverEdit($Entry,$Message) {
    $id=$Message.id
    try {
        $target=Get-PkCustomCover $Entry $id
        Assert-SafePath $target
        switch ($Message.command) {
            'cover-edit' {
                $web.CoverDraft=$null
                Send-WebCollectionMessage @{type='cover-edit';id=$id;custom=[IO.File]::Exists($target)}
            }
            'cover-choose' {
                $picker=[Windows.Forms.OpenFileDialog]@{Title='Coverbild auswählen';Filter='Bilder (*.jpg;*.jpeg;*.png;*.bmp;*.gif)|*.jpg;*.jpeg;*.png;*.bmp;*.gif'}
                try {
                    if ($picker.ShowDialog($form) -ne 'OK') { return }
                    $encoded=Read-PkCoverImage $picker.FileName
                    $web.CoverDraft=@{Id=$id;Encoded=$encoded}
                    Send-WebCollectionMessage @{type='cover-draft';id=$id;image="data:image/jpeg;base64,$encoded"}
                } finally { $picker.Dispose() }
            }
            'cover-save' {
                if (!$web.CoverDraft -or $web.CoverDraft.Id -cne $id) { throw 'Bitte zuerst ein Bild auswählen.' }
                $temporary="$target.$([guid]::NewGuid().ToString('N')).tmp"
                try {
                    [IO.File]::WriteAllBytes($temporary,[Convert]::FromBase64String($web.CoverDraft.Encoded))
                    if ([IO.File]::Exists($target)) { [IO.File]::Replace($temporary,$target,[NullString]::Value) }
                    else { [IO.File]::Move($temporary,$target) }
                } finally { [IO.File]::Delete($temporary) }
                $web.CoverDraft=$null
                Send-WebCover $Entry $id
                Send-WebCollectionMessage @{type='cover-edit-status';id=$id;close=$true}
            }
            'cover-reset' {
                [IO.File]::Delete($target)
                $web.CoverDraft=$null
                Send-WebCover $Entry $id
                Send-WebCollectionMessage @{type='cover-edit-status';id=$id;close=$true}
            }
        }
    } catch { Send-WebCollectionMessage @{type='cover-edit-status';id=$id;status=$_.Exception.Message} }
}

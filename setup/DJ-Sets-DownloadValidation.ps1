# Publish only checked, tagged staged downloads. Existing library files are never retagged here.
function Complete-PkDownloadPayload($Row,[string]$Source,[string]$Audio,[string]$Payload,[string]$Info,[string]$Cover) {
    $options=@{FFmpeg=$ffmpeg;Probe=$probe}
    $artist=([string]$Row.Artist).Trim();$title=([string]$Row.Title).Trim()
    if (!$artist -or !$title -or $artist -match '[\x00-\x1F]' -or $title -match '[\x00-\x1F]') { throw 'Pflichtmetadaten fehlen oder sind ungültig. Download bleibt unveröffentlicht.' }
    foreach ($path in @($Source,$Audio,$Payload,$Info,$Cover)) { Assert-SafePath $path }
    if([IO.FileInfo]::new($Cover).Length -gt 20MB){throw 'Download-Cover ist zu groß.'}
    $coverProbe=Invoke-PkHealthTool $probe @('-v','error','-show_entries','stream=width,height','-of','json','--',$Cover) $null
    $image=(ConvertFrom-Json $coverProbe).streams|Select-Object -First 1
    if(!$image.width -or !$image.height -or [long]$image.width*$image.height -gt 40000000){throw 'Download-Cover ist nicht lesbar.'}
    $before=Get-PkHealthProbe $Source $options $null
    $beforeHashes=Get-PkHealthAudioHashes $Source $options $null
    # This is an unpublished, owned job path. Remove only our prior failed temporary output.
    if ([IO.File]::Exists($Audio)) { [IO.File]::Delete($Audio) }
    $null=Invoke-PkHealthTool $ffmpeg @('-v','error','-nostdin','-n','-i',$Source,'-map','0:a:0','-map_metadata','0','-c:a','copy','-metadata',"artist=$artist",'-metadata',"title=$title",'-metadata:s:a:0',"artist=$artist",'-metadata:s:a:0',"title=$title",$Audio) $null 3600
    $after=Get-PkHealthProbe $Audio $options $null
    $afterHashes=Get-PkHealthAudioHashes $Audio $options $null
    if (($beforeHashes -join '|') -cne ($afterHashes -join '|')) { throw 'Download-Abschlussprüfung: Audiodaten verändert.' }
    $a=@($before.streams|Where-Object codec_type -eq 'audio')[0];$b=@($after.streams|Where-Object codec_type -eq 'audio')[0]
    foreach($field in @('codec_name','sample_rate','channels','profile')){if([string]$a.$field -cne [string]$b.$field){throw "Download-Abschlussprüfung: $field verändert."}}
    $tags=Get-PkHealthTags $after
    if ($tags.Artist -cne $artist -or $tags.Title -cne $title) { throw 'Download-Abschlussprüfung: Pflichtmetadaten fehlen.' }
    $null=Invoke-PkHealthTool $ffmpeg @('-v','error','-xerror','-err_detect','explode','-nostdin','-i',$Audio,'-map','0:a','-f','null','-') $null 14400
    $pk=@{MetadataSources=@{};HealthSchemaVersion=1;SourceUrl="https://www.youtube.com/watch?v=$($Row.Id)";VideoId=$Row.Id}
    foreach($field in (Get-PkHealthFields).Keys){$pk[$field]=[string]$tags[$field]}
    $pk.SourceUrl="https://www.youtube.com/watch?v=$($Row.Id)";$pk.VideoId=$Row.Id
    foreach($field in @('Artist','Title')){$pk.MetadataSources[$field]=@{Provider='Bestätigter Downloadauftrag';Value=$pk[$field];ConfirmedAt=[datetime]::UtcNow.ToString('o');Confidence='VERIFIED';Manual=$true}}
    $target=Join-Path $Payload ('audio'+[IO.Path]::GetExtension($Audio))
    foreach($path in @($target,(Join-Path $Payload 'info.json'),(Join-Path $Payload ('cover'+[IO.Path]::GetExtension($Cover))))){Assert-SafePath $path}
    [IO.File]::Copy($Audio,$target,$true)
    [IO.File]::Copy($Info,(Join-Path $Payload 'info.json'),$true)
    [IO.File]::Copy($Cover,(Join-Path $Payload ('cover'+[IO.Path]::GetExtension($Cover))),$true)
    Write-PkHealthJson (Join-Path $Payload 'plattenkoffer.json') $pk
    Assert-PkPublishedDownload $Payload $Row
}

function Assert-PkPublishedDownload([string]$Folder,$Row) {
    Assert-SafePath $Folder
    $pk=Read-PkHealthJson (Join-Path $Folder 'plattenkoffer.json')
    $files=@(Get-ChildItem -LiteralPath $Folder -File|Where-Object Name -in @('audio.opus','audio.m4a'))
    if ($files.Count -ne 1 -or !$pk.Artist -or !$pk.Title -or $pk.Artist -cne ([string]$Row.Artist).Trim() -or $pk.Title -cne ([string]$Row.Title).Trim()) { throw 'Download darf ohne konsistente Pflichtmetadaten nicht archiviert werden.' }
    $options=@{FFmpeg=$ffmpeg;Probe=$probe}
    $tags=Get-PkHealthTags (Get-PkHealthProbe $files[0].FullName $options $null)
    if($tags.Artist -cne $pk.Artist -or $tags.Title -cne $pk.Title){throw 'Download-JSON und Audio-Tags stimmen nicht überein.'}
    $null=Invoke-PkHealthTool $ffmpeg @('-v','error','-xerror','-err_detect','explode','-nostdin','-i',$files[0].FullName,'-map','0:a','-f','null','-') $null 14400
}

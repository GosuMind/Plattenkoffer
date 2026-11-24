function Assert-PkMp3CoverEquivalent($Before,$After,$BeforeHashes,$AfterHashes) {
    $a=@{format=$Before.format;streams=@($Before.streams|Where-Object codec_type -eq 'audio')}
    $b=@{format=$After.format;streams=@($After.streams|Where-Object codec_type -eq 'audio')}
    Assert-PkHealthEquivalent $a $b $BeforeHashes $AfterHashes
    $pictures=@($After.streams|Where-Object {$_.codec_type -eq 'video' -and $_.disposition.attached_pic -eq 1 -and $_.codec_name -eq 'mjpeg'})
    if($pictures.Count -ne 1 -or @($After.streams).Count -ne @($b.streams).Count+1){throw 'MP3 enthält nicht genau das freigegebene JPEG-Cover.'}
}
function New-PkMp3CoverOutput([string]$Source,[string]$Cover,[string]$Target,$Options,$Control) {
    $null=Invoke-PkHealthTool $Options.FFmpeg @('-v','error','-nostdin','-n','-i',$Source,'-i',$Cover,'-map','0:a','-map','1:v:0','-map_metadata','0','-c:a','copy','-c:v','copy','-id3v2_version','3','-metadata:s:v:0','title=Album cover','-metadata:s:v:0','comment=Cover (front)','-disposition:v:0','attached_pic',$Target) $Control 3600
}
function Get-PkHealthCoverRecovery($Options,$Record,$Control) {
    if(!$Options.CoverRoot){throw 'Cover-Arbeitsordner konfigurieren.'}
    $null=Assert-PkHealthScope $Record.Path $Options.Root;Assert-SafePath $Options.CoverRoot
    [void][IO.Directory]::CreateDirectory($Options.CoverRoot)
    $target=Join-Path $Options.CoverRoot ([guid]::NewGuid().ToString('N')+'.jpg')
    if($Record.EmbeddedCover){
        $null=Invoke-PkHealthTool $Options.FFmpeg @('-v','error','-nostdin','-n','-i',$Record.Path,'-map','0:v:0','-frames:v','1','-q:v','2',$target) $Control
        return @{Path=$target;Origin='Eingebettetes Originalcover';Url='';Hash=(Get-PkHealthFileHash $target)}
    }
    $existing=@($Record.Covers|Where-Object {$_.Valid})|Select-Object -First 1
    if($existing){return @{Path=$existing.Path;Origin='Vorhandenes externes Cover';Url='';Hash=(Get-PkHealthFileHash $existing.Path)}}
    $info=Read-PkHealthJson (Join-Path ([IO.Path]::GetDirectoryName($Record.Path)) 'info.json')
    if($info.id -cnotmatch '^[a-zA-Z0-9_-]{11}$'){throw 'Keine geprüfte YouTube-Video-ID für das Original-Thumbnail vorhanden.'}
    foreach($quality in @('maxresdefault','hqdefault')){
        if($Control -and $Control.Cancel){throw [OperationCanceledException]::new('Abgebrochen.')}
        $url="https://i.ytimg.com/vi/$($info.id)/$quality.jpg";$response=$null;$stream=$null;$file=$null
        try{
            $request=[Net.HttpWebRequest]::Create($url);$request.AllowAutoRedirect=$false;$request.Timeout=20000;$request.ReadWriteTimeout=20000
            $response=$request.GetResponse()
            if($response.StatusCode -ne 200 -or $response.ContentLength -gt 8MB -or $response.ContentType -notmatch '^image/'){throw 'Thumbnail nicht verfügbar.'}
            $stream=$response.GetResponseStream();$file=[IO.File]::Open($target,'CreateNew','Write','None');$buffer=[byte[]]::new(32768);$size=0L
            while(($read=$stream.Read($buffer,0,$buffer.Length)) -gt 0){$size+=$read;if($size -gt 8MB){throw 'Thumbnail zu groß.'};if($Control -and $Control.Cancel){throw [OperationCanceledException]::new('Abgebrochen.')};$file.Write($buffer,0,$read)}
            $file.Dispose();$file=$null
            $raw=Invoke-PkHealthTool $Options.Probe @('-v','error','-show_entries','stream=width,height','-of','json','--',$target) $Control
            $picture=(ConvertFrom-Json $raw).streams|Select-Object -First 1
            if($picture.width -lt 200 -or $picture.height -lt 100){throw 'Thumbnail ist nur ein Platzhalter.'}
            return @{Path=$target;Origin='Original-Thumbnail';Url=$url;Hash=(Get-PkHealthFileHash $target)}
        }catch{if($file){$file.Dispose();$file=$null};if([IO.File]::Exists($target)){[IO.File]::Delete($target)};if($Control -and $Control.Cancel){throw}}
        finally{if($file){$file.Dispose()};if($stream){$stream.Dispose()};if($response){$response.Dispose()}}
    }
    throw 'Kein gültiges Original-Thumbnail verfügbar. Eigenes Cover auswählen.'
}
function Get-PkHealthCoverPreview([string]$Path) {
    Assert-SafePath $Path
    if([IO.FileInfo]::new($Path).Length -gt 8MB){return ''}
    $extension=[IO.Path]::GetExtension($Path).TrimStart('.').ToLowerInvariant()
    if($extension -notin @('jpg','jpeg','png','webp')){return ''};if($extension -eq 'jpg'){$extension='jpeg'}
    "data:image/$extension;base64,$([Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)))"
}

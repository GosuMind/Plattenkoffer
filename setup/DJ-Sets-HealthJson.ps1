function New-PkHealthRecoveredJson([string]$Path,$Options,$Control) {
    $folder=Get-PkHealthFolder $Path $Options.Root
    if(!$folder.Valid){throw 'Alte Ordnerstruktur muss vor der JSON-Rekonstruktion manuell zugeordnet werden.'}
    $files=@(Get-ChildItem -LiteralPath ([IO.Path]::GetDirectoryName($Path)) -File|Where-Object {$_.Extension -in @('.mp3','.opus','.m4a','.wav','.flac','.ogg','.webm','.aac') -and $_.BaseName -notmatch '(audio_repaired|\.tmp|\.pk-health-)'}|Sort-Object Name)
    if($files.Count -le 1){return [pscustomobject]@{}}
    if($folder.Kind -ne 'Set'){throw 'Mehrere Audiodateien in einem Trackordner benötigen eine manuelle Zuordnung.'}
    $parts=@(foreach($file in $files){$null=Assert-PkHealthScope $file.FullName $Options.Root;[pscustomobject]@{FileName=$file.Name;Tags=[pscustomobject](Get-PkHealthTags (Get-PkHealthProbe $file.FullName $Options $Control));MetadataSources=[pscustomobject]@{}}})
    [pscustomobject]@{Artist=$folder.Artist;Title=$folder.Title;Parts=$parts;MetadataSources=[pscustomobject]@{Artist=@{Provider='Bestätigte Set-Ordnerstruktur';Value=$folder.Artist};Title=@{Provider='Bestätigte Set-Ordnerstruktur';Value=$folder.Title}}}
}

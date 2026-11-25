function ConvertTo-PkMetadataComparable([string]$Value) {
    (($Value.Normalize([Text.NormalizationForm]::FormC).Trim() -replace '\s+',' ') -replace '[–—]','-').ToUpperInvariant()
}
function Test-PkHealthTitleVariant([string]$Title,$Metadata) {
    $actual=ConvertTo-PkMetadataComparable $Title;$base=ConvertTo-PkMetadataComparable ([string]$Metadata.Title)
    if(!$base){return $false};if($actual -ceq $base){return $true}
    foreach($field in @('Version','Genre','Label')){
        $extra=ConvertTo-PkMetadataComparable ([string]$Metadata.$field)
        if(!$extra){continue}
        foreach($variant in @("$base ($extra)","$base [$extra]","$base - $extra","$base $extra")){if($actual -ceq $variant){return $true}}
    }
    $false
}
function Test-PkHealthFieldEquivalent([string]$Field,[string]$Left,[string]$Right,$Metadata) {
    $a=ConvertTo-PkMetadataComparable $Left;$b=ConvertTo-PkMetadataComparable $Right
    if($a -ceq $b){return $true}
    if($Field -eq 'Title' -and (Test-PkHealthTitleVariant $Left $Metadata) -and (Test-PkHealthTitleVariant $Right $Metadata)){return $true}
    if($Field -eq 'Year' -and $a -match '^\d{4}(?:-\d{2}(?:-\d{2})?)?$' -and $b -match '^\d{4}(?:-\d{2}(?:-\d{2})?)?$' -and $a.Substring(0,4) -ceq $b.Substring(0,4)){return $true}
    $false
}
function Test-PkHealthSuspiciousUnicode([string]$Value) {
    $Value.Contains([string][char]0xfffd) -or $Value -match '(?:Ã[\u0080-\u00BF]|â€[\u0080-\u00FF\u2018-\u203A]|├[\u00A0-\u00FF])'
}
function Get-PkHealthMetadataStatus($Tags,$Pk) {
    if(!$Pk -or !$Pk.Artist -or !$Pk.Title -or !$Tags.Artist -or !$Tags.Title){return 'METADATA_REVIEW_REQUIRED'}
    $exact=$true
    foreach($field in @('Artist','Title','Album','Year','Genre','Label','Version')){
        if(!$Pk.$field -or !$Tags.$field){continue}
        if((ConvertTo-PkMetadataComparable $Pk.$field) -ceq (ConvertTo-PkMetadataComparable $Tags.$field)){continue}
        $exact=$false
        if(!(Test-PkHealthFieldEquivalent $field $Tags.$field $Pk.$field $Pk)){return 'METADATA_CONFLICT'}
    }
    if($exact){'METADATA_EXACT_MATCH'}else{'METADATA_SEMANTIC_MATCH'}
}
function Get-PkHealthIssueCodes($Codes) {
    @($Codes|Where-Object {$_ -notin @('GENERIC_FILENAME','EMBEDDED_COVER_MISSING','HEALTHY','METADATA_EXACT_MATCH','METADATA_SEMANTIC_MATCH')})
}

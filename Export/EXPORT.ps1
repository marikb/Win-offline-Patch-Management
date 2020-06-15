# Run deny and approve
& 'F:\ExportContent\deny stuff.ps1'
& 'F:\ExportContent\approve stuff.ps1'

$counter = 0;
$prev = @();

# Add all already created updates and create new bulk
while(Test-Path F:\ExportContent\$counter)
{
    $prev += ,(& 'C:\Program Files\7-Zip\7z.exe' l "F:\ExportContent\$counter\F$counter.7z");
    $counter++;
}

$cur = $null;
$cur = Get-ChildItem -File -Recurse F:\WsusContent
$filename = "";
$filename = "F:\ExportContent\$counter\files.txt";

mkdir F:\ExportContent\$counter\

$cur | ForEach-Object {
   Write-Debug $_.FullName;
    
    if (!($prev | select-string ($_.Name) -Quiet)){
        Write-Debug " Adding"
        Add-Content -Value "$($_.FullName)" -Path $filename -Force -Encoding UTF8;
    }
}

Write-Host "Making 7z"
& 'C:\Program Files\7-Zip\7z.exe' a -y -spf -t7z -scsUTF-8 "F:\ExportContent\$counter\F$counter.7z"  "`@$filename"

& "C:\Program Files\Update Services\Tools\WsusUtil.exe" Export "F:\ExportContent\$counter\exportdbwsus.xml.gz" "F:\ExportContent\$counter\exportlogwsus.xml"

Get-WsusUpdate -Approval Approved | Export-Clixml F:\ExportContent\$counter\approved.clixml
Get-WsusUpdate -Approval Declined | Export-Clixml F:\ExportContent\$counter\declined.clixml
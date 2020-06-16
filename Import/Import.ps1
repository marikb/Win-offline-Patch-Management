$import_num = (Get-ChildItem D:\ImportContent -Directory | Sort-Object LastWrite -Descending | Select-Object -First 1).Name
$import_dir = "D:\ImportContent\$import_num"
$content_path = "D:\ImportContent\$import_num\F$import_num.7z"

Get-Date
Write-Host "Importing metadata to DB..." -ForegroundColor Yellow
& 'C:\Program Files\Update Services\Tools\WsusUtil.exe' import "$import_dir\exportwsus.xml.gz" "$import_dir\import_log.txt"
Get-Date

# Rename files in archive to make extraction easier
& "C:\Program Files\7-Zip\7z.exe" rn $content_path F:\WsusContent WsusContent

Write-Host "Extracting content..." -ForegroundColor Yellow
& "C:\Program Files\7-Zip\7z.exe" x -y -o'D:' $content_path

Write-Host "Import Approvals and Denials..."
$approvals = Import-Clixml $import_dir\approved.clixml
$approvals.UpdateId | ForEach-Object {Get-WsusUpdate -updateId $_} | Approve-WsusUpdate -Action Install -TargetGroupName DummyGroup
$denials = Import-Clixml $import_dir\declined.clixml
$denials.UpdateId | ForEach-Object {Get-WsusUpdate -UpdateId $_} | Deny-WsusUpdate -Confirm:$false
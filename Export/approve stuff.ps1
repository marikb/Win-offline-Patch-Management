<#
    Approve section, add type of updates to approve here.
#>

Get-Date

$u = Get-WsusUpdate -approval Unapproved | Where-Object {((Get-Date) - $_.Update.CreationDate).TotalDays -ge 90}
$u | Approve-WsusUpdate -Action Install -Confirm:$false -TargetGroupName "All Computers"

$ready = $u | ForEach-Object {(Get-WsusUpdate -UpdateId $_.UpdateId).Update.State} | Where-Object {$_ -eq "Ready"}

while ($ready.count -lt $u.count)
{
    Write-Progress -Activity "Downloading approved update files" -Status "$($ready.count) of $($u.count)" -PercentComplete (100 * ($ready.count / $u.count))
    Start-Sleep 3
    $ready = $u | ForEach-Object {(Get-WsusUpdate -UpdateId $_.UpdateId).Update.State} | Where-Object {$_ -eq "Ready"}
}

Get-Date
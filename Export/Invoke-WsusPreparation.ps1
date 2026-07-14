#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules UpdateServices

<#
.SYNOPSIS
Runs explicitly selected WSUS approval and maintenance operations before an export.

.DESCRIPTION
No action is selected by default. Use -WhatIf to review approval and cleanup operations.
Approved update content is monitored until it is ready or the configured timeout expires.

.EXAMPLE
.\Invoke-WsusPreparation.ps1 -ApproveEligibleUpdates -MinimumUpdateAgeDays 90 `
    -TargetGroupName 'All Computers' -WhatIf
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch] $ApproveEligibleUpdates,

    [ValidateRange(0, 3650)]
    [int] $MinimumUpdateAgeDays = 90,

    [ValidateNotNullOrEmpty()]
    [string] $TargetGroupName = 'All Computers',

    [ValidateRange(1, 1440)]
    [int] $DownloadTimeoutMinutes = 180,

    [switch] $DeclineExpiredAndSuperseded,

    [switch] $CleanupObsoleteUpdates,

    [switch] $CleanupUnneededContentFiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ($ApproveEligibleUpdates -or $DeclineExpiredAndSuperseded -or
    $CleanupObsoleteUpdates -or $CleanupUnneededContentFiles)) {
    throw 'No preparation action was selected.'
}

if ($ApproveEligibleUpdates) {
    $targetGroupExists = @(
        (Get-WsusServer).GetComputerTargetGroups() |
            Where-Object { $_.Name -eq $TargetGroupName }
    ).Count -gt 0
    if (-not $targetGroupExists) {
        throw "WSUS target group not found: '$TargetGroupName'."
    }

    $cutoff = (Get-Date).AddDays(-$MinimumUpdateAgeDays)
    $updates = @(
        Get-WsusUpdate -Approval Unapproved |
            Where-Object { $_.Update.CreationDate -le $cutoff }
    )

    if ($updates.Count -eq 0) {
        Write-Host 'No updates match the approval policy.' -ForegroundColor Yellow
    }
    elseif ($PSCmdlet.ShouldProcess(
        "$($updates.Count) updates in '$TargetGroupName'",
        "Approve updates at least $MinimumUpdateAgeDays days old"
    )) {
        $updates | Approve-WsusUpdate -Action Install -TargetGroupName $TargetGroupName -Confirm:$false

        $deadline = (Get-Date).AddMinutes($DownloadTimeoutMinutes)
        do {
            $readyCount = @(
                $updates |
                    ForEach-Object { (Get-WsusUpdate -UpdateId $_.UpdateId).Update.State } |
                    Where-Object { $_ -eq 'Ready' }
            ).Count

            $percent = [Math]::Floor(100 * ($readyCount / $updates.Count))
            Write-Progress -Activity 'Downloading approved update files' `
                -Status "$readyCount of $($updates.Count) ready" `
                -PercentComplete $percent

            if ($readyCount -lt $updates.Count) {
                if ((Get-Date) -ge $deadline) {
                    throw "Timed out after $DownloadTimeoutMinutes minutes waiting for approved content."
                }
                Start-Sleep -Seconds 15
            }
        } while ($readyCount -lt $updates.Count)

        Write-Progress -Activity 'Downloading approved update files' -Completed
    }
}

$cleanupParameters = @{}
if ($DeclineExpiredAndSuperseded) {
    $cleanupParameters.DeclineExpiredUpdates = $true
    $cleanupParameters.DeclineSupersededUpdates = $true
}
if ($CleanupObsoleteUpdates) {
    $cleanupParameters.CleanupObsoleteUpdates = $true
}
if ($CleanupUnneededContentFiles) {
    $cleanupParameters.CleanupUnneededContentFiles = $true
}

if ($cleanupParameters.Count -gt 0 -and $PSCmdlet.ShouldProcess(
    $env:COMPUTERNAME,
    "Run WSUS cleanup: $($cleanupParameters.Keys -join ', ')"
)) {
    Invoke-WsusServerCleanup @cleanupParameters
}

#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules UpdateServices

<#
.SYNOPSIS
Validates and imports one offline WSUS transfer package.

.DESCRIPTION
Verifies every package artifact with SHA-256, restores content before metadata, and
optionally applies approval and decline state. Packages must normally be imported in
sequence because content archives are incremental.

.EXAMPLE
.\Import-WsusOfflinePackage.ps1 -PackagePath E:\WsusTransfer\000001-20260714T120000Z

.EXAMPLE
.\Import-WsusOfflinePackage.ps1 -PackagePath E:\WsusTransfer\000002-20260721T120000Z `
    -ApplyApprovals -ApprovalTargetGroup 'Offline Staging' -ApplyDeclines
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $PackagePath,

    [string] $ContentPath,

    [string] $WsusUtilPath,

    [string] $SevenZipPath,

    [string] $StatePath,

    [switch] $ApplyApprovals,

    [string] $ApprovalTargetGroup,

    [switch] $ApplyDeclines,

    [switch] $AllowSequenceGap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\src\WsusOffline.Common.ps1')

if ($ApplyApprovals -and [string]::IsNullOrWhiteSpace($ApprovalTargetGroup)) {
    throw '-ApprovalTargetGroup is required when -ApplyApprovals is used.'
}

$packageRoot = Get-FullPath -Path $PackagePath
if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
    throw "Package directory not found: '$packageRoot'."
}

$manifestPath = Join-Path $packageRoot 'manifest.json'
$manifest = Read-JsonFile -Path $manifestPath
if ([int] $manifest.FormatVersion -ne 1) {
    throw "Unsupported package format version '$($manifest.FormatVersion)'."
}

$parsedPackageId = [Guid]::Empty
if (-not [Guid]::TryParse([string] $manifest.PackageId, [ref] $parsedPackageId)) {
    throw 'The package manifest contains an invalid PackageId.'
}

$sequence = [int] $manifest.Sequence
if ($sequence -lt 1) {
    throw 'The package manifest contains an invalid sequence number.'
}

Write-Host 'Verifying package integrity...' -ForegroundColor Cyan
$artifactNames = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($artifact in @($manifest.Artifacts)) {
    if (-not $artifactNames.Add([string] $artifact.Name)) {
        throw "Duplicate artifact path in manifest: '$($artifact.Name)'."
    }

    $artifactPath = Resolve-PackageArtifactPath -PackagePath $packageRoot -RelativePath $artifact.Name
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        throw "Package artifact is missing: '$($artifact.Name)'."
    }

    $file = Get-Item -LiteralPath $artifactPath
    if ($file.Length -ne [long] $artifact.Length) {
        throw "Package artifact has an unexpected size: '$($artifact.Name)'."
    }

    $actualHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash
    if (-not $actualHash.Equals([string] $artifact.Sha256, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "SHA-256 verification failed for '$($artifact.Name)'."
    }
}

foreach ($packageFile in @(Get-ChildItem -LiteralPath $packageRoot -File -Recurse -Force)) {
    $relativePackagePath = Get-RelativePath -BasePath $packageRoot -Path $packageFile.FullName
    if ($relativePackagePath -eq 'manifest.json') {
        continue
    }
    if (-not $artifactNames.Contains($relativePackagePath)) {
        throw "Package file is not covered by the integrity manifest: '$relativePackagePath'."
    }
}

$requiredArtifactNames = @(
    [string] $manifest.MetadataFile,
    [string] $manifest.ApprovalState.ApprovalsFile,
    [string] $manifest.ApprovalState.DeclinesFile
) + @($manifest.Content.Archives)
foreach ($requiredArtifactName in $requiredArtifactNames) {
    if (-not $artifactNames.Contains($requiredArtifactName)) {
        throw "Required file is not covered by the integrity manifest: '$requiredArtifactName'."
    }
}

$contentEntries = @($manifest.Content.Files)
$contentPaths = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($entry in $contentEntries) {
    $null = Resolve-PackageArtifactPath -PackagePath $packageRoot -RelativePath $entry.RelativePath
    if (-not $contentPaths.Add([string] $entry.RelativePath)) {
        throw "Duplicate content path in manifest: '$($entry.RelativePath)'."
    }
}

if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = Join-Path $env:ProgramData 'WsusOfflinePatchManagement\import-state.json'
}
$importStatePath = Get-FullPath -Path $StatePath
$importMutex = [System.Threading.Mutex]::new(
    $false,
    'Global\WsusOfflinePatchManagement.Import'
)
$lockTaken = $false
try {
    try {
        $lockTaken = $importMutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        $lockTaken = $true
    }
    if (-not $lockTaken) {
        throw 'Another WSUS offline import is already running on this server.'
    }

    $importedPackages = [System.Collections.Generic.List[object]]::new()
    $lastSequence = 0

    if (Test-Path -LiteralPath $importStatePath -PathType Leaf) {
        $importState = Read-JsonFile -Path $importStatePath
        if ([int] $importState.FormatVersion -ne 1) {
            throw "Unsupported import state format in '$importStatePath'."
        }

        $lastSequence = [int] $importState.LastSequence
        foreach ($importedPackage in @($importState.ImportedPackages)) {
            if ([string] $importedPackage.PackageId -eq [string] $manifest.PackageId) {
                throw "Package '$($manifest.PackageId)' has already been imported."
            }
            $importedPackages.Add($importedPackage)
        }
    }

    $expectedSequence = $lastSequence + 1
    if (-not $AllowSequenceGap -and $sequence -ne $expectedSequence) {
        throw "Package sequence $sequence cannot follow imported sequence $lastSequence. Expected $expectedSequence. Use -AllowSequenceGap only after verifying that all earlier content already exists."
    }
    if ($sequence -le $lastSequence) {
        throw "Package sequence $sequence is not newer than imported sequence $lastSequence."
    }

    $contentRoot = Resolve-WsusContentPath -Path $ContentPath
    $wsusUtil = Resolve-WsusUtilPath -Path $WsusUtilPath
    $sevenZip = $null
    $archiveNames = @($manifest.Content.Archives)
    if ($contentEntries.Count -gt 0) {
        $sevenZip = Resolve-SevenZipPath -Path $SevenZipPath
        if ($archiveNames.Count -eq 0) {
            throw 'The package contains content entries but no archive.'
        }

        foreach ($archiveName in $archiveNames) {
            $archivePath = Resolve-PackageArtifactPath -PackagePath $packageRoot -RelativePath $archiveName
            if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
                throw "Content archive is missing: '$archiveName'."
            }
        }
    }

    $approvals = @()
    $declines = @()
    if ($ApplyApprovals -or $ApplyDeclines) {
        if (-not [bool] $manifest.ApprovalState.Included) {
            throw 'This package does not include approval state.'
        }

        if ($ApplyApprovals) {
            $targetGroupExists = @(
                (Get-WsusServer).GetComputerTargetGroups() |
                    Where-Object { $_.Name -eq $ApprovalTargetGroup }
            ).Count -gt 0
            if (-not $targetGroupExists) {
                throw "WSUS target group not found: '$ApprovalTargetGroup'."
            }

            $approvalsPath = Resolve-PackageArtifactPath `
                -PackagePath $packageRoot `
                -RelativePath $manifest.ApprovalState.ApprovalsFile
            $approvals = @(Read-JsonFile -Path $approvalsPath)
            foreach ($approval in $approvals) {
                $validatedId = [Guid]::Empty
                if (-not [Guid]::TryParse([string] $approval.UpdateId, [ref] $validatedId)) {
                    throw "Invalid update ID in approval state: '$($approval.UpdateId)'."
                }
            }
        }

        if ($ApplyDeclines) {
            $declinesPath = Resolve-PackageArtifactPath `
                -PackagePath $packageRoot `
                -RelativePath $manifest.ApprovalState.DeclinesFile
            $declines = @(Read-JsonFile -Path $declinesPath)
            foreach ($decline in $declines) {
                $validatedId = [Guid]::Empty
                if (-not [Guid]::TryParse([string] $decline.UpdateId, [ref] $validatedId)) {
                    throw "Invalid update ID in decline state: '$($decline.UpdateId)'."
                }
            }
        }
    }

    if (-not $PSCmdlet.ShouldProcess(
        $env:COMPUTERNAME,
        "Import WSUS package $($manifest.PackageId) (sequence $sequence)"
    )) {
        return
    }

    if ($contentEntries.Count -gt 0) {
        $firstArchivePath = Resolve-PackageArtifactPath -PackagePath $packageRoot -RelativePath $archiveNames[0]
        Write-Host "Restoring $($contentEntries.Count) WSUS content files..." -ForegroundColor Cyan
        Invoke-NativeTool -FilePath $sevenZip -ArgumentList @('x', '-y', "-o$contentRoot", $firstArchivePath)

        Write-Host 'Verifying restored content...' -ForegroundColor Cyan
        foreach ($entry in $contentEntries) {
            $restoredPath = Get-FullPath -Path (Join-Path $contentRoot $entry.RelativePath)
            if (-not (Test-PathIsWithin -ParentPath $contentRoot -ChildPath $restoredPath) -or
                -not (Test-Path -LiteralPath $restoredPath -PathType Leaf)) {
                throw "Expected content file was not restored: '$($entry.RelativePath)'."
            }

            if ((Get-Item -LiteralPath $restoredPath).Length -ne [long] $entry.Length) {
                throw "Restored content has an unexpected size: '$($entry.RelativePath)'."
            }
        }
    }

    $metadataPath = Resolve-PackageArtifactPath -PackagePath $packageRoot -RelativePath $manifest.MetadataFile
    $stateDirectory = Split-Path -Parent $importStatePath
    $logDirectory = Join-Path $stateDirectory 'logs'
    if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $logDirectory -Force
    }
    $importLogPath = Join-Path $logDirectory (
        'import-{0}-{1}.log' -f $manifest.PackageId, (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    )

    Write-Host 'Importing WSUS metadata...' -ForegroundColor Cyan
    Invoke-NativeTool -FilePath $wsusUtil -ArgumentList @('import', $metadataPath, $importLogPath)

    if ($ApplyApprovals -or $ApplyDeclines) {
        if ($ApplyApprovals) {
            Write-Host "Applying $($approvals.Count) approvals to '$ApprovalTargetGroup'..." -ForegroundColor Cyan
            foreach ($approval in $approvals) {
                Get-WsusUpdate -UpdateId ([Guid] $approval.UpdateId) |
                    Approve-WsusUpdate -Action Install -TargetGroupName $ApprovalTargetGroup -Confirm:$false |
                    Out-Null
            }
        }

        if ($ApplyDeclines) {
            Write-Host "Applying $($declines.Count) declines..." -ForegroundColor Cyan
            foreach ($decline in $declines) {
                Get-WsusUpdate -UpdateId ([Guid] $decline.UpdateId) |
                    Deny-WsusUpdate -Confirm:$false |
                    Out-Null
            }
        }
    }

    $importedPackages.Add([pscustomobject] [ordered] @{
        PackageId   = [string] $manifest.PackageId
        Sequence    = $sequence
        ImportedUtc = (Get-Date).ToUniversalTime().ToString('o')
    })
    $newImportState = [pscustomobject] [ordered] @{
        FormatVersion    = 1
        LastSequence     = $sequence
        UpdatedUtc       = (Get-Date).ToUniversalTime().ToString('o')
        ImportedPackages = @($importedPackages)
    }
    Write-AtomicJsonFile -Path $importStatePath -InputObject $newImportState

    Write-Host "Package sequence $sequence imported successfully." -ForegroundColor Green
    [pscustomobject] [ordered] @{
        PackageId     = [string] $manifest.PackageId
        Sequence      = $sequence
        ContentFiles  = $contentEntries.Count
        ImportLogPath = $importLogPath
    }
}
finally {
    if ($lockTaken) {
        $importMutex.ReleaseMutex()
    }
    $importMutex.Dispose()
}

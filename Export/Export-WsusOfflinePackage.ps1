#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules UpdateServices

<#
.SYNOPSIS
Creates a verified, incremental transfer package on an internet-connected WSUS server.

.DESCRIPTION
Exports the complete WSUS metadata database and packages only content files that have
not appeared in a previous successful export. The package includes SHA-256 checksums,
an inventory, and optional approval and decline snapshots.

.PARAMETER ExportRoot
Directory in which completed packages and the private incremental state file are kept.

.PARAMETER ArchiveVolumeSize
Optional 7-Zip volume size, such as 4g or 700m. Omit it to create one archive.

.EXAMPLE
.\Export-WsusOfflinePackage.ps1 -ExportRoot E:\WsusTransfer
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $ExportRoot,

    [string] $ContentPath,

    [string] $WsusUtilPath,

    [string] $SevenZipPath,

    [ValidateRange(0, 9)]
    [int] $CompressionLevel = 1,

    [ValidatePattern('^\d+[bkmg]?$')]
    [string] $ArchiveVolumeSize,

    [switch] $ExcludeApprovalState
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\src\WsusOffline.Common.ps1')

$contentRoot = Resolve-WsusContentPath -Path $ContentPath
$wsusUtil = Resolve-WsusUtilPath -Path $WsusUtilPath
$sevenZip = Resolve-SevenZipPath -Path $SevenZipPath
$exportRootPath = Get-FullPath -Path $ExportRoot

if (Test-PathIsWithin -ParentPath $contentRoot -ChildPath $exportRootPath) {
    throw 'ExportRoot must not be inside the WSUS content directory.'
}

if (-not (Test-Path -LiteralPath $exportRootPath -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $exportRootPath -Force
}

$lockPath = Join-Path $exportRootPath '.wsus-offline-export.lock'
try {
    $lockStream = [System.IO.File]::Open(
        $lockPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
}
catch {
    throw "Another export is already using '$exportRootPath'."
}

try {
    $statePath = Join-Path $exportRootPath '.wsus-offline-export-state.json'
    $previousFileLengths = [System.Collections.Generic.Dictionary[string, long]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $lastSequence = 0
    $hasPreviousInventory = $false

    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $state = Read-JsonFile -Path $statePath
        if ([int] $state.FormatVersion -ne 1) {
            throw "Unsupported export state format in '$statePath'."
        }

        $lastSequence = [int] $state.LastSequence
        $hasPreviousInventory = ($lastSequence -gt 0)
        foreach ($file in @($state.Files)) {
            $previousFileLengths[[string] $file.RelativePath] = [long] $file.Length
        }
    }
    else {
        foreach ($manifestFile in @(Get-ChildItem -LiteralPath $exportRootPath -Filter manifest.json -File -Recurse)) {
            try {
                $existingManifest = Read-JsonFile -Path $manifestFile.FullName
                $lastSequence = [Math]::Max($lastSequence, [int] $existingManifest.Sequence)
            }
            catch {
                Write-Warning "Ignoring unreadable manifest '$($manifestFile.FullName)' while determining the next sequence."
            }
        }
    }

    Write-Host "Scanning WSUS content in '$contentRoot'..." -ForegroundColor Cyan
    $currentInventory = [System.Collections.Generic.List[object]]::new()
    $newInventory = [System.Collections.Generic.List[object]]::new()

    foreach ($file in @(Get-ChildItem -LiteralPath $contentRoot -File -Recurse | Sort-Object FullName)) {
        $relativePath = Get-RelativePath -BasePath $contentRoot -Path $file.FullName
        $entry = [pscustomobject] [ordered] @{
            RelativePath = $relativePath
            Length       = [long] $file.Length
        }
        $currentInventory.Add($entry)

        if (-not $previousFileLengths.ContainsKey($relativePath) -or
            $previousFileLengths[$relativePath] -ne [long] $file.Length) {
            $newInventory.Add($entry)
        }
    }

    $sequence = $lastSequence + 1
    $createdUtc = (Get-Date).ToUniversalTime()
    $packageId = [Guid]::NewGuid().ToString()
    $packageName = '{0:d6}-{1}' -f $sequence, $createdUtc.ToString('yyyyMMddTHHmmssZ')
    $partialPath = Join-Path $exportRootPath ".partial-$packageId"
    $finalPath = Join-Path $exportRootPath $packageName

    if (Test-Path -LiteralPath $finalPath) {
        throw "Package directory already exists: '$finalPath'."
    }

    $null = New-Item -ItemType Directory -Path $partialPath

    try {
        $listPath = Join-Path $partialPath 'content-files.txt'
        $listEncoding = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllLines(
            $listPath,
            [string[]] @($newInventory | ForEach-Object { $_.RelativePath }),
            $listEncoding
        )

        $archiveFiles = @()
        if ($newInventory.Count -gt 0) {
            Write-Host "Archiving $($newInventory.Count) new content files..." -ForegroundColor Cyan
            $archivePath = Join-Path $partialPath 'content.7z'
            $archiveArguments = [System.Collections.Generic.List[string]]::new()
            foreach ($argument in @('a', '-t7z', "-mx=$CompressionLevel", '-y', '-scsUTF-8')) {
                $archiveArguments.Add($argument)
            }
            if (-not [string]::IsNullOrWhiteSpace($ArchiveVolumeSize)) {
                $archiveArguments.Add("-v$ArchiveVolumeSize")
            }
            $archiveArguments.Add($archivePath)
            $archiveArguments.Add("@$listPath")

            Invoke-NativeTool -FilePath $sevenZip -ArgumentList $archiveArguments.ToArray() -WorkingDirectory $contentRoot
            $archiveFiles = @(Get-ChildItem -LiteralPath $partialPath -Filter 'content.7z*' -File | Sort-Object Name)
            if ($archiveFiles.Count -eq 0) {
                throw '7-Zip completed without creating a content archive.'
            }

            foreach ($entry in $newInventory) {
                $sourcePath = Get-FullPath -Path (Join-Path $contentRoot $entry.RelativePath)
                if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or
                    (Get-Item -LiteralPath $sourcePath).Length -ne [long] $entry.Length) {
                    throw "WSUS content changed while it was being archived: '$($entry.RelativePath)'. Run the export again after synchronization and downloads finish."
                }
            }
        }

        Write-Host 'Exporting WSUS metadata...' -ForegroundColor Cyan
        $metadataPath = Join-Path $partialPath 'metadata.xml.gz'
        $metadataLogPath = Join-Path $partialPath 'wsus-export.log'
        Invoke-NativeTool -FilePath $wsusUtil -ArgumentList @('export', $metadataPath, $metadataLogPath)

        $approvalsPath = Join-Path $partialPath 'approvals.json'
        $declinesPath = Join-Path $partialPath 'declines.json'
        if ($ExcludeApprovalState) {
            $approvedUpdates = @()
            $declinedUpdates = @()
        }
        else {
            Write-Host 'Capturing approval and decline state...' -ForegroundColor Cyan
            $approvedUpdates = @(
                Get-WsusUpdate -Approval Approved |
                    ForEach-Object {
                        [pscustomobject] [ordered] @{
                            UpdateId = $_.UpdateId.ToString()
                        }
                    } |
                    Sort-Object UpdateId -Unique
            )
            $declinedUpdates = @(
                Get-WsusUpdate -Approval Declined |
                    ForEach-Object {
                        [pscustomobject] [ordered] @{
                            UpdateId = $_.UpdateId.ToString()
                        }
                    } |
                    Sort-Object UpdateId -Unique
            )
        }

        Write-JsonFile -Path $approvalsPath -InputObject @($approvedUpdates)
        Write-JsonFile -Path $declinesPath -InputObject @($declinedUpdates)

        $artifactFiles = @(Get-ChildItem -LiteralPath $partialPath -File | Sort-Object Name)
        $artifacts = @(
            $artifactFiles | ForEach-Object {
                Get-ArtifactRecord -PackagePath $partialPath -Path $_.FullName
            }
        )

        $totalContentBytes = [long] 0
        foreach ($entry in $newInventory) {
            $totalContentBytes += [long] $entry.Length
        }

        $manifest = [pscustomobject] [ordered] @{
            FormatVersion = 1
            PackageId     = $packageId
            Sequence      = $sequence
            CreatedUtc    = $createdUtc.ToString('o')
            SourceServer  = $env:COMPUTERNAME
            Content       = [pscustomobject] [ordered] @{
                IsIncremental = $hasPreviousInventory
                FileCount     = $newInventory.Count
                TotalBytes    = $totalContentBytes
                Files         = @($newInventory)
                Archives      = @($archiveFiles | ForEach-Object { $_.Name })
            }
            ApprovalState = [pscustomobject] [ordered] @{
                Included      = -not $ExcludeApprovalState.IsPresent
                ApprovalCount = $approvedUpdates.Count
                DeclineCount  = $declinedUpdates.Count
                ApprovalsFile = 'approvals.json'
                DeclinesFile  = 'declines.json'
            }
            MetadataFile  = 'metadata.xml.gz'
            Artifacts     = $artifacts
        }

        Write-JsonFile -Path (Join-Path $partialPath 'manifest.json') -InputObject $manifest -Depth 20
        Move-Item -LiteralPath $partialPath -Destination $finalPath

        $newState = [pscustomobject] [ordered] @{
            FormatVersion = 1
            LastSequence  = $sequence
            LastPackageId = $packageId
            UpdatedUtc    = (Get-Date).ToUniversalTime().ToString('o')
            Files         = @($currentInventory)
        }
        Write-AtomicJsonFile -Path $statePath -InputObject $newState
    }
    catch {
        if (Test-Path -LiteralPath $partialPath -PathType Container) {
            Remove-Item -LiteralPath $partialPath -Recurse -Force
        }
        throw
    }

    Write-Host "Package created: '$finalPath'" -ForegroundColor Green
    [pscustomobject] [ordered] @{
        PackagePath  = $finalPath
        PackageId    = $packageId
        Sequence     = $sequence
        ContentFiles = $newInventory.Count
        ContentBytes = $totalContentBytes
    }
}
finally {
    $lockStream.Dispose()
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}

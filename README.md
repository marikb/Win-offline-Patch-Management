# WSUS Offline Patch Management

[![Quality](https://github.com/marikb/Win-offline-Patch-Management/actions/workflows/quality.yml/badge.svg)](https://github.com/marikb/Win-offline-Patch-Management/actions/workflows/quality.yml)

Reliable export and import tooling for moving Windows Server Update Services (WSUS) metadata and content across an air gap.

The project builds ordered, incremental transfer packages on a connected WSUS server. Each package carries a complete metadata export, new content files, optional approval state, and a SHA-256 integrity manifest. The disconnected server validates the package and restores content before importing metadata.

> [!NOTE]
> Microsoft has deprecated further WSUS feature development, but WSUS remains supported for production deployments and continues to receive security and quality updates. See the current [WSUS overview](https://learn.microsoft.com/windows-server/administration/windows-server-update-services/get-started/windows-server-update-services-wsus).

## Why use these scripts

- No hard-coded drive letters, WSUS paths, or staging groups
- Incremental content packages backed by durable export state
- Complete metadata export in every package
- SHA-256 validation before any import operation
- Strict package sequencing with an import ledger
- Explicit, opt-in approval, decline, and cleanup actions
- Split archive support for removable media
- PowerShell 5.1 compatibility for supported Windows Server releases
- Fail-fast handling for missing tools, invalid packages, and native command failures

## Requirements

Run the scripts locally from an elevated Windows PowerShell 5.1 session on each WSUS server.

- A supported Windows Server release with the WSUS role and `UpdateServices` module
- [7-Zip](https://www.7-zip.org/) on both servers
- Enough free space for the transfer package
- Matching products, classifications, languages, and express-installation settings on both WSUS servers
- An autonomous disconnected WSUS server; centrally managed downstream servers cannot use this import model

The scripts discover the WSUS content directory from the local WSUS registry configuration. Use `-ContentPath`, `-WsusUtilPath`, or `-SevenZipPath` only when discovery is not suitable.

## Quick start

### 1. Prepare the connected server

Finish WSUS synchronization and allow approved content downloads to complete. Preparation actions are separate from export and make no changes unless explicitly selected.

Review an approval and cleanup run:

```powershell
Set-Location C:\Tools\Win-offline-Patch-Management\Export

.\Invoke-WsusPreparation.ps1 `
    -ApproveEligibleUpdates `
    -MinimumUpdateAgeDays 90 `
    -TargetGroupName 'All Computers' `
    -DeclineExpiredAndSuperseded `
    -WhatIf
```

Remove `-WhatIf` only after reviewing the proposed scope. Cleanup is optional and is not invoked by the export command.

### 2. Create a transfer package

```powershell
.\Export-WsusOfflinePackage.ps1 -ExportRoot E:\WsusTransfer
```

To split large content archives into 4 GiB volumes:

```powershell
.\Export-WsusOfflinePackage.ps1 `
    -ExportRoot E:\WsusTransfer `
    -ArchiveVolumeSize 4g
```

The first package contains all current WSUS content. Later packages contain only files that are new or whose size changed. Keep `E:\WsusTransfer\.wsus-offline-export-state.json`; it is the connected server's incremental inventory.

### 3. Cross the air gap

Copy the completed numbered package directory to trusted removable media. Never transfer a directory whose name starts with `.partial-`.

Import packages in sequence. SHA-256 checks protect against accidental corruption, but do not establish who created a package. Apply the controls required by your removable-media and air-gap policy.

### 4. Import on the disconnected server

```powershell
Set-Location C:\Tools\Win-offline-Patch-Management\Import

.\Import-WsusOfflinePackage.ps1 `
    -PackagePath E:\WsusTransfer\000001-20260714T120000Z
```

The command validates the entire package before prompting for confirmation. It then restores content, verifies the restored files, imports metadata, and records the package in `%ProgramData%\WsusOfflinePatchManagement\import-state.json`.

Approval changes are deliberately opt-in. A safe pattern is to apply imported approvals to a staging group:

```powershell
.\Import-WsusOfflinePackage.ps1 `
    -PackagePath E:\WsusTransfer\000002-20260721T120000Z `
    -ApplyApprovals `
    -ApprovalTargetGroup 'Offline Staging' `
    -ApplyDeclines
```

The target group must already exist. Approval snapshots contain update IDs, not the connected server's target-group layout.

## Documentation

- [Operations runbook](docs/OPERATIONS.md) — deployment, routine operation, recovery, and troubleshooting
- [Package format](docs/PACKAGE-FORMAT.md) — package contents, sequencing, and validation contract
- [Security policy](SECURITY.md) — trust model and private vulnerability reporting
- [Change history](CHANGELOG.md) — notable changes and migration notes

## Important operating rules

1. Keep the two WSUS servers' synchronization options aligned.
2. Do not export while synchronization or content downloads are still active.
3. Keep the export state file and import ledger backed up.
4. Import every incremental package in order.
5. Use `-AllowSequenceGap` only when earlier content is already present and has been independently verified.
6. Accept packages only from a trusted connected WSUS server.

Microsoft's supported disconnected workflow is described in [Synchronize software updates with no Internet connection](https://learn.microsoft.com/intune/configmgr/sum/get-started/synchronize-software-updates-disconnected) and [Setting up update synchronizations](https://learn.microsoft.com/windows-server/administration/windows-server-update-services/manage/setting-up-update-synchronizations).

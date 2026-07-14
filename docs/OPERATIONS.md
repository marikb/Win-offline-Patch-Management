# Operations runbook

This runbook covers the controlled movement of WSUS updates from an internet-connected server to an autonomous server on a disconnected network.

## Operating model

The connected server is the source of truth for update metadata and content. Each successful export creates one numbered package:

```text
Connected WSUS                 Transfer media                 Disconnected WSUS
sync and download -> export -> validate/copy -> import -> content, metadata, policy
```

Metadata exports are complete. Content archives are incremental after the first package. This distinction matters: a later metadata file can be imported independently, but its corresponding update payloads may depend on earlier content packages.

## Initial deployment

1. Install the WSUS role and current Windows updates on both servers.
2. Install 7-Zip on both servers.
3. Copy this repository to a local tools directory on each server.
4. Configure the disconnected server as autonomous.
5. Match products, classifications, update languages, and express-installation settings.
6. Create an approval staging group on the disconnected server if approvals will be transferred.
7. Select durable locations for:
   - the connected server's export root;
   - removable-media package copies;
   - the disconnected server's import state and logs.

The default import state is `%ProgramData%\WsusOfflinePatchManagement\import-state.json`. Back it up with the server's operational configuration.

## Connected-server procedure

### Preflight

Before every export:

1. Confirm the latest WSUS synchronization completed successfully.
2. Confirm update downloads are no longer active.
3. Confirm the export volume has enough free space.
4. Confirm no other export process is using the same export root.
5. Decide whether approval or cleanup policy needs to run. Export itself does not change policy.

### Optional policy preparation

`Invoke-WsusPreparation.ps1` has no default action. All mutating operations support `-WhatIf` and confirmation.

Approve unapproved updates that are at least 30 days old:

```powershell
.\Invoke-WsusPreparation.ps1 `
    -ApproveEligibleUpdates `
    -MinimumUpdateAgeDays 30 `
    -TargetGroupName 'Pilot' `
    -WhatIf
```

Decline expired and superseded updates, then clean obsolete metadata and unneeded content:

```powershell
.\Invoke-WsusPreparation.ps1 `
    -DeclineExpiredAndSuperseded `
    -CleanupObsoleteUpdates `
    -CleanupUnneededContentFiles `
    -WhatIf
```

Remove `-WhatIf` only after reviewing the operation. Approval waits for selected update files to reach the WSUS `Ready` state and fails when `-DownloadTimeoutMinutes` is exceeded.

### Export

Standard export:

```powershell
.\Export-WsusOfflinePackage.ps1 -ExportRoot E:\WsusTransfer
```

Common overrides:

```powershell
.\Export-WsusOfflinePackage.ps1 `
    -ExportRoot E:\WsusTransfer `
    -ContentPath D:\WSUS\WsusContent `
    -SevenZipPath 'C:\Program Files\7-Zip\7z.exe' `
    -CompressionLevel 1 `
    -ArchiveVolumeSize 4g
```

Use `-ExcludeApprovalState` when approval and decline data must not cross the boundary. The package still contains empty policy files so its structure remains consistent.

On success, the command returns the package path, ID, sequence, content file count, and uncompressed content size. An incomplete export is removed automatically and never receives a numbered directory name.

### Export state

The export root contains `.wsus-offline-export-state.json`. It records the last sequence and the path and size of every content file seen during the last successful run.

- Do not copy this file across the air gap.
- Do not edit it manually.
- Back it up with the connected server's WSUS configuration.
- If it is lost, the next package safely includes a full content snapshot. The next sequence is recovered from existing manifests when possible.

Only one process can use an export root at a time. A lock prevents concurrent runs from allocating the same sequence.

## Transfer procedure

1. Select the completed numbered package directory.
2. Confirm that `manifest.json` exists.
3. Copy the whole directory, including every split archive volume.
4. Apply the organization's removable-media scanning, custody, and labeling controls.
5. On the disconnected side, copy or mount the package without changing its files.

The import command recomputes every recorded SHA-256 value. A checksum proves that a package matches its manifest; because the manifest is not digitally signed, it does not prove origin. Only accept media through a trusted chain of custody.

## Disconnected-server procedure

### Preflight without changes

`-WhatIf` performs package and environment validation, then stops before content or WSUS changes:

```powershell
.\Import-WsusOfflinePackage.ps1 `
    -PackagePath E:\WsusTransfer\000001-20260714T120000Z `
    -WhatIf
```

If approvals are requested, preflight also confirms that the target group exists and that every update ID is a valid GUID.

### Import content and metadata

```powershell
.\Import-WsusOfflinePackage.ps1 `
    -PackagePath E:\WsusTransfer\000001-20260714T120000Z
```

The import order is fixed:

1. Validate manifest structure, sequence, sizes, and hashes.
2. Extract content into the configured WSUS content directory.
3. Verify every restored content path and size.
4. Import the complete metadata package with `WsusUtil.exe`.
5. Apply requested approvals and declines.
6. Atomically update the import ledger.

For unattended execution after a separate change-control approval, add `-Confirm:$false`.

### Approval and decline policy

Approval state is not applied unless `-ApplyApprovals` is present. A destination target group is mandatory:

```powershell
.\Import-WsusOfflinePackage.ps1 `
    -PackagePath E:\WsusTransfer\000002-20260721T120000Z `
    -ApplyApprovals `
    -ApprovalTargetGroup 'Offline Staging'
```

Declines are independently controlled with `-ApplyDeclines`. If the same update appears in both snapshots, decline is applied last.

The connected server's group topology is not exported. All captured approved update IDs are applied to the single destination group specified for that import.

## Sequence handling

The normal sequence begins at 1 and increases by one. Import rejects:

- a package that was already recorded;
- an older sequence;
- a gap in the sequence.

Only one import can run on a server at a time. A machine-wide lock protects the sequence ledger for the duration of content, metadata, and policy processing.

`-AllowSequenceGap` bypasses only the gap check. It is intended for a server whose earlier content was restored through another verified process. It does not download or reconstruct missing payloads.

To use a nondefault ledger location:

```powershell
.\Import-WsusOfflinePackage.ps1 `
    -PackagePath E:\WsusTransfer\000001-20260714T120000Z `
    -StatePath D:\WSUS-State\import-state.json
```

Use the same state path for every import on that server.

## Logs and audit evidence

- The export package contains `wsus-export.log` from `WsusUtil.exe`.
- Import logs are written beside the import state, under `logs`.
- `manifest.json` records package identity, source server, UTC creation time, sequence, content inventory, and artifact hashes.
- The import ledger records each successfully completed package and UTC import time.

Retain these files according to the environment's update-management and media-handling policy.

## Recovery and troubleshooting

### Integrity validation fails

Do not import the package. Recopy it from trusted source media. If the source copy also fails, discard it and run a new export.

### Sequence validation fails

Locate and import the missing package. Do not use `-AllowSequenceGap` merely to clear the error; incremental archives may rely on content from that package.

### Content changed during export

Wait for synchronization and downloads to finish, then rerun export. The incomplete package is removed automatically.

### `WsusUtil.exe` fails

Review the package's `wsus-export.log` or the disconnected server's import log. Also review `%ProgramFiles%\Update Services\LogFiles\SoftwareDistribution.log` and the Windows event logs.

### Approval application fails after metadata import

Correct the target group or update-state issue and rerun the same package. The ledger is written only after every requested operation completes. Content extraction and metadata import are designed to be repeatable.

### Export state was lost

Keep the existing numbered package directories in the export root and rerun export. Sequence recovery reads their manifests, while content is exported as a full snapshot to avoid omissions.

## Legacy migration

The former scripts used fixed `F:` and `D:` paths, selected import folders by modification time, renamed archive paths in place, and automatically ran approval and cleanup logic. Those entry points have been removed.

For the first run of the current workflow:

1. Choose a new or empty export root.
2. Let sequence 1 create a full content package.
3. Import sequence 1 on the disconnected server.
4. Preserve both state files for later incremental runs.

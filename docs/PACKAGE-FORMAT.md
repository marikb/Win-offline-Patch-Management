# Package format

This document defines package format version 1.

## Directory layout

An unsplit package has this structure:

```text
000001-20260714T120000Z/
|-- approvals.json
|-- content-files.txt
|-- content.7z
|-- declines.json
|-- manifest.json
|-- metadata.xml.gz
`-- wsus-export.log
```

When archive volumes are enabled, `content.7z` is replaced by `content.7z.001`, `content.7z.002`, and so on. A metadata-only package has no content archive and an empty `content-files.txt`.

## Naming and identity

The directory name combines a six-digit sequence and UTC creation timestamp. Consumers must use the values inside `manifest.json` as authoritative; the directory can be renamed during transport.

Each package has a random GUID `PackageId`. The import ledger uses this ID to prevent accidental replay.

## Manifest fields

`manifest.json` contains:

| Field | Meaning |
| --- | --- |
| `FormatVersion` | Package schema version; currently `1` |
| `PackageId` | Unique package GUID |
| `Sequence` | Monotonically increasing export sequence |
| `CreatedUtc` | ISO 8601 creation time in UTC |
| `SourceServer` | Connected WSUS computer name |
| `Content` | Incremental flag, file count, byte count, inventory, and archive names |
| `ApprovalState` | Whether policy state is included and the relevant counts and filenames |
| `MetadataFile` | WSUS metadata export filename |
| `Artifacts` | Relative path, byte length, and SHA-256 for every file except the manifest |

Each content inventory entry has a path relative to the WSUS content root and an expected byte length. Paths must be relative, must remain inside the destination content root, and must not be duplicated case-insensitively.

## Integrity model

Every artifact except `manifest.json` is hashed with SHA-256. Import checks both length and hash before extraction or database changes. Restored content is checked again by relative path and size.

The manifest is not signed. Checksums detect incomplete or changed transfers but cannot prove package origin against an attacker who can replace both artifacts and manifest. Authenticity depends on trusted source systems, controlled removable media, and chain-of-custody procedures.

## Incremental behavior

The connected server maintains a private inventory outside package directories. A file is included when its relative path has not been exported previously or its size has changed.

WSUS metadata is always a complete `WsusUtil.exe export`, including in incremental content packages. Approval and decline snapshots, when enabled, are also complete snapshots for that export.

Because update payloads are incremental, packages normally have to be imported in sequence. The package format does not include a content-level dependency graph.

## Compatibility policy

Import rejects unknown format versions. A future incompatible format will increment `FormatVersion` and document migration requirements here.

# Changelog

Notable changes to this project are recorded here.

## Unreleased

### Changed

- Replaced fixed-path export and import scripts with parameterized PowerShell 5.1 commands.
- Separated WSUS approval and maintenance policy from package export.
- Changed import order to restore content before metadata.
- Replaced modification-time package selection with an explicit package path and sequence ledger.
- Replaced serialized WSUS objects with portable JSON update-ID snapshots.
- Replaced filename-only incremental detection with a durable relative-path and size inventory.

### Added

- Atomic package creation and export locking.
- SHA-256 artifact manifests and restored-content verification.
- Optional split archives for removable media.
- Explicit approval target groups and opt-in decline application.
- Fail-fast native command handling and import logs.
- Operations, package-format, security, and migration documentation.
- Dependency-free repository checks and Windows CI validation.
- MIT license.
- Repository validation now enforces approved PowerShell verbs and a `#Requires -Version 5.1` declaration in every runtime script.
- `#Requires -Version 5.1` declaration in the shared module.
- Dependabot configuration to keep GitHub Actions versions current.

### Fixed

- Export no longer reuses a package sequence number when the incremental state file is stale, lagging, or restored from backup; the next sequence is reconciled against the completed packages in the export root on every run.
- Export sequence recovery now ignores provisional `.partial-*` directories and nested copies, preventing a phantom import sequence gap.
- Repository validation reports every failure in a run instead of stopping at the first.

### Removed

- Hard-coded `F:` and `D:` drive assumptions.
- Automatic approval and cleanup execution during export.
- In-place archive renaming during import.
- Ambiguous legacy script names.

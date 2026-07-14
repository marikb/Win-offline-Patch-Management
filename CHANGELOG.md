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

### Removed

- Hard-coded `F:` and `D:` drive assumptions.
- Automatic approval and cleanup execution during export.
- In-place archive renaming during import.
- Ambiguous legacy script names.

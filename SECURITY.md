# Security policy

## Supported version

Security fixes are applied to the current default branch. Legacy fixed-path scripts are not supported.

## Reporting a vulnerability

Please report suspected vulnerabilities privately through [GitHub Security Advisories](https://github.com/marikb/Win-offline-Patch-Management/security/advisories/new). Include the affected script, a reproducible scenario, impact, and any suggested mitigation. Do not include sensitive WSUS data, internal hostnames, or production logs unless they have been sanitized.

## Package trust model

Import verifies package size and SHA-256 values before changing WSUS. These checks detect corruption, not authorship: the manifest is not digitally signed. Accept packages only from a trusted connected server and through an approved removable-media process.

Run the scripts with administrative rights only on the local WSUS server. Review `-WhatIf` output before approval, cleanup, or import operations. Keep the repository, export state, import ledger, and transfer media writable only by authorized administrators.

Microsoft also warns against importing WSUS data from an untrusted source because it can compromise the server. Refer to its [disconnected software update guidance](https://learn.microsoft.com/intune/configmgr/sum/get-started/synchronize-software-updates-disconnected).

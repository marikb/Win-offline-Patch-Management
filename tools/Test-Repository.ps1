#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()
$powerShellFiles = @(
    Get-ChildItem -LiteralPath $repositoryRoot -File -Recurse |
        Where-Object { $_.Extension -in @('.ps1', '.psm1') }
)

foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref] $tokens,
        [ref] $parseErrors
    )

    foreach ($parseError in $parseErrors) {
        $relativePath = $file.FullName.Substring($repositoryRoot.Length + 1)
        $failures.Add(
            "$relativePath`:$($parseError.Extent.StartLineNumber): $($parseError.Message)"
        )
    }

    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $file.FullName) {
        $lineNumber++
        if ($line -match '[ \t]+$') {
            $relativePath = $file.FullName.Substring($repositoryRoot.Length + 1)
            $failures.Add("$relativePath`:$lineNumber`: trailing whitespace")
        }
    }
}

$runtimeFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'Export') -File -Filter *.ps1
    Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'Import') -File -Filter *.ps1
    Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'src') -File -Filter *.ps1
)
$legacyPathPattern = '(?i)\b[def]:\\(?:ExportContent|ImportContent|WsusContent)'
foreach ($file in $runtimeFiles) {
    if ((Get-Content -LiteralPath $file.FullName -Raw) -match $legacyPathPattern) {
        $relativePath = $file.FullName.Substring($repositoryRoot.Length + 1)
        $failures.Add("$relativePath`: contains a legacy hard-coded content path")
    }
}

foreach ($file in $runtimeFiles) {
    if ((Get-Content -LiteralPath $file.FullName -Raw) -notmatch '(?m)^#Requires\s+-Version\s+5\.1\b') {
        $relativePath = $file.FullName.Substring($repositoryRoot.Length + 1)
        $failures.Add("$relativePath`: missing '#Requires -Version 5.1' declaration")
    }
}

$requiredFiles = @(
    'README.md',
    'SECURITY.md',
    'CHANGELOG.md',
    'docs\OPERATIONS.md',
    'docs\PACKAGE-FORMAT.md',
    'Export\Export-WsusOfflinePackage.ps1',
    'Export\Invoke-WsusPreparation.ps1',
    'Import\Import-WsusOfflinePackage.ps1'
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot $relativePath) -PathType Leaf)) {
        $failures.Add("Required file is missing: $relativePath")
    }
}

$markdownFiles = @(Get-ChildItem -LiteralPath $repositoryRoot -File -Filter *.md -Recurse)
foreach ($markdownFile in $markdownFiles) {
    $markdown = Get-Content -LiteralPath $markdownFile.FullName -Raw
    foreach ($match in [regex]::Matches($markdown, '\[[^\]]+\]\(([^)]+)\)')) {
        $target = $match.Groups[1].Value
        if ($target -match '^(?:https?://|mailto:|#)') {
            continue
        }

        $localTarget = ($target -split '#', 2)[0]
        $resolvedTarget = Join-Path $markdownFile.DirectoryName $localTarget
        if (-not (Test-Path -LiteralPath $resolvedTarget)) {
            $relativeMarkdownPath = $markdownFile.FullName.Substring($repositoryRoot.Length + 1)
            $failures.Add("$relativeMarkdownPath`: local link does not resolve: '$target'")
        }
    }
}

$approvedVerbs = [System.Collections.Generic.HashSet[string]]::new(
    [string[]] @(Get-Verb | ForEach-Object { $_.Verb }),
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($file in $powerShellFiles) {
    $fileAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref] $null,
        [ref] $null
    )
    $functionAsts = $fileAst.FindAll(
        { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] },
        $true
    )
    foreach ($functionAst in $functionAsts) {
        if ($functionAst.Name -notmatch '-') {
            continue
        }
        $verb = ($functionAst.Name -split '-', 2)[0]
        if (-not $approvedVerbs.Contains($verb)) {
            $relativePath = $file.FullName.Substring($repositoryRoot.Length + 1)
            $failures.Add("$relativePath`: function '$($functionAst.Name)' uses unapproved verb '$verb'")
        }
    }
}

$temporaryRoot = Join-Path $env:TEMP ('wsus-offline-test-' + [Guid]::NewGuid().ToString('N'))
try {
    . (Join-Path $repositoryRoot 'src\WsusOffline.Common.ps1')

    $packagePath = Join-Path $temporaryRoot 'package'
    $nestedPath = Join-Path $packagePath 'nested'
    $null = New-Item -ItemType Directory -Path $nestedPath -Force
    $samplePath = Join-Path $nestedPath 'sample.txt'
    [System.IO.File]::WriteAllText(
        $samplePath,
        'sample',
        [System.Text.UTF8Encoding]::new($false)
    )

    $relativePath = Get-RelativePath -BasePath $packagePath -Path $samplePath
    if ($relativePath -ne 'nested\sample.txt') {
        throw "Unexpected relative path: '$relativePath'."
    }
    if (-not (Test-PathIsWithin -ParentPath $packagePath -ChildPath $samplePath)) {
        throw 'Path containment test failed.'
    }
    if ((Resolve-PackageArtifactPath -PackagePath $packagePath -RelativePath $relativePath) -ne
        (Get-FullPath -Path $samplePath)) {
        throw 'Package artifact resolution test failed.'
    }

    $artifact = Get-ArtifactRecord -PackagePath $packagePath -Path $samplePath
    if ($artifact.Length -ne 6 -or $artifact.Sha256.Length -ne 64) {
        throw 'Artifact record test failed.'
    }

    $statePath = Join-Path $temporaryRoot 'state.json'
    Write-AtomicJsonFile -Path $statePath -InputObject ([pscustomobject] @{
        FormatVersion = 1
        Files = @([pscustomobject] @{
            RelativePath = $relativePath
            Length = 6
        })
    })
    $state = Read-JsonFile -Path $statePath
    if ($state.FormatVersion -ne 1 -or @($state.Files).Count -ne 1) {
        throw 'JSON state round-trip test failed.'
    }

    Write-AtomicJsonFile -Path $statePath -InputObject ([pscustomobject] @{
        FormatVersion = 2
        Files = @()
    })
    $replacementState = Read-JsonFile -Path $statePath
    if ($replacementState.FormatVersion -ne 2) {
        throw 'Atomic JSON replacement test failed.'
    }

    $emptyArrayPath = Join-Path $temporaryRoot 'empty-array.json'
    Write-JsonFile -Path $emptyArrayPath -InputObject @()
    if ((Get-Content -LiteralPath $emptyArrayPath -Raw).Trim() -ne '[]') {
        throw 'Empty JSON array serialization test failed.'
    }

    $singleArrayPath = Join-Path $temporaryRoot 'single-array.json'
    Write-JsonFile -Path $singleArrayPath -InputObject @([pscustomobject] @{ Value = 1 })
    $singleArrayJson = (Get-Content -LiteralPath $singleArrayPath -Raw).Trim()
    if (-not ($singleArrayJson.StartsWith('[') -and $singleArrayJson.EndsWith(']'))) {
        throw 'Single-item JSON array serialization test failed.'
    }

    $volumeRoot = [System.IO.Path]::GetPathRoot($repositoryRoot)
    if ((Get-FullPath -Path $volumeRoot) -ne $volumeRoot) {
        throw 'Volume-root path normalization test failed.'
    }

    Invoke-NativeTool -FilePath $env:ComSpec -ArgumentList @('/d', '/c', 'exit', '0')
    $nativeFailureDetected = $false
    try {
        Invoke-NativeTool -FilePath $env:ComSpec -ArgumentList @('/d', '/c', 'exit', '7')
    }
    catch {
        $nativeFailureDetected = ($_.Exception.Message -match 'exit code 7')
    }
    $global:LASTEXITCODE = 0
    if (-not $nativeFailureDetected) {
        throw 'Native command failure test failed.'
    }

    $unsafePathAccepted = $false
    try {
        $null = Resolve-PackageArtifactPath -PackagePath $packagePath -RelativePath '..\escape.txt'
        $unsafePathAccepted = $true
    }
    catch {
        $unsafePathAccepted = $false
    }
    if ($unsafePathAccepted) {
        throw 'Unsafe relative path test failed.'
    }
}
catch {
    $failures.Add("Common helper test failed: $($_.Exception.Message)")
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    throw "Repository validation failed with $($failures.Count) error(s)."
}

Write-Host "Repository validation passed for $($powerShellFiles.Count) PowerShell files." -ForegroundColor Green

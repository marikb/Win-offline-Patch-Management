#Requires -Version 5.1

Set-StrictMode -Version Latest

function Get-FullPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    # Resolve a relative path against the current PowerShell file-system
    # location rather than the process working directory. .NET's GetFullPath
    # uses [Environment]::CurrentDirectory, which PowerShell does not keep in
    # sync with Set-Location, so a relative -ExportRoot/-PackagePath/-ContentPath
    # would otherwise silently resolve against the wrong directory. Rooted
    # (absolute) paths are left untouched.
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = [System.IO.Path]::Combine(
            $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath,
            $Path
        )
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootPath = [System.IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Equals($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath
    }

    return $fullPath.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
}

function Get-RelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $BasePath,

        [Parameter(Mandatory)]
        [string] $Path
    )

    $base = Get-FullPath -Path $BasePath
    $baseWithSeparator = $base.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    $baseUri = [System.Uri]::new($baseWithSeparator)
    $pathUri = [System.Uri]::new((Get-FullPath -Path $Path))
    $relativeUri = $baseUri.MakeRelativeUri($pathUri)

    return [System.Uri]::UnescapeDataString($relativeUri.ToString()).Replace(
        [System.IO.Path]::AltDirectorySeparatorChar,
        [System.IO.Path]::DirectorySeparatorChar
    )
}

function Test-PathIsWithin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ParentPath,

        [Parameter(Mandatory)]
        [string] $ChildPath
    )

    $parentPathValue = Get-FullPath -Path $ParentPath
    $child = Get-FullPath -Path $ChildPath
    if ($child.Equals($parentPathValue, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $parentWithSeparator = $parentPathValue.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar
    return $child.StartsWith($parentWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)
}

function Resolve-WsusContentPath {
    [CmdletBinding()]
    param(
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $setupKey = 'HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup'
        try {
            $Path = (Get-ItemProperty -LiteralPath $setupKey -Name ContentDir -ErrorAction Stop).ContentDir
        }
        catch {
            throw "The WSUS content directory could not be read from '$setupKey'. Supply -ContentPath explicitly."
        }
    }

    $resolved = Get-FullPath -Path $Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "The WSUS content directory does not exist: '$resolved'."
    }

    return $resolved
}

function Resolve-WsusUtilPath {
    [CmdletBinding()]
    param(
        [string] $Path
    )

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $candidates.Add($Path)
    }

    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $candidates.Add((Join-Path $env:ProgramFiles 'Update Services\Tools\WsusUtil.exe'))
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Get-FullPath -Path $candidate)
        }
    }

    throw 'WsusUtil.exe was not found. Supply its full path with -WsusUtilPath.'
}

function Resolve-SevenZipPath {
    [CmdletBinding()]
    param(
        [string] $Path
    )

    $candidates = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $candidates.Add($Path)
    }

    $command = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $candidates.Add($command.Source)
    }

    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $candidates.Add((Join-Path $env:ProgramFiles '7-Zip\7z.exe'))
    }

    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $candidates.Add((Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe'))
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Get-FullPath -Path $candidate)
        }
    }

    throw '7z.exe was not found. Install 7-Zip or supply its full path with -SevenZipPath.'
}

function Invoke-NativeTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $ArgumentList,

        [string] $WorkingDirectory
    )

    $locationChanged = $false
    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            Push-Location -LiteralPath $WorkingDirectory
            $locationChanged = $true
        }

        & $FilePath @ArgumentList
        $exitCode = $LASTEXITCODE
    }
    finally {
        if ($locationChanged) {
            Pop-Location
        }
    }

    if ($exitCode -ne 0) {
        $displayArguments = $ArgumentList -join ' '
        throw "Native command failed with exit code $exitCode`: '$FilePath' $displayArguments"
    }
}

function Write-JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $InputObject,

        [ValidateRange(2, 100)]
        [int] $Depth = 12
    )

    if ($InputObject -is [System.Array] -and $InputObject.Count -eq 0) {
        $json = '[]'
    }
    else {
        $json = ConvertTo-Json -InputObject $InputObject -Depth $Depth
    }
    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Get-FullPath -Path $Path), $json + [Environment]::NewLine, $encoding)
}

function Write-AtomicJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [object] $InputObject
    )

    $fullPath = Get-FullPath -Path $Path
    $directory = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }

    $temporaryPath = "$fullPath.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        Write-JsonFile -Path $temporaryPath -InputObject $InputObject
        Move-Item -LiteralPath $temporaryPath -Destination $fullPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Read-JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON file not found: '$Path'."
    }

    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-ArtifactRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $PackagePath,

        [Parameter(Mandatory)]
        [string] $Path
    )

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    $hash = Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256

    return [pscustomobject] [ordered] @{
        Name   = Get-RelativePath -BasePath $PackagePath -Path $item.FullName
        Length = $item.Length
        Sha256 = $hash.Hash.ToLowerInvariant()
    }
}

function Resolve-PackageArtifactPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $PackagePath,

        [Parameter(Mandatory)]
        [string] $RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "Unsafe package path: '$RelativePath'."
    }

    $segments = $RelativePath -split '[\\/]'
    if ($segments -contains '..' -or $segments -contains '.') {
        throw "Unsafe package path: '$RelativePath'."
    }

    $packageRoot = Get-FullPath -Path $PackagePath
    $resolved = Get-FullPath -Path (Join-Path $packageRoot $RelativePath)
    if (-not (Test-PathIsWithin -ParentPath $packageRoot -ChildPath $resolved)) {
        throw "Package path escapes the package directory: '$RelativePath'."
    }

    return $resolved
}

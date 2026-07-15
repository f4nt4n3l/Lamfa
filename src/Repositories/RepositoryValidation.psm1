# Repository path normalization + validation.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking

function Get-NormalizedPath {
    <#
    .SYNOPSIS
        Canonical form of a Windows path for storage and comparison: absolute,
        backslashes, no trailing separator (except drive roots), original case
        preserved. Comparison is case-insensitive via Test-SamePath.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 3 -and $full -ne '/') { $full = $full.TrimEnd('\', '/') }
    return $full
}

function Test-SamePath {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$PathA,
        [Parameter(Mandatory)][string]$PathB
    )
    # Windows paths are case-insensitive; POSIX paths are case-sensitive.
    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    return [string]::Equals((Get-NormalizedPath $PathA), (Get-NormalizedPath $PathB), $comparison)
}

function Test-PathInsideRoot {
    <#
    .SYNOPSIS
        True when Path is Root itself or located anywhere below Root.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $p = (Get-NormalizedPath $Path) + $separator
    $r = (Get-NormalizedPath $Root) + $separator
    $comparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    return $p.StartsWith($r, $comparison)
}

function Test-IsDriveRoot {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path)
    $normalized = Get-NormalizedPath $Path
    if ($normalized -eq '/') { return $true }   # POSIX filesystem root
    return $normalized -match '^[A-Za-z]:\\?$'
}

function Lamfa-TestRepository {
    <#
    .SYNOPSIS
        Validates a repository folder: exists + whether it is a Git repository
        (worktrees included - .git may be a file). Returns a validation record.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Path)

    $exists = Test-Path -LiteralPath $Path -PathType Container
    $isGit = $false
    $gitDirectory = $null
    if ($exists) {
        $result = Invoke-ExternalCommand -Executable git -Arguments @('rev-parse', '--git-dir') -WorkingDirectory $Path
        if ($result.Succeeded) {
            $isGit = $true
            $gitDirectory = $result.StandardOutput.Trim()
            if (-not [System.IO.Path]::IsPathRooted($gitDirectory)) {
                $gitDirectory = Get-NormalizedPath (Join-Path $Path $gitDirectory)
            }
        }
    }
    return [pscustomobject]@{
        PSTypeName      = 'Lamfa.RepositoryValidation'
        Path            = if ($exists) { Get-NormalizedPath $Path } else { $Path }
        Exists          = $exists
        IsGitRepository = $isGit
        GitDirectory    = $gitDirectory
    }
}

Export-ModuleMember -Function Get-NormalizedPath, Test-SamePath, Test-PathInsideRoot, Test-IsDriveRoot, Lamfa-TestRepository

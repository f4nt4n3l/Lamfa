# Version source, changelog, and Git bundle backup.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking

function Lamfa-GetProjectVersion {
    <#
    .SYNOPSIS
        Reads + validates the version from the profile-defined version file
       . Supports csproj (<Version>), package.json (version), and raw
        one-line version files.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [Parameter(Mandatory)][string]$VersionFile
    )
    $fullPath = Join-Path $RepositoryPath $VersionFile
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "ValidationError: version file not found: $VersionFile"
    }
    $raw = Get-Content -LiteralPath $fullPath -Raw
    $version = $null
    if ($VersionFile -like '*.csproj') {
        if ($raw -match '<Version>\s*([0-9]+\.[0-9]+\.[0-9]+[^<\s]*)\s*</Version>') { $version = $Matches[1] }
    } elseif ($VersionFile -like '*package.json') {
        $json = $raw | ConvertFrom-Json
        if ($json.PSObject.Properties['version']) { $version = [string]$json.version }
    } else {
        $trimmed = $raw.Trim()
        if ($trimmed -match '^v?([0-9]+\.[0-9]+\.[0-9]+\S*)$') { $version = $Matches[1] }
    }
    if (-not $version) {
        throw "ValidationError: no SemVer version found in $VersionFile. Expected e.g. <Version>1.2.3</Version> (csproj), ""version"" (package.json), or a bare version line."
    }
    return [pscustomobject]@{
        PSTypeName = 'Lamfa.ProjectVersion'
        Version    = $version
        File       = $VersionFile
    }
}

function Lamfa-GetChangelogSection {
    <#
    .SYNOPSIS
        Extracts one section ('Unreleased' or a version number) from a
        Keep-a-Changelog style CHANGELOG.md.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [Parameter()][string]$Section = 'Unreleased',
        [Parameter()][string]$ChangelogFile = 'CHANGELOG.md'
    )
    $fullPath = Join-Path $RepositoryPath $ChangelogFile
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "ValidationError: changelog not found: $ChangelogFile"
    }
    $inSection = $false
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in (Get-Content -LiteralPath $fullPath)) {
        if ($line -match '^\#\#\s*\[(.+?)\]') {
            if ($inSection) { break }
            if ($Matches[1] -eq $Section) { $inSection = $true; continue }
        } elseif ($inSection) {
            $lines.Add($line)
        }
    }
    if (-not $inSection) { throw "ValidationError: changelog has no [$Section] section." }
    return (($lines -join "`n").Trim())
}

function New-GitBundleBackup {
    <#
    .SYNOPSIS
        Exports the ENTIRE repository history as a verified .bundle file
        - a single-file backup restorable with 'git clone <bundle>'.
        Not a replacement for pushing commits.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [Parameter(Mandatory)][string]$DestinationDirectory
    )
    if (-not (Test-Path -Path $DestinationDirectory)) {
        $null = New-Item -ItemType Directory -Path $DestinationDirectory -Force
    }
    $name = (Split-Path $RepositoryPath -Leaf) -replace '[^\w.\-]', '_'
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $bundlePath = Join-Path $DestinationDirectory "$name-$stamp.bundle"
    $create = Invoke-ExternalCommand -Executable git -Arguments @('bundle', 'create', $bundlePath, '--all') `
        -WorkingDirectory $RepositoryPath -TimeoutSeconds 3600
    if (-not $create.Succeeded) { throw "ExternalCommandError: bundle create failed. $($create.StandardError)" }
    $verify = Invoke-ExternalCommand -Executable git -Arguments @('bundle', 'verify', $bundlePath) `
        -WorkingDirectory $RepositoryPath -TimeoutSeconds 600
    if (-not $verify.Succeeded) { throw "ExternalCommandError: bundle verification FAILED - do not rely on this backup. $($verify.StandardError)" }
    return [pscustomobject]@{
        PSTypeName = 'Lamfa.GitBundleBackup'
        Path       = $bundlePath
        SizeBytes  = (Get-Item -LiteralPath $bundlePath).Length
        Verified   = $true
    }
}

Export-ModuleMember -Function Lamfa-GetProjectVersion, Lamfa-GetChangelogSection, New-GitBundleBackup

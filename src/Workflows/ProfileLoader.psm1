# Profile loading, validation, and trust. Profiles are DATA: executable + argument array only, no
# expressions. Repository-owned profiles need explicit trust (repo id + hash).
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Configuration.psm1') -DisableNameChecking

function Lamfa-TestProfile {
    <#
    .SYNOPSIS
        Validates a parsed profile object; returns actionable error strings
        (empty = valid). Same comma-return contract as Lamfa-TestConfiguration.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$RepoProfile,
        [Parameter()][string]$SourceDescription = 'profile'
    )
    $problems = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $RepoProfile) {
        $problems.Add("$($SourceDescription): empty or invalid JSON.")
        return ,$problems.ToArray()
    }
    function HasProp([object]$o, [string]$n) { return $null -ne ($o.PSObject.Properties | Where-Object Name -eq $n) }
    if (-not (HasProp $RepoProfile 'schemaVersion') -or $RepoProfile.schemaVersion -ne 1) {
        $problems.Add("$($SourceDescription): 'schemaVersion' must be 1.")
    }
    if ((HasProp $RepoProfile 'commands') -and ($null -ne $RepoProfile.commands)) {
        foreach ($commandProperty in $RepoProfile.commands.PSObject.Properties) {
            $command = $commandProperty.Value
            if (-not (HasProp $command 'executable') -or [string]::IsNullOrWhiteSpace([string]$command.executable)) {
                $problems.Add("$($SourceDescription): command '$($commandProperty.Name)' has no 'executable'.")
            }
            if ((HasProp $command 'executable') -and (([string]$command.executable) -match '[|;&<>]')) {
                $problems.Add("$($SourceDescription): command '$($commandProperty.Name)' executable contains shell metacharacters - profiles are data, not shell strings.")
            }
            if ((HasProp $command 'arguments') -and ($null -ne $command.arguments) -and ($command.arguments -isnot [array])) {
                $problems.Add("$($SourceDescription): command '$($commandProperty.Name)' 'arguments' must be a JSON array.")
            }
        }
    }
    return ,$problems.ToArray()
}

function Lamfa-GetProfile {
    <#
    .SYNOPSIS
        Resolves the effective profile for a repository: the repo-owned
        .lamfa.json when present, else a built-in profile matched by name,
        else the built-in default. An INVALID repo profile falls back to the
        default and reports why - it never disables generic functionality.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [Parameter()][AllowEmptyString()][string]$RepositoryName = '',
        [Parameter()][string]$BuiltInDirectory = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'profiles')
    )
    $problems = @()
    $source = 'built-in default'
    $data = $null
    $isRepositoryOwned = $false

    $repoOwned = Join-Path $RepositoryPath '.lamfa.json'
    if (Test-Path -LiteralPath $repoOwned) {
        try { $data = Get-Content -LiteralPath $repoOwned -Raw | ConvertFrom-Json } catch { $data = $null }
        $problems = Lamfa-TestProfile -RepoProfile $data -SourceDescription $repoOwned
        if ($problems.Count -eq 0) { $source = $repoOwned; $isRepositoryOwned = $true }
        else { $data = $null }
    }
    if ($null -eq $data -and $RepositoryName) {
        $builtIn = Join-Path $BuiltInDirectory ("$($RepositoryName.ToLowerInvariant()).json")
        if (Test-Path -LiteralPath $builtIn) {
            try { $data = Get-Content -LiteralPath $builtIn -Raw | ConvertFrom-Json } catch { $data = $null }
            if ($data -and (Lamfa-TestProfile -RepoProfile $data).Count -eq 0) { $source = $builtIn }
            else { $data = $null }
        }
    }
    if ($null -eq $data) {
        $defaultPath = Join-Path $BuiltInDirectory 'default.json'
        if (Test-Path -LiteralPath $defaultPath) {
            $data = Get-Content -LiteralPath $defaultPath -Raw | ConvertFrom-Json
            $source = $defaultPath
        } else {
            $data = [pscustomobject]@{ schemaVersion = 1; commands = [pscustomobject]@{}; workflows = [pscustomobject]@{} }
            $source = 'embedded empty default'
        }
    }
    return [pscustomobject]@{
        PSTypeName        = 'Lamfa.ResolvedProfile'
        Data              = $data
        Source            = $source
        IsRepositoryOwned = $isRepositoryOwned
        ValidationErrors  = $problems
    }
}

function Lamfa-GetProfileHash {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$ProfilePath)
    return (Get-FileHash -LiteralPath $ProfilePath -Algorithm SHA256).Hash
}

function Lamfa-IsProfileTrusted {
    <#
    .SYNOPSIS
        True when this repository's CURRENT profile content hash was explicitly
        trusted before. Any content change invalidates the trust.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$RepositoryId,
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter()][string]$TrustStorePath = (Join-Path (Lamfa-GetConfigDirectory) 'profile-trust.json')
    )
    if (-not (Test-Path -LiteralPath $TrustStorePath)) { return $false }
    $store = Get-Content -LiteralPath $TrustStorePath -Raw | ConvertFrom-Json
    $hash = Lamfa-GetProfileHash -ProfilePath $ProfilePath
    return [bool](@($store) | Where-Object { $_.repositoryId -eq $RepositoryId -and $_.profileHash -eq $hash })
}

function Lamfa-GrantProfileTrust {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryId,
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter()][string]$TrustStorePath = (Join-Path (Lamfa-GetConfigDirectory) 'profile-trust.json')
    )
    $entries = @()
    if (Test-Path -LiteralPath $TrustStorePath) {
        $entries = @(Get-Content -LiteralPath $TrustStorePath -Raw | ConvertFrom-Json)
    }
    $entries = @($entries | Where-Object { $_.repositoryId -ne $RepositoryId })
    $entries += [pscustomobject]@{
        repositoryId = $RepositoryId
        profileHash  = Lamfa-GetProfileHash -ProfilePath $ProfilePath
        grantedUtc   = [DateTime]::UtcNow.ToString('o')
    }
    $directory = Split-Path -Path $TrustStorePath -Parent
    if (-not (Test-Path -Path $directory)) { $null = New-Item -ItemType Directory -Path $directory -Force }
    Set-Content -Path $TrustStorePath -Value (ConvertTo-Json @($entries) -Depth 4) -Encoding utf8
}

Export-ModuleMember -Function Lamfa-TestProfile, Lamfa-GetProfile, Lamfa-GetProfileHash, Lamfa-IsProfileTrusted, Lamfa-GrantProfileTrust

# Registry configuration + login launcher. Login happens in
# a visible console via docker's own credential flow - Lamfa never touches
# the password.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/SecretVault.psm1') -DisableNameChecking

function Get-DockerRegistryTarget {
    <#
    .SYNOPSIS
        Resolves registry/image/tag from a resolved profile into the exact push
        reference: registry/image:tag.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$ResolvedProfile,
        [Parameter()][string]$Tag = 'latest'
    )
    $docker = $ResolvedProfile.Data.PSObject.Properties['docker']
    if (-not $docker -or $null -eq $docker.Value) {
        throw 'ValidationError: the profile defines no docker section. Add registry + image to the repository profile.'
    }
    $registry = [string]$docker.Value.registry
    $image = [string]$docker.Value.image
    if ([string]::IsNullOrWhiteSpace($registry) -or [string]::IsNullOrWhiteSpace($image)) {
        throw 'ValidationError: the profile docker section needs both "registry" and "image" for push operations.'
    }
    return [pscustomobject]@{
        PSTypeName = 'Lamfa.DockerRegistryTarget'
        Registry   = $registry
        Image      = $image
        Tag        = $Tag
        Reference  = "$registry/${image}:$Tag"
    }
}

function Start-DockerRegistryLogin {
    <#
    .SYNOPSIS
        Launches interactive 'docker login <registry>' in a visible console
       . Explicit user action; the credential goes to Docker directly.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Registry)
    Start-Process -FilePath docker -ArgumentList @('login', $Registry) -Wait
}


function Connect-DockerRegistryWithVault {
    <#
    .SYNOPSIS
        Non-interactive registry login: a PSCredential stored in the
        vault under 'Lamfa/registry/<host>' feeds docker login via
        --password-stdin. The password never appears in arguments or logs.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Registry,
        [Parameter()][hashtable]$VaultApi = $null
    )
    $vaultArguments = @{}
    if ($null -ne $VaultApi) { $vaultArguments.VaultApi = $VaultApi }
    $credential = Lamfa-GetSecret -Purpose "registry/$Registry" -AsCredential @vaultArguments
    if ($credential -isnot [pscredential]) {
        throw "ValidationError: the vault entry 'Lamfa/registry/$Registry' must be a PSCredential (user + password)."
    }
    return Invoke-ExternalCommand -Executable docker `
        -Arguments @('login', $Registry, '--username', $credential.UserName, '--password-stdin') `
        -WorkingDirectory ([System.IO.Path]::GetTempPath()) -TimeoutSeconds 120 `
        -StandardInput $credential.GetNetworkCredential().Password
}

Export-ModuleMember -Function Get-DockerRegistryTarget, Start-DockerRegistryLogin, Connect-DockerRegistryWithVault

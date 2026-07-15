# Image build/list/tag/push/pull + digest comparison. Push happens only through the operation engine with an exact
# destination preview.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking

function Build-DockerImage {
    <#
    .SYNOPSIS
        Builds an image with EXPLICIT context, Dockerfile, and tags -
        nothing inferred. Build arguments must not carry secrets.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$ContextPath,
        [Parameter(Mandatory)][string]$Dockerfile,
        [Parameter(Mandatory)][string[]]$Tags,
        [Parameter()][hashtable]$BuildArguments = @{},
        [Parameter()][switch]$NoCache
    )
    $arguments = @('build', '-f', $Dockerfile)
    foreach ($tag in $Tags) { $arguments += @('-t', $tag) }
    foreach ($key in $BuildArguments.Keys) { $arguments += @('--build-arg', "$key=$($BuildArguments[$key])") }
    if ($NoCache) { $arguments += '--no-cache' }
    $arguments += '.'
    return Invoke-ExternalCommand -Executable docker -Arguments $arguments `
        -WorkingDirectory $ContextPath -TimeoutSeconds 7200
}

function Get-DockerImageList {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter()][AllowEmptyString()][string]$Filter = '')
    $arguments = @('images', '--format', 'json')
    if ($Filter) { $arguments += @('--filter', "reference=$Filter") }
    $result = Invoke-ExternalCommand -Executable docker -Arguments $arguments -WorkingDirectory ([System.IO.Path]::GetTempPath()) -TimeoutSeconds 60
    if (-not $result.Succeeded) { throw "ExternalCommandError: docker images failed. $($result.StandardError)" }
    $images = foreach ($line in ($result.StandardOutput -split "`r?`n" | Where-Object { $_ })) {
        $json = $line | ConvertFrom-Json
        [pscustomobject]@{ PSTypeName = 'Lamfa.DockerImage'
            Repository = $json.Repository; Tag = $json.Tag; Id = $json.ID; Size = $json.Size; Created = $json.CreatedSince }
    }
    return @($images)
}

function Add-DockerImageTag {
    <#
    .SYNOPSIS
        Creates the exact registry target tag: source -> registry/name:tag.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$SourceImage,
        [Parameter(Mandatory)][string]$TargetImage
    )
    return Invoke-ExternalCommand -Executable docker -Arguments @('tag', $SourceImage, $TargetImage) `
        -WorkingDirectory ([System.IO.Path]::GetTempPath()) -TimeoutSeconds 60
}

function Push-DockerImage {
    <#
    .SYNOPSIS
        Pushes ONE exact image reference. The operation-engine preview
        must have shown this reference verbatim before this runs.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$ImageReference)
    return Invoke-ExternalCommand -Executable docker -Arguments @('push', $ImageReference) `
        -WorkingDirectory ([System.IO.Path]::GetTempPath()) -TimeoutSeconds 7200
}

function Get-DockerImageDigest {
    <#
    .SYNOPSIS
        Local repo digests for an image - compare against the registry
        after pull/push to prove local == remote.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$ImageReference)
    $result = Invoke-ExternalCommand -Executable docker `
        -Arguments @('image', 'inspect', '--format', '{{json .RepoDigests}}', $ImageReference) `
        -WorkingDirectory ([System.IO.Path]::GetTempPath()) -AllowNonZeroExitCode -TimeoutSeconds 60
    if ($result.ExitCode -ne 0) { return @() }
    return @($result.StandardOutput.Trim() | ConvertFrom-Json)
}

function Invoke-DockerImagePull {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$ImageReference)
    return Invoke-ExternalCommand -Executable docker -Arguments @('pull', $ImageReference) `
        -WorkingDirectory ([System.IO.Path]::GetTempPath()) -TimeoutSeconds 7200
}

Export-ModuleMember -Function Build-DockerImage, Get-DockerImageList, Add-DockerImageTag, Push-DockerImage, Get-DockerImageDigest, Invoke-DockerImagePull

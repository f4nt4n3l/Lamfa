# Release step orchestration.
# Drives the resumable release record: gates -> tag -> publish -> docker.
# Every step checks the state first and NEVER repeats a completed remote action.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Configuration.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/State.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'WorkflowEngine.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'ProfileLoader.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitTags.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Docker/DockerImages.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Docker/DockerRegistry.psm1') -DisableNameChecking

function Lamfa-InvokeReleaseGateCheck {
    <#
    .SYNOPSIS
        Runs the profile's build and test commands as release gates.
        BOTH configured gates must exit 0; a missing command is reported and
        fails the gate - a release must never ship unverified by accident.
    .OUTPUTS
        @{ Passed(bool); Details(string[]) }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [Parameter(Mandatory)][string]$RepositoryId,
        [Parameter(Mandatory)][pscustomobject]$ResolvedProfile,
        [Parameter()][string[]]$GateCommands = @('build', 'test'),
        [Parameter()][string]$TrustStorePath = (Join-Path (Lamfa-GetConfigDirectory) 'profile-trust.json')
    )
    $details = [System.Collections.Generic.List[string]]::new()
    $passed = $true
    foreach ($gate in $GateCommands) {
        if ($null -eq (Lamfa-GetWorkflowCommand -ResolvedProfile $ResolvedProfile -CommandName $gate)) {
            $passed = $false
            $details.Add("Gate '$gate': NOT CONFIGURED in the profile - add it, or release with an explicit reduced gate list.")
            continue
        }
        $result = Lamfa-InvokeWorkflowCommand -RepositoryPath $RepositoryPath -RepositoryId $RepositoryId `
            -ResolvedProfile $ResolvedProfile -CommandName $gate -TrustStorePath $TrustStorePath
        if ($result.ExitCode -eq 0) {
            $details.Add("Gate '$gate': passed.")
        } else {
            $passed = $false
            $details.Add("Gate '$gate': FAILED (exit $($result.ExitCode)). $($result.StandardError)".Trim())
        }
    }
    return [pscustomobject]@{
        PSTypeName = 'Lamfa.ReleaseGateResult'
        Passed     = $passed
        Details    = $details.ToArray()
    }
}

function New-GitHubRelease {
    <#
    .SYNOPSIS
        Creates a GitHub release for an EXISTING tag with explicit notes
        via 'gh release create'. Never a draft-less surprise: the
        caller previews tag + title + notes through the operation flow first.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$Title,
        [Parameter()][AllowEmptyString()][string]$NotesText = '',
        [Parameter()][switch]$Draft
    )
    $arguments = @('release', 'create', $Tag, '--title', $Title, '--notes', $NotesText)
    if ($Draft) { $arguments += '--draft' }
    return Invoke-ExternalCommand -Executable gh -Arguments $arguments `
        -WorkingDirectory $RepositoryPath -TimeoutSeconds 300
}

function Lamfa-InvokeDockerReleaseStep {
    <#
    .SYNOPSIS
        The Docker leg of a release: build the image from the profile,
        tag it with the release version AND the exact registry reference, push.
        Returns the pushed reference; throws on the first failing sub-step so
        the release record keeps the step pending for resume.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [Parameter(Mandatory)][pscustomobject]$ResolvedProfile,
        [Parameter(Mandatory)][string]$Version
    )
    $dockerProperty = $ResolvedProfile.Data.PSObject.Properties['docker']
    if (-not $dockerProperty -or $null -eq $dockerProperty.Value) {
        throw 'ValidationError: the profile has no docker section; the release has no Docker step to run.'
    }
    $docker = $dockerProperty.Value
    $target = Get-DockerRegistryTarget -ResolvedProfile $ResolvedProfile -Tag $Version

    $build = Build-DockerImage -ContextPath $RepositoryPath -Dockerfile ([string]$docker.dockerfile) `
        -Tags @("$($target.Image):$Version")
    if (-not $build.Succeeded) { throw "ExternalCommandError: release image build failed. $($build.StandardError)" }

    $tag = Add-DockerImageTag -SourceImage "$($target.Image):$Version" -TargetImage $target.Reference
    if (-not $tag.Succeeded) { throw "ExternalCommandError: release image tagging failed. $($tag.StandardError)" }

    $push = Push-DockerImage -ImageReference $target.Reference
    if (-not $push.Succeeded) { throw "ExternalCommandError: release image push failed. $($push.StandardError)" }

    return [pscustomobject]@{
        PSTypeName = 'Lamfa.DockerReleaseResult'
        Reference  = $target.Reference
        Digests    = (Get-DockerImageDigest -ImageReference $target.Reference)
    }
}

Export-ModuleMember -Function Lamfa-InvokeReleaseGateCheck, New-GitHubRelease, Lamfa-InvokeDockerReleaseStep

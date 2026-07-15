# Resumable release state. Each repository
# gets one JSON state record so an interrupted release continues without
# repeating completed remote actions. Never contains secrets.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot 'Configuration.psm1') -DisableNameChecking

function Lamfa-GetReleaseStatePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$RepositoryId,
        [Parameter()][string]$StateDirectory = (Join-Path (Lamfa-GetConfigDirectory) 'release-state')
    )
    return Join-Path $StateDirectory "$RepositoryId.json"
}

function Lamfa-GetReleaseState {
    <#
    .SYNOPSIS
        Loads the release state for a repository; $null when no release is open.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$RepositoryId,
        [Parameter()][string]$StateDirectory = (Join-Path (Lamfa-GetConfigDirectory) 'release-state')
    )
    $path = Lamfa-GetReleaseStatePath -RepositoryId $RepositoryId -StateDirectory $StateDirectory
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Lamfa-NewReleaseState {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$RepositoryId,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string[]]$Steps,
        [Parameter()][string]$StateDirectory = (Join-Path (Lamfa-GetConfigDirectory) 'release-state')
    )
    $state = [pscustomobject]@{
        repositoryId = $RepositoryId
        version      = $Version
        startedUtc   = [DateTime]::UtcNow.ToString('o')
        steps        = @($Steps | ForEach-Object {
            [pscustomobject]@{ name = $_; status = 'Pending'; completedUtc = $null; detail = '' } })
    }
    Lamfa-SaveReleaseState -State $state -StateDirectory $StateDirectory
    return $state
}

function Lamfa-SaveReleaseState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$State,
        [Parameter()][string]$StateDirectory = (Join-Path (Lamfa-GetConfigDirectory) 'release-state')
    )
    if (-not (Test-Path -Path $StateDirectory)) { $null = New-Item -ItemType Directory -Path $StateDirectory -Force }
    $path = Lamfa-GetReleaseStatePath -RepositoryId $State.repositoryId -StateDirectory $StateDirectory
    Set-Content -Path $path -Value ($State | ConvertTo-Json -Depth 6) -Encoding utf8
}

function Lamfa-CompleteReleaseStep {
    <#
    .SYNOPSIS
        Marks one step Completed (or Failed) and persists immediately, so a crash
        right after a remote action still knows the action happened.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$State,
        [Parameter(Mandatory)][string]$StepName,
        [Parameter()][ValidateSet('Completed', 'Failed', 'Skipped')][string]$Status = 'Completed',
        [Parameter()][AllowEmptyString()][string]$Detail = '',
        [Parameter()][string]$StateDirectory = (Join-Path (Lamfa-GetConfigDirectory) 'release-state')
    )
    $step = @($State.steps) | Where-Object { $_.name -eq $StepName } | Select-Object -First 1
    if (-not $step) { throw "ValidationError: release state has no step '$StepName'." }
    $step.status = $Status
    $step.completedUtc = [DateTime]::UtcNow.ToString('o')
    $step.detail = $Detail
    Lamfa-SaveReleaseState -State $State -StateDirectory $StateDirectory
}

function Lamfa-IsReleaseStepPending {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][pscustomobject]$State,
        [Parameter(Mandatory)][string]$StepName
    )
    $step = @($State.steps) | Where-Object { $_.name -eq $StepName } | Select-Object -First 1
    if (-not $step) { return $false }
    return ($step.status -eq 'Pending' -or $step.status -eq 'Failed')
}

function Lamfa-RemoveReleaseState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryId,
        [Parameter()][string]$StateDirectory = (Join-Path (Lamfa-GetConfigDirectory) 'release-state')
    )
    $path = Lamfa-GetReleaseStatePath -RepositoryId $RepositoryId -StateDirectory $StateDirectory
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}

Export-ModuleMember -Function Lamfa-GetReleaseStatePath, Lamfa-GetReleaseState, Lamfa-NewReleaseState, Lamfa-SaveReleaseState, Lamfa-CompleteReleaseStep, Lamfa-IsReleaseStepPending, Lamfa-RemoveReleaseState

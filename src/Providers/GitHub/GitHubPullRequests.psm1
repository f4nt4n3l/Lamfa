# Pull request view/create/checks. JSON only.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../../Core/CommandRunner.psm1') -DisableNameChecking

function Get-GitHubPullRequestForBranch {
    <#
    .SYNOPSIS
        PR metadata for the current branch; $null when none exists.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Path)
    $result = Invoke-ExternalCommand -Executable gh `
        -Arguments @('pr', 'view', '--json', 'number,title,state,isDraft,baseRefName,headRefName,url,reviewDecision') `
        -WorkingDirectory $Path -AllowNonZeroExitCode -TimeoutSeconds 60
    if ($result.ExitCode -ne 0) { return $null }
    return ($result.StandardOutput | ConvertFrom-Json)
}

function New-GitHubPullRequest {
    <#
    .SYNOPSIS
        Creates a PR with EXPLICIT base and head - never inferred.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BaseBranch,
        [Parameter(Mandatory)][string]$HeadBranch,
        [Parameter(Mandatory)][string]$Title,
        [Parameter()][AllowEmptyString()][string]$Body = '',
        [Parameter()][switch]$Draft
    )
    $arguments = @('pr', 'create', '--base', $BaseBranch, '--head', $HeadBranch, '--title', $Title, '--body', $Body)
    if ($Draft) { $arguments += '--draft' }
    return Invoke-ExternalCommand -Executable gh -Arguments $arguments -WorkingDirectory $Path -TimeoutSeconds 120
}

function Get-GitHubPullRequestCheckList {
    <#
    .SYNOPSIS
        CI check runs for the current branch's PR: pending, passed,
        failed, cancelled - by name.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][string]$Path)
    $result = Invoke-ExternalCommand -Executable gh `
        -Arguments @('pr', 'checks', '--json', 'name,state,link') `
        -WorkingDirectory $Path -AllowNonZeroExitCode -TimeoutSeconds 60
    if ($result.ExitCode -ne 0 -and [string]::IsNullOrWhiteSpace($result.StandardOutput)) { return @() }
    return @($result.StandardOutput | ConvertFrom-Json)
}

function Open-GitHubPullRequestInBrowser {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $null = Invoke-ExternalCommand -Executable gh -Arguments @('pr', 'view', '--web') -WorkingDirectory $Path -AllowNonZeroExitCode -TimeoutSeconds 30
}


function Invoke-GitHubPullRequestCheckout {
    <#
    .SYNOPSIS
        Checks out a PR's branch locally - the reviewer flow. Refuses
        when the working tree is not clean (git itself would tangle the states).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$Number
    )
    return Invoke-ExternalCommand -Executable gh -Arguments @('pr', 'checkout', "$Number") `
        -WorkingDirectory $Path -TimeoutSeconds 300
}

function Add-GitHubPullRequestComment {
    <#
    .SYNOPSIS
        Adds a comment to the current branch's PR.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Body
    )
    return Invoke-ExternalCommand -Executable gh -Arguments @('pr', 'comment', '--body', $Body) `
        -WorkingDirectory $Path -TimeoutSeconds 120
}

Export-ModuleMember -Function Get-GitHubPullRequestForBranch, New-GitHubPullRequest, Get-GitHubPullRequestCheckList, Open-GitHubPullRequestInBrowser, Invoke-GitHubPullRequestCheckout, Add-GitHubPullRequestComment

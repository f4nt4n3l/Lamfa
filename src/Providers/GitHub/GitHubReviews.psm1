# PR reviews + comments. JSON only.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../../Core/CommandRunner.psm1') -DisableNameChecking

function Get-GitHubPullRequestFeedback {
    <#
    .SYNOPSIS
        Review decision, reviews, and comments for the current branch's PR.
        Returns $null when no PR exists.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Path)
    $result = Invoke-ExternalCommand -Executable gh `
        -Arguments @('pr', 'view', '--json', 'reviewDecision,reviews,comments') `
        -WorkingDirectory $Path -TimeoutSeconds 60
    if ($result.ExitCode -ne 0) { return $null }
    $json = $result.StandardOutput | ConvertFrom-Json
    return [pscustomobject]@{
        PSTypeName     = 'Lamfa.GitHubPullRequestFeedback'
        ReviewDecision = $json.reviewDecision
        Reviews        = @($json.reviews | ForEach-Object {
            [pscustomobject]@{ Author = $_.author.login; State = $_.state; Body = $_.body } })
        Comments       = @($json.comments | ForEach-Object {
            [pscustomobject]@{ Author = $_.author.login; Body = $_.body; CreatedAt = $_.createdAt } })
    }
}

Export-ModuleMember -Function Get-GitHubPullRequestFeedback

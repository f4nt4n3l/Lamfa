# GitLab adapter via the official glab CLI. Follows the
# Pattern: official CLI, JSON output, native credential storage.
# Baseline note (section 43): verified against glab's documented flags; re-check
# 'glab mr view --help' when installing a new glab major version.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../../Core/CommandRunner.psm1') -DisableNameChecking

function Get-GitLabAuthStatus {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    $result = Invoke-ExternalCommand -Executable glab -Arguments @('auth', 'status') `
        -WorkingDirectory ([System.IO.Path]::GetTempPath()) -AllowNonZeroExitCode -TimeoutSeconds 60
    $text = $result.StandardOutput + "`n" + $result.StandardError
    $accounts = [System.Collections.Generic.List[object]]::new()
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match 'Logged in to (\S+) as (\S+)') {
            $accounts.Add([pscustomobject]@{ PSTypeName = 'Lamfa.GitLabAccount'
                HostName = $Matches[1]; Account = $Matches[2]; Active = $true })
        }
    }
    return [pscustomobject]@{
        PSTypeName          = 'Lamfa.GitLabAuthStatus'
        Authenticated       = ($result.ExitCode -eq 0)
        Accounts            = $accounts.ToArray()
        UsesPlaintextTokens = ($text -match 'plain.?text')
        RawSummary          = $text.Trim()
    }
}

function Get-GitLabMergeRequestForBranch {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Path)
    $result = Invoke-ExternalCommand -Executable glab -Arguments @('mr', 'view', '--output', 'json') `
        -WorkingDirectory $Path -AllowNonZeroExitCode -TimeoutSeconds 60
    if ($result.ExitCode -ne 0) { return $null }
    $json = $result.StandardOutput | ConvertFrom-Json
    return [pscustomobject]@{
        Number = $json.iid; Title = $json.title; State = ([string]$json.state).ToUpperInvariant()
        IsDraft = [bool]$json.draft; Base = $json.target_branch; Head = $json.source_branch
        Url = $json.web_url; ReviewDecision = $null
    }
}

function New-GitLabMergeRequest {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BaseBranch,
        [Parameter(Mandatory)][string]$HeadBranch,
        [Parameter(Mandatory)][string]$Title,
        [Parameter()][AllowEmptyString()][string]$Body = ''
    )
    return Invoke-ExternalCommand -Executable glab `
        -Arguments @('mr', 'create', '--source-branch', $HeadBranch, '--target-branch', $BaseBranch,
            '--title', $Title, '--description', $Body, '--yes') `
        -WorkingDirectory $Path -TimeoutSeconds 120
}

function Add-GitLabMergeRequestComment {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Body
    )
    return Invoke-ExternalCommand -Executable glab -Arguments @('mr', 'note', '--message', $Body) `
        -WorkingDirectory $Path -TimeoutSeconds 120
}

function Get-GitLabPipelineStatus {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][string]$Path)
    $result = Invoke-ExternalCommand -Executable glab -Arguments @('ci', 'list', '--output', 'json', '--per-page', '5') `
        -WorkingDirectory $Path -AllowNonZeroExitCode -TimeoutSeconds 60
    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.StandardOutput)) { return @() }
    return @($result.StandardOutput | ConvertFrom-Json | ForEach-Object {
        [pscustomobject]@{ Name = "pipeline #$($_.id) ($($_.ref))"; State = ([string]$_.status).ToUpperInvariant(); Url = $_.web_url }
    })
}

function New-GitLabRelease {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$Title,
        [Parameter()][AllowEmptyString()][string]$Notes = ''
    )
    return Invoke-ExternalCommand -Executable glab `
        -Arguments @('release', 'create', $Tag, '--name', $Title, '--notes', $Notes) `
        -WorkingDirectory $Path -TimeoutSeconds 120
}

function Get-GitLabProviderAdapter {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    return @{
        CliName              = 'glab'
        AuthStatus           = { param($Context) Get-GitLabAuthStatus }
        PullRequestForBranch = { param($Context) Get-GitLabMergeRequestForBranch -Path $Context.Path }
        PullRequestCreate    = { param($Context, $Base, $Head, $Title, $Body)
            New-GitLabMergeRequest -Path $Context.Path -BaseBranch $Base -HeadBranch $Head -Title $Title -Body $Body }
        PullRequestComment   = { param($Context, $Body) Add-GitLabMergeRequestComment -Path $Context.Path -Body $Body }
        PullRequestChecks    = { param($Context) Get-GitLabPipelineStatus -Path $Context.Path }
        ReleaseCreate        = { param($Context, $Tag, $Title, $Notes)
            New-GitLabRelease -Path $Context.Path -Tag $Tag -Title $Title -Notes $Notes }
    }
}

Export-ModuleMember -Function Get-GitLabAuthStatus, Get-GitLabMergeRequestForBranch, New-GitLabMergeRequest, Add-GitLabMergeRequestComment, Get-GitLabPipelineStatus, New-GitLabRelease, Get-GitLabProviderAdapter

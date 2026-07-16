# Gitea/Forgejo adapter via the official tea CLI.
# Self-hosted instances: 'tea login add' once per host; tea then resolves the
# login from the repository remote. Baseline note (section 43): verify tea's
# output flags ('--output json') when installing a new tea version.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../../Core/CommandRunner.psm1') -DisableNameChecking

function Get-GiteaAuthStatus {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    $result = Invoke-ExternalCommand -Executable tea -Arguments @('login', 'list', '--output', 'json') `
        -WorkingDirectory ([System.IO.Path]::GetTempPath()) -TimeoutSeconds 60
    $accounts = @()
    if ($result.ExitCode -eq 0 -and $result.StandardOutput.Trim()) {
        try {
            $accounts = @($result.StandardOutput | ConvertFrom-Json | ForEach-Object {
                [pscustomobject]@{ PSTypeName = 'Lamfa.GiteaAccount'
                    HostName = $_.url; Account = $_.user; Active = [bool]$_.default }
            })
        } catch { $accounts = @() }
    }
    return [pscustomobject]@{
        PSTypeName          = 'Lamfa.GiteaAuthStatus'
        Authenticated       = ($accounts.Count -gt 0)
        Accounts            = $accounts
        UsesPlaintextTokens = $false
        RawSummary          = $result.StandardOutput.Trim()
    }
}

function Get-GiteaPullRequestForBranch {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Branch
    )
    $result = Invoke-ExternalCommand -Executable tea `
        -Arguments @('pr', 'list', '--output', 'json', '--fields', 'index,title,state,base,head,url') `
        -WorkingDirectory $Path -TimeoutSeconds 60
    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.StandardOutput)) { return $null }
    $match = @($result.StandardOutput | ConvertFrom-Json) |
        Where-Object { $_.head -eq $Branch -and ([string]$_.state) -ieq 'open' } | Select-Object -First 1
    if (-not $match) { return $null }
    return [pscustomobject]@{
        Number = $match.index; Title = $match.title; State = ([string]$match.state).ToUpperInvariant()
        IsDraft = $false; Base = $match.base; Head = $match.head; Url = $match.url; ReviewDecision = $null
    }
}

function New-GiteaPullRequest {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BaseBranch,
        [Parameter(Mandatory)][string]$HeadBranch,
        [Parameter(Mandatory)][string]$Title,
        [Parameter()][AllowEmptyString()][string]$Body = ''
    )
    return Invoke-ExternalCommand -Executable tea `
        -Arguments @('pr', 'create', '--base', $BaseBranch, '--head', $HeadBranch, '--title', $Title, '--description', $Body) `
        -WorkingDirectory $Path -TimeoutSeconds 120
}

function Add-GiteaPullRequestComment {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$Number,
        [Parameter(Mandatory)][string]$Body
    )
    return Invoke-ExternalCommand -Executable tea -Arguments @('comment', "$Number", $Body) `
        -WorkingDirectory $Path -TimeoutSeconds 120
}

function New-GiteaRelease {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$Title,
        [Parameter()][AllowEmptyString()][string]$Notes = ''
    )
    return Invoke-ExternalCommand -Executable tea `
        -Arguments @('release', 'create', '--tag', $Tag, '--title', $Title, '--note', $Notes) `
        -WorkingDirectory $Path -TimeoutSeconds 120
}

function Get-GiteaProviderAdapter {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    return @{
        CliName              = 'tea'
        AuthStatus           = { param($Context) Get-GiteaAuthStatus }
        PullRequestForBranch = { param($Context) Get-GiteaPullRequestForBranch -Path $Context.Path -Branch $Context.CurrentBranch }
        PullRequestCreate    = { param($Context, $Base, $Head, $Title, $Body)
            New-GiteaPullRequest -Path $Context.Path -BaseBranch $Base -HeadBranch $Head -Title $Title -Body $Body }
        PullRequestComment   = { param($Context, $Body)
            $pr = Get-GiteaPullRequestForBranch -Path $Context.Path -Branch $Context.CurrentBranch
            if ($null -eq $pr) { throw 'ValidationError: no open pull request for this branch to comment on.' }
            Add-GiteaPullRequestComment -Path $Context.Path -Number $pr.Number -Body $Body }
        PullRequestChecks    = { param($Context) @() }   # Gitea Actions status is not exposed by tea; browser link covers it
        ReleaseCreate        = { param($Context, $Tag, $Title, $Notes)
            New-GiteaRelease -Path $Context.Path -Tag $Tag -Title $Title -Notes $Notes }
    }
}

Export-ModuleMember -Function Get-GiteaAuthStatus, Get-GiteaPullRequestForBranch, New-GiteaPullRequest, Add-GiteaPullRequestComment, New-GiteaRelease, Get-GiteaProviderAdapter

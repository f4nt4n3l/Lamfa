# Bitbucket Cloud adapter via REST API 2.0.
# Bitbucket has no official CLI; credentials (username + app password) come
# EXCLUSIVELY from the secret vault entry 'Lamfa/bitbucket/api' and are
# passed to Invoke-RestMethod as a PSCredential (Basic auth) - never logged,
# never displayed, never stored by Lamfa. HTTP here uses the built-in
# Invoke-RestMethod: this is an in-process web call, not an external command,
# so the command-runner mandate does not apply.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../../Core/SecretVault.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../../Core/Logging.psm1') -DisableNameChecking

$script:ApiBase = 'https://api.bitbucket.org/2.0'

function Get-BitbucketRepositoryTarget {
    <#
    .SYNOPSIS
        Extracts workspace + repository slug from a bitbucket.org remote URL.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$RemoteUrl)
    if ($RemoteUrl -match 'bitbucket\.org[:/]([^/]+)/([^/]+?)(\.git)?/?$') {
        return [pscustomobject]@{ Workspace = $Matches[1]; Slug = $Matches[2] }
    }
    throw "ValidationError: cannot extract workspace/repository from '$RemoteUrl'."
}

function Get-BitbucketCredential {
    [CmdletBinding()]
    [OutputType([pscredential])]
    param([Parameter()][AllowNull()][hashtable]$VaultApi = $null)
    $vaultArguments = @{}
    if ($null -ne $VaultApi) { $vaultArguments.VaultApi = $VaultApi }
    $credential = Lamfa-GetSecret -Purpose 'bitbucket/api' -AsCredential @vaultArguments
    if ($credential -isnot [pscredential]) {
        throw "ValidationError: the vault entry 'Lamfa/bitbucket/api' must be a PSCredential (Bitbucket username + app password)."
    }
    return $credential
}

function Invoke-BitbucketApi {
    # Single HTTP chokepoint - mockable in tests, uniform auth + error text.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$PathAndQuery,
        [Parameter()][AllowNull()][object]$BodyObject = $null,
        [Parameter()][AllowNull()][hashtable]$VaultApi = $null
    )
    $credential = Get-BitbucketCredential -VaultApi $VaultApi
    $parameters = @{
        Method         = $Method
        Uri            = "$script:ApiBase$PathAndQuery"
        Credential     = $credential
        Authentication = 'Basic'
        ContentType    = 'application/json'
        ErrorAction    = 'Stop'
    }
    if ($null -ne $BodyObject) { $parameters.Body = ($BodyObject | ConvertTo-Json -Depth 8) }
    Lamfa-WriteLog -Message 'bitbucket api call' -Data @{ method = $Method; path = $PathAndQuery }
    return Invoke-RestMethod @parameters
}

function Get-BitbucketPullRequestForBranch {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$RemoteUrl,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter()][AllowNull()][hashtable]$VaultApi = $null
    )
    $target = Get-BitbucketRepositoryTarget -RemoteUrl $RemoteUrl
    $query = [uri]::EscapeDataString("source.branch.name = `"$Branch`" AND state = `"OPEN`"")
    $response = Invoke-BitbucketApi -Method GET -VaultApi $VaultApi `
        -PathAndQuery "/repositories/$($target.Workspace)/$($target.Slug)/pullrequests?q=$query"
    $pullRequest = @($response.values) | Select-Object -First 1
    if (-not $pullRequest) { return $null }
    return [pscustomobject]@{
        Number = $pullRequest.id; Title = $pullRequest.title; State = $pullRequest.state
        IsDraft = [bool]$pullRequest.draft; Base = $pullRequest.destination.branch.name
        Head = $pullRequest.source.branch.name; Url = $pullRequest.links.html.href; ReviewDecision = $null
    }
}

function New-BitbucketPullRequest {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$RemoteUrl,
        [Parameter(Mandatory)][string]$BaseBranch,
        [Parameter(Mandatory)][string]$HeadBranch,
        [Parameter(Mandatory)][string]$Title,
        [Parameter()][AllowEmptyString()][string]$Body = '',
        [Parameter()][AllowNull()][hashtable]$VaultApi = $null
    )
    $target = Get-BitbucketRepositoryTarget -RemoteUrl $RemoteUrl
    return Invoke-BitbucketApi -Method POST -VaultApi $VaultApi `
        -PathAndQuery "/repositories/$($target.Workspace)/$($target.Slug)/pullrequests" `
        -BodyObject @{
            title       = $Title
            description = $Body
            source      = @{ branch = @{ name = $HeadBranch } }
            destination = @{ branch = @{ name = $BaseBranch } }
        }
}

function Add-BitbucketPullRequestComment {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$RemoteUrl,
        [Parameter(Mandatory)][int]$Number,
        [Parameter(Mandatory)][string]$Body,
        [Parameter()][AllowNull()][hashtable]$VaultApi = $null
    )
    $target = Get-BitbucketRepositoryTarget -RemoteUrl $RemoteUrl
    return Invoke-BitbucketApi -Method POST -VaultApi $VaultApi `
        -PathAndQuery "/repositories/$($target.Workspace)/$($target.Slug)/pullrequests/$Number/comments" `
        -BodyObject @{ content = @{ raw = $Body } }
}

function Get-BitbucketRemoteUrlFromContext {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][pscustomobject]$Context)
    $remote = @($Context.Remotes) | Where-Object { $_.Name -eq $Context.PreferredRemote } | Select-Object -First 1
    if (-not $remote) { $remote = @($Context.Remotes) | Select-Object -First 1 }
    if (-not $remote) { throw 'ValidationError: the repository has no remote - Bitbucket operations need one.' }
    return $remote.FetchUrl
}

function Get-BitbucketProviderAdapter {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    return @{
        CliName              = $null   # REST-based: availability = vault reachable, checked at call time
        AuthStatus           = { param($Context)
            $vault = Lamfa-TestVaultAvailable
            [pscustomobject]@{ Authenticated = $vault.Available; Accounts = @()
                UsesPlaintextTokens = $false
                RawSummary = if ($vault.Available) { "Credential expected in the vault as 'Lamfa/bitbucket/api'." } else { $vault.Remediation } } }
        PullRequestForBranch = { param($Context)
            Get-BitbucketPullRequestForBranch -RemoteUrl (Get-BitbucketRemoteUrlFromContext -Context $Context) -Branch $Context.CurrentBranch }
        PullRequestCreate    = { param($Context, $Base, $Head, $Title, $Body)
            New-BitbucketPullRequest -RemoteUrl (Get-BitbucketRemoteUrlFromContext -Context $Context) `
                -BaseBranch $Base -HeadBranch $Head -Title $Title -Body $Body }
        PullRequestComment   = { param($Context, $Body)
            $pr = Get-BitbucketPullRequestForBranch -RemoteUrl (Get-BitbucketRemoteUrlFromContext -Context $Context) -Branch $Context.CurrentBranch
            if ($null -eq $pr) { throw 'ValidationError: no open pull request for this branch to comment on.' }
            Add-BitbucketPullRequestComment -RemoteUrl (Get-BitbucketRemoteUrlFromContext -Context $Context) -Number $pr.Number -Body $Body }
        PullRequestChecks    = { param($Context) @() }   # pipelines API deferred; browser link covers it
        ReleaseCreate        = { param($Context, $Tag, $Title, $Notes)
            throw 'ValidationError: Bitbucket Cloud has no release API comparable to GitHub releases; push the tag and document in the repository instead.' }
    }
}

Export-ModuleMember -Function Get-BitbucketRepositoryTarget, Get-BitbucketCredential, Invoke-BitbucketApi, Get-BitbucketPullRequestForBranch, New-BitbucketPullRequest, Add-BitbucketPullRequestComment, Get-BitbucketRemoteUrlFromContext, Get-BitbucketProviderAdapter

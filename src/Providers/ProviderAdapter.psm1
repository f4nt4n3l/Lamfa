# Provider adapter contract + registry + resolution. One neutral surface for GitHub/GitLab/Gitea/Bitbucket; menus never
# talk to a provider CLI directly. Every adapter maps its native output into
# the COMMON pull-request record:
#   @{ Number; Title; State; IsDraft; Base; Head; Url; ReviewDecision }
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot 'GenericRemote.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitHub/GitHubAuth.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitHub/GitHubPullRequests.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitHub/GitHubReviews.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitLab/GitLabAdapter.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'Gitea/GiteaAdapter.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'Bitbucket/BitbucketAdapter.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Workflows/ReleaseOrchestrator.psm1') -DisableNameChecking

$script:Adapters = @{}

function Lamfa-RegisterProviderAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][hashtable]$Adapter
    )
    foreach ($required in @('CliName', 'AuthStatus', 'PullRequestForBranch', 'PullRequestCreate', 'PullRequestComment', 'PullRequestChecks', 'ReleaseCreate')) {
        if (-not $Adapter.ContainsKey($required)) {
            throw "ValidationError: adapter '$Provider' is missing the contract member '$required'."
        }
    }
    $script:Adapters[$Provider] = $Adapter
}

function Lamfa-GetProviderAdapter {
    <#
    .SYNOPSIS
        Resolves the adapter for a repository context: the profile's
        repository.provider wins, else the remote URL decides. Returns the
        adapter plus availability (CLI installed / credentials reachable).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Context,
        [Parameter()][AllowNull()][object]$ResolvedProfile = $null
    )
    $provider = $null
    if ($null -ne $ResolvedProfile) {
        $repositorySection = $ResolvedProfile.Data.PSObject.Properties['repository']
        if ($repositorySection -and $repositorySection.Value) {
            $providerProperty = $repositorySection.Value.PSObject.Properties['provider']
            if ($providerProperty -and $providerProperty.Value) { $provider = [string]$providerProperty.Value }
        }
    }
    if (-not $provider) {
        $remote = @($Context.Remotes) | Where-Object { $_.Name -eq $Context.PreferredRemote } | Select-Object -First 1
        if (-not $remote) { $remote = @($Context.Remotes) | Select-Object -First 1 }
        if ($remote -and $remote.FetchUrl) {
            $provider = (Lamfa-GetProviderFromRemote -RemoteUrl $remote.FetchUrl).Provider
        }
    }
    if (-not $provider) { $provider = 'generic' }

    if (-not $script:Adapters.ContainsKey($provider)) {
        return [pscustomobject]@{
            PSTypeName = 'Lamfa.ResolvedAdapter'; Provider = $provider; Adapter = $null; Available = $false
            Remediation = "No integration exists for '$provider' - Git and the browser link keep working."
        }
    }
    $adapter = $script:Adapters[$provider]
    $available = $true
    $remediation = ''
    if ($adapter.CliName) {
        $cli = Get-Command -Name $adapter.CliName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cli) {
            $available = $false
            $remediation = "The '$($adapter.CliName)' CLI is not installed - Lamfa can install it (guided install)."
        }
    }
    return [pscustomobject]@{
        PSTypeName  = 'Lamfa.ResolvedAdapter'
        Provider    = $provider
        Adapter     = $adapter
        Available   = $available
        Remediation = $remediation
    }
}

function Lamfa-GetRegisteredProviderList {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    return @($script:Adapters.Keys | Sort-Object)
}

# ---- GitHub adapter: the existing gh integration, contract-shaped --
Lamfa-RegisterProviderAdapter -Provider 'github' -Adapter @{
    CliName              = 'gh'
    AuthStatus           = { param($Context) Get-GitHubAuthStatus }
    PullRequestForBranch = {
        param($Context)
        $pr = Get-GitHubPullRequestForBranch -Path $Context.Path
        if ($null -eq $pr) { return $null }
        [pscustomobject]@{ Number = $pr.number; Title = $pr.title; State = $pr.state; IsDraft = [bool]$pr.isDraft
            Base = $pr.baseRefName; Head = $pr.headRefName; Url = $pr.url; ReviewDecision = $pr.reviewDecision }
    }
    PullRequestCreate    = { param($Context, $Base, $Head, $Title, $Body)
        New-GitHubPullRequest -Path $Context.Path -BaseBranch $Base -HeadBranch $Head -Title $Title -Body $Body }
    PullRequestComment   = { param($Context, $Body) Add-GitHubPullRequestComment -Path $Context.Path -Body $Body }
    PullRequestChecks    = { param($Context)
        @(Get-GitHubPullRequestCheckList -Path $Context.Path | ForEach-Object {
            [pscustomobject]@{ Name = $_.name; State = $_.state; Url = $_.link } }) }
    ReleaseCreate        = { param($Context, $Tag, $Title, $Notes)
        New-GitHubRelease -RepositoryPath $Context.Path -Tag $Tag -Title $Title -NotesText $Notes }
}

Lamfa-RegisterProviderAdapter -Provider 'gitlab' -Adapter (Get-GitLabProviderAdapter)
Lamfa-RegisterProviderAdapter -Provider 'gitea' -Adapter (Get-GiteaProviderAdapter)
Lamfa-RegisterProviderAdapter -Provider 'bitbucket' -Adapter (Get-BitbucketProviderAdapter)

Export-ModuleMember -Function Lamfa-RegisterProviderAdapter, Lamfa-GetProviderAdapter, Lamfa-GetRegisteredProviderList

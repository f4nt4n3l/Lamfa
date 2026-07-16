# JSON API facade - the single surface every future
# front-end (web UI, scripts, CI) consumes. JSON/hashtable in, JSON out.
# Version 1 exposes READ + safe-sync operations only; state-changing flows with
# typed confirmations stay in the terminal.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot 'Configuration.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'DependencyCheck.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Repositories/RepositoryRegistry.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitRepository.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitStatus.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitHistory.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitDiff.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitRemotes.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Providers/ProviderAdapter.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Workflows/ProfileLoader.psm1') -DisableNameChecking

function Lamfa-GetApiContext {
    param([string]$ConfigPath)
    $config = Lamfa-GetConfiguration -Path $ConfigPath
    if (-not $config.activeRepositoryId) { throw 'ValidationError: no active repository. Call repos.activate first.' }
    $context = Lamfa-SetActiveRepository -Id $config.activeRepositoryId -ConfigPath $ConfigPath
    return (Lamfa-UpdateRepositoryContext -Context $context)
}

$script:ApiOperations = [ordered]@{
    'version'        = { param($p, $cfg)
        # In the single-file distribution everything shares one scope, so the
        # root module's Lamfa-GetVersion is available; the manifest file is not
        # shipped there. Modular layout falls back to reading the manifest.
        if (Get-Command -Name Lamfa-GetVersion -ErrorAction SilentlyContinue) {
            return @{ version = [string](Lamfa-GetVersion) }
        }
        $manifest = Import-PowerShellDataFile -Path (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Lamfa.psd1')
        @{ version = [string]$manifest.ModuleVersion } }
    'doctor'         = { param($p, $cfg)
        $tools = foreach ($t in @('git', 'gh', 'glab', 'tea', 'docker')) {
            $cmd = Get-Command -Name $t -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            @{ name = $t; installed = [bool]$cmd }
        }
        @{ powershell = $PSVersionTable.PSVersion.ToString(); tools = @($tools) } }
    'repos.list'     = { param($p, $cfg)
        @{ repositories = @(Lamfa-GetRepositoryList -ConfigPath $cfg | ForEach-Object {
            @{ id = $_.id; name = $_.name; path = $_.path } }) } }
    'repos.activate' = { param($p, $cfg)
        if (-not $p.id) { throw 'ValidationError: repos.activate needs parameters.id' }
        $context = Lamfa-SetActiveRepository -Id ([string]$p.id) -ConfigPath $cfg
        @{ active = $context.Name } }
    'status'         = { param($p, $cfg)
        $context = Lamfa-GetApiContext -ConfigPath $cfg
        $status = Get-GitStatus -Path $context.Path
        @{ repository = $context.Name; branch = $status.Branch; upstream = $status.Upstream
           ahead = $status.Ahead; behind = $status.Behind; clean = $status.IsClean
           entries = @($status.Entries | ForEach-Object { @{ kind = $_.Kind; path = $_.Path; index = [string]$_.IndexState; worktree = [string]$_.WorktreeState } }) } }
    'history'        = { param($p, $cfg)
        $context = Lamfa-GetApiContext -ConfigPath $cfg
        $limit = if ($p.limit) { [int]$p.limit } else { 20 }
        @{ commits = @(Get-GitHistory -Path $context.Path -Limit $limit | ForEach-Object {
            @{ hash = $_.Hash; author = $_.Author; date = $_.Date; subject = $_.Subject } }) } }
    'diff'           = { param($p, $cfg)
        $context = Lamfa-GetApiContext -ConfigPath $cfg
        $scope = if ($p.scope) { [string]$p.scope } else { 'Unstaged' }
        @{ scope = $scope; text = (Get-GitDiff -Path $context.Path -Scope $scope) } }
    'fetch'          = { param($p, $cfg)
        $context = Lamfa-GetApiContext -ConfigPath $cfg
        $result = Invoke-GitFetch -Path $context.Path
        @{ succeeded = $result.Succeeded; detail = $result.StandardError.Trim() } }
    'push.preview'   = { param($p, $cfg)
        $context = Lamfa-GetApiContext -ConfigPath $cfg
        $preview = Get-GitPushPreview -Path $context.Path
        @{ branch = $preview.Branch; remote = $preview.RemoteName; url = $preview.RemoteUrl
           target = $preview.TargetBranch; commits = $preview.CommitCount; createsUpstream = $preview.CreatesUpstream } }
    'pr.view'        = { param($p, $cfg)
        $context = Lamfa-GetApiContext -ConfigPath $cfg
        $resolvedProfile = Lamfa-GetProfile -RepositoryPath $context.Path -RepositoryName $context.Name
        $resolved = Lamfa-GetProviderAdapter -Context $context -ResolvedProfile $resolvedProfile
        if ($null -eq $resolved.Adapter -or -not $resolved.Available) {
            return @{ provider = $resolved.Provider; available = $false; detail = $resolved.Remediation }
        }
        $pr = & $resolved.Adapter.PullRequestForBranch $context
        if ($null -eq $pr) { return @{ provider = $resolved.Provider; available = $true; pullRequest = $null } }
        @{ provider = $resolved.Provider; available = $true
           pullRequest = @{ number = $pr.Number; title = $pr.Title; state = $pr.State; base = $pr.Base; head = $pr.Head; url = $pr.Url } } }
    'operations'     = { param($p, $cfg) @{ operations = @($script:ApiOperations.Keys) } }
}

function Lamfa-Api {
    <#
    .SYNOPSIS
        The JSON facade. Request: JSON string or hashtable with
        { operation, parameters? }. Response: JSON { ok, result | error, type }.
        Never throws - errors come back structured.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)][object]$Request,
        [Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath)
    )
    try {
        if ($Request -is [string]) { $Request = $Request | ConvertFrom-Json -AsHashtable }
        $operation = [string]$Request.operation
        if (-not $script:ApiOperations.Contains($operation)) {
            return (@{ ok = $false; type = 'ValidationError'
                error = "Unknown operation '$operation'. Call 'operations' for the list." } | ConvertTo-Json -Compress -Depth 8)
        }
        $parameters = if ($Request.ContainsKey('parameters') -and $Request.parameters) { $Request.parameters } else { @{} }
        $result = & $script:ApiOperations[$operation] $parameters $ConfigPath
        return (@{ ok = $true; result = $result } | ConvertTo-Json -Compress -Depth 10)
    } catch {
        $type = 'UnexpectedError'
        if ($_.Exception.Message -match '^(\w+Error):') { $type = $Matches[1] }
        return (@{ ok = $false; type = $type; error = $_.Exception.Message } | ConvertTo-Json -Compress -Depth 4)
    }
}

Export-ModuleMember -Function Lamfa-Api, Lamfa-GetApiContext

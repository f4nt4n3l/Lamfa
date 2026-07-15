# Git repository metadata + operation-state detection + context refresh.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Platform.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Models/DependencyStatus.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Models/RepositoryContext.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitStatus.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitBranches.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitRemotes.psm1') -DisableNameChecking

function Get-GitDependencyStatus {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    $command = Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        return New-DependencyStatus -Name Git -Executable git -Installed $false -Required $true `
            -Message 'Git is not installed or not on PATH. Install Git for Windows: https://gitforwindows.org/'
    }
    $result = Invoke-ExternalCommand -Executable git -Arguments @('--version') -WorkingDirectory ([System.IO.Path]::GetTempPath())
    $version = if ($result.Succeeded) { ($result.StandardOutput.Trim() -replace '^git version\s*', '') } else { $null }
    return New-DependencyStatus -Name Git -Executable git -Installed $true -Version $version `
        -Supported $true -Required $true -Capabilities @('porcelain-v2', 'worktree')
}

function Get-GitOperationState {
    <#
    .SYNOPSIS
        Detects in-progress Git operations from the state files inside
        the git directory: merge, rebase, cherry-pick, revert, detached HEAD.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Path)

    $gitDirResult = Invoke-ExternalCommand -Executable git -Arguments @('rev-parse', '--git-dir') -WorkingDirectory $Path
    $gitDir = $null
    if ($gitDirResult.Succeeded) {
        $gitDir = $gitDirResult.StandardOutput.Trim()
        if (-not [System.IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $Path $gitDir }
    }
    $detached = $false
    $headResult = Invoke-ExternalCommand -Executable git -Arguments @('symbolic-ref', '-q', 'HEAD') -WorkingDirectory $Path -AllowNonZeroExitCode
    if ($headResult.ExitCode -ne 0) { $detached = $true }

    return [pscustomobject]@{
        PSTypeName           = 'Lamfa.GitOperationState'
        MergeInProgress      = ($null -ne $gitDir -and (Test-Path (Join-Path $gitDir 'MERGE_HEAD')))
        RebaseInProgress     = ($null -ne $gitDir -and ((Test-Path (Join-Path $gitDir 'rebase-merge')) -or (Test-Path (Join-Path $gitDir 'rebase-apply'))))
        CherryPickInProgress = ($null -ne $gitDir -and (Test-Path (Join-Path $gitDir 'CHERRY_PICK_HEAD')))
        RevertInProgress     = ($null -ne $gitDir -and (Test-Path (Join-Path $gitDir 'REVERT_HEAD')))
        IsDetachedHead       = $detached
    }
}

function Lamfa-UpdateRepositoryContext {
    <#
    .SYNOPSIS
        Refreshes a RepositoryContext with live Git data: branch, HEAD,
        remotes, upstream, working-tree state, ahead/behind, operation state.
        Non-Git folders come back unchanged apart from IsGitRepository=false.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][pscustomobject]$Context)

    $probe = Invoke-ExternalCommand -Executable git -Arguments @('rev-parse', '--git-dir') -WorkingDirectory $Context.Path
    if (-not $probe.Succeeded) {
        return New-RepositoryContext -Id $Context.Id -Name $Context.Name -Path $Context.Path `
            -PreferredRemote $Context.PreferredRemote -RepositoryProfile $Context.Profile -Provider $Context.Provider
    }
    $gitDir = $probe.StandardOutput.Trim()
    if (-not [System.IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $Context.Path $gitDir }

    $head = Invoke-ExternalCommand -Executable git -Arguments @('rev-parse', '--short', 'HEAD') -WorkingDirectory $Context.Path -AllowNonZeroExitCode
    $headCommit = if ($head.ExitCode -eq 0) { $head.StandardOutput.Trim() } else { $null }

    $status = Get-GitStatus -Path $Context.Path
    $state = Get-GitOperationState -Path $Context.Path
    $remotes = Get-GitRemoteList -Path $Context.Path
    $defaultBranch = Get-GitDefaultBranch -Path $Context.Path -RemoteName $Context.PreferredRemote

    $treeState = 'Clean'
    if ($status.HasConflicts) { $treeState = 'Conflicted' }
    elseif ($status.Entries.Count -gt 0) { $treeState = 'Dirty' }

    return New-RepositoryContext -Id $Context.Id -Name $Context.Name -Path $Context.Path `
        -IsGitRepository $true -GitDirectory $gitDir `
        -CurrentBranch $status.Branch -IsDetachedHead $state.IsDetachedHead -HeadCommit $headCommit `
        -Remotes $remotes -PreferredRemote $Context.PreferredRemote `
        -UpstreamBranch $status.Upstream -DefaultBranch $defaultBranch `
        -IntegrationBranch $Context.IntegrationBranch `
        -WorkingTreeState $treeState -AheadCount $status.Ahead -BehindCount $status.Behind `
        -MergeInProgress $state.MergeInProgress -RebaseInProgress $state.RebaseInProgress `
        -CherryPickInProgress $state.CherryPickInProgress -RevertInProgress $state.RevertInProgress `
        -RepositoryProfile $Context.Profile -Provider $Context.Provider
}

function Get-GitIdentity {
    <#
    .SYNOPSIS
        Local, global, and effective Git identity plus credential helpers
       . Warns about the plaintext 'store' helper.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Path)

    function ReadConfig([string[]]$ExtraArguments) {
        $result = Invoke-ExternalCommand -Executable git -Arguments (@('config') + $ExtraArguments) -WorkingDirectory $Path -AllowNonZeroExitCode
        if ($result.ExitCode -eq 0) { return $result.StandardOutput.Trim() }
        return $null
    }
    $helpers = Invoke-ExternalCommand -Executable git -Arguments @('config', '--get-all', 'credential.helper') -WorkingDirectory $Path -AllowNonZeroExitCode
    $helperList = @()
    if ($helpers.ExitCode -eq 0) { $helperList = @($helpers.StandardOutput.Trim() -split "`r?`n" | Where-Object { $_ }) }

    return [pscustomobject]@{
        PSTypeName          = 'Lamfa.GitIdentity'
        LocalName           = ReadConfig @('--local', 'user.name')
        LocalEmail          = ReadConfig @('--local', 'user.email')
        GlobalName          = ReadConfig @('--global', 'user.name')
        GlobalEmail         = ReadConfig @('--global', 'user.email')
        EffectiveName       = ReadConfig @('user.name')
        EffectiveEmail      = ReadConfig @('user.email')
        CredentialHelpers   = $helperList
        UsesPlaintextStore  = [bool]($helperList | Where-Object { $_ -match '^store' })
    }
}

function Set-GitLocalIdentity {
    <#
    .SYNOPSIS
        Sets user.name/user.email for ONE repository only. Lamfa
        never changes the global identity outside Advanced Mode UI flows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][string]$Email
    )
    foreach ($pair in @(@('user.name', $UserName), @('user.email', $Email))) {
        $result = Invoke-ExternalCommand -Executable git -Arguments @('config', '--local', $pair[0], $pair[1]) -WorkingDirectory $Path
        if (-not $result.Succeeded) { throw "ExternalCommandError: git config failed. $($result.StandardError)" }
    }
}


function Lamfa-GetEnvironmentReport {
    <#
    .SYNOPSIS
        SSH / Git LFS / submodule readiness for a repository - the
        three silent killers of beginner clones. Read-only.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Path)

    $sshDirectory = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.ssh'
    $publicKeys = @()
    if (Test-Path -LiteralPath $sshDirectory) {
        $publicKeys = @(Get-ChildItem -LiteralPath $sshDirectory -Filter '*.pub' -ErrorAction SilentlyContinue | ForEach-Object Name)
    }
    $agentRunning = Lamfa-IsSshAgentRunning

    $lfsInstalled = $null -ne (Get-Command -Name 'git-lfs' -CommandType Application -ErrorAction SilentlyContinue)
    $lfsRequired = $false
    $attributes = Join-Path $Path '.gitattributes'
    if (Test-Path -LiteralPath $attributes) {
        $lfsRequired = [bool]((Get-Content -LiteralPath $attributes -Raw) -match 'filter=lfs')
    }

    $hasSubmodules = Test-Path -LiteralPath (Join-Path $Path '.gitmodules')
    $uninitializedSubmodules = @()
    if ($hasSubmodules) {
        $status = Invoke-ExternalCommand -Executable git -Arguments @('submodule', 'status') -WorkingDirectory $Path -AllowNonZeroExitCode
        # a leading '-' marks a submodule that was never initialized
        $uninitializedSubmodules = @($status.StandardOutput -split "`r?`n" | Where-Object { $_ -match '^-' } |
            ForEach-Object { ($_ -split '\s+')[1] })
    }

    return [pscustomobject]@{
        PSTypeName              = 'Lamfa.EnvironmentReport'
        SshPublicKeys           = $publicKeys
        SshAgentRunning         = $agentRunning
        LfsInstalled            = $lfsInstalled
        LfsRequired             = $lfsRequired
        LfsProblem              = ($lfsRequired -and -not $lfsInstalled)
        HasSubmodules           = $hasSubmodules
        UninitializedSubmodules = $uninitializedSubmodules
    }
}

Export-ModuleMember -Function Get-GitDependencyStatus, Get-GitOperationState, Lamfa-UpdateRepositoryContext, Get-GitIdentity, Set-GitLocalIdentity, Lamfa-GetEnvironmentReport

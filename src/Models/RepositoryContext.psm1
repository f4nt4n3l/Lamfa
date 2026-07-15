# RepositoryContext - the runtime snapshot of the active repository.
# Git-derived fields stay null/false until the read-only Git services populate them; the model is the contract.
Set-StrictMode -Version 3.0

function New-RepositoryContext {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][bool]$IsGitRepository = $false,
        [Parameter()][AllowNull()][string]$GitDirectory = $null,
        [Parameter()][AllowNull()][string]$CurrentBranch = $null,
        [Parameter()][bool]$IsDetachedHead = $false,
        [Parameter()][AllowNull()][string]$HeadCommit = $null,
        [Parameter()][object[]]$Remotes = @(),
        [Parameter()][AllowNull()][string]$PreferredRemote = $null,
        [Parameter()][AllowNull()][string]$UpstreamBranch = $null,
        [Parameter()][AllowNull()][string]$DefaultBranch = $null,
        [Parameter()][AllowNull()][string]$IntegrationBranch = $null,
        [Parameter()][ValidateSet('Unknown', 'Clean', 'Dirty', 'Conflicted')][string]$WorkingTreeState = 'Unknown',
        [Parameter()][Nullable[int]]$AheadCount = $null,
        [Parameter()][Nullable[int]]$BehindCount = $null,
        [Parameter()][bool]$MergeInProgress = $false,
        [Parameter()][bool]$RebaseInProgress = $false,
        [Parameter()][bool]$CherryPickInProgress = $false,
        [Parameter()][bool]$RevertInProgress = $false,
        [Parameter()][AllowNull()][object]$RepositoryProfile = $null,
        [Parameter()][AllowNull()][string]$Provider = $null
    )
    return [pscustomobject]@{
        PSTypeName           = 'Lamfa.RepositoryContext'
        Id                   = $Id
        Name                 = $Name
        Path                 = $Path
        IsGitRepository      = $IsGitRepository
        GitDirectory         = $GitDirectory
        CurrentBranch        = $CurrentBranch
        IsDetachedHead       = $IsDetachedHead
        HeadCommit           = $HeadCommit
        Remotes              = $Remotes
        PreferredRemote      = $PreferredRemote
        UpstreamBranch       = $UpstreamBranch
        DefaultBranch        = $DefaultBranch
        IntegrationBranch    = $IntegrationBranch
        WorkingTreeState     = $WorkingTreeState
        AheadCount           = $AheadCount
        BehindCount          = $BehindCount
        MergeInProgress      = $MergeInProgress
        RebaseInProgress     = $RebaseInProgress
        CherryPickInProgress = $CherryPickInProgress
        RevertInProgress     = $RevertInProgress
        Profile              = $RepositoryProfile
        Provider             = $Provider
    }
}

Export-ModuleMember -Function New-RepositoryContext

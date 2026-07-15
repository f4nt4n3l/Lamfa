# Remote queries + fetch/pull/push.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitStatus.psm1') -DisableNameChecking

function Get-GitRemoteList {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][string]$Path)
    $result = Invoke-ExternalCommand -Executable git -Arguments @('remote', '-v') -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: $($result.StandardError)" }
    $remotes = @{}
    foreach ($line in ($result.StandardOutput -split "`r?`n" | Where-Object { $_ })) {
        if ($line -match '^(\S+)\s+(\S+)\s+\((fetch|push)\)$') {
            if (-not $remotes.ContainsKey($Matches[1])) {
                $remotes[$Matches[1]] = [pscustomobject]@{
                    PSTypeName = 'Lamfa.GitRemote'; Name = $Matches[1]; FetchUrl = $null; PushUrl = $null
                }
            }
            if ($Matches[3] -eq 'fetch') { $remotes[$Matches[1]].FetchUrl = $Matches[2] }
            else { $remotes[$Matches[1]].PushUrl = $Matches[2] }
        }
    }
    return @($remotes.Values | Sort-Object Name)
}

function Invoke-GitFetch {
    <#
    .SYNOPSIS
        Fetches one remote with pruning. Read-only for local files.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][string]$RemoteName = 'origin'
    )
    return Invoke-ExternalCommand -Executable git -Arguments @('fetch', '--prune', $RemoteName) `
        -WorkingDirectory $Path -TimeoutSeconds 600
}

function Invoke-GitPull {
    <#
    .SYNOPSIS
        Safe pull: fetch first, then fast-forward only.
        Diverged history is never merged or rebased automatically - the result
        explains the state and the safe options instead.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][string]$RemoteName = 'origin'
    )
    $fetch = Invoke-GitFetch -Path $Path -RemoteName $RemoteName
    if (-not $fetch.Succeeded) {
        return [pscustomobject]@{ PSTypeName = 'Lamfa.GitPullResult'; Outcome = 'FetchFailed'; Detail = $fetch.StandardError }
    }
    $status = Get-GitStatus -Path $Path
    if ($null -eq $status.Upstream) {
        return [pscustomobject]@{ PSTypeName = 'Lamfa.GitPullResult'; Outcome = 'NoUpstream'
            Detail = 'The current branch has no upstream. Publish the branch first so Lamfa knows where to pull from.' }
    }
    if ($status.Behind -eq 0) {
        return [pscustomobject]@{ PSTypeName = 'Lamfa.GitPullResult'; Outcome = 'UpToDate'; Detail = 'Nothing to pull.' }
    }
    if ($status.Ahead -gt 0) {
        return [pscustomobject]@{ PSTypeName = 'Lamfa.GitPullResult'; Outcome = 'Diverged'
            Detail = "Local branch is $($status.Ahead) ahead and $($status.Behind) behind '$($status.Upstream)'. Lamfa does not merge or rebase automatically - review both sides first." }
    }
    $merge = Invoke-ExternalCommand -Executable git -Arguments @('merge', '--ff-only', $status.Upstream) -WorkingDirectory $Path
    if ($merge.Succeeded) {
        return [pscustomobject]@{ PSTypeName = 'Lamfa.GitPullResult'; Outcome = 'FastForwarded'
            Detail = "Fast-forwarded $($status.Behind) commit(s) from '$($status.Upstream)'." }
    }
    return [pscustomobject]@{ PSTypeName = 'Lamfa.GitPullResult'; Outcome = 'Failed'; Detail = $merge.StandardError }
}

function Get-GitPushPreview {
    <#
    .SYNOPSIS
        The exact-target preview shown before every push.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][string]$RemoteName = 'origin'
    )
    $status = Get-GitStatus -Path $Path
    $remote = @(Get-GitRemoteList -Path $Path) | Where-Object Name -eq $RemoteName | Select-Object -First 1
    $willPublish = ($null -eq $status.Upstream)
    $commitCount = 0
    if (-not $willPublish -and $null -ne $status.Ahead) { $commitCount = $status.Ahead }
    elseif ($willPublish -and $status.Branch) {
        $count = Invoke-ExternalCommand -Executable git -Arguments @('rev-list', '--count', 'HEAD') -WorkingDirectory $Path -AllowNonZeroExitCode
        if ($count.ExitCode -eq 0) { $commitCount = [int]$count.StandardOutput.Trim() }
    }
    return [pscustomobject]@{
        PSTypeName        = 'Lamfa.GitPushPreview'
        Branch            = $status.Branch
        RemoteName        = $RemoteName
        RemoteUrl         = if ($remote) { $remote.PushUrl } else { $null }
        TargetBranch      = if ($status.Upstream) { $status.Upstream } else { "$RemoteName/$($status.Branch) (new)" }
        CommitCount       = $commitCount
        CreatesUpstream   = $willPublish
    }
}

function Invoke-GitPush {
    <#
    .SYNOPSIS
        Pushes the current branch; publishes with -u when no upstream
        exists yet. NEVER force-pushes - there is deliberately no force parameter.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][string]$RemoteName = 'origin'
    )
    $status = Get-GitStatus -Path $Path
    if (-not $status.Branch) { throw 'PreconditionError: detached HEAD - there is no branch to push.' }
    $arguments = if ($null -eq $status.Upstream) { @('push', '-u', $RemoteName, $status.Branch) }
    else { @('push', $RemoteName) }
    return Invoke-ExternalCommand -Executable git -Arguments $arguments -WorkingDirectory $Path -TimeoutSeconds 600
}


function Test-GitProtectedBranchPush {
    <#
    .SYNOPSIS
        True when a push from the given branch targets a default/integration
        class branch directly - the UI then requires a typed
        confirmation, because that push lands without review.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Branch,
        [Parameter()][AllowNull()][AllowEmptyString()][string]$DefaultBranch = $null,
        [Parameter()][AllowNull()][AllowEmptyString()][string]$IntegrationBranch = $null
    )
    if ([string]::IsNullOrWhiteSpace($Branch)) { return $false }
    foreach ($protected in @($DefaultBranch, $IntegrationBranch, 'main', 'master', 'develop')) {
        if (-not [string]::IsNullOrWhiteSpace($protected) -and $Branch -ieq $protected) { return $true }
    }
    return $false
}

Export-ModuleMember -Function Get-GitRemoteList, Invoke-GitFetch, Invoke-GitPull, Get-GitPushPreview, Invoke-GitPush, Test-GitProtectedBranchPush

# Branch queries + safe branch changes.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitStatus.psm1') -DisableNameChecking

function Get-GitBranchList {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][switch]$IncludeRemote
    )
    $refs = @('refs/heads')
    if ($IncludeRemote) { $refs += 'refs/remotes' }
    $result = Invoke-ExternalCommand -Executable git -Arguments (@('for-each-ref',
            '--format=%(refname:short)|%(objectname:short)|%(upstream:short)|%(HEAD)') + $refs) -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: git for-each-ref failed. $($result.StandardError)" }
    $branches = foreach ($line in ($result.StandardOutput -split "`r?`n" | Where-Object { $_ })) {
        $parts = $line.Split('|')
        [pscustomobject]@{
            PSTypeName = 'Lamfa.GitBranch'
            Name       = $parts[0]
            Commit     = $parts[1]
            Upstream   = if ($parts[2]) { $parts[2] } else { $null }
            IsCurrent  = ($parts[3] -eq '*')
            IsRemote   = $parts[0].Contains('/') -and -not (Test-Path (Join-Path $Path ".git/refs/heads/$($parts[0])"))
        }
    }
    return @($branches)
}

function Get-GitCurrentBranch {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)
    $result = Invoke-ExternalCommand -Executable git -Arguments @('branch', '--show-current') -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: $($result.StandardError)" }
    $name = $result.StandardOutput.Trim()
    if ($name) { return $name }
    return $null   # detached HEAD
}

function Get-GitDefaultBranch {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][AllowNull()][AllowEmptyString()][string]$RemoteName = 'origin'
    )
    if ([string]::IsNullOrWhiteSpace($RemoteName)) { $RemoteName = 'origin' }
    $result = Invoke-ExternalCommand -Executable git `
        -Arguments @('symbolic-ref', '-q', "refs/remotes/$RemoteName/HEAD") -WorkingDirectory $Path -AllowNonZeroExitCode
    if ($result.ExitCode -eq 0 -and $result.StandardOutput.Trim()) {
        return $result.StandardOutput.Trim() -replace "^refs/remotes/$RemoteName/", ''
    }
    # Fallback: a local main/master branch.
    foreach ($candidate in @('main', 'master')) {
        $probe = Invoke-ExternalCommand -Executable git -Arguments @('rev-parse', '-q', '--verify', "refs/heads/$candidate") `
            -WorkingDirectory $Path -AllowNonZeroExitCode
        if ($probe.ExitCode -eq 0) { return $candidate }
    }
    return $null
}

function Compare-GitBranch {
    <#
    .SYNOPSIS
        Ahead/behind between two branches via rev-list --count.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$Against
    )
    $result = Invoke-ExternalCommand -Executable git `
        -Arguments @('rev-list', '--left-right', '--count', "$Against...$Branch") -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: $($result.StandardError)" }
    $counts = $result.StandardOutput.Trim() -split '\s+'
    return [pscustomobject]@{
        PSTypeName = 'Lamfa.GitBranchComparison'
        Branch     = $Branch
        Against    = $Against
        Ahead      = [int]$counts[1]   # commits only on Branch
        Behind     = [int]$counts[0]   # commits only on Against
    }
}

function New-GitBranch {
    <#
    .SYNOPSIS
        Creates a branch from an explicit source ref; optionally
        switches to it. The source is never implicit HEAD unless stated.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][string]$SourceRef = 'HEAD',
        [Parameter()][switch]$Switch
    )
    $check = Invoke-ExternalCommand -Executable git -Arguments @('check-ref-format', '--branch', $Name) `
        -WorkingDirectory $Path -AllowNonZeroExitCode
    if ($check.ExitCode -ne 0) { throw "ValidationError: '$Name' is not a valid branch name." }
    $arguments = if ($Switch) { @('switch', '-c', $Name, $SourceRef) } else { @('branch', $Name, $SourceRef) }
    $result = Invoke-ExternalCommand -Executable git -Arguments $arguments -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: branch creation failed. $($result.StandardError)" }
}

function Switch-GitBranch {
    <#
    .SYNOPSIS
        Switches branches only when the working state is safe: clean
        tree, or explicitly acknowledged carry-over of local edits.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][switch]$AllowDirtyCarryOver
    )
    $status = Get-GitStatus -Path $Path
    if ($status.HasConflicts) {
        throw 'PreconditionError: conflicts are unresolved; resolve or abort the current operation before switching.'
    }
    if (-not $status.IsClean -and -not $AllowDirtyCarryOver) {
        throw 'PreconditionError: the working tree has local changes. Commit or stash them first, or explicitly allow carrying them over.'
    }
    $result = Invoke-ExternalCommand -Executable git -Arguments @('switch', $Name) -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: switch failed. $($result.StandardError)" }
}

function Remove-MergedGitBranch {
    <#
    .SYNOPSIS
        Deletes a LOCAL branch only after verifying it is fully merged into the
        integration ref. Uses -d (never -D): git re-verifies the merge.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$IntegrationRef
    )
    if ((Get-GitCurrentBranch -Path $Path) -eq $Name) {
        throw 'PreconditionError: cannot delete the branch you are standing on. Switch first.'
    }
    $comparison = Compare-GitBranch -Path $Path -Branch $Name -Against $IntegrationRef
    if ($comparison.Ahead -gt 0) {
        throw "PreconditionError: '$Name' has $($comparison.Ahead) commit(s) not in '$IntegrationRef' - it is not fully merged."
    }
    $result = Invoke-ExternalCommand -Executable git -Arguments @('branch', '-d', $Name) -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: branch delete failed. $($result.StandardError)" }
}


function Rename-GitBranch {
    <#
    .SYNOPSIS
        Renames a LOCAL branch. The remote branch (if published) keeps
        its old name until the renamed branch is pushed - the caller is told.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$NewName
    )
    $check = Invoke-ExternalCommand -Executable git -Arguments @('check-ref-format', '--branch', $NewName) `
        -WorkingDirectory $Path -AllowNonZeroExitCode
    if ($check.ExitCode -ne 0) { throw "ValidationError: '$NewName' is not a valid branch name." }
    $result = Invoke-ExternalCommand -Executable git -Arguments @('branch', '-m', $Name, $NewName) -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: rename failed. $($result.StandardError)" }
}

function Get-GitUnmergedBranchList {
    <#
    .SYNOPSIS
        Local branches NOT fully merged into the given ref - the ones
        that still carry unique work.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$IntegrationRef
    )
    $result = Invoke-ExternalCommand -Executable git `
        -Arguments @('branch', '--format=%(refname:short)', '--no-merged', $IntegrationRef) -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: $($result.StandardError)" }
    return @($result.StandardOutput -split "`r?`n" | Where-Object { $_ })
}


function Get-GitMergedBranchReport {
    <#
    .SYNOPSIS
        Local branches fully merged into the integration ref, with their last
        commit date - cleanup candidates. Never includes the current
        branch or the integration ref itself.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$IntegrationRef,
        [Parameter()][int]$OlderThanDays = 0
    )
    $result = Invoke-ExternalCommand -Executable git `
        -Arguments @('branch', '--format=%(refname:short)|%(committerdate:iso-strict)', '--merged', $IntegrationRef) `
        -WorkingDirectory $Path
    if (-not $result.Succeeded) { throw "ExternalCommandError: $($result.StandardError)" }
    $current = Get-GitCurrentBranch -Path $Path
    $cutoff = [DateTime]::UtcNow.AddDays(-$OlderThanDays)
    $report = foreach ($line in ($result.StandardOutput -split "`r?`n" | Where-Object { $_ })) {
        $parts = $line.Split('|')
        $name = $parts[0]
        if ($name -eq $current -or $name -eq ($IntegrationRef -replace '^origin/', '')) { continue }
        $lastCommit = [DateTimeOffset]::Parse($parts[1]).UtcDateTime
        if ($OlderThanDays -gt 0 -and $lastCommit -gt $cutoff) { continue }
        [pscustomobject]@{ PSTypeName = 'Lamfa.MergedBranch'; Name = $name; LastCommitUtc = $lastCommit }
    }
    return @($report)
}

Export-ModuleMember -Function Get-GitBranchList, Get-GitCurrentBranch, Get-GitDefaultBranch, Compare-GitBranch, New-GitBranch, Switch-GitBranch, Remove-MergedGitBranch, Rename-GitBranch, Get-GitUnmergedBranchList, Get-GitMergedBranchReport

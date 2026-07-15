# The "Oops" button - reflog-based, WORK-PRESERVING undo. Lamfa's
# flagship safety feature: before any undo a backup branch pins the current
# HEAD, then the branch pointer moves SOFTLY (changes come back staged).
# Nothing is ever discarded; the backup branch makes even the undo undoable.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitRepository.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitStatus.psm1') -DisableNameChecking

function Get-GitReflogList {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][ValidateRange(1, 100)][int]$Limit = 10
    )
    $result = Invoke-ExternalCommand -Executable git `
        -Arguments @('reflog', "--max-count=$Limit", '--format=%h%x1f%gd%x1f%gs') -WorkingDirectory $Path -AllowNonZeroExitCode
    if ($result.ExitCode -ne 0) { return @() }
    $entries = foreach ($line in ($result.StandardOutput -split "`r?`n" | Where-Object { $_ })) {
        $parts = $line -split "`u{1f}"
        [pscustomobject]@{ PSTypeName = 'Lamfa.GitReflogEntry'
            Commit = $parts[0]; Ref = $parts[1]; Subject = $parts[2] }
    }
    return @($entries)
}

function Get-GitUndoPlan {
    <#
    .SYNOPSIS
        Inspects the last recorded action and, when Lamfa knows a SAFE undo,
        returns the plan (what happened, what undo will do, target). $null when
        there is nothing Lamfa can undo safely.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Path)

    $state = Get-GitOperationState -Path $Path
    if ($state.MergeInProgress -or $state.RebaseInProgress -or $state.CherryPickInProgress -or $state.RevertInProgress) {
        return $null   # in-progress operations have their own recovery guidance
    }
    $reflog = @(Get-GitReflogList -Path $Path -Limit 2)
    if ($reflog.Count -lt 2) { return $null }
    $last = $reflog[0]
    if ($last.Subject -match '^commit( \(amend\))?:') {
        $status = Get-GitStatus -Path $Path
        $pushedWarning = ''
        if ($null -ne $status.Ahead -and $status.Ahead -eq 0 -and $status.Upstream) {
            $pushedWarning = "The commit was already PUSHED to '$($status.Upstream)' - undoing locally makes your branch diverge; prefer a new fixing commit."
        }
        return [pscustomobject]@{
            PSTypeName   = 'Lamfa.GitUndoPlan'
            Kind         = 'LastCommit'
            WhatHappened = $last.Subject
            WhatUndoDoes = 'Moves the branch pointer one commit back SOFTLY: every change of that commit comes back as staged files. Nothing is deleted, and a backup branch pins the current state first.'
            Target       = $reflog[1].Commit
            Warning      = $pushedWarning
        }
    }
    return $null
}

function Invoke-GitUndoLastCommit {
    <#
    .SYNOPSIS
        Executes the LastCommit undo plan: backup branch at HEAD, then
        'git reset --soft HEAD~1'. Returns the backup branch name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)
    $plan = Get-GitUndoPlan -Path $Path
    if ($null -eq $plan -or $plan.Kind -ne 'LastCommit') {
        throw 'PreconditionError: the last recorded action is not an undoable commit. Use the recovery guidance instead.'
    }
    $stampResult = Invoke-ExternalCommand -Executable git -Arguments @('rev-parse', '--short', 'HEAD') -WorkingDirectory $Path
    $backup = "lamfa-backup/$($stampResult.StandardOutput.Trim())"
    $branch = Invoke-ExternalCommand -Executable git -Arguments @('branch', '-f', $backup, 'HEAD') -WorkingDirectory $Path
    if (-not $branch.Succeeded) { throw "ExternalCommandError: could not create the backup branch. Undo refused. $($branch.StandardError)" }
    # Soft reset: history moves, index keeps the commit's changes, worktree untouched.
    $reset = Invoke-ExternalCommand -Executable git -Arguments @('reset', '--soft', 'HEAD~1') -WorkingDirectory $Path
    if (-not $reset.Succeeded) { throw "ExternalCommandError: undo failed; your work is safe on '$backup'. $($reset.StandardError)" }
    return $backup
}

function Invoke-GitSquashHistory {
    <#
    .SYNOPSIS
        Guided squash of the last N commits into one (Advanced Mode
        only in the UI): backup branch, soft reset N back, one new commit.
        No rebase machinery, no conflicts possible, fully work-preserving.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateRange(2, 50)][int]$Count,
        [Parameter(Mandatory)][string]$Title,
        [Parameter()][AllowEmptyString()][string]$Body = ''
    )
    $countCheck = Invoke-ExternalCommand -Executable git -Arguments @('rev-list', '--count', 'HEAD') -WorkingDirectory $Path
    if (-not $countCheck.Succeeded -or [int]$countCheck.StandardOutput.Trim() -le $Count) {
        throw "PreconditionError: the branch does not have more than $Count commits to squash."
    }
    $status = Get-GitStatus -Path $Path
    if (-not $status.IsClean) { throw 'PreconditionError: commit or stash your local changes before squashing history.' }
    $stampResult = Invoke-ExternalCommand -Executable git -Arguments @('rev-parse', '--short', 'HEAD') -WorkingDirectory $Path
    $backup = "lamfa-backup/$($stampResult.StandardOutput.Trim())"
    $null = Invoke-ExternalCommand -Executable git -Arguments @('branch', '-f', $backup, 'HEAD') -WorkingDirectory $Path
    $reset = Invoke-ExternalCommand -Executable git -Arguments @('reset', '--soft', "HEAD~$Count") -WorkingDirectory $Path
    if (-not $reset.Succeeded) { throw "ExternalCommandError: squash failed; your work is safe on '$backup'. $($reset.StandardError)" }
    $arguments = @('commit', '-m', $Title)
    if ($Body) { $arguments += @('-m', $Body) }
    $commit = Invoke-ExternalCommand -Executable git -Arguments $arguments -WorkingDirectory $Path
    if (-not $commit.Succeeded) { throw "ExternalCommandError: the squash commit failed; everything is staged and '$backup' has the original history. $($commit.StandardError)" }
    return $backup
}

Export-ModuleMember -Function Get-GitReflogList, Get-GitUndoPlan, Invoke-GitUndoLastCommit, Invoke-GitSquashHistory

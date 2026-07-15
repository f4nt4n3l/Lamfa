# Guided, NON-destructive recovery explanations.
# Every suggestion preserves work; data-discarding commands are never suggested
# in Beginner Mode.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot 'GitRepository.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitStatus.psm1') -DisableNameChecking

function Get-GitRecoveryGuidance {
    <#
    .SYNOPSIS
        Detects the current interrupted/abnormal state and returns guidance
        records: State, WhatHappened, WorkPreserved, Steps.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][string]$Path)

    $state = Get-GitOperationState -Path $Path
    $status = Get-GitStatus -Path $Path
    $guidance = [System.Collections.Generic.List[object]]::new()

    if ($state.MergeInProgress) {
        $guidance.Add([pscustomobject]@{ PSTypeName = 'Lamfa.RecoveryGuidance'; State = 'MergeInProgress'
            WhatHappened = 'A merge stopped because both sides changed the same lines.'
            WorkPreserved = $true
            Steps = @('Open each conflicted file and keep the correct content.',
                      'Stage the resolved files, then commit to finish the merge.',
                      "To go back to the state before the merge started: 'git merge --abort' keeps all your committed work.") })
    }
    if ($state.RebaseInProgress) {
        $guidance.Add([pscustomobject]@{ PSTypeName = 'Lamfa.RecoveryGuidance'; State = 'RebaseInProgress'
            WhatHappened = 'A rebase stopped mid-way (usually on a conflict).'
            WorkPreserved = $true
            Steps = @('Resolve the conflicted files and stage them, then continue the rebase.',
                      "To cancel entirely and return to the pre-rebase state: 'git rebase --abort'. Nothing committed is lost.") })
    }
    if ($state.CherryPickInProgress) {
        $guidance.Add([pscustomobject]@{ PSTypeName = 'Lamfa.RecoveryGuidance'; State = 'CherryPickInProgress'
            WhatHappened = 'A cherry-pick stopped on a conflict.'
            WorkPreserved = $true
            Steps = @('Resolve and stage the files, then continue the cherry-pick.',
                      "To cancel: 'git cherry-pick --abort' restores the previous state.") })
    }
    if ($state.RevertInProgress) {
        $guidance.Add([pscustomobject]@{ PSTypeName = 'Lamfa.RecoveryGuidance'; State = 'RevertInProgress'
            WhatHappened = 'A revert stopped on a conflict.'
            WorkPreserved = $true
            Steps = @('Resolve and stage the files, then continue the revert.',
                      "To cancel: 'git revert --abort'.") })
    }
    if ($state.IsDetachedHead) {
        $guidance.Add([pscustomobject]@{ PSTypeName = 'Lamfa.RecoveryGuidance'; State = 'DetachedHead'
            WhatHappened = 'HEAD points at a commit instead of a branch; new commits here are easy to lose.'
            WorkPreserved = $true
            Steps = @('If you made commits you want to keep: create a branch right here first.',
                      'Then switch back to a normal branch.') })
    }
    if ($null -ne $status.Ahead -and $null -ne $status.Behind -and $status.Ahead -gt 0 -and $status.Behind -gt 0) {
        $guidance.Add([pscustomobject]@{ PSTypeName = 'Lamfa.RecoveryGuidance'; State = 'Diverged'
            WhatHappened = "Your branch and '$($status.Upstream)' each have commits the other lacks."
            WorkPreserved = $true
            Steps = @('Inspect both sides (history view) before integrating.',
                      'A merge keeps both histories; ask a teammate if unsure.',
                      'Lamfa never merges or rebases diverged branches automatically.') })
    }
    if ($null -eq $status.Upstream -and $status.Branch) {
        $guidance.Add([pscustomobject]@{ PSTypeName = 'Lamfa.RecoveryGuidance'; State = 'NoUpstream'
            WhatHappened = "Branch '$($status.Branch)' has no upstream; pull and push have no defined target."
            WorkPreserved = $true
            Steps = @('Publish the branch (push with upstream creation) to link it to the remote.') })
    }
    return $guidance.ToArray()
}

Export-ModuleMember -Function Get-GitRecoveryGuidance

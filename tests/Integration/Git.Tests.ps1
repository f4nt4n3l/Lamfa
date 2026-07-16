# Read-only Git + safe-change integration tests over real
# disposable fixtures - status parser states, branches, remotes, history,
# stash, worktrees, operation state, pull/push against a local bare remote.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    foreach ($m in @('Git/GitStatus', 'Git/GitBranches', 'Git/GitRemotes', 'Git/GitCommits',
                     'Git/GitDiff', 'Git/GitHistory', 'Git/GitStash', 'Git/GitTags',
                     'Git/GitWorktrees', 'Git/GitRepository', 'Git/GitRecovery',
                     'Models/RepositoryContext')) {
        Import-Module (Join-Path $repoRoot "src/$m.psm1") -Force -DisableNameChecking
    }
    . (Join-Path $repoRoot 'tools/New-TestRepository.ps1')
    $script:fixtures = [System.Collections.Generic.List[object]]::new()
    function New-Fx([string]$State) {
        $fx = New-TestRepository -State $State
        $script:fixtures.Add($fx)
        return $fx
    }
}
AfterAll {
    foreach ($fx in $script:fixtures) { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Status parser' {
    It 'parses <state>' -ForEach @(
        @{ state = 'Clean';      kind = $null;         clean = $true }
        @{ state = 'Modified';   kind = 'Changed';     clean = $false }
        @{ state = 'Staged';     kind = 'Changed';     clean = $false }
        @{ state = 'Untracked';  kind = 'Untracked';   clean = $false }
        @{ state = 'Renamed';    kind = 'Renamed';     clean = $false }
        @{ state = 'Conflicted'; kind = 'Conflicted';  clean = $false }
    ) {
        $fx = New-Fx $state
        $status = Get-GitStatus -Path $fx.Path
        $status.IsClean | Should -Be $clean
        if ($kind) { @($status.Entries | Where-Object Kind -eq $kind).Count | Should -BeGreaterThan 0 }
        if ($state -eq 'Conflicted') { $status.HasConflicts | Should -BeTrue }
        if ($state -eq 'Renamed') {
            $entry = @($status.Entries | Where-Object Kind -eq 'Renamed')[0]
            $entry.Path | Should -Be 'renamed readme.txt'   # space-containing path intact
            $entry.OriginalPath | Should -Be 'readme.txt'
        }
    }

    It 'reports ahead/behind after fetch' {
        $fx = New-Fx 'AheadBehind'
        $status = Get-GitStatus -Path $fx.Path
        $status.Ahead | Should -Be 1
        $status.Behind | Should -Be 1
    }
}

Describe 'Operation state + recovery' {
    It 'detects a merge in progress and offers non-destructive guidance' {
        $fx = New-Fx 'Conflicted'
        (Get-GitOperationState -Path $fx.Path).MergeInProgress | Should -BeTrue
        $guidance = Get-GitRecoveryGuidance -Path $fx.Path
        @($guidance | Where-Object State -eq 'MergeInProgress').Count | Should -Be 1
        ($guidance | Where-Object State -eq 'MergeInProgress').WorkPreserved | Should -BeTrue
    }
    It 'detects detached HEAD' {
        $fx = New-Fx 'Detached'
        (Get-GitOperationState -Path $fx.Path).IsDetachedHead | Should -BeTrue
    }
}

Describe 'Branches' {
    It 'creates, lists, switches, compares, and safely deletes a merged branch' {
        $fx = New-Fx 'Clean'
        New-GitBranch -Path $fx.Path -Name 'feature/demo' -SourceRef main
        @(Get-GitBranchList -Path $fx.Path).Name | Should -Contain 'feature/demo'
        Switch-GitBranch -Path $fx.Path -Name 'feature/demo'
        Get-GitCurrentBranch -Path $fx.Path | Should -Be 'feature/demo'
        (Compare-GitBranch -Path $fx.Path -Branch 'feature/demo' -Against main).Ahead | Should -Be 0
        Switch-GitBranch -Path $fx.Path -Name main
        Remove-MergedGitBranch -Path $fx.Path -Name 'feature/demo' -IntegrationRef main
        @(Get-GitBranchList -Path $fx.Path).Name | Should -Not -Contain 'feature/demo'
    }
    It 'refuses to switch with a dirty tree and to delete an unmerged branch' {
        $fx = New-Fx 'Clean'
        New-GitBranch -Path $fx.Path -Name 'wip' -SourceRef main -Switch
        Set-Content -Path (Join-Path $fx.Path 'wip.txt') -Value 'x'
        Add-GitStagedFile -Path $fx.Path -Files @('wip.txt')
        New-GitCommit -Path $fx.Path -Title 'wip commit' | Out-Null
        Switch-GitBranch -Path $fx.Path -Name main
        { Remove-MergedGitBranch -Path $fx.Path -Name 'wip' -IntegrationRef main } | Should -Throw '*not fully merged*'
        Set-Content -Path (Join-Path $fx.Path 'readme.txt') -Value 'dirty now'
        { Switch-GitBranch -Path $fx.Path -Name 'wip' } | Should -Throw '*Commit or stash*'
    }
}

Describe 'Selective staging + commit' {
    It 'stages ONLY selected files, warns on secrets, commits' {
        $fx = New-Fx 'Clean'
        Set-Content -Path (Join-Path $fx.Path 'a.txt') -Value 'file a'
        Set-Content -Path (Join-Path $fx.Path 'b.txt') -Value 'file b'
        Set-Content -Path (Join-Path $fx.Path 'leak.txt') -Value 'token ghp_abcdefghij1234567890KLMNOP'
        Add-GitStagedFile -Path $fx.Path -Files @('a.txt')
        $status = Get-GitStatus -Path $fx.Path
        @($status.Entries | Where-Object { $_.IndexState -eq 'A' }).Path | Should -Be @('a.txt')
        $concerns = Test-GitPreCommitConcern -Path $fx.Path -Files @('a.txt', 'leak.txt')
        @($concerns | Where-Object Kind -eq 'LikelySecret').File | Should -Contain 'leak.txt'
        Remove-GitStagedFile -Path $fx.Path -Files @('a.txt')
        (Get-GitStatus -Path $fx.Path).HasStaged | Should -BeFalse
        Add-GitStagedFile -Path $fx.Path -Files @('b.txt')
        New-GitCommit -Path $fx.Path -Title 'add b' -Body 'body line' | Out-Null
        (Get-GitHistory -Path $fx.Path -Limit 1)[0].Subject | Should -Be 'add b'
        { New-GitCommit -Path $fx.Path -Title 'empty' } | Should -Throw '*nothing is staged*'
    }
}

Describe 'Stash' {
    It 'creates a named stash and applies it back' {
        $fx = New-Fx 'Modified'
        Add-GitStash -Path $fx.Path -Message 'my work in progress'
        (Get-GitStatus -Path $fx.Path).IsClean | Should -BeTrue
        @(Get-GitStashList -Path $fx.Path).Count | Should -Be 1
        (Use-GitStash -Path $fx.Path -Mode Pop).Outcome | Should -Be 'Applied'
        (Get-GitStatus -Path $fx.Path).IsClean | Should -BeFalse
        @(Get-GitStashList -Path $fx.Path).Count | Should -Be 0
    }
}

Describe 'Remotes, pull, push' {
    It 'lists remotes and previews the exact push target' {
        $fx = New-Fx 'WithRemote'
        $remotes = Get-GitRemoteList -Path $fx.Path
        @($remotes).Name | Should -Contain 'origin'
        $preview = Get-GitPushPreview -Path $fx.Path
        $preview.Branch | Should -Be 'main'
        $preview.CreatesUpstream | Should -BeFalse
    }
    It 'fast-forward pulls when behind, refuses diverged automatically' {
        $fx = New-Fx 'AheadBehind'
        (Invoke-GitPull -Path $fx.Path).Outcome | Should -Be 'Diverged'
    }
    It 'pushes new commits to the bare remote' {
        $fx = New-Fx 'WithRemote'
        Set-Content -Path (Join-Path $fx.Path 'new.txt') -Value 'push me'
        Add-GitStagedFile -Path $fx.Path -Files @('new.txt')
        New-GitCommit -Path $fx.Path -Title 'to push' | Out-Null
        (Get-GitPushPreview -Path $fx.Path).CommitCount | Should -Be 1
        (Invoke-GitPush -Path $fx.Path).Succeeded | Should -BeTrue
        (Get-GitStatus -Path $fx.Path).Ahead | Should -Be 0
    }
}

Describe 'Tags + worktrees + history + diff' {
    It 'creates and lists an annotated tag, refusing overwrite' {
        $fx = New-Fx 'Clean'
        New-GitTag -Path $fx.Path -Name 'v0.1.0' -Message 'first tag'
        @(Get-GitTagList -Path $fx.Path).Name | Should -Contain 'v0.1.0'
        { New-GitTag -Path $fx.Path -Name 'v0.1.0' -Message 'again' } | Should -Throw '*already exists*'
    }
    It 'adds and removes a worktree' {
        $fx = New-Fx 'Clean'
        $wt = Join-Path $fx.Root 'wt one'
        Add-GitWorktree -Path $fx.Path -Destination $wt -Branch 'wt-branch' -NewBranch
        @(Get-GitWorktreeList -Path $fx.Path).Count | Should -Be 2
        Remove-GitWorktree -Path $fx.Path -WorktreePath $wt
        @(Get-GitWorktreeList -Path $fx.Path).Count | Should -Be 1
    }
    It 'returns history records and diff text' {
        $fx = New-Fx 'Modified'
        @(Get-GitHistory -Path $fx.Path -Limit 5).Count | Should -Be 1
        (Get-GitDiff -Path $fx.Path -Scope Unstaged) | Should -Match 'changed content'
        (Get-GitDiff -Path $fx.Path -Scope Unstaged -NameOnly).Trim() | Should -Be 'readme.txt'
    }
}

Describe 'Context refresh + identity' {
    It 'populates the full repository context from live git data' {
        $fx = New-Fx 'AheadBehind'
        $context = New-RepositoryContext -Id fx -Name Fixture -Path $fx.Path -PreferredRemote origin
        $context = Lamfa-UpdateRepositoryContext -Context $context
        $context.IsGitRepository | Should -BeTrue
        $context.CurrentBranch | Should -Be 'main'
        $context.AheadCount | Should -Be 1
        $context.BehindCount | Should -Be 1
        $context.WorkingTreeState | Should -Be 'Clean'
    }
    It 'reads and sets repository-local identity without touching global' {
        $fx = New-Fx 'Clean'
        Set-GitLocalIdentity -Path $fx.Path -UserName 'Local Person' -Email 'local@example.test'
        $identity = Get-GitIdentity -Path $fx.Path
        $identity.LocalName | Should -Be 'Local Person'
        $identity.EffectiveEmail | Should -Be 'local@example.test'
    }
}

Describe 'Plan parity' {
    It 'renames a local branch' {
        $fx = New-Fx 'Clean'
        New-GitBranch -Path $fx.Path -Name 'old-name' -SourceRef main
        Rename-GitBranch -Path $fx.Path -Name 'old-name' -NewName 'new-name'
        $branches = @(Get-GitBranchList -Path $fx.Path).Name
        $branches | Should -Contain 'new-name'
        $branches | Should -Not -Contain 'old-name'
        { Rename-GitBranch -Path $fx.Path -Name 'new-name' -NewName 'bad..name' } | Should -Throw '*not a valid*'
    }
    It 'lists unmerged branches only' {
        $fx = New-Fx 'Clean'
        New-GitBranch -Path $fx.Path -Name 'merged-one' -SourceRef main
        New-GitBranch -Path $fx.Path -Name 'ahead-one' -SourceRef main -Switch
        Set-Content -Path (Join-Path $fx.Path 'extra.txt') -Value 'x'
        Add-GitStagedFile -Path $fx.Path -Files @('extra.txt')
        $null = New-GitCommit -Path $fx.Path -Title 'extra work'
        Switch-GitBranch -Path $fx.Path -Name main
        $unmerged = Get-GitUnmergedBranchList -Path $fx.Path -IntegrationRef main
        $unmerged | Should -Contain 'ahead-one'
        $unmerged | Should -Not -Contain 'merged-one'
    }
    It 'includes ignored files only when requested' {
        $fx = New-Fx 'Clean'
        Set-Content -Path (Join-Path $fx.Path '.gitignore') -Value 'ignored.tmp'
        Add-GitStagedFile -Path $fx.Path -Files @('.gitignore')
        $null = New-GitCommit -Path $fx.Path -Title 'add gitignore'
        Set-Content -Path (Join-Path $fx.Path 'ignored.tmp') -Value 'x'
        @((Get-GitStatus -Path $fx.Path).Entries | Where-Object Kind -eq 'Ignored').Count | Should -Be 0
        @((Get-GitStatus -Path $fx.Path -IncludeIgnored).Entries | Where-Object Kind -eq 'Ignored').Path | Should -Contain 'ignored.tmp'
    }
}

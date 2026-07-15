# Console UX + safety quick wins.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repoRoot 'src/UI/ConsoleRenderer.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Git/GitRemotes.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Git/GitBranches.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Git/GitCommits.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Git/GitRepository.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Workflows/WorkflowEngine.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Repositories/RepositoryRegistry.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Models/RepositoryContext.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Git/GitRepository.psm1') -Force
    . (Join-Path $repoRoot 'tools/New-TestRepository.ps1')
    $script:sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("lamfa-p13-" + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path $script:sandbox
}
AfterAll {
    Remove-Item -Path $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Menu selector plain fallback' {
    BeforeAll {
        $script:items = @(
            [pscustomobject]@{ Key = '1'; Label = 'First';  Help = 'first help' }
            [pscustomobject]@{ Key = 'A'; Label = 'Second'; Help = 'second help' }
        )
    }
    It 'selects by hotkey (case-insensitive)' {
        $selected = Lamfa-SelectMenuChoice -Items $script:items -ForcePlain -Reader { param($p) 'a' }
        $selected.Label | Should -Be 'Second'
    }
    It 'returns null for back (0 or empty)' {
        Lamfa-SelectMenuChoice -Items $script:items -ForcePlain -Reader { param($p) '0' } | Should -BeNullOrEmpty
        Lamfa-SelectMenuChoice -Items $script:items -ForcePlain -Reader { param($p) '' } | Should -BeNullOrEmpty
    }
    It 're-prompts on unknown input until valid' {
        $script:calls = 0
        $selected = Lamfa-SelectMenuChoice -Items $script:items -ForcePlain -Reader {
            param($p)
            $script:calls++
            if ($script:calls -lt 3) { 'zz' } else { '1' }
        }
        $selected.Label | Should -Be 'First'
        $script:calls | Should -Be 3
    }
}

Describe 'Protected-branch push policy' {
    It 'flags <branch> as protected=<expected>' -ForEach @(
        @{ branch = 'main';          expected = $true }
        @{ branch = 'develop';       expected = $true }
        @{ branch = 'MASTER';        expected = $true }
        @{ branch = 'feature/x';     expected = $false }
        @{ branch = 'release';       expected = $false }
    ) {
        Test-GitProtectedBranchPush -Branch $branch | Should -Be $expected
    }
    It 'honors profile-defined integration branches' {
        Test-GitProtectedBranchPush -Branch 'trunk' -IntegrationBranch 'trunk' | Should -BeTrue
        Test-GitProtectedBranchPush -Branch 'trunk' | Should -BeFalse
        Test-GitProtectedBranchPush -Branch $null | Should -BeFalse
    }
}

Describe 'Auto-fetch freshness' {
    It 'fetches once, stamps lastFetchUtc, then skips inside the window' {
        $fx = New-TestRepository -State WithRemote
        try {
            $cfg = Join-Path $fx.Root 'config.json'
            $registration = Lamfa-AddRepository -Path $fx.Path -Name 'fresh' -ConfigPath $cfg
            $context = Lamfa-SetActiveRepository -Id $registration.id -ConfigPath $cfg
            Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'src/Git/GitRepository.psm1') -Force
            $context = Lamfa-UpdateRepositoryContext -Context $context
            (Lamfa-UpdateFetchFreshness -Context $context -ConfigPath $cfg) | Should -BeTrue
            $saved = (Lamfa-GetRepositoryList -ConfigPath $cfg)[0]
            $saved.lastFetchUtc | Should -Not -BeNullOrEmpty
            (Lamfa-UpdateFetchFreshness -Context $context -ConfigPath $cfg) | Should -BeFalse
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'does nothing without remotes' {
        $context = New-RepositoryContext -Id x -Name N -Path $script:sandbox -IsGitRepository $true
        Lamfa-UpdateFetchFreshness -Context $context -ConfigPath (Join-Path $script:sandbox 'c.json') | Should -BeFalse
    }
}

Describe 'Merged-branch cleanup report' {
    It 'lists merged branches with dates, excluding current and integration' {
        $fx = New-TestRepository -State Clean
        try {
            New-GitBranch -Path $fx.Path -Name 'was-merged' -SourceRef main
            $report = @(Get-GitMergedBranchReport -Path $fx.Path -IntegrationRef main)
            $report.Name | Should -Contain 'was-merged'
            $report.Name | Should -Not -Contain 'main'
            @(Get-GitMergedBranchReport -Path $fx.Path -IntegrationRef main -OlderThanDays 30).Count | Should -Be 0
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Commit-title conventions' {
    BeforeAll {
        $script:conventionProfile = [pscustomobject]@{
            Data = [pscustomobject]@{
                schemaVersion = 1
                commit = [pscustomobject]@{ titlePattern = '^(Fix|Add|Update|Remove):'; hint = 'Start with Fix:/Add:/Update:/Remove:' }
            }
            Source = 't'; IsRepositoryOwned = $false
        }
    }
    It 'accepts matching titles and rejects others with the hint' {
        (Lamfa-TestCommitTitle -ResolvedProfile $script:conventionProfile -Title 'Fix: login').Valid | Should -BeTrue
        $bad = Lamfa-TestCommitTitle -ResolvedProfile $script:conventionProfile -Title 'login fixed'
        $bad.Valid | Should -BeFalse
        $bad.Hint | Should -Match 'Fix:'
    }
    It 'treats a profile without conventions as always valid' {
        $plain = [pscustomobject]@{ Data = [pscustomobject]@{ schemaVersion = 1 }; Source = 't'; IsRepositoryOwned = $false }
        (Lamfa-TestCommitTitle -ResolvedProfile $plain -Title 'anything').Valid | Should -BeTrue
    }
}

Describe 'Environment report' {
    It 'detects LFS requirement from .gitattributes and submodule presence' {
        $fx = New-TestRepository -State Clean
        try {
            $report = Lamfa-GetEnvironmentReport -Path $fx.Path
            $report.LfsRequired | Should -BeFalse
            $report.HasSubmodules | Should -BeFalse
            Set-Content -Path (Join-Path $fx.Path '.gitattributes') -Value '*.bin filter=lfs diff=lfs merge=lfs'
            (Lamfa-GetEnvironmentReport -Path $fx.Path).LfsRequired | Should -BeTrue
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Registry export/import' {
    It 'round-trips registrations, skipping duplicates and missing folders' {
        $cfgA = Join-Path $script:sandbox 'a.json'
        $cfgB = Join-Path $script:sandbox 'b.json'
        $repo = Join-Path $script:sandbox 'exported repo'
        $null = New-Item -ItemType Directory -Path $repo
        $null = Lamfa-AddRepository -Path $repo -Name 'exported repo' -ConfigPath $cfgA
        $export = Join-Path $script:sandbox 'registry-export.json'
        Lamfa-ExportRegistry -Destination $export -ConfigPath $cfgA
        (Get-Content $export -Raw) | Should -Not -Match 'password|token'

        $result = Lamfa-ImportRegistry -Source $export -ConfigPath $cfgB
        $result.Added | Should -Be 1
        @(Lamfa-GetRepositoryList -ConfigPath $cfgB).Count | Should -Be 1
        # importing again: duplicate skipped
        $again = Lamfa-ImportRegistry -Source $export -ConfigPath $cfgB
        $again.Added | Should -Be 0
        @($again.Skipped).Count | Should -BeGreaterThan 0
    }
}

Describe 'Main menu items' {
    It 'uses single-character hotkeys only (single-key navigation safe)' {
        Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'src/UI/MainMenu.psm1') -Force
        $items = Lamfa-GetMainMenuItemList
        @($items).Count | Should -Be 11
        foreach ($item in $items) {
            ([string]$item.Key).Length | Should -Be 1
            $item.Help | Should -Not -BeNullOrEmpty
        }
    }
}

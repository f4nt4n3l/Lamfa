# Non-interactive UI checks: menus load, recommended-action
# rules, glossary/help completeness. Interactive flows are covered by the
# manual acceptance pass.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repoRoot 'src/Models/RepositoryContext.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/UI/Help.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/UI/MainMenu.psm1') -Force
}

Describe 'Recommended next action' {
    It 'suggests registering when no repository is active' {
        Lamfa-GetRecommendedAction -Context $null | Should -Match 'Repositories'
    }
    It 'suggests committing when the tree is dirty' {
        $context = New-RepositoryContext -Id x -Name D -Path 'C:\x' -IsGitRepository $true -WorkingTreeState Dirty
        Lamfa-GetRecommendedAction -Context $context | Should -Match 'Commit'
    }
    It 'suggests pushing when ahead' {
        $context = New-RepositoryContext -Id x -Name D -Path 'C:\x' -IsGitRepository $true -WorkingTreeState Clean -AheadCount 2 -BehindCount 0
        Lamfa-GetRecommendedAction -Context $context | Should -Match 'unpushed'
    }
    It 'suggests recovery during a merge' {
        $context = New-RepositoryContext -Id x -Name D -Path 'C:\x' -IsGitRepository $true -MergeInProgress $true
        Lamfa-GetRecommendedAction -Context $context | Should -Match 'recovery'
    }
    It 'suggests branching when everything is in sync' {
        $context = New-RepositoryContext -Id x -Name D -Path 'C:\x' -IsGitRepository $true -WorkingTreeState Clean -AheadCount 0 -BehindCount 0
        Lamfa-GetRecommendedAction -Context $context | Should -Match 'branch'
    }
}

Describe 'Help + glossary' {
    It 'defines every mandatory glossary term' {
        $glossary = Lamfa-GetGlossary
        foreach ($term in @('Repository', 'Working tree', 'Commit', 'Branch', 'Remote', 'Upstream branch',
                'Fetch', 'Pull', 'Push', 'Pull request', 'Merge', 'Rebase',
                'Docker image', 'Docker container', 'Docker registry', 'Docker context')) {
            $glossary.Keys | Should -Contain $term
        }
    }
    It 'returns topic text and the topic index' {
        Lamfa-GetHelpTopic -Topic 'safety' | Should -Match 'Beginner Mode'
        Lamfa-GetHelpTopic | Should -Match 'first-steps'
    }
}

Describe 'Menu modules load with all commands resolvable' {
    It 'exports the complete menu surface' {
        foreach ($function in @('Lamfa-StartMainMenu', 'Lamfa-ShowDashboard', 'Lamfa-InvokeFirstRunWizard')) {
            Get-Command -Name $function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'lamfa CLI dispatcher' {
    BeforeAll {
        Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'src/UI/LamfaCli.psm1') -Force
    }
    It 'exposes the lamfa command and the full subcommand list' {
        # The entry function is named Lamfa itself - the command IS lamfa.
        (Get-Command -Name Lamfa -CommandType Function).Name | Should -Be 'Lamfa'
        $subcommands = Lamfa-GetSubcommandList
        foreach ($expected in @('status', 'push', 'pr', 'doctor', 'help')) { $subcommands.Keys | Should -Contain $expected }
    }
    It 'help lists every subcommand lamfa-first' {
        $output = Lamfa -Command help 6>&1 | Out-String
        $output | Should -Match 'lamfa status'
        $output | Should -Match 'lamfa push'
        $output | Should -Match 'lamfa doctor'
    }
    It 'unknown subcommands fall back to help without throwing' {
        { Lamfa -Command 'nonsense' 6>&1 | Out-Null } | Should -Not -Throw
    }
}

Describe 'Persistent status bar' {
    It 'composes repository and account lines' {
        Mock Get-GitHubAuthStatus -ModuleName MainMenu { [pscustomobject]@{ Accounts = @([pscustomobject]@{ HostName = 'github.com'; Account = 'tester'; Active = $true }) } }
        $ctx = [pscustomobject]@{ Name = 'demo'; CurrentBranch = 'main'; IsDetachedHead = $false; WorkingTreeState = 'Clean'; AheadCount = 1; BehindCount = 0 }
        $docker = [pscustomobject]@{ DaemonRunning = $true; CurrentContext = 'default' }
        $lines = Lamfa-BuildStatusBar -Context $ctx -DockerStatus $docker -BeginnerMode $true
        $lines[0] | Should -Match 'demo @ main'
        $lines[0] | Should -Match 'ahead 1 / behind 0'
        $lines[1] | Should -Match 'GitHub: tester'
        $lines[1] | Should -Match 'Docker: default'
        $lines[1] | Should -Match 'Mode: Beginner'
    }
    It 'reports the empty session honestly' {
        Mock Get-GitHubAuthStatus -ModuleName MainMenu { [pscustomobject]@{ Accounts = @() } }
        $lines = Lamfa-BuildStatusBar -Context $null -BeginnerMode $false
        $lines[0] | Should -Be 'no active repository'
        $lines[1] | Should -Match 'GitHub: not logged in'
        $lines[1] | Should -Match 'Mode: Advanced'
    }
}

# Provider adapters: contract conformance + parsing, all
# mocked - no network, no CLIs, no credentials.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repoRoot 'src/Models/RepositoryContext.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Providers/GitLab/GitLabAdapter.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Providers/Gitea/GiteaAdapter.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Providers/Bitbucket/BitbucketAdapter.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Providers/ProviderAdapter.psm1') -Force
}

Describe 'Adapter registry + resolution' {
    It 'registers all four providers' {
        $providers = Lamfa-GetRegisteredProviderList
        foreach ($expected in @('github', 'gitlab', 'gitea', 'bitbucket')) { $providers | Should -Contain $expected }
    }
    It 'every adapter satisfies the full contract' {
        # contract keys are enforced at registration time; registering a broken one throws
        { Lamfa-RegisterProviderAdapter -Provider 'broken' -Adapter @{ CliName = 'x' } } |
            Should -Throw '*missing the contract member*'
    }
    It 'profile provider override beats URL detection' {
        $context = New-RepositoryContext -Id x -Name N -Path 'C:\x' -IsGitRepository $true `
            -Remotes @([pscustomobject]@{ Name = 'origin'; FetchUrl = 'https://github.com/o/r.git' }) -PreferredRemote origin
        $profile_ = [pscustomobject]@{ Data = [pscustomobject]@{
            repository = [pscustomobject]@{ provider = 'gitea' } }; Source = 't'; IsRepositoryOwned = $false }
        (Lamfa-GetProviderAdapter -Context $context -ResolvedProfile $profile_).Provider | Should -Be 'gitea'
    }
    It 'detects the provider from the remote URL' {
        $context = New-RepositoryContext -Id x -Name N -Path 'C:\x' -IsGitRepository $true `
            -Remotes @([pscustomobject]@{ Name = 'origin'; FetchUrl = 'git@bitbucket.org:team/repo.git' }) -PreferredRemote origin
        (Lamfa-GetProviderAdapter -Context $context).Provider | Should -Be 'bitbucket'
    }
    It 'degrades gracefully for unknown providers' {
        $context = New-RepositoryContext -Id x -Name N -Path 'C:\x' -IsGitRepository $true `
            -Remotes @([pscustomobject]@{ Name = 'origin'; FetchUrl = 'https://svn.example.com/x' }) -PreferredRemote origin
        $resolved = Lamfa-GetProviderAdapter -Context $context
        $resolved.Adapter | Should -BeNullOrEmpty
        $resolved.Remediation | Should -Match 'keep working'
    }
}

Describe 'GitLab adapter parsing' {
    It 'maps an MR into the common record' {
        Mock Invoke-ExternalCommand -ModuleName GitLabAdapter {
            [pscustomobject]@{ ExitCode = 0; Succeeded = $true; StandardError = ''
                StandardOutput = '{"iid":7,"title":"Fix x","state":"opened","draft":false,"source_branch":"feature/x","target_branch":"main","web_url":"https://gitlab.example/mr/7"}' }
        }
        $pr = Get-GitLabMergeRequestForBranch -Path 'C:\x'
        $pr.Number | Should -Be 7
        $pr.Base | Should -Be 'main'
        $pr.Head | Should -Be 'feature/x'
        $pr.State | Should -Be 'OPENED'
    }
    It 'creates an MR with explicit source and target branches' {
        Mock Invoke-ExternalCommand -ModuleName GitLabAdapter {
            param($Executable, $Arguments)
            $Executable | Should -Be 'glab'
            $Arguments | Should -Contain '--source-branch'
            $Arguments | Should -Contain 'feature/x'
            $Arguments | Should -Contain '--target-branch'
            $Arguments | Should -Contain 'main'
            [pscustomobject]@{ ExitCode = 0; Succeeded = $true; StandardOutput = ''; StandardError = '' }
        }
        (New-GitLabMergeRequest -Path 'C:\x' -BaseBranch main -HeadBranch feature/x -Title t).Succeeded | Should -BeTrue
    }
}

Describe 'Gitea adapter parsing' {
    It 'finds the PR for the current branch from the list output' {
        Mock Invoke-ExternalCommand -ModuleName GiteaAdapter {
            [pscustomobject]@{ ExitCode = 0; Succeeded = $true; StandardError = ''
                StandardOutput = '[{"index":3,"title":"Old","state":"closed","base":"main","head":"feature/x","url":"u1"},{"index":9,"title":"New","state":"open","base":"main","head":"feature/x","url":"u2"}]' }
        }
        $pr = Get-GiteaPullRequestForBranch -Path 'C:\x' -Branch 'feature/x'
        $pr.Number | Should -Be 9
        $pr.State | Should -Be 'OPEN'
    }
    It 'returns null when no open PR matches the branch' {
        Mock Invoke-ExternalCommand -ModuleName GiteaAdapter {
            [pscustomobject]@{ ExitCode = 0; Succeeded = $true; StandardError = ''
                StandardOutput = '[{"index":3,"title":"Other","state":"open","base":"main","head":"another","url":"u"}]' }
        }
        Get-GiteaPullRequestForBranch -Path 'C:\x' -Branch 'feature/x' | Should -BeNullOrEmpty
    }
}

Describe 'Bitbucket adapter' {
    It 'extracts workspace/slug from https and ssh remotes' {
        $target = Get-BitbucketRepositoryTarget -RemoteUrl 'https://bitbucket.org/myteam/myrepo.git'
        $target.Workspace | Should -Be 'myteam'
        $target.Slug | Should -Be 'myrepo'
        (Get-BitbucketRepositoryTarget -RemoteUrl 'git@bitbucket.org:ws/slug.git').Slug | Should -Be 'slug'
        { Get-BitbucketRepositoryTarget -RemoteUrl 'https://github.com/x/y.git' } | Should -Throw '*cannot extract*'
    }
    It 'maps the REST response into the common record' {
        Mock Invoke-BitbucketApi -ModuleName BitbucketAdapter {
            [pscustomobject]@{ values = @([pscustomobject]@{
                id = 12; title = 'Fix y'; state = 'OPEN'; draft = $false
                destination = [pscustomobject]@{ branch = [pscustomobject]@{ name = 'main' } }
                source = [pscustomobject]@{ branch = [pscustomobject]@{ name = 'feature/y' } }
                links = [pscustomobject]@{ html = [pscustomobject]@{ href = 'https://bitbucket.org/pr/12' } } }) }
        }
        $pr = Get-BitbucketPullRequestForBranch -RemoteUrl 'https://bitbucket.org/ws/slug.git' -Branch 'feature/y'
        $pr.Number | Should -Be 12
        $pr.Base | Should -Be 'main'
        $pr.Url | Should -Be 'https://bitbucket.org/pr/12'
    }
    It 'refuses a non-credential vault entry' {
        $fakeApi = @{ GetRaw = { param($Name) 'just-a-string' }; Get = {}; Set = {}; Remove = {}; Vaults = { @() } }
        { Get-BitbucketCredential -VaultApi $fakeApi } | Should -Throw '*must be a PSCredential*'
    }
}

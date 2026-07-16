# GitHub + Docker provider tests - JSON parsing and guard
# logic with Invoke-ExternalCommand MOCKED (no network, no daemon, no creds).
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repoRoot 'src/Providers/GitHub/GitHubAuth.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'src/Providers/GitHub/GitHubRepositories.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'src/Providers/GitHub/GitHubPullRequests.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'src/Docker/DockerEnvironment.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'src/Docker/DockerImages.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'src/Docker/DockerRegistry.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'src/Workflows/ProfileLoader.psm1') -Force -DisableNameChecking

}

Describe 'GitHub auth status parsing' {
    It 'parses hosts, accounts, and the active marker' {
        Mock Invoke-ExternalCommand -ModuleName GitHubAuth {
            [pscustomobject]@{ ExitCode = 0; Succeeded = $true
                StandardOutput = "github.com`n  Logged in to github.com account flamaj (keyring)`n  - Active account: true"
                StandardError = '' }
        }
        $status = Get-GitHubAuthStatus
        $status.Authenticated | Should -BeTrue
        @($status.Accounts).Count | Should -Be 1
        $status.Accounts[0].Account | Should -Be 'flamaj'
        $status.UsesPlaintextTokens | Should -BeFalse
    }
    It 'flags plaintext token storage' {
        Mock Invoke-ExternalCommand -ModuleName GitHubAuth {
            [pscustomobject]@{ ExitCode = 0; Succeeded = $true
                StandardOutput = 'Logged in to github.com account x. Token stored in plain text file.'
                StandardError = '' }
        }
        (Get-GitHubAuthStatus).UsesPlaintextTokens | Should -BeTrue
    }
}

Describe 'GitHub repository access + PR parsing' {
    It 'parses accessible repository JSON' {
        Mock Invoke-ExternalCommand -ModuleName GitHubRepositories {
            [pscustomobject]@{ ExitCode = 0; Succeeded = $true
                StandardOutput = '{"nameWithOwner":"org/repo","viewerPermission":"WRITE"}'; StandardError = '' }
        }
        $access = Test-GitHubRepositoryAccess -Path 'C:\x'
        $access.Accessible | Should -BeTrue
        $access.Repository | Should -Be 'org/repo'
        $access.Permission | Should -Be 'WRITE'
    }
    It 'reports inaccessible without throwing' {
        Mock Invoke-ExternalCommand -ModuleName GitHubRepositories {
            [pscustomobject]@{ ExitCode = 1; Succeeded = $false; StandardOutput = ''; StandardError = 'HTTP 404' }
        }
        (Test-GitHubRepositoryAccess -Path 'C:\x').Accessible | Should -BeFalse
    }
    It 'returns null when no PR exists for the branch' {
        Mock Invoke-ExternalCommand -ModuleName GitHubPullRequests {
            [pscustomobject]@{ ExitCode = 1; Succeeded = $false; StandardOutput = ''; StandardError = 'no pull requests found' }
        }
        Get-GitHubPullRequestForBranch -Path 'C:\x' | Should -BeNullOrEmpty
    }
    It 'parses PR metadata JSON' {
        Mock Invoke-ExternalCommand -ModuleName GitHubPullRequests {
            [pscustomobject]@{ ExitCode = 0; Succeeded = $true
                StandardOutput = '{"number":150,"title":"Fix","state":"OPEN","isDraft":false,"baseRefName":"develop","headRefName":"feature/x","url":"https://x","reviewDecision":"APPROVED"}'
                StandardError = '' }
        }
        $pr = Get-GitHubPullRequestForBranch -Path 'C:\x'
        $pr.number | Should -Be 150
        $pr.baseRefName | Should -Be 'develop'
    }
}

Describe 'Docker status + context parsing' {
    It 'degrades gracefully when the daemon is down (client only)' {
        Mock Invoke-ExternalCommand -ModuleName DockerEnvironment {
            param($Executable, $Arguments, $WorkingDirectory, $Environment, $TimeoutSeconds)
            if ($Arguments -contains 'version') {
                return [pscustomobject]@{ ExitCode = 1; Succeeded = $false
                    StandardOutput = '{"Client":{"Version":"29.2.0"}}'; StandardError = 'error during connect' }
            }
            return [pscustomobject]@{ ExitCode = 1; Succeeded = $false; StandardOutput = ''; StandardError = 'x' }
        }
        $status = Get-DockerStatus
        $status.CliInstalled | Should -BeTrue
        $status.DaemonRunning | Should -BeFalse
        $status.Message | Should -Match 'daemon'
    }
    It 'parses context list JSON lines and flags remote endpoints' {
        Mock Invoke-ExternalCommand -ModuleName DockerEnvironment {
            [pscustomobject]@{ ExitCode = 0; Succeeded = $true
                StandardOutput = '{"Name":"default","DockerEndpoint":"npipe:////./pipe/docker_engine","Current":true}' + "`n" +
                                 '{"Name":"prod","DockerEndpoint":"ssh://admin@prod.example.com","Current":false}'
                StandardError = '' }
        }
        $contexts = Get-DockerContextList
        @($contexts).Count | Should -Be 2
        ($contexts | Where-Object Name -eq 'prod').LooksRemote | Should -BeTrue
        ($contexts | Where-Object Name -eq 'default').LooksRemote | Should -BeFalse
    }
}

Describe 'Docker registry target resolution' {
    It 'builds the exact push reference from the profile' {
        $resolved = [pscustomobject]@{ Data = ([pscustomobject]@{
            docker = [pscustomobject]@{ registry = 'registry.example.com'; image = 'myapp' } })
            Source = 'x'; IsRepositoryOwned = $false }
        $target = Get-DockerRegistryTarget -ResolvedProfile $resolved -Tag '1.2.3'
        $target.Reference | Should -Be 'registry.example.com/myapp:1.2.3'
    }
    It 'refuses a profile without registry configuration' {
        $resolved = [pscustomobject]@{ Data = ([pscustomobject]@{ docker = [pscustomobject]@{ registry = ''; image = '' } })
            Source = 'x'; IsRepositoryOwned = $false }
        { Get-DockerRegistryTarget -ResolvedProfile $resolved } | Should -Throw '*registry*'
    }
}

Describe 'Generic remote provider detection' {
    BeforeAll {
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        Import-Module (Join-Path $repoRoot 'src/Providers/GenericRemote.psm1') -Force -DisableNameChecking
    }
    It 'detects <expected> from <url>' -ForEach @(
        @{ url = 'https://github.com/org/repo.git';          expected = 'github' }
        @{ url = 'git@github.com:org/repo.git';              expected = 'github' }
        @{ url = 'https://gitlab.company.com/g/p.git';       expected = 'gitlab' }
        @{ url = 'https://bitbucket.org/team/repo.git';      expected = 'bitbucket' }
        @{ url = 'git@gitea.internal.lan:org/repo.git';      expected = 'gitea' }
        @{ url = 'https://codeberg.org/org/repo.git';        expected = 'gitea' }
        @{ url = 'https://dev.azure.com/org/proj/_git/repo'; expected = 'azuredevops' }
        @{ url = 'https://git.example.com/x/y.git';          expected = 'generic' }
    ) {
        (Lamfa-GetProviderFromRemote -RemoteUrl $url).Provider | Should -Be $expected
    }
    It 'converts SSH URLs to browsable HTTPS' {
        Lamfa-ConvertToWebUrl -RemoteUrl 'git@github.com:org/repo.git' | Should -Be 'https://github.com/org/repo'
        Lamfa-ConvertToWebUrl -RemoteUrl 'ssh://git@gitea.lan:2222/org/repo.git' | Should -Be 'https://gitea.lan/org/repo'
        Lamfa-ConvertToWebUrl -RemoteUrl 'https://github.com/org/repo.git' | Should -Be 'https://github.com/org/repo'
    }
}

Describe 'PR checkout + comment' {
    It 'checks out a PR by number' {
        Mock Invoke-ExternalCommand -ModuleName GitHubPullRequests {
            param($Executable, $Arguments)
            $Arguments | Should -Be @('pr', 'checkout', '42')
            [pscustomobject]@{ ExitCode = 0; Succeeded = $true; StandardOutput = ''; StandardError = '' }
        }
        (Invoke-GitHubPullRequestCheckout -Path 'C:\x' -Number 42).Succeeded | Should -BeTrue
    }
    It 'adds a comment with the body as one argument' {
        Mock Invoke-ExternalCommand -ModuleName GitHubPullRequests {
            param($Executable, $Arguments)
            $Arguments[-1] | Should -Be 'looks good, one question about spaces'
            [pscustomobject]@{ ExitCode = 0; Succeeded = $true; StandardOutput = ''; StandardError = '' }
        }
        (Add-GitHubPullRequestComment -Path 'C:\x' -Body 'looks good, one question about spaces').Succeeded | Should -BeTrue
    }
}

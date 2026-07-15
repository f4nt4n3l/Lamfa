# Automated acceptance journey:
# register -> switch -> branch -> edit -> selective commit -> push to a local
# bare remote -> second clone sees the change -> bundle backup -> release
# record with gates + local tag. Everything on disposable fixtures.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    foreach ($m in @('Repositories/RepositoryRegistry', 'Git/GitBranches', 'Git/GitCommits',
                     'Git/GitRemotes', 'Git/GitStatus', 'Git/GitTags', 'Git/GitRepository',
                     'Workflows/ReleaseTools', 'Workflows/ReleaseOrchestrator', 'Core/State', 'Core/CommandRunner',
                     'Models/RepositoryContext')) {
        Import-Module (Join-Path $repoRoot "src/$m.psm1") -Force
    }
    . (Join-Path $repoRoot 'tools/New-TestRepository.ps1')
    $script:fx = New-TestRepository -State WithRemote
    $script:cfg = Join-Path $script:fx.Root 'config.json'
    $script:stateDir = Join-Path $script:fx.Root 'release-state'
}
AfterAll {
    Remove-Item -Path $script:fx.Root -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Beginner journey end to end' {
    It '1. registers and activates the repository' {
        $registration = Lamfa-AddRepository -Path $script:fx.Path -Name 'journey' -ConfigPath $script:cfg
        $script:context = Lamfa-SetActiveRepository -Id $registration.id -ConfigPath $script:cfg
        $script:context.IsGitRepository | Should -BeTrue
    }
    It '2. creates a work branch from main' {
        New-GitBranch -Path $script:context.Path -Name 'feature/journey' -SourceRef main -Switch
        Get-GitCurrentBranch -Path $script:context.Path | Should -Be 'feature/journey'
    }
    It '3. commits ONLY the selected file' {
        Set-Content -Path (Join-Path $script:context.Path 'wanted.txt') -Value 'ship this'
        Set-Content -Path (Join-Path $script:context.Path 'unwanted.txt') -Value 'not this'
        Add-GitStagedFile -Path $script:context.Path -Files @('wanted.txt')
        $null = New-GitCommit -Path $script:context.Path -Title 'Add wanted file'
        $status = Get-GitStatus -Path $script:context.Path
        @($status.Entries | Where-Object Kind -eq 'Untracked').Path | Should -Be @('unwanted.txt')
    }
    It '4. publishes the branch with an exact-target preview' {
        $preview = Get-GitPushPreview -Path $script:context.Path
        $preview.CreatesUpstream | Should -BeTrue
        (Invoke-GitPush -Path $script:context.Path).Succeeded | Should -BeTrue
    }
    It '5. a second clone receives the pushed branch' {
        $second = Join-Path $script:fx.Root 'second clone'
        $result = Invoke-ExternalCommand -Executable git -Arguments @('clone', '--branch', 'feature/journey', $script:fx.RemotePath, $second) `
            -WorkingDirectory $script:fx.Root
        $result.Succeeded | Should -BeTrue
        Test-Path (Join-Path $second 'wanted.txt') | Should -BeTrue
        Test-Path (Join-Path $second 'unwanted.txt') | Should -BeFalse
    }
    It '6. bundle backup is created and verified' {
        (New-GitBundleBackup -RepositoryPath $script:context.Path -DestinationDirectory (Join-Path $script:fx.Root 'backups')).Verified |
            Should -BeTrue
    }
    It '7. release record: passing gates unlock a local tag; steps never repeat' {
        $state = Lamfa-NewReleaseState -RepositoryId 'journey' -Version '0.9.9' `
            -Steps @('gates', 'tag') -StateDirectory $script:stateDir
        $gateProfile = [pscustomobject]@{
            Data = [pscustomobject]@{ schemaVersion = 1; commands = [pscustomobject]@{
                build = [pscustomobject]@{ executable = 'pwsh'; arguments = @('-NoProfile', '-Command', 'exit 0') }
                test  = [pscustomobject]@{ executable = 'pwsh'; arguments = @('-NoProfile', '-Command', 'exit 0') } } }
            Source = 'test'; IsRepositoryOwned = $false }
        $gates = Lamfa-InvokeReleaseGateCheck -RepositoryPath $script:context.Path -RepositoryId journey -ResolvedProfile $gateProfile
        $gates.Passed | Should -BeTrue
        Lamfa-CompleteReleaseStep -State $state -StepName 'gates' -StateDirectory $script:stateDir
        New-GitTag -Path $script:context.Path -Name 'v0.9.9' -Message 'journey release'
        Lamfa-CompleteReleaseStep -State $state -StepName 'tag' -StateDirectory $script:stateDir
        $resumed = Lamfa-GetReleaseState -RepositoryId 'journey' -StateDirectory $script:stateDir
        Lamfa-IsReleaseStepPending -State $resumed -StepName 'tag' | Should -BeFalse
    }
}

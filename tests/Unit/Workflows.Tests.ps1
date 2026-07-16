# Profiles, trust, detection, workflow engine, release tools, release state.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repoRoot 'src/Workflows/ProfileLoader.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'src/Workflows/ProjectDetection.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'src/Workflows/WorkflowEngine.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'src/Workflows/ReleaseTools.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'src/Core/State.psm1') -Force -DisableNameChecking
    . (Join-Path $repoRoot 'tools/New-TestRepository.ps1')
    $script:repoRoot = $repoRoot
    $script:sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("lamfa-wf-" + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path $script:sandbox
    $script:trustStore = Join-Path $script:sandbox 'trust.json'
}
AfterAll {
    Remove-Item -Path $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Profile validation + resolution' {
    It 'accepts the shipped built-in profiles' {
        foreach ($file in @('default.json')) {
            $data = Get-Content (Join-Path $script:repoRoot "profiles/$file") -Raw | ConvertFrom-Json
            (Lamfa-TestProfile -RepoProfile $data -SourceDescription $file).Count | Should -Be 0
        }
    }
    It 'rejects shell metacharacters in executables' {
        $bad = [pscustomobject]@{ schemaVersion = 1
            commands = [pscustomobject]@{ evil = [pscustomobject]@{ executable = 'cmd & del'; arguments = @() } } }
        (Lamfa-TestProfile -RepoProfile $bad) -join ' ' | Should -Match 'metacharacters'
    }
    It 'falls back to the default profile when the repo profile is invalid - generic Git keeps working' {
        $repo = Join-Path $script:sandbox 'invalid profile repo'
        $null = New-Item -ItemType Directory -Path $repo
        Set-Content -Path (Join-Path $repo '.lamfa.json') -Value '{ "schemaVersion": 99 }'
        $resolved = Lamfa-GetProfile -RepositoryPath $repo -BuiltInDirectory (Join-Path $script:repoRoot 'profiles')
        $resolved.IsRepositoryOwned | Should -BeFalse
        $resolved.Source | Should -Match 'default.json'
        ($resolved.ValidationErrors).Count | Should -BeGreaterThan 0
    }
    It 'resolves a built-in profile by repository name' {
        $repo = Join-Path $script:sandbox 'named repo'
        $null = New-Item -ItemType Directory -Path $repo
        $builtIn = Join-Path $script:sandbox 'builtin-profiles'
        $null = New-Item -ItemType Directory -Path $builtIn
        Copy-Item (Join-Path $script:repoRoot 'profiles/default.json') (Join-Path $builtIn 'default.json')
        Copy-Item (Join-Path $script:repoRoot 'profiles/default.json') (Join-Path $builtIn 'sample.json')
        $resolved = Lamfa-GetProfile -RepositoryPath $repo -RepositoryName 'Sample' -BuiltInDirectory $builtIn
        $resolved.Source | Should -Match 'sample.json'
    }
}

Describe 'Profile trust' {
    BeforeAll {
        $script:trustRepo = Join-Path $script:sandbox 'trusted repo'
        $null = New-Item -ItemType Directory -Path $script:trustRepo
        Set-Content -Path (Join-Path $script:trustRepo '.lamfa.json') -Value (@'
{ "schemaVersion": 1, "commands": { "hello": { "executable": "pwsh", "arguments": ["-NoProfile", "-Command", "Write-Output hi"] } } }
'@)
        $script:profilePath = Join-Path $script:trustRepo '.lamfa.json'
    }
    It 'an untrusted repository-owned profile is refused with the exact command shown' {
        $resolved = Lamfa-GetProfile -RepositoryPath $script:trustRepo -BuiltInDirectory (Join-Path $script:repoRoot 'profiles')
        $resolved.IsRepositoryOwned | Should -BeTrue
        { Lamfa-InvokeWorkflowCommand -RepositoryPath $script:trustRepo -RepositoryId 'repo-1' `
            -ResolvedProfile $resolved -CommandName hello -TrustStorePath $script:trustStore } |
            Should -Throw '*not trusted*'
    }
    It 'runs after trust is granted; changed content invalidates trust' {
        Lamfa-GrantProfileTrust -RepositoryId 'repo-1' -ProfilePath $script:profilePath -TrustStorePath $script:trustStore
        $resolved = Lamfa-GetProfile -RepositoryPath $script:trustRepo -BuiltInDirectory (Join-Path $script:repoRoot 'profiles')
        $result = Lamfa-InvokeWorkflowCommand -RepositoryPath $script:trustRepo -RepositoryId 'repo-1' `
            -ResolvedProfile $resolved -CommandName hello -TrustStorePath $script:trustStore
        $result.StandardOutput.Trim() | Should -Be 'hi'
        Add-Content -Path $script:profilePath -Value ' '
        Lamfa-IsProfileTrusted -RepositoryId 'repo-1' -ProfilePath $script:profilePath -TrustStorePath $script:trustStore |
            Should -BeFalse
    }
}

Describe 'Project detection' {
    It 'detects dotnet + docker evidence without executing anything' {
        $repo = Join-Path $script:sandbox 'detect repo'
        $null = New-Item -ItemType Directory -Path (Join-Path $repo 'App') -Force
        Set-Content -Path (Join-Path $repo 'App/App.csproj') -Value '<Project />'
        Set-Content -Path (Join-Path $repo 'Dockerfile') -Value 'FROM scratch'
        $evidence = Lamfa-FindProjectEvidence -Path $repo
        @($evidence | Where-Object ProjectType -eq 'dotnet').Count | Should -BeGreaterThan 0
        @($evidence | Where-Object ProjectType -eq 'docker').Count | Should -BeGreaterThan 0
    }
}

Describe 'Version + changelog' {
    BeforeAll {
        $script:versionRepo = Join-Path $script:sandbox 'version repo'
        $null = New-Item -ItemType Directory -Path $script:versionRepo
        Set-Content -Path (Join-Path $script:versionRepo 'App.csproj') -Value '<Project><PropertyGroup><Version>1.2.3</Version></PropertyGroup></Project>'
        Set-Content -Path (Join-Path $script:versionRepo 'package.json') -Value '{ "version": "4.5.6" }'
        Set-Content -Path (Join-Path $script:versionRepo 'CHANGELOG.md') -Value "# Log`n`n## [Unreleased]`n`n- new thing`n`n## [1.2.2]`n`n- old thing"
    }
    It 'reads csproj and package.json versions' {
        (Lamfa-GetProjectVersion -RepositoryPath $script:versionRepo -VersionFile 'App.csproj').Version | Should -Be '1.2.3'
        (Lamfa-GetProjectVersion -RepositoryPath $script:versionRepo -VersionFile 'package.json').Version | Should -Be '4.5.6'
    }
    It 'throws an actionable error for a file without a version' {
        Set-Content -Path (Join-Path $script:versionRepo 'empty.txt') -Value 'nothing here'
        { Lamfa-GetProjectVersion -RepositoryPath $script:versionRepo -VersionFile 'empty.txt' } |
            Should -Throw '*no SemVer version*'
    }
    It 'extracts exactly one changelog section' {
        Lamfa-GetChangelogSection -RepositoryPath $script:versionRepo -Section 'Unreleased' | Should -Be '- new thing'
        Lamfa-GetChangelogSection -RepositoryPath $script:versionRepo -Section '1.2.2' | Should -Be '- old thing'
        { Lamfa-GetChangelogSection -RepositoryPath $script:versionRepo -Section '9.9.9' } | Should -Throw '*no*section*'
    }
}

Describe 'Release state' {
    It 'creates, completes steps, resumes, and never repeats completed steps' {
        $stateDirectory = Join-Path $script:sandbox 'release-state'
        $state = Lamfa-NewReleaseState -RepositoryId 'repo-x' -Version '2.0.0' `
            -Steps @('gates', 'tag', 'publish') -StateDirectory $stateDirectory
        Lamfa-IsReleaseStepPending -State $state -StepName 'tag' | Should -BeTrue
        Lamfa-CompleteReleaseStep -State $state -StepName 'tag' -Detail 'v2.0.0' -StateDirectory $stateDirectory
        # simulate interruption: reload from disk
        $resumed = Lamfa-GetReleaseState -RepositoryId 'repo-x' -StateDirectory $stateDirectory
        Lamfa-IsReleaseStepPending -State $resumed -StepName 'tag' | Should -BeFalse
        Lamfa-IsReleaseStepPending -State $resumed -StepName 'publish' | Should -BeTrue
        Lamfa-RemoveReleaseState -RepositoryId 'repo-x' -StateDirectory $stateDirectory
        Lamfa-GetReleaseState -RepositoryId 'repo-x' -StateDirectory $stateDirectory | Should -BeNullOrEmpty
    }
}

Describe 'Git bundle backup' {
    It 'creates and verifies a bundle from a fixture repository' {
        $fx = New-TestRepository -State Clean
        try {
            $backup = New-GitBundleBackup -RepositoryPath $fx.Path -DestinationDirectory (Join-Path $script:sandbox 'bundles')
            $backup.Verified | Should -BeTrue
            $backup.SizeBytes | Should -BeGreaterThan 0
        } finally { Remove-Item $fx.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Comment audit' {
    It 'finds TODO markers and secret-looking comments, reporting only' {
        $repo = Join-Path $script:sandbox 'audit repo'
        $null = New-Item -ItemType Directory -Path $repo
        Set-Content -Path (Join-Path $repo 'code.ps1') -Value @(
            '# TODO: refactor this later',
            '$x = 1  # HACK workaround',
            '# api key ghp_abcdefghij1234567890KLMNOP')
        $findings = Lamfa-GetCommentAudit -Path $repo
        @($findings | Where-Object Kind -eq 'TODO').Count | Should -Be 1
        @($findings | Where-Object Kind -eq 'HACK').Count | Should -Be 1
        @($findings | Where-Object Kind -eq 'LikelySecret').Count | Should -Be 1
        ($findings | Where-Object Kind -eq 'LikelySecret').Text | Should -Match 'REDACTED'
        (Get-Content (Join-Path $repo 'code.ps1') -Raw) | Should -Match 'ghp_'   # never modified
    }
}

# Release orchestration tests + config migration
# + hardened redaction cases.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repoRoot 'src/Workflows/ProfileLoader.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Workflows/ReleaseOrchestrator.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Core/Configuration.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Core/Logging.psm1') -Force
    $script:sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("lamfa-rel-" + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path $script:sandbox
    $script:trustStore = Join-Path $script:sandbox 'trust.json'

    function New-GateProfile {
        param([int]$BuildExit = 0, [int]$TestExit = 0, [switch]$OmitTest)
        $commands = [ordered]@{
            build = [pscustomobject]@{ executable = 'pwsh'; arguments = @('-NoProfile', '-Command', "exit $BuildExit") }
        }
        if (-not $OmitTest) {
            $commands.test = [pscustomobject]@{ executable = 'pwsh'; arguments = @('-NoProfile', '-Command', "exit $TestExit") }
        }
        return [pscustomobject]@{
            Data = [pscustomobject]@{ schemaVersion = 1; commands = [pscustomobject]$commands }
            Source = 'built-in-test'; IsRepositoryOwned = $false; ValidationErrors = @()
        }
    }
}
AfterAll {
    Remove-Item -Path $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Release gates' {
    It 'passes when build and test both exit 0' {
        $gates = Lamfa-InvokeReleaseGateCheck -RepositoryPath $script:sandbox -RepositoryId r `
            -ResolvedProfile (New-GateProfile) -TrustStorePath $script:trustStore
        $gates.Passed | Should -BeTrue
        @($gates.Details).Count | Should -Be 2
    }
    It 'fails when a gate command fails' {
        $gates = Lamfa-InvokeReleaseGateCheck -RepositoryPath $script:sandbox -RepositoryId r `
            -ResolvedProfile (New-GateProfile -TestExit 5) -TrustStorePath $script:trustStore
        $gates.Passed | Should -BeFalse
        ($gates.Details -join ' ') | Should -Match "FAILED"
    }
    It 'fails closed when a gate is NOT CONFIGURED - a release never ships unverified by accident' {
        $gates = Lamfa-InvokeReleaseGateCheck -RepositoryPath $script:sandbox -RepositoryId r `
            -ResolvedProfile (New-GateProfile -OmitTest) -TrustStorePath $script:trustStore
        $gates.Passed | Should -BeFalse
        ($gates.Details -join ' ') | Should -Match 'NOT CONFIGURED'
    }
}

Describe 'GitHub release + Docker release step' {
    It 'creates a release with explicit tag, title, and notes' {
        Mock Invoke-ExternalCommand -ModuleName ReleaseOrchestrator {
            param($Executable, $Arguments, $WorkingDirectory)
            $Arguments[0] | Should -Be 'release'
            $Arguments | Should -Contain 'v1.0.0'
            [pscustomobject]@{ ExitCode = 0; Succeeded = $true; StandardOutput = 'https://github.com/x/y/releases/v1.0.0'; StandardError = '' }
        }
        (New-GitHubRelease -RepositoryPath $script:sandbox -Tag 'v1.0.0' -Title 'Release 1.0.0' -NotesText 'notes').Succeeded |
            Should -BeTrue
    }
    It 'docker step builds, tags the exact reference, pushes - and throws on build failure' {
        $resolved = [pscustomobject]@{
            Data = [pscustomobject]@{ docker = [pscustomobject]@{ dockerfile = 'Dockerfile'; image = 'app'; registry = 'reg.example.com' } }
            Source = 'x'; IsRepositoryOwned = $false }
        Mock Build-DockerImage -ModuleName ReleaseOrchestrator {
            [pscustomobject]@{ Succeeded = $false; StandardError = 'no daemon' }
        }
        { Lamfa-InvokeDockerReleaseStep -RepositoryPath $script:sandbox -ResolvedProfile $resolved -Version '1.0.0' } |
            Should -Throw '*build failed*'
    }
    It 'refuses a profile without a docker section' {
        $resolved = [pscustomobject]@{ Data = [pscustomobject]@{ schemaVersion = 1 }; Source = 'x'; IsRepositoryOwned = $false }
        { Lamfa-InvokeDockerReleaseStep -RepositoryPath $script:sandbox -ResolvedProfile $resolved -Version '1.0.0' } |
            Should -Throw '*no docker section*'
    }
}

Describe 'Configuration migration' {
    It 'fills missing properties and stamps schemaVersion 1' {
        $old = [pscustomobject]@{ beginnerMode = $false }
        $migration = Lamfa-ConvertConfiguration -Configuration $old
        $migration.Migrated | Should -BeTrue
        $migration.Configuration.schemaVersion | Should -Be 1
        $migration.Configuration.beginnerMode | Should -BeFalse   # user value preserved
        $migration.Configuration.preferences | Should -Not -BeNullOrEmpty
    }
    It 'leaves a current configuration untouched' {
        (Lamfa-ConvertConfiguration -Configuration (Lamfa-GetDefaultConfiguration)).Migrated | Should -BeFalse
    }
    It 'refuses a FUTURE schema version instead of guessing' {
        { Lamfa-ConvertConfiguration -Configuration ([pscustomobject]@{ schemaVersion = 2 }) } |
            Should -Throw '*NEWER*'
    }
    It 'loader migrates an old file on disk and persists the result' {
        $path = Join-Path $script:sandbox 'old-config.json'
        Set-Content -Path $path -Value '{ "beginnerMode": true, "workspaceRoots": [], "repositories": [], "preferences": {"openEditorCommand":"code","fetchFreshnessMinutes":15,"showCommandsBeforeExecution":true,"pauseAfterErrors":true} }'
        $config = Lamfa-GetConfiguration -Path $path
        $config.schemaVersion | Should -Be 1
        (Get-Content -Path $path -Raw | ConvertFrom-Json).schemaVersion | Should -Be 1   # persisted
    }
}

Describe 'Hardened redaction' {
    It 'redacts <kind>' -ForEach @(
        @{ kind = 'npm token';   text = 'auth npm_AbCdEfGhIjKlMnOpQrStUvWxYz012345';       secret = 'npm_AbCdEfGhIjKlMnOpQrStUvWxYz012345' }
        @{ kind = 'slack token'; text = 'hook xoxb-1234567890-abcdefghij';                  secret = 'xoxb-1234567890-abcdefghij' }
        @{ kind = 'PEM block';   text = "-----BEGIN RSA PRIVATE KEY-----`nMIIE...`n-----END RSA PRIVATE KEY-----"; secret = 'MIIE' }
    ) {
        $redacted = Get-RedactedText -Text $text
        $redacted | Should -Not -Match ([regex]::Escape($secret))
        $redacted | Should -Match 'REDACTED'
    }
}

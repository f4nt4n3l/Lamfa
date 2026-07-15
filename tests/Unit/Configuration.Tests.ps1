# Configuration loader + validation tests.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repoRoot 'src/Core/Configuration.psm1') -Force
    $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("lamfa-cfg-" + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path $script:tempDir
    $script:cfgPath = Join-Path $script:tempDir 'config.json'
}
AfterAll {
    Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Lamfa-GetConfiguration' {
    It 'returns embedded defaults when no user file exists' {
        $config = Lamfa-GetConfiguration -Path (Join-Path $script:tempDir 'missing.json')
        $config.schemaVersion | Should -Be 1
        $config.beginnerMode | Should -BeTrue
        @($config.workspaceRoots).Count | Should -Be 0
    }

    It 'round-trips through Save + Get' {
        $config = Lamfa-GetDefaultConfiguration
        $config.beginnerMode = $false
        Lamfa-SaveConfiguration -Configuration $config -Path $script:cfgPath
        (Lamfa-GetConfiguration -Path $script:cfgPath).beginnerMode | Should -BeFalse
    }

    It 'throws a ConfigurationError naming the file for broken JSON' {
        $broken = Join-Path $script:tempDir 'broken.json'
        Set-Content -Path $broken -Value '{ not json'
        { Lamfa-GetConfiguration -Path $broken } | Should -Throw '*ConfigurationError*'
    }
}

Describe 'Lamfa-TestConfiguration' {
    It 'accepts the default configuration' {
        (Lamfa-TestConfiguration -Configuration (Lamfa-GetDefaultConfiguration)).Count | Should -Be 0
    }

    It 'reports property, expected value, and recovery for a wrong schemaVersion' {
        $bad = Lamfa-GetDefaultConfiguration
        $bad.schemaVersion = 99
        $problems = Lamfa-TestConfiguration -Configuration $bad -SourceDescription 'test.json'
        $problems.Count | Should -BeGreaterThan 0
        $problems[0] | Should -Match 'schemaVersion'
        $problems[0] | Should -Match '99'
        $problems[0] | Should -Match 'delete the file'
    }

    It 'flags a missing preferences object' {
        $bad = [pscustomobject]@{ schemaVersion = 1; beginnerMode = $true; workspaceRoots = @(); repositories = @() }
        (Lamfa-TestConfiguration -Configuration $bad) -join ' ' | Should -Match 'preferences'
    }

    It 'refuses to save an invalid configuration' {
        { Lamfa-SaveConfiguration -Configuration ([pscustomobject]@{ schemaVersion = 2 }) -Path $script:cfgPath } |
            Should -Throw '*ConfigurationError*'
    }

    It 'matches the shipped config/default-config.json template' {
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        $shipped = Get-Content (Join-Path $repoRoot 'config/default-config.json') -Raw | ConvertFrom-Json
        (Lamfa-TestConfiguration -Configuration $shipped -SourceDescription 'default-config.json').Count | Should -Be 0
        $shipped.beginnerMode | Should -Be (Lamfa-GetDefaultConfiguration).beginnerMode
    }
}

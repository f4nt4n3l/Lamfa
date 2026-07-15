# Precondition engine tests.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repoRoot 'src/Models/RepositoryContext.psm1') -Force
    Import-Module (Join-Path $repoRoot 'src/Core/Preconditions.psm1') -Force
    $script:existingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("lamfa-pre-" + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path $script:existingDir
}
AfterAll {
    Remove-Item -Path $script:existingDir -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Lamfa-TestPrecondition' {
    It 'passes RepositorySelected + RepositoryPathExists for a real folder' {
        $context = New-RepositoryContext -Id x -Name Demo -Path $script:existingDir
        $results = Lamfa-TestPrecondition -Names @('RepositorySelected', 'RepositoryPathExists') -Context $context
        @($results | Where-Object Passed).Count | Should -Be 2
    }

    It 'fails RepositorySelected with remediation when no context exists' {
        $result = Lamfa-TestPrecondition -Names @('RepositorySelected') -Context $null
        $result[0].Passed | Should -BeFalse
        $result[0].SafeNextAction | Should -Match 'register'
        $result[0].WhyItMatters | Should -Not -BeNullOrEmpty
    }

    It 'fails RepositoryPathExists for a deleted folder' {
        $context = New-RepositoryContext -Id x -Name Gone -Path (Join-Path $script:existingDir 'gone')
        (Lamfa-TestPrecondition -Names @('RepositoryPathExists') -Context $context)[0].Passed | Should -BeFalse
    }

    It 'IsGitRepository reflects the context flag' {
        $git = New-RepositoryContext -Id x -Name G -Path $script:existingDir -IsGitRepository $true
        (Lamfa-TestPrecondition -Names @('IsGitRepository') -Context $git)[0].Passed | Should -BeTrue
        $plain = New-RepositoryContext -Id y -Name P -Path $script:existingDir
        (Lamfa-TestPrecondition -Names @('IsGitRepository') -Context $plain)[0].Passed | Should -BeFalse
    }

    It 'RequiredCommandAvailable detects an installed and a missing tool' {
        (Lamfa-TestPrecondition -Names @('RequiredCommandAvailable') -Parameters @{ RequiredCommand = 'pwsh' })[0].Passed | Should -BeTrue
        (Lamfa-TestPrecondition -Names @('RequiredCommandAvailable') -Parameters @{ RequiredCommand = 'no-such-tool-xyz' })[0].Passed | Should -BeFalse
    }

    It 'RequiredFileExists checks inside the repository path' {
        Set-Content -Path (Join-Path $script:existingDir 'build.cmd') -Value 'rem'
        $context = New-RepositoryContext -Id x -Name Demo -Path $script:existingDir
        (Lamfa-TestPrecondition -Names @('RequiredFileExists') -Context $context -Parameters @{ RequiredFile = 'build.cmd' })[0].Passed | Should -BeTrue
        (Lamfa-TestPrecondition -Names @('RequiredFileExists') -Context $context -Parameters @{ RequiredFile = 'missing.cmd' })[0].Passed | Should -BeFalse
    }

    It 'fails closed for an unknown precondition name' {
        $result = Lamfa-TestPrecondition -Names @('NotARealCheck')
        $result[0].Passed | Should -BeFalse
        $result[0].Description | Should -Match 'Unknown precondition'
    }

    It 'supports registering custom preconditions' {
        Lamfa-RegisterPrecondition -Name 'AlwaysTrueTest' -Description 'test' `
            -Test { param($Context, $Parameters) $true } -WhyItMatters 'w' -SafeNextAction 's'
        (Lamfa-TestPrecondition -Names @('AlwaysTrueTest'))[0].Passed | Should -BeTrue
        Lamfa-GetPreconditionList | Should -Contain 'AlwaysTrueTest'
    }
}

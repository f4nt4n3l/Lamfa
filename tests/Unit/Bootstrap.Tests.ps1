# Bootstrap tests - prove the bootstrap exit criteria:
# manifest valid, module imports, version consistent, entry parses and guards,
# Build.ps1 produces a parseable distribution.

BeforeAll {
    $script:RepoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:ManifestPath = Join-Path $script:RepoRoot 'Lamfa.psd1'
    Import-Module -Name $script:ManifestPath -Force
}

Describe 'Lamfa module bootstrap' {
    It 'has a valid module manifest' {
        Test-ModuleManifest -Path $script:ManifestPath | Should -Not -BeNullOrEmpty
    }

    It 'exports the bootstrap public surface' {
        $exported = (Get-Module -Name Lamfa).ExportedFunctions.Keys
        $exported | Should -Contain 'Lamfa-Start'
        $exported | Should -Contain 'Lamfa-GetVersion'
        $exported | Should -Contain 'Lamfa-GetBootstrapInfo'
    }

    It 'reports the same version as the manifest' {
        $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
        (Lamfa-GetVersion).ToString() | Should -Be $manifest.ModuleVersion
    }

    It 'returns a bootstrap info object with host and tool entries' {
        $info = Lamfa-GetBootstrapInfo
        $info.PowerShell | Should -Not -BeNullOrEmpty
        $info.Tools.Count | Should -Be 3
        $info.Tools.Name | Should -Contain 'Git'
    }

    It 'Lamfa-Start -SelfTest completes without waiting for input' {
        $info = Lamfa-Start -SelfTest
        $info.LamfaVersion | Should -Be (Lamfa-GetVersion)
    }
}

Describe 'Lamfa entry script' {
    BeforeAll {
        $script:EntryPath = Join-Path $script:RepoRoot 'Lamfa.ps1'
    }

    It 'parses without errors' {
        $parseErrors = $null
        $tokens = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($script:EntryPath, [ref]$tokens, [ref]$parseErrors)
        $parseErrors.Count | Should -Be 0
    }

    It 'contains the PowerShell 7 version guard' {
        # The guard itself can only fire on a 5.1 host, so assert its presence.
        (Get-Content -Path $script:EntryPath -Raw) | Should -Match 'PSVersion\.Major -lt 7'
    }
}

Describe 'Build script' {
    BeforeAll {
        $script:DistFile = Join-Path $script:RepoRoot 'dist/Lamfa.ps1'
        & (Join-Path $script:RepoRoot 'Build.ps1') | Out-Null
    }

    It 'produces dist/Lamfa.ps1' {
        Test-Path -Path $script:DistFile | Should -BeTrue
    }

    It 'produces a distribution that parses without errors' {
        $parseErrors = $null
        $tokens = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($script:DistFile, [ref]$tokens, [ref]$parseErrors)
        $parseErrors.Count | Should -Be 0
    }

    It 'stamps the generated header with the manifest version' {
        $manifest = Import-PowerShellDataFile -Path $script:ManifestPath
        (Get-Content -Path $script:DistFile -Raw) | Should -Match ([regex]::Escape($manifest.ModuleVersion))
    }

    It 'writes a checksum file that matches the distribution' {
        $checksumLine = Get-Content -Path (Join-Path $script:RepoRoot 'dist/checksums.txt') -First 1
        $expected = (Get-FileHash -Path $script:DistFile -Algorithm SHA256).Hash
        $checksumLine | Should -Match ([regex]::Escape($expected))
    }
}

# Guided dependency installation + secret vault.
BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Import-Module (Join-Path $repoRoot 'src/Core/DependencyCheck.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'src/Core/SecretVault.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'src/Core/CommandRunner.psm1') -Force -DisableNameChecking
    Import-Module (Join-Path $repoRoot 'src/Docker/DockerRegistry.psm1') -Force -DisableNameChecking
    $script:repoRoot = $repoRoot
}

Describe 'Install plans from policy' {
    It 'resolves winget and module recipes from the shipped policy' {
        $policy = Lamfa-GetDependencyPolicy -PolicyPath (Join-Path $script:repoRoot 'config/dependency-policy.json')
        (Lamfa-GetInstallPlan -Name gh -Policy $policy).Target | Should -Be 'GitHub.cli'
        (Lamfa-GetInstallPlan -Name glab -Policy $policy).Kind | Should -Be 'winget'
        (Lamfa-GetInstallPlan -Name 'Microsoft.PowerShell.SecretManagement' -Policy $policy).Kind | Should -Be 'module'
        Lamfa-GetInstallPlan -Name 'no-such-tool' -Policy $policy | Should -BeNullOrEmpty
    }
}

Describe 'Guided install consent' {
    It 'declines cleanly when the user says no - nothing runs' {
        Mock Invoke-ExternalCommand -ModuleName DependencyCheck { throw 'must not run' }
        $result = Lamfa-InstallDependency -Name gh -Prompter { param($p) 'n' }
        $result.Installed | Should -BeFalse
        $result.Detail | Should -Match 'Skipped by user choice'
        Should -Invoke Invoke-ExternalCommand -ModuleName DependencyCheck -Times 0
    }
    It 'runs winget after consent and reports based on re-detection' {
        # The winget-availability probe must be mocked so the flow is hermetic on runners without winget.
        Mock Get-Command -ModuleName DependencyCheck { [pscustomobject]@{ Name = 'winget' } } -ParameterFilter { $Name -eq 'winget' }
        Mock Invoke-ExternalCommand -ModuleName DependencyCheck {
            param($Executable, $Arguments)
            $Executable | Should -Be 'winget'
            $Arguments | Should -Contain 'GitHub.cli'
            [pscustomobject]@{ ExitCode = 0; Succeeded = $true; StandardOutput = ''; StandardError = '' }
        }
        Mock Lamfa-IsDependencyPresent -ModuleName DependencyCheck { $true }
        $result = Lamfa-InstallDependency -Name gh -Prompter { param($p) 'y' }
        $result.Installed | Should -BeTrue
        Should -Invoke Invoke-ExternalCommand -ModuleName DependencyCheck -Times 1
    }
    It 'installs modules through the isolated module-install path' {
        Mock Lamfa-InvokeModuleInstall -ModuleName DependencyCheck {
            [pscustomobject]@{ Succeeded = $true; StandardError = '' }
        }
        Mock Lamfa-IsDependencyPresent -ModuleName DependencyCheck { $true }
        $result = Lamfa-InstallDependency -Name 'Microsoft.PowerShell.SecretStore' -Prompter { param($p) 'yes' }
        $result.Installed | Should -BeTrue
        Should -Invoke Lamfa-InvokeModuleInstall -ModuleName DependencyCheck -Times 1
    }
    It 'reports missing recipes without attempting anything' {
        (Lamfa-InstallDependency -Name 'unknown-tool' -Prompter { param($p) 'y' }).Detail |
            Should -Match 'No install recipe'
    }
}

Describe 'Secret vault accessor' {
    BeforeAll {
        $script:store = @{}
        $script:fakeApi = @{
            Get    = { param($Name) if ($script:store.ContainsKey($Name)) { $script:store[$Name] } else { throw 'not found' } }
            GetRaw = { param($Name) if ($script:store.ContainsKey($Name)) { $script:store[$Name] } else { throw 'not found' } }
            Set    = { param($Name, $Value) $script:store[$Name] = $Value }
            Remove = { param($Name) $script:store.Remove($Name) }
            Vaults = { @([pscustomobject]@{ Name = 'FakeVault' }) }
        }
    }
    It 'prefixes every secret name with Lamfa/ and validates the purpose' {
        Lamfa-GetSecretName -Purpose 'registry/reg.example.com' | Should -Be 'Lamfa/registry/reg.example.com'
        { Lamfa-GetSecretName -Purpose 'bad purpose!' } | Should -Throw '*invalid characters*'
    }
    It 'stores, reads, and removes through the injected vault api' {
        Lamfa-SetSecret -Purpose 'test/one' -Value 'value-1' -VaultApi $script:fakeApi
        Lamfa-GetSecret -Purpose 'test/one' -VaultApi $script:fakeApi | Should -Be 'value-1'
        Lamfa-RemoveSecret -Purpose 'test/one' -VaultApi $script:fakeApi
        { Lamfa-GetSecret -Purpose 'test/one' -VaultApi $script:fakeApi } | Should -Throw '*not in the vault*'
    }
    It 'reports vault availability with remediation when nothing is registered' {
        $status = Lamfa-TestVaultAvailable -VaultApi @{ Vaults = { @() } }
        # module missing OR no vaults - either way unavailable with actionable text
        $status.Available | Should -BeFalse
        $status.Remediation | Should -Not -BeNullOrEmpty
    }
}

Describe 'Runner stdin + vault-backed docker login' {
    It 'pipes StandardInput to the child process' {
        $workDir = [System.IO.Path]::GetTempPath()
        $script = Join-Path $workDir "stdin-test-$([guid]::NewGuid()).ps1"
        Set-Content -Path $script -Value '$content = [Console]::In.ReadToEnd(); Write-Output "got:$content"' -Encoding utf8
        try {
            $result = Invoke-ExternalCommand -Executable pwsh -Arguments @('-NoProfile', '-File', $script) `
                -WorkingDirectory $workDir -StandardInput 'piped-secret'
            $result.StandardOutput.Trim() | Should -Be 'got:piped-secret'
            $result.SanitizedCommand | Should -Not -Match 'piped-secret'   # stdin never reaches the log line
        } finally { Remove-Item $script -Force -ErrorAction SilentlyContinue }
    }
    It 'logs in with --password-stdin using the vault credential - password never in arguments' {
        # Test-only credential; SecureString built via the .NET ctor (PSSA-clean).
        $password = [System.Security.SecureString]::new()
        foreach ($ch in 'Reg!Pass123'.ToCharArray()) { $password.AppendChar($ch) }
        $credential = [pscredential]::new('registryuser', $password)
        $fakeApi = @{
            GetRaw = { param($Name) $credential }.GetNewClosure()
            Get = { param($Name) throw 'unused' }; Set = {}; Remove = {}; Vaults = { @() }
        }
        Mock Invoke-ExternalCommand -ModuleName DockerRegistry {
            param($Executable, $Arguments, $WorkingDirectory, $Environment, $TimeoutSeconds, $CancellationToken, $StandardInput)
            ($Arguments -join ' ') | Should -Match '--password-stdin'
            ($Arguments -join ' ') | Should -Not -Match 'Reg!Pass123'
            $StandardInput | Should -Be 'Reg!Pass123'
            [pscustomobject]@{ ExitCode = 0; Succeeded = $true; StandardOutput = 'Login Succeeded'; StandardError = '' }
        }
        (Connect-DockerRegistryWithVault -Registry 'reg.example.com' -VaultApi $fakeApi).Succeeded | Should -BeTrue
    }
}

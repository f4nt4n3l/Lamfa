# Settings, diagnostics, and help menu (main-menu category 11).
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot 'ConsoleRenderer.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Platform.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'Help.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Configuration.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Logging.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Repositories/RepositoryRegistry.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/DependencyCheck.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/SecretVault.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/SelfUpdate.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'WebUi.psm1') -DisableNameChecking

function Show-SettingsMenu {
    [CmdletBinding()]
    param([Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath))
    while ($true) {
        $config = Lamfa-GetConfiguration -Path $ConfigPath
        Write-Host ''
        Write-Host 'SETTINGS, DIAGNOSTICS, AND HELP' -ForegroundColor Cyan
        Lamfa-WriteKeyValue -Key 'Mode' -Value ($(if ($config.beginnerMode) { 'Beginner (destructive operations hidden)' } else { 'ADVANCED (destructive operations visible)' }))
        Lamfa-WriteKeyValue -Key 'Config' -Value $ConfigPath
        Lamfa-WriteKeyValue -Key 'Logs' -Value (Lamfa-GetLogDirectory)
        Write-Host ''
        Write-Host '  1. Toggle Beginner/Advanced Mode   4. Show configuration'
        Write-Host '  2. Help and glossary               5. Export registry (for another machine)'
        Write-Host '  3. Open log folder                 6. Import registry'
        Write-Host '  7. Secrets (vault)                 8. Start web dashboard (local)'
        Write-Host '  9. Check for updates               0. Back'
        switch (Lamfa-ReadMenuKey -Breadcrumb @('Lamfa', 'Settings')) {
            '1' {
                if ($config.beginnerMode) {
                    Lamfa-WriteMessage -Level Warning -Text 'Advanced Mode reveals operations that can DESTROY work (force push, hard reset, volume deletion).'
                    if ((Read-Host "Type 'ADVANCED' to confirm") -cne 'ADVANCED') { Lamfa-WriteMessage -Level Info -Text 'Staying in Beginner Mode.'; continue }
                    $config.beginnerMode = $false
                } else {
                    $config.beginnerMode = $true
                }
                Lamfa-SaveConfiguration -Configuration $config -Path $ConfigPath
                Lamfa-WriteMessage -Level Success -Text "Mode changed to $(if ($config.beginnerMode) { 'Beginner' } else { 'Advanced' })."
            }
            '2' { Lamfa-ShowHelp }
            '3' { Lamfa-OpenPath -Path (Lamfa-GetLogDirectory) }
            '4' { $config | ConvertTo-Json -Depth 6 | Out-Host }
            '5' {
                $destination = Read-Host 'Export file path (e.g. D:\lamfa-registry.json)'
                if ($destination) {
                    try { Lamfa-ExportRegistry -Destination $destination -ConfigPath $ConfigPath
                          Lamfa-WriteMessage -Level Success -Text "Exported (no secrets included)." }
                    catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
                }
            }
            '6' {
                $source = Read-Host 'Import file path'
                if ($source) {
                    try {
                        $result = Lamfa-ImportRegistry -Source $source -ConfigPath $ConfigPath
                        Lamfa-WriteMessage -Level Success -Text "Imported $($result.Added) repositor$(if ($result.Added -eq 1) { 'y' } else { 'ies' })."
                        $result.Skipped | ForEach-Object { Lamfa-WriteMessage -Level Warning -Text $_ }
                    } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
                }
            }
            '7' {
                $vault = Lamfa-TestVaultAvailable
                if (-not $vault.Available) {
                    Lamfa-WriteMessage -Level Warning -Text $vault.Remediation
                    $install = Lamfa-InstallDependency -Name 'Microsoft.PowerShell.SecretManagement' -Reason 'Secrets need the SecretManagement module.'
                    Lamfa-WriteMessage -Level Info -Text $install.Detail
                    if ($install.Installed) {
                        $storeInstall = Lamfa-InstallDependency -Name 'Microsoft.PowerShell.SecretStore' -Reason 'SecretStore is the default local vault (DPAPI-protected).'
                        Lamfa-WriteMessage -Level Info -Text $storeInstall.Detail
                    }
                    continue
                }
                Lamfa-WriteKeyValue -Key 'Vaults' -Value ($vault.Vaults -join ', ')
                Write-Host '  1. Store registry credential (user + password)   2. Remove a secret'
                switch (Lamfa-ReadMenuKey -Breadcrumb @('Lamfa', 'Settings', 'Secrets')) {
                    '1' {
                        $registry = Read-Host 'Registry host (e.g. registry.company.com)'
                        if ($registry) {
                            $credential = Get-Credential -Message "Credential for $registry (stored ONLY in your vault)"
                            if ($credential) {
                                Lamfa-SetSecret -Purpose "registry/$registry" -Value $credential
                                Lamfa-WriteMessage -Level Success -Text "Stored as Lamfa/registry/$registry. Lamfa never displays it."
                            }
                        }
                    }
                    '2' {
                        $purpose = Read-Host 'Secret purpose to remove (e.g. registry/registry.company.com)'
                        if ($purpose) {
                            try { Lamfa-RemoveSecret -Purpose $purpose
                                  Lamfa-WriteMessage -Level Success -Text 'Removed.' }
                            catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
                        }
                    }
                }
            }
            '8' { Lamfa-StartWebUi -ConfigPath $ConfigPath }
            '9' {
                $manifest = Import-PowerShellDataFile -Path (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Lamfa.psd1')
                $projectUri = ''
                try { $projectUri = [string]$manifest.PrivateData.PSData.ProjectUri } catch { $projectUri = '' }
                $check = Lamfa-CheckUpdate -CurrentVersion ([version]$manifest.ModuleVersion) -ProjectUri $projectUri
                Lamfa-WriteMessage -Level ($(if ($check.UpdateAvailable) { 'Warning' } else { 'Info' })) -Text $check.Detail
                if ($check.UpdateAvailable -and (Read-Host 'Open the release page? [y/N]') -match '^(y|yes)$') {
                    Start-Process $check.ReleaseUrl
                }
            }
            '0' { return }
        }
    }
}

Export-ModuleMember -Function Show-SettingsMenu

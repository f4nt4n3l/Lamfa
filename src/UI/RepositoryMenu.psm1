# Repositories menu: list/switch/register/scan/clone/
# open/unregister/guarded delete. Deletion runs through the operation engine
# with a typed-name confirmation.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot 'ConsoleRenderer.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Platform.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Configuration.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Safety.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Repositories/RepositoryRegistry.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Repositories/RepositoryDiscovery.psm1') -DisableNameChecking

function Select-RegisteredRepository {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath))
    $repositories = @(Lamfa-GetRepositoryList -ConfigPath $ConfigPath)
    if ($repositories.Count -eq 0) { Lamfa-WriteMessage -Level Info -Text 'No repositories registered yet.'; return $null }
    for ($i = 0; $i -lt $repositories.Count; $i++) {
        Write-Host ("  {0}. {1,-28} {2}" -f ($i + 1), $repositories[$i].name, $repositories[$i].path)
    }
    $answer = Read-Host 'Number (Enter to cancel)'
    if ($answer -match '^\d+$' -and [int]$answer -ge 1 -and [int]$answer -le $repositories.Count) {
        return $repositories[[int]$answer - 1]
    }
    return $null
}

function Invoke-RegisterRepositoryFlow {
    [CmdletBinding()]
    param([Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath))
    $path = Read-Host 'Full path of the existing repository folder'
    if (-not $path) { return }
    try {
        $registration = Lamfa-AddRepository -Path $path -ConfigPath $ConfigPath
        Lamfa-WriteMessage -Level Success -Text "Registered '$($registration.name)'."
        $config = Lamfa-GetConfiguration -Path $ConfigPath
        $config.activeRepositoryId = $registration.id
        Lamfa-SaveConfiguration -Configuration $config -Path $ConfigPath
    } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
}

function Invoke-ScanRepositoriesFlow {
    [CmdletBinding()]
    param([Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath))
    $root = Read-Host 'Folder to scan (e.g. D:\Repos)'
    if (-not $root) { return }
    try {
        Lamfa-AddWorkspaceRoot -Path $root -ConfigPath $ConfigPath
        $found = @(Lamfa-FindRepository -Root $root)
        if ($found.Count -eq 0) { Lamfa-WriteMessage -Level Info -Text 'No Git repositories found there.'; return }
        Write-Host " Found $($found.Count) repositor$(if ($found.Count -eq 1) { 'y' } else { 'ies' }):"
        $found | ForEach-Object { Write-Host "   $($_.Path)" }
        if ((Read-Host 'Register all? [y/N]') -match '^(y|yes)$') {
            foreach ($repo in $found) {
                try { $null = Lamfa-AddRepository -Path $repo.Path -ConfigPath $ConfigPath }
                catch { Lamfa-WriteMessage -Level Warning -Text $_.Exception.Message }
            }
        }
    } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
}

function Invoke-CloneRepositoryFlow {
    [CmdletBinding()]
    param([Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath))
    $url = Read-Host 'Repository URL (https://... or git@...)'
    if (-not $url) { return }
    $parent = Read-Host 'Destination parent folder (e.g. D:\Repos)'
    if (-not $parent) { return }
    try {
        $registration = Lamfa-InvokeClone -Url $url -DestinationParent $parent -ConfigPath $ConfigPath
        Lamfa-WriteMessage -Level Success -Text "Cloned and registered '$($registration.name)' at $($registration.path)."
    } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
}

function Show-RepositoryMenu {
    [CmdletBinding()]
    param([Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath))
    while ($true) {
        Write-Host ''
        Write-Host 'REPOSITORIES' -ForegroundColor Cyan
        Write-Host '  1. Switch active repository     4. Clone from URL'
        Write-Host '  2. Register existing folder     5. Open in Explorer / editor'
        Write-Host '  3. Scan a folder                6. Unregister (keeps files)'
        Write-Host '  7. Delete repository folder (guarded)'
        Write-Host '  0. Back'
        switch (Lamfa-ReadMenuKey -Breadcrumb @('Lamfa', 'Repositories')) {
            '1' {
                $selected = Select-RegisteredRepository -ConfigPath $ConfigPath
                if ($selected) {
                    try { $null = Lamfa-SetActiveRepository -Id $selected.id -ConfigPath $ConfigPath; return }
                    catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
                }
            }
            '2' { Invoke-RegisterRepositoryFlow -ConfigPath $ConfigPath }
            '3' { Invoke-ScanRepositoriesFlow -ConfigPath $ConfigPath }
            '4' { Invoke-CloneRepositoryFlow -ConfigPath $ConfigPath }
            '5' {
                $selected = Select-RegisteredRepository -ConfigPath $ConfigPath
                if ($selected) {
                    Write-Host '  1. File Explorer  2. VS Code  3. Terminal here'
                    switch (Lamfa-ReadMenuKey -Breadcrumb @('Lamfa', 'Repositories', 'Open')) {
                        '1' { Lamfa-OpenPath -Path $selected.path }
                        '2' { Start-Process code -ArgumentList $selected.path -ErrorAction SilentlyContinue }
                        '3' { Start-Process pwsh -WorkingDirectory $selected.path }
                    }
                }
            }
            '6' {
                $selected = Select-RegisteredRepository -ConfigPath $ConfigPath
                if ($selected) {
                    Lamfa-WriteMessage -Level Info -Text 'Unregistering removes the entry from Lamfa only; NO files are deleted.'
                    if ((Read-Host "Unregister '$($selected.name)'? [y/N]") -match '^(y|yes)$') {
                        Lamfa-RemoveRepository -Id $selected.id -ConfigPath $ConfigPath
                        Lamfa-WriteMessage -Level Success -Text 'Unregistered.'
                    }
                }
            }
            '7' {
                $selected = Select-RegisteredRepository -ConfigPath $ConfigPath
                if ($selected) {
                    Lamfa-WriteMessage -Level Warning -Text "This DELETES the folder '$($selected.path)' (to the Recycle Bin) after safety checks: clean tree, everything pushed, remote exists."
                    $confirmed = Lamfa-RequestConfirmation -ConfirmationMode TypeTargetName -TargetName $selected.name
                    if ($confirmed) {
                        try {
                            Lamfa-RemoveRepositoryFolder -Id $selected.id -ConfigPath $ConfigPath
                            Lamfa-WriteMessage -Level Success -Text 'Deleted (recycled) and unregistered.'
                        } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
                    } else { Lamfa-WriteMessage -Level Info -Text 'Cancelled. Nothing was changed.' }
                }
            }
            '0' { return }
        }
    }
}

Export-ModuleMember -Function Show-RepositoryMenu, Select-RegisteredRepository, Invoke-RegisterRepositoryFlow, Invoke-ScanRepositoriesFlow, Invoke-CloneRepositoryFlow

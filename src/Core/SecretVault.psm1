# Secret vault integration.
# All Lamfa secrets flow through Microsoft.PowerShell.SecretManagement under
# names prefixed 'Lamfa/'. Secret VALUES never reach Lamfa files, logs,
# console output, or diagnostic bundles - only NAMES are ever logged.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot 'Logging.psm1') -DisableNameChecking

# Injectable vault API (tests replace this; the defaults resolve the real
# SecretManagement cmdlets lazily so the module loads even when they are absent).
$script:DefaultVaultApi = @{
    Get    = { param($Name) Microsoft.PowerShell.SecretManagement\Get-Secret -Name $Name -AsPlainText -ErrorAction Stop }
    GetRaw = { param($Name) Microsoft.PowerShell.SecretManagement\Get-Secret -Name $Name -ErrorAction Stop }
    Set    = { param($Name, $Value) Microsoft.PowerShell.SecretManagement\Set-Secret -Name $Name -Secret $Value -ErrorAction Stop }
    Remove = { param($Name) Microsoft.PowerShell.SecretManagement\Remove-Secret -Name $Name -ErrorAction Stop }
    Vaults = { Microsoft.PowerShell.SecretManagement\Get-SecretVault -ErrorAction Stop }
}

function Lamfa-TestVaultAvailable {
    <#
    .SYNOPSIS
        Vault readiness: SecretManagement module present AND at least
        one registered vault. Returns a status record with remediation text.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][hashtable]$VaultApi = $script:DefaultVaultApi)
    $module = Get-Module -ListAvailable -Name 'Microsoft.PowerShell.SecretManagement' | Select-Object -First 1
    if (-not $module) {
        return [pscustomobject]@{ Available = $false; Vaults = @()
            Remediation = "Install the vault modules first (Settings -> guided install): Microsoft.PowerShell.SecretManagement + Microsoft.PowerShell.SecretStore." }
    }
    $vaults = @()
    try { $vaults = @(& $VaultApi.Vaults) } catch { $vaults = @() }
    if ($vaults.Count -eq 0) {
        return [pscustomobject]@{ Available = $false; Vaults = @()
            Remediation = "No secret vault is registered. Register the default one: Register-SecretVault -Name SecretStore -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault" }
    }
    return [pscustomobject]@{ Available = $true; Vaults = @($vaults | ForEach-Object { $_.Name }); Remediation = '' }
}

function Lamfa-GetSecretName {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Purpose)
    if ($Purpose -notmatch '^[\w.\-/]+$') { throw "ValidationError: secret purpose contains invalid characters: $Purpose" }
    return "Lamfa/$Purpose"
}

function Lamfa-GetSecret {
    <#
    .SYNOPSIS
        Reads one secret by PURPOSE. -AsCredential returns the stored
        PSCredential (for user+password pairs). The value is returned to the
        caller ONLY - never logged, never displayed by this module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Purpose,
        [Parameter()][switch]$AsCredential,
        [Parameter()][hashtable]$VaultApi = $script:DefaultVaultApi
    )
    $name = Lamfa-GetSecretName -Purpose $Purpose
    try {
        if ($AsCredential) { return (& $VaultApi.GetRaw $name) }
        return (& $VaultApi.Get $name)
    } catch {
        throw "ValidationError: secret '$name' is not in the vault. Store it first (Settings -> secrets), or check Lamfa-TestVaultAvailable."
    }
}

function Lamfa-SetSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Purpose,
        [Parameter(Mandatory)][object]$Value,   # string, SecureString, or PSCredential
        [Parameter()][hashtable]$VaultApi = $script:DefaultVaultApi
    )
    $name = Lamfa-GetSecretName -Purpose $Purpose
    & $VaultApi.Set $name $Value
    Lamfa-WriteLog -Message 'secret stored' -Data @{ secretName = $name }   # name only, never the value
}

function Lamfa-RemoveSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Purpose,
        [Parameter()][hashtable]$VaultApi = $script:DefaultVaultApi
    )
    $name = Lamfa-GetSecretName -Purpose $Purpose
    & $VaultApi.Remove $name
    Lamfa-WriteLog -Message 'secret removed' -Data @{ secretName = $name }
}

Export-ModuleMember -Function Lamfa-TestVaultAvailable, Lamfa-GetSecretName, Lamfa-GetSecret, Lamfa-SetSecret, Lamfa-RemoveSecret

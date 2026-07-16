# Guided dependency installation.
# Every missing-tool path can offer a CONSENT-GATED install: Lamfa shows the
# exact command, the user decides, the command runner executes, detection
# re-runs. Nothing is ever installed silently.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot 'CommandRunner.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'Logging.psm1') -DisableNameChecking

function Lamfa-GetDependencyPolicy {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][string]$PolicyPath = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'config/dependency-policy.json'))
    if (-not (Test-Path -LiteralPath $PolicyPath)) {
        throw "ConfigurationError: dependency policy not found: $PolicyPath"
    }
    return (Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json)
}

function Lamfa-GetInstallPlan {
    <#
    .SYNOPSIS
        Resolves HOW a dependency would be installed: winget package or
        PowerShell module. Returns $null when the policy has no recipe.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][AllowNull()][object]$Policy = $null
    )
    if ($null -eq $Policy) { $Policy = Lamfa-GetDependencyPolicy }
    $installProperty = $Policy.PSObject.Properties['install']
    if (-not $installProperty -or $null -eq $installProperty.Value) { return $null }
    $recipeProperty = $installProperty.Value.PSObject.Properties[$Name]
    if (-not $recipeProperty) { return $null }
    $recipe = $recipeProperty.Value
    if ($recipe.PSObject.Properties['winget'] -and $recipe.winget) {
        return [pscustomobject]@{
            PSTypeName = 'Lamfa.InstallPlan'; Name = $Name; Kind = 'winget'
            Target = [string]$recipe.winget
            CommandText = "winget install --id $($recipe.winget) --source winget --accept-source-agreements --accept-package-agreements"
        }
    }
    if ($recipe.PSObject.Properties['module'] -and $recipe.module) {
        return [pscustomobject]@{
            PSTypeName = 'Lamfa.InstallPlan'; Name = $Name; Kind = 'module'
            Target = [string]$recipe.module
            CommandText = "Install-PSResource -Name $($recipe.module) -Scope CurrentUser -TrustRepository"
        }
    }
    return $null
}

function Lamfa-InstallDependency {
    <#
    .SYNOPSIS
        The universal missing-tool flow: explains what is missing,
        shows the EXACT command, asks for consent, installs, re-detects.
    .PARAMETER Prompter
        Injectable consent input for tests; must answer y/yes to proceed.
    .OUTPUTS
        @{ Installed(bool); Detail(string) }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][AllowEmptyString()][string]$Reason = '',
        [Parameter()][AllowNull()][object]$Policy = $null,
        [Parameter()][scriptblock]$Prompter = { param($PromptText) Read-Host -Prompt $PromptText }
    )
    $plan = Lamfa-GetInstallPlan -Name $Name -Policy $Policy
    if ($null -eq $plan) {
        return [pscustomobject]@{ Installed = $false
            Detail = "No install recipe is defined for '$Name' - install it manually." }
    }
    if ($Reason) { Write-Host " $Reason" }
    Write-Host " '$Name' is not installed. Lamfa can install it now by running:" -ForegroundColor Yellow
    Write-Host "   $($plan.CommandText)" -ForegroundColor White
    $answer = [string](& $Prompter "Install '$Name' now? Type y to install, anything else skips")
    if ($answer -notmatch '^(y|yes)$') {
        Lamfa-WriteLog -Message 'guided install declined' -Data @{ dependency = $Name }
        return [pscustomobject]@{ Installed = $false; Detail = 'Skipped by user choice. Nothing was installed.' }
    }

    if ($plan.Kind -eq 'winget') {
        $winget = Get-Command -Name winget -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $winget) {
            return [pscustomobject]@{ Installed = $false
                Detail = 'winget itself is not available; install the tool manually or install App Installer from the Microsoft Store.' }
        }
        $result = Invoke-ExternalCommand -Executable winget `
            -Arguments @('install', '--id', $plan.Target, '--source', 'winget', '--accept-source-agreements', '--accept-package-agreements') `
            -WorkingDirectory ([System.IO.Path]::GetTempPath()) -TimeoutSeconds 1800
        # winget exit 0 = installed; specific non-zero codes mean already-installed - re-detection decides.
    } else {
        $result = Lamfa-InvokeModuleInstall -ModuleName $plan.Target
    }

    $detected = Lamfa-IsDependencyPresent -Name $Name -Kind $plan.Kind -Target $plan.Target
    Lamfa-WriteLog -Message 'guided install finished' -Data @{ dependency = $Name; detected = $detected }
    if ($detected) {
        return [pscustomobject]@{ Installed = $true; Detail = "'$Name' is now available." }
    }
    return [pscustomobject]@{ Installed = $false
        Detail = "The install command ran but '$Name' is still not detectable - a new terminal session may be needed for PATH changes. $($result.StandardError)".Trim() }
}

function Lamfa-InvokeModuleInstall {
    # Isolated so tests can mock module installation without touching the machine.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$ModuleName)
    try {
        Install-PSResource -Name $ModuleName -Scope CurrentUser -TrustRepository -ErrorAction Stop
        return [pscustomobject]@{ Succeeded = $true; StandardError = '' }
    } catch {
        return [pscustomobject]@{ Succeeded = $false; StandardError = $_.Exception.Message }
    }
}

function Lamfa-IsDependencyPresent {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][ValidateSet('winget', 'module')][string]$Kind = 'winget',
        [Parameter()][AllowEmptyString()][string]$Target = ''
    )
    if ($Kind -eq 'module') {
        return $null -ne (Get-Module -ListAvailable -Name $Target | Select-Object -First 1)
    }
    return $null -ne (Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
}

Export-ModuleMember -Function Lamfa-GetDependencyPolicy, Lamfa-GetInstallPlan, Lamfa-InstallDependency, Lamfa-InvokeModuleInstall, Lamfa-IsDependencyPresent

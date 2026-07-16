# Configuration - global configuration loading, validation,
# and persistence. The embedded defaults below are the
# source of truth; config/default-config.json documents the same shape for users.
# (Embedded because the generated single-file distribution ships without config/.)
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot 'Platform.psm1') -DisableNameChecking

function Lamfa-GetConfigDirectory {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $directory = Lamfa-GetAppDataRoot
    # One-time migration from the pre-rename location: copy, never delete.
    $legacy = if ($IsWindows) { Join-Path $env:LOCALAPPDATA 'RepoTool' } else { $null }
    if ($legacy -and -not (Test-Path -LiteralPath $directory) -and (Test-Path -LiteralPath $legacy)) {
        try { Copy-Item -LiteralPath $legacy -Destination $directory -Recurse -Force } catch { $null = $_ }
    }
    return $directory
}

function Lamfa-GetConfigPath {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter()][string]$ConfigDirectory = (Lamfa-GetConfigDirectory))
    return Join-Path $ConfigDirectory 'config.json'
}

function Lamfa-GetDefaultConfiguration {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()
    return [pscustomobject]@{
        schemaVersion      = 1
        beginnerMode       = $true
        activeRepositoryId = $null
        workspaceRoots     = @()
        repositories       = @()
        preferences        = [pscustomobject]@{
            openEditorCommand           = 'code'
            fetchFreshnessMinutes       = 15
            showCommandsBeforeExecution = $true
            pauseAfterErrors            = $true
        }
        # Features that have not been through real-world acceptance yet.
        experimentalFeatures = [pscustomobject]@{
            webUi = $false
        }
    }
}

function Lamfa-ConvertConfiguration {
    <#
    .SYNOPSIS
        Migrates an older/partial configuration document to the current schema
       . Missing properties are filled from defaults; unknown FUTURE
        schema versions are refused with a clear error instead of guessed at.
    .OUTPUTS
        @{ Configuration; Migrated(bool); Notes(string[]) }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][AllowNull()][object]$Configuration)

    $notes = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Configuration) {
        return [pscustomobject]@{ Configuration = (Lamfa-GetDefaultConfiguration); Migrated = $true
            Notes = @('Empty configuration replaced with defaults.') }
    }
    $versionProperty = $Configuration.PSObject.Properties['schemaVersion']
    $version = if ($versionProperty) { [int]$Configuration.schemaVersion } else { 0 }
    if ($version -gt 1) {
        throw "ConfigurationError: config schemaVersion $version is NEWER than this Lamfa understands (1). Update Lamfa instead of downgrading the file."
    }
    $migrated = $false
    $defaults = Lamfa-GetDefaultConfiguration
    foreach ($property in $defaults.PSObject.Properties) {
        if ($null -eq $Configuration.PSObject.Properties[$property.Name]) {
            $Configuration | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
            $notes.Add("Added missing '$($property.Name)' with its default value.")
            $migrated = $true
        }
    }
    if ($version -lt 1) {
        $Configuration.schemaVersion = 1
        $notes.Add('Stamped schemaVersion 1.')
        $migrated = $true
    }
    return [pscustomobject]@{ Configuration = $Configuration; Migrated = $migrated; Notes = $notes.ToArray() }
}

function Lamfa-TestConfiguration {
    <#
    .SYNOPSIS
        Validates a configuration object. Returns a list of human-actionable error
        strings (empty list = valid). Every error names the property, the expected
        shape, the actual value, and the recovery step.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Configuration,
        [Parameter()][string]$SourceDescription = 'configuration'
    )

    $problems = [System.Collections.Generic.List[string]]::new()
    $recovery = 'Fix the property in the file, or delete the file so Lamfa recreates defaults.'

    if ($null -eq $Configuration) {
        $problems.Add("$($SourceDescription): content is empty or not valid JSON. $recovery")
        return ,$problems.ToArray()
    }

    function HasProperty([object]$Object, [string]$Name) {
        return $null -ne ($Object.PSObject.Properties | Where-Object Name -eq $Name)
    }

    if (-not (HasProperty $Configuration 'schemaVersion') -or $Configuration.schemaVersion -ne 1) {
        $actual = if (HasProperty $Configuration 'schemaVersion') { $Configuration.schemaVersion } else { '(missing)' }
        $problems.Add("$($SourceDescription): 'schemaVersion' must be 1, found '$actual'. $recovery")
    }
    if (-not (HasProperty $Configuration 'beginnerMode') -or $Configuration.beginnerMode -isnot [bool]) {
        $problems.Add("$($SourceDescription): 'beginnerMode' must be true or false. $recovery")
    }
    foreach ($listProperty in @('workspaceRoots', 'repositories')) {
        if (-not (HasProperty $Configuration $listProperty) -or
            ($null -ne $Configuration.$listProperty -and $Configuration.$listProperty -isnot [array] -and $Configuration.$listProperty -isnot [System.Collections.IEnumerable])) {
            $problems.Add("$($SourceDescription): '$listProperty' must be a JSON array. $recovery")
        }
    }
    if (-not (HasProperty $Configuration 'preferences') -or $null -eq $Configuration.preferences) {
        $problems.Add("$($SourceDescription): 'preferences' object is missing. $recovery")
    }
    return ,$problems.ToArray()
}

function Lamfa-GetConfiguration {
    <#
    .SYNOPSIS
        Loads the user configuration; returns embedded defaults when no user file
        exists yet. An invalid user file throws a ConfigurationError-style message
        listing every problem - generic functionality must fail loudly, not guess.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][string]$Path = (Lamfa-GetConfigPath))

    if (-not (Test-Path -Path $Path)) {
        return Lamfa-GetDefaultConfiguration
    }
    $parsed = $null
    try {
        $parsed = Get-Content -Path $Path -Raw | ConvertFrom-Json
    } catch {
        throw "ConfigurationError: '$Path' is not valid JSON ($($_.Exception.Message)). Fix the JSON, or delete the file so Lamfa recreates defaults."
    }
    $migration = Lamfa-ConvertConfiguration -Configuration $parsed
    if ($migration.Migrated) {
        Lamfa-SaveConfiguration -Configuration $migration.Configuration -Path $Path
    }
    $parsed = $migration.Configuration
    $problems = Lamfa-TestConfiguration -Configuration $parsed -SourceDescription $Path
    if ($problems.Count -gt 0) {
        throw ("ConfigurationError: invalid configuration.`n" + ($problems -join "`n"))
    }
    return $parsed
}

function Lamfa-SaveConfiguration {
    <#
    .SYNOPSIS
        Validates and persists the configuration as pretty-printed JSON. Refuses
        to write an invalid object - a broken file must never reach disk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Configuration,
        [Parameter()][string]$Path = (Lamfa-GetConfigPath)
    )
    $problems = Lamfa-TestConfiguration -Configuration $Configuration -SourceDescription 'configuration to save'
    if ($problems.Count -gt 0) {
        throw ("ConfigurationError: refusing to save invalid configuration.`n" + ($problems -join "`n"))
    }
    $directory = Split-Path -Path $Path -Parent
    if (-not (Test-Path -Path $directory)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }
    Set-Content -Path $Path -Value ($Configuration | ConvertTo-Json -Depth 8) -Encoding utf8
}

Export-ModuleMember -Function Lamfa-GetConfigDirectory, Lamfa-GetConfigPath, Lamfa-GetDefaultConfiguration, Lamfa-ConvertConfiguration, Lamfa-TestConfiguration, Lamfa-GetConfiguration, Lamfa-SaveConfiguration

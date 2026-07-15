# Repository registry.
# Registrations live in the global configuration; the active repository context
# is produced here and enriched by the Git modules.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Platform.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Configuration.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Models/RepositoryContext.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'RepositoryValidation.psm1') -DisableNameChecking

function Lamfa-GetRepositoryList {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath))
    $config = Lamfa-GetConfiguration -Path $ConfigPath
    return @($config.repositories)
}

function Lamfa-AddRepository {
    <#
    .SYNOPSIS
        Registers an existing local folder. Rejects duplicates by normalized path
        and by name. Returns the new registration record.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][AllowEmptyString()][string]$Name = '',
        [Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath)
    )
    $validation = Lamfa-TestRepository -Path $Path
    if (-not $validation.Exists) { throw "ValidationError: folder does not exist: $Path" }
    $normalized = $validation.Path
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = Split-Path -Path $normalized -Leaf }

    $config = Lamfa-GetConfiguration -Path $ConfigPath
    foreach ($existing in @($config.repositories)) {
        if (Test-SamePath $existing.path $normalized) {
            throw "ValidationError: this folder is already registered as '$($existing.name)'."
        }
        if ($existing.name -ieq $Name) {
            throw "ValidationError: a repository named '$Name' is already registered. Choose another name."
        }
    }
    $registration = [pscustomobject]@{
        id              = [guid]::NewGuid().ToString()
        name            = $Name
        path            = $normalized
        provider        = $null
        profilePath     = '.lamfa.json'
        preferredRemote = 'origin'
        lastOpenedUtc   = $null
    }
    $config.repositories = @($config.repositories) + $registration
    Lamfa-SaveConfiguration -Configuration $config -Path $ConfigPath
    return $registration
}

function Lamfa-RemoveRepository {
    <#
    .SYNOPSIS
        Unregisters a repository WITHOUT touching any files on disk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath)
    )
    $config = Lamfa-GetConfiguration -Path $ConfigPath
    $remaining = @($config.repositories | Where-Object { $_.id -ne $Id })
    if ($remaining.Count -eq @($config.repositories).Count) {
        throw "ValidationError: no registered repository has id '$Id'."
    }
    $config.repositories = $remaining
    if ($config.activeRepositoryId -eq $Id) { $config.activeRepositoryId = $null }
    Lamfa-SaveConfiguration -Configuration $config -Path $ConfigPath
}

function Lamfa-AddWorkspaceRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath)
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "ValidationError: workspace root does not exist: $Path"
    }
    $normalized = Get-NormalizedPath $Path
    $config = Lamfa-GetConfiguration -Path $ConfigPath
    foreach ($root in @($config.workspaceRoots)) {
        if (Test-SamePath $root $normalized) { return }
    }
    $config.workspaceRoots = @($config.workspaceRoots) + $normalized
    Lamfa-SaveConfiguration -Configuration $config -Path $ConfigPath
}

function Lamfa-SetActiveRepository {
    <#
    .SYNOPSIS
        Sets the active repository and returns a fresh RepositoryContext for it
       . Refuses ids whose folder no longer exists.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath)
    )
    $config = Lamfa-GetConfiguration -Path $ConfigPath
    $registration = @($config.repositories) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $registration) { throw "ValidationError: no registered repository has id '$Id'." }
    $validation = Lamfa-TestRepository -Path $registration.path
    if (-not $validation.Exists) {
        throw "ValidationError: registered folder no longer exists: $($registration.path). Re-register it with its new location."
    }
    $config.activeRepositoryId = $Id
    $registration.lastOpenedUtc = [DateTime]::UtcNow.ToString('o')
    Lamfa-SaveConfiguration -Configuration $config -Path $ConfigPath

    return New-RepositoryContext -Id $registration.id -Name $registration.name -Path $validation.Path `
        -IsGitRepository $validation.IsGitRepository -GitDirectory $validation.GitDirectory `
        -PreferredRemote $registration.preferredRemote
}

function Lamfa-InvokeClone {
    <#
    .SYNOPSIS
        Clones a repository (HTTPS, SSH, or local source) into DestinationParent
        and registers it. Enforces the section 16.3 preconditions.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$DestinationParent,
        [Parameter()][AllowEmptyString()][string]$Name = '',
        [Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath)
    )
    $looksHttps = $Url -match '^https://\S+'
    $looksSsh = $Url -match '^(ssh://\S+|[\w.-]+@[\w.-]+:\S+)'
    $looksLocal = (Test-Path -LiteralPath $Url) -or ($Url -match '^[A-Za-z]:\\')
    if (-not ($looksHttps -or $looksSsh -or $looksLocal)) {
        throw "ValidationError: '$Url' is not an HTTPS, SSH, or local repository source."
    }
    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = ([regex]::Match($Url, '([^/\\:]+?)(\.git)?/?$')).Groups[1].Value
    }
    if ($Name -notmatch '^[\w][\w.\- ]*$') { throw "ValidationError: '$Name' is not a valid repository folder name." }
    if (-not (Test-Path -LiteralPath $DestinationParent -PathType Container)) {
        throw "ValidationError: destination parent does not exist: $DestinationParent"
    }
    $destination = Join-Path (Get-NormalizedPath $DestinationParent) $Name
    if (Test-Path -LiteralPath $destination) {
        if (@(Get-ChildItem -LiteralPath $destination -Force -ErrorAction SilentlyContinue).Count -gt 0) {
            throw "ValidationError: destination already exists and is not empty: $destination"
        }
    }
    $config = Lamfa-GetConfiguration -Path $ConfigPath
    foreach ($existing in @($config.repositories)) {
        if (Test-SamePath $existing.path $destination) {
            throw "ValidationError: destination is already registered as '$($existing.name)'."
        }
    }
    $result = Invoke-ExternalCommand -Executable git -Arguments @('clone', '--', $Url, $destination) `
        -WorkingDirectory $DestinationParent -TimeoutSeconds 3600
    if (-not $result.Succeeded) {
        throw "ExternalCommandError: git clone failed. $($result.StandardError)"
    }
    return Lamfa-AddRepository -Path $destination -Name $Name -ConfigPath $ConfigPath
}

function Lamfa-RemoveRepositoryFolder {
    <#
    .SYNOPSIS
        Guarded local repository folder deletion. Refuses on ANY unsafe
        signal (section 16.4); the caller runs it through the operation engine
        with a typed-name confirmation. Recycles instead of permanent deletion.
    .PARAMETER Force
        Skips only the workspace-root membership requirement (path may live
        outside approved roots) - never skips the safety checks themselves.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath),
        [Parameter()][switch]$Force
    )
    $config = Lamfa-GetConfiguration -Path $ConfigPath
    $registration = @($config.repositories) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $registration) { throw "ValidationError: no registered repository has id '$Id'." }
    $path = $registration.path

    $blockers = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { $blockers.Add('The folder does not exist on disk.') }
    if (Test-IsDriveRoot $path) { $blockers.Add('The path is a drive root and can never be deleted by Lamfa.') }
    foreach ($root in @($config.workspaceRoots)) {
        if (Test-SamePath $root $path) { $blockers.Add('The path IS a workspace root, not a repository inside one.') }
    }
    if (-not $Force) {
        $insideAny = $false
        foreach ($root in @($config.workspaceRoots)) {
            if ((Test-PathInsideRoot -Path $path -Root $root) -and -not (Test-SamePath $root $path)) { $insideAny = $true }
        }
        if (-not $insideAny) { $blockers.Add('The path is outside every approved workspace root (use the explicit override only if you are certain).') }
    }
    if ($blockers.Count -eq 0) {
        $validation = Lamfa-TestRepository -Path $path
        if (-not $validation.IsGitRepository) {
            $blockers.Add('The folder is not a verified Git repository; Lamfa cannot prove it is safely backed up.')
        } else {
            $status = Invoke-ExternalCommand -Executable git -Arguments @('status', '--porcelain') -WorkingDirectory $path
            if (-not $status.Succeeded) { $blockers.Add('Git state could not be checked; deletion is refused when safety cannot be proven.') }
            elseif (-not [string]::IsNullOrWhiteSpace($status.StandardOutput)) { $blockers.Add('Uncommitted, staged, or untracked files exist - they would be lost forever.') }

            $remotes = Invoke-ExternalCommand -Executable git -Arguments @('remote') -WorkingDirectory $path
            if (-not $remotes.Succeeded -or [string]::IsNullOrWhiteSpace($remotes.StandardOutput)) {
                $blockers.Add('No remote exists - the history exists nowhere else.')
            } else {
                $unpushed = Invoke-ExternalCommand -Executable git -Arguments @('log', '--branches', '--not', '--remotes', '--oneline') -WorkingDirectory $path
                if (-not $unpushed.Succeeded) { $blockers.Add('Unpushed-commit state could not be checked; deletion is refused.') }
                elseif (-not [string]::IsNullOrWhiteSpace($unpushed.StandardOutput)) { $blockers.Add('Commits exist that were never pushed to any remote - they would be lost forever.') }
            }
            $worktrees = Invoke-ExternalCommand -Executable git -Arguments @('worktree', 'list', '--porcelain') -WorkingDirectory $path
            if ($worktrees.Succeeded -and (@($worktrees.StandardOutput -split "`n" | Where-Object { $_ -like 'worktree *' }).Count -gt 1)) {
                $blockers.Add('Linked worktrees exist under this repository; remove them first.')
            }
        }
    }
    if ($blockers.Count -gt 0) {
        throw ("PreconditionError: deletion refused.`n- " + ($blockers -join "`n- "))
    }

    # Reversible by design: recycle/trash, never a permanent delete.
    Lamfa-SendToRecycle -Path $path
    Lamfa-RemoveRepository -Id $Id -ConfigPath $ConfigPath
}


function Lamfa-UpdateFetchFreshness {
    <#
    .SYNOPSIS
        Silent auto-fetch: fetches the preferred remote when the last
        fetch is older than preferences.fetchFreshnessMinutes, so the dashboard
        ahead/behind numbers stay honest. Returns $true when a fetch ran.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Context,
        [Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath)
    )
    if (-not $Context.IsGitRepository -or @($Context.Remotes).Count -eq 0) { return $false }
    $config = Lamfa-GetConfiguration -Path $ConfigPath
    $registration = @($config.repositories) | Where-Object { $_.id -eq $Context.Id } | Select-Object -First 1
    if (-not $registration) { return $false }
    $minutes = 15
    $preference = $config.preferences.PSObject.Properties['fetchFreshnessMinutes']
    if ($preference -and [int]$preference.Value -gt 0) { $minutes = [int]$preference.Value }
    $lastProperty = $registration.PSObject.Properties['lastFetchUtc']
    if ($lastProperty -and $lastProperty.Value) {
        # ConvertFrom-Json may hand back a [datetime] (local kind) or the ISO string.
        $raw = $lastProperty.Value
        $last = if ($raw -is [datetime]) { $raw.ToUniversalTime() }
        else { [DateTimeOffset]::Parse([string]$raw, [cultureinfo]::InvariantCulture).UtcDateTime }
        if (([DateTime]::UtcNow - $last).TotalMinutes -lt $minutes) { return $false }
    }
    $remoteName = if ($Context.PreferredRemote) { $Context.PreferredRemote } else { 'origin' }
    $fetch = Invoke-ExternalCommand -Executable git -Arguments @('fetch', '--prune', $remoteName) `
        -WorkingDirectory $Context.Path -TimeoutSeconds 120 -AllowNonZeroExitCode
    if (-not $lastProperty) {
        $registration | Add-Member -NotePropertyName lastFetchUtc -NotePropertyValue $null
    }
    $registration.lastFetchUtc = [DateTime]::UtcNow.ToString('o')
    Lamfa-SaveConfiguration -Configuration $config -Path $ConfigPath
    return $fetch.Succeeded
}

function Lamfa-ExportRegistry {
    <#
    .SYNOPSIS
        Portable export of workspace roots, registrations, and preferences
        - for moving to another machine. Contains no secrets.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Destination,
        [Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath)
    )
    $config = Lamfa-GetConfiguration -Path $ConfigPath
    $export = [pscustomobject]@{
        schemaVersion  = 1
        exportedUtc    = [DateTime]::UtcNow.ToString('o')
        workspaceRoots = @($config.workspaceRoots)
        repositories   = @($config.repositories)
        preferences    = $config.preferences
    }
    Set-Content -Path $Destination -Value ($export | ConvertTo-Json -Depth 8) -Encoding utf8
}

function Lamfa-ImportRegistry {
    <#
    .SYNOPSIS
        Merges an exported registry into the local configuration:
        duplicate paths/names are skipped, folders missing on THIS machine are
        reported and skipped. Returns a summary record.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath)
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "ValidationError: export file not found: $Source"
    }
    $export = Get-Content -LiteralPath $Source -Raw | ConvertFrom-Json
    $added = 0
    $skipped = [System.Collections.Generic.List[string]]::new()
    foreach ($root in @($export.workspaceRoots)) {
        if (Test-Path -LiteralPath $root -PathType Container) {
            Lamfa-AddWorkspaceRoot -Path $root -ConfigPath $ConfigPath
        } else { $skipped.Add("workspace root missing on this machine: $root") }
    }
    foreach ($repository in @($export.repositories)) {
        if (-not (Test-Path -LiteralPath $repository.path -PathType Container)) {
            $skipped.Add("folder missing on this machine: $($repository.path)")
            continue
        }
        try {
            $null = Lamfa-AddRepository -Path $repository.path -Name $repository.name -ConfigPath $ConfigPath
            $added++
        } catch { $skipped.Add($_.Exception.Message) }
    }
    return [pscustomobject]@{
        PSTypeName = 'Lamfa.RegistryImportResult'
        Added      = $added
        Skipped    = $skipped.ToArray()
    }
}

Export-ModuleMember -Function Lamfa-GetRepositoryList, Lamfa-AddRepository, Lamfa-RemoveRepository, Lamfa-AddWorkspaceRoot, Lamfa-SetActiveRepository, Lamfa-InvokeClone, Lamfa-RemoveRepositoryFolder, Lamfa-UpdateFetchFreshness, Lamfa-ExportRegistry, Lamfa-ImportRegistry

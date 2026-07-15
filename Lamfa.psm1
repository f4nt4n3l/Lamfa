# Lamfa root module - bootstrap surface.
# Loads sub-modules from src/ and exposes the public functions declared in Lamfa.psd1.
Set-StrictMode -Version 3.0

# Single version constant so the generated single-file distribution (which has no
# .psd1 next to it) reports the same version. A bootstrap test asserts this value
# matches Lamfa.psd1.
$script:LamfaVersion = '0.1.0'

Import-Module -Name (Join-Path $PSScriptRoot 'src/UI/ConsoleRenderer.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Models/CommandResult.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Models/DependencyStatus.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Models/RepositoryContext.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Models/OperationDefinition.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Core/Platform.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Core/Logging.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Core/CommandRunner.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Core/Configuration.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Core/DependencyCheck.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Core/SelfUpdate.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Core/SecretVault.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Core/Preconditions.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Core/Safety.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Core/OperationEngine.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Repositories/RepositoryValidation.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Repositories/RepositoryRegistry.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Repositories/RepositoryDiscovery.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Git/GitStatus.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Git/GitBranches.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Git/GitRemotes.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Git/GitCommits.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Git/GitDiff.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Git/GitHistory.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Git/GitStash.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Git/GitTags.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Git/GitWorktrees.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Git/GitRepository.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Git/GitRecovery.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Git/GitHunks.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Git/GitUndo.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Git/GitInsights.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Providers/GenericRemote.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Providers/GitHub/GitHubAuth.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Providers/GitHub/GitHubRepositories.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Providers/GitHub/GitHubPullRequests.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Providers/GitHub/GitHubReviews.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Providers/GitLab/GitLabAdapter.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Providers/Gitea/GiteaAdapter.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Providers/Bitbucket/BitbucketAdapter.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Workflows/ProfileLoader.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Workflows/ProjectDetection.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Workflows/WorkflowEngine.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Workflows/ReleaseTools.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Workflows/ReleaseOrchestrator.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Providers/ProviderAdapter.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Core/State.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Docker/DockerEnvironment.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Docker/DockerImages.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Docker/DockerContainers.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Docker/DockerCompose.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Docker/DockerRegistry.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/UI/Help.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/UI/RepositoryMenu.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/UI/GitMenu.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/UI/GitHubMenu.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/UI/DockerMenu.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/UI/SettingsMenu.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/UI/MainMenu.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/Core/ApiFacade.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/UI/WebUi.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'src/UI/LamfaCli.psm1') -Force -DisableNameChecking

function Lamfa-GetVersion {
    [CmdletBinding()]
    [OutputType([version])]
    param()
    return [version]$script:LamfaVersion
}

function Lamfa-GetBootstrapInfo {
    <#
    .SYNOPSIS
        Collects the informational bootstrap snapshot: Lamfa version, host, and
        whether the optional external tools are on PATH.
    .NOTES
        Informational display only.
    #>
    [CmdletBinding()]
    param()

    $tools = foreach ($tool in @(
            @{ Name = 'Git';        Executable = 'git' },
            @{ Name = 'GitHub CLI'; Executable = 'gh' },
            @{ Name = 'Docker';     Executable = 'docker' })) {
        $command = Get-Command -Name $tool.Executable -CommandType Application -ErrorAction SilentlyContinue
        $versionText = $null
        if ($command) {
            try {
                $versionText = (& $tool.Executable '--version' 2>$null | Select-Object -First 1)
            } catch {
                $versionText = 'version query failed'
            }
        }
        [pscustomobject]@{
            Name      = $tool.Name
            Installed = [bool]$command
            Version   = $versionText
        }
    }

    return [pscustomobject]@{
        LamfaVersion = Lamfa-GetVersion
        PowerShell      = $PSVersionTable.PSVersion
        Tools           = $tools
    }
}

function Lamfa-Start {
    <#
    .SYNOPSIS
        Entry point: renders the dashboard and starts the interactive menus.
    .PARAMETER SelfTest
        Renders the dashboard without waiting for input and returns the bootstrap
        info object. Used by CI and the bootstrap tests.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Renders the console dashboard only; changes no system state.')]
    [CmdletBinding()]
    param([switch]$SelfTest)

    # Application exception boundary: an unexpected error inside the
    # session renders a consistent error screen and returns instead of crashing
    # the host and destroying session state.
    try {
        return Lamfa-InvokeSession -SelfTest:$SelfTest
    } catch {
        Lamfa-WriteMessage -Level Error -Text "Unexpected error: $($_.Exception.Message)"
        Lamfa-WriteMessage -Level Info -Text "Nothing further was executed. Details were logged to: $(Lamfa-GetLogDirectory)"
        Lamfa-WriteLog -Level Error -Message 'unexpected session error' -Data @{
            error = $_.Exception.ToString()
        }
        return $null
    }
}

function Lamfa-InvokeSession {
    [CmdletBinding()]
    param([switch]$SelfTest)

    $info = Lamfa-GetBootstrapInfo

    Lamfa-WriteHeader -Text "Lamfa $($info.LamfaVersion) - bootstrap"
    Write-Host ''
    Write-Host ' Environment' -ForegroundColor White
    Lamfa-WriteKeyValue -Key 'PowerShell' -Value $info.PowerShell.ToString()
    foreach ($tool in $info.Tools) {
        $value = if ($tool.Installed) { $tool.Version } else { 'not found on PATH' }
        Lamfa-WriteKeyValue -Key $tool.Name -Value $value
    }
    if ($SelfTest) {
        Write-Host ''
        Lamfa-WriteMessage -Level Info -Text 'Self-test mode: dashboard rendered, menus skipped.'
        return $info
    }

    Lamfa-StartMainMenu
}

Export-ModuleMember -Function Lamfa-GetVersion, Lamfa-GetBootstrapInfo, Lamfa-Start, Lamfa

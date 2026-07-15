# The lamfa-first command surface: git-style subcommands so
# daily use is as short as possible - 'lamfa', 'lamfa status', 'lamfa push',
# 'lamfa pr', 'lamfa doctor'. Everything dispatches into the SAME tested
# engine/menus; this file adds no logic of its own.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot 'ConsoleRenderer.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'MainMenu.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'RepositoryMenu.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitMenu.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitHubMenu.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'DockerMenu.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'SettingsMenu.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Configuration.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Repositories/RepositoryRegistry.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitRepository.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitStatus.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitRemotes.psm1') -DisableNameChecking

$script:Subcommands = [ordered]@{
    ''         = 'Open the interactive menu (default)'
    'status'   = 'Working-tree status of the active repository'
    'fetch'    = 'Fetch the preferred remote'
    'pull'     = 'Safe pull (fast-forward only)'
    'push'     = 'Push with exact-target preview + confirmation'
    'commit'   = 'Commit wizard (select files -> review -> commit)'
    'branch'   = 'Branches and worktrees menu'
    'repos'    = 'Repositories menu (switch/register/scan/clone)'
    'pr'       = 'Pull requests menu (provider-neutral)'
    'docker'   = 'Docker menu'
    'release'  = 'Release menu (gates -> tag -> publish -> docker)'
    'recover'  = 'Recovery guidance + bundle backup'
    'accounts' = 'Git identity / provider accounts / environment report'
    'settings' = 'Settings, secrets, help'
    'doctor'   = 'Dependency + environment health check'
    'help'     = 'This list'
}

function Lamfa-GetCliContext {
    # Resolves the active repository context exactly like the main menu does.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath))
    $config = Lamfa-GetConfiguration -Path $ConfigPath
    if (-not $config.activeRepositoryId) { return $null }
    try {
        $context = Lamfa-SetActiveRepository -Id $config.activeRepositoryId -ConfigPath $ConfigPath
        return (Lamfa-UpdateRepositoryContext -Context $context)
    } catch {
        Lamfa-WriteMessage -Level Warning -Text $_.Exception.Message
        return $null
    }
}

function Lamfa {
    <#
    .SYNOPSIS
        The lamfa command. 'lamfa' opens the menu; 'lamfa <subcommand>'
        jumps straight to the matching flow. 'lamfa help' lists everything.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][AllowEmptyString()][string]$Command = '',
        [Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath)
    )
    $config = Lamfa-GetConfiguration -Path $ConfigPath
    $beginner = [bool]$config.beginnerMode
    $context = $null
    if ($Command -notin @('', 'help', 'repos', 'settings', 'doctor')) {
        $context = Lamfa-GetCliContext -ConfigPath $ConfigPath
    }
    switch ($Command.ToLowerInvariant()) {
        ''         { Lamfa-Start }
        'status'   {
            if (-not (Test-MenuContext $context)) { return }
            $status = Get-GitStatus -Path $context.Path
            Write-Host "$($context.Name) on $($status.Branch)  (ahead $($status.Ahead ?? '-') / behind $($status.Behind ?? '-'))"
            if ($status.IsClean) { Lamfa-WriteMessage -Level Success -Text 'Working tree clean.' }
            foreach ($entry in $status.Entries) {
                Write-Host ("  [{0}{1}] {2,-10} {3}" -f $entry.IndexState, $entry.WorktreeState, $entry.Kind, $entry.Path)
            }
        }
        'fetch'    {
            if (-not (Test-MenuContext $context)) { return }
            $result = Invoke-GitFetch -Path $context.Path
            Lamfa-WriteMessage -Level ($(if ($result.Succeeded) { 'Success' } else { 'Error' })) `
                -Text ($(if ($result.Succeeded) { 'Fetched.' } else { $result.StandardError }))
        }
        'pull'     {
            if (-not (Test-MenuContext $context)) { return }
            $pull = Invoke-GitPull -Path $context.Path
            Lamfa-WriteMessage -Level ($(if ($pull.Outcome -in @('FastForwarded', 'UpToDate')) { 'Success' } else { 'Warning' })) `
                -Text "$($pull.Outcome): $($pull.Detail)"
        }
        'push'     { if (Test-MenuContext $context) { Invoke-PushFlow -Context $context } }
        'commit'   { if (Test-MenuContext $context) { Show-CommitPushMenu -Context $context -BeginnerMode $beginner } }
        'branch'   { if (Test-MenuContext $context) { Show-BranchMenu -Context $context -BeginnerMode $beginner } }
        'repos'    { Show-RepositoryMenu -ConfigPath $ConfigPath }
        'pr'       { if (Test-MenuContext $context) { Show-PullRequestMenu -Context $context -BeginnerMode $beginner } }
        'docker'   { Show-DockerMenu -Context $context -BeginnerMode $beginner -ConfigPath $ConfigPath }
        'release'  { if (Test-MenuContext $context) { Show-ReleaseMenu -Context $context -ConfigPath $ConfigPath } }
        'recover'  { if (Test-MenuContext $context) { Show-RecoveryMenu -Context $context } }
        'accounts' { Show-AccountsMenu -Context $context }
        'settings' { Show-SettingsMenu -ConfigPath $ConfigPath }
        'doctor'   {
            $info = Lamfa-GetBootstrapInfo
            Lamfa-WriteKeyValue -Key 'PowerShell' -Value $info.PowerShell.ToString()
            foreach ($tool in $info.Tools) {
                Lamfa-WriteKeyValue -Key $tool.Name -Value ($(if ($tool.Installed) { $tool.Version } else { 'NOT INSTALLED' }))
            }
            $context = Lamfa-GetCliContext -ConfigPath $ConfigPath
            if ($context -and $context.IsGitRepository) {
                $report = Lamfa-GetEnvironmentReport -Path $context.Path
                Lamfa-WriteKeyValue -Key 'SSH keys' -Value (@($report.SshPublicKeys).Count)
                Lamfa-WriteKeyValue -Key 'ssh-agent' -Value ($(if ($report.SshAgentRunning) { 'running' } else { 'not running' }))
                if ($report.LfsProblem) { Lamfa-WriteMessage -Level Warning -Text 'Repository requires Git LFS but git-lfs is not installed.' }
                if (@($report.UninitializedSubmodules).Count) { Lamfa-WriteMessage -Level Warning -Text "Uninitialized submodules: $($report.UninitializedSubmodules -join ', ')" }
            }
        }
        'help'     {
            Write-Host 'Usage: lamfa [subcommand]' -ForegroundColor Cyan
            foreach ($key in $script:Subcommands.Keys) {
                Write-Host ("  lamfa {0,-9} {1}" -f $key, $script:Subcommands[$key])
            }
        }
        default    {
            Lamfa-WriteMessage -Level Warning -Text "Unknown subcommand '$Command'."
            Lamfa -Command 'help' -ConfigPath $ConfigPath
        }
    }
}

function Lamfa-GetSubcommandList {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()
    return $script:Subcommands
}

Export-ModuleMember -Function Lamfa, Lamfa-GetCliContext, Lamfa-GetSubcommandList

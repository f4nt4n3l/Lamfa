# Main menu loop + dashboard + recommended next action + onboarding.
# Menu handlers delegate to the domain modules; state-changing flows go through
# the operation engine in the submenu modules.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot 'ConsoleRenderer.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'Help.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'RepositoryMenu.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitMenu.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitHubMenu.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'DockerMenu.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'SettingsMenu.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Configuration.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/DependencyCheck.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Repositories/RepositoryRegistry.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitRepository.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Providers/GitHub/GitHubAuth.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Docker/DockerEnvironment.psm1') -DisableNameChecking

function Lamfa-GetRecommendedAction {
    <#
    .SYNOPSIS
        One safe, contextual suggestion for the dashboard.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter()][AllowNull()][object]$Context = $null)
    if ($null -eq $Context) { return 'No active repository. Open [1] Repositories to register, scan, or clone one.' }
    if (-not $Context.IsGitRepository) { return 'The active folder is not a Git repository. Pick another, or clone one.' }
    if ($Context.MergeInProgress -or $Context.RebaseInProgress) { return 'An operation is in progress. Open [9] Backup and recovery for guided, work-preserving steps.' }
    if ($Context.WorkingTreeState -eq 'Conflicted') { return 'Conflicts need resolving. Open [9] Backup and recovery for guidance.' }
    if ($Context.WorkingTreeState -eq 'Dirty') { return 'You have local changes. Open [4] Commit and push to review and commit them.' }
    if ($null -ne $Context.AheadCount -and $Context.AheadCount -gt 0) { return "You have $($Context.AheadCount) unpushed commit(s). Open [4] Commit and push." }
    if ($null -ne $Context.BehindCount -and $Context.BehindCount -gt 0) { return "The remote has $($Context.BehindCount) new commit(s). Open [2] Git status and changes to pull safely." }
    return 'Everything is in sync. Create a branch under [3] before starting new work.'
}

function Lamfa-BuildStatusBar {
    <#
    .SYNOPSIS
        Composes the two persistent status lines (repository state; accounts
        and mode) shown at the top of every screen via Lamfa-SetStatusBar.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()][AllowNull()][object]$Context = $null,
        [Parameter()][AllowNull()][object]$DockerStatus = $null,
        [Parameter()][bool]$BeginnerMode = $true
    )
    $repoLine = 'no active repository'
    if ($null -ne $Context) {
        $branch = if ($Context.IsDetachedHead) { '(detached HEAD)' } else { $Context.CurrentBranch }
        $repoLine = "$($Context.Name) @ $branch  [$($Context.WorkingTreeState)]"
        if ($null -ne $Context.AheadCount) { $repoLine += "  ahead $($Context.AheadCount) / behind $($Context.BehindCount)" }
    }
    $account = 'not logged in'
    try {
        $auth = Get-GitHubAuthStatus
        $active = @($auth.Accounts | Where-Object Active | Select-Object -First 1)
        if ($active.Count -gt 0) { $account = $active[0].Account }
    } catch { $account = 'unknown' }
    $dockerText = 'off'
    if ($null -ne $DockerStatus -and $DockerStatus.DaemonRunning) { $dockerText = $DockerStatus.CurrentContext }
    $mode = if ($BeginnerMode) { 'Beginner' } else { 'Advanced' }
    return @($repoLine, "GitHub: $account  |  Docker: $dockerText  |  Mode: $mode")
}

function Lamfa-ShowDashboard {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][object]$Context = $null,
        [Parameter()][AllowNull()][object]$DockerStatus = $null
    )
    Clear-Host
    Lamfa-WriteHeader -Text 'Lamfa'
    $git = Get-GitDependencyStatus
    $gh = Get-GitHubCliStatus
    $docker = if ($null -ne $DockerStatus) { $DockerStatus } else { Get-DockerStatus }
    Write-Host ''
    Write-Host ' Environment' -ForegroundColor White
    Lamfa-WriteKeyValue -Key 'PowerShell' -Value $PSVersionTable.PSVersion.ToString()
    Lamfa-WriteKeyValue -Key 'Git' -Value ($(if ($git.Installed) { $git.Version } else { 'not installed' }))
    Lamfa-WriteKeyValue -Key 'GitHub CLI' -Value ($(if ($gh.Installed) { $gh.Version } else { 'not installed (optional)' }))
    Lamfa-WriteKeyValue -Key 'Docker' -Value ($(if ($docker.DaemonRunning) { "running (context: $($docker.CurrentContext))" } elseif ($docker.CliInstalled) { 'installed, daemon not running' } else { 'not installed (optional)' }))
    Write-Host ''
    if ($null -ne $Context) {
        Write-Host ' Active repository' -ForegroundColor White
        Lamfa-WriteKeyValue -Key 'Name' -Value $Context.Name
        Lamfa-WriteKeyValue -Key 'Path' -Value $Context.Path
        Lamfa-WriteKeyValue -Key 'Branch' -Value ($(if ($Context.IsDetachedHead) { '(detached HEAD)' } else { $Context.CurrentBranch }))
        Lamfa-WriteKeyValue -Key 'Upstream' -Value $Context.UpstreamBranch
        Lamfa-WriteKeyValue -Key 'State' -Value $Context.WorkingTreeState
        if ($null -ne $Context.AheadCount) { Lamfa-WriteKeyValue -Key 'Ahead/Behind' -Value "$($Context.AheadCount) / $($Context.BehindCount)" }
    } else {
        Write-Host ' Active repository: none selected' -ForegroundColor Yellow
    }
    Write-Host ''
    Lamfa-WriteMessage -Level Info -Text (Lamfa-GetRecommendedAction -Context $Context)
    Write-Host ''
}

function Lamfa-GetMainMenuItemList {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    return @(
        [pscustomobject]@{ Key = '1'; Label = 'Repositories';                Help = 'Register, scan, clone, switch, open, or delete repositories.' }
        [pscustomobject]@{ Key = '2'; Label = 'Git status and changes';      Help = 'Status, diffs, history, fetch, and safe fast-forward pull.' }
        [pscustomobject]@{ Key = '3'; Label = 'Branches and worktrees';      Help = 'Create/switch/rename branches, stash, worktrees, cleanup.' }
        [pscustomobject]@{ Key = '4'; Label = 'Commit and push';             Help = 'Pick files, review, commit, and push with an exact-target preview.' }
        [pscustomobject]@{ Key = '5'; Label = 'Pull requests and reviews';   Help = 'Create/inspect PRs, checks, reviews, comments, checkout.' }
        [pscustomobject]@{ Key = '6'; Label = 'Build, test, and quality';    Help = 'Run the repository profile commands and the comment audit.' }
        [pscustomobject]@{ Key = '7'; Label = 'Docker';                      Help = 'Images, containers, compose, contexts, registry push.' }
        [pscustomobject]@{ Key = '8'; Label = 'Release';                     Help = 'Gated, resumable release: gates -> tag -> publish -> docker.' }
        [pscustomobject]@{ Key = '9'; Label = 'Backup and recovery';         Help = 'Plain-language recovery guidance, conflict helper, bundle backup.' }
        [pscustomobject]@{ Key = 'A'; Label = 'Accounts and authentication'; Help = 'Git identity vs GitHub account vs Docker logins - shown separately.' }
        [pscustomobject]@{ Key = 'S'; Label = 'Settings and help';           Help = 'Beginner/Advanced mode, help, glossary, export/import, logs.' }
    )
}

function Lamfa-InvokeFirstRunWizard {
    <#
    .SYNOPSIS
        Onboarding on first start: explains the tool, checks
        dependencies, and offers the three ways to get a first repository.
    #>
    [CmdletBinding()]
    param([Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath))
    Lamfa-WriteHeader -Text 'Welcome to Lamfa'
    Write-Host ''
    Write-Host ' Lamfa manages your Git repositories, GitHub, and Docker safely.'
    Write-Host ' Every action explains what it does before running; risky operations'
    Write-Host ' are hidden until you leave Beginner Mode in Settings.'
    Write-Host ''
    $git = Get-GitDependencyStatus
    if (-not $git.Installed) {
        Lamfa-WriteMessage -Level Warning -Text $git.Message
        $install = Lamfa-InstallDependency -Name git -Reason 'Lamfa cannot do anything useful without Git.'
        Lamfa-WriteMessage -Level Info -Text $install.Detail
        if (-not $install.Installed) { return }
        $git = Get-GitDependencyStatus
    }
    Lamfa-WriteMessage -Level Success -Text "Git $($git.Version) found."
    Write-Host ''
    Write-Host ' Get your first repository:'
    Write-Host '   1. Register an existing local folder'
    Write-Host '   2. Scan a folder for repositories'
    Write-Host '   3. Clone from a URL'
    Write-Host '   0. Skip for now'
    switch (Lamfa-ReadMenuKey -Breadcrumb @('Lamfa', 'Welcome')) {
        '1' { Invoke-RegisterRepositoryFlow -ConfigPath $ConfigPath }
        '2' { Invoke-ScanRepositoriesFlow -ConfigPath $ConfigPath }
        '3' { Invoke-CloneRepositoryFlow -ConfigPath $ConfigPath }
        default { }
    }
}

function Lamfa-StartMainMenu {
    <#
    .SYNOPSIS
        The interactive session loop. Every iteration refreshes the
        active repository context so the header never lies.
    #>
    [CmdletBinding()]
    param([Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath))

    $config = Lamfa-GetConfiguration -Path $ConfigPath
    if (@($config.repositories).Count -eq 0) {
        Lamfa-InvokeFirstRunWizard -ConfigPath $ConfigPath
    }
    while ($true) {
        $config = Lamfa-GetConfiguration -Path $ConfigPath
        $context = $null
        if ($config.activeRepositoryId) {
            try {
                $context = Lamfa-SetActiveRepository -Id $config.activeRepositoryId -ConfigPath $ConfigPath
                $context = Lamfa-UpdateRepositoryContext -Context $context
            } catch {
                Lamfa-WriteMessage -Level Warning -Text $_.Exception.Message
                $context = $null
            }
        }
        if ($null -ne $context) {
            # Silent freshness fetch keeps ahead/behind honest.
            if (Lamfa-UpdateFetchFreshness -Context $context -ConfigPath $ConfigPath) {
                $context = Lamfa-UpdateRepositoryContext -Context $context
            }
        }
        $beginner = [bool]$config.beginnerMode
        $docker = Get-DockerStatus
        Lamfa-SetStatusBar -Lines (Lamfa-BuildStatusBar -Context $context -DockerStatus $docker -BeginnerMode $beginner)
        Lamfa-ShowDashboard -Context $context -DockerStatus $docker
        Write-Host ''
        $selected = Lamfa-SelectMenuChoice -Items (Lamfa-GetMainMenuItemList) -Breadcrumb @('Lamfa')
        if ($null -eq $selected) { return }
        switch ($selected.Key) {
            '1' { Show-RepositoryMenu -ConfigPath $ConfigPath }
            '2' { Show-GitStatusMenu -Context $context }
            '3' { Show-BranchMenu -Context $context -BeginnerMode $beginner }
            '4' { Show-CommitPushMenu -Context $context -BeginnerMode $beginner }
            '5' { Show-PullRequestMenu -Context $context -BeginnerMode $beginner }
            '6' { Show-WorkflowMenu -Context $context -ConfigPath $ConfigPath }
            '7' { Show-DockerMenu -Context $context -BeginnerMode $beginner -ConfigPath $ConfigPath }
            '8' { Show-ReleaseMenu -Context $context -ConfigPath $ConfigPath }
            '9' { Show-RecoveryMenu -Context $context }
            'A' { Show-AccountsMenu -Context $context }
            'S' { Show-SettingsMenu -ConfigPath $ConfigPath }
        }
    }
}

Export-ModuleMember -Function Lamfa-GetRecommendedAction, Lamfa-GetMainMenuItemList, Lamfa-BuildStatusBar, Lamfa-ShowDashboard, Lamfa-InvokeFirstRunWizard, Lamfa-StartMainMenu

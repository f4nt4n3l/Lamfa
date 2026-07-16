# Pull requests + accounts menus (main-menu categories 5 and 10).
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot 'ConsoleRenderer.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitMenu.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitRepository.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitBranches.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Providers/GenericRemote.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Workflows/ProfileLoader.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/DependencyCheck.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Providers/GitHub/GitHubAuth.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Providers/GitHub/GitHubRepositories.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Providers/GitHub/GitHubPullRequests.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Providers/GitHub/GitHubReviews.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Providers/ProviderAdapter.psm1') -DisableNameChecking

function Show-PullRequestMenu {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][object]$Context, [Parameter()][bool]$BeginnerMode = $true)
    if (-not (Test-MenuContext $Context)) { return }
    # Provider-neutral: resolve the adapter from the profile/remote.
    $resolvedProfile = Lamfa-GetProfile -RepositoryPath $Context.Path -RepositoryName $Context.Name
    $resolvedAdapter = Lamfa-GetProviderAdapter -Context $Context -ResolvedProfile $resolvedProfile
    if ($null -eq $resolvedAdapter.Adapter) {
        Lamfa-WriteMessage -Level Info -Text $resolvedAdapter.Remediation
        return
    }
    if (-not $resolvedAdapter.Available) {
        Lamfa-WriteMessage -Level Warning -Text $resolvedAdapter.Remediation
        $install = Lamfa-InstallDependency -Name $resolvedAdapter.Adapter.CliName `
            -Reason "Pull-request features for '$($resolvedAdapter.Provider)' need this CLI."
        Lamfa-WriteMessage -Level Info -Text $install.Detail
        if (-not $install.Installed) { return }
    }
    $adapter = $resolvedAdapter.Adapter
    $isGitHub = ($resolvedAdapter.Provider -eq 'github')
    $screenShown = $false
    while ($true) {
        if ($screenShown) { Lamfa-PauseForReview }
        $screenShown = $true
        Lamfa-ShowScreen -Breadcrumb @('Lamfa', 'Pull requests')
        Write-Host ''
        Write-Host "PULL REQUESTS AND REVIEWS  (provider: $($resolvedAdapter.Provider))" -ForegroundColor Cyan
        $pr = $null
        try { $pr = & $adapter.PullRequestForBranch $Context } catch { Lamfa-WriteMessage -Level Warning -Text $_.Exception.Message }
        if ($pr) {
            Lamfa-WriteKeyValue -Key 'PR' -Value "#$($pr.Number) $($pr.Title) [$($pr.State)$(if ($pr.IsDraft) { ', draft' })]"
            Lamfa-WriteKeyValue -Key 'Base<-Head' -Value "$($pr.Base) <- $($pr.Head)"
            if ($pr.ReviewDecision) { Lamfa-WriteKeyValue -Key 'Review' -Value $pr.ReviewDecision }
        } else {
            Lamfa-WriteMessage -Level Info -Text "No pull request exists for branch '$($Context.CurrentBranch)'."
        }
        Write-Host ''
        Write-Host '  1. Create PR   3. Reviews and comments   5. Checkout a PR locally'
        Write-Host '  2. Checks      4. Open in browser        6. Add comment to this PR   0. Back'
        switch (Lamfa-ReadMenuKey -Breadcrumb @('Lamfa', 'Pull requests')) {
            '1' {
                if ($pr) { Lamfa-WriteMessage -Level Info -Text 'A PR already exists for this branch.'; continue }
                $base = Read-Host "Base branch (target, e.g. $($Context.IntegrationBranch ?? $Context.DefaultBranch ?? 'main'))"
                $title = Read-Host 'PR title'
                if (-not $base -or -not $title) { continue }
                $body = Read-Host 'PR body (Enter to skip)'
                Write-Host " Creating: $base <- $($Context.CurrentBranch)  '$title'"
                if ((Read-Host 'Confirm? [y/N]') -match '^(y|yes)$') {
                    try {
                        $result = & $adapter.PullRequestCreate $Context $base $Context.CurrentBranch $title $body
                        if ($result -and $result.PSObject.Properties['Succeeded'] -and -not $result.Succeeded) {
                            Lamfa-WriteMessage -Level Error -Text $result.StandardError
                        } else { Lamfa-WriteMessage -Level Success -Text 'Pull request created.' }
                    } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
                }
            }
            '2' {
                try {
                    $checks = @(& $adapter.PullRequestChecks $Context)
                    if ($checks.Count -eq 0) { Lamfa-WriteMessage -Level Info -Text 'No checks reported for this provider - use the browser link.' }
                    foreach ($check in $checks) {
                        $color = switch ($check.State) { 'SUCCESS' { 'Green' } 'FAILURE' { 'Red' } default { 'Yellow' } }
                        Write-Host ("  {0,-10} {1}" -f $check.State, $check.Name) -ForegroundColor $color
                    }
                } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
            }
            '3' {
                if ($isGitHub) {
                    $feedback = Get-GitHubPullRequestFeedback -Path $Context.Path
                    if ($feedback) {
                        Lamfa-WriteKeyValue -Key 'Decision' -Value $feedback.ReviewDecision
                        foreach ($review in $feedback.Reviews) { Write-Host "  [$($review.State)] $($review.Author): $($review.Body)" }
                        foreach ($comment in $feedback.Comments) { Write-Host "  [comment] $($comment.Author): $($comment.Body)" }
                    } else { Lamfa-WriteMessage -Level Info -Text 'No PR for this branch.' }
                } elseif ($pr -and $pr.Url) {
                    Lamfa-WriteMessage -Level Info -Text 'Detailed reviews for this provider open in the browser.'
                    Start-Process $pr.Url
                } else { Lamfa-WriteMessage -Level Info -Text 'No PR for this branch.' }
            }
            '4' {
                if ($pr -and $pr.Url) { Start-Process $pr.Url }
                elseif ($isGitHub) { Open-GitHubPullRequestInBrowser -Path $Context.Path }
                else {
                    $remote = @($Context.Remotes) | Select-Object -First 1
                    if ($remote) { Lamfa-OpenRemoteInBrowser -RemoteUrl $remote.FetchUrl }
                }
            }
            '5' {
                if (-not $isGitHub) { Lamfa-WriteMessage -Level Info -Text 'PR checkout is currently available for GitHub only.'; continue }
                $number = Read-Host 'PR number to check out'
                if ($number -match '^\d+$') {
                    $result = Invoke-GitHubPullRequestCheckout -Path $Context.Path -Number ([int]$number)
                    if ($result.Succeeded) { Lamfa-WriteMessage -Level Success -Text "Checked out PR #$number - you are now on its branch." }
                    else { Lamfa-WriteMessage -Level Error -Text $result.StandardError }
                }
            }
            '6' {
                if (-not $pr) { Lamfa-WriteMessage -Level Info -Text 'No PR for this branch.'; continue }
                $body = Read-Host 'Comment text'
                if ($body) {
                    try {
                        $result = & $adapter.PullRequestComment $Context $body
                        if ($result -and $result.PSObject.Properties['Succeeded'] -and -not $result.Succeeded) {
                            Lamfa-WriteMessage -Level Error -Text $result.StandardError
                        } else { Lamfa-WriteMessage -Level Success -Text 'Comment added.' }
                    } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
                }
            }
            '0' { return }
        }
    }
}

function Show-AccountsMenu {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][object]$Context)
    $screenShown = $false
    while ($true) {
        if ($screenShown) { Lamfa-PauseForReview }
        $screenShown = $true
        Lamfa-ShowScreen -Breadcrumb @('Lamfa', 'Accounts')
        Write-Host ''
        Write-Host 'ACCOUNTS AND AUTHENTICATION' -ForegroundColor Cyan
        Write-Host ' These are THREE separate things (a frequent source of confusion):' -ForegroundColor DarkGray
        if ($null -ne $Context -and $Context.IsGitRepository) {
            $identity = Get-GitIdentity -Path $Context.Path
            Write-Host ''
            Write-Host ' 1) Git commit identity (stamped into every commit)' -ForegroundColor White
            Lamfa-WriteKeyValue -Key 'Effective' -Value "$($identity.EffectiveName) <$($identity.EffectiveEmail)>"
            Lamfa-WriteKeyValue -Key 'From' -Value ($(if ($identity.LocalName) { 'this repository (local config)' } else { 'global config' }))
            Lamfa-WriteKeyValue -Key 'Cred helper' -Value ($identity.CredentialHelpers -join ', ')
            if ($identity.UsesPlaintextStore) {
                Lamfa-WriteMessage -Level Warning -Text "The 'store' credential helper saves passwords as PLAIN TEXT. Prefer Git Credential Manager."
            }
        }
        Write-Host ''
        Write-Host ' 2) GitHub CLI account (used for PRs, repo listing)' -ForegroundColor White
        $auth = Get-GitHubAuthStatus
        if ($auth.Authenticated) {
            foreach ($account in $auth.Accounts) {
                Lamfa-WriteKeyValue -Key $account.HostName -Value "$($account.Account)$(if ($account.Active) { ' (active)' })"
            }
        } else { Lamfa-WriteMessage -Level Info -Text 'Not logged in to GitHub CLI.' }
        if ($auth.UsesPlaintextTokens) { Lamfa-WriteMessage -Level Warning -Text 'gh reports plaintext token storage - consider re-login so the token lands in Windows Credential Manager.' }
        Write-Host ''
        Write-Host ' 3) Docker registry logins are separate again (Docker menu).' -ForegroundColor White
        Write-Host ''
        Write-Host '  1. Set repository-local Git identity   3. Switch GitHub account'
        Write-Host '  2. GitHub login                         4. SSH / LFS / submodule report   0. Back'
        switch (Lamfa-ReadMenuKey -Breadcrumb @('Lamfa', 'Accounts')) {
            '1' {
                if ($null -eq $Context -or -not $Context.IsGitRepository) { Lamfa-WriteMessage -Level Warning -Text 'Needs an active Git repository.'; continue }
                $name = Read-Host 'Name for THIS repository'
                $email = Read-Host 'Email for THIS repository'
                if ($name -and $email) {
                    Set-GitLocalIdentity -Path $Context.Path -UserName $name -Email $email
                    Lamfa-WriteMessage -Level Success -Text 'Local identity set. Other repositories are unaffected.'
                }
            }
            '2' { Start-GitHubLogin }
            '4' {
                if ($null -eq $Context -or -not $Context.IsGitRepository) { Lamfa-WriteMessage -Level Warning -Text 'Needs an active Git repository.'; continue }
                $report = Lamfa-GetEnvironmentReport -Path $Context.Path
                Lamfa-WriteKeyValue -Key 'SSH keys' -Value ($(if (@($report.SshPublicKeys).Count) { $report.SshPublicKeys -join ', ' } else { 'none found in ~/.ssh' }))
                Lamfa-WriteKeyValue -Key 'ssh-agent' -Value ($(if ($report.SshAgentRunning) { 'running' } else { 'not running (SSH remotes will prompt for the key passphrase every time)' }))
                Lamfa-WriteKeyValue -Key 'Git LFS' -Value ($(if ($report.LfsInstalled) { 'installed' } else { 'not installed' }))
                if ($report.LfsProblem) { Lamfa-WriteMessage -Level Warning -Text 'This repository REQUIRES Git LFS (.gitattributes) but git-lfs is not installed - large files will appear as tiny pointer texts.' }
                if ($report.HasSubmodules) {
                    if (@($report.UninitializedSubmodules).Count) { Lamfa-WriteMessage -Level Warning -Text "Uninitialized submodules: $($report.UninitializedSubmodules -join ', '). Run: git submodule update --init" }
                    else { Lamfa-WriteKeyValue -Key 'Submodules' -Value 'all initialized' }
                }
            }
            '3' {
                $account = Read-Host 'Account name to activate'
                if ($account) {
                    $result = Switch-GitHubAccount -Account $account
                    if ($result.Succeeded) { Lamfa-WriteMessage -Level Success -Text "Switched to '$account'." }
                    else { Lamfa-WriteMessage -Level Error -Text $result.StandardError }
                }
            }
            '0' { return }
        }
    }
}

Export-ModuleMember -Function Show-PullRequestMenu, Show-AccountsMenu

# Git menus: status/changes, branches/worktrees, commit/push, workflows,
# recovery (main-menu categories 2, 3, 4, 6, 9).
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot 'ConsoleRenderer.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Configuration.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitStatus.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitDiff.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitHistory.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitBranches.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitRemotes.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitCommits.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitHunks.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitUndo.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitInsights.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitStash.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitWorktrees.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitRecovery.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Workflows/ProfileLoader.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Workflows/WorkflowEngine.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Workflows/ProjectDetection.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Workflows/ReleaseTools.psm1') -DisableNameChecking

function Test-MenuContext {
    param([AllowNull()][object]$Context)
    if ($null -eq $Context -or -not $Context.IsGitRepository) {
        Lamfa-WriteMessage -Level Warning -Text 'This menu needs an active Git repository. Open [1] Repositories first.'
        return $false
    }
    return $true
}

function Show-GitStatusMenu {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][object]$Context)
    if (-not (Test-MenuContext $Context)) { return }
    $screenShown = $false
    while ($true) {
        if ($screenShown) { Lamfa-PauseForReview }
        $screenShown = $true
        Lamfa-ShowScreen -Breadcrumb @('Lamfa', 'Git status')
        $status = Get-GitStatus -Path $Context.Path
        Write-Host ''
        Write-Host "STATUS - $($Context.Name) on $($status.Branch)" -ForegroundColor Cyan
        if ($status.IsClean) { Lamfa-WriteMessage -Level Success -Text 'Working tree clean.' }
        foreach ($entry in $status.Entries) {
            Write-Host ("  [{0}{1}] {2,-10} {3}" -f $entry.IndexState, $entry.WorktreeState, $entry.Kind, $entry.Path)
        }
        Write-Host ''
        Write-Host '  1. Show diff (unstaged)   4. History graph              7. Show ignored files'
        Write-Host '  2. Show diff (staged)     5. Fetch                      8. Blame a file'
        Write-Host '  3. History (recent)       6. Pull (safe, ff-only)       9. Search commits'
        Write-Host '  0. Back'
        switch (Lamfa-ReadMenuKey -Breadcrumb @('Lamfa', 'Git status')) {
            '1' { Get-GitDiff -Path $Context.Path -Scope Unstaged | Out-Host -Paging -ErrorAction SilentlyContinue }
            '2' { Get-GitDiff -Path $Context.Path -Scope Staged | Out-Host -Paging -ErrorAction SilentlyContinue }
            '3' { Get-GitHistory -Path $Context.Path -Limit 20 | Format-Table Hash, Date, Author, Subject -AutoSize | Out-Host }
            '4' { Get-GitHistoryGraph -Path $Context.Path | Out-Host }
            '5' { $result = Invoke-GitFetch -Path $Context.Path
                  Lamfa-WriteMessage -Level ($(if ($result.Succeeded) { 'Success' } else { 'Error' })) -Text ($(if ($result.Succeeded) { 'Fetched.' } else { $result.StandardError })) }
            '8' {
                $file = Read-Host 'File to blame'
                if ($file) {
                    try {
                        Get-GitBlame -Path $Context.Path -File $file | ForEach-Object {
                            Write-Host ("  {0,4} {1} {2:yyyy-MM-dd} {3,-18} {4}" -f $_.Line, $_.Commit, $_.Date, $_.Author, $_.Text)
                        } | Out-Host -Paging -ErrorAction SilentlyContinue
                    } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
                }
            }
            '9' {
                $message = Read-Host 'Search in commit messages (Enter to skip)'
                $code = Read-Host 'Search added/removed CODE (pickaxe, Enter to skip)'
                try {
                    $found = @(Find-GitCommit -Path $Context.Path -Message $message -Code $code)
                    if ($found.Count -eq 0) { Lamfa-WriteMessage -Level Info -Text 'No commits matched.' }
                    else { $found | Format-Table Hash, Date, Author, Subject -AutoSize | Out-Host }
                } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
            }
            '7' {
                $ignored = @((Get-GitStatus -Path $Context.Path -IncludeIgnored).Entries | Where-Object Kind -eq 'Ignored')
                if ($ignored.Count -eq 0) { Lamfa-WriteMessage -Level Info -Text 'No ignored files in tracked directories.' }
                else { $ignored | ForEach-Object { Write-Host "  [ignored] $($_.Path)" } }
            }
            '6' { $pull = Invoke-GitPull -Path $Context.Path
                  Lamfa-WriteMessage -Level ($(if ($pull.Outcome -in @('FastForwarded','UpToDate')) { 'Success' } else { 'Warning' })) -Text "$($pull.Outcome): $($pull.Detail)" }
            '0' { return }
        }
    }
}

function Show-BranchMenu {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][object]$Context, [Parameter()][bool]$BeginnerMode = $true)
    if (-not (Test-MenuContext $Context)) { return }
    $screenShown = $false
    while ($true) {
        if ($screenShown) { Lamfa-PauseForReview }
        $screenShown = $true
        Lamfa-ShowScreen -Breadcrumb @('Lamfa', 'Branches')
        Write-Host ''
        Write-Host 'BRANCHES AND WORKTREES' -ForegroundColor Cyan
        Get-GitBranchList -Path $Context.Path | ForEach-Object {
            $marker = if ($_.IsCurrent) { '*' } else { ' ' }
            Write-Host ("  $marker {0,-32} {1}" -f $_.Name, $_.Commit)
        }
        Write-Host ''
        Write-Host '  1. Create branch          4. Delete merged local branch   7. Show unmerged branches'
        Write-Host '  2. Switch branch          5. Worktrees (list/add/remove)  8. Cleanup report (merged + old)'
        Write-Host '  3. Stash (save/restore)   6. Rename local branch          0. Back'
        if (-not $BeginnerMode) { Write-Host '  9. Squash last N commits into one (Advanced)' }
        switch (Lamfa-ReadMenuKey -Breadcrumb @('Lamfa', 'Branches')) {
            '1' {
                $name = Read-Host 'New branch name'
                $source = Read-Host 'Source ref (Enter = current HEAD)'
                if (-not $source) { $source = 'HEAD' }
                try { New-GitBranch -Path $Context.Path -Name $name -SourceRef $source -Switch
                      Lamfa-WriteMessage -Level Success -Text "Created and switched to '$name' (from $source)." }
                catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
            }
            '2' {
                $name = Read-Host 'Branch to switch to'
                try { Switch-GitBranch -Path $Context.Path -Name $name
                      Lamfa-WriteMessage -Level Success -Text "On '$name'." }
                catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
            }
            '3' {
                Get-GitStashList -Path $Context.Path | ForEach-Object { Write-Host "  $($_.Ref)  $($_.Description)" }
                Write-Host '  1. Save changes to a new stash   2. Apply latest   3. Pop latest'
                switch (Lamfa-ReadMenuKey -Breadcrumb @('Lamfa', 'Branches', 'Stash')) {
                    '1' {
                        $message = Read-Host 'Stash name/description'
                        $untracked = (Read-Host 'Include NEW (untracked) files too? [y/N]') -match '^(y|yes)$'
                        try { Add-GitStash -Path $Context.Path -Message $message -IncludeUntracked:$untracked
                              Lamfa-WriteMessage -Level Success -Text 'Stashed. Your working tree is clean; restore with Apply or Pop.' }
                        catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
                    }
                    '2' { $result = Use-GitStash -Path $Context.Path -Mode Apply; Lamfa-WriteMessage -Level Info -Text "$($result.Outcome). $($result.Detail)" }
                    '3' { $result = Use-GitStash -Path $Context.Path -Mode Pop; Lamfa-WriteMessage -Level Info -Text "$($result.Outcome). $($result.Detail)" }
                }
            }
            '4' {
                $name = Read-Host 'Local branch to delete (must be fully merged)'
                $integration = Read-Host "Merged into which branch? (e.g. $($Context.IntegrationBranch ?? 'main'))"
                Lamfa-WriteMessage -Level Warning -Text "Deleting local branch '$name'. Type the branch name to confirm."
                if ((Read-Host 'Confirm') -ceq $name) {
                    try { Remove-MergedGitBranch -Path $Context.Path -Name $name -IntegrationRef $integration
                          Lamfa-WriteMessage -Level Success -Text 'Deleted.' }
                    catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
                } else { Lamfa-WriteMessage -Level Info -Text 'Cancelled.' }
            }
            '6' {
                $name = Read-Host 'Branch to rename'
                $newName = Read-Host 'New name'
                if ($name -and $newName) {
                    try {
                        Rename-GitBranch -Path $Context.Path -Name $name -NewName $newName
                        Lamfa-WriteMessage -Level Success -Text "Renamed. If '$name' was already published, the remote still has the old name until you push '$newName'."
                    } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
                }
            }
            '8' {
                $ref = Read-Host "Merged into which branch? (e.g. $($Context.IntegrationBranch ?? 'main'))"
                if (-not $ref) { continue }
                try {
                    $report = @(Get-GitMergedBranchReport -Path $Context.Path -IntegrationRef $ref -OlderThanDays 14)
                    if ($report.Count -eq 0) { Lamfa-WriteMessage -Level Success -Text 'No merged branches older than 14 days.'; continue }
                    $report | ForEach-Object { Write-Host ("  {0,-36} last commit {1:yyyy-MM-dd}" -f $_.Name, $_.LastCommitUtc) }
                    if ((Read-Host 'Delete ALL of the above? Each deletion re-verifies the merge. [y/N]') -match '^(y|yes)$') {
                        foreach ($branch in $report) {
                            try { Remove-MergedGitBranch -Path $Context.Path -Name $branch.Name -IntegrationRef $ref
                                  Lamfa-WriteMessage -Level Success -Text "Deleted $($branch.Name)." }
                            catch { Lamfa-WriteMessage -Level Warning -Text $_.Exception.Message }
                        }
                    }
                } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
            }
            '7' {
                $ref = Read-Host "Not merged into which branch? (e.g. $($Context.IntegrationBranch ?? 'main'))"
                if ($ref) {
                    try {
                        $unmerged = Get-GitUnmergedBranchList -Path $Context.Path -IntegrationRef $ref
                        if (@($unmerged).Count -eq 0) { Lamfa-WriteMessage -Level Success -Text "Every local branch is fully merged into '$ref'." }
                        else { $unmerged | ForEach-Object { Write-Host "  $_  (has commits not in $ref)" } }
                    } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
                }
            }
            '5' {
                Get-GitWorktreeList -Path $Context.Path | ForEach-Object { Write-Host "  $($_.Path)  [$($_.Branch)]" }
                Write-Host '  1. Add worktree (new branch)   2. Remove clean worktree'
                switch (Lamfa-ReadMenuKey -Breadcrumb @('Lamfa', 'Branches', 'Worktrees')) {
                    '1' {
                        $destination = Read-Host 'New worktree folder (must not exist)'
                        $branch = Read-Host 'New branch name for it'
                        try { Add-GitWorktree -Path $Context.Path -Destination $destination -Branch $branch -NewBranch
                              Lamfa-WriteMessage -Level Success -Text 'Worktree created.' }
                        catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
                    }
                    '2' {
                        $target = Read-Host 'Worktree path to remove'
                        try { Remove-GitWorktree -Path $Context.Path -WorktreePath $target
                              Lamfa-WriteMessage -Level Success -Text 'Removed.' }
                        catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
                    }
                }
            }
            '9' {
                if ($BeginnerMode) { Lamfa-WriteMessage -Level Warning -Text 'History rewriting is available in Advanced Mode only (Settings).'; continue }
                $count = Read-Host 'How many of the LAST commits to squash into one? (>=2)'
                if ($count -notmatch '^\d+$' -or [int]$count -lt 2) { continue }
                (Get-GitHistory -Path $Context.Path -Limit ([int]$count)) | Format-Table Hash, Subject -AutoSize | Out-Host
                Lamfa-WriteMessage -Level Warning -Text 'These commits become ONE. A backup branch pins the current history first.'
                if ((Read-Host 'Type SQUASH to continue') -cne 'SQUASH') { Lamfa-WriteMessage -Level Info -Text 'Cancelled.'; continue }
                $title = Read-Host 'Title for the combined commit'
                if (-not $title) { continue }
                try {
                    $backup = Invoke-GitSquashHistory -Path $Context.Path -Count ([int]$count) -Title $title
                    Lamfa-WriteMessage -Level Success -Text "Squashed. Original history is preserved on '$backup'."
                } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
            }
            '0' { return }
        }
    }
}

function Show-CommitPushMenu {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][object]$Context, [Parameter()][bool]$BeginnerMode = $true)
    if (-not (Test-MenuContext $Context)) { return }
    $screenShown = $false
    while ($true) {
        if ($screenShown) { Lamfa-PauseForReview }
        $screenShown = $true
        Lamfa-ShowScreen -Breadcrumb @('Lamfa', 'Commit and push')
        $status = Get-GitStatus -Path $Context.Path
        Write-Host ''
        Write-Host 'COMMIT AND PUSH' -ForegroundColor Cyan
        $index = 0
        $changed = @($status.Entries | Where-Object Kind -ne 'Ignored')
        foreach ($entry in $changed) {
            $index++
            $stagedMark = if ($entry.IndexState -notin @('.', '?')) { 'staged' } else { '      ' }
            Write-Host ("  {0,2}. [{1}] {2,-10} {3}" -f $index, $stagedMark, $entry.Kind, $entry.Path)
        }
        if ($changed.Count -eq 0) { Lamfa-WriteMessage -Level Success -Text 'Nothing to commit.' }
        Write-Host ''
        Write-Host '  1. Commit wizard (select files -> review -> commit)'
        Write-Host '  2. Push current branch     4. Stage HUNKS of one file (partial staging)'
        Write-Host '  3. Unstage files           0. Back'
        switch (Lamfa-ReadMenuKey -Breadcrumb @('Lamfa', 'Commit and push')) {
            '1' {
                if ($changed.Count -eq 0) { continue }
                $selection = Read-Host 'File numbers to include (e.g. 1,3,4 or * for all listed)'
                $files = if ($selection.Trim() -eq '*') { @($changed | ForEach-Object Path) }
                else {
                    @($selection -split '[, ]+' | Where-Object { $_ -match '^\d+$' } |
                        ForEach-Object { $changed[[int]$_ - 1].Path })
                }
                if ($files.Count -eq 0) { Lamfa-WriteMessage -Level Info -Text 'No files selected.'; continue }
                $concerns = Test-GitPreCommitConcern -Path $Context.Path -Files $files
                foreach ($concern in $concerns) { Lamfa-WriteMessage -Level Warning -Text "$($concern.File): $($concern.Kind) - $($concern.Detail)" }
                if ($concerns.Count -gt 0 -and (Read-Host 'Concerns listed above. Continue anyway? [y/N]') -notmatch '^(y|yes)$') { continue }
                try {
                    Add-GitStagedFile -Path $Context.Path -Files $files
                    Write-Host (Get-GitStagedDiff -Path $Context.Path -StatOnly)
                    $resolvedProfile = Lamfa-GetProfile -RepositoryPath $Context.Path -RepositoryName $Context.Name
                    $title = ''
                    while ($true) {
                        $title = Read-Host 'Commit title (imperative, short)'
                        if (-not $title) { break }
                        $convention = Lamfa-TestCommitTitle -ResolvedProfile $resolvedProfile -Title $title
                        if ($convention.Valid) { break }
                        Lamfa-WriteMessage -Level Warning -Text "Title does not follow the project convention. $($convention.Hint)"
                    }
                    if (-not $title) { Remove-GitStagedFile -Path $Context.Path -Files $files; continue }
                    $body = Read-Host 'Optional body (Enter to skip)'
                    $null = New-GitCommit -Path $Context.Path -Title $title -Body $body
                    Lamfa-WriteMessage -Level Success -Text 'Committed.'
                    if ((Read-Host 'Push now? [y/N]') -match '^(y|yes)$') { Invoke-PushFlow -Context $Context }
                } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
            }
            '2' { Invoke-PushFlow -Context $Context }
            '4' {
                $file = Read-Host 'File to stage partially (path)'
                if (-not $file) { continue }
                try {
                    $fileHunks = Get-GitFileHunkList -Path $Context.Path -File $file
                    if (@($fileHunks.Hunks).Count -eq 0) { Lamfa-WriteMessage -Level Info -Text 'No unstaged hunks in that file.'; continue }
                    foreach ($hunk in $fileHunks.Hunks) {
                        Write-Host ''
                        Write-Host " Hunk $($hunk.Index): $($hunk.Header)" -ForegroundColor Cyan
                        $hunk.Lines | Select-Object -First 12 | ForEach-Object {
                            $color = if ($_.StartsWith('+')) { 'Green' } elseif ($_.StartsWith('-')) { 'Red' } else { 'Gray' }
                            Write-Host "   $_" -ForegroundColor $color
                        }
                        if (@($hunk.Lines).Count -gt 12) { Write-Host '   ...' -ForegroundColor DarkGray }
                    }
                    $picks = Read-Host 'Hunk numbers to STAGE (e.g. 1,3 or * for all)'
                    $indexes = if ($picks.Trim() -eq '*') { @($fileHunks.Hunks | ForEach-Object Index) }
                    else { @($picks -split '[, ]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }) }
                    if ($indexes.Count -gt 0) {
                        Add-GitStagedHunk -Path $Context.Path -FileHunks $fileHunks -HunkIndexes $indexes
                        Lamfa-WriteMessage -Level Success -Text "Staged $($indexes.Count) hunk(s). The rest of the file stays unstaged."
                    }
                } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
            }
            '3' {
                $files = Read-Host 'File paths to unstage (comma-separated)'
                try { Remove-GitStagedFile -Path $Context.Path -Files @($files -split ',\s*')
                      Lamfa-WriteMessage -Level Success -Text 'Unstaged; working-tree content untouched.' }
                catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
            }
            '0' { return }
        }
    }
}

function Invoke-PushFlow {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Context)
    $preview = Get-GitPushPreview -Path $Context.Path
    Write-Host ''
    Write-Host 'PUSH TARGET' -ForegroundColor White
    Lamfa-WriteKeyValue -Key 'Branch' -Value $preview.Branch
    Lamfa-WriteKeyValue -Key 'Remote' -Value "$($preview.RemoteName)  $($preview.RemoteUrl)"
    Lamfa-WriteKeyValue -Key 'Target' -Value $preview.TargetBranch
    Lamfa-WriteKeyValue -Key 'Commits' -Value $preview.CommitCount
    if ($preview.CreatesUpstream) { Lamfa-WriteMessage -Level Info -Text 'This publishes the branch and sets its upstream.' }
    if (Test-GitProtectedBranchPush -Branch $preview.Branch -DefaultBranch $Context.DefaultBranch -IntegrationBranch $Context.IntegrationBranch) {
        Lamfa-WriteMessage -Level Warning -Text "You are pushing DIRECTLY to '$($preview.Branch)' - this lands without review. The usual flow is a feature branch + pull request."
        if ((Read-Host "Type the branch name '$($preview.Branch)' to allow the direct push") -cne $preview.Branch) {
            Lamfa-WriteMessage -Level Info -Text 'Cancelled. Nothing was pushed.'
            return
        }
    }
    if ((Read-Host 'Push? [y/N]') -match '^(y|yes)$') {
        $result = Invoke-GitPush -Path $Context.Path
        if ($result.Succeeded) { Lamfa-WriteMessage -Level Success -Text 'Pushed.' }
        else { Lamfa-WriteMessage -Level Error -Text "Push failed (your local commits are safe): $($result.StandardError)" }
    } else { Lamfa-WriteMessage -Level Info -Text 'Cancelled.' }
}

function Show-WorkflowMenu {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][object]$Context, [Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath))
    if (-not (Test-MenuContext $Context)) { return }
    $resolved = Lamfa-GetProfile -RepositoryPath $Context.Path -RepositoryName $Context.Name
    $screenShown = $false
    while ($true) {
        if ($screenShown) { Lamfa-PauseForReview }
        $screenShown = $true
        Lamfa-ShowScreen -Breadcrumb @('Lamfa', 'Build and quality')
        Write-Host ''
        Write-Host "BUILD, TEST, AND QUALITY  (profile: $($resolved.Source))" -ForegroundColor Cyan
        $commands = @()
        $commandsProperty = $resolved.Data.PSObject.Properties['commands']
        if ($commandsProperty -and $commandsProperty.Value) { $commands = @($commandsProperty.Value.PSObject.Properties.Name) }
        if ($commands.Count -eq 0) {
            Lamfa-WriteMessage -Level Info -Text 'The profile defines no commands. Detected project evidence:'
            Lamfa-FindProjectEvidence -Path $Context.Path | ForEach-Object { Write-Host "   [$($_.ProjectType)] $($_.File)" }
            Lamfa-WriteMessage -Level Info -Text 'Add a .lamfa.json to define build/test/run commands.'
            return
        }
        $items = @()
        $hotkeys = '123456789abcdefg'.ToCharArray()
        for ($i = 0; $i -lt $commands.Count; $i++) {
            $items += [pscustomobject]@{ Key = [string]$hotkeys[$i]; Label = "Run '$($commands[$i])'"
                Help = 'Runs this profile command through the workflow engine.'; Value = $commands[$i] }
        }
        $items += [pscustomobject]@{ Key = 'T'; Label = 'Trust repository profile'
            Help = 'Review and trust the repo-owned .lamfa.json by content hash.'; Value = '__trust' }
        $items += [pscustomobject]@{ Key = 'X'; Label = 'Comment audit'
            Help = 'Scans sources for TODO/FIXME/HACK and secret-looking comments.'; Value = '__audit' }
        $items += [pscustomobject]@{ Key = 'I'; Label = '.gitignore helper'
            Help = 'Add ignore entries or apply a template for the detected project type.'; Value = '__ignore' }
        $selected = Lamfa-SelectMenuChoice -Items $items -Breadcrumb @('Lamfa', 'Build and quality')
        if ($null -eq $selected) { return }
        $choice = $selected.Value
        if ($choice -eq '__ignore') {
            $evidence = @(Lamfa-FindProjectEvidence -Path $Context.Path)
            $types = @($evidence | ForEach-Object ProjectType | Where-Object { $_ -in @('dotnet', 'node', 'python', 'docker') } | Select-Object -Unique)
            Write-Host " Detected project types: $($types -join ', ')"
            Write-Host '  1. Apply template for a detected type   2. Add custom entries'
            switch (Lamfa-ReadMenuKey -Breadcrumb @('Lamfa', 'Build and quality', 'gitignore')) {
                '1' {
                    $type = Read-Host "Type ($($types -join '/'))"
                    if ($type -in @('dotnet', 'node', 'python', 'docker')) {
                        $added = Add-GitIgnoreEntry -Path $Context.Path -Entries (Get-GitIgnoreTemplate -ProjectType $type)
                        Lamfa-WriteMessage -Level Success -Text "Added $(@($added).Count) new entr$(if (@($added).Count -eq 1) { 'y' } else { 'ies' }) (existing ones skipped)."
                    }
                }
                '2' {
                    $raw = Read-Host 'Entries (comma-separated, e.g. dist/, *.log)'
                    if ($raw) {
                        $added = Add-GitIgnoreEntry -Path $Context.Path -Entries @($raw -split ',\s*')
                        Lamfa-WriteMessage -Level Success -Text "Added $(@($added).Count)."
                    }
                }
            }
            continue
        }
        if ($choice -eq '__audit') {
            Lamfa-GetCommentAudit -Path $Context.Path | Format-Table Kind, File, Line, Text -AutoSize | Out-Host
            continue
        }
        if ($choice -eq '__trust') {
            if ($resolved.IsRepositoryOwned) {
                Write-Host (Get-Content -LiteralPath $resolved.Source -Raw)
                if ((Read-Host 'Trust this exact profile content? [y/N]') -match '^(y|yes)$') {
                    Lamfa-GrantProfileTrust -RepositoryId $Context.Id -ProfilePath $resolved.Source
                    Lamfa-WriteMessage -Level Success -Text 'Trusted (until its content changes).'
                }
            } else { Lamfa-WriteMessage -Level Info -Text 'Built-in profiles are already trusted.' }
            continue
        }
        if ($true) {
            $commandName = $choice
            try {
                $result = Lamfa-InvokeWorkflowCommand -RepositoryPath $Context.Path -RepositoryId $Context.Id `
                    -ResolvedProfile $resolved -CommandName $commandName
                Write-Host $result.StandardOutput
                if ($result.ExitCode -eq 0) { Lamfa-WriteMessage -Level Success -Text "'$commandName' finished (exit 0)." }
                else { Lamfa-WriteMessage -Level Error -Text "'$commandName' failed (exit $($result.ExitCode)). $($result.StandardError)" }
            } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
        }
    }
}

function Show-RecoveryMenu {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][object]$Context)
    if (-not (Test-MenuContext $Context)) { return }
    Lamfa-ShowScreen -Breadcrumb @('Lamfa', 'Backup and recovery')
    Write-Host ''
    Write-Host 'BACKUP AND RECOVERY' -ForegroundColor Cyan
    $guidance = @(Get-GitRecoveryGuidance -Path $Context.Path)
    if ($guidance.Count -eq 0) { Lamfa-WriteMessage -Level Success -Text 'No abnormal Git state detected.' }
    foreach ($item in $guidance) {
        Write-Host ''
        Write-Host " $($item.State)" -ForegroundColor Yellow
        Write-Host "   What happened: $($item.WhatHappened)"
        Write-Host "   Your work is preserved: $($item.WorkPreserved)"
        $item.Steps | ForEach-Object { Write-Host "   - $_" }
    }
    $conflicted = @()
    try { $conflicted = @((Get-GitStatus -Path $Context.Path).Entries | Where-Object Kind -eq 'Conflicted') } catch { $conflicted = @() }
    $undoPlan = $null
    try { $undoPlan = Get-GitUndoPlan -Path $Context.Path } catch { $undoPlan = $null }
    Write-Host ''
    Write-Host '  1. Create Git bundle backup (whole history, one file)'
    if ($undoPlan) { Write-Host "  3. OOPS - undo the last commit safely  ($($undoPlan.WhatHappened))" }
    if ($conflicted.Count -gt 0) { Write-Host "  2. Conflict helper ($($conflicted.Count) conflicted file(s))" }
    Write-Host '  0. Back'
    $recoveryChoice = Lamfa-ReadMenuKey -Breadcrumb @('Lamfa', 'Backup and recovery')
    if ($recoveryChoice -eq '3' -and $undoPlan) {
        Write-Host " What happened   : $($undoPlan.WhatHappened)"
        Write-Host " What undo does  : $($undoPlan.WhatUndoDoes)"
        if ($undoPlan.Warning) { Lamfa-WriteMessage -Level Warning -Text $undoPlan.Warning }
        if ((Read-Host 'Undo now? [y/N]') -match '^(y|yes)$') {
            try {
                $backup = Invoke-GitUndoLastCommit -Path $Context.Path
                Lamfa-WriteMessage -Level Success -Text "Undone. The changes are back as STAGED files; the old state is pinned on '$backup'."
            } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
        }
    }
    if ($recoveryChoice -eq '2' -and $conflicted.Count -gt 0) {
        $config = Lamfa-GetConfiguration
        $editor = [string]$config.preferences.openEditorCommand
        Write-Host ' Conflict markers look like <<<<<<< (yours) ======= (theirs) >>>>>>>.'
        Write-Host ' Keep the correct content, remove the markers, save, then stage the file.'
        foreach ($entry in $conflicted) {
            Write-Host "  - $($entry.Path)"
            if ((Read-Host "    Open in '$editor'? [y/N]") -match '^(y|yes)$') {
                Start-Process $editor -ArgumentList (Join-Path $Context.Path $entry.Path) -ErrorAction SilentlyContinue
            }
        }
        if ((Read-Host 'Stage ALL resolved files now? [y/N]') -match '^(y|yes)$') {
            try { Add-GitStagedFile -Path $Context.Path -Files @($conflicted | ForEach-Object Path)
                  Lamfa-WriteMessage -Level Success -Text 'Staged. Commit to finish the merge.' }
            catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
        }
    }
    if ($recoveryChoice -eq '1') {
        $destination = Read-Host 'Backup destination folder'
        try {
            $backup = New-GitBundleBackup -RepositoryPath $Context.Path -DestinationDirectory $destination
            Lamfa-WriteMessage -Level Success -Text "Backup verified: $($backup.Path) ($([math]::Round($backup.SizeBytes / 1MB, 1)) MB)"
        } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
    }
}

Export-ModuleMember -Function Show-GitStatusMenu, Show-BranchMenu, Show-CommitPushMenu, Invoke-PushFlow, Show-WorkflowMenu, Show-RecoveryMenu, Test-MenuContext

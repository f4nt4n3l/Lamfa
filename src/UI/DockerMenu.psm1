# Docker + Release menus (main-menu categories 7 and 8).
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot 'ConsoleRenderer.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'GitMenu.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Configuration.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/State.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Core/DependencyCheck.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Docker/DockerEnvironment.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Docker/DockerImages.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Docker/DockerContainers.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Docker/DockerCompose.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Docker/DockerRegistry.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Workflows/ProfileLoader.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Workflows/ReleaseTools.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Workflows/ReleaseOrchestrator.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot '../Git/GitTags.psm1') -DisableNameChecking

function Show-DockerMenu {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][object]$Context,
        [Parameter()][bool]$BeginnerMode = $true,
        [Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath)
    )
    $status = Get-DockerStatus
    if (-not $status.CliInstalled) {
        Lamfa-WriteMessage -Level Warning -Text $status.Message
        $install = Lamfa-InstallDependency -Name docker -Reason 'The Docker menu needs the Docker CLI + Desktop.'
        Lamfa-WriteMessage -Level Info -Text $install.Detail
        if (-not $install.Installed) { return }
        $status = Get-DockerStatus
    }
    if (-not $status.DaemonRunning) {
        Lamfa-WriteMessage -Level Warning -Text $status.Message
        return
    }
    $screenShown = $false
    while ($true) {
        if ($screenShown) { Lamfa-PauseForReview }
        $screenShown = $true
        Lamfa-ShowScreen -Breadcrumb @('Lamfa', 'Docker')
        $status = Get-DockerStatus
        Write-Host ''
        Write-Host "DOCKER  (context: $($status.CurrentContext), client $($status.ClientVersion), server $($status.ServerVersion))" -ForegroundColor Cyan
        Write-Host '  1. Images (list)            4. Compose (validate/up/down/logs)'
        Write-Host '  2. Containers (list/logs)   5. Build image from profile'
        Write-Host '  3. Switch context (guarded) 6. Tag + push to registry (guarded)'
        Write-Host '  7. Registry login           0. Back'
        if ($BeginnerMode) { Write-Host '  (Volume deletion and global prune are hidden in Beginner Mode.)' -ForegroundColor DarkGray }
        switch (Lamfa-ReadMenuKey -Breadcrumb @('Lamfa', 'Docker')) {
            '1' { Get-DockerImageList | Format-Table Repository, Tag, Id, Size, Created -AutoSize | Out-Host }
            '2' {
                Get-DockerContainerList -All | Format-Table Name, Image, State, Status -AutoSize | Out-Host
                $name = Read-Host 'Container name for logs (Enter to skip)'
                if ($name) { Get-DockerContainerLog -Container $name | Out-Host -Paging -ErrorAction SilentlyContinue }
            }
            '3' {
                $contexts = Get-DockerContextList
                $contexts | ForEach-Object {
                    $marker = if ($_.Current) { '*' } else { ' ' }
                    Write-Host "  $marker $($_.Name)  ->  $($_.Endpoint)  $(if ($_.LooksRemote) { '(REMOTE)' })"
                }
                $target = Read-Host 'Context to activate (Enter to cancel)'
                if ($target) {
                    $chosen = $contexts | Where-Object Name -eq $target | Select-Object -First 1
                    if (-not $chosen) { Lamfa-WriteMessage -Level Error -Text "No context named '$target'."; continue }
                    Lamfa-WriteMessage -Level Warning -Text "Switching is PERSISTENT: every later docker command targets '$($chosen.Endpoint)'."
                    if ((Read-Host "Type the context name '$target' to confirm") -ceq $target) {
                        $result = Switch-DockerContext -Name $target
                        if ($result.Succeeded) { Lamfa-WriteMessage -Level Success -Text 'Context switched.' }
                        else { Lamfa-WriteMessage -Level Error -Text $result.StandardError }
                    } else { Lamfa-WriteMessage -Level Info -Text 'Cancelled.' }
                }
            }
            '4' {
                if (-not (Test-MenuContext $Context)) { continue }
                $composeFile = Read-Host 'Compose file (relative to repository, e.g. docker/docker-compose.yaml)'
                if (-not $composeFile) { continue }
                $validation = Test-DockerComposeConfiguration -Path $Context.Path -ComposeFile $composeFile
                if (-not $validation.Valid) { Lamfa-WriteMessage -Level Error -Text "Invalid compose file: $($validation.Detail)"; continue }
                Write-Host ('  Services: ' + ((Get-DockerComposeServiceList -Path $Context.Path -ComposeFile $composeFile) -join ', '))
                Write-Host '  1. up (detached)  2. down (containers only, volumes kept)  3. restart  4. logs'
                $action = switch (Lamfa-ReadMenuKey -Breadcrumb @('Lamfa', 'Docker', 'Compose')) { '1' { 'up' } '2' { 'down' } '3' { 'restart' } '4' { 'logs' } default { $null } }
                if ($action) {
                    $result = Invoke-DockerComposeAction -Path $Context.Path -ComposeFile $composeFile -Action $action
                    Write-Host $result.StandardOutput $result.StandardError
                }
            }
            '5' {
                if (-not (Test-MenuContext $Context)) { continue }
                $resolved = Lamfa-GetProfile -RepositoryPath $Context.Path -RepositoryName $Context.Name
                try {
                    $target = Get-DockerRegistryTarget -ResolvedProfile $resolved -Tag 'latest'
                    $docker = $resolved.Data.docker
                    Write-Host " Build: context=$($Context.Path) dockerfile=$($docker.dockerfile) tag=$($target.Image):latest"
                    if ((Read-Host 'Build? [y/N]') -match '^(y|yes)$') {
                        $result = Build-DockerImage -ContextPath $Context.Path -Dockerfile $docker.dockerfile -Tags @("$($target.Image):latest")
                        if ($result.Succeeded) { Lamfa-WriteMessage -Level Success -Text 'Image built.' }
                        else { Lamfa-WriteMessage -Level Error -Text $result.StandardError }
                    }
                } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
            }
            '6' {
                if (-not (Test-MenuContext $Context)) { continue }
                $resolved = Lamfa-GetProfile -RepositoryPath $Context.Path -RepositoryName $Context.Name
                try {
                    $tag = Read-Host 'Tag to push (Enter = latest)'
                    if (-not $tag) { $tag = 'latest' }
                    $target = Get-DockerRegistryTarget -ResolvedProfile $resolved -Tag $tag
                    Lamfa-WriteMessage -Level Warning -Text "EXACT push destination: $($target.Reference)  (context: $($status.CurrentContext))"
                    if ((Read-Host "Type the full reference to confirm") -ceq $target.Reference) {
                        $null = Add-DockerImageTag -SourceImage "$($target.Image):$tag" -TargetImage $target.Reference
                        $result = Push-DockerImage -ImageReference $target.Reference
                        if ($result.Succeeded) { Lamfa-WriteMessage -Level Success -Text "Pushed $($target.Reference)." }
                        else { Lamfa-WriteMessage -Level Error -Text $result.StandardError }
                    } else { Lamfa-WriteMessage -Level Info -Text 'Cancelled - the typed reference did not match.' }
                } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
            }
            '7' {
                $registry = Read-Host 'Registry host (e.g. ghcr.io or registry.company.com)'
                if ($registry) { Start-DockerRegistryLogin -Registry $registry }
            }
            '0' { return }
        }
    }
}

function Show-ReleaseMenu {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][object]$Context,
        [Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath)
    )
    if (-not (Test-MenuContext $Context)) { return }
    $resolved = Lamfa-GetProfile -RepositoryPath $Context.Path -RepositoryName $Context.Name
    $screenShown = $false
    while ($true) {
        if ($screenShown) { Lamfa-PauseForReview }
        $screenShown = $true
        Lamfa-ShowScreen -Breadcrumb @('Lamfa', 'Release')
        Write-Host ''
        Write-Host 'RELEASE' -ForegroundColor Cyan
        $existing = Lamfa-GetReleaseState -RepositoryId $Context.Id
        if ($existing) {
            Lamfa-WriteMessage -Level Warning -Text "A release for version $($existing.version) is IN PROGRESS. Completed steps will not repeat."
            $existing.steps | ForEach-Object { Write-Host ("  [{0,-9}] {1}" -f $_.status, $_.name) }
        }
        Write-Host '  1. Show project version + changelog   4. Create + push release tag (needs gates)'
        Write-Host '  2. Start / resume release record       5. GitHub release for the tag (needs tag)'
        Write-Host '  3. Run release gates (build + test)    6. Docker build + push for release (needs tag)'
        Write-Host '  7. Close release record                0. Back'
        switch (Lamfa-ReadMenuKey -Breadcrumb @('Lamfa', 'Release')) {
            '1' {
                try {
                    $project = $resolved.Data.PSObject.Properties['project']
                    if ($project -and $project.Value -and $project.Value.versionFile) {
                        $version = Lamfa-GetProjectVersion -RepositoryPath $Context.Path -VersionFile $project.Value.versionFile
                        Lamfa-WriteKeyValue -Key 'Version' -Value "$($version.Version)  (from $($version.File))"
                    } else { Lamfa-WriteMessage -Level Info -Text 'The profile defines no versionFile.' }
                    Write-Host (Lamfa-GetChangelogSection -RepositoryPath $Context.Path -Section 'Unreleased')
                } catch { Lamfa-WriteMessage -Level Warning -Text $_.Exception.Message }
            }
            '2' {
                if ($existing) { Lamfa-WriteMessage -Level Info -Text 'Release record already open (shown above).'; continue }
                $version = Read-Host 'Release version (X.Y.Z)'
                if ($version -notmatch '^\d+\.\d+\.\d+$') { Lamfa-WriteMessage -Level Error -Text 'Invalid version.'; continue }
                $null = Lamfa-NewReleaseState -RepositoryId $Context.Id -Version $version `
                    -Steps @('gates', 'tag', 'publish', 'docker')
                Lamfa-WriteMessage -Level Success -Text 'Release record created. Steps track what already ran, so an interrupted release resumes safely.'
            }
            '3' {
                $state = Lamfa-GetReleaseState -RepositoryId $Context.Id
                if (-not $state) { Lamfa-WriteMessage -Level Warning -Text 'Start a release record first (option 2).'; continue }
                if (-not (Lamfa-IsReleaseStepPending -State $state -StepName 'gates')) {
                    Lamfa-WriteMessage -Level Info -Text 'The gates step is already completed for this release.'; continue
                }
                Lamfa-WriteMessage -Level Info -Text "Runs the profile's 'build' and 'test' commands; BOTH must pass."
                try {
                    $gates = Lamfa-InvokeReleaseGateCheck -RepositoryPath $Context.Path -RepositoryId $Context.Id `
                        -ResolvedProfile $resolved
                    $gates.Details | ForEach-Object { Write-Host "   $_" }
                    if ($gates.Passed) {
                        Lamfa-CompleteReleaseStep -State $state -StepName 'gates' -Detail ($gates.Details -join ' | ')
                        Lamfa-WriteMessage -Level Success -Text 'Gates passed.'
                    } else {
                        Lamfa-CompleteReleaseStep -State $state -StepName 'gates' -Status Failed -Detail ($gates.Details -join ' | ')
                        Lamfa-WriteMessage -Level Error -Text 'Gates FAILED - fix the build/tests, then run the gates again.'
                    }
                } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
            }
            '4' {
                $state = Lamfa-GetReleaseState -RepositoryId $Context.Id
                if (-not $state) { Lamfa-WriteMessage -Level Warning -Text 'Start a release record first (option 2).'; continue }
                $gatesStep = @($state.steps) | Where-Object { $_.name -eq 'gates' } | Select-Object -First 1
                if ($gatesStep.status -ne 'Completed') {
                    Lamfa-WriteMessage -Level Warning -Text 'The release gates have not passed yet (option 3). A release never ships unverified.'; continue
                }
                if (-not (Lamfa-IsReleaseStepPending -State $state -StepName 'tag')) {
                    Lamfa-WriteMessage -Level Info -Text 'The tag step is already completed for this release.'; continue
                }
                $tagName = "v$($state.version)"
                Write-Host " Creates annotated tag '$tagName' on HEAD and pushes it to origin."
                if ((Read-Host "Type '$tagName' to confirm") -ceq $tagName) {
                    try {
                        New-GitTag -Path $Context.Path -Name $tagName -Message "Release $($state.version)" -PushToRemote origin
                        Lamfa-CompleteReleaseStep -State $state -StepName 'tag' -Detail $tagName
                        Lamfa-WriteMessage -Level Success -Text "Tag $tagName created and pushed."
                    } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
                }
            }
            '5' {
                $state = Lamfa-GetReleaseState -RepositoryId $Context.Id
                if (-not $state) { Lamfa-WriteMessage -Level Warning -Text 'Start a release record first (option 2).'; continue }
                $tagStep = @($state.steps) | Where-Object { $_.name -eq 'tag' } | Select-Object -First 1
                if ($tagStep.status -ne 'Completed') {
                    Lamfa-WriteMessage -Level Warning -Text 'Create and push the tag first (option 4).'; continue
                }
                if (-not (Lamfa-IsReleaseStepPending -State $state -StepName 'publish')) {
                    Lamfa-WriteMessage -Level Info -Text 'The publish step is already completed for this release.'; continue
                }
                $tagName = "v$($state.version)"
                $notes = ''
                try { $notes = Lamfa-GetChangelogSection -RepositoryPath $Context.Path -Section $state.version }
                catch { try { $notes = Lamfa-GetChangelogSection -RepositoryPath $Context.Path -Section 'Unreleased' } catch { $notes = '' } }
                Write-Host " Creates GitHub release '$tagName' with these notes:"
                Write-Host $notes
                if ((Read-Host 'Publish the GitHub release? [y/N]') -match '^(y|yes)$') {
                    $result = New-GitHubRelease -RepositoryPath $Context.Path -Tag $tagName -Title "Release $($state.version)" -NotesText $notes
                    if ($result.Succeeded) {
                        Lamfa-CompleteReleaseStep -State $state -StepName 'publish' -Detail $result.StandardOutput.Trim()
                        Lamfa-WriteMessage -Level Success -Text $result.StandardOutput.Trim()
                    } else { Lamfa-WriteMessage -Level Error -Text $result.StandardError }
                }
            }
            '6' {
                $state = Lamfa-GetReleaseState -RepositoryId $Context.Id
                if (-not $state) { Lamfa-WriteMessage -Level Warning -Text 'Start a release record first (option 2).'; continue }
                $tagStep = @($state.steps) | Where-Object { $_.name -eq 'tag' } | Select-Object -First 1
                if ($tagStep.status -ne 'Completed') {
                    Lamfa-WriteMessage -Level Warning -Text 'Create and push the tag first (option 4).'; continue
                }
                if (-not (Lamfa-IsReleaseStepPending -State $state -StepName 'docker')) {
                    Lamfa-WriteMessage -Level Info -Text 'The docker step is already completed for this release.'; continue
                }
                try {
                    $target = Get-DockerRegistryTarget -ResolvedProfile $resolved -Tag $state.version
                    Lamfa-WriteMessage -Level Warning -Text "EXACT release push destination: $($target.Reference)"
                    if ((Read-Host 'Type the full reference to confirm') -ceq $target.Reference) {
                        $dockerResult = Lamfa-InvokeDockerReleaseStep -RepositoryPath $Context.Path `
                            -ResolvedProfile $resolved -Version $state.version
                        Lamfa-CompleteReleaseStep -State $state -StepName 'docker' -Detail $dockerResult.Reference
                        Lamfa-WriteMessage -Level Success -Text "Pushed $($dockerResult.Reference)."
                    } else { Lamfa-WriteMessage -Level Info -Text 'Cancelled - the typed reference did not match.' }
                } catch { Lamfa-WriteMessage -Level Error -Text $_.Exception.Message }
            }
            '7' {
                if ((Read-Host 'Close (delete) the release record? [y/N]') -match '^(y|yes)$') {
                    Lamfa-RemoveReleaseState -RepositoryId $Context.Id
                    Lamfa-WriteMessage -Level Success -Text 'Closed.'
                }
            }
            '0' { return }
        }
    }
}

Export-ModuleMember -Function Show-DockerMenu, Show-ReleaseMenu

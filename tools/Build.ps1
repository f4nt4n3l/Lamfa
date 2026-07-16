<#
    Build.ps1 - generates the portable single-file distribution dist/Lamfa.ps1
    from the modular source. The generated file must never be edited
    manually. Also writes dist/checksums.txt.

    Usage:  pwsh -File tools/Build.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory = '',
    [switch]$Package
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'dist' }

$manifest = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'Lamfa.psd1')
$version = $manifest.ModuleVersion

$commit = 'uncommitted'
try {
    $gitOutput = & git -C $repoRoot rev-parse --short HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $gitOutput) { $commit = $gitOutput.Trim() }
} catch {
    # Not a git repository or git unavailable - the placeholder stays.
    $commit = 'uncommitted'
}

# Source modules in dependency order. Add new modules here as phases land.
$moduleFiles = @(
    (Join-Path $repoRoot 'src/Models/CommandResult.psm1'),
    (Join-Path $repoRoot 'src/Models/DependencyStatus.psm1'),
    (Join-Path $repoRoot 'src/Models/RepositoryContext.psm1'),
    (Join-Path $repoRoot 'src/Models/OperationDefinition.psm1'),
    (Join-Path $repoRoot 'src/UI/ConsoleRenderer.psm1'),
    (Join-Path $repoRoot 'src/Core/Platform.psm1'),
    (Join-Path $repoRoot 'src/Core/Logging.psm1'),
    (Join-Path $repoRoot 'src/Core/CommandRunner.psm1'),
    (Join-Path $repoRoot 'src/Core/Configuration.psm1'),
    (Join-Path $repoRoot 'src/Core/DependencyCheck.psm1'),
    (Join-Path $repoRoot 'src/Core/SelfUpdate.psm1'),
    (Join-Path $repoRoot 'src/Core/SecretVault.psm1'),
    (Join-Path $repoRoot 'src/Core/Preconditions.psm1'),
    (Join-Path $repoRoot 'src/Core/Safety.psm1'),
    (Join-Path $repoRoot 'src/Core/OperationEngine.psm1'),
    (Join-Path $repoRoot 'src/Repositories/RepositoryValidation.psm1'),
    (Join-Path $repoRoot 'src/Repositories/RepositoryRegistry.psm1'),
    (Join-Path $repoRoot 'src/Repositories/RepositoryDiscovery.psm1'),
    (Join-Path $repoRoot 'src/Git/GitStatus.psm1'),
    (Join-Path $repoRoot 'src/Git/GitBranches.psm1'),
    (Join-Path $repoRoot 'src/Git/GitRemotes.psm1'),
    (Join-Path $repoRoot 'src/Git/GitCommits.psm1'),
    (Join-Path $repoRoot 'src/Git/GitDiff.psm1'),
    (Join-Path $repoRoot 'src/Git/GitHistory.psm1'),
    (Join-Path $repoRoot 'src/Git/GitStash.psm1'),
    (Join-Path $repoRoot 'src/Git/GitTags.psm1'),
    (Join-Path $repoRoot 'src/Git/GitWorktrees.psm1'),
    (Join-Path $repoRoot 'src/Git/GitRepository.psm1'),
    (Join-Path $repoRoot 'src/Git/GitRecovery.psm1'),
    (Join-Path $repoRoot 'src/Git/GitHunks.psm1'),
    (Join-Path $repoRoot 'src/Git/GitUndo.psm1'),
    (Join-Path $repoRoot 'src/Git/GitInsights.psm1'),
    (Join-Path $repoRoot 'src/Providers/GenericRemote.psm1'),
    (Join-Path $repoRoot 'src/Providers/GitHub/GitHubAuth.psm1'),
    (Join-Path $repoRoot 'src/Providers/GitHub/GitHubRepositories.psm1'),
    (Join-Path $repoRoot 'src/Providers/GitHub/GitHubPullRequests.psm1'),
    (Join-Path $repoRoot 'src/Providers/GitHub/GitHubReviews.psm1'),
    (Join-Path $repoRoot 'src/Providers/GitLab/GitLabAdapter.psm1'),
    (Join-Path $repoRoot 'src/Providers/Gitea/GiteaAdapter.psm1'),
    (Join-Path $repoRoot 'src/Providers/Bitbucket/BitbucketAdapter.psm1'),
    (Join-Path $repoRoot 'src/Workflows/ProfileLoader.psm1'),
    (Join-Path $repoRoot 'src/Workflows/ProjectDetection.psm1'),
    (Join-Path $repoRoot 'src/Workflows/WorkflowEngine.psm1'),
    (Join-Path $repoRoot 'src/Workflows/ReleaseTools.psm1'),
    (Join-Path $repoRoot 'src/Workflows/ReleaseOrchestrator.psm1'),
    (Join-Path $repoRoot 'src/Providers/ProviderAdapter.psm1'),
    (Join-Path $repoRoot 'src/Core/State.psm1'),
    (Join-Path $repoRoot 'src/Docker/DockerEnvironment.psm1'),
    (Join-Path $repoRoot 'src/Docker/DockerImages.psm1'),
    (Join-Path $repoRoot 'src/Docker/DockerContainers.psm1'),
    (Join-Path $repoRoot 'src/Docker/DockerCompose.psm1'),
    (Join-Path $repoRoot 'src/Docker/DockerRegistry.psm1'),
    (Join-Path $repoRoot 'src/UI/Help.psm1'),
    (Join-Path $repoRoot 'src/UI/RepositoryMenu.psm1'),
    (Join-Path $repoRoot 'src/UI/GitMenu.psm1'),
    (Join-Path $repoRoot 'src/UI/GitHubMenu.psm1'),
    (Join-Path $repoRoot 'src/UI/DockerMenu.psm1'),
    (Join-Path $repoRoot 'src/UI/SettingsMenu.psm1'),
    (Join-Path $repoRoot 'src/UI/MainMenu.psm1'),
    (Join-Path $repoRoot 'src/Core/ApiFacade.psm1'),
    (Join-Path $repoRoot 'src/UI/WebUi.psm1'),
    (Join-Path $repoRoot 'src/UI/LamfaCli.psm1'),
    (Join-Path $repoRoot 'Lamfa.psm1')
)

$bodyBuilder = [System.Text.StringBuilder]::new()
foreach ($file in $moduleFiles) {
    if (-not (Test-Path -Path $file)) { throw "Source module not found: $file" }
    $relative = [System.IO.Path]::GetRelativePath($repoRoot, $file)
    [void]$bodyBuilder.AppendLine("# --- begin $relative ---")
    foreach ($line in (Get-Content -Path $file)) {
        # In the single file everything shares one scope: module plumbing lines
        # (exports and intra-package imports) are dropped.
        if ($line -match '^\s*Export-ModuleMember') { continue }
        if ($line -match '^\s*Import-Module\s+-Name\s+\(Join-Path \$PSScriptRoot') { continue }
        [void]$bodyBuilder.AppendLine($line)
    }
    [void]$bodyBuilder.AppendLine("# --- end $relative ---")
}

$entryBody = @'
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host 'Lamfa requires PowerShell 7.6 or later.'
    Write-Host ('Current host: {0} {1}.' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion)
    Write-Host 'Start Lamfa using pwsh.exe.'
    exit 1
}

if ($PSVersionTable.PSVersion -lt [version]'7.6') {
    Write-Host ('Warning: Lamfa targets PowerShell 7.6 LTS; current host is {0}. Continuing.' -f $PSVersionTable.PSVersion)
}

if ($Command -and -not $SelfTest) {
    Lamfa -Command $Command
    exit 0
}

$info = Lamfa-Start -SelfTest:$SelfTest
if ($SelfTest) {
    Write-Host ('SELFTEST OK - Lamfa {0} on PowerShell {1}' -f $info.LamfaVersion, $info.PowerShell)
    exit 0
}
'@

# Reproducible builds: stamp the COMMIT date, not wall-clock time, so
# the same commit always produces byte-identical output.
$timestamp = 'unknown (uncommitted)'
try {
    $commitDate = & git -C $repoRoot log -1 --format=%cI 2>$null
    if ($LASTEXITCODE -eq 0 -and $commitDate) { $timestamp = $commitDate.Trim() }
} catch { $timestamp = 'unknown (uncommitted)' }
$header = @"
<#
    Lamfa $version - generated single-file distribution.

    GENERATED FILE - DO NOT EDIT MANUALLY.
    Source repository modules are authoritative; rebuild with tools/Build.ps1.

    Version   : $version
    Built     : $timestamp
    Commit    : $commit
    Checksum  : see checksums.txt next to this file
#>
[CmdletBinding()]
param([Parameter(Position = 0)][AllowEmptyString()][string]`$Command = '', [switch]`$SelfTest)

`$ErrorActionPreference = 'Stop'
"@

$content = $header + [Environment]::NewLine +
    $bodyBuilder.ToString() + [Environment]::NewLine +
    $entryBody + [Environment]::NewLine

# Validate before writing: a distribution that does not parse must fail the build.
$parseErrors = $null
$parseTokens = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$parseTokens, [ref]$parseErrors)
if ($parseErrors -and $parseErrors.Count -gt 0) {
    foreach ($parseError in $parseErrors) {
        Write-Error -Message ("Generated file parse error at line {0}: {1}" -f $parseError.Extent.StartLineNumber, $parseError.Message) -ErrorAction Continue
    }
    throw 'Build failed: generated distribution does not parse.'
}

if (-not (Test-Path -Path $OutputDirectory)) {
    $null = New-Item -ItemType Directory -Path $OutputDirectory
}
$outputFile = Join-Path $OutputDirectory 'Lamfa.ps1'
Set-Content -Path $outputFile -Value $content -Encoding utf8BOM

$hash = (Get-FileHash -Path $outputFile -Algorithm SHA256).Hash
Set-Content -Path (Join-Path $OutputDirectory 'checksums.txt') -Value "$hash  Lamfa.ps1" -Encoding utf8BOM

Write-Host "Built $outputFile"
Write-Host "  version : $version"
Write-Host "  commit  : $commit"
Write-Host "  sha256  : $hash"

if ($Package) {
    # Portable ZIP: single-file script + docs + config templates + profiles.
    $stage = Join-Path $OutputDirectory "package-stage"
    if (Test-Path $stage) { Remove-Item -Path $stage -Recurse -Force }
    $null = New-Item -ItemType Directory -Path (Join-Path $stage 'docs') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $stage 'config') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $stage 'profiles') -Force
    Copy-Item -Path $outputFile -Destination (Join-Path $stage 'Lamfa.ps1')
    Copy-Item -Path (Join-Path $repoRoot 'tools/Install-Lamfa.ps1') -Destination $stage
    Copy-Item -Path (Join-Path $repoRoot 'README.md') -Destination $stage
    Copy-Item -Path (Join-Path $repoRoot 'CHANGELOG.md') -Destination $stage
    foreach ($doc in @('USER_GUIDE.md', 'RECOVERY_GUIDE.md', 'ADMIN_GUIDE.md', 'PROFILE_SCHEMA.md')) {
        Copy-Item -Path (Join-Path $repoRoot "docs/$doc") -Destination (Join-Path $stage 'docs')
    }
    Copy-Item -Path (Join-Path $repoRoot 'config/*.json') -Destination (Join-Path $stage 'config')
    Copy-Item -Path (Join-Path $repoRoot 'profiles/*.json') -Destination (Join-Path $stage 'profiles')
    $zipPath = Join-Path $OutputDirectory "Lamfa-$version.zip"
    if (Test-Path $zipPath) { Remove-Item -Path $zipPath -Force }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zipPath
    Remove-Item -Path $stage -Recurse -Force
    $zipHash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
    Add-Content -Path (Join-Path $OutputDirectory 'checksums.txt') -Value "$zipHash  Lamfa-$version.zip" -Encoding utf8BOM
    Write-Host "Packaged $zipPath"
    Write-Host "  sha256  : $zipHash"
}

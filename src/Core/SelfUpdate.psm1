# Self-update check. Compares the running version against the latest
# GitHub release of the project (ProjectUri from the manifest). GUIDED only:
# reports + opens the release page; never installs anything by itself.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/Platform.psm1') -DisableNameChecking

function Lamfa-CheckUpdate {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][version]$CurrentVersion,
        [Parameter()][AllowEmptyString()][string]$ProjectUri = '',
        [Parameter()][scriptblock]$Fetcher = { param($Uri) Invoke-RestMethod -Uri $Uri -Headers @{ 'User-Agent' = 'Lamfa' } -TimeoutSec 15 }
    )
    if ([string]::IsNullOrWhiteSpace($ProjectUri)) {
        return [pscustomobject]@{ PSTypeName = 'Lamfa.UpdateCheck'
            UpdateAvailable = $false; Latest = $null; ReleaseUrl = $null
            Detail = 'No project URL configured yet (pre-launch build) - update checks activate with the first public release.' }
    }
    if ($ProjectUri -notmatch 'github\.com/([^/]+)/([^/]+?)/?$') {
        return [pscustomobject]@{ PSTypeName = 'Lamfa.UpdateCheck'
            UpdateAvailable = $false; Latest = $null; ReleaseUrl = $null
            Detail = "Update checks currently support GitHub project URLs only (found: $ProjectUri)." }
    }
    try {
        $release = & $Fetcher "https://api.github.com/repos/$($Matches[1])/$($Matches[2])/releases/latest"
    } catch {
        return [pscustomobject]@{ PSTypeName = 'Lamfa.UpdateCheck'
            UpdateAvailable = $false; Latest = $null; ReleaseUrl = $null
            Detail = "Could not reach GitHub releases: $($_.Exception.Message)" }
    }
    $latestVersion = $null
    if (([string]$release.tag_name) -match '^v?(\d+\.\d+\.\d+)') { $latestVersion = [version]$Matches[1] }
    if ($null -eq $latestVersion) {
        return [pscustomobject]@{ PSTypeName = 'Lamfa.UpdateCheck'
            UpdateAvailable = $false; Latest = $null; ReleaseUrl = $release.html_url
            Detail = "The latest release tag '$($release.tag_name)' is not SemVer - cannot compare." }
    }
    return [pscustomobject]@{
        PSTypeName      = 'Lamfa.UpdateCheck'
        UpdateAvailable = ($latestVersion -gt $CurrentVersion)
        Latest          = $latestVersion.ToString()
        ReleaseUrl      = $release.html_url
        Detail          = if ($latestVersion -gt $CurrentVersion) {
            "Lamfa $latestVersion is available (you run $CurrentVersion). Opening the release page lets you grab the ZIP or Install-Module update."
        } else { "You are up to date ($CurrentVersion)." }
    }
}

Export-ModuleMember -Function Lamfa-CheckUpdate

<#
    Publish-Lamfa.ps1 - stages the module layout and publishes to the
    PowerShell Gallery. Run by the release workflow (gated by repository
    variable PUBLISH_TO_GALLERY=true + PSGALLERY_API_KEY secret), or manually.

    Usage:  pwsh -File tools/Publish-Lamfa.ps1 -ApiKey <key> [-WhatIfPublish]
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ApiKey,
    [switch]$WhatIfPublish
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Path $PSScriptRoot -Parent

$manifest = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'Lamfa.psd1')
$psData = $manifest.PrivateData.PSData
foreach ($required in @('ProjectUri', 'LicenseUri')) {
    if (-not $psData.ContainsKey($required) -or [string]::IsNullOrWhiteSpace([string]$psData[$required])) {
        throw "ValidationError: Lamfa.psd1 PrivateData.PSData.$required must be set before publishing."
    }
}

# Publish-Module needs a folder named after the module containing the payload.
$stage = Join-Path ([System.IO.Path]::GetTempPath()) "Lamfa-publish-$([guid]::NewGuid())/Lamfa"
$null = New-Item -ItemType Directory -Path $stage -Force
Copy-Item -Path (Join-Path $repoRoot 'Lamfa.psd1'), (Join-Path $repoRoot 'Lamfa.psm1'), (Join-Path $repoRoot 'LICENSE') -Destination $stage
Copy-Item -Path (Join-Path $repoRoot 'src') -Destination $stage -Recurse
Copy-Item -Path (Join-Path $repoRoot 'profiles') -Destination $stage -Recurse
Copy-Item -Path (Join-Path $repoRoot 'config') -Destination $stage -Recurse

if ($WhatIfPublish) {
    Write-Host "Staged at $stage - publish skipped (-WhatIfPublish)."
    return
}
Publish-Module -Path $stage -NuGetApiKey $ApiKey
Write-Host "Published Lamfa $($manifest.ModuleVersion) to the PowerShell Gallery."
Remove-Item -Path (Split-Path $stage -Parent) -Recurse -Force

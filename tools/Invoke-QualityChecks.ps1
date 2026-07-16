<#
    Invoke-QualityChecks.ps1 - the local and CI quality gate.

    Runs, in order:
      1. PSScriptAnalyzer over the Lamfa sources (settings: PSScriptAnalyzerSettings.psd1)
      2. Pester over tests/

    Exits non-zero on the first failing gate. legacy/ and dist/ are intentionally
    not analyzed: legacy is a frozen migration reference, dist is generated.

    Usage:  pwsh -File tools/Invoke-QualityChecks.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Path $PSScriptRoot -Parent

foreach ($module in @('PSScriptAnalyzer', 'Pester')) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Error "$module is not installed. Install it with: Install-Module $module -Scope CurrentUser"
    }
}

Write-Host '=== PSScriptAnalyzer ===' -ForegroundColor Cyan
$analyzePaths = @('Lamfa.ps1', 'Lamfa.psm1', 'src', 'tools', 'tests') |
    ForEach-Object { Join-Path $repoRoot $_ } |
    Where-Object { Test-Path $_ }

$findings = @()
foreach ($path in $analyzePaths) {
    $findings += Invoke-ScriptAnalyzer -Path $path -Recurse -Settings (Join-Path $repoRoot 'tools/PSScriptAnalyzerSettings.psd1')
}
if ($findings.Count -gt 0) {
    $findings | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize | Out-String | Write-Host
    Write-Error "PSScriptAnalyzer reported $($findings.Count) finding(s)."
}
Write-Host 'PSScriptAnalyzer: clean' -ForegroundColor Green

Write-Host '=== Pester ===' -ForegroundColor Cyan
$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path $repoRoot 'tests'
$configuration.Run.Exit = $true
$configuration.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $configuration

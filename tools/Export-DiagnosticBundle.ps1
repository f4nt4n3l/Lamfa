<#
    Export-DiagnosticBundle.ps1 - writes a sanitized support bundle:
    tool + dependency versions, redacted configuration, recent redacted logs.
    Never includes repository source files or credentials.

    Usage:  pwsh -File tools/Export-DiagnosticBundle.ps1 [-OutputDirectory <path>]
#>
[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path $env:LOCALAPPDATA 'Lamfa\diagnostics'))

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
Import-Module (Join-Path $repoRoot 'src/Core/Logging.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $repoRoot 'src/Core/Configuration.psm1') -Force -DisableNameChecking

$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$work = Join-Path $OutputDirectory "bundle-$stamp"
$null = New-Item -ItemType Directory -Path $work -Force

# 1. Versions
$manifest = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'Lamfa.psd1')
$versions = [ordered]@{
    repoTool   = $manifest.ModuleVersion
    powerShell = $PSVersionTable.PSVersion.ToString()
    os         = [System.Environment]::OSVersion.VersionString
}
foreach ($tool in @('git', 'gh', 'docker')) {
    $command = Get-Command -Name $tool -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $versions[$tool] = if ($command) { (& $command.Source --version 2>$null | Select-Object -First 1) } else { 'not installed' }
}
Set-Content -Path (Join-Path $work 'versions.json') -Value ($versions | ConvertTo-Json) -Encoding utf8

# 2. Redacted configuration
$configPath = Lamfa-GetConfigPath
if (Test-Path -LiteralPath $configPath) {
    $raw = Get-Content -LiteralPath $configPath -Raw
    Set-Content -Path (Join-Path $work 'config.redacted.json') -Value (Get-RedactedText -Text $raw) -Encoding utf8
}

# 3. Recent redacted logs (already redacted at write time; redact again = belt and braces)
$logDirectory = Lamfa-GetLogDirectory
if (Test-Path -LiteralPath $logDirectory) {
    $recent = Get-ChildItem -Path $logDirectory -Filter 'lamfa-*.log' |
        Sort-Object Name -Descending | Select-Object -First 3
    foreach ($file in $recent) {
        $raw = Get-Content -LiteralPath $file.FullName -Raw
        Set-Content -Path (Join-Path $work $file.Name) -Value (Get-RedactedText -Text $raw) -Encoding utf8
    }
}

$zip = Join-Path $OutputDirectory "lamfa-diagnostics-$stamp.zip"
Compress-Archive -Path (Join-Path $work '*') -DestinationPath $zip -Force
Remove-Item -Path $work -Recurse -Force
Write-Host "Diagnostic bundle: $zip"

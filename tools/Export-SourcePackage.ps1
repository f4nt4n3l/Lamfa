<#
    Export-SourcePackage.ps1 - creates a source ZIP from TRACKED files only,
    via git archive. This is the ONLY sanctioned way to hand the source to
    someone outside Git: compressing the working folder by hand would include
    .git (full history), .claude, dist and other local state.

    Usage:  pwsh -File tools/Export-SourcePackage.ps1 [-OutputPath dist/Lamfa-source.zip]
#>
[CmdletBinding()]
param([Parameter()][string]$OutputPath = '')

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$manifest = Import-PowerShellDataFile -Path (Join-Path $repoRoot 'Lamfa.psd1')
if (-not $OutputPath) { $OutputPath = Join-Path $repoRoot "dist/Lamfa-source-$($manifest.ModuleVersion).zip" }

$directory = Split-Path -Path $OutputPath -Parent
if ($directory -and -not (Test-Path -Path $directory)) { $null = New-Item -ItemType Directory -Path $directory }

& git -C $repoRoot archive --format=zip --output $OutputPath HEAD
if ($LASTEXITCODE -ne 0) { throw "git archive failed with exit code $LASTEXITCODE." }

$hash = (Get-FileHash -Path $OutputPath -Algorithm SHA256).Hash
Write-Host "Source package: $OutputPath"
Write-Host "  sha256 : $hash"

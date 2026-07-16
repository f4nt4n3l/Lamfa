<#
    Test-ReleasePackage.ps1 - verifies that a portable package ZIP contains
    ONLY the files declared in config/release-allowlist.json and nothing
    that must never ship (.git, .claude, legacy artifacts, old project names).

    Optionally scans the text content of every packaged file for private
    strings listed one-per-line in .claude/forbidden-strings.txt (a local,
    gitignored file - the strings themselves must never be committed).

    Exits non-zero on any violation. Run by CI after every package build.

    Usage:  pwsh -File tools/Test-ReleasePackage.ps1 -ZipPath dist/Lamfa-0.1.0.zip
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ZipPath,
    [Parameter()][string]$AllowlistPath = '',
    [Parameter()][string]$ForbiddenStringsPath = ''
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
if (-not $AllowlistPath) { $AllowlistPath = Join-Path $repoRoot 'config/release-allowlist.json' }
if (-not $ForbiddenStringsPath) { $ForbiddenStringsPath = Join-Path $repoRoot '.claude/forbidden-strings.txt' }

if (-not (Test-Path -Path $ZipPath)) { throw "Package not found: $ZipPath" }
$allowlist = Get-Content -Path $AllowlistPath -Raw | ConvertFrom-Json
$forbiddenStrings = @()
if (Test-Path -Path $ForbiddenStringsPath) {
    $forbiddenStrings = @(Get-Content -Path $ForbiddenStringsPath | Where-Object { $_.Trim() })
}

$violations = [System.Collections.Generic.List[string]]::new()
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("lamfa-pkgcheck-" + [guid]::NewGuid())
try {
    Expand-Archive -Path $ZipPath -DestinationPath $stage
    $entries = Get-ChildItem -Path $stage -Recurse -File | ForEach-Object {
        [System.IO.Path]::GetRelativePath($stage, $_.FullName).Replace('\', '/')
    }

    foreach ($entry in $entries) {
        if ($allowlist.allowedFiles -notcontains $entry) {
            $violations.Add("not on the allowlist: $entry")
        }
        foreach ($name in $allowlist.forbiddenNames) {
            if (($entry -split '/') -contains $name -or $entry -like "*$name*.zip" -or $entry -like "$name*") {
                $violations.Add("forbidden name '$name' in: $entry")
            }
        }
    }

    if ($forbiddenStrings.Count -gt 0) {
        foreach ($file in (Get-ChildItem -Path $stage -Recurse -File)) {
            $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $content) { continue }
            foreach ($needle in $forbiddenStrings) {
                if ($content -match [regex]::Escape($needle)) {
                    $relative = [System.IO.Path]::GetRelativePath($stage, $file.FullName)
                    $violations.Add("private string found in: $relative")
                }
            }
        }
    }
} finally {
    Remove-Item -Path $stage -Recurse -Force -ErrorAction SilentlyContinue
}

if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Error -Message $_ -ErrorAction Continue }
    throw "Package check FAILED with $($violations.Count) violation(s): $ZipPath"
}
Write-Host "Package check OK: $ZipPath ($(@($entries).Count) files, all allowlisted)"

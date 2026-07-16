<#
    Install-Lamfa.ps1 - makes the "lamfa" command available in every terminal.

    Writes two launcher shims (lamfa.cmd for cmd/PowerShell, lamfa for
    Git Bash) into %LOCALAPPDATA%\Lamfa\bin and adds that folder to the
    user PATH. No admin rights required. Re-run after moving Lamfa.

    Usage:  pwsh -File tools/Install-Lamfa.ps1        (from the repository)
            pwsh -File Install-Lamfa.ps1              (from the portable ZIP)
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Portable ZIP layout: Lamfa.ps1 sits next to this script.
# Repository layout: this script is in tools/, Lamfa.ps1 one level up.
$entry = Join-Path $PSScriptRoot 'Lamfa.ps1'
if (-not (Test-Path -Path $entry)) {
    $entry = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'Lamfa.ps1'
}
if (-not (Test-Path -Path $entry)) {
    throw "Lamfa.ps1 not found next to this script or one level up. Run from the Lamfa folder."
}
$entry = (Resolve-Path -Path $entry).Path

$bin = Join-Path $env:LOCALAPPDATA 'Lamfa\bin'
$null = New-Item -ItemType Directory -Path $bin -Force

# cmd / PowerShell shim
Set-Content -Path (Join-Path $bin 'lamfa.cmd') -Encoding ascii -Value @"
@echo off
pwsh -NoLogo -File "$entry" %*
"@

# Git Bash / sh shim (forward slashes, no extension)
$entryUnix = $entry.Replace('\', '/')
Set-Content -Path (Join-Path $bin 'lamfa') -Encoding ascii -NoNewline -Value @"
#!/bin/sh
exec pwsh -NoLogo -File '$entryUnix' "`$@"
"@

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $bin) {
    [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $bin), 'User')
    Write-Host "Added to user PATH: $bin"
} else {
    Write-Host "Already on user PATH: $bin"
}
Write-Host "Command 'lamfa' now points to: $entry"
Write-Host "Open a NEW terminal for the PATH change to take effect."

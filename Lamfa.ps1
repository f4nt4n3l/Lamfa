<#
    Lamfa console entry point.

    This file must stay parseable by Windows PowerShell 5.1 so the version guard
    below can print a friendly message instead of a syntax error: ASCII only, no
    PowerShell 7-only syntax at the top level.
#>
[CmdletBinding()]
param(
    # Optional git-style subcommand: Lamfa.ps1 status / push / help ...
    [Parameter(Position = 0)][AllowEmptyString()][string]$Command = '',
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host 'Lamfa requires PowerShell 7.6 or later.'
    Write-Host ('Current host: {0} {1}.' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion)
    Write-Host 'Start Lamfa using pwsh.exe.'
    exit 1
}

if ($PSVersionTable.PSVersion -lt [version]'7.6') {
    Write-Host ('Warning: Lamfa targets PowerShell 7.6 LTS; current host is {0}. Continuing.' -f $PSVersionTable.PSVersion)
}

Import-Module -Name (Join-Path $PSScriptRoot 'Lamfa.psd1') -Force -DisableNameChecking

if ($Command -and -not $SelfTest) {
    Lamfa -Command $Command
    exit 0
}

$info = Lamfa-Start -SelfTest:$SelfTest
if ($SelfTest) {
    # Machine-checkable success signal for CI and the bootstrap tests.
    Write-Host ('SELFTEST OK - Lamfa {0} on PowerShell {1}' -f $info.LamfaVersion, $info.PowerShell)
    exit 0
}

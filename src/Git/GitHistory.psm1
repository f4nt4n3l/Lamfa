# History services. Structured log output via explicit format tokens.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/CommandRunner.psm1') -DisableNameChecking

function Get-GitHistory {
    <#
    .SYNOPSIS
        Recent commits as structured records. -Unpushed limits to commits not on
        any remote; -AllBranches widens beyond HEAD.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][ValidateRange(1, 1000)][int]$Limit = 25,
        [Parameter()][switch]$Unpushed,
        [Parameter()][switch]$AllBranches
    )
    $arguments = @('log', "--max-count=$Limit", '--date=iso-strict', '--format=%h%x1f%an%x1f%ad%x1f%s')
    if ($Unpushed) { $arguments += @('--branches', '--not', '--remotes') }
    elseif ($AllBranches) { $arguments += '--branches' }
    $result = Invoke-ExternalCommand -Executable git -Arguments $arguments -WorkingDirectory $Path -AllowNonZeroExitCode
    if ($result.ExitCode -ne 0) { return @() }   # empty repository has no log
    $commits = foreach ($line in ($result.StandardOutput -split "`r?`n" | Where-Object { $_ })) {
        $parts = $line -split "`u{1f}"
        [pscustomobject]@{
            PSTypeName = 'Lamfa.GitCommit'
            Hash       = $parts[0]
            Author     = $parts[1]
            Date       = $parts[2]
            Subject    = $parts[3]
        }
    }
    return @($commits)
}

function Get-GitHistoryGraph {
    <#
    .SYNOPSIS
        Human-oriented graph text for display only - never parsed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][ValidateRange(1, 500)][int]$Limit = 30
    )
    $result = Invoke-ExternalCommand -Executable git `
        -Arguments @('log', '--graph', '--oneline', '--decorate', "--max-count=$Limit", '--branches') `
        -WorkingDirectory $Path -AllowNonZeroExitCode
    return $result.StandardOutput
}

Export-ModuleMember -Function Get-GitHistory, Get-GitHistoryGraph
